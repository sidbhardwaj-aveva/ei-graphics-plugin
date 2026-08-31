#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time state. Pester needs -ForEach data before any BeforeAll block runs.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Part 3 names ten files a person reads. session-summary.md is rendered at run time into a
# gitignored folder, so it is never on disk to scan. T009 checks that one with golden files.
# This list is closed. Nothing in this build adds an eleventh entry. T021 asserts all nine exist
# by then, which is what catches this hardcoded list drifting away from the repository.
$PluginRoot = 'plugins/demo-ei-graphics'
$CoveredPaths = @(
    "$PluginRoot/agents/ei-graphics.agent.md"
    "$PluginRoot/skills/ei-graphics-core/SKILL.md"
    "$PluginRoot/skills/ei-azure-devops-cli-intake/SKILL.md"
    "$PluginRoot/skills/ei-graphics-core/references/rnd-delegation.md"
    "$PluginRoot/skills/ei-graphics-core/references/checkpoint-templates.md"
    "$PluginRoot/README.md"
    "$PluginRoot/INSTRUCTIONS.md"
    'README.md'
    'PLUGIN-INFO.md'
)

# Most of these do not exist yet at T006. Scan whichever are present and ignore the rest.
$PresentPaths = @(
    $CoveredPaths |
        ForEach-Object { Join-Path $RepoRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ }
)
$PresentCount = $PresentPaths.Count

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $PSScriptRoot 'PlainLanguageRules.psm1') -Force

    $script:JargonFile = Join-Path $script:RepoRoot 'tests' 'data' 'jargon-terms.txt'
    $script:JargonTerms = @(
        Get-Content -LiteralPath $script:JargonFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )

    function New-TempMarkdown {
        param([Parameter(Mandatory)] [string] $Content, [string] $Name = 'sample.md')
        $path = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $path -Value $Content -Encoding utf8NoBOM
        $path
    }
}

Describe 'Plain language rules' -Tag 'Unit' {

    Context 'the checker fails closed' {
        It 'the jargon term file exists' {
            Test-Path -LiteralPath $script:JargonFile | Should -BeTrue
        }

        It 'the jargon term file yields at least 18 terms' {
            # An emptied file must not turn this guard into a silent pass.
            $script:JargonTerms.Count | Should -BeGreaterOrEqual 18
        }

        It 'refuses to run with an empty jargon list' {
            $file = New-TempMarkdown -Content 'A short line.'
            { Get-PlainLanguageProblem -Path $file -JargonTerm @() } | Should -Throw '*empty*'
        }

        It 'refuses to run against a path that does not exist' {
            { Get-PlainLanguageProblem -Path (Join-Path $TestDrive 'nope.md') -JargonTerm $script:JargonTerms } |
                Should -Throw '*does not exist*'
        }

        It 'finds at least one file to scan' -TestCases @(@{ Count = $PresentCount }) {
            # An empty target list is an error, not a pass.
            $Count | Should -BeGreaterThan 0
        }
    }

    Context 'each rule catches what it is meant to catch' {
        It 'catches a planted jargon word' {
            $file = New-TempMarkdown -Content 'We will commence the run now.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'jargon' }).Count | Should -BeGreaterThan 0
        }

        It 'matches jargon on whole words only' {
            # The termination-drawing skill uses words like this hundreds of times. Substring
            # matching would flood the checker with false hits and someone would delete it.
            $file = New-TempMarkdown -Content 'The subsequently named part is fine here.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm @('subsequent')
            @($found | Where-Object { $_.Rule -eq 'jargon' }).Count | Should -Be 0
        }

        It 'catches a 30-word sentence' {
            $sentence = (1..30 | ForEach-Object { 'word' }) -join ' '
            $file = New-TempMarkdown -Content "$sentence."
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'sentence-length' }).Count | Should -Be 1
        }

        It 'accepts a 25-word sentence' {
            $sentence = (1..25 | ForEach-Object { 'word' }) -join ' '
            $file = New-TempMarkdown -Content "$sentence."
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'sentence-length' }).Count | Should -Be 0
        }

        It 'catches a bare script name outside backticks' {
            $file = New-TempMarkdown -Content 'Run Write-EiArtifact.ps1 to save the file.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'backticks' }).Count | Should -BeGreaterThan 0
        }

        It 'accepts the same script name inside backticks' {
            $file = New-TempMarkdown -Content 'Run `Write-EiArtifact.ps1` to save the file.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'backticks' }).Count | Should -Be 0
        }

        It 'ignores code names inside a fenced block' {
            $lines = @(
                'Here is how you call it.'
                ''
                '```powershell'
                '& ./Write-EiArtifact.ps1 -StoryId 4965976'
                '```'
                ''
                'That is all.'
            )
            $file = New-TempMarkdown -Content ($lines -join "`n")
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'backticks' }).Count | Should -Be 0
        }

        It 'catches an acronym that is never spelled out' {
            $file = New-TempMarkdown -Content 'The LOC value drives the layout.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'acronym' }).Count | Should -Be 1
        }

        It 'accepts an acronym that is spelled out on first use' {
            $file = New-TempMarkdown -Content 'The level of connectivity (LOC) drives the layout. A high LOC means more rows.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'acronym' }).Count | Should -Be 0
        }

        It 'accepts the acronyms Part 3 exempts' {
            $file = New-TempMarkdown -Content 'The ADO CLI writes JSON. The PR carries a YAML file, an MD file and a SHA.'
            $found = Get-PlainLanguageProblem -Path $file -JargonTerm $script:JargonTerms
            @($found | Where-Object { $_.Rule -eq 'acronym' }).Count | Should -Be 0
        }
    }

    Context 'every file a person reads passes all four rules' {
        It 'passes: <_>' -ForEach $PresentPaths {
            $found = @(Get-PlainLanguageProblem -Path $_ -JargonTerm $script:JargonTerms)
            $report = ($found | ForEach-Object { "[$($_.Rule)] $($_.Detail)" }) -join "`n"
            $found.Count | Should -Be 0 -Because "of these problems:`n$report"
        }
    }
}
