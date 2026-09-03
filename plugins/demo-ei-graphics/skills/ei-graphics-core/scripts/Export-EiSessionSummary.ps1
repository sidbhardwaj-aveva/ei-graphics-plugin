#Requires -Version 7.0
<#
.SYNOPSIS
    Renders session-summary.md from session.json, for a person to read.
.DESCRIPTION
    Reads .ei-session-logs/<StoryId>/session.json and writes session-summary.md beside it. How
    much detail it writes comes from the verbosity field inside the log, not from a parameter.
#>
[CmdletBinding()]
param(
    [string] $StoryId,
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$phaseNames = @{
    'ado-intake' = 'Intake'; 'understanding' = 'Understanding'; 'human-checkpoint' = 'Checkpoint'
    'complexity' = 'Complexity'; 'implementation' = 'Implementation'; 'validation' = 'Validation'
    'commit' = 'Commit'
}

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }
function Add-Plural { param([int] $Count, [string] $Word) if ($Count -eq 1) { "1 $Word" } else { "$Count ${Word}s" } }
function Get-Text { param($Value, [string] $Fallback = 'not recorded') if ($Value) { $Value } else { $Fallback } }

function Get-Field {
    param($Owner, [string] $Name)
    if ($null -eq $Owner) { return $null }
    if ($Owner.PSObject.Properties.Name -notcontains $Name) { return $null }
    $Owner.$Name
}

function Format-Duration {
    param([Nullable[int]] $Milliseconds)
    if ($null -eq $Milliseconds) { return 'not recorded' }
    $total = [int][math]::Round($Milliseconds / 1000)
    $parts = @()
    if ($total -ge 3600) { $parts += "$([int][math]::Floor($total / 3600))h"; $total = $total % 3600 }
    if ($total -ge 60 -or $parts.Count -gt 0) { $parts += "$([int][math]::Floor($total / 60))m"; $total = $total % 60 }
    ($parts + "${total}s") -join ' '
}

