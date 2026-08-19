#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run the human scope-approval checkpoint: request a decision, approve, or reject.

.DESCRIPTION
This is the orchestration around the `human-approval` gate. It does not make the decision and it
cannot manufacture one: an approval requires an explicit approver identity, and a rejection requires
an explicit decider and reason.

    request  in-progress       -> awaiting-approval   (only when scope-analysis passed)
    approve  awaiting-approval -> sealed, in-progress (delegates to New-EiApprovedScope.ps1)
    reject   awaiting-approval -> blocked            (delegates to Set-EiWorkflowStage.ps1)

The stage itself is carried with the decision: `request` starts it so the pause is recorded against
a started stage, and a successful `approve` completes it against the version that was actually
sealed. A decision that is refused, stale, or fails to seal leaves the stage open.

An approval is bound to the scope that was analysed: the canonical hash of the current
ProposedScope must still match the hash recorded by `scope-analysis`. If the proposal changed after
the human was asked, the approval is stale and nothing is sealed.

Hashing, sealing and versioning are not reimplemented here; they belong to New-EiApprovedScope.ps1.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][ValidateSet('request', 'approve', 'reject')][string]$Decision,
    [AllowEmptyString()][string]$DecidedBy = '',
    [AllowEmptyString()][string]$Note = '',
    [string]$StageId = 'scope-approval',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeHash.ps1"

$stateScripts = "$PSScriptRoot/../../ei-workflow-state/scripts"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'Decision' -Value $Decision
$result = Set-EiDetail -Result $result -Name 'StageId' -Value $StageId

