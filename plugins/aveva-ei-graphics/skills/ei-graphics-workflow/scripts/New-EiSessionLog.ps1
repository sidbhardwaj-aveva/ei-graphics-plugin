#!/usr/bin/env pwsh
<#
.SYNOPSIS
Create or update a session log for a completed EI Graphics workflow run.

.DESCRIPTION
Writes a structured JSON session log to `.ei-session-logs/<storyId>/<timestamp>-<sessionId>.json`
at the workspace root. Each log captures:
  - Session timing (total and per-stage breakdown)
  - Workflow inputs (story ID, path, entry point, diff base branch)
  - Gate results and block codes from the completed workflow
  - Token usage when provided (populated manually or from agent telemetry hooks)
  - Auto-generated improvement notes flagging slow stages, gate failures, and correction attempts

The log directory is gitignored so logs stay local to each developer. Use
Read-EiSessionLogs.ps1 to generate a cross-session summary report.

.PARAMETER StateDir
The workflow state directory, e.g. .copilottracking/ei-graphics/123456.

.PARAMETER WorkspaceRoot
Repository root used to resolve .ei-session-logs/. Defaults to current location.

.PARAMETER SessionId
Unique identifier for this session. Defaults to a GUID.

.PARAMETER AgentVersion
Plugin/skill version string recorded in the log. Defaults to '1.0.0'.

.PARAMETER EntryPoint
How the workflow was invoked (e.g. 'ado-url', 'ado-id', 'manual'). Optional.

.PARAMETER PromptTokens
Number of prompt tokens consumed. Optional; leave unset if unavailable.

.PARAMETER CompletionTokens
Number of completion tokens consumed. Optional; leave unset if unavailable.

.PARAMETER EstimatedCostUSD
Estimated USD cost for this session. Optional; leave unset if unavailable.

.PARAMETER LogDir
Override the default .ei-session-logs root. Primarily for testing.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
Details.LogFile holds the path to the written log file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$SessionId = [System.Guid]::NewGuid().ToString(),
    [string]$AgentVersion = '1.0.0',
    [string]$EntryPoint = '',
    [Nullable[int]]$PromptTokens = $null,
    [Nullable[int]]$CompletionTokens = $null,
    [Nullable[double]]$EstimatedCostUSD = $null,
    [string]$LogDir = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'ei-workflow-state' 'scripts')))
. "$stateScripts/helpers/EiWorkflowState.ps1"

$result = New-EiResult

# ── Validate state directory ────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    $result = Add-EiError -Result $result -Code 'EILOG-STATE-MISSING' -Message "State directory not found at '$StateDir'."
    Exit-EiResult -Result $result -Json:$Json
}

$stateFile = Join-Path $StateDir 'workflow-state.json'
if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
    $result = Add-EiError -Result $result -Code 'EILOG-STATE-MISSING' -Message "workflow-state.json not found in '$StateDir'."
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
}
catch {
    $result = Add-EiError -Result $result -Code 'EILOG-STATE-INVALID' -Message "workflow-state.json could not be parsed: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

# ── Resolve log directory ────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $WorkspaceRoot (Join-Path '.ei-session-logs' [string]$state.storyId)
}

if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $LogDir -Force
}

# ── Compute overall timing ───────────────────────────────────────────────────
$startedAt = [string]$state.createdAt
$endedAt   = [string]$state.updatedAt

$durationSeconds = $null
try {
    $start = [datetime]::Parse($startedAt)
    $end   = [datetime]::Parse($endedAt)
    $durationSeconds = [math]::Round(($end - $start).TotalSeconds, 2)
}
catch { }

# ── Build per-stage timing entries ──────────────────────────────────────────
$stageEntries = @(foreach ($stage in @($state.stages)) {
    $stageDurationSeconds = $null
    try {
        if ($stage.startedAt -and $stage.completedAt) {
            $s = [datetime]::Parse([string]$stage.startedAt)
            $e = [datetime]::Parse([string]$stage.completedAt)
            $stageDurationSeconds = [math]::Round(($e - $s).TotalSeconds, 2)
        }
    }
    catch { }

    [ordered]@{
        id              = [string]$stage.id
        name            = [string]$stage.name
        startedAt       = $stage.startedAt
        endedAt         = $stage.completedAt
        durationSeconds = $stageDurationSeconds
        status          = [string]$stage.status
        gateResult      = [string]$stage.gateResult
        blockReason     = if ($stage.PSObject.Properties['blockReason']) { $stage.blockReason } else { $null }
    }
})

# ── Collect gates and blocks ─────────────────────────────────────────────────
$gateEntries = @(foreach ($stage in @($state.stages)) {
    if (-not $stage.gate) { continue }
    [ordered]@{
        id     = [string]$stage.gate
        stage  = [string]$stage.id
        result = [string]$stage.gateResult
        detail = if ($stage.PSObject.Properties['blockReason']) { [string]$stage.blockReason } else { $null }
    }
})

$blockEntries = @(foreach ($block in @($state.blocks)) {
    [ordered]@{
        code    = [string]$block.code
        stage   = [string]$block.stage
        message = [string]$block.message
    }
})

# ── Resolve input metadata from the ADO artifact if present ─────────────────
$adoFile    = Join-Path $StateDir 'ado.json'
$storyRef   = if ($state.PSObject.Properties['storyRef']) { [string]$state.storyRef } else { $null }
$diffBase   = $null

