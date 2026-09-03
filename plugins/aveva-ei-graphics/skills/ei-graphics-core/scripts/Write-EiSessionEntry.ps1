#Requires -Version 7.0
<#
.SYNOPSIS
    Appends one entry to the session log, or closes the session with a summary.

.DESCRIPTION
    Writes .ei-session-logs/<StoryId>/session.json. The first call creates the envelope. Later
    calls append one entry each. -Finalize instead adds the summary block, working out the parts
    it can from the entries already written.
#>
[CmdletBinding(DefaultParameterSetName = 'Append')]
param(
    [string] $StoryId,
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help,

    [Parameter(ParameterSetName = 'Append')] [string] $Phase,
    [Parameter(ParameterSetName = 'Append')] [string] $Action,
    [Parameter(ParameterSetName = 'Append')] [string] $Reasoning,
    [Parameter(ParameterSetName = 'Append')] [string] $Outcome,
    [Parameter(ParameterSetName = 'Append')] [Nullable[int]] $DurationMs,
    [Parameter(ParameterSetName = 'Append')] [Nullable[int]] $TokensUsed,
    [Parameter(ParameterSetName = 'Append')] [string[]] $FilesRead,
    [Parameter(ParameterSetName = 'Append')] [string[]] $FilesModified,
    [Parameter(ParameterSetName = 'Append')] [string] $HumanInput,
    [Parameter(ParameterSetName = 'Append')] $ScriptOutput,
    [Parameter(ParameterSetName = 'Append')] [object[]] $Evidence,

    [Parameter(ParameterSetName = 'Finalize', Mandatory = $true)] [switch] $Finalize,
    [Parameter(ParameterSetName = 'Finalize')] [Nullable[int]] $TestsRun,
    [Parameter(ParameterSetName = 'Finalize')] [Nullable[int]] $TestsPassed,
    [Parameter(ParameterSetName = 'Finalize')] [Nullable[int]] $HumanInteractions,
    [Parameter(ParameterSetName = 'Finalize')] [string] $SessionOutcome,
    [Parameter(ParameterSetName = 'Finalize')] [string] $DomainSkillUsed,
    [Parameter(ParameterSetName = 'Finalize')] [string] $BugPatternMatched,
    [Parameter(ParameterSetName = 'Finalize')] [object[]] $CommentDeviations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

function Get-UtcStamp {
    (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-PlainValue {
    <#
    .SYNOPSIS
        Turns any date ConvertFrom-Json produced back into the timestamp string we wrote.
    #>
    param($Node)
    if ($Node -is [datetime]) {
        return $Node.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Node -is [datetimeoffset]) {
        return $Node.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Node -is [string] -or $null -eq $Node) { return $Node }
    if ($Node -is [System.Collections.IDictionary]) {
        $plain = [ordered]@{}
        foreach ($key in @($Node.Keys)) { $plain[$key] = ConvertTo-PlainValue -Node $Node[$key] }
        return $plain
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        $items = @(foreach ($item in $Node) { ConvertTo-PlainValue -Node $item })
        return , $items
    }
    $Node
}

function Save-Session {
    <#
    .SYNOPSIS
        Writes the session log through a temporary file, so a second call cannot truncate it.
    #>
    param([Parameter(Mandatory)] $Session, [Parameter(Mandatory)] [string] $Path)
    $body = ($Session | ConvertTo-Json -Depth 30) -replace "`r`n", "`n"
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($temporary, $body + "`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function ConvertTo-EvidenceItem {
    <#
    .SYNOPSIS
        Turns one evidence item into the four keys the schema allows, whatever shape it arrived in.
    #>
    param($Item, [int] $Position)

    $read = { param([string] $Key)
        if ($Item -is [System.Collections.IDictionary]) { if ($Item.Contains($Key)) { return $Item[$Key] } ; return $null }
        if ($Item.PSObject.Properties.Name -contains $Key) { return $Item.$Key }
        $null
    }

    $file = & $read 'file'
    if (-not $file) {
        Write-Problem "Evidence item $Position has no 'file'. Every piece of evidence names the file it came from. Add file, and optionally line, symbol and quote."
        exit 1
    }

    $plain = [ordered]@{ file = [string] $file }
    foreach ($key in @('line', 'symbol', 'quote')) {
        $value = & $read $key
        if ([string]::IsNullOrEmpty([string] $value)) { continue }
        if ($key -eq 'line') { $plain[$key] = [int] $value } else { $plain[$key] = [string] $value }
    }
    $plain
}

function ConvertTo-CommentDeviation {
    <#
    .SYNOPSIS
        Turns one comment deviation into the two keys the schema allows, whatever shape it arrived in.
    #>
    param($Item, [int] $Position)

    $read = { param([string] $Key)
        if ($Item -is [System.Collections.IDictionary]) { if ($Item.Contains($Key)) { return $Item[$Key] } ; return $null }
        if ($Item.PSObject.Properties.Name -contains $Key) { return $Item.$Key }
        $null
    }

    $commentId = & $read 'commentId'
    $effect = & $read 'effect'
    if ([string]::IsNullOrEmpty([string] $commentId) -or [string]::IsNullOrEmpty([string] $effect)) {
        Write-Problem "Comment deviation $Position needs both 'commentId' and 'effect'. Each records which comment changed the story, and what it changed."
        exit 1
    }
    [ordered]@{ commentId = [string] $commentId; effect = [string] $effect }
}

$schemaPath = Join-Path $PSScriptRoot '..' 'schemas' 'session.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath)) {
    Write-Problem "session.schema.json is missing. Expected it at: $schemaPath"
    exit 1
}
$schemaText = Get-Content -LiteralPath $schemaPath -Raw
$schema = $schemaText | ConvertFrom-Json
$validPhases = @($schema.properties.entries.items.properties.phase.enum)

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the story number this session belongs to.'; exit 1 }

$folder = Join-Path (Resolve-Path -LiteralPath $Root).Path '.ei-session-logs' $StoryId
if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
$target = Join-Path $folder 'session.json'

if (Test-Path -LiteralPath $target) {
    try { $session = ConvertTo-PlainValue -Node (Get-Content -LiteralPath $target -Raw | ConvertFrom-Json -AsHashtable) }
    catch { Write-Problem "session.json for story $StoryId is not valid JSON. Move it aside and start again. $($_.Exception.Message)"; exit 1 }
} else {
    $session = [ordered]@{
        schemaVersion = '1.0.0'
        storyId       = $StoryId
        startedAt     = Get-UtcStamp
        agent         = 'ei-graphics'
        verbosity     = 'verbose'
        entries       = @()
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Finalize') {
    $entries = @($session['entries'])
    $durations = @($entries | ForEach-Object { if ($_.Contains('durationMs')) { $_['durationMs'] } } | Where-Object { $null -ne $_ })
    $tokens = @($entries | ForEach-Object { if ($_.Contains('tokensUsed')) { $_['tokensUsed'] } } | Where-Object { $null -ne $_ })
    $touched = @($entries | ForEach-Object { if ($_.Contains('filesModified')) { $_['filesModified'] } })

    $summary = [ordered]@{
        completedAt   = Get-UtcStamp
        filesModified = @($touched | Where-Object { $_ } | Sort-Object -Unique)
    }
    # Omitted, not zeroed, when nothing recorded a value. A measured zero and no measurement at all
    # are different things, and the summary must never present the second as the first.
    if ($durations.Count -gt 0) { $summary['totalDurationMs'] = [int](($durations | Measure-Object -Sum).Sum) }
    if ($tokens.Count -gt 0) { $summary['totalTokens'] = [int](($tokens | Measure-Object -Sum).Sum) }
    if ($null -ne $TestsRun) { $summary['testsRun'] = [int] $TestsRun }
    if ($null -ne $TestsPassed) { $summary['testsPassed'] = [int] $TestsPassed }
    if ($null -ne $HumanInteractions) { $summary['humanInteractions'] = [int] $HumanInteractions }
    if ($SessionOutcome) { $summary['outcome'] = $SessionOutcome }
    if ($DomainSkillUsed) { $summary['domainSkillUsed'] = $DomainSkillUsed }
    if ($BugPatternMatched) { $summary['bugPatternMatched'] = $BugPatternMatched }
    if ($CommentDeviations) {
        $items = @(for ($i = 0; $i -lt $CommentDeviations.Count; $i++) { ConvertTo-CommentDeviation -Item $CommentDeviations[$i] -Position ($i + 1) })
        $summary['commentDeviations'] = @($items)
    }
    $session['summary'] = $summary
    $written = $summary
} else {
    if (-not $Phase) { Write-Problem "No -Phase was given. Use one of: $($validPhases -join ', ')."; exit 1 }
    if ($validPhases -notcontains $Phase) {
        Write-Problem "'$Phase' is not a phase session.schema.json knows. Use one of: $($validPhases -join ', ')."
        exit 1
    }
    if (-not $Action) { Write-Problem 'No -Action was given. Say in a few words what this step did.'; exit 1 }
    if (-not $Outcome) { Write-Problem 'No -Outcome was given. Say what came of the step.'; exit 1 }

    $entry = [ordered]@{
        timestamp  = Get-UtcStamp
        phase      = $Phase
        action     = $Action
        reasoning  = $null
        outcome    = $Outcome
        durationMs = $null
        tokensUsed = $null
    }
    if ($Reasoning) { $entry['reasoning'] = $Reasoning }
    if ($null -ne $DurationMs) { $entry['durationMs'] = [int] $DurationMs }
    if ($null -ne $TokensUsed) { $entry['tokensUsed'] = [int] $TokensUsed }
    if ($FilesRead) { $entry['filesRead'] = @($FilesRead) }
    if ($FilesModified) { $entry['filesModified'] = @($FilesModified) }
    if ($HumanInput) { $entry['humanInput'] = $HumanInput }
    if ($null -ne $ScriptOutput) { $entry['scriptOutput'] = $ScriptOutput }
    if ($Evidence) {
        $items = @(for ($i = 0; $i -lt $Evidence.Count; $i++) { ConvertTo-EvidenceItem -Item $Evidence[$i] -Position ($i + 1) })
        $entry['evidence'] = @($items)
    }

    $session['entries'] = @(@($session['entries']) + $entry)
    $written = $entry
}

$body = ($session | ConvertTo-Json -Depth 30) -replace "`r`n", "`n"
try { $null = $body | Test-Json -Schema $schemaText -ErrorAction Stop }
catch {
    Write-Problem "The session log for story $StoryId would no longer match session.schema.json:"
    Write-Problem "  $($_.Exception.Message)"
    Write-Problem 'Nothing was written. Fix the values you passed and run this script again.'
    exit 1
}

Save-Session -Session $session -Path $target

$result = [pscustomobject]@{
    path       = $target
    storyId    = $StoryId
    entryCount = @($session['entries']).Count
    written    = $written
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result }
exit 0
