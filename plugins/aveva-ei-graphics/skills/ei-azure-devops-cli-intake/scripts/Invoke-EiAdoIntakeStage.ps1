#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run the `ado-intake` lifecycle stage: retrieve the Azure DevOps story and seal it as the `ado` artifact.

.DESCRIPTION
This is the stage wrapper, not a second intake implementation. Retrieval is delegated to
`Invoke-EiAdoCliIntake.ps1`, which owns URL parsing, `az` invocation and failure classification.
This script only decides what the workflow is allowed to believe afterwards.

The stage fails closed. A retrieval that did not reach `retrieved` never becomes an artifact: the
stage is blocked with the intake's own reason so the run stops with an explained cause rather than
carrying a partial story forward. The `artifact-present` gate is not asserted either -- it is
evaluated by reading the persisted artifact back through `Read-EiWorkflowArtifact.ps1`, and the
stage is only completed with a passing gate when that read succeeds.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [AllowEmptyString()][string]$WorkItemUrl = '',
    [AllowEmptyString()][string]$WorkItemId = '',
    [AllowEmptyString()][string]$Organization = '',
    [AllowEmptyString()][string]$Project = '',
    [AllowEmptyString()][string]$CliWorkItemJson = '',
    [AllowEmptyString()][string]$Summary = '',
    [string]$StageId = 'ado-intake',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts'
. (Join-Path $stateScripts 'helpers' 'EiWorkflowState.ps1')

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'StageId' -Value $StageId

$stagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
$writePath = Join-Path $stateScripts 'Write-EiWorkflowArtifact.ps1'
$readPath = Join-Path $stateScripts 'Read-EiWorkflowArtifact.ps1'
$intakePath = Join-Path $PSScriptRoot 'Invoke-EiAdoCliIntake.ps1'

function Block-EiAdoIntakeStage {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Remediation
    )

    $blocked = & $stagePath -StateDir $StateDir -StageId $StageId -Action block `
        -BlockCode $Code -BlockMessage $Message -Remediation $Remediation -Json | ConvertFrom-Json

    $updated = Add-EiError -Result $Result -Code $Code -Message $Message
    if ($blocked.Status -ne 'Valid') {
        $updated = Add-EiWarning -Result $updated -Message "The stage could not be recorded as blocked: $(@($blocked.Errors) -join '; ')"
    }

    Set-EiDetail -Result $updated -Name 'StageStatus' -Value 'blocked'
}

# The story id is taken from the workflow state rather than a parameter, so the artifact cannot be
# written under an id the run was never initialised with.
$statePayload = & $readPath -StateDir $StateDir -Name 'workflow-state' -Json | ConvertFrom-Json
if ($statePayload.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIAI-STATE-UNREADABLE' -Message "Workflow state could not be read from '$StateDir': $(@($statePayload.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$storyId = $statePayload.Details.Payload.storyId
$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $storyId

$started = & $stagePath -StateDir $StateDir -StageId $StageId -Action start -Json | ConvertFrom-Json
if ($started.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIAI-STAGE-NOT-STARTED' -Message "Stage '$StageId' could not be started: $(@($started.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$intakeArgs = @{ Json = $true }
if (-not [string]::IsNullOrWhiteSpace($WorkItemUrl)) { $intakeArgs['WorkItemUrl'] = $WorkItemUrl }
if (-not [string]::IsNullOrWhiteSpace($WorkItemId)) { $intakeArgs['WorkItemId'] = $WorkItemId }
if (-not [string]::IsNullOrWhiteSpace($Organization)) { $intakeArgs['Organization'] = $Organization }
if (-not [string]::IsNullOrWhiteSpace($Project)) { $intakeArgs['Project'] = $Project }
if (-not [string]::IsNullOrWhiteSpace($CliWorkItemJson)) { $intakeArgs['CliWorkItemJson'] = $CliWorkItemJson }

$intakeRaw = & $intakePath @intakeArgs
$intake = $null
try { $intake = ($intakeRaw -join [Environment]::NewLine) | ConvertFrom-Json }
catch { $intake = $null }

if ($null -eq $intake -or $intake.status -ne 'retrieved') {
    $reason = if ($null -eq $intake) { 'intake-output-unreadable' } else { $intake.reason }
    $result = Block-EiAdoIntakeStage -Result $result -Code 'EIAI-INTAKE-FAILED' `
        -Message "Azure DevOps intake did not return a story (reason: $reason)." `
        -Remediation 'Confirm the work item reference and that the az CLI session can read it, then re-run the ado-intake stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$context = $intake.workItemContext
$artifact = [ordered]@{
    schemaVersion = $script:EiStateSchemaVersion
    source        = 'ei-azure-devops-cli-intake'
    storyId       = $storyId
    storyRef      = if ([string]::IsNullOrWhiteSpace($context.workItemUrl)) { $null } else { $context.workItemUrl }
    summary       = if ([string]::IsNullOrWhiteSpace($Summary)) { $null } else { $Summary }
    description   = $intake.descriptionText
    workItem      = [ordered]@{
        id           = [string]$context.workItemId
        organization = [string]$context.organization
        project      = [string]$context.project
        url          = if ([string]::IsNullOrWhiteSpace($context.workItemUrl)) { $null } else { [string]$context.workItemUrl }
    }
    retrieval     = [ordered]@{
        status     = $intake.status
        reason     = $intake.reason
        authSource = $context.authSource
    }
    retrievedAt   = Get-EiUtcTimestamp
}

$written = & $writePath -StateDir $StateDir -Name 'ado' -Content ($artifact | ConvertTo-Json -Depth 10) -Json | ConvertFrom-Json
if ($written.Status -ne 'Valid') {
    $result = Block-EiAdoIntakeStage -Result $result -Code 'EIAI-ARTIFACT-UNWRITABLE' `
        -Message "The ado artifact could not be persisted: $(@($written.Errors) -join '; ')" `
        -Remediation 'Fix the reported schema or state-directory problem and re-run the ado-intake stage.'
    Exit-EiResult -Result $result -Json:$Json
}

# The `artifact-present` gate is evidence, not an assumption: it passes only if the persisted
# artifact reads back and validates.
$readBack = & $readPath -StateDir $StateDir -Name 'ado' -Json | ConvertFrom-Json
if ($readBack.Status -ne 'Valid') {
    $result = Block-EiAdoIntakeStage -Result $result -Code 'EIAI-ARTIFACT-ABSENT' `
        -Message "The ado artifact did not read back after being written: $(@($readBack.Errors) -join '; ')" `
        -Remediation 'Inspect the state directory for a truncated or hand-edited ado.json and re-run the ado-intake stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$completed = & $stagePath -StateDir $StateDir -StageId $StageId -Action complete -GateResult pass -Json | ConvertFrom-Json
if ($completed.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIAI-STAGE-NOT-COMPLETED' -Message "Stage '$StageId' could not be completed: $(@($completed.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value 'complete'
$result = Set-EiDetail -Result $result -Name 'GateResult' -Value 'pass'
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $completed.Details.WorkflowStatus
$result = Set-EiDetail -Result $result -Name 'Path' -Value $written.Details.Path
$result = Set-EiDetail -Result $result -Name 'Payload' -Value $readBack.Details.Payload

Exit-EiResult -Result $result -Json:$Json
