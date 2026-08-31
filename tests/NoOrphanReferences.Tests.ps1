#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time state. Pester needs -ForEach data before any BeforeAll block runs.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# The only place this list is written down. Everything else in the repository is scanned.
# docs/** is load-bearing: architecture-v3.md is a word for word archive that legitimately holds
# many of these names, and it is never edited. plan.md and BUILD-LOG.md name the old plugin folder
# as a copy source.
$SkipPatterns = @(
    '^docs[\\/]'
    '^BUILD-LOG\.md$'
    '^BUILD-PROGRESS\.md$'
    '^plan\.md$'
    '^tests[\\/]data[\\/]forbidden-identifiers\.txt$'
    '^tests[\\/]fixtures[\\/]'
    '^\.git[\\/]'
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
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'plugins' 'demo-ei-graphics' 'skills') -Directory |
        ForEach-Object { $_.FullName }
)

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:TermFile = Join-Path $script:RepoRoot 'tests' 'data' 'forbidden-identifiers.txt'
    $script:Terms = @(
        Get-Content -LiteralPath $script:TermFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )

    # Part 2, "what we are deliberately not copying". Skills by folder name, scripts by file name
    # without the extension.
    $script:NotCopied = @(
        'ei-graphics-workflow'
        'ei-workflow-state'
        'ei-scope-resolver'
        'ei-scope-validator'
        'ei-vocabulary-navigator'
        'ei-bug-reproducer'
        'ei-test-scaffolder'
        'Test-EiGraphicsSpecSync'
        'Invoke-EiAdoIntakeStage'
        'EiTestPreflight'
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
            Set-Content -LiteralPath $planted -Value 'This mentions ei-graphics-workflow in prose.' -Encoding utf8NoBOM
            $hits = @($script:Terms | Where-Object { (Get-Content -LiteralPath $planted -Raw) -like "*$_*" })
            $hits.Count | Should -BeGreaterThan 0
        }
    }

    Context 'the term file covers everything the build dropped' {
        It 'names <_>' -ForEach @(
            'ei-graphics-workflow'
            'ei-workflow-state'
            'ei-scope-resolver'
            'ei-scope-validator'
            'ei-vocabulary-navigator'
            'ei-bug-reproducer'
            'ei-test-scaffolder'
            'Test-EiGraphicsSpecSync'
            'Invoke-EiAdoIntakeStage'
            'EiTestPreflight'
        ) {
            $script:Terms | Should -Contain $_
        }

        It 'names the old plugin, which must not survive anywhere' {
            $script:Terms | Should -Contain 'aveva-ei-graphics'
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
