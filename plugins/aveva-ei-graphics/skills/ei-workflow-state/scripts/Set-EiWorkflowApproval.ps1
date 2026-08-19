#!/usr/bin/env pwsh
<#
.SYNOPSIS
Move an EI Graphics workflow into or out of `awaiting-approval`.

.DESCRIPTION
`awaiting-approval` is a real pause, not a label: while it is set, `Set-EiWorkflowStage.ps1` refuses
to start any stage, so nothing advances until a human decision is recorded. This script is the only
supported way to enter and leave that pause, so `workflow-state.json` is still never hand-edited.

The pause may only be requested for a stage whose gate is `human-approval`, and it is granted only
from the pause itself. Granting the pause records that a decision was taken; it is not the decision.
The decision lives in the sealed ApprovedScope for an approval, or in a block record for a refusal.

Failed validation never mutates state: the candidate is validated in a temporary file first.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][AllowEmptyString()][string]$StageId,
    [Parameter(Mandatory)][ValidateSet('request', 'grant')][string]$Action,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiWorkflowState.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'StageId' -Value $StageId
$result = Set-EiDetail -Result $result -Name 'Action' -Value $Action

$statePath = Join-Path $StateDir 'workflow-state.json'

$stateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $statePath -Json | ConvertFrom-Json
if ($stateValidation.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "Cannot change the approval checkpoint against unusable state: $(@($stateValidation.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$stage = @($state.stages) | Where-Object { $_.id -eq $StageId } | Select-Object -First 1

if ($null -eq $stage) {
    $result = Add-EiError -Result $result -Code 'EIWF-STAGE-UNKNOWN' -Message "Stage '$StageId' is not part of the '$($state.path)' lifecycle."
    Exit-EiResult -Result $result -Json:$Json
}

if ($stage.gate -ne 'human-approval') {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-STAGE' -Message "Stage '$StageId' owns the '$($stage.gate)' gate, not 'human-approval'. Only a human-approval stage can pause a run for a decision."
    Exit-EiResult -Result $result -Json:$Json
}

if ($stage.status -notin @('pending', 'running')) {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-STAGE' -Message "Stage '$StageId' is '$($stage.status)'; a decision can only be pending on a stage that has not finished."
    Exit-EiResult -Result $result -Json:$Json
}

$expected = if ($Action -eq 'request') { 'in-progress' } else { 'awaiting-approval' }

if ($state.status -ne $expected) {
    $message = if ($Action -eq 'request') {
        "Workflow status is '$($state.status)'; only an in-progress run can be paused for approval."
    }
    else {
        "Workflow status is '$($state.status)'; there is no approval pending to grant."
    }

    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-STATE' -Message $message
    Exit-EiResult -Result $result -Json:$Json
}

$state.status = if ($Action -eq 'request') { 'awaiting-approval' } else { 'in-progress' }
$state.updatedAt = Get-EiUtcTimestamp

$candidateJson = $state | ConvertTo-Json -Depth 20

$schemaCheck = Test-EiJsonAgainstSchema -Content $candidateJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'workflow-state.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-SCHEMA' -Message "The '$Action' checkpoint would produce schema-invalid state: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$candidatePath = Join-Path ([System.IO.Path]::GetTempPath()) ("ei-workflow-approval-candidate-$([guid]::NewGuid().ToString('N')).json")
Set-Content -LiteralPath $candidatePath -Value $candidateJson -Encoding utf8

try {
    $candidateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $candidatePath -Json | ConvertFrom-Json

    if ($candidateValidation.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-STATE' -Message "The '$Action' checkpoint would produce invalid state: $(@($candidateValidation.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }
}
finally {
    Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
}

Set-Content -LiteralPath $statePath -Value $candidateJson -Encoding utf8

$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $state.status
$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value $stage.status
$result = Set-EiDetail -Result $result -Name 'UpdatedAt' -Value $state.updatedAt

Exit-EiResult -Result $result -Json:$Json
