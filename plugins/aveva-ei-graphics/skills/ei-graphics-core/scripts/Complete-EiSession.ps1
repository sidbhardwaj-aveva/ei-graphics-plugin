#Requires -Version 7.0
<#
.SYNOPSIS
    One-command wrapper for the session-close sequence.
.DESCRIPTION
    Runs Write-EiSessionEntry.ps1 -Finalize -SessionOutcome, then Export-EiSessionSummary.ps1,
    and when EI_GRAPHICS_SHARE_PATH is set in the environment,
    Export-EiSessionBundleToShare.ps1 -SharePath $env:EI_GRAPHICS_SHARE_PATH.

    Returns one JSON object naming the summary path and, when the share export ran, the
    exported bundle path. A failure in finalize or summary exits 1 with the failing step named
    on stderr. A share-export failure is a warning on stderr, not fatal, so the local bundle
    remains usable and the operator can retry.

    The wrapper does not add its own session entries. It does not rewrite artifacts. It does
    not touch attachments, comments, or hyperlinks in ado.json or story-understanding.json.
    Stderr from every sub-script is forwarded unaltered.
.PARAMETER StoryId
    The story number this session belongs to. Passed to every sub-script so the bundle stays
    under .ei-session-logs/<StoryId>/.
.PARAMETER SessionOutcome
    Passed to Write-EiSessionEntry.ps1 as -SessionOutcome, populating summary.outcome.
.PARAMETER Root
    The folder that holds .ei-session-logs. Defaults to the current folder.
.PARAMETER Json
    Emit stdout as a JSON string instead of a PSCustomObject.
.PARAMETER Help
    Print this help and exit 0.
#>
[CmdletBinding()]
param(
    [string] $StoryId,
    [string] $SessionOutcome,
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

if (-not $StoryId) {
    Write-Problem 'No -StoryId was given. Pass the story number this session belongs to.'
    exit 1
}
if (-not $SessionOutcome) {
    Write-Problem 'No -SessionOutcome was given. Pass the outcome to record on the finalized session.'
    exit 1
}

$scriptsFolder = $PSScriptRoot

$steps = [ordered]@{
    'Write-EiSessionEntry.ps1'        = Join-Path $scriptsFolder 'Write-EiSessionEntry.ps1'
    'Export-EiSessionSummary.ps1'     = Join-Path $scriptsFolder 'Export-EiSessionSummary.ps1'
    'Export-EiSessionBundleToShare.ps1' = Join-Path $scriptsFolder 'Export-EiSessionBundleToShare.ps1'
}
foreach ($name in $steps.Keys) {
    if (-not (Test-Path -LiteralPath $steps[$name] -PathType Leaf)) {
        Write-Problem "Missing dependency: $($steps[$name]). This wrapper expects the standard ei-graphics-core layout."
        exit 1
    }
}

$finalizeJson = & $steps['Write-EiSessionEntry.ps1'] -StoryId $StoryId -Root $Root -Finalize -SessionOutcome $SessionOutcome -Json
if ($LASTEXITCODE -ne 0) {
    Write-Problem "Step 1 failed: Write-EiSessionEntry.ps1 exited $LASTEXITCODE. Nothing further was run."
    exit 1
}

$summaryJson = & $steps['Export-EiSessionSummary.ps1'] -StoryId $StoryId -Root $Root -Json
if ($LASTEXITCODE -ne 0) {
    Write-Problem "Step 2 failed: Export-EiSessionSummary.ps1 exited $LASTEXITCODE. Nothing further was run."
    exit 1
}

$summary = $summaryJson -join "`n" | ConvertFrom-Json
$summaryPath = $summary.path

$bundlePath = $null
$shareStatus = 'skipped'
$sharePath = $env:EI_GRAPHICS_SHARE_PATH
if ($sharePath) {
    $bundleJson = & $steps['Export-EiSessionBundleToShare.ps1'] -StoryId $StoryId -Root $Root -SharePath $sharePath -Json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $bundle = ($bundleJson | Where-Object { $_ -is [string] }) -join "`n" | ConvertFrom-Json
        $bundlePath = $bundle.exportedPath
        $shareStatus = $bundle.status
    } else {
        # Share export is a warning, not fatal. The finalized session is complete on disk.
        foreach ($line in $bundleJson) { if ($line -is [System.Management.Automation.ErrorRecord] -or $line -is [string]) { Write-Problem ($line.ToString()) } }
        Write-Problem "Warning: Export-EiSessionBundleToShare.ps1 exited $LASTEXITCODE. The local bundle remains usable; retry the share export directly."
        $shareStatus = 'failed'
    }
}

$result = [pscustomobject]@{
    storyId     = $StoryId
    summaryPath = $summaryPath
    bundlePath  = $bundlePath
    shareStatus = $shareStatus
}
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
exit 0
