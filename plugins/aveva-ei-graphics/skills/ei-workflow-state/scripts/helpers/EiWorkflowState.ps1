#!/usr/bin/env pwsh
# Shared helpers for EI Graphics workflow state scripts.
# Dot-source this file; do not execute it directly.

Set-StrictMode -Version Latest

$script:EiStoryIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
$script:EiStateSchemaVersion = '1.0.0'

function New-EiResult {
    [CmdletBinding()]
    param()

    [PSCustomObject]@{
        Status   = 'Valid'
        Errors   = @()
        Warnings = @()
        Details  = [PSCustomObject]@{}
    }
}

function Add-EiError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Result,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )

    $Result.Status = 'Invalid'
    $Result.Errors = @($Result.Errors) + @("${Code}: $Message")
    $Result
}

function Add-EiWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Result,
        [Parameter(Mandatory)][string]$Message
    )

    $Result.Warnings = @($Result.Warnings) + @($Message)
    $Result
}

function Set-EiDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Result,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()]$Value
    )

    $Result.Details | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $Result
}

function Exit-EiResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Result,
        [switch]$Json
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 20
    }
    else {
        $Result
    }

    if ($Result.Status -eq 'Valid') { exit 0 }
    exit 1
}

function Test-EiStoryId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$StoryId)

    # Story ids become directory names; anything outside this set is rejected to prevent traversal.
    return [bool]($StoryId -match $script:EiStoryIdPattern)
}

function Resolve-EiStateDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoryId,
        [string]$WorkspaceRoot = (Get-Location).Path,
        [string]$TrackingDir = '.copilottracking'
    )

    Join-Path -Path $WorkspaceRoot -ChildPath (Join-Path $TrackingDir (Join-Path 'ei-graphics' $StoryId))
}

function Get-EiSchemaRoot {
    [CmdletBinding()]
    param()

    # Use ScriptBlock.File so this resolves to the helper's own directory regardless of PS version or dot-source caller.
    $helperDir = Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File
    (Resolve-Path (Join-Path $helperDir '..' '..' 'schemas')).Path
}

function Get-EiArtifactRegistry {
    [CmdletBinding()]
    param([string]$RegistryPath = (Join-Path (Get-EiSchemaRoot) 'artifact-registry.json'))

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        throw "Artifact registry not found at '$RegistryPath'."
    }

    Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
}

function Get-EiArtifactEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [PSCustomObject]$Registry = (Get-EiArtifactRegistry)
    )

    @($Registry.artifacts) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Resolve-EiArtifactFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Entry,
        [int]$Version = 1
    )

    if ($Entry.versioned) {
        return $Entry.file.Replace('{version}', [string]$Version)
    }

    $Entry.file
}

function Test-EiJsonAgainstSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        return [PSCustomObject]@{ IsValid = $false; Errors = @("Schema file not found at '$SchemaPath'.") }
    }

    $schema = Get-Content -LiteralPath $SchemaPath -Raw

    try {
        $isValid = Test-Json -Json $Content -Schema $schema -ErrorAction Stop
        return [PSCustomObject]@{ IsValid = [bool]$isValid; Errors = @() }
    }
    catch {
        return [PSCustomObject]@{ IsValid = $false; Errors = @($_.Exception.Message) }
    }
}

function Get-EiUtcTimestamp {
    [CmdletBinding()]
    param()

    (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
