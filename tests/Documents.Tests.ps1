#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:CopilotPath = Join-Path $script:RepoRoot '.github' 'copilot-instructions.md'
}

Describe 'The documents' -Tag 'Unit' {

    It '<_> exists and is not empty' -ForEach @(
        'README.md'
        'PLUGIN-INFO.md'
        'plugins/aveva-ei-graphics/README.md'
        'plugins/aveva-ei-graphics/INSTRUCTIONS.md'
        '.github/copilot-instructions.md'
    ) {
        $path = Join-Path $script:RepoRoot $_
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw).Trim().Length | Should -BeGreaterThan 0
    }

    It 'copilot-instructions.md names <_>' -ForEach @(
        'Test-BuildProgress.ps1'
        'gc.auto=0'
        'Set-StrictMode'
    ) {
        (Get-Content -LiteralPath $script:CopilotPath -Raw) | Should -BeLike "*$_*"
    }

    It 'copilot-instructions.md carries the per-task loop and the machines-decide rule' {
        $raw = Get-Content -LiteralPath $script:CopilotPath -Raw
        $raw | Should -Match '(?i)only machines decide'
        $raw | Should -Match 'build\(T0NN\): start'
        $raw | Should -Match 'chore\(T0NN\): record commit sha'
        $raw | Should -Match '(?i)three commits per task'
    }

    It 'the root README lists marketplace installation and update instructions' {
        $raw = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw) -replace '\s+', ' '
        $raw | Should -Match 'PLUGIN-INFO\.md'
        $raw | Should -Match 'chat\.plugins\.marketplaces'
        $raw | Should -Match 'AVEVA-Copilot-Access/aveva-agent-plugins'
        $raw | Should -Match 'sidbhardwaj-aveva/ei-graphics-plugin'
        $raw | Should -Match 'aveva-ei-graphics'
        $raw | Should -Match 'fetch origin'
        $raw | Should -Match 'reset --hard origin/main'
        $raw | Should -Match '(?i)new installations do not need this'
        $raw | Should -Match 'EI_GRAPHICS_SHARE_PATH'
        $raw | Should -Match 'INHYDD1510\\Share\\ei-graphics-plugin-sessions'
        $raw | Should -Match 'git -C.*agent-plugins.*ei-graphics-plugin.*pull'
    }

    It 'the plugin README lists every skill folder that exists on disk' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/README.md') -Raw
        $skills = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/skills') -Directory)
        $skills.Count | Should -BeGreaterThan 0
        foreach ($skill in $skills) { $raw | Should -BeLike "*$($skill.Name)*" }
    }

    It 'the plugin README lists every artifact a run produces' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/README.md') -Raw
        foreach ($artifact in @('ado.json', 'story-understanding.json', 'approved-files.json',
                'session.json', 'session-summary.md')) {
            $raw | Should -BeLike "*$artifact*"
        }
    }

    It 'the plugin README gives maintainers the investigation steps in order' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/README.md') -Raw
        $section = [regex]::Match($raw, '(?s)## Investigation order\s+(.*?)\s+### Worked example').Groups[1].Value
        $steps = @('Intake', 'Write the understanding', 'Checkpoint', 'Select the domain',
            'Read the domain', 'Triage bounded history', 'Inspect key files', 'State a hypothesis',
            'Make the smallest edit', 'Run focused validation', 'Run the layer guard',
            'Close the session', 'Check the summary')

        $section | Should -Not -BeNullOrEmpty
        $lastIndex = -1
        foreach ($step in $steps) {
            $index = $section.IndexOf($step, [StringComparison]::Ordinal)
            $index | Should -BeGreaterThan $lastIndex -Because "'$step' must follow the prior step"
            $lastIndex = $index
        }
    }

    It 'the plugin README works the mounting-rail regression through that order' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/README.md') -Raw
        $example = [regex]::Match($raw, '(?s)### Worked example: a mounting-rail ordering regression\s+(.*?)\s+## Folder tree').Groups[1].Value

        $example | Should -Match '(?i)one example'
        $example | Should -Match '(?i)other bugs and other domain skills'
        $example | Should -Match ([regex]::Escape('TS-1, B-1, --134, IOM-1'))
        $example | Should -Match ([regex]::Escape('OrderSequence()'))
        $example | Should -Match ([regex]::Escape('ApplyPlateOrdering()'))
        $example | Should -Match '(?i)plated and unplated'
        $example | Should -Match ([regex]::Escape('Complete-EiSession.ps1'))
        @($example -split "`r?`n" | Where-Object { $_ -match '^\d+\.' }).Count | Should -Be 13
    }

    It 'PLUGIN-INFO.md names the plugin as the folder does' {
        $folderName = Split-Path -Leaf (Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics')
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'PLUGIN-INFO.md') -Raw) |
            Should -BeLike "*$folderName*"
    }

    It 'PLUGIN-INFO.md explains the approved shared-session location' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'PLUGIN-INFO.md') -Raw
        $raw | Should -Match 'EI_GRAPHICS_SHARE_PATH'
        $raw | Should -Match 'INHYDD1510\\Share\\ei-graphics-plugin-sessions'
        $raw | Should -Not -Match 'Siddanth'
        $raw | Should -Match 'story text, comments, interactions, and evidence'
    }

    # The count drifted for six tasks because no test read it off disk. Every document that states
    # it is checked against the folder, so the next script to join cannot leave one of them stale.
    It 'every document that counts the core scripts agrees with the scripts folder' {
        $scriptsFolder = Join-Path $script:RepoRoot 'plugins/aveva-ei-graphics/skills/ei-graphics-core/scripts'
        $onDisk = @(Get-ChildItem -LiteralPath $scriptsFolder -Filter '*.ps1' -File).Count
        $onDisk | Should -BeGreaterThan 0

        $numberWords = @{
            one = 1; two = 2; three = 3; four = 4; five = 5; six = 6; seven = 7; eight = 8
            nine = 9; ten = 10; eleven = 11; twelve = 12; thirteen = 13; fourteen = 14; fifteen = 15
        }

        foreach ($relative in @(
                'plugins/aveva-ei-graphics/README.md'
                'plugins/aveva-ei-graphics/skills/ei-graphics-core/SKILL.md'
                'docs/presentation/04-components.mmd'
                'docs/presentation/04-components.html'
            )) {
            $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot $relative) -Raw
            $stated = 0
            foreach ($match in [regex]::Matches($raw, '(?i)\b([a-z]+|\d+)\s+(?:core\s+)?scripts\b')) {
                $token = $match.Groups[1].Value.ToLowerInvariant()
                $count = if ($numberWords.ContainsKey($token)) { $numberWords[$token] }
                         elseif ($token -match '^\d+$') { [int] $token }
                         else { $null }   # prose such as "core scripts" states no count
                if ($null -eq $count) { continue }

                $stated++
                $count | Should -Be $onDisk -Because "$relative says '$($match.Value.Trim())' and the folder holds $onDisk"
            }
            $stated | Should -BeGreaterThan 0 -Because "$relative should state how many core scripts there are"
        }
    }
}