function Get-Moment {
    # ConvertFrom-Json turns a Z timestamp into a UTC DateTime, so handle both forms.
    param($Value)
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    [datetime]::Parse([string] $Value, $invariant, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
}

function Get-Clock { param($Timestamp) (Get-Moment -Value $Timestamp).ToString('HH:mm:ss', $invariant) }

function Get-EvidenceLine {
    <#
    .SYNOPSIS
        Renders one entry's evidence: a link to each file, and the text that was read beneath it.
    .DESCRIPTION
        The link climbs two folders, because the summary sits at .ei-session-logs/<storyId>/ and
        the recorded paths start at the repository root. The quote goes in a fenced block at the
        left margin: quoted source is not our prose, and the Part 3 rules skip fenced blocks.
    #>
    param($Entry)

    # @($null) is an array of one, so a missing field has to be tested before it is wrapped.
    $items = @((Get-Field -Owner $Entry -Name 'evidence') | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return , @() }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('**Evidence**'); $lines.Add('')
    foreach ($item in $items) {
        $file = [string] (Get-Field -Owner $item -Name 'file')
        $line = Get-Field -Owner $item -Name 'line'
        $symbol = Get-Field -Owner $item -Name 'symbol'
        $quote = Get-Field -Owner $item -Name 'quote'

        $target = '../../' + ($file -replace '\\', '/')
        $label = Split-Path -Leaf $file
        if ($null -ne $line) { $target = "${target}#L$line"; $label = "${label}:$line" }
        $bullet = "- [``$label``]($target)"
        if ($symbol) { $bullet = "$bullet — ``$symbol``" }
        $lines.Add($bullet)

        if ($quote) {
            $lines.Add('')
            $lines.Add('```text')
            foreach ($row in ([string] $quote -split '\r?\n')) { $lines.Add($row) }
            $lines.Add('```')
            $lines.Add('')
        }
    }
    if ($lines[$lines.Count - 1] -ne '') { $lines.Add('') }
    , $lines.ToArray()
}

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the story number this session belongs to.'; exit 1 }

$folder = Join-Path (Resolve-Path -LiteralPath $Root).Path '.ei-session-logs' $StoryId
$source = Join-Path $folder 'session.json'
if (-not (Test-Path -LiteralPath $source)) {
    Write-Problem "There is no session log for story $StoryId. Expected it at: $source"
    Write-Problem 'Run Write-EiSessionEntry.ps1 at least once before rendering a summary.'
    exit 1
}

$schemaPath = Join-Path $PSScriptRoot '..' 'schemas' 'session.schema.json'
$raw = Get-Content -LiteralPath $source -Raw
try { $null = $raw | Test-Json -Schema (Get-Content -LiteralPath $schemaPath -Raw) -ErrorAction Stop }
catch {
    Write-Problem "The session log for story $StoryId does not match session.schema.json:"
    Write-Problem "  $($_.Exception.Message)"
    Write-Problem 'Fix the log before rendering a summary. Nothing was written.'
    exit 1
}

$session = $raw | ConvertFrom-Json
$entries = @(Get-Field -Owner $session -Name 'entries')
$summary = Get-Field -Owner $session -Name 'summary'
$concise = (Get-Field -Owner $session -Name 'verbosity') -eq 'concise'

$domain = Get-Field -Owner $summary -Name 'domainSkillUsed'
$pattern = Get-Field -Owner $summary -Name 'bugPatternMatched'
$outcome = Get-Field -Owner $summary -Name 'outcome'
$tokens = Get-Field -Owner $summary -Name 'totalTokens'
$filesChanged = @(Get-Field -Owner $summary -Name 'filesModified')
$testsRun = Get-Field -Owner $summary -Name 'testsRun'
$testsPassed = Get-Field -Owner $summary -Name 'testsPassed'

$filesRead = @($entries | ForEach-Object { Get-Field -Owner $_ -Name 'filesRead' } |
    Where-Object { $_ } | Sort-Object -Unique)
# The agent's own artifacts and its own skills can never belong in a Key Files table.
$sourceRead = @($filesRead | Where-Object { $_ -notmatch '^(\.ei-session-logs|plugins)[\\/]' })

$waitSeconds = 0
$pauses = 0
for ($i = 0; $i -lt $entries.Count - 1; $i++) {
    if ($entries[$i].phase -ne 'human-checkpoint') { continue }
    if (Get-Field -Owner $entries[$i] -Name 'humanInput') { continue }
    $waitSeconds += [int]((Get-Moment $entries[$i + 1].timestamp) - (Get-Moment $entries[$i].timestamp)).TotalSeconds
    $pauses++
}

$lines = [System.Collections.Generic.List[string]]::new()
$out = { param([string] $Line) $lines.Add($Line) }

$tokenText = 'not recorded'
if ($null -ne $tokens) { $tokenText = ([int] $tokens).ToString('N0', $invariant) }
$domainText = 'not recorded'
if ($domain) { $domainText = "``$domain``" }

& $out "# Session: story $StoryId"
& $out ''
& $out "**Duration:** $(Format-Duration (Get-Field -Owner $summary -Name 'totalDurationMs')) | **Tokens:** $tokenText"
& $out "**Domain:** $domainText | **Pattern:** $(Get-Text $pattern)"
& $out "**Outcome:** $(Get-Text $outcome)"
& $out ''; & $out '## Timeline'; & $out ''

$shown = $entries
if ($concise) {
    # One row per phase, showing the last entry of that phase, in the order the phases first ran.
    $shown = @($entries | Group-Object -Property phase | ForEach-Object { $_.Group[-1] } |
        Sort-Object -Property timestamp)
}

if ($shown.Count -eq 0) {
    & $out 'No steps were recorded.'
} else {
    & $out '| Time | Phase | What happened |'; & $out '|------|-------|---------------|'
    foreach ($entry in $shown) {
        & $out "| $(Get-Clock $entry.timestamp) | $($phaseNames[$entry.phase]) | $($entry.outcome) |"
    }
}
& $out ''

if (-not $concise) {
    & $out '## Agent Reasoning Trail'; & $out ''
    $reasoned = @($entries | Where-Object { Get-Field -Owner $_ -Name 'reasoning' })
    if ($reasoned.Count -eq 0) { & $out 'No reasoning was recorded.'; & $out '' }
    foreach ($entry in $reasoned) {
        & $out "### $($phaseNames[$entry.phase]) — $($entry.action)"; & $out ''
        & $out "> $($entry.reasoning)"; & $out ''
        foreach ($line in (Get-EvidenceLine -Entry $entry)) { & $out $line }
    }
}

$coverage = 'No domain skill was recorded. If this story belongs to a domain, its skill is missing, or the agent did not match it.'
if ($domain -and $pattern) { $coverage = "The ``$domain`` skill was used. It matched the bug pattern named $pattern." }
elseif ($domain) { $coverage = "The ``$domain`` skill was used. No bug pattern matched, so this may be new ground for that skill." }

$corrections = @((Get-Field -Owner $summary -Name 'commentDeviations') | Where-Object { $null -ne $_ })
$correctionLine = 'None recorded.'
if ($corrections.Count -gt 0) {
    $parts = $corrections | ForEach-Object {
        $id = [string] (Get-Field -Owner $_ -Name 'commentId')
        "comment ``$id``: $([string] (Get-Field -Owner $_ -Name 'effect'))"
    }
    $correctionLine = $parts -join ' '
}

$opportunity = 'No source file was read, so there is nothing to compare against the skill.'
if ($sourceRead.Count -gt 0) {
    $named = ($sourceRead | ForEach-Object { "``$_``" }) -join ', '
    $it = 'them'; if ($sourceRead.Count -eq 1) { $it = 'it' }
    $opportunity = "The agent read $(Add-Plural $sourceRead.Count 'source file'). Check $it against the Key Files table in the skill, and add any that are missing: $named."
}

$wait = 'None recorded.'
if ($pauses -gt 0) { $wait = "$(Format-Duration ($waitSeconds * 1000)), across $(Add-Plural $pauses 'pause')." }

$efficiency = "$(Add-Plural $filesRead.Count 'file') read, $(Add-Plural $filesChanged.Count 'file') changed. No test run was recorded."
if ($null -ne $testsRun -and $null -ne $testsPassed) {
    $efficiency = "$(Add-Plural $filesRead.Count 'file') read, $(Add-Plural $filesChanged.Count 'file') changed, and $testsPassed of $testsRun tests passed."
}

& $out '## For the maintainer'; & $out ''
& $out "- **Skill coverage:** $coverage"
& $out "- **Comment corrections:** $correctionLine"
& $out "- **Improvement opportunity:** $opportunity"
& $out "- **Human wait time:** $wait"
& $out "- **Agent efficiency:** $efficiency"

$target = Join-Path $folder 'session-summary.md'
[System.IO.File]::WriteAllText($target, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))

$result = [pscustomobject]@{ path = $target; storyId = $StoryId; verbosity = (Get-Field -Owner $session -Name 'verbosity') }
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
exit 0
