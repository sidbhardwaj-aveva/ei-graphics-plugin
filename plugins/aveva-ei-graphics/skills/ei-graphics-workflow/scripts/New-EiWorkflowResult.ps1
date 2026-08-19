#!/usr/bin/env pwsh
<#
.SYNOPSIS
Build, validate and persist the ei-graphics-workflow result contract.

.DESCRIPTION
The thin entry agent communicates this contract and nothing else. The contract is derived from
`workflow-state.json`, validated against `workflow-result.schema.json`, and written through the
`ei-workflow-state` skill so that every returned result is also recoverable state.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Result holds the contract).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][string]$Summary,
    [Parameter(Mandatory)][string]$NextAction,
    [ValidateSet('', 'completed', 'awaiting-approval', 'blocked', 'failed')][string]$Status = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'ei-workflow-state' 'scripts')))
. "$stateScripts/helpers/EiWorkflowState.ps1"

$result = New-EiResult

$stateValidation = & "$stateScripts/Validate-EiWorkflowState.ps1" -StateDir $StateDir -Json | ConvertFrom-Json
if ($stateValidation.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "Cannot build a result contract from unusable state: $(@($stateValidation.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$state = Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Status)) {
    if ($state.status -eq 'in-progress') {
        $result = Add-EiError -Result $result -Code 'EIWF-RESULT-STATUS' -Message 'The workflow is still in-progress. Supply an explicit -Status; a run may not return without a terminal contract status.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $Status = $state.status
}

$registry = Get-EiArtifactRegistry
$artifacts = foreach ($stage in @($state.stages)) {
    if ([string]::IsNullOrWhiteSpace([string]$stage.artifact)) { continue }

    $entry = Get-EiArtifactEntry -Name $stage.artifact -Registry $registry
    if ($null -eq $entry) { continue }

    $fileName = Resolve-EiArtifactFileName -Entry $entry -Version 1
    $artifactPath = Join-Path $StateDir $fileName

    [ordered]@{
        name   = $entry.name
        path   = (Join-Path $state.stateDir $fileName) -replace '\\', '/'
        exists = [bool](Test-Path -LiteralPath $artifactPath)
    }
}

$uniqueArtifacts = @()
$seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($artifact in @($artifacts)) {
    if ($seen.Add($artifact.name)) { $uniqueArtifacts += $artifact }
}

$gates = foreach ($stage in @($state.stages)) {
    if ([string]::IsNullOrWhiteSpace([string]$stage.gate)) { continue }

    [ordered]@{
        id     = $stage.gate
        stage  = $stage.id
        result = $stage.gateResult
        detail = $stage.blockReason
    }
}

$contract = [ordered]@{
    schemaVersion = '1.0.0'
    workflow      = 'ei-graphics-workflow'
    path          = $state.path
    storyId       = $state.storyId
    status        = $Status
    stage         = $state.stage
    stateDir      = $state.stateDir
    summary       = $Summary
    artifacts     = @($uniqueArtifacts)
    gates         = @($gates)
    blocks        = @($state.blocks)
    nextAction    = $NextAction
}

$contractJson = $contract | ConvertTo-Json -Depth 20

$writeResult = & "$stateScripts/Write-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'workflow-result' -Content $contractJson -Json | ConvertFrom-Json
if ($writeResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-RESULT-INVALID' -Message "Result contract could not be persisted: $(@($writeResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'ResultPath' -Value $writeResult.Details.Path
$result = Set-EiDetail -Result $result -Name 'Result' -Value ($contractJson | ConvertFrom-Json)

Exit-EiResult -Result $result -Json:$Json
