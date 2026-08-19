#!/usr/bin/env pwsh
# Canonical serialisation and content hashing for the EI Graphics ApprovedScope seal.
# Dot-source this file; do not execute it directly.

Set-StrictMode -Version Latest

. "$PSScriptRoot/../../../ei-workflow-state/scripts/helpers/EiWorkflowState.ps1"

$script:EiApprovedScopeSchemaVersion = '1.0.0'
$script:EiScopeCanonicalization = 'ei-scope-canonical-v1'
$script:EiScopeHashAlgorithm = 'sha256'
$script:EiScopeHashPattern = '^sha256:[0-9a-f]{64}$'

# Timestamps make an otherwise identical scope hash differently, so they are the one thing the seal ignores.
$script:EiScopeHashExcludedFields = @('generatedAt')

function ConvertTo-EiCanonicalJsonString {
    [CmdletBinding()]
    param([Parameter(Position = 0, Mandatory)][AllowEmptyString()][string]$Value)

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')

    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character

        switch ($code) {
            8 { [void]$builder.Append('\b'); break }
            9 { [void]$builder.Append('\t'); break }
            10 { [void]$builder.Append('\n'); break }
            12 { [void]$builder.Append('\f'); break }
            13 { [void]$builder.Append('\r'); break }
            34 { [void]$builder.Append('\"'); break }
            92 { [void]$builder.Append('\\'); break }
            default {
                if ($code -lt 32) { [void]$builder.Append(('\u{0:x4}' -f $code)) }
                else { [void]$builder.Append($character) }
            }
        }
    }

    [void]$builder.Append('"')
    $builder.ToString()
}

function ConvertTo-EiCanonicalNumber {
    [CmdletBinding()]
    param([Parameter(Position = 0, Mandatory)]$Value)

    $number = [double]$Value

    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw 'A scope cannot be hashed while it contains a non-finite number.'
    }

    if ($number -eq [System.Math]::Floor($number) -and [System.Math]::Abs($number) -lt 1e15) {
        return ([long]$number).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    $number.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-EiCanonicalJson {
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return 'null' }
    if ($InputObject -is [string]) { return ConvertTo-EiCanonicalJsonString $InputObject }
    if ($InputObject -is [bool]) { return $(if ($InputObject) { 'true' } else { 'false' }) }

    if ($InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [double] -or
        $InputObject -is [decimal] -or $InputObject -is [single] -or $InputObject -is [byte]) {
        return ConvertTo-EiCanonicalNumber $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $keys = [string[]]@($InputObject.Keys)
        [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)

        $members = foreach ($key in $keys) {
            '{0}:{1}' -f (ConvertTo-EiCanonicalJsonString $key), (ConvertTo-EiCanonicalJson $InputObject[$key])
        }

        return '{' + (@($members) -join ',') + '}'
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        # Every array in a scope is a set, so element order carries no authorisation meaning and is normalised away.
        $elements = [string[]]@(@($InputObject) | ForEach-Object { ConvertTo-EiCanonicalJson $_ })
        [System.Array]::Sort($elements, [System.StringComparer]::Ordinal)
        return '[' + (@($elements) -join ',') + ']'
    }

    $properties = @($InputObject.PSObject.Properties)
    $names = [string[]]@($properties | ForEach-Object { $_.Name })
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)

    $members = foreach ($name in $names) {
        '{0}:{1}' -f (ConvertTo-EiCanonicalJsonString $name), (ConvertTo-EiCanonicalJson $InputObject.$name)
    }

    '{' + (@($members) -join ',') + '}'
}

function Get-EiCanonicalScopeText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Scope)

    if ($null -eq $Scope) {
        throw 'There is no scope to canonicalise.'
    }

    $retained = [ordered]@{}

    if ($Scope -is [System.Collections.IDictionary]) {
        foreach ($key in @($Scope.Keys)) {
            if ($script:EiScopeHashExcludedFields -contains [string]$key) { continue }
            $retained[[string]$key] = $Scope[$key]
        }
    }
    else {
        foreach ($property in @($Scope.PSObject.Properties)) {
            if ($script:EiScopeHashExcludedFields -contains $property.Name) { continue }
            $retained[$property.Name] = $property.Value
        }
    }

    if ($retained.Count -eq 0) {
        throw 'There is no hashable scope content once the excluded fields are removed.'
    }

    ConvertTo-EiCanonicalJson $retained
}

function Get-EiScopeContentHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Scope)

    $canonical = Get-EiCanonicalScopeText -Scope $Scope
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash($bytes) }
    finally { $sha.Dispose() }

    'sha256:' + ((@($digest) | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-EiApprovedScopeVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateDir)

    if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) { return @() }

    $versions = foreach ($file in @(Get-ChildItem -LiteralPath $StateDir -Filter 'approved-scope.v*.json' -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -match '^approved-scope\.v(\d+)\.json$') { [int]$Matches[1] }
    }

    # An empty foreach yields $null, and @($null) is a one-element array, so the empty case is returned explicitly.
    if ($null -eq $versions) { return @() }

    @(@($versions) | Sort-Object)
}
