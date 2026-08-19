#!/usr/bin/env pwsh
# Shared helpers for EI Graphics scope validator scripts.
# Dot-source this file; do not execute it directly.

Set-StrictMode -Version Latest

. "$PSScriptRoot/../../../ei-scope-resolver/scripts/helpers/EiScopeResolver.ps1"
. "$PSScriptRoot/../../../ei-graphics-workflow/scripts/helpers/EiScopeHash.ps1"

$script:EiValidationSchemaVersion = '1.0.0'
$script:EiScopeChangeSchemaVersion = '1.0.0'

function Get-EiApprovalPolicy {
    [CmdletBinding()]
    param([string]$PolicyPath = (Join-Path $PSScriptRoot '..' '..' 'references' 'approval-policy.json'))

    if (-not (Test-Path -LiteralPath $PolicyPath)) {
        throw "Approval policy not found at '$PolicyPath'."
    }

    Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
}

function New-EiValidationFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Policy,
        [Parameter(Mandatory)][string]$Code,
        [AllowNull()][string]$Target = $null,
        [AllowEmptyString()][string]$Detail = ''
    )

    $rule = @($Policy.rules) | Where-Object { $_.code -eq $Code } | Select-Object -First 1
    if ($null -eq $rule) {
        throw "Approval policy does not declare rule '$Code'."
    }

    [ordered]@{
        code     = $Code
        severity = [string]$rule.severity
        target   = if ([string]::IsNullOrWhiteSpace($Target)) { $null } else { $Target }
        message  = if ([string]::IsNullOrWhiteSpace($Detail)) { [string]$rule.message } else { "$Detail $($rule.message)" }
    }
}

function ConvertTo-EiNormalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    (@(Get-EiPathSegment -Path $Path) -join '/')
}

function Get-EiImplementationArea {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [int]$Depth = 2
    )

    $segments = @(Get-EiPathSegment -Path $Path)
    if ($segments.Count -le 1) { return '' }

    # The file name is never part of an area, so the directory segments are what identify it.
    $directory = @($segments[0..($segments.Count - 2)])
    $take = [System.Math]::Min($Depth, $directory.Count)

    (@($directory[0..($take - 1)]) -join '/')
}

function Test-EiPathAllowedByPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][PSCustomObject]$Policy
    )

    foreach ($prefix in @($Policy.drift.allowedPathPrefixes)) {
        if (Test-EiPathInArea -Path $Path -Area ([string]$prefix)) { return $true }
    }

    return $false
}

function Test-EiTestNamesPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$TestTarget,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension((ConvertTo-EiNormalPath -Path $Path))
    if ([string]::IsNullOrWhiteSpace($stem)) { return $false }

    $target = ConvertTo-EiNormalPath -Path $TestTarget

    # A test proves a file when it names it; anything looser would be the model guessing at coverage.
    return $target.IndexOf($stem, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function New-EiValidationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('scope-analysis', 'scope-validation')][string]$Gate,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$StoryId,
        [Parameter(Mandatory)][AllowNull()]$ApprovedScopeVersion,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$ContentHash,
        [Parameter(Mandatory)][string]$Summary,
        [Parameter(Mandatory)][AllowNull()]$Findings,
        [Parameter(Mandatory)][AllowNull()]$Paths
    )

    $findingList = @(ConvertTo-EiArray $Findings)
    $verdict = if (@($findingList | Where-Object { $_.severity -eq 'blocking' }).Count -gt 0) { 'block' } else { 'pass' }

    [ordered]@{
        schemaVersion        = $script:EiValidationSchemaVersion
        validator            = 'ei-scope-validator'
        gate                 = $Gate
        stage                = $Stage
        storyId              = $StoryId
        generatedAt          = Get-EiUtcTimestamp
        verdict              = $verdict
        approvedScopeVersion = if ($null -eq $ApprovedScopeVersion) { $null } else { [int]$ApprovedScopeVersion }
        contentHash          = if ([string]::IsNullOrWhiteSpace([string]$ContentHash)) { $null } else { [string]$ContentHash }
        summary              = $Summary
        findings             = $findingList
        paths                = @(ConvertTo-EiArray $Paths)
    }
}

function Save-EiValidationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateDir,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Evidence
    )

    $json = $Evidence | ConvertTo-Json -Depth 20

    $writeResult = & "$PSScriptRoot/../../../ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'validation' -Content $json -Json | ConvertFrom-Json

    if ($writeResult.Status -ne 'Valid') {
        throw "Validation evidence could not be persisted: $(@($writeResult.Errors) -join '; ')"
    }

    # validation.json is overwritten by the next validating stage, so each stage also keeps its own copy.
    $evidenceDir = Join-Path $StateDir 'validation'
    if (-not (Test-Path -LiteralPath $evidenceDir -PathType Container)) {
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
    }

    $stageCopy = Join-Path $evidenceDir ("$($Evidence.stage).json")
    Set-Content -LiteralPath $stageCopy -Value $json -Encoding utf8

    [PSCustomObject]@{
        Path      = [string]$writeResult.Details.Path
        StagePath = $stageCopy
    }
}

function Get-EiScopeChangeRequestVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateDir)

    if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) { return @() }

    $versions = foreach ($file in @(Get-ChildItem -LiteralPath $StateDir -Filter 'scope-change-request.v*.json' -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -match '^scope-change-request\.v(\d+)\.json$') { [int]$Matches[1] }
    }

    if ($null -eq $versions) { return @() }

    @(@($versions) | Sort-Object)
}
