#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time state. Pester needs -ForEach data before any BeforeAll block runs.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# The only place this list is written down. Everything else in the repository is scanned.
# docs/** is load-bearing: architecture-v3.md is a word for word archive that legitimately holds
# many of these names, and it is never edited. plan.md and BUILD-LOG.md name the old plugin folder
# as a copy source. .ei-session-logs/ is gitignored run output, not part of the built repository:
# a real story's own text could otherwise fail this guard. That eighth entry is a deliberate
# departure from the seven the plan lists, recorded in T019's regression block in BUILD-LOG.md.
$SkipPatterns = @(
    '^docs[\\/]'
    '^BUILD-LOG\.md$'
    '^BUILD-PROGRESS\.md$'
    '^plan\.md$'
    '^tests[\\/]data[\\/]forbidden-identifiers\.txt$'
    '^tests[\\/]fixtures[\\/]'
    '^\.git[\\/]'
    '^\.ei-session-logs[\\/]'
)

$ScannedFiles = @(
    Get-ChildItem -LiteralPath $RepoRoot -File -Recurse -Force |
        ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1) } |
        Where-Object {
            $relative = $_
            -not ($SkipPatterns | Where-Object { $relative -match $_ })
        }
)

$SkillFolders = @(
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'plugins' 'aveva-ei-graphics' 'skills') -Directory |
        ForEach-Object { $_.FullName }
)

# Part 2's "what we are deliberately not copying" list, read out of plan.md rather than repeated
# here. Writing it here would make this file fail its own scan.
$NotCopiedParagraph = [regex]::Match(
    (Get-Content -LiteralPath (Join-Path $RepoRoot 'plan.md') -Raw),
    '(?ms)^### What we are deliberately not copying\s*\r?\n\r?\n(.*?)\r?\n\r?\n'
).Groups[1].Value

$NotCopied = @(
    [regex]::Matches($NotCopiedParagraph, '`([^`]+)`') |
        ForEach-Object { $_.Groups[1].Value } |
        ForEach-Object { (Split-Path -Leaf $_) -replace '\.ps1$', '' } |
        Sort-Object -Unique
)

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:TermFile = Join-Path $script:RepoRoot 'tests' 'data' 'forbidden-identifiers.txt'
    $script:Terms = @(
        Get-Content -LiteralPath $script:TermFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

Describe 'No orphan references' -Tag 'Unit' {

    Context 'the guard fails closed' {
        It 'the term file exists and parses' {
            Test-Path -LiteralPath $script:TermFile | Should -BeTrue
            { Get-Content -LiteralPath $script:TermFile } | Should -Not -Throw
        }

        It 'the term file yields at least 23 terms' {
            # Checked before any scanning. An emptied file must not turn this into a silent pass.
            $script:Terms.Count | Should -BeGreaterOrEqual 23
        }

        It 'every term is a non-empty single line' {
            foreach ($term in $script:Terms) {
                $term | Should -Not -BeNullOrEmpty
                $term | Should -Not -Match '\s'
            }
        }

        It 'the scan found files to look at' -TestCases @(@{ Count = $ScannedFiles.Count }) {
            $Count | Should -BeGreaterThan 0
        }

        It 'a planted term in a scanned location would fail the scan' {
            $planted = Join-Path $TestDrive 'planted.md'
            Set-Content -LiteralPath $planted -Encoding utf8NoBOM -Value "This prose mentions $($script:Terms[0]) by name."
            $raw = Get-Content -LiteralPath $planted -Raw
            @($script:Terms | Where-Object { $raw -like "*$_*" }).Count | Should -BeGreaterThan 0
        }

        It 'never scans the gitignored session logs' -TestCases @(@{ Scanned = $ScannedFiles }) {
            # A live run writes a story's own words into .ei-session-logs/. A story that happened to
            # mention a banned identifier would otherwise fail this guard on someone else's text.
            @($Scanned | Where-Object { $_ -match '^\.ei-session-logs[\\/]' }).Count | Should -Be 0
        }

        It 'skips only what the build plan and this file account for' -TestCases @(@{ Count = $SkipPatterns.Count }) {
            # Seven from the plan, plus the run output folder added in T019's regression.
            $Count | Should -Be 8
        }
    }

    Context 'the term file covers everything the build dropped' {
        It 'the not-copied list was found in plan.md' -TestCases @(@{ Names = $NotCopied }) {
            # A parse that quietly returns nothing would make the next check vacuous.
            $Names.Count | Should -BeGreaterOrEqual 10
        }

        It 'names <_>' -ForEach $NotCopied {
            $script:Terms | Should -Contain $_
        }

        It 'names the replaced plugin folder, which must not survive anywhere' {
            $replacedName = @('demo-ei', 'graphics') -join '-'
            $script:Terms | Should -Contain $replacedName
        }
    }

    Context 'nothing in the built repository names a dropped skill' {
        It 'is clean: <_>' -ForEach $ScannedFiles {
            $path = Join-Path $RepoRoot $_
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
            if ($null -eq $raw) { return }
            $hits = @($script:Terms | Where-Object { $raw -like "*$_*" })
            $hits.Count | Should -Be 0 -Because "$_ names: $($hits -join ', ')"
        }
    }

    Context 'every skill declares a name matching its folder' {
        It 'checks <_>' -ForEach $SkillFolders {
            $skillPath = Join-Path $_ 'SKILL.md'
            Test-Path -LiteralPath $skillPath | Should -BeTrue
            $raw = Get-Content -LiteralPath $skillPath -Raw
            $raw | Should -Match '(?s)\A---\r?\n.*?\r?\n---\r?\n'
            ([regex]::Match($raw, '(?m)^name:\s*(\S+)\s*$')).Groups[1].Value | Should -Be (Split-Path -Leaf $_)
        }
    }
}
