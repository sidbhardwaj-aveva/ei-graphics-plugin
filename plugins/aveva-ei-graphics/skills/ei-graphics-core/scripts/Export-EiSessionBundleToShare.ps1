#Requires -Version 7.0
<#
.SYNOPSIS
    Copies a completed EI Graphics session bundle to an approved review share.
.DESCRIPTION
    Copies the five session artifacts into a unique folder below SharePath. A share problem keeps
    the local bundle in place and exits 0, so the operator can retry after restoring access.
#>
[CmdletBinding()]
param(
    [string] $StoryId,
    [string] $Root = '.',
    [string] $SharePath,
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the completed session story number.'; exit 1 }
if ($StoryId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    Write-Problem "StoryId '$StoryId' is invalid. Use 1 to 64 letters, numbers, periods, underscores, or hyphens."
    exit 1
}
if (-not $SharePath) { Write-Problem 'No -SharePath was given. Set EI_GRAPHICS_SHARE_PATH to an approved internal share.'; exit 1 }

try { $rootPath = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path }
catch { Write-Problem "Cannot find Root '$Root'. Pass the repository root that holds .ei-session-logs."; exit 1 }

$bundlePath = Join-Path $rootPath '.ei-session-logs' $StoryId
$artifactNames = @('ado.json', 'story-understanding.json', 'approved-files.json', 'session.json', 'session-summary.md')
$missing = @($artifactNames | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bundlePath $_) -PathType Leaf) })
if ($missing.Count -gt 0) {
    Write-Problem "Session bundle for story $StoryId is incomplete at: $bundlePath"
    Write-Problem "Run the session workflow again to create: $($missing -join ', ')."
    exit 1
}

try { $session = Get-Content -LiteralPath (Join-Path $bundlePath 'session.json') -Raw | ConvertFrom-Json -ErrorAction Stop }
catch { Write-Problem "session.json for story $StoryId is invalid. Repair it before exporting the bundle."; exit 1 }
$summaryProperty = $session.PSObject.Properties['summary']
$completedAtProperty = if ($null -ne $summaryProperty) { $summaryProperty.Value.PSObject.Properties['completedAt'] }
if ($null -eq $summaryProperty -or $null -eq $summaryProperty.Value -or $null -eq $completedAtProperty -or -not $completedAtProperty.Value) {
    Write-Problem "session.json for story $StoryId is not finalized. Run Write-EiSessionEntry.ps1 with -Finalize first."
    exit 1
}

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ', [System.Globalization.CultureInfo]::InvariantCulture)
$folderName = "$StoryId-$stamp-$([guid]::NewGuid().ToString('N'))"
$targetPath = Join-Path $SharePath $folderName
$temporaryPath = Join-Path $SharePath ".$folderName.tmp"
$status = 'exported'
$exportedPath = $null

try {
    if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $SharePath -Force -ErrorAction Stop
    }
    $null = New-Item -ItemType Directory -Path $temporaryPath -ErrorAction Stop
    foreach ($name in $artifactNames) {
        Copy-Item -LiteralPath (Join-Path $bundlePath $name) -Destination (Join-Path $temporaryPath $name) -ErrorAction Stop
    }
    Move-Item -LiteralPath $temporaryPath -Destination $targetPath -ErrorAction Stop
    $exportedPath = $targetPath
} catch {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction SilentlyContinue }
    $status = 'retained-locally'
    Write-Problem "Cannot export story $StoryId to '$SharePath'. The local bundle remains at: $bundlePath"
    Write-Problem 'Restore access to the approved share, then rerun Export-EiSessionBundleToShare.ps1.'
}

$result = [pscustomobject]@{
    storyId      = $StoryId
    sourcePath   = $bundlePath
    status       = $status
    exportedPath = $exportedPath
}
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
exit 0