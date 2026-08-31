#Requires -Version 7.0
<#
.SYNOPSIS
    Compares the files that changed against the files a person approved.
.DESCRIPTION
    Reads .ei-session-logs/<StoryId>/approved-files.json. Without -ChangedFiles it asks git for
    its diff plus any untracked files. Reports drift and exits 1 when something unapproved
    changed. An approved file nobody touched is reported, but it is only a warning.
#>
[CmdletBinding()]
param(
    [string] $StoryId,
    [string] $Root = '.',
    [string[]] $ChangedFiles,
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

function ConvertTo-ComparablePath {
    param([string[]] $Path)
    $clean = foreach ($item in $Path) {
        if (-not $item) { continue }
        ($item -replace '\\', '/') -replace '^\./', ''
    }
    , @($clean)
}

function Get-ChangedFromGit {
    param([string] $WorkingFolder)
    Push-Location -LiteralPath $WorkingFolder
    try {
        $tracked = @(git diff --name-only 2>$null) + @(git diff --name-only --cached 2>$null)
        $untracked = @(git ls-files --others --exclude-standard 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Problem "git could not report what changed in $WorkingFolder. Run this from inside a git repository, or pass -ChangedFiles."
            exit 1
        }
        , @($tracked + $untracked | Where-Object { $_ } | Sort-Object -Unique)
    } finally { Pop-Location }
}

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the story number this scope belongs to.'; exit 1 }

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$source = Join-Path $rootPath '.ei-session-logs' $StoryId 'approved-files.json'
if (-not (Test-Path -LiteralPath $source)) {
    Write-Problem "There is no approved file list for story $StoryId. Expected it at: $source"
    Write-Problem 'Write it with Write-EiArtifact.ps1 -ArtifactType approved-files before checking for drift.'
    exit 1
}

try { $approvedFiles = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json }
catch {
    Write-Problem "approved-files.json for story $StoryId is not valid JSON. $($_.Exception.Message)"
    exit 1
}

$approved = ConvertTo-ComparablePath -Path @($approvedFiles.files | ForEach-Object { $_.path })

# -ChangedFiles is the seam that keeps this testable. Without it, ask git.
$changed = $null
if ($PSBoundParameters.ContainsKey('ChangedFiles')) {
    $changed = ConvertTo-ComparablePath -Path $ChangedFiles
} else {
    $changed = ConvertTo-ComparablePath -Path (Get-ChangedFromGit -WorkingFolder $rootPath)
}

$unapproved = @($changed | Where-Object { $approved -cnotcontains $_ } | Sort-Object -Unique)
$approvedUnchanged = @($approved | Where-Object { $changed -cnotcontains $_ } | Sort-Object -Unique)

$status = 'pass'
if ($unapproved.Count -gt 0) { $status = 'drift' }

foreach ($path in $approvedUnchanged) {
    Write-Problem "Warning: $path was approved but never changed. That is allowed. Drop it from the list if you no longer plan to touch it."
}

if ($status -eq 'drift') {
    Write-Problem "Scope drift on story $StoryId. These files changed but nobody approved them:"
    foreach ($path in $unapproved) { Write-Problem "  $path" }
    Write-Problem 'Either revert them, or agree the wider scope with a person and write a new approved-files.json.'
}

$result = [pscustomobject]@{
    status            = $status
    storyId           = $StoryId
    unapproved        = $unapproved
    approvedUnchanged = $approvedUnchanged
}

if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
if ($status -eq 'pass') { exit 0 } else { exit 1 }
