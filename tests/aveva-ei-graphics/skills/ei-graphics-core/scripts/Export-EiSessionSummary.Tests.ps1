#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
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

    Context 'the evidence behind the reasoning' {

        It 'links the file at the line it was read, from where the summary sits' {
            # Two folders up, because the summary lives at .ei-session-logs/<storyId>/ and the
            # recorded path starts at the repository root.
            $root = New-SessionRoot -Fixture 'session-verbose.json'
            $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
            $rendered | Should -Match '\*\*Evidence\*\*'
            $rendered | Should -BeLike '*(../../Presentation/Manager/CoreConnectorManager.cs#L84)*'
        }

        It 'shows the quoted text in a fenced block, word for word' {
            $root = New-SessionRoot -Fixture 'session-verbose.json'
            $lines = @(Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path)
            $opened = [array]::IndexOf($lines, '```text')
            $opened | Should -BeGreaterThan 0
            $lines[$opened + 1] | Should -Be '// nothing to do when the shape is already there'
            $lines[$opened + 2] | Should -Be 'if (existsInBoth) { return; }'
            $lines[$opened + 3] | Should -Be '```'
        }

        It 'writes no evidence heading for an entry that has none' {
            # Eight entries carry reasoning in the fixture and two carry evidence.
            $root = New-SessionRoot -Fixture 'session-verbose.json'
            $lines = @(Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path)
            @($lines | Where-Object { $_ -eq '**Evidence**' }).Count | Should -Be 2
            @($lines | Where-Object { $_ -match '^### ' }).Count | Should -Be 8
        }

        It 'drops the evidence with the reasoning trail at concise' {
            $root = New-SessionRoot -Fixture 'session-concise.json'
            $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
            $rendered | Should -Not -Match 'Evidence'
        }
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

    It 'reports a comment that overrode the story, and which comment it was' {
        $root = New-SessionRoot -Fixture 'session-verbose.json'
        $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
        $rendered | Should -Match '(?m)^- \*\*Comment corrections:\*\* comment `7`: '
    }

    It 'says none plainly when the summary records no comment deviations' {
        $root = New-SessionRoot -Fixture 'session-concise.json'
        $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
        $rendered | Should -Match '(?m)^- \*\*Comment corrections:\*\* None recorded\.'
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

    Context 'the improvement opportunity names source files only' {
        BeforeEach {
            # A session that read one real source file, its own artifact and its own skill.
            $script:MixedRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $folder = Join-Path $script:MixedRoot '.ei-session-logs' '4965976'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $session = Get-Content -LiteralPath (Join-Path $script:FixtureDir 'session-verbose.json') -Raw | ConvertFrom-Json
            $session.entries[6].filesRead = @(
                'src/Manager/CoreConnectorManager.cs'
                '.ei-session-logs/4965976/ado.json'
                'plugins/aveva-ei-graphics/skills/termination-drawing/SKILL.md'
            )
            Set-Content -LiteralPath (Join-Path $folder 'session.json') -Encoding utf8NoBOM `
                -Value ($session | ConvertTo-Json -Depth 30)
        }

        It 'lists the source file' {
            $rendered = Get-Content -LiteralPath (Invoke-Export -Root $script:MixedRoot).Result.path -Raw
            $rendered | Should -BeLike '*CoreConnectorManager.cs*'
        }

        It 'leaves out the agent own artifact and its own skill' {
            $line = [regex]::Match(
                (Get-Content -LiteralPath (Invoke-Export -Root $script:MixedRoot).Result.path -Raw),
                '(?m)^- \*\*Improvement opportunity:\*\* (.*)$').Groups[1].Value
            $line | Should -Not -Match 'ado\.json'
            $line | Should -Not -Match 'SKILL\.md'
            $line | Should -Match 'source file'
        }

        It 'still counts every read in the efficiency line' {
            # A read is a read. Only the improvement advice is filtered.
            $line = [regex]::Match(
                (Get-Content -LiteralPath (Invoke-Export -Root $script:MixedRoot).Result.path -Raw),
                '(?m)^- \*\*Agent efficiency:\*\* (.*)$').Groups[1].Value
            $line | Should -BeLike '3 files read*'
        }

        It 'says so plainly when nothing but its own files were read' {
            $session = Get-Content -LiteralPath (Join-Path $script:FixtureDir 'session-verbose.json') -Raw | ConvertFrom-Json
            $session.entries[6].filesRead = @('.ei-session-logs/4965976/ado.json')
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $folder = Join-Path $root '.ei-session-logs' '4965976'
            $null = New-Item -ItemType Directory -Path $folder -Force
            Set-Content -LiteralPath (Join-Path $folder 'session.json') -Encoding utf8NoBOM `
                -Value ($session | ConvertTo-Json -Depth 30)
            $rendered = Get-Content -LiteralPath (Invoke-Export -Root $root).Result.path -Raw
            $rendered | Should -Match 'No source file was read'
        }
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
