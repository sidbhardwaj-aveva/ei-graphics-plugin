#!/usr/bin/env pwsh
<#
.SYNOPSIS
Read and summarise local EI Graphics session logs.

.DESCRIPTION
Scans `.ei-session-logs/` (or a custom -LogRoot) for session JSON files and produces a
human-readable Markdown report covering:
  - Session count and date range
  - Average and max workflow duration
  - Gate failure frequency
  - Correction-attempt rate
  - Most common block codes
  - Top improvement notes from all sessions

Use this report to identify systematic prompt weaknesses, slow stages, or gate threshold
issues so you can iterate on the plugin.

.PARAMETER WorkspaceRoot
Repository root used to resolve .ei-session-logs/. Defaults to current location.

.PARAMETER LogRoot
Override the default .ei-session-logs root. Primarily for testing.

.PARAMETER StoryId
Filter to logs for a single story ID. When omitted, all stories are included.

.PARAMETER Last
Only consider the N most recent session files per story. Defaults to all.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
Details.Report holds the Markdown summary string.
Details.Sessions holds an array of parsed session objects.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$LogRoot = '',
    [string]$StoryId = '',
    [int]$Last = 0,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'ei-workflow-state' 'scripts')))
. "$stateScripts/helpers/EiWorkflowState.ps1"

$result = New-EiResult

# ── Resolve log root ─────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $WorkspaceRoot '.ei-session-logs'
}

if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    $result = Add-EiWarning -Result $result -Message "No session logs found. Run a workflow and call New-EiSessionLog.ps1 to start recording."
    $result = Set-EiDetail -Result $result -Name 'Report'   -Value "# EI Graphics Session Log Report`n`nNo session logs found at '$LogRoot'."
    $result = Set-EiDetail -Result $result -Name 'Sessions' -Value @()
    Exit-EiResult -Result $result -Json:$Json
}

# ── Discover log files ───────────────────────────────────────────────────────
$searchRoot = if ([string]::IsNullOrWhiteSpace($StoryId)) { $LogRoot } else { Join-Path $LogRoot $StoryId }
$logFiles   = @(Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending)

if ($Last -gt 0) {
    $logFiles = @($logFiles | Select-Object -First $Last)
}

if ($logFiles.Count -eq 0) {
    $result = Add-EiWarning -Result $result -Message "No session log files found under '$searchRoot'."
    $result = Set-EiDetail -Result $result -Name 'Report'   -Value "# EI Graphics Session Log Report`n`nNo session log files found."
    $result = Set-EiDetail -Result $result -Name 'Sessions' -Value @()
    Exit-EiResult -Result $result -Json:$Json
}

# ── Parse logs ───────────────────────────────────────────────────────────────
$sessions = [System.Collections.Generic.List[object]]::new()
$parseErrors = 0

foreach ($file in $logFiles) {
    try {
        $raw = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $sessions.Add($raw)
    }
    catch {
        $parseErrors++
        $result = Add-EiWarning -Result $result -Message "Could not parse '$($file.Name)': $($_.Exception.Message)"
    }
}

# ── Compute aggregate statistics ─────────────────────────────────────────────
$totalSessions  = $sessions.Count
$completedCount = @($sessions | Where-Object { $_.finalStatus -eq 'completed' }).Count
$blockedCount   = @($sessions | Where-Object { $_.finalStatus -eq 'blocked' }).Count
$failedCount    = @($sessions | Where-Object { $_.finalStatus -eq 'failed' }).Count

$durations = @($sessions | Where-Object { $null -ne $_.durationSeconds } | ForEach-Object { [double]$_.durationSeconds })
$avgDurationSec = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Average).Average, 1) } else { $null }
$maxDurationSec = if ($durations.Count -gt 0) { ($durations | Measure-Object -Maximum).Maximum } else { $null }

$allGates = @($sessions | ForEach-Object { @($_.gates) } | Where-Object { $_ })
$gateFailures = @($allGates | Where-Object { $_.result -eq 'block' })

$allBlocks = @($sessions | ForEach-Object { @($_.blocks) } | Where-Object { $_ })
$blockFreq = @($allBlocks | Group-Object code | Sort-Object Count -Descending | Select-Object -First 5)

$correctionSessions = @($sessions | Where-Object {
    @($_.improvementNotes) | Where-Object { $_.category -eq 'correction-attempt' }
}).Count

$allNotes = @($sessions | ForEach-Object { @($_.improvementNotes) } | Where-Object { $_ })
$topNotes = @($allNotes | Group-Object note | Sort-Object Count -Descending | Select-Object -First 10)

