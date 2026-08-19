#!/usr/bin/env pwsh
<#
.SYNOPSIS
Validate the integrity of an EI Graphics workflow state file and report resume eligibility.

.DESCRIPTION
Fails closed. A missing, unreadable, schema-invalid or internally inconsistent state file is
`Invalid`, never "passed by absence of evidence".

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [AllowEmptyString()][string]$StateDir = '',
    [AllowEmptyString()][string]$StatePath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiWorkflowState.ps1"

$result = New-EiResult

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    if ([string]::IsNullOrWhiteSpace($StateDir)) {
        $result = Add-EiError -Result $result -Code 'EIWF-STATE-INPUT' -Message 'Provide either -StateDir or -StatePath.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $StatePath = Join-Path $StateDir 'workflow-state.json'
}

$result = Set-EiDetail -Result $result -Name 'StatePath' -Value $StatePath

if (-not (Test-Path -LiteralPath $StatePath)) {
    $result = Set-EiDetail -Result $result -Name 'StateExists' -Value $false
    $result = Set-EiDetail -Result $result -Name 'Resumable' -Value $false
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-MISSING' -Message "Workflow state not found at '$StatePath'. Initialise the workflow before running any stage."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StateExists' -Value $true
$content = Get-Content -LiteralPath $StatePath -Raw

try {
    $state = $content | ConvertFrom-Json
}
catch {
    $result = Set-EiDetail -Result $result -Name 'Resumable' -Value $false
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-CORRUPT' -Message "Workflow state is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$schemaCheck = Test-EiJsonAgainstSchema -Content $content -SchemaPath (Join-Path (Get-EiSchemaRoot) 'workflow-state.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Set-EiDetail -Result $result -Name 'Resumable' -Value $false
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-SCHEMA' -Message "Workflow state failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$stages = @($state.stages)
$stageIds = @($stages | ForEach-Object { $_.id })

if ($state.stage -notin $stageIds) {
    $result = Add-EiError -Result $result -Code 'EIWF-STAGE-UNKNOWN' -Message "Current stage '$($state.stage)' is not part of the '$($state.path)' lifecycle."
}

$seenIncomplete = $false
foreach ($stage in $stages) {
    if ($stage.status -in @('pending', 'running')) {
        $seenIncomplete = $true
        continue
    }

    if ($seenIncomplete -and $stage.status -eq 'complete') {
        $result = Add-EiError -Result $result -Code 'EIWF-STAGE-ORDER' -Message "Stage '$($stage.id)' is complete while an earlier stage is still pending. Lifecycle order was bypassed."
    }
}

foreach ($stage in $stages) {
    if ($stage.status -eq 'complete' -and $stage.gate -and $stage.gateResult -ne 'pass') {
        $result = Add-EiError -Result $result -Code 'EIWF-GATE-UNVERIFIED' -Message "Stage '$($stage.id)' is complete but its '$($stage.gate)' gate did not record a pass."
    }
}

if ($state.correctionAttempts -gt $state.maxCorrectionAttempts) {
    $result = Add-EiError -Result $result -Code 'EIWF-RETRY-EXCEEDED' -Message "Correction attempts ($($state.correctionAttempts)) exceed the ceiling of $($state.maxCorrectionAttempts). Escalate to a human."
}

if ($state.status -eq 'blocked' -and @($state.blocks).Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EIWF-BLOCK-UNEXPLAINED' -Message 'Workflow status is blocked but no block record was written.'
}

$nextStage = @($stages | Where-Object { $_.status -in @('pending', 'running') } | Select-Object -First 1)
$nextStageId = if ($nextStage.Count -gt 0) { $nextStage[0].id } else { $null }

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $state.storyId
$result = Set-EiDetail -Result $result -Name 'WorkflowPath' -Value $state.path
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $state.status
$result = Set-EiDetail -Result $result -Name 'Stage' -Value $state.stage
$result = Set-EiDetail -Result $result -Name 'NextStage' -Value $nextStageId
$result = Set-EiDetail -Result $result -Name 'StageCount' -Value $stages.Count
$result = Set-EiDetail -Result $result -Name 'BlockCount' -Value @($state.blocks).Count
$result = Set-EiDetail -Result $result -Name 'ApprovedScopeHash' -Value $state.approvedScopeHash
$result = Set-EiDetail -Result $result -Name 'CorrectionAttempts' -Value $state.correctionAttempts
$result = Set-EiDetail -Result $result -Name 'Resumable' -Value ($result.Status -eq 'Valid' -and $state.status -in @('in-progress', 'awaiting-approval', 'blocked'))

Exit-EiResult -Result $result -Json:$Json
