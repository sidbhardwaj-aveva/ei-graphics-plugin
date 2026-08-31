#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Export-EiSessionSummary.ps1'
    $script:FixtureDir = Join-Path $repoRoot 'tests' 'fixtures'

    Import-Module (Join-Path $repoRoot 'tests' 'PlainLanguageRules.psm1') -Force
    $script:JargonTerms = @(
        Get-Content -LiteralPath (Join-Path $repoRoot 'tests' 'data' 'jargon-terms.txt') |
            ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    )

    function New-SessionRoot {
        param([Parameter(Mandatory)] [string] $Fixture, [string] $StoryId = '4965976')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $folder = Join-Path $root '.ei-session-logs' $StoryId
        $null = New-Item -ItemType Directory -Path $folder -Force
        Copy-Item -LiteralPath (Join-Path $script:FixtureDir $Fixture) -Destination (Join-Path $folder 'session.json')
        $root
    }

    function Invoke-Export {
        param([string] $Root, [string] $StoryId = '4965976')
        $output = & $script:ScriptPath -StoryId $StoryId -Root $Root
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }

    function Get-Golden {
        param([Parameter(Mandatory)] [string] $Name)
        (Get-Content -LiteralPath (Join-Path $script:FixtureDir $Name) -Raw) -replace "`r`n", "`n"
    }
}

Describe 'Export-EiSessionSummary' -Tag 'Unit' {

    It 'matches the golden file at verbose' {
        $root = New-SessionRoot -Fixture 'session-verbose.json'
        $run = Invoke-Export -Root $root
        $run.ExitCode | Should -Be 0
        $rendered = (Get-Content -LiteralPath $run.Result.path -Raw) -replace "`r`n", "`n"
        $rendered | Should -Be (Get-Golden -Name 'session-summary-verbose.md')
    }

    It 'matches the golden file at concise' {
        $root = New-SessionRoot -Fixture 'session-concise.json'
        $run = Invoke-Export -Root $root
        $run.ExitCode | Should -Be 0
        $rendered = (Get-Content -LiteralPath $run.Result.path -Raw) -replace "`r`n", "`n"
        $rendered | Should -Be (Get-Golden -Name 'session-summary-concise.md')
    }

    It 'drops the reasoning trail at concise but keeps the maintainer section' {
        $root = New-SessionRoot -Fixture 'session-concise.json'
        $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
        $rendered | Should -Not -Match 'Agent Reasoning Trail'
        $rendered | Should -Match 'For the maintainer'
    }

    It 'shortens the timeline at concise to one row per phase' {
        $verboseRoot = New-SessionRoot -Fixture 'session-verbose.json'
        $conciseRoot = New-SessionRoot -Fixture 'session-concise.json'
        $countRows = {
            param($path)
            @(Get-Content -LiteralPath $path | Where-Object { $_ -match '^\| \d{2}:\d{2}:\d{2} \|' }).Count
        }
        $long = & $countRows (Invoke-Export -Root $verboseRoot).Result.path
        $short = & $countRows (Invoke-Export -Root $conciseRoot).Result.path
        $long | Should -Be 11
        $short | Should -Be 7
    }

    It 'reads the detail level from the log, not from a parameter' {
        (Get-Command $script:ScriptPath).Parameters.Keys | Should -Not -Contain 'Verbosity'
    }

    It 'writes a stub for a session with no entries instead of crashing' {
        $root = New-SessionRoot -Fixture 'session-empty.json'
        $run = Invoke-Export -Root $root
        $run.ExitCode | Should -Be 0
        $rendered = Get-Content -LiteralPath $run.Result.path -Raw
        $rendered | Should -Match '# Session: story 4965976'
        $rendered | Should -Match 'No steps were recorded'
        $rendered | Should -Match 'No reasoning was recorded'
        $rendered | Should -Match 'For the maintainer'
        $rendered | Should -Match 'not recorded'
    }

    It 'shows no cost anywhere' {
        # Part 10: the summary carries totalTokens with no rate, so a price cannot be worked out
        # and must not be invented.
        foreach ($fixture in @('session-verbose.json', 'session-concise.json', 'session-empty.json')) {
            $root = New-SessionRoot -Fixture $fixture
            $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
            $rendered | Should -Not -Match '(?i)cost'
            $rendered | Should -Not -Match '\$\d'
        }
    }

    It 'shows Duration and Tokens in the header' {
        $root = New-SessionRoot -Fixture 'session-verbose.json'
        $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
        $rendered | Should -Match '\*\*Duration:\*\* 3m 36s'
        $rendered | Should -Match '\*\*Tokens:\*\* 7,682'
    }

    It 'works out the human wait time from the checkpoint that had no reply' {
        $root = New-SessionRoot -Fixture 'session-verbose.json'
        $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
        $rendered | Should -Match '\*\*Human wait time:\*\* 2m 21s, across 1 pause\.'
    }

    It 'passes the four plain-language rules at <_>' -ForEach @('session-verbose.json', 'session-concise.json', 'session-empty.json') {
        # The golden files live under tests/, which the T006 scanner skips, so this artifact has
        # to check itself.
        $root = New-SessionRoot -Fixture $_
        $found = @(Get-PlainLanguageProblem -Path (Invoke-Export -Root $root).Result.path -JargonTerm $script:JargonTerms)
        $report = ($found | ForEach-Object { "[$($_.Rule)] $($_.Detail)" }) -join "`n"
        $found.Count | Should -Be 0 -Because "of these problems:`n$report"
    }

    It 'writes the file beside the session log' {
        $root = New-SessionRoot -Fixture 'session-verbose.json'
        $run = Invoke-Export -Root $root
        $run.Result.path | Should -Be (Join-Path $root '.ei-session-logs' '4965976' 'session-summary.md')
    }

    It 'exits 1 when there is no session log' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root -Force
        (Invoke-Export -Root $root).ExitCode | Should -Be 1
    }

    It 'exits 1 when the session log does not validate' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $folder = Join-Path $root '.ei-session-logs' '4965976'
        $null = New-Item -ItemType Directory -Path $folder -Force
        Set-Content -LiteralPath (Join-Path $folder 'session.json') -Encoding utf8NoBOM -Value '{ "schemaVersion": "1.0.0" }'
        (Invoke-Export -Root $root).ExitCode | Should -Be 1
    }

    It 'exits 1 when no story id is given' {
        $null = & $script:ScriptPath -Root $TestDrive
        $LASTEXITCODE | Should -Be 1
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
