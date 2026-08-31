#Requires -Version 7.0
<#
.SYNOPSIS
    Checks that BUILD-PROGRESS.md is in a state a later session can resume from.

.DESCRIPTION
    Reads the task list out of plan.md, then checks BUILD-PROGRESS.md against the rules in
    Part 4 of the plan. Writes an object with Status, Errors, Warnings and Details.
    Exits 0 when the file is valid and 1 when it is not.
#>
[CmdletBinding()]
param(
    [string] $PlanPath = './plan.md',
    [string] $ProgressPath = './BUILD-PROGRESS.md',
    [string] $LogPath = './BUILD-LOG.md',
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errorList = [System.Collections.Generic.List[string]]::new()
$warningList = [System.Collections.Generic.List[string]]::new()

function Write-StdErr {
    param([string] $Message)
    [Console]::Error.WriteLine($Message)
}

# --- read the three files ----------------------------------------------------

$planText = $null
if (Test-Path -LiteralPath $PlanPath) {
    $planText = Get-Content -LiteralPath $PlanPath -Raw
} else {
    $errorList.Add("$PlanPath was not found. The checker reads the task list from it. Copy the build plan to the repository root as plan.md.")
}

$progressLines = @()
if (Test-Path -LiteralPath $ProgressPath) {
    $progressLines = @(Get-Content -LiteralPath $ProgressPath)
} else {
    $errorList.Add("$ProgressPath was not found. Create it with one row for every task in plan.md.")
}

$logText = ''
if (Test-Path -LiteralPath $LogPath) {
    $logText = Get-Content -LiteralPath $LogPath -Raw
} else {
    $errorList.Add("$LogPath was not found. Create it before starting a task, because every task records itself there.")
}

# --- the task list comes from plan.md, never from a hardcoded list -----------

$planTasks = @()
if ($null -ne $planText) {
    $planTasks = @([regex]::Matches($planText, '(?m)^#### (T\d{3})\b') | ForEach-Object { $_.Groups[1].Value })
    if ($planTasks.Count -eq 0) {
        $errorList.Add("$PlanPath has no '#### T0NN' task headings. The checker cannot work out the task list. Check that the file is the full build plan and not a fragment.")
    }
}

# --- parse the progress table ------------------------------------------------

$rows = [System.Collections.Generic.List[pscustomobject]]::new()
for ($i = 0; $i -lt $progressLines.Count; $i++) {
    $line = $progressLines[$i]
    if ($line -notmatch '^\s*\|') { continue }
    $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
    if ($cells.Count -lt 5) { continue }
    if ($cells[0] -notmatch '^T\d{3}$') { continue }
    $rows.Add([pscustomobject]@{
        Id       = $cells[0]
        Task     = $cells[1]
        Status   = $cells[2]
        Commit   = $cells[3]
        Verified = $cells[4]
        Line     = $i + 1
    })
}

if ($progressLines.Count -gt 0 -and $rows.Count -eq 0) {
    $errorList.Add("$ProgressPath has no task rows. Each row must look like '| T001 | Title | TODO | - | - |'.")
}

# --- rule: status is one of exactly four words -------------------------------

$validStatuses = @('TODO', 'IN-PROGRESS', 'DONE', 'BLOCKED')
foreach ($row in $rows) {
    if ($validStatuses -notcontains $row.Status) {
        $errorList.Add("$ProgressPath line $($row.Line): row $($row.Id) has status '$($row.Status)'. Use one of TODO, IN-PROGRESS, DONE or BLOCKED.")
    }
}

# --- rule: every plan task appears exactly once, and nothing extra ------------

$rowIds = @($rows | ForEach-Object { $_.Id })
foreach ($id in $planTasks) {
    $count = @($rowIds | Where-Object { $_ -eq $id }).Count
    if ($count -eq 0) {
        $errorList.Add("$ProgressPath has no row for $id, which plan.md defines. Add a row for it.")
    } elseif ($count -gt 1) {
        $errorList.Add("$ProgressPath has $count rows for $id. Each task gets exactly one row. Delete the duplicates.")
    }
}
foreach ($id in ($rowIds | Sort-Object -Unique)) {
    if ($planTasks -notcontains $id -and $planTasks.Count -gt 0) {
        $errorList.Add("$ProgressPath has a row for $id, but plan.md has no '#### $id' heading. Remove the row or add the task to the plan.")
    }
}

# --- rule: at most one IN-PROGRESS row ---------------------------------------

$inProgress = @($rows | Where-Object { $_.Status -eq 'IN-PROGRESS' })
if ($inProgress.Count -gt 1) {
    $ids = ($inProgress | ForEach-Object { $_.Id }) -join ', '
    $errorList.Add("$ProgressPath has $($inProgress.Count) rows marked IN-PROGRESS ($ids). Only one task runs at a time. Finish or reset all but one.")
}

# --- rule: DONE rows need a timestamp and a commit value ---------------------

foreach ($row in ($rows | Where-Object { $_.Status -eq 'DONE' })) {
    if ($row.Commit -notmatch '^[0-9a-f]{7,40}$' -and $row.Commit -ne 'pending') {
        $errorList.Add("$ProgressPath line $($row.Line): row $($row.Id) is DONE but its Commit column holds '$($row.Commit)'. Put the short commit SHA there, or the word pending until the SHA is recorded.")
    }
    if ($row.Verified -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
        $errorList.Add("$ProgressPath line $($row.Line): row $($row.Id) is DONE but its 'Acceptance verified at' column holds '$($row.Verified)'. Put the time the check passed, as yyyy-MM-ddTHH:mm:ssZ.")
    }
}

# --- rule: pending appears at most once, and only in a DONE row --------------

$pendingRows = @($rows | Where-Object { $_.Commit -eq 'pending' })
foreach ($row in $pendingRows) {
    if ($row.Status -ne 'DONE') {
        $errorList.Add("$ProgressPath line $($row.Line): row $($row.Id) has Commit 'pending' but status '$($row.Status)'. Only a DONE row may say pending, in the gap between the build commit and the SHA commit.")
    }
}
if ($pendingRows.Count -gt 1) {
    $ids = ($pendingRows | ForEach-Object { $_.Id }) -join ', '
    $errorList.Add("$ProgressPath has $($pendingRows.Count) rows with Commit 'pending' ($ids). Only one is allowed. Find the missing SHAs with: git log -1 --format=%h --grep=`"^build(T0NN):`"")
} elseif ($pendingRows.Count -eq 1 -and $pendingRows[0].Status -eq 'DONE') {
    $warningList.Add("Row $($pendingRows[0].Id) is DONE with Commit 'pending'. Record its SHA and make the chore($($pendingRows[0].Id)) commit.")
}

# --- rule: no TODO row sits above an IN-PROGRESS row -------------------------

if ($inProgress.Count -eq 1) {
    $cutoff = $inProgress[0].Line
    foreach ($row in ($rows | Where-Object { $_.Line -lt $cutoff -and $_.Status -eq 'TODO' })) {
        $errorList.Add("$ProgressPath line $($row.Line): row $($row.Id) is still TODO but sits above the IN-PROGRESS row $($inProgress[0].Id). Tasks run in order. Finish $($row.Id) first.")
    }
}

# --- rule: the Current task header matches the table -------------------------

$expectedCurrent = $null
if ($inProgress.Count -eq 1) {
    $expectedCurrent = $inProgress[0].Id
} else {
    $firstTodo = @($rows | Where-Object { $_.Status -eq 'TODO' }) | Select-Object -First 1
    if ($firstTodo) { $expectedCurrent = $firstTodo.Id }
}

$headerCurrent = $null
$headerMatch = [regex]::Match(($progressLines -join "`n"), '(?m)^\*\*Current task:\*\*\s*(\S+)\s*$')
if ($headerMatch.Success) {
    $headerCurrent = $headerMatch.Groups[1].Value
} elseif ($rows.Count -gt 0) {
    $errorList.Add("$ProgressPath has no '**Current task:**' header line. Add one naming the IN-PROGRESS task, or the first TODO task when none is running.")
}

if ($headerCurrent -and $expectedCurrent -and $headerCurrent -ne $expectedCurrent) {
    $errorList.Add("$ProgressPath says '**Current task:** $headerCurrent', but the table points at $expectedCurrent. Change the header to $expectedCurrent.")
}

# --- rule: an IN-PROGRESS row needs a log block with an Assumptions line ------

foreach ($row in $inProgress) {
    $blockMatch = [regex]::Match($logText, "(?ms)^## $($row.Id)\b.*?(?=^## T\d{3}\b|\z)")
    if (-not $blockMatch.Success) {
        $errorList.Add("$LogPath has no '## $($row.Id)' block, but $($row.Id) is IN-PROGRESS. Write the block, with its **Assumptions:** line, before doing the work.")
    } elseif ($blockMatch.Value -notmatch '(?m)^\*\*Assumptions:\*\*') {
        $errorList.Add("$LogPath block '## $($row.Id)' has no '**Assumptions:**' line. Add it. A resuming session reads it to understand why things are the way they are.")
    }
}

# --- report ------------------------------------------------------------------

$status = 'Valid'
if ($errorList.Count -gt 0) { $status = 'Invalid' }

$result = [pscustomobject]@{
    Status   = $status
    Errors   = @($errorList)
    Warnings = @($warningList)
    Details  = @{
        PlanPath      = $PlanPath
        ProgressPath  = $ProgressPath
        LogPath       = $LogPath
        PlanTaskCount = $planTasks.Count
        RowCount      = $rows.Count
        DoneCount     = @($rows | Where-Object { $_.Status -eq 'DONE' }).Count
        BlockedCount  = @($rows | Where-Object { $_.Status -eq 'BLOCKED' }).Count
        PendingCount  = $pendingRows.Count
        CurrentTask   = $expectedCurrent
    }
}

foreach ($message in $warningList) { Write-StdErr "WARNING: $message" }
foreach ($message in $errorList) { Write-StdErr "ERROR: $message" }
Write-StdErr "$($ProgressPath): $status. $($result.Details.RowCount) rows, $($result.Details.DoneCount) done, $($errorList.Count) errors, $($warningList.Count) warnings. Current task $expectedCurrent."

if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    $result
}

if ($errorList.Count -eq 0) { exit 0 } else { exit 1 }