# ── Date range ───────────────────────────────────────────────────────────────
$startDates = @($sessions | Where-Object { $_.startedAt } | ForEach-Object { [datetime]::Parse([string]$_.startedAt) } | Sort-Object)
$firstDate  = if ($startDates.Count -gt 0) { $startDates[0].ToString('yyyy-MM-dd') } else { 'unknown' }
$lastDate   = if ($startDates.Count -gt 0) { $startDates[-1].ToString('yyyy-MM-dd') } else { 'unknown' }

# ── Build Markdown report ─────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()

$null = $sb.AppendLine('# EI Graphics Session Log Report')
$null = $sb.AppendLine('')
$null = $sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC")
$null = $sb.AppendLine("Log root: ``$LogRoot``")
$null = $sb.AppendLine('')

$null = $sb.AppendLine('## Summary')
$null = $sb.AppendLine('')
$null = $sb.AppendLine("| Metric | Value |")
$null = $sb.AppendLine("|---|---|")
$null = $sb.AppendLine("| Total sessions | $totalSessions |")
$null = $sb.AppendLine("| Date range | $firstDate → $lastDate |")
$null = $sb.AppendLine("| Completed | $completedCount |")
$null = $sb.AppendLine("| Blocked | $blockedCount |")
$null = $sb.AppendLine("| Failed | $failedCount |")
$null = $sb.AppendLine("| Avg duration | $(if ($null -ne $avgDurationSec) { "$avgDurationSec s" } else { 'n/a' }) |")
$null = $sb.AppendLine("| Max duration | $(if ($null -ne $maxDurationSec) { "$maxDurationSec s" } else { 'n/a' }) |")
$null = $sb.AppendLine("| Gate failures | $($gateFailures.Count) |")
$null = $sb.AppendLine("| Sessions with correction attempts | $correctionSessions |")
$null = $sb.AppendLine("| Parse errors | $parseErrors |")
$null = $sb.AppendLine('')

if ($blockFreq.Count -gt 0) {
    $null = $sb.AppendLine('## Most Common Blocks')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Block code | Occurrences |')
    $null = $sb.AppendLine('|---|---|')
    foreach ($b in $blockFreq) {
        $null = $sb.AppendLine("| ``$($b.Name)`` | $($b.Count) |")
    }
    $null = $sb.AppendLine('')
}

if ($gateFailures.Count -gt 0) {
    $null = $sb.AppendLine('## Gate Failures')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Gate | Stage | Detail |')
    $null = $sb.AppendLine('|---|---|---|')
    foreach ($g in $gateFailures | Select-Object -First 20) {
        $detail = if ($g.detail) { [string]$g.detail -replace '\|', '\\|' } else { '' }
        $null = $sb.AppendLine("| ``$($g.id)`` | ``$($g.stage)`` | $detail |")
    }
    $null = $sb.AppendLine('')
}

if ($topNotes.Count -gt 0) {
    $null = $sb.AppendLine('## Top Improvement Notes')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('> These observations were auto-generated across all recorded sessions.')
    $null = $sb.AppendLine('> Use them to identify recurring problems and prioritise prompt or gate improvements.')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Count | Note |')
    $null = $sb.AppendLine('|---|---|')
    foreach ($n in $topNotes) {
        $note = [string]$n.Name -replace '\|', '\\|'
        $null = $sb.AppendLine("| $($n.Count) | $note |")
    }
    $null = $sb.AppendLine('')
}

# Per-session index
$null = $sb.AppendLine('## Session Index')
$null = $sb.AppendLine('')
$null = $sb.AppendLine('| Session | Story | Path | Status | Duration (s) | Started |')
$null = $sb.AppendLine('|---|---|---|---|---|---|')
foreach ($s in $sessions | Select-Object -First 50) {
    $sid     = if ($s.sessionId) { [string]$s.sessionId.Substring(0, 8) } else { '?' }
    $story   = if ($s.storyId) { [string]$s.storyId } else { '?' }
    $path    = if ($s.workflowPath) { [string]$s.workflowPath } else { '?' }
    $status  = if ($s.finalStatus) { [string]$s.finalStatus } else { '?' }
    $dur     = if ($null -ne $s.durationSeconds) { [string]$s.durationSeconds } else { 'n/a' }
    $started = if ($s.startedAt) { [string]$s.startedAt } else { '?' }
    $null = $sb.AppendLine("| $sid | $story | $path | $status | $dur | $started |")
}
if ($sessions.Count -gt 50) {
    $null = $sb.AppendLine("| *(and $($sessions.Count - 50) more)* | | | | | |")
}

$report = $sb.ToString()
$result = Set-EiDetail -Result $result -Name 'Report'        -Value $report
$result = Set-EiDetail -Result $result -Name 'Sessions'      -Value @($sessions)
$result = Set-EiDetail -Result $result -Name 'TotalSessions' -Value $totalSessions
$result = Set-EiDetail -Result $result -Name 'GateFailures'  -Value $gateFailures.Count

Exit-EiResult -Result $result -Json:$Json
