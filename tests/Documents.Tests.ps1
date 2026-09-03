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
}
