#!/usr/bin/env pwsh
# Shared helpers for EI Graphics scope resolver scripts.
# Dot-source this file; do not execute it directly.

Set-StrictMode -Version Latest

. "$PSScriptRoot/../../../ei-workflow-state/scripts/helpers/EiWorkflowState.ps1"

$script:EiScopeSchemaVersion = '1.0.0'

function Get-EiScopePolicy {
    [CmdletBinding()]
    param([string]$PolicyPath = (Join-Path $PSScriptRoot '..' '..' 'references' 'scope-policy.json'))

    if (-not (Test-Path -LiteralPath $PolicyPath)) {
        throw "Scope policy not found at '$PolicyPath'."
    }

    Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
}

function Get-EiScopeRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Policy,
        [Parameter(Mandatory)][string]$Code
    )

    $rule = @($Policy.rules) | Where-Object { $_.code -eq $Code } | Select-Object -First 1
    if ($null -eq $rule) {
        throw "Scope policy does not declare rule '$Code'."
    }

    $rule
}

function ConvertTo-EiArray {
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$Value)

    # Pipeline input is deliberately not supported: it re-wraps each element and hides the shape of JSON arrays.
    if ($null -eq $Value) { return @() }

    @($Value)
}

function Get-EiJsonValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($null -eq $InputObject.PSObject.Properties[$Name]) { return $Default }

    $value = $InputObject.$Name
    if ($null -eq $value) { return $Default }

    $value
}

function Get-EiPathSegment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    @(($Path -replace '\\', '/').Split('/') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne '.' })
}

function Test-EiPathInArea {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Area
    )

    $pathSegments = @(Get-EiPathSegment -Path $Path)
    $areaSegments = @(Get-EiPathSegment -Path $Area)

    if ($areaSegments.Count -eq 0 -or $pathSegments.Count -lt $areaSegments.Count) { return $false }

    for ($i = 0; $i -lt $areaSegments.Count; $i++) {
        if ($pathSegments[$i] -ne $areaSegments[$i]) { return $false }
    }

    return $true
}

function Test-EiPathOwnedByDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DependencyName
    )

    if ([string]::IsNullOrWhiteSpace($DependencyName)) { return $false }

    # A dependency owns a path when its name appears as a whole path segment; substring matching would be guesswork.
    foreach ($segment in @(Get-EiPathSegment -Path $Path)) {
        if ($segment -eq $DependencyName) { return $true }
        if ([System.IO.Path]::GetFileNameWithoutExtension($segment) -eq $DependencyName) { return $true }
    }

    return $false
}

function Test-EiProposedPathPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RepositoryRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$ChangeIntent
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot) -or -not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        return $false
    }

    $full = Join-Path $RepositoryRoot $Path

    if ($ChangeIntent -eq 'add') {
        $parent = Split-Path -Parent $full
        if ([string]::IsNullOrWhiteSpace($parent)) { return $false }
        return (Test-Path -LiteralPath $parent -PathType Container)
    }

    Test-Path -LiteralPath $full -PathType Leaf
}

function New-EiScopeFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Policy,
        [Parameter(Mandatory)][string]$Code,
        [AllowEmptyString()][string]$Detail = ''
    )

    $rule = Get-EiScopeRule -Policy $Policy -Code $Code
    $question = if ([string]::IsNullOrWhiteSpace($Detail)) { $rule.question } else { "$Detail $($rule.question)" }

    [ordered]@{
        code     = $Code
        question = $question
        blocking = [bool]$rule.blocking
    }
}

function Resolve-EiScopeStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Unresolved)

    $entries = @($Unresolved)
    if ($entries.Count -eq 0) { return 'resolved' }
    if (@($entries | Where-Object { $_.blocking }).Count -gt 0) { return 'blocked' }

    'needs-review'
}
