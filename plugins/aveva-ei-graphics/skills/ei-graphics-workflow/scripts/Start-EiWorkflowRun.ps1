#!/usr/bin/env pwsh
<#
.SYNOPSIS
Bootstrap an EI Graphics run in a single call: initialise state, write the start marker, preflight
dependencies, and record the `preflight` (and, on IMPLEMENT, `state-init`) stages.

.DESCRIPTION
Startup used to cost seven separate script invocations, and every one of them is a separate
approval prompt in an agent host. That tax was paid before the run did any story work at all, so
this script performs the whole sequence in one process and returns one result contract.

Consolidation does not mean skipping. Each underlying script is still the single owner of its own
step and is still called: `Initialize-EiWorkflowState.ps1` materialises state,
`Validate-EiWorkflowPrerequisites.ps1` evaluates the `prerequisites` gate, and
`Set-EiWorkflowStage.ps1` remains the only path that mutates `workflow-state.json`.

The bootstrap fails closed. A failing preflight records `preflight` as blocked and returns Invalid
rather than leaving a run that looks startable. Writing the session log is the one non-fatal step;
it produces a warning, because a missing local log must never stop a run.

Re-running is safe. Stages already `complete` are left alone, so an interrupted bootstrap can be
repeated without tripping the `EIWF-TRANSITION-INVALID` guard.

`-StoryId` may be left empty when `-StoryRef` carries a work item link or a pasted reference such as
`[Bug 4983245 SR350 - <title>](<url>)`; the id is then resolved deterministically by
`Resolve-EiWorkItemReference`.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details. Details.StateDir and Details.SessionId
carry the values every later stage needs.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$StoryId,
    [ValidateSet('IMPLEMENT', 'ITERATE')][string]$WorkflowPath = 'IMPLEMENT',
    [AllowEmptyString()][string]$StoryRef = '',
    [Alias('RepositoryRoot')][string]$WorkspaceRoot = (Get-Location).Path,
    [ValidateSet('A', 'B', 'C', 'D', 'E')][string]$Phase = 'A',
    [string]$SessionId = [System.Guid]::NewGuid().ToString(),
    [AllowEmptyString()][string]$EntryPoint = '',
    [string[]]$PluginSearchRoot = @(),
    [switch]$NoDefaultSearchRoots,
    [string]$TrackingDir = '.copilottracking',
    [AllowEmptyString()][string]$LogDir = '',
    [switch]$Force,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts'
