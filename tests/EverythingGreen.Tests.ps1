#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time state. Pester needs -ForEach data before any BeforeAll block runs.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# The nine files T006 scans. Its list is hardcoded, because "is this human-facing?" cannot be read
# off the filesystem. Asserting here that all nine now exist is what catches that list drifting.
# The tenth, session-summary.md, is rendered at run time and covered by T009's golden files.
$PluginRoot = 'plugins/aveva-ei-graphics'
$PlainLanguageTargets = @(
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

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    $script:Rows = @(
        Get-Content -LiteralPath (Join-Path $script:RepoRoot 'BUILD-PROGRESS.md') |
            Where-Object { $_ -match '^\s*\|\s*T\d{3}\s*\|' } |
            ForEach-Object {
                $cells = @($_.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
                [pscustomobject]@{ Id = $cells[0]; Status = $cells[2]; Commit = $cells[3]; Verified = $cells[4] }
            }
    )

    # T001 through T020. T021 cannot assert its own completion while it is running, T022 and T023
    # need a person and a live connection, and T024 and T025 were added after T021 had already
    # passed.
    $script:MustBeDone = @($script:Rows | Where-Object { [int]($_.Id.Substring(1)) -le 20 })
}

Describe 'Everything green, before the live run' -Tag 'Unit' {

    It 'the progress table was read' {
        $script:Rows.Count | Should -Be 26
        $script:MustBeDone.Count | Should -Be 20
    }

    It 'no row other than the approved T022 exception is BLOCKED' {
        $blocked = @($script:Rows | Where-Object { $_.Status -eq 'BLOCKED' -and $_.Id -ne 'T022' } | ForEach-Object { $_.Id })
        $blocked.Count | Should -Be 0 -Because "these are blocked: $($blocked -join ', ')"
    }

    It 'T001 through T020 are all DONE' {
        $notDone = @($script:MustBeDone | Where-Object { $_.Status -ne 'DONE' } | ForEach-Object { "$($_.Id) is $($_.Status)" })
        $notDone.Count | Should -Be 0 -Because "these are not done: $($notDone -join ', ')"
    }

    It 'every DONE row carries a real commit, not the pending marker' {
        $bad = @(
            $script:MustBeDone |
                Where-Object { $_.Commit -notmatch '^[0-9a-f]{7,40}$' } |
                ForEach-Object { "$($_.Id) has '$($_.Commit)'" }
        )
        $bad.Count | Should -Be 0 -Because "these have no commit SHA: $($bad -join ', ')"
    }

    It 'zero pending markers remain in the Commit column' {
        @($script:Rows | Where-Object { $_.Commit -eq 'pending' }).Count | Should -Be 0
    }

    It 'every DONE row carries a timestamp' {
        foreach ($row in $script:MustBeDone) {
            $row.Verified | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -Because "$($row.Id) has no timestamp"
        }
    }

    It 'BUILD-LOG.md has a block for every task that is done' {
        $log = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'BUILD-LOG.md') -Raw
        foreach ($row in $script:MustBeDone) {
            $log | Should -Match "(?m)^## $($row.Id)\b" -Because "$($row.Id) has no BUILD-LOG.md block"
        }
    }

    It 'the resolved old repository path is recorded in BUILD-LOG.md, as T001 required' {
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'BUILD-LOG.md') -Raw) |
            Should -Match '(?i)the old repo'
    }

    Context 'the T006 gap is closed' {
        It 'exists now: <_>' -ForEach $PlainLanguageTargets {
            # T006 scanned whichever of these were present at the time, because most did not exist
            # yet. Without this check, a file that was never written would have been skipped by
            # every run of that checker.
            Test-Path -LiteralPath (Join-Path $RepoRoot $_) | Should -BeTrue
        }

        It 'all nine are present, not merely most of them' -TestCases @(@{ Paths = $PlainLanguageTargets }) {
            $Paths.Count | Should -Be 9
            @($Paths | Where-Object { Test-Path -LiteralPath (Join-Path $script:RepoRoot $_) }).Count | Should -Be 9
        }
    }

    Context 'the shape of the finished build' {
        It 'the plugin ships exactly the four skills the plan names' {
            $skills = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills') -Directory |
                    ForEach-Object { $_.Name } | Sort-Object)
            ($skills -join ',') | Should -Be 'ei-azure-devops-cli-intake,ei-graphics-core,ei-layer-guard,termination-drawing'
        }

        It 'the script count under plugins is 12 or fewer' {
            @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'plugins') -File -Recurse -Filter '*.ps1').Count |
                Should -BeLessOrEqual 12
        }
    }
}
