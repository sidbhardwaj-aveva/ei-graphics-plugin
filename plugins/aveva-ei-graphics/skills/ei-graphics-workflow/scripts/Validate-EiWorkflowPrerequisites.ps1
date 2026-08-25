#!/usr/bin/env pwsh
<#
.SYNOPSIS
Preflight the tooling and cross-plugin capabilities that ei-graphics-workflow depends on.

.DESCRIPTION
Dependency metadata does not install a plugin, so the workflow verifies every required capability
before the first stage runs and fails closed when one is missing. Capabilities whose owning
implementation phase has not landed yet are reported as warnings, not silent passes.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [ValidateSet('A', 'B', 'C', 'D', 'E')][string]$Phase = 'A',
    [string]$StateDir = '',
    [string]$RequiredCapabilitiesPath = '',
    [string[]]$PluginSearchRoot = @(),
    [switch]$NoDefaultSearchRoots,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../../ei-workflow-state/scripts/helpers/EiWorkflowState.ps1"

$result = New-EiResult

if ([string]::IsNullOrWhiteSpace($RequiredCapabilitiesPath)) {
    $RequiredCapabilitiesPath = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'references' 'required-capabilities.json'))
}

if (-not (Test-Path -LiteralPath $RequiredCapabilitiesPath)) {
    $result = Add-EiError -Result $result -Code 'EIWF-CAPABILITIES-MISSING' -Message "Required-capabilities manifest not found at '$RequiredCapabilitiesPath'."
    Exit-EiResult -Result $result -Json:$Json
}

$manifest = Get-Content -LiteralPath $RequiredCapabilitiesPath -Raw | ConvertFrom-Json

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $result = Add-EiError -Result $result -Code 'EIWF-PWSH-VERSION' -Message "PowerShell 7 or later is required; found $($PSVersionTable.PSVersion)."
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    $result = Add-EiError -Result $result -Code 'EIWF-GIT-MISSING' -Message 'git was not found on PATH. Scope validation and commit stages cannot run without it.'
}
else {
    $insideWorkTree = $false
    try {
        Push-Location -LiteralPath $RepositoryRoot
        $insideWorkTree = ((git rev-parse --is-inside-work-tree 2>$null) -eq 'true')
    }
    catch {
        $insideWorkTree = $false
    }
    finally {
        Pop-Location
    }

    if (-not $insideWorkTree) {
        if ($Phase -ge 'C') {
            $result = Add-EiError -Result $result -Code 'EIWF-GIT-NO-REPO' -Message "'$RepositoryRoot' is not inside a git work tree."
        }
        else {
            $result = Add-EiWarning -Result $result -Message "'$RepositoryRoot' is not inside a git work tree; scope validation will block from Phase C onwards."
        }
    }

    $result = Set-EiDetail -Result $result -Name 'InsideWorkTree' -Value $insideWorkTree
}

# Local EI skills ship with this plugin, so they are resolved relative to this script.
$localSkillRoot = (Resolve-Path (Join-Path $PSScriptRoot (Join-Path '..' '..'))).Path

$searchRoots = [System.Collections.Generic.List[string]]::new()
foreach ($root in $PluginSearchRoot) {
    if (-not [string]::IsNullOrWhiteSpace($root)) { $searchRoots.Add($root) }
}

if (-not $NoDefaultSearchRoots) {
    $repoPluginsRoot = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path '..' '..')))
    if (Test-Path -LiteralPath $repoPluginsRoot) {
        $searchRoots.Add((Resolve-Path $repoPluginsRoot).Path)
    }

    $installGlobs = @(
        (Join-Path $HOME '.copilot/installed-plugins/*'),
        (Join-Path $HOME '.vscode/agent-plugins/*/*/*/plugins')
    )

    foreach ($glob in $installGlobs) {
        foreach ($directory in @(Get-ChildItem -Path $glob -Directory -ErrorAction SilentlyContinue)) {
            $searchRoots.Add($directory.FullName)
        }
    }
}

$searchRoots = @($searchRoots | Select-Object -Unique)
$result = Set-EiDetail -Result $result -Name 'SearchRoots' -Value $searchRoots

$found = [System.Collections.Generic.List[string]]::new()
$missingRequired = [System.Collections.Generic.List[object]]::new()
$missingLater = [System.Collections.Generic.List[string]]::new()

