#Requires -Version 7.0
Set-StrictMode -Version Latest

<#
    The Part 3 plain-language rules, in one place.

    T006 runs them over the files a person reads in this repository. T009 runs them over the
    session summary it renders, which never exists on disk and so cannot be scanned by T006.
    Keeping the rules here means the two tasks cannot drift apart.
#>

# Named in Part 3. AVEVA is added because it is a company name, not an acronym, and there is no
# expansion to write for it.
$script:DefaultExemptAcronyms = @('ADO', 'CLI', 'JSON', 'PR', 'YAML', 'SHA', 'MD', 'AVEVA')

function Get-PlainLanguageText {
    <#
    .SYNOPSIS
        Reduces markdown to the prose a person actually reads.
    #>
    param([Parameter(Mandatory)] [string] $Markdown)

    $body = $Markdown
    $frontmatterProse = ''
    $frontmatter = [regex]::Match($Markdown, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')
    if ($frontmatter.Success) {
        $body = $Markdown.Substring($frontmatter.Length)
        $frontmatterProse = ($frontmatter.Groups[1].Value -split '\r?\n' |
            ForEach-Object { $_ -replace '^\s*[A-Za-z_][\w-]*:\s*', '' }) -join "`n"
    }

    $text = $frontmatterProse + "`n" + $body
    $text = [regex]::Replace($text, '(?ms)^```.*?^```[^\n]*$', '')   # fenced code blocks
    $text = [regex]::Replace($text, '\]\([^)]*\)', ']')              # link targets, keep link text
    $text
}

function Remove-InlineCode {
    param([Parameter(Mandatory)] [string] $Text)
    [regex]::Replace($Text, '`[^`]*`', ' ')
}

function Get-ProseSentence {
    <#
    .SYNOPSIS
        Splits prose into sentences, after dropping headings, tables and list markers.
    #>
    param([Parameter(Mandatory)] [string] $Text)

    $lines = $Text -split '\r?\n' | Where-Object {
        $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*\|' -and $_ -notmatch '^\s*-{3,}\s*$'
    }
    $prose = ($lines -join ' ') -replace '\*+', '' -replace '^\s*[-*+]\s+', ' '
    $prose = $prose -replace '\s+', ' '

    $prose -split '(?<=[.!?])\s+' | Where-Object { $_ -match '\S' }
}

function Get-PlainLanguageProblem {
    <#
    .SYNOPSIS
        Applies the four Part 3 rules to one markdown file and returns what it found.

    .DESCRIPTION
        Returns one object per problem, with a Rule, the File, and a Detail naming what to change.
        An empty result means the file passes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string[]] $JargonTerm,
        [int] $MaxSentenceWords = 25,
        [string[]] $ExemptAcronym = $script:DefaultExemptAcronyms
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Get-PlainLanguageProblem was given a path that does not exist: $Path"
    }
    if ($JargonTerm.Count -eq 0) {
        throw 'Get-PlainLanguageProblem was given an empty jargon list. Check tests/data/jargon-terms.txt.'
    }

    $name = Split-Path -Leaf $Path
    $problems = [System.Collections.Generic.List[pscustomobject]]::new()
    $add = {
        param($rule, $detail)
        $problems.Add([pscustomobject]@{ Rule = $rule; File = $name; Detail = $detail })
    }

    $text = Get-PlainLanguageText -Markdown (Get-Content -LiteralPath $Path -Raw)
    $prose = Remove-InlineCode -Text $text

    # Rule 1 - sentences of 25 words or fewer.
    foreach ($sentence in (Get-ProseSentence -Text $prose)) {
        $words = @($sentence -split '\s+' | Where-Object { $_ -match '[A-Za-z0-9]' })
        if ($words.Count -gt $MaxSentenceWords) {
            $opening = ($words | Select-Object -First 8) -join ' '
            & $add 'sentence-length' "$($words.Count) words, limit is $MaxSentenceWords. Starts: $opening ... Split it into two sentences."
        }
    }

    # Rule 2 - no jargon, matched on whole words and ignoring case.
    foreach ($term in $JargonTerm) {
        if ($prose -match "(?i)\b$([regex]::Escape($term))\b") {
            & $add 'jargon' "Uses the word '$term'. Part 3 bans it. Write the ordinary word instead."
        }
    }

    # Rule 3 - code names sit inside backticks.
    $codeNamePatterns = @(
        '\b[A-Z][a-z]+-Ei[A-Za-z]+\b'
        '\b[\w][\w.-]*\.(?:ps1|psm1|json|md|txt)\b'
    )
    foreach ($pattern in $codeNamePatterns) {
        foreach ($hit in [regex]::Matches($prose, $pattern)) {
            & $add 'backticks' "'$($hit.Value)' is a code name written as an ordinary word. Put it inside backticks."
        }
    }

    # Rule 4 - spell out an acronym the first time the file uses it.
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($hit in [regex]::Matches($prose, '\b[A-Z]{2,6}\b')) {
        $acronym = $hit.Value
        if ($ExemptAcronym -contains $acronym) { continue }
        if (-not $seen.Add($acronym)) { continue }
        $expanded = $prose -match "\(\s*$acronym\s*\)" -or $prose -match "\b$acronym\s*\([A-Za-z]"
        if (-not $expanded) {
            & $add 'acronym' "Uses '$acronym' without ever spelling it out. Write the full words once, with '$acronym' in brackets after them."
        }
    }

    $problems
}

Export-ModuleMember -Function Get-PlainLanguageProblem, Get-PlainLanguageText, Remove-InlineCode, Get-ProseSentence
