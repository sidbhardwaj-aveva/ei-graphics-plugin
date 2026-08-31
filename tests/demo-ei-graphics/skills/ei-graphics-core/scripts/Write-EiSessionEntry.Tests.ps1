#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Write-EiSessionEntry.ps1'
    $script:SchemaText = Get-Content -LiteralPath (Join-Path $core 'schemas' 'session.schema.json') -Raw

    function Invoke-Entry {
        param([hashtable] $Splat)
        $output = & $script:ScriptPath @Splat
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }

    function Get-Session {
        param([string] $Root, [string] $StoryId = '4965976')
        Get-Content -LiteralPath (Join-Path $Root '.ei-session-logs' $StoryId 'session.json') -Raw
    }
}

Describe 'Write-EiSessionEntry' -Tag 'Unit' {

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Root -Force
        $script:Base = @{ StoryId = '4965976'; Root = $script:Root }
    }

    It 'creates the envelope on the first call' {
        $run = Invoke-Entry -Splat ($script:Base + @{
            Phase = 'ado-intake'; Action = 'retrieve-story'; Outcome = 'Retrieved the story.'
        })
        $run.ExitCode | Should -Be 0
        $raw = Get-Session -Root $script:Root
        $session = $raw | ConvertFrom-Json
        $session.schemaVersion | Should -Be '1.0.0'
        $session.storyId | Should -Be '4965976'
        $session.agent | Should -Be 'ei-graphics'
        $session.verbosity | Should -Be 'verbose'
        # Checked against the file text. ConvertFrom-Json turns a timestamp into a date object and
        # would hide the format we actually wrote.
        $raw | Should -Match '"startedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
        @($session.entries).Count | Should -Be 1
    }

    It 'keeps three appends in the order they were written' {
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'ado-intake'; Action = 'first'; Outcome = 'one' }) | Out-Null
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'understanding'; Action = 'second'; Outcome = 'two' }) | Out-Null
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'implementation'; Action = 'third'; Outcome = 'three' }) | Out-Null

        $entries = @((Get-Session -Root $script:Root | ConvertFrom-Json).entries)
        $entries.Count | Should -Be 3
        $entries[0].action | Should -Be 'first'
        $entries[1].action | Should -Be 'second'
        $entries[2].action | Should -Be 'third'
    }

    It 'keeps the timestamp format when it rewrites the file' {
        # Reading the log back turns every timestamp into a date object. Writing it out again
        # would then change the format unless the script converts it back first.
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'ado-intake'; Action = 'first'; Outcome = 'one' }) | Out-Null
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'understanding'; Action = 'second'; Outcome = 'two' }) | Out-Null

        $raw = Get-Session -Root $script:Root
        $raw | Should -Not -Match '\.\d{7}Z'
        @([regex]::Matches($raw, '"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"')).Count | Should -Be 3
    }

    It 'does not truncate the file on a rapid second append' {
        Invoke-Entry -Splat ($script:Base + @{ Phase = 'ado-intake'; Action = 'first'; Outcome = 'one' }) | Out-Null
        $run = Invoke-Entry -Splat ($script:Base + @{ Phase = 'understanding'; Action = 'second'; Outcome = 'two' })
        $run.ExitCode | Should -Be 0
        $raw = Get-Session -Root $script:Root
        { $raw | ConvertFrom-Json } | Should -Not -Throw
        @(($raw | ConvertFrom-Json).entries).Count | Should -Be 2
        # No temporary file is left behind.
        @(Get-ChildItem -LiteralPath (Join-Path $script:Root '.ei-session-logs' '4965976') -Filter '*.tmp').Count | Should -Be 0
    }

    It 'records the four optional entry fields when they are given' {
        $run = Invoke-Entry -Splat ($script:Base + @{
            Phase = 'implementation'; Action = 'apply-fix'; Outcome = 'Changed one method.'
            Reasoning = 'The guard returned too early.'
            DurationMs = 2000; TokensUsed = 1200
            FilesRead = @('src/A.cs'); FilesModified = @('src/A.cs')
            HumanInput = 'go ahead'; ScriptOutput = @{ status = 'pass' }
        })
        $run.ExitCode | Should -Be 0
        $entry = @((Get-Session -Root $script:Root | ConvertFrom-Json).entries)[0]
        $entry.filesRead | Should -Contain 'src/A.cs'
        $entry.filesModified | Should -Contain 'src/A.cs'
        $entry.humanInput | Should -Be 'go ahead'
        $entry.scriptOutput.status | Should -Be 'pass'
    }

    It 'rejects a phase the schema does not know' {
        $run = Invoke-Entry -Splat ($script:Base + @{ Phase = 'daydreaming'; Action = 'a'; Outcome = 'b' })
        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:Root '.ei-session-logs' '4965976' 'session.json') | Should -BeFalse
    }

    It 'rejects an append with no action or outcome' {
        (Invoke-Entry -Splat ($script:Base + @{ Phase = 'ado-intake'; Outcome = 'b' })).ExitCode | Should -Be 1
        (Invoke-Entry -Splat ($script:Base + @{ Phase = 'ado-intake'; Action = 'a' })).ExitCode | Should -Be 1
    }

    Context '-Finalize' {
        BeforeEach {
            Invoke-Entry -Splat ($script:Base + @{
                Phase = 'implementation'; Action = 'first'; Outcome = 'one'
                DurationMs = 1000; TokensUsed = 100; FilesModified = @('src/A.cs')
            }) | Out-Null
            Invoke-Entry -Splat ($script:Base + @{
                Phase = 'validation'; Action = 'second'; Outcome = 'two'
                DurationMs = 2500; TokensUsed = 400; FilesModified = @('src/B.cs')
            }) | Out-Null
        }

        It 'writes all ten summary fields and still validates' {
            $run = Invoke-Entry -Splat ($script:Base + @{
                Finalize = $true; TestsRun = 12; TestsPassed = 12; HumanInteractions = 2
                SessionOutcome = 'fixed'; DomainSkillUsed = 'termination-drawing'
                BugPatternMatched = 'Core Connector Update'
            })
            $run.ExitCode | Should -Be 0

            $raw = Get-Session -Root $script:Root
            $raw | Test-Json -Schema $script:SchemaText | Should -BeTrue

            $summary = ($raw | ConvertFrom-Json).summary
            $summary.PSObject.Properties.Name | Should -HaveCount 10
            $raw | Should -Match '"completedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
            $summary.totalDurationMs | Should -Be 3500
            $summary.totalTokens | Should -Be 500
            @($summary.filesModified) | Should -HaveCount 2
            $summary.testsRun | Should -Be 12
            $summary.testsPassed | Should -Be 12
            $summary.humanInteractions | Should -Be 2
            $summary.outcome | Should -Be 'fixed'
            $summary.domainSkillUsed | Should -Be 'termination-drawing'
            $summary.bugPatternMatched | Should -Be 'Core Connector Update'
        }

        It 'works out the four derived fields from the entries, not from parameters' {
            $run = Invoke-Entry -Splat ($script:Base + @{ Finalize = $true; SessionOutcome = 'fixed' })
            $run.ExitCode | Should -Be 0
            $summary = (Get-Session -Root $script:Root | ConvertFrom-Json).summary
            $summary.totalDurationMs | Should -Be 3500
            $summary.totalTokens | Should -Be 500
            @($summary.filesModified) | Sort-Object | Should -Be @('src/A.cs', 'src/B.cs')
        }

        It 'leaves the entries alone' {
            Invoke-Entry -Splat ($script:Base + @{ Finalize = $true; SessionOutcome = 'fixed' }) | Out-Null
            @((Get-Session -Root $script:Root | ConvertFrom-Json).entries).Count | Should -Be 2
        }
    }

    It 'refuses an append parameter together with -Finalize' {
        # A parameter set error, not a silent partial write.
        { & $script:ScriptPath -StoryId '4965976' -Root $script:Root -Finalize -Phase 'ado-intake' } |
            Should -Throw '*Parameter set cannot be resolved*'
    }

    It 'exits 1 when no story id is given' {
        (Invoke-Entry -Splat @{ Root = $script:Root; Phase = 'ado-intake'; Action = 'a'; Outcome = 'b' }).ExitCode |
            Should -Be 1
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
