#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '..' '..'
    $script:CheckerPath = (Resolve-Path (Join-Path $repoRoot 'tools' 'Test-BuildProgress.ps1')).Path

    # A miniature plan with three task headings. The checker reads its task list from here.
    $script:PlanText = @'
# A small plan

#### T001 - first task

Some words.

#### T002 - second task

More words.

#### T003 - third task

Last words.
'@

    $script:LogText = @'
# Build Log

## T001 - first task - 2026-01-01T00:00:00Z

**Assumptions:** none worth stating.

## T002 - second task - 2026-01-02T00:00:00Z

**Assumptions:** the checker reads its task list from the plan.

## T003 - third task - 2026-01-03T00:00:00Z

**Assumptions:** the third task assumes nothing.
'@

    function New-ProgressFile {
        param(
            [Parameter(Mandatory)] [string] $CurrentTask,
            [Parameter(Mandatory)] [string[]] $Rows,
            [string] $FileName = 'BUILD-PROGRESS.md'
        )
        $lines = @(
            '# Build Progress'
            ''
            '**Plan:** `plan.md`'
            "**Current task:** $CurrentTask"
            '**Last verified green:** none'
            ''
            '| ID | Task | Status | Commit | Acceptance verified at |'
            '|----|------|--------|--------|------------------------|'
        ) + $Rows
        $path = Join-Path $TestDrive $FileName
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8NoBOM
        $path
    }

    function Invoke-Checker {
        param([Parameter(Mandatory)] [string] $ProgressFile, [string] $LogOverride)
        $logPath = if ($LogOverride) { $LogOverride } else { $script:LogPath }
        $output = & $script:CheckerPath -PlanPath $script:PlanPath -ProgressPath $ProgressFile -LogPath $logPath 2>$null
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }
}

Describe 'Test-BuildProgress' -Tag 'Unit' {

    BeforeEach {
        $script:PlanPath = Join-Path $TestDrive 'plan.md'
        $script:LogPath = Join-Path $TestDrive 'BUILD-LOG.md'
        Set-Content -LiteralPath $script:PlanPath -Value $script:PlanText -Encoding utf8NoBOM
        Set-Content -LiteralPath $script:LogPath -Value $script:LogText -Encoding utf8NoBOM
    }

    It 'accepts a valid progress file' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | DONE | e4f5a6b | 2026-01-02T12:00:00Z |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Valid'
        $run.Result.Errors.Count | Should -Be 0
        $run.ExitCode | Should -Be 0
    }

    It 'reads the task list from the plan, not from a hardcoded list' {
        $file = New-ProgressFile -CurrentTask 'T001' -Rows @(
            '| T001 | first task | TODO | — | — |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Details.PlanTaskCount | Should -Be 3
        $run.ExitCode | Should -Be 0
    }

    It 'rejects two IN-PROGRESS rows' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | IN-PROGRESS | — | — |'
            '| T003 | third task | IN-PROGRESS | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'IN-PROGRESS'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a DONE row with an empty commit' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | — | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Commit column'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a DONE row with no timestamp' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | — |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Acceptance verified at'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a missing task ID' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'no row for T003'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a duplicated task ID' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
            '| T002 | second task again | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'rows for T002'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a row whose task ID is not in the plan' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
            '| T004 | invented task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'no .#### T004. heading'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a header that disagrees with the table' {
        $file = New-ProgressFile -CurrentTask 'T001' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | IN-PROGRESS | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Change the header to T002'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a TODO row sitting above the IN-PROGRESS row' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | IN-PROGRESS | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Tasks run in order'
        $run.ExitCode | Should -Be 1
    }

    It 'warns but passes when one DONE row says pending' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | DONE | pending | 2026-01-02T12:00:00Z |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Valid'
        $run.Result.Warnings.Count | Should -Be 1
        ($run.Result.Warnings -join ' ') | Should -Match 'T002'
        $run.ExitCode | Should -Be 0
    }

    It 'still passes when the pending row is in the middle, not last' {
        # This is the Part 8 repair case: an early task is redone while later ones are done.
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | pending | 2026-01-01T12:00:00Z |'
            '| T002 | second task | DONE | e4f5a6b | 2026-01-02T12:00:00Z |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Valid'
        $run.Result.Warnings.Count | Should -Be 1
        $run.ExitCode | Should -Be 0
    }

    It 'rejects two pending values' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | pending | 2026-01-01T12:00:00Z |'
            '| T002 | second task | DONE | pending | 2026-01-02T12:00:00Z |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Only one is allowed'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects pending in a row that is not DONE' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | IN-PROGRESS | pending | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Only a DONE row may say pending'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects an IN-PROGRESS row whose log block has no Assumptions line' {
        $logPath = Join-Path $TestDrive 'BUILD-LOG-no-assumptions.md'
        Set-Content -LiteralPath $logPath -Encoding utf8NoBOM -Value @(
            '# Build Log'
            ''
            '## T002 - second task - 2026-01-02T00:00:00Z'
            ''
            '**Goal:** do the thing.'
        )
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | IN-PROGRESS | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file -LogOverride $logPath
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'Assumptions'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects an IN-PROGRESS row with no log block at all' {
        $logPath = Join-Path $TestDrive 'BUILD-LOG-empty.md'
        Set-Content -LiteralPath $logPath -Value '# Build Log' -Encoding utf8NoBOM
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | IN-PROGRESS | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file -LogOverride $logPath
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'no .## T002. block'
        $run.ExitCode | Should -Be 1
    }

    It 'rejects a status word that is not one of the four' {
        $file = New-ProgressFile -CurrentTask 'T002' -Rows @(
            '| T001 | first task | FINISHED | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | TODO | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Status | Should -Be 'Invalid'
        ($run.Result.Errors -join ' ') | Should -Match 'TODO, IN-PROGRESS, DONE or BLOCKED'
        $run.ExitCode | Should -Be 1
    }

    It 'reports BLOCKED rows in Details' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | BLOCKED | — | — |'
            '| T003 | third task | TODO | — | — |'
        )
        $run = Invoke-Checker -ProgressFile $file
        $run.Result.Details.BlockedCount | Should -Be 1
        $run.ExitCode | Should -Be 0
    }

    It 'emits JSON on stdout when -Json is given' {
        $file = New-ProgressFile -CurrentTask 'T003' -Rows @(
            '| T001 | first task | DONE | a1b2c3d | 2026-01-01T12:00:00Z |'
            '| T002 | second task | DONE | e4f5a6b | 2026-01-02T12:00:00Z |'
            '| T003 | third task | TODO | — | — |'
        )
        $raw = & $script:CheckerPath -PlanPath $script:PlanPath -ProgressPath $file -LogPath $script:LogPath -Json 2>$null
        $parsed = ($raw -join "`n") | ConvertFrom-Json
        $parsed.Status | Should -Be 'Valid'
        $parsed.Details.RowCount | Should -Be 3
    }

    It 'fails when the progress file does not exist' {
        $run = Invoke-Checker -ProgressFile (Join-Path $TestDrive 'does-not-exist.md')
        $run.Result.Status | Should -Be 'Invalid'
        $run.ExitCode | Should -Be 1
    }
}
