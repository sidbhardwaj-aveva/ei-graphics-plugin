#Requires -Version 7.0
<#
.SYNOPSIS
    One-command wrapper for the three-script story intake sequence.
.DESCRIPTION
    Runs Invoke-EiAdoCliIntake.ps1, pipes the result to Convert-EiAdoIntake.ps1, then to
    Write-EiArtifact.ps1 -ArtifactType ado. Returns one JSON object naming the artifact path
    and its hash.

    The wrapper never re-parses, re-shapes, or filters the JSON that flows between steps. Every
    attachment URL, every comment, every markdown hyperlink already collected by the underlying
    pipeline survives end to end. Stderr from every sub-script is forwarded to this script's
    stderr unaltered, so a failed download or an unreadable comment thread is still visible.
.PARAMETER WorkItem
    A work item reference. Accepts everything Invoke-EiAdoCliIntake.ps1 accepts: a URL, a
    markdown link, a pasted title such as "Bug 4965976 SR205 - ...", or a bare numeric id.
    A bare positive integer is forwarded as -WorkItemId; anything else is forwarded as
    -WorkItemUrl.
.PARAMETER StoryId
    The story number this intake belongs to. Passed to Convert-EiAdoIntake.ps1 and to
    Write-EiArtifact.ps1 so the artifact lands under .ei-session-logs/<StoryId>/.
.PARAMETER Root
    The folder that holds .ei-session-logs. Defaults to the current folder.
.PARAMETER Json
    Emit stdout as a JSON string instead of a PSCustomObject.
.PARAMETER Help
    Print this help and exit 0.
#>
[CmdletBinding()]
param(
    [string] $WorkItem,
    [string] $StoryId,
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

if (-not $WorkItem) {
    Write-Problem 'No -WorkItem was given. Pass an ADO work item URL, a markdown link, a pasted reference, or the numeric id.'
    exit 1
}
if (-not $StoryId) {
    Write-Problem 'No -StoryId was given. Pass the story number this intake belongs to.'
    exit 1
}

$scriptsFolder = $PSScriptRoot
$adoIntakeFolder = (Resolve-Path (Join-Path $scriptsFolder '..' '..' 'ei-azure-devops-cli-intake' 'scripts')).Path

$steps = [ordered]@{
    'Invoke-EiAdoCliIntake.ps1' = Join-Path $adoIntakeFolder  'Invoke-EiAdoCliIntake.ps1'
    'Convert-EiAdoIntake.ps1'   = Join-Path $scriptsFolder    'Convert-EiAdoIntake.ps1'
    'Write-EiArtifact.ps1'      = Join-Path $scriptsFolder    'Write-EiArtifact.ps1'
}
foreach ($name in $steps.Keys) {
    if (-not (Test-Path -LiteralPath $steps[$name] -PathType Leaf)) {
        Write-Problem "Missing dependency: $($steps[$name]). This wrapper expects the standard ei-graphics-core layout."
        exit 1
    }
}

# The intake script's reference parser routes an explicit numeric id ahead of a URL. Mirror
# that split so a bare number never has to be reparsed out of a URL.
$intakeArgs = @{ Json = $true }
if ($WorkItem -match '^\d+$') { $intakeArgs['WorkItemId'] = $WorkItem }
else                          { $intakeArgs['WorkItemUrl'] = $WorkItem }

$intakeJson = & $steps['Invoke-EiAdoCliIntake.ps1'] @intakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Problem "Step 1 failed: Invoke-EiAdoCliIntake.ps1 exited $LASTEXITCODE. Nothing was written."
    exit 1
}

$adoJson = & $steps['Convert-EiAdoIntake.ps1'] -IntakeJson ($intakeJson -join "`n") -StoryId $StoryId -Root $Root -Json
if ($LASTEXITCODE -ne 0) {
    Write-Problem "Step 2 failed: Convert-EiAdoIntake.ps1 exited $LASTEXITCODE. Nothing was written."
    exit 1
}

$writeResult = & $steps['Write-EiArtifact.ps1'] -StoryId $StoryId -ArtifactType 'ado' -InputJson ($adoJson -join "`n") -Root $Root -Json
if ($LASTEXITCODE -ne 0) {
    Write-Problem "Step 3 failed: Write-EiArtifact.ps1 exited $LASTEXITCODE. Nothing was written."
    exit 1
}

if ($Json) { $writeResult } else { $writeResult | ConvertFrom-Json }
exit 0