. (Join-Path $stateScripts 'helpers' 'EiWorkflowState.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'ei-azure-devops-cli-intake' 'scripts' 'helpers' 'EiWorkItemReference.ps1')

$initPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
$stagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
$writePath = Join-Path $stateScripts 'Write-EiWorkflowArtifact.ps1'
$logPath = Join-Path $PSScriptRoot 'New-EiSessionLog.ps1'
$prerequisitesPath = Join-Path $PSScriptRoot 'Validate-EiWorkflowPrerequisites.ps1'

# The story is handed over as a pasted work item link, so the id and the canonical url are read off
# it by a script rather than by the model. An id that is already a usable state directory name is
# left alone; the reference is still parsed so `storyRef` is stored as a bare url.
$reference = Resolve-EiWorkItemReference -Reference $StoryRef -WorkItemId $StoryId
if ($reference.status -eq 'resolved') {
    if (-not (Test-EiStoryId -StoryId $StoryId)) { $StoryId = $reference.workItemId }
    if (-not [string]::IsNullOrWhiteSpace($reference.workItemUrl)) { $StoryRef = $reference.workItemUrl }
}

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $StoryId
$result = Set-EiDetail -Result $result -Name 'StoryRef' -Value $StoryRef
$result = Set-EiDetail -Result $result -Name 'WorkflowPath' -Value $WorkflowPath
$result = Set-EiDetail -Result $result -Name 'SessionId' -Value $SessionId

function Get-EiOptionalDetail {
    param(
        [Parameter(Mandatory)][psobject]$Details,
        [Parameter(Mandatory)][string]$Name
    )

    # Details is built by Set-EiDetail, so absent steps simply have no property under StrictMode.
    if ($Details.PSObject.Properties[$Name]) { $Details.$Name } else { $null }
}

# --- Step 1: state ---------------------------------------------------------------------------

$initArgs = @{
    StoryId      = $StoryId
    WorkflowPath = $WorkflowPath
    WorkspaceRoot = $WorkspaceRoot
    TrackingDir  = $TrackingDir
    Json         = $true
}
if (-not [string]::IsNullOrWhiteSpace($StoryRef)) { $initArgs['StoryRef'] = $StoryRef }
if ($Force) { $initArgs['Force'] = $true }

$init = & $initPath @initArgs | ConvertFrom-Json

foreach ($warning in @($init.Warnings)) { $result = Add-EiWarning -Result $result -Message $warning }

if ($init.Status -ne 'Valid') {
    foreach ($initError in @($init.Errors)) {
        $result = Add-EiError -Result $result -Code 'EIWF-BOOTSTRAP-STATE' -Message $initError
    }
    Exit-EiResult -Result $result -Json:$Json
}

$stateDir = [string]$init.Details.StateDir
$resumed = [bool](Get-EiOptionalDetail -Details $init.Details -Name 'Resumed')
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $stateDir
$result = Set-EiDetail -Result $result -Name 'Resumed' -Value $resumed

# --- Step 2: start marker (non-fatal) --------------------------------------------------------

$logArgs = @{
    StateDir     = $stateDir
    WorkspaceRoot = $WorkspaceRoot
    SessionId    = $SessionId
    FinalStatus  = 'in-progress'
    Json         = $true
}
if (-not [string]::IsNullOrWhiteSpace($EntryPoint)) { $logArgs['EntryPoint'] = $EntryPoint }
if (-not [string]::IsNullOrWhiteSpace($LogDir)) { $logArgs['LogDir'] = $LogDir }

try {
    $log = & $logPath @logArgs | ConvertFrom-Json
    if ($log.Status -ne 'Valid') {
        $result = Add-EiWarning -Result $result -Message "The session start marker was not written: $(@($log.Errors) -join '; ')"
    }
}
catch {
    $result = Add-EiWarning -Result $result -Message "The session start marker was not written: $($_.Exception.Message)"
}

# --- Step 3: preflight gate ------------------------------------------------------------------

# -StateDir is deliberately omitted: from Phase B it makes the preflight assert candidate.json,
# which by definition does not exist yet at bootstrap time. That gate belongs to the later
# re-validation before the proposed-scope stage.
$prerequisiteArgs = @{
    RepositoryRoot = $WorkspaceRoot
    Phase          = $Phase
    Json           = $true
}
if (@($PluginSearchRoot).Count -gt 0) { $prerequisiteArgs['PluginSearchRoot'] = $PluginSearchRoot }
if ($NoDefaultSearchRoots) { $prerequisiteArgs['NoDefaultSearchRoots'] = $true }

$prerequisites = & $prerequisitesPath @prerequisiteArgs | ConvertFrom-Json

foreach ($warning in @($prerequisites.Warnings)) { $result = Add-EiWarning -Result $result -Message $warning }
$result = Set-EiDetail -Result $result -Name 'Prerequisites' -Value $prerequisites.Details

# The gate verdict is persisted, not just asserted. `preflight` owns the `prerequisites` artifact,
# so Set-EiWorkflowStage.ps1 refuses to complete the stage without this file — a run that stalls on
# stage order cannot be freed by claiming `-GateResult pass` for an evaluation that never ran.
$evidence = [ordered]@{
    schemaVersion     = '1.0.0'
    gate              = 'prerequisites'
    stage             = 'preflight'
    storyId           = $StoryId
    workflowPath      = $WorkflowPath
    phase             = $Phase
    generatedAt       = Get-EiUtcTimestamp
    verdict           = if ($prerequisites.Status -eq 'Valid') { 'pass' } else { 'block' }
    pwshVersion       = $PSVersionTable.PSVersion.ToString()
    repositoryRoot    = $WorkspaceRoot
    insideWorkTree    = Get-EiOptionalDetail -Details $prerequisites.Details -Name 'InsideWorkTree'
    searchRoots       = @(Get-EiOptionalDetail -Details $prerequisites.Details -Name 'SearchRoots')
    found             = @(Get-EiOptionalDetail -Details $prerequisites.Details -Name 'Found')
    missingRequired   = @(Get-EiOptionalDetail -Details $prerequisites.Details -Name 'MissingRequired')
    missingLaterPhase = @(Get-EiOptionalDetail -Details $prerequisites.Details -Name 'MissingLaterPhase')
    errors            = @($prerequisites.Errors)
    warnings          = @($prerequisites.Warnings)
}

$evidenceError = $null
try {
    $written = & $writePath -StateDir $stateDir -Name 'prerequisites' `
        -Content ($evidence | ConvertTo-Json -Depth 10) -Json | ConvertFrom-Json
    if ($written.Status -ne 'Valid') { $evidenceError = @($written.Errors) -join '; ' }
}
catch {
    $evidenceError = $_.Exception.Message
}

if ($prerequisites.Status -ne 'Valid') {
    $reason = @($prerequisites.Errors) -join '; '

    $blocked = & $stagePath -StateDir $stateDir -StageId 'preflight' -Action block `
        -BlockCode 'EIWF-PREREQUISITES' -BlockMessage "Preflight failed: $reason" `
        -Remediation 'Install the reported plugin or tool, then re-run the bootstrap.' -Json | ConvertFrom-Json

    foreach ($prerequisiteError in @($prerequisites.Errors)) {
        $result = Add-EiError -Result $result -Code 'EIWF-BOOTSTRAP-PREFLIGHT' -Message $prerequisiteError
    }
    if ($blocked.Status -ne 'Valid') {
        $result = Add-EiWarning -Result $result -Message "The preflight stage could not be recorded as blocked: $(@($blocked.Errors) -join '; ')"
    }
    if ($null -ne $evidenceError) {
        $result = Add-EiWarning -Result $result -Message "The preflight evidence was not written: $evidenceError"
    }

    Exit-EiResult -Result $result -Json:$Json
}

if ($null -ne $evidenceError) {
    $result = Add-EiError -Result $result -Code 'EIWF-BOOTSTRAP-EVIDENCE' -Message "The preflight gate passed but its evidence could not be written, so the stage cannot be completed: $evidenceError"
    Exit-EiResult -Result $result -Json:$Json
}

# --- Step 4: record the stages the bootstrap actually performed -------------------------------

function Complete-EiBootstrapStage {
    param(
        [Parameter(Mandatory)][string]$StateDirectory,
        [Parameter(Mandatory)][string]$StageId
    )

    $state = Get-Content -LiteralPath (Join-Path $StateDirectory 'workflow-state.json') -Raw | ConvertFrom-Json
    $stage = @($state.stages) | Where-Object { $_.id -eq $StageId } | Select-Object -First 1

    if ($null -eq $stage) { return "Stage '$StageId' is not part of the '$($state.path)' lifecycle." }
    if ($stage.status -eq 'complete') { return $null }

    if ($stage.status -eq 'pending') {
        $started = & $stagePath -StateDir $StateDirectory -StageId $StageId -Action start -Json | ConvertFrom-Json
        if ($started.Status -ne 'Valid') { return (@($started.Errors) -join '; ') }
    }

    $gateResult = if ([string]::IsNullOrWhiteSpace([string]$stage.gate)) { '' } else { 'pass' }
    $completed = & $stagePath -StateDir $StateDirectory -StageId $StageId -Action complete -GateResult $gateResult -Json | ConvertFrom-Json
    if ($completed.Status -ne 'Valid') { return (@($completed.Errors) -join '; ') }

    return $null
}

# ITERATE's second stage is `state-recovery`, which also recovers branch/PR evidence. That is more
# than this bootstrap performed, so it is left to its owner.
$bootstrapStages = @('preflight')
if ($WorkflowPath -eq 'IMPLEMENT') { $bootstrapStages += 'state-init' }

$completedStages = @()
foreach ($stageId in $bootstrapStages) {
    $stageError = Complete-EiBootstrapStage -StateDirectory $stateDir -StageId $stageId

    if ($null -ne $stageError) {
        $result = Add-EiError -Result $result -Code 'EIWF-BOOTSTRAP-STAGE' -Message "Stage '$stageId' could not be recorded: $stageError"
        $result = Set-EiDetail -Result $result -Name 'StagesCompleted' -Value $completedStages
        Exit-EiResult -Result $result -Json:$Json
    }

    $completedStages += $stageId
}

$finalState = Get-Content -LiteralPath (Join-Path $stateDir 'workflow-state.json') -Raw | ConvertFrom-Json
$result = Set-EiDetail -Result $result -Name 'StagesCompleted' -Value $completedStages
$result = Set-EiDetail -Result $result -Name 'NextStage' -Value $finalState.stage

Exit-EiResult -Result $result -Json:$Json