function Test-EiSkillPresent {
    param(
        [string[]]$Roots,
        [string]$Plugin,
        [string]$Skill
    )

    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath (Join-Path $root (Join-Path $Plugin (Join-Path 'skills' (Join-Path $Skill 'SKILL.md'))))) {
            return $true
        }
    }

    return $false
}

foreach ($capability in @($manifest.localSkills)) {
    $present = Test-Path -LiteralPath (Join-Path $localSkillRoot (Join-Path $capability.skill 'SKILL.md'))
    $label = "$($capability.plugin):$($capability.skill)"

    if ($present) {
        $found.Add($label)
        continue
    }

    if ($capability.required -and $capability.requiredFromPhase -le $Phase) {
        $missingRequired.Add([PSCustomObject]@{ plugin = $capability.plugin; skill = $capability.skill })
    }
    else {
        $missingLater.Add("$label (needed from Phase $($capability.requiredFromPhase))")
    }
}

foreach ($capability in @($manifest.capabilities)) {
    $present = Test-EiSkillPresent -Roots $searchRoots -Plugin $capability.plugin -Skill $capability.skill
    $label = "$($capability.plugin):$($capability.skill)"

    if ($present) {
        $found.Add($label)
        continue
    }

    if ($capability.required -and $capability.requiredFromPhase -le $Phase) {
        $missingRequired.Add([PSCustomObject]@{ plugin = $capability.plugin; skill = $capability.skill })
    }
    else {
        $missingLater.Add("$label (needed from Phase $($capability.requiredFromPhase))")
    }
}

foreach ($plugin in @($missingRequired | Select-Object -ExpandProperty plugin -Unique)) {
    $skills = @($missingRequired | Where-Object { $_.plugin -eq $plugin } | Select-Object -ExpandProperty skill) -join ', '
    $result = Add-EiError -Result $result -Code 'EIWF-DEPENDENCY-MISSING' -Message "$plugin is not installed. Install it from the marketplace and retry. Missing capabilities: $skills."
}

foreach ($later in $missingLater) {
    $result = Add-EiWarning -Result $result -Message "Capability not resolved yet: $later."
}

$result = Set-EiDetail -Result $result -Name 'Phase'              -Value $Phase
$result = Set-EiDetail -Result $result -Name 'Found'              -Value @($found)
$result = Set-EiDetail -Result $result -Name 'MissingRequired'    -Value @($missingRequired)
$result = Set-EiDetail -Result $result -Name 'MissingLaterPhase'  -Value @($missingLater)

# ── Candidate check: required before proposed-scope (Phase B+) ────────────────
# When a StateDir is provided the candidate artifact must exist and be structurally valid before
# the workflow may advance to the proposed-scope stage. Surfacing this here (rather than inside
# New-EiProposedScope.ps1 alone) allows the orchestrator to fail fast with a clear action message.
if ($Phase -ge 'B' -and -not [string]::IsNullOrWhiteSpace($StateDir)) {
    $candidatePath = Join-Path $StateDir 'candidate.json'
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        $result = Add-EiError -Result $result -Code 'EIWF-CANDIDATE-MISSING' `
            -Message "candidate.json was not found at '$candidatePath'. Run New-EiScopeCandidate.ps1 to generate it before starting the proposed-scope stage."
    }
    else {
        try {
            $c = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
            $hasMissing = [string]::IsNullOrWhiteSpace([string]($c.rationale)) -or
                          $null -eq $c.confidence -or
                          $null -eq $c.evidence -or
                          @($c.evidence).Count -eq 0
            if ($hasMissing) {
                $result = Add-EiError -Result $result -Code 'EIWF-CANDIDATE-INVALID' `
                    -Message "candidate.json at '$candidatePath' is missing required fields (confidence, rationale, evidence). Regenerate it with New-EiScopeCandidate.ps1."
            }
            else {
                $result = Set-EiDetail -Result $result -Name 'CandidatePath' -Value $candidatePath
            }
        }
        catch {
            $result = Add-EiError -Result $result -Code 'EIWF-CANDIDATE-INVALID' `
                -Message "candidate.json at '$candidatePath' is not valid JSON: $($_.Exception.Message)"
        }
    }
}

Exit-EiResult -Result $result -Json:$Json
