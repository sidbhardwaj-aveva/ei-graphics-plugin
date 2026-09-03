#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:SkillFolder = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'termination-drawing'
    $script:SkillPath = Join-Path $script:SkillFolder 'SKILL.md'
    $script:ReferenceFolder = Join-Path $script:SkillFolder 'references'
    $script:FixturePath = Join-Path $repoRoot 'tests' 'fixtures' 'termination-drawing-v2-SKILL.md'

    $script:ReferenceNames = @(
        'architecture.md'
        'composite-key-system.md'
        'update-flow.md'
        'log-analysis.md'
        'bug-patterns.md'
    )

    function Get-Heading {
        <#
        .SYNOPSIS
            Returns the real headings in a markdown file, ignoring anything inside a code fence.
        #>
        param([Parameter(Mandatory)] [string] $Path)
        $inFence = $false
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($line in (Get-Content -LiteralPath $Path)) {
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if (-not $inFence -and $line -match '^#{1,6}\s') { $found.Add($line.Trim()) }
        }
        $found
    }

    $script:FixtureHeadings = @(Get-Heading -Path $script:FixturePath)

    # Where each heading ended up. A heading in two places is a duplicate; in none, it is lost.
    $script:Placement = @{}
    foreach ($file in @(@{ Name = 'SKILL.md'; Path = $script:SkillPath }) +
        @($script:ReferenceNames | ForEach-Object { @{ Name = $_; Path = Join-Path $script:ReferenceFolder $_ } })) {
        if (-not (Test-Path -LiteralPath $file.Path)) { continue }
        foreach ($heading in (Get-Heading -Path $file.Path)) {
            if (-not $script:Placement.ContainsKey($heading)) { $script:Placement[$heading] = @() }
            $script:Placement[$heading] += $file.Name
        }
    }
}

Describe 'termination-drawing split' -Tag 'Unit' {

    Context 'the skill document stays small' {
        It 'is under 180 lines' {
            @(Get-Content -LiteralPath $script:SkillPath).Count | Should -BeLessThan 180
        }

        It 'is under 5000 tokens, estimated as characters divided by 4' {
            [int]((Get-Content -LiteralPath $script:SkillPath -Raw).Length / 4) | Should -BeLessThan 5000
        }

        It 'keeps its frontmatter, with a name matching the folder' {
            $raw = Get-Content -LiteralPath $script:SkillPath -Raw
            $raw | Should -Match '(?s)\A---\r?\n.*?\r?\n---\r?\n'
            ([regex]::Match($raw, '(?m)^name:\s*(\S+)\s*$')).Groups[1].Value |
                Should -Be (Split-Path -Leaf $script:SkillFolder)
        }
    }

    Context 'the reference files' {
        It '<_> exists and is not empty' -ForEach @(
            'architecture.md'
            'composite-key-system.md'
            'update-flow.md'
            'log-analysis.md'
            'bug-patterns.md'
        ) {
            $path = Join-Path $script:ReferenceFolder $_
            Test-Path -LiteralPath $path | Should -BeTrue
            (Get-Content -LiteralPath $path -Raw).Trim().Length | Should -BeGreaterThan 0
        }

        It 'every reference file is linked from SKILL.md' {
            $raw = Get-Content -LiteralPath $script:SkillPath -Raw
            foreach ($name in $script:ReferenceNames) {
                $raw | Should -BeLike "*references/$name*"
            }
        }

        It 'the References section says when to load each file, not just which files exist' {
            $section = [regex]::Match((Get-Content -LiteralPath $script:SkillPath -Raw), '(?ms)^## References\s*$.*\z')
            $section.Success | Should -BeTrue
            $section.Value | Should -Match '(?i)read this'
        }

        It 'no reference folder holds a file nobody links to' {
            $onDisk = @(Get-ChildItem -LiteralPath $script:ReferenceFolder -Filter '*.md' | ForEach-Object { $_.Name })
            $onDisk | Sort-Object | Should -Be ($script:ReferenceNames | Sort-Object)
        }
    }

    Context 'nothing was lost and nothing was duplicated' {
        # This checks one direction only. Headings may be added later, and T015 itself adds
        # '## References'. Freezing the heading set, or a total count, would turn any future
        # improvement to this skill into a build failure.

        It 'the committed fixture still has headings to compare against' {
            $script:FixtureHeadings.Count | Should -BeGreaterThan 0
        }

        It 'reports zero headings lost from the fixture' {
            $missing = @($script:FixtureHeadings | Where-Object { -not $script:Placement.ContainsKey($_) })
            $missing.Count | Should -Be 0 -Because "these headings went missing:`n$($missing -join "`n")"
        }

        It 'reports zero headings placed in more than one file' {
            $duplicated = @(
                $script:FixtureHeadings |
                    Where-Object { $script:Placement.ContainsKey($_) -and @($script:Placement[$_]).Count -gt 1 } |
                    ForEach-Object { "$_ -> $(@($script:Placement[$_]) -join ', ')" }
            )
            $duplicated.Count | Should -Be 0 -Because "these headings are in two places:`n$($duplicated -join "`n")"
        }

        It 'ignores the code comments that sit inside fenced blocks' {
            # The source has about ten '#' lines inside PowerShell and C# blocks. Counting them as
            # headings would make this suite fail for no reason.
            $script:FixtureHeadings | Should -Not -Contain '# Model + insertion summary'
            $script:FixtureHeadings | Should -Not -Contain '# Key shape actions'
        }
    }

    Context 'the pieces the plan calls out by number' {
        It 'the Key Files table still has all 14 rows' {
            $architecture = Get-Content -LiteralPath (Join-Path $script:ReferenceFolder 'architecture.md') -Raw
            $section = [regex]::Match($architecture, '(?ms)^### Key Files\s*$.*?(?=^#{2,3}\s|\z)').Value
            $rows = @([regex]::Matches($section, '(?m)^\|(?!\s*-).*\|\s*$'))
            ($rows.Count - 1) | Should -Be 14
        }

        It 'all 7 bug patterns moved together' {
            $patterns = Get-Content -LiteralPath (Join-Path $script:ReferenceFolder 'bug-patterns.md') -Raw
            @([regex]::Matches($patterns, '(?m)^### \d+\.\s')).Count | Should -Be 7
        }

        It 'all 10 critical rules stayed in SKILL.md' {
            $raw = Get-Content -LiteralPath $script:SkillPath -Raw
            $section = [regex]::Match($raw, '(?ms)^## Critical Rules \(Do NOT Violate\)\s*$.*?(?=^## |\z)').Value
            @([regex]::Matches($section, '(?m)^\d+\.\s')).Count | Should -Be 10
        }

        It 'the child of the core connector section moved with its parent' {
            # Two earlier drafts of the plan lost this heading.
            $updateFlow = Get-Content -LiteralPath (Join-Path $script:ReferenceFolder 'update-flow.md') -Raw
            $updateFlow | Should -BeLike '*## Core Connector Update (existsInBoth)*'
            $updateFlow | Should -BeLike '*### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)*'
        }

        It 'the long command block left SKILL.md and landed in log-analysis.md' {
            $raw = Get-Content -LiteralPath $script:SkillPath -Raw
            $step = [regex]::Match($raw, '(?ms)^### Step 2 — Analyse the Log\s*$.*?(?=^### |\z)').Value
            $step | Should -Not -Match 'Select-String'
            $step | Should -BeLike '*references/log-analysis.md*'
            Get-Content -LiteralPath (Join-Path $script:ReferenceFolder 'log-analysis.md') -Raw |
                Should -BeLike '*SKIP-DUPLICATE*'
        }
    }
}