$stateValidation = & "$stateScripts/Validate-EiWorkflowState.ps1" -StateDir $StateDir -Json | ConvertFrom-Json
if ($stateValidation.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "The approval checkpoint cannot run against unusable state: $(@($stateValidation.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $stateValidation.Details.WorkflowStatus

if ($Decision -eq 'reject') {
    if ([string]::IsNullOrWhiteSpace($DecidedBy) -or [string]::IsNullOrWhiteSpace($Note)) {
        $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-INPUT' -Message 'A rejection needs -DecidedBy and -Note. An unexplained refusal cannot be answered.'
        Exit-EiResult -Result $result -Json:$Json
    }

    if ($stateValidation.Details.WorkflowStatus -ne 'awaiting-approval') {
        $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-REQUESTED' -Message "Workflow status is '$($stateValidation.Details.WorkflowStatus)'; there is no pending decision to reject."
        Exit-EiResult -Result $result -Json:$Json
    }

    $blockResult = & "$stateScripts/Set-EiWorkflowStage.ps1" -StateDir $StateDir -StageId $StageId -Action block `
        -BlockCode 'EIWF-SCOPE-REJECTED' -BlockMessage "Scope rejected by $($DecidedBy.Trim()): $($Note.Trim())" `
        -Remediation 'Re-resolve the scope against the rejection reason, re-run scope-analysis, and request approval again.' -Json | ConvertFrom-Json

    if ($blockResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-RECORDED' -Message "The rejection could not be recorded: $(@($blockResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $blockResult.Details.WorkflowStatus
    $result = Set-EiDetail -Result $result -Name 'DecidedBy' -Value $DecidedBy.Trim()
    $result = Set-EiDetail -Result $result -Name 'Recorded' -Value $true
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-REJECTED' -Message "$($DecidedBy.Trim()) rejected the proposed scope: $($Note.Trim())"
    Exit-EiResult -Result $result -Json:$Json
}

# Both request and approve rest on the scope-analysis verdict, which is kept per stage so a later
# validating stage cannot overwrite the evidence the approver was shown.
$evidencePath = Join-Path (Join-Path $StateDir 'validation') 'scope-analysis.json'
$result = Set-EiDetail -Result $result -Name 'AnalysisEvidencePath' -Value $evidencePath

if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-READY' -Message "No scope-analysis evidence was found at '$evidencePath'. Run Invoke-EiScopeAnalysis.ps1 before asking a human to decide."
    Exit-EiResult -Result $result -Json:$Json
}

$evidenceContent = Get-Content -LiteralPath $evidencePath -Raw

$evidenceSchema = Test-EiJsonAgainstSchema -Content $evidenceContent -SchemaPath (Join-Path (Get-EiSchemaRoot) 'validation.schema.json')
if (-not $evidenceSchema.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-SCHEMA' -Message "Scope-analysis evidence failed schema validation: $(@($evidenceSchema.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$evidence = $evidenceContent | ConvertFrom-Json

if ($evidence.gate -ne 'scope-analysis') {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-READY' -Message "Evidence at '$evidencePath' records the '$($evidence.gate)' gate, not 'scope-analysis'."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'AnalysisVerdict' -Value $evidence.verdict
$result = Set-EiDetail -Result $result -Name 'AnalysedHash' -Value $evidence.contentHash

if ($evidence.verdict -ne 'pass') {
    $blockingCodes = @(@($evidence.findings) | Where-Object { $_.severity -eq 'blocking' } | ForEach-Object { $_.code } | Select-Object -Unique)
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-READY' -Message "Scope analysis blocked the scope ($(@($blockingCodes) -join ', ')), so it is not put in front of an approver."
    Exit-EiResult -Result $result -Json:$Json
}

if ($Decision -eq 'request') {
    # A pause taken on a stage that was never started can never be completed, so the stage is started first.
    $stage = @((Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json).stages) |
        Where-Object { $_.id -eq $StageId } | Select-Object -First 1

    if ($null -ne $stage -and $stage.status -eq 'pending') {
        $startResult = & "$stateScripts/Set-EiWorkflowStage.ps1" -StateDir $StateDir -StageId $StageId -Action start -Json | ConvertFrom-Json

        if ($startResult.Status -ne 'Valid') {
            $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-REQUESTED' -Message "Stage '$StageId' could not be started, so the run was not paused for approval: $(@($startResult.Errors) -join '; ')"
            Exit-EiResult -Result $result -Json:$Json
        }
    }

    $requestResult = & "$stateScripts/Set-EiWorkflowApproval.ps1" -StateDir $StateDir -StageId $StageId -Action request -Json | ConvertFrom-Json

    if ($requestResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-REQUESTED' -Message "The run could not be paused for approval: $(@($requestResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $requestResult.Details.WorkflowStatus
    $result = Set-EiDetail -Result $result -Name 'Summary' -Value $evidence.summary
    $result = Set-EiDetail -Result $result -Name 'PresentedPaths' -Value @(@($evidence.paths) | ForEach-Object { $_.path })
    $result = Set-EiDetail -Result $result -Name 'Advisories' -Value @(@($evidence.findings) | ForEach-Object { "$($_.code): $($_.message)" })
    Exit-EiResult -Result $result -Json:$Json
}

if ([string]::IsNullOrWhiteSpace($DecidedBy)) {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVER-MISSING' -Message 'An approval needs an explicit approver identity. An unattributed approval is not an approval.'
    Exit-EiResult -Result $result -Json:$Json
}

if ($stateValidation.Details.WorkflowStatus -ne 'awaiting-approval') {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-REQUESTED' -Message "Workflow status is '$($stateValidation.Details.WorkflowStatus)'; approval must be requested before it can be granted, so that what the approver saw is on record."
    Exit-EiResult -Result $result -Json:$Json
}

$scopeRead = & "$stateScripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'proposed-scope' -Json | ConvertFrom-Json

if ($scopeRead.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-SOURCE-UNREADABLE' -Message "ProposedScope could not be read from state: $(@($scopeRead.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $currentHash = Get-EiScopeContentHash -Scope $scopeRead.Details.Payload
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-INVALID' -Message "The proposed scope could not be canonicalised: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'CurrentHash' -Value $currentHash

if ($currentHash -ne [string]$evidence.contentHash) {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-STALE' -Message "The proposed scope changed after it was analysed: the approver was shown '$($evidence.contentHash)' but the scope now hashes to '$currentHash'. Re-run scope-analysis and ask again; nothing was sealed."
    Exit-EiResult -Result $result -Json:$Json
}

$sealResult = & "$PSScriptRoot/New-EiApprovedScope.ps1" -StateDir $StateDir -ApprovedBy $DecidedBy -ApprovalNote $Note -Json | ConvertFrom-Json

if ($sealResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-SEAL-FAILED' -Message "The approved scope could not be sealed, so the run stays paused for approval: $(@($sealResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'ApprovedScopeVersion' -Value $sealResult.Details.Version
$result = Set-EiDetail -Result $result -Name 'ApprovedScopePath' -Value $sealResult.Details.Path
$result = Set-EiDetail -Result $result -Name 'ContentHash' -Value $sealResult.Details.ContentHash
$result = Set-EiDetail -Result $result -Name 'ApprovedBy' -Value $sealResult.Details.ApprovedBy

$grantResult = & "$stateScripts/Set-EiWorkflowApproval.ps1" -StateDir $StateDir -StageId $StageId -Action grant -Json | ConvertFrom-Json

if ($grantResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-RECORDED' -Message "ApprovedScope v$($sealResult.Details.Version) was sealed but the run is still paused for approval: $(@($grantResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $grantResult.Details.WorkflowStatus

# The stage is completed against the version that was sealed, so a second or later approval is not
# validated against ApprovedScope v1.
$completeResult = & "$stateScripts/Set-EiWorkflowStage.ps1" -StateDir $StateDir -StageId $StageId -Action complete `
    -GateResult pass -ArtifactVersion ([int]$sealResult.Details.Version) -Json | ConvertFrom-Json

if ($completeResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVAL-NOT-RECORDED' -Message "ApprovedScope v$($sealResult.Details.Version) was sealed and the pause was lifted, but stage '$StageId' was not completed, so the run cannot advance: $(@($completeResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $completeResult.Details.WorkflowStatus
$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value $completeResult.Details.StageStatus
$result = Set-EiDetail -Result $result -Name 'GateResult' -Value $completeResult.Details.GateResult
$result = Set-EiDetail -Result $result -Name 'NextStage' -Value $completeResult.Details.NextStage

Exit-EiResult -Result $result -Json:$Json