if (Test-Path -LiteralPath $adoFile -PathType Leaf) {
    try {
        $ado      = Get-Content -LiteralPath $adoFile -Raw | ConvertFrom-Json
        if ($ado.PSObject.Properties['url']) { $storyRef = [string]$ado.url }
    }
    catch { }
}

# ── Auto-generate improvement notes ─────────────────────────────────────────
$improvementNotes = [System.Collections.Generic.List[object]]::new()

# Flag slow sessions (>5 minutes)
if ($null -ne $durationSeconds -and $durationSeconds -gt 300) {
    $improvementNotes.Add([ordered]@{
        category = 'timing'
        note     = "Session duration was $([math]::Round($durationSeconds / 60, 1)) minutes. Review stage breakdown to identify bottlenecks."
    })
}

# Flag slow individual stages (>60 seconds)
foreach ($s in $stageEntries) {
    if ($null -ne $s.durationSeconds -and $s.durationSeconds -gt 60) {
        $improvementNotes.Add([ordered]@{
            category = 'timing'
            note     = "Stage '$($s.name)' took $([math]::Round($s.durationSeconds, 1))s. Consider optimising prompts or scripts for this stage."
        })
    }
}

# Flag gate failures
foreach ($g in $gateEntries) {
    if ($g.result -eq 'block') {
        $improvementNotes.Add([ordered]@{
            category = 'gate-failure'
            note     = "Gate '$($g.id)' blocked at stage '$($g.stage)'. Detail: $($g.detail)"
        })
    }
}

# Flag correction attempts
if ($state.PSObject.Properties['correctionAttempts'] -and [int]$state.correctionAttempts -gt 0) {
    $improvementNotes.Add([ordered]@{
        category = 'correction-attempt'
        note     = "$($state.correctionAttempts) correction attempt(s) used (max $($state.maxCorrectionAttempts)). Review gate thresholds if this is frequent."
    })
}

# Flag blocks
foreach ($b in $blockEntries) {
    $improvementNotes.Add([ordered]@{
        category = 'block'
        note     = "Block '$($b.code)' at stage '$($b.stage)': $($b.message)"
    })
}

# ── Build token usage ────────────────────────────────────────────────────────
$totalTokens = $null
if ($null -ne $PromptTokens -and $null -ne $CompletionTokens) {
    $totalTokens = $PromptTokens + $CompletionTokens
}

$tokenUsage = [ordered]@{
    promptTokens     = $PromptTokens
    completionTokens = $CompletionTokens
    totalTokens      = $totalTokens
    estimatedCostUSD = $EstimatedCostUSD
    note             = if ($null -eq $PromptTokens) { 'Token usage not available from this execution context. Populate via agent telemetry hooks.' } else { 'Populated from caller.' }
}

# ── Assemble the log document ────────────────────────────────────────────────
$log = [ordered]@{
    schemaVersion  = '1.0.0'
    sessionId      = $SessionId
    storyId        = [string]$state.storyId
    workflowPath   = [string]$state.path
    agentVersion   = $AgentVersion
    startedAt      = $startedAt
    endedAt        = $endedAt
    durationSeconds = $durationSeconds
    stages         = $stageEntries
    gates          = $gateEntries
    blocks         = $blockEntries
    finalStatus    = [string]$state.status
    summary        = $null
    tokenUsage     = $tokenUsage
    inputs         = [ordered]@{
        storyRef       = $storyRef
        entryPoint     = if ([string]::IsNullOrWhiteSpace($EntryPoint)) { $null } else { $EntryPoint }
        diffBaseBranch = $diffBase
    }
    improvementNotes = @($improvementNotes)
}

# ── Populate summary from workflow-result artifact if available ──────────────
$resultFile = Join-Path $StateDir 'workflow-result.json'
if (Test-Path -LiteralPath $resultFile -PathType Leaf) {
    try {
        $wr = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        if ($wr.PSObject.Properties['summary']) {
            $log.summary = [string]$wr.summary
        }
    }
    catch { }
}

# ── Validate against schema ──────────────────────────────────────────────────
$schemaPath = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'ei-workflow-state' (Join-Path 'schemas' 'session-log.schema.json'))))
if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
    try {
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        # Basic required-field check (full JSON Schema validation requires an external library)
        $required = @($schema.required)
        foreach ($field in $required) {
            if (-not $log.Contains($field)) {
                $result = Add-EiWarning -Result $result -Message "Session log is missing required field '$field' — log written but may fail schema validation."
            }
        }
    }
    catch { }
}

# ── Write the log file ───────────────────────────────────────────────────────
$timestamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$fileName   = "$timestamp-$($SessionId.Substring(0, 8)).json"
$logFile    = Join-Path $LogDir $fileName

$log | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $logFile -Encoding UTF8

$result = Set-EiDetail -Result $result -Name 'LogFile'   -Value $logFile
$result = Set-EiDetail -Result $result -Name 'SessionId' -Value $SessionId
$result = Set-EiDetail -Result $result -Name 'DurationSeconds' -Value $durationSeconds
$result = Set-EiDetail -Result $result -Name 'ImprovementNoteCount' -Value $improvementNotes.Count

Exit-EiResult -Result $result -Json:$Json
