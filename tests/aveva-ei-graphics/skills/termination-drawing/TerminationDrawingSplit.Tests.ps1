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
        It 'is under 260 lines' {
            @(Get-Content -LiteralPath $script:SkillPath).Count | Should -BeLessThan 260
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

    Context 'regression triage runs before the log is demanded' {
        BeforeAll {
            $script:SkillRaw = Get-Content -LiteralPath $script:SkillPath -Raw
            $script:TriageStep = [regex]::Match(
                $script:SkillRaw, '(?ms)^### Step 1b — Regression Triage\s*$.*?(?=^### |\z)').Value
        }

        It 'has its own step, between understanding the problem and analysing the log' {
            $script:TriageStep | Should -Not -BeNullOrEmpty
            $understanding = $script:SkillRaw.IndexOf('### Step 1 — Understand the Problem')
            $triage = $script:SkillRaw.IndexOf('### Step 1b — Regression Triage')
            $analysis = $script:SkillRaw.IndexOf('### Step 2 — Analyse the Log')
            $triage | Should -BeGreaterThan $understanding
            $analysis | Should -BeGreaterThan $triage
        }

        It 'names every symptom class that triggers it' {
            foreach ($symptom in @('order', 'position', 'layout', 'grouping', 'rendering sequence')) {
                $script:TriageStep | Should -BeLike "*$symptom*"
            }
            $script:TriageStep | Should -Match '(?i)before you return\s+`needs-log`'
        }

        It 'lists the six triage steps in order' {
            $letters = @([regex]::Matches($script:TriageStep, '(?m)^([a-f])\.\s') |
                    ForEach-Object { $_.Groups[1].Value })
            ($letters -join '') | Should -Be 'abcdef'
        }

        It 'gives the exact history commands, not a suggestion to look around' {
            $script:TriageStep | Should -BeLike '*git log --all --oneline -S*'
            $script:TriageStep | Should -BeLike '*git log --all --oneline --*'
            $script:TriageStep | Should -BeLike '*git show <commit> -- <key file>*'
        }

        It 'bounds the search to one hop and sends the agent back to the key files' {
            $script:TriageStep | Should -Match '(?i)fixed list, not an invitation to explore'
            $script:TriageStep | Should -Match '(?i)at most one history hop'
            $script:TriageStep | Should -Match '(?i)return to\s+the Key Files'
        }

        It 'makes needs-log conditional on the triage finding nothing' {
            $script:SkillRaw | Should -Match '(?i)`status: needs-log`.*Step 1b triage found no'
        }

        It 'no longer sends the agent straight to the log from a bare symptom' {
            $script:SkillRaw | Should -Not -Match '(?i)request the diagnostic log before proceeding'
            $script:SkillRaw | Should -Match '(?i)run Step 1b before you ask for the diagnostic log'
        }
    }

    Context 'the result separates root cause from runtime verification' {
        BeforeAll {
            $script:Contract = [regex]::Match(
                (Get-Content -LiteralPath $script:SkillPath -Raw),
                '(?ms)^## Output Contract\s*$.*?(?=^## |\z)').Value
        }

        It 'carries the six statuses, including the two this task adds' {
            foreach ($status in @('diagnosed', 'fixed', 'needs-log', 'blocked', 'setup-failed', 'verification-unconfirmed')) {
                $script:Contract | Should -BeLike "*$status*"
            }
        }

        It 'carries every field a reader needs to weigh the diagnosis' {
            foreach ($field in @(
                    'status', 'issueClass', 'rootCause', 'affectedFiles', 'evidenceUsed',
                    'alternativeHypotheses', 'proposedFix', 'confidence',
                    'runtimeVerificationStatus', 'testCommand')) {
                $script:Contract | Should -BeLike "*`"$field`"*"
            }
        }

        It 'says confidence measures the root cause only, and verification is separate' {
            $script:Contract | Should -Match '(?i)It measures the \*\*root cause only\*\*'
            $script:Contract | Should -Match '(?i)`runtimeVerificationStatus` is separate from `confidence`'
        }

        It 'refuses both collapses in the same place' {
            $script:Contract | Should -Match '(?i)A build is not a test result\. Historical evidence is not\s+runtime verification'
            $script:Contract | Should -Match '(?i)Never say the drawing is fixed without a regenerated drawing or an executed targeted test'
        }

        It 'shows the three-line report a person reads' {
            $script:Contract | Should -BeLike '*root-cause confidence:*'
            $script:Contract | Should -BeLike '*runtime reproduction:*'
            $script:Contract | Should -BeLike '*fix verification:*'
        }

        It 'lists all five conditions that make a runtime log optional' {
            $path = [regex]::Match($script:Contract,
                '(?ms)^### The historical-regression evidence path\s*$.*?(?=^### |\z)').Value
            $path | Should -Match '(?i)\*\*all five\*\*'
            @([regex]::Matches($path, '(?m)^\d\.\s')).Count | Should -Be 5
            $path | Should -Match '(?i)Miss any one of them and the answer is `needs-log`'
            $path | Should -Match '(?i)return\s+`diagnosed` with `runtimeVerificationStatus: unavailable`, never `fixed`'
        }
    }

    Context 'the phase map says who owns what' {
        BeforeAll {
            $script:Architecture = Get-Content -LiteralPath (Join-Path $script:ReferenceFolder 'architecture.md') -Raw
            $script:PhaseSection = [regex]::Match(
                $script:Architecture, '(?ms)^## Phase Ownership\s*$.*?(?=^## |\z)').Value
        }

        It 'names every method a wrong-layer edit could reach for' {
            foreach ($method in @(
                    'OrderSequence()'
                    'ApplyPlateOrdering()'
                    'GetDwgPlateCollectionOrder()'
                    'ConnectedEquipmentGroupResolver.GetGroupableContainedEquipment()'
                    'ConnectedEquipmentGroupResolver.GetAllChildren()'
                    'PlaceLoc0Groups()'
                    'LayoutAdjustmentService.AdjustConnectedDeviceVerticalOverlaps()')) {
                $script:PhaseSection | Should -BeLike "*$method*"
            }
        }

        It 'separates ordering, placement and post-placement adjustment' {
            foreach ($phase in @('Model ordering', 'Group resolution', 'Placement', 'Post-placement adjustment')) {
                $script:PhaseSection | Should -BeLike "*$phase*"
            }
        }

        It 'explains ContainedEquipment against CanHavePartEquipment' {
            $script:PhaseSection | Should -Match '(?m)^### ContainedEquipment and CanHavePartEquipment\s*$'
            $script:PhaseSection | Should -Match '(?i)The first is data, the second is a capability'
            $script:PhaseSection | Should -Match '(?i)ignores nested rail and compartment contents'
        }

        It 'carries all six rows of the symptom-to-owner table' {
            $table = [regex]::Match($script:PhaseSection,
                '(?ms)^### Which owner to inspect first\s*$.*?(?=^### |\z)').Value
            $rows = @([regex]::Matches($table, '(?m)^\|(?!\s*-).*\|\s*$'))
            ($rows.Count - 1) | Should -Be 6
            foreach ($symptom in @(
                    'Wrong `MODEL-DONE` order'
                    'Correct `MODEL-DONE`, wrong position'
                    'Correct model, missing shape'
                    'Update-only stale shape'
                    'Wrong connector visibility'
                    'Duplicate connected equipment')) {
                # -BeLike would eat the backticks: in a wildcard pattern a backtick is the escape
                # character, so '`MODEL-DONE`' would look for MODEL-DONE without them.
                $table | Should -Match ([regex]::Escape($symptom))
            }
        }

        It 'warns that the shared resolver is almost never the right place' {
            $script:PhaseSection | Should -Match '(?i)broader abstraction, and\s+it is shared'
            $script:PhaseSection | Should -Match '(?i)almost\s+never the right place to fix a symptom seen on one rail'
        }

        It 'states the one-phase-later rule and its no-log exception' {
            $rule = [regex]::Match($script:PhaseSection,
                '(?ms)^### The one-phase-later rule\s*$.*?(?=^### |\z)').Value
            $rule | Should -Match '(?i)is not the place to edit'
            $rule | Should -Match '(?i)Move one phase later'
            $rule | Should -Match '(?i)Label runtime confirmation as missing'
        }
    }

    Context 'the hypothesis is recorded before the edit' {
        BeforeAll {
            $script:PreEdit = [regex]::Match(
                (Get-Content -LiteralPath $script:SkillPath -Raw),
                '(?ms)^### Step 3b — Record the Hypothesis Before You Edit\s*$.*?(?=^### |\z)').Value
        }

        It 'sits between reading the source and implementing the fix' {
            $raw = Get-Content -LiteralPath $script:SkillPath -Raw
            $read = $raw.IndexOf('### Step 3 — Read Source Before Touching It')
            $record = $raw.IndexOf('### Step 3b — Record the Hypothesis Before You Edit')
            $implement = $raw.IndexOf('### Step 4 — Implement the Fix')
            $record | Should -BeGreaterThan $read
            $implement | Should -BeGreaterThan $record
        }

        It 'asks for all six lines' {
            @([regex]::Matches($script:PreEdit, '(?m)^\d\.\s')).Count | Should -Be 6
            foreach ($item in @(
                    'the symptom', 'the expected phase', 'the owning method',
                    'falsifiable hypothesis', 'cheaper alternative hypothesis',
                    'discriminating evidence')) {
                $script:PreEdit | Should -BeLike "*$item*"
            }
        }

        It 'blocks the edit when the discriminating evidence cannot be named' {
            $script:PreEdit | Should -Match '(?i)you are not ready to edit'
        }

        It 'repeats the one-phase-later rule where the edit happens' {
            $script:PreEdit | Should -Match '(?i)do not change model ordering code'
            $script:PreEdit | Should -Match '(?i)move one\s+phase later'
        }
    }
}
