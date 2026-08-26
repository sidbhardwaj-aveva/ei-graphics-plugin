#!/usr/bin/env pwsh
<#
.SYNOPSIS
Apply a deterministic stage transition to an EI Graphics workflow state file.

.DESCRIPTION
`ei-graphics-workflow` must mark a stage running, record its gate result, and advance it without
ever hand-editing `workflow-state.json`. This script is the only supported mutation path, so the
transition rules already implied by the state schema, the lifecycle definitions and
`Validate-EiWorkflowState.ps1` are enforced identically on every run.

Failed validation never mutates state: the candidate state is validated in a temporary file and is
only committed once it satisfies both the schema and the state validator.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][AllowEmptyString()][string]$StageId,
    [Parameter(Mandatory)][ValidateSet('start', 'complete', 'block')][string]$Action,
    [ValidateSet('', 'pass', 'block')][string]$GateResult = '',
    [AllowEmptyString()][string]$BlockCode = '',
    [AllowEmptyString()][string]$BlockMessage = '',
    [AllowEmptyString()][string]$Remediation = '',
    [int]$ArtifactVersion = 1,
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
$result = Set-EiDetail -Result $result -Name 'StatePath' -Value $statePath

$stateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $statePath -Json | ConvertFrom-Json
if ($stateValidation.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "Cannot transition a stage against unusable state: $(@($stateValidation.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$stages = @($state.stages)

$stageIndex = -1
for ($i = 0; $i -lt $stages.Count; $i++) {
    if ($stages[$i].id -eq $StageId) { $stageIndex = $i; break }
}

if ($stageIndex -lt 0) {
    $result = Add-EiError -Result $result -Code 'EIWF-STAGE-UNKNOWN' -Message "Stage '$StageId' is not part of the '$($state.path)' lifecycle."
    Exit-EiResult -Result $result -Json:$Json
}

$stage = $stages[$stageIndex]
$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value $stage.status

if ($state.status -in @('completed', 'failed')) {
    $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "Workflow status is '$($state.status)'. A terminal run cannot transition stage '$StageId'."
    Exit-EiResult -Result $result -Json:$Json
}

$timestamp = Get-EiUtcTimestamp

switch ($Action) {
    'start' {
        if ($state.status -ne 'in-progress') {
            $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "Workflow status is '$($state.status)'. Clear it through the owning checkpoint before starting stage '$StageId'."
            Exit-EiResult -Result $result -Json:$Json
        }

        if ($stage.status -notin @('pending', 'running')) {
            $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "Stage '$StageId' is '$($stage.status)'; only a pending or running stage can be started."
            Exit-EiResult -Result $result -Json:$Json
        }

        for ($i = 0; $i -lt $stageIndex; $i++) {
            if ($stages[$i].status -notin @('complete', 'skipped')) {
                $result = Add-EiError -Result $result -Code 'EIWF-STAGE-ORDER' -Message "Stage '$StageId' cannot start while earlier stage '$($stages[$i].id)' is '$($stages[$i].status)'."
                Exit-EiResult -Result $result -Json:$Json
            }
        }

        # Starting a stage that is already running is re-entry after an interruption, so the first attempt's
        # startedAt stands and no gate is skipped; failing here would strand the run, since state is never hand-edited.
        $resumed = $stage.status -eq 'running'
        if ($resumed) {
            $result = Add-EiWarning -Result $result -Message "Stage '$StageId' was already running; re-entered without resetting startedAt."
        }
        else {
            $stage.startedAt = $timestamp
        }

        $stage.status = 'running'
        $stage.blockReason = $null
        $state.stage = $StageId
        $result = Set-EiDetail -Result $result -Name 'Resumed' -Value $resumed
    }

    'complete' {
        if ($stage.status -ne 'running') {
            $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "Stage '$StageId' is '$($stage.status)'; only a running stage can be completed."
            Exit-EiResult -Result $result -Json:$Json
        }

        $hasGate = -not [string]::IsNullOrWhiteSpace([string]$stage.gate)

        if ($hasGate) {
            if ([string]::IsNullOrWhiteSpace($GateResult)) {
                $result = Add-EiError -Result $result -Code 'EIWF-GATE-REQUIRED' -Message "Stage '$StageId' owns the '$($stage.gate)' gate. Supply -GateResult; a gate result is never assumed."
                Exit-EiResult -Result $result -Json:$Json
            }

            if ($GateResult -ne 'pass') {
                $result = Add-EiError -Result $result -Code 'EIWF-GATE-INVALID' -Message "Gate '$($stage.gate)' returned '$GateResult'. Only a passing gate completes a stage; use -Action block."
                Exit-EiResult -Result $result -Json:$Json
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($GateResult)) {
            $result = Add-EiError -Result $result -Code 'EIWF-GATE-INVALID' -Message "Stage '$StageId' has no gate, so -GateResult cannot be recorded against it."
            Exit-EiResult -Result $result -Json:$Json
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$stage.artifact)) {
            $readOutput = & "$PSScriptRoot/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name $stage.artifact -Version $ArtifactVersion -Json
            $read = $readOutput | ConvertFrom-Json

            if ($read.Status -ne 'Valid') {
                $readError = [string]@($read.Errors)[0]
                $parts = $readError -split ':\s*', 2
                $code = if ($parts.Count -eq 2) { $parts[0] } else { 'EIWF-ARTIFACT-MISSING' }
                $message = if ($parts.Count -eq 2) { $parts[1] } else { $readError }

                $result = Add-EiError -Result $result -Code $code -Message "Stage '$StageId' cannot complete: $message"
                Exit-EiResult -Result $result -Json:$Json
            }

            $result = Set-EiDetail -Result $result -Name 'Artifact' -Value $stage.artifact
        }

        $stage.status = 'complete'
        $stage.gateResult = if ($hasGate) { 'pass' } else { 'not-run' }
        $stage.completedAt = $timestamp
        $stage.blockReason = $null

        $nextStage = @($stages | Where-Object { $_.status -in @('pending', 'running') } | Select-Object -First 1)
        $state.stage = if ($nextStage.Count -gt 0) { $nextStage[0].id } else { $StageId }
    }

    'block' {
        if ($stage.status -notin @('pending', 'running')) {
            $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "Stage '$StageId' is '$($stage.status)'; only a pending or running stage can be blocked."
            Exit-EiResult -Result $result -Json:$Json
        }

        if ([string]::IsNullOrWhiteSpace($BlockCode) -or [string]::IsNullOrWhiteSpace($BlockMessage)) {
            $result = Add-EiError -Result $result -Code 'EIWF-BLOCK-INPUT' -Message 'A block requires both -BlockCode and -BlockMessage so the run records why it stopped.'
            Exit-EiResult -Result $result -Json:$Json
        }

        $stage.status = 'blocked'
        $stage.gateResult = if ([string]::IsNullOrWhiteSpace([string]$stage.gate)) { 'not-run' } else { 'block' }
        $stage.blockReason = $BlockMessage

        $state.stage = $StageId
        $state.status = 'blocked'
        $state.blocks = @($state.blocks) + @([ordered]@{
                code        = $BlockCode
                stage       = $StageId
                message     = $BlockMessage
                remediation = if ([string]::IsNullOrWhiteSpace($Remediation)) { $null } else { $Remediation }
                raisedAt    = $timestamp
            })
    }
}

$state.updatedAt = $timestamp
$candidateJson = $state | ConvertTo-Json -Depth 20

$schemaCheck = Test-EiJsonAgainstSchema -Content $candidateJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'workflow-state.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-SCHEMA' -Message "The '$Action' transition would produce schema-invalid state: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

# The candidate is validated on disk before it is committed, so a rejected transition leaves the real state untouched.
$candidatePath = Join-Path ([System.IO.Path]::GetTempPath()) ("ei-workflow-state-candidate-$([guid]::NewGuid().ToString('N')).json")
Set-Content -LiteralPath $candidatePath -Value $candidateJson -Encoding utf8

try {
    $candidateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $candidatePath -Json | ConvertFrom-Json

    if ($candidateValidation.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-TRANSITION-INVALID' -Message "The '$Action' transition would produce invalid state: $(@($candidateValidation.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }
}
finally {
    Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
}

Set-Content -LiteralPath $statePath -Value $candidateJson -Encoding utf8

$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value $stage.status
$result = Set-EiDetail -Result $result -Name 'GateResult' -Value $stage.gateResult
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $state.status
$result = Set-EiDetail -Result $result -Name 'CurrentStage' -Value $state.stage
$result = Set-EiDetail -Result $result -Name 'NextStage' -Value $candidateValidation.Details.NextStage
$result = Set-EiDetail -Result $result -Name 'BlockCount' -Value @($state.blocks).Count
$result = Set-EiDetail -Result $result -Name 'UpdatedAt' -Value $state.updatedAt

Exit-EiResult -Result $result -Json:$Json
