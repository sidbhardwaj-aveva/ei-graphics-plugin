#Requires -Version 7.0
<#
.SYNOPSIS
    Turns the name of a core script into the absolute path of the installed file.
.DESCRIPTION
    Resolves the ei-graphics-core scripts folder from -ScriptRoot, which defaults to the folder
    this script sits in. With -Name it returns that one script. Without -Name it checks the whole
    roster and names anything missing. A folder that is not the installed scripts folder fails,
    so a path built by hand that leaves out plugins\aveva-ei-graphics cannot quietly succeed.
.EXAMPLE
    & "$pluginRoot\plugins\aveva-ei-graphics\skills\ei-graphics-core\scripts\Resolve-EiScriptPath.ps1"
    Checks the roster before the session writes its first entry.
#>
[CmdletBinding()]
param(
    [string] $Name,
    [string] $ScriptRoot = $PSScriptRoot,
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

# The roster is every script a session calls by path. The doctor is not here on purpose: it lives
# in another skill and is always started by the person, never by a resolved path.
$roster = @(
    'Complete-EiSession.ps1'
    'Convert-EiAdoIntake.ps1'
    'Export-EiSessionBundleToShare.ps1'
    'Export-EiSessionSummary.ps1'
    'Get-EiDomainSkillCatalog.ps1'
    'Invoke-EiStoryIntake.ps1'
    'Resolve-EiScriptPath.ps1'
    'Test-EiScopeDrift.ps1'
    'Write-EiArtifact.ps1'
    'Write-EiSessionEntry.ps1'
)

$expectedTail = Join-Path 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts'

if (-not (Test-Path -LiteralPath $ScriptRoot)) {
    Write-Problem "There is no folder at: $ScriptRoot"
    Write-Problem "Pass -ScriptRoot the scripts folder of the installed plugin, ending $expectedTail."
    exit 1
}

$resolvedRoot = (Resolve-Path -LiteralPath $ScriptRoot).Path
if (-not $resolvedRoot.TrimEnd('\', '/').EndsWith($expectedTail, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Problem "This is not the core scripts folder: $resolvedRoot"
    Write-Problem "A core scripts path ends $expectedTail. Rebuild it from the plugin install root instead of by hand."
    exit 1
}

$missing = @($roster | Where-Object { -not (Test-Path -LiteralPath (Join-Path $resolvedRoot $_)) })
if ($missing.Count -gt 0) {
    Write-Problem "The installed plugin is incomplete at: $resolvedRoot"
    foreach ($item in $missing) { Write-Problem "  missing: $item" }
    Write-Problem 'Reinstall the plugin, or run the doctor, then start the session again.'
    exit 1
}

if ($Name) {
    $leaf = if ($Name.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) { $Name } else { "$Name.ps1" }
    if ($roster -notcontains $leaf) {
        Write-Problem "$leaf is not a core script. The core scripts are:"
        foreach ($item in $roster) { Write-Problem "  $item" }
        exit 1
    }
    $result = [pscustomobject]@{
        status      = 'resolved'
        name        = $leaf
        path        = (Join-Path $resolvedRoot $leaf)
        scriptsRoot = $resolvedRoot
    }
} else {
    $result = [pscustomobject]@{
        status      = 'complete'
        scriptsRoot = $resolvedRoot
        scripts     = @($roster | ForEach-Object { Join-Path $resolvedRoot $_ })
    }
}

if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
exit 0
