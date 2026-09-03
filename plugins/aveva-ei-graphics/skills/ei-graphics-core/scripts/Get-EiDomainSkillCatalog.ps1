#Requires -Version 7.0
<#
.SYNOPSIS
    Lists the domain skills this plugin ships, with enough detail to shortlist one.
.DESCRIPTION
    Reads references/domain-skill-registry.json, then reads only the front of each skill
    document: the description in its frontmatter, and the bullets under '## When to Use'.
    The rest of the skill body is never read.
#>
[CmdletBinding()]
param(
    [string] $RegistryPath = (Join-Path $PSScriptRoot '..' 'references' 'domain-skill-registry.json'),
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

function Get-Description {
    <#
    .SYNOPSIS
        Reads the description out of a skill document's frontmatter.
    .DESCRIPTION
        Handles a plain value and a folded block written with '>', where the text sits on the
        indented lines below the key.
    #>
    # Mandatory is left off on purpose: on a string array it rejects every empty element.
    param([string[]] $Frontmatter)

    for ($i = 0; $i -lt $Frontmatter.Count; $i++) {
        if ($Frontmatter[$i] -notmatch '^description:\s*(.*)$') { continue }
        $head = $Matches[1].Trim()
        if ($head -and $head -notin @('>', '|', '>-', '|-')) { return $head }
        $folded = [System.Collections.Generic.List[string]]::new()
        for ($j = $i + 1; $j -lt $Frontmatter.Count; $j++) {
            if ($Frontmatter[$j] -notmatch '^\s+\S') { break }
            $folded.Add($Frontmatter[$j].Trim())
        }
        return ($folded -join ' ').Trim()
    }
    ''
}

function Get-WhenToUse {
    param([string[]] $Lines)

    $bullets = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in $Lines) {
        if ($line -match '^##\s+When to Use\s*$') { $inSection = $true; continue }
        if (-not $inSection) { continue }
        if ($line -match '^#{1,6}\s') { break }
        if ($line -match '^\s*[-*+]\s+(.*\S)\s*$') { $bullets.Add($Matches[1].Trim()) }
    }
    , $bullets.ToArray()
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    Write-Problem "The domain skill registry is missing. Expected it at: $RegistryPath"
    Write-Problem 'Check the path, or restore references/domain-skill-registry.json.'
    exit 1
}

try { $registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json }
catch {
    Write-Problem "The domain skill registry is not valid JSON: $RegistryPath"
    Write-Problem "  $($_.Exception.Message)"
    exit 1
}

$registryFolder = (Resolve-Path -LiteralPath (Split-Path -Parent $RegistryPath)).Path
# Normalised without touching the disk, so a fixture registry outside the plugin still resolves.
$pluginRoot = [System.IO.Path]::GetFullPath((Join-Path $registryFolder '..' '..' '..'))
$skills = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($domain in @($registry.domains)) {
    $skillPath = Join-Path $pluginRoot $domain.skillPath
    if (-not (Test-Path -LiteralPath $skillPath)) {
        Write-Problem "The registry lists the domain '$($domain.id)', but its skill document is missing."
        Write-Problem "  Expected it at: $skillPath"
        Write-Problem "  Fix the skillPath in $RegistryPath, or add the missing skill document."
        exit 1
    }

    $lines = @(Get-Content -LiteralPath $skillPath)
    $fence = @()
    if ($lines.Count -gt 0) { $fence = @(0..($lines.Count - 1) | Where-Object { $lines[$_].Trim() -eq '---' }) }
    if ($fence.Count -lt 2 -or $fence[0] -ne 0) {
        Write-Problem "The skill document for '$($domain.id)' has no frontmatter block."
        Write-Problem "  File: $skillPath"
        Write-Problem '  Add a block fenced by --- at the top, holding a name and a description.'
        exit 1
    }

    $description = Get-Description -Frontmatter $lines[1..($fence[1] - 1)]
    if (-not $description) {
        Write-Problem "The frontmatter for '$($domain.id)' has no description."
        Write-Problem "  File: $skillPath"
        Write-Problem '  Add a description line. The agent uses it to decide whether to read the skill.'
        exit 1
    }

    $skills.Add([pscustomobject]@{
        domainId    = $domain.id
        displayName = $domain.displayName
        skillPath   = $domain.skillPath
        description = $description
        whenToUse   = Get-WhenToUse -Lines $lines
    })
}

$result = [pscustomobject]@{ skills = $skills.ToArray() }
if ($Json) { $result | ConvertTo-Json -Depth 10 } else { $result }
exit 0
