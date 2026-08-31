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
        'plugins/demo-ei-graphics/README.md'
        'plugins/demo-ei-graphics/INSTRUCTIONS.md'
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

    It 'the root README lists the prerequisites and the improvement loop' {
        $raw = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw) -replace '\s+', ' '
        $raw | Should -Match '(?i)az.{0,20}signed in'
        $raw | Should -Match '(?i)working tree is clean'
        $raw | Should -Match '(?i)dotnet'
        $raw | Should -Match '(?i)session-summary\.md'
        $raw | Should -Match '(?i)Key Files'
    }

    It 'the plugin README lists every skill folder that exists on disk' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/demo-ei-graphics/README.md') -Raw
        $skills = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'plugins/demo-ei-graphics/skills') -Directory)
        $skills.Count | Should -BeGreaterThan 0
        foreach ($skill in $skills) { $raw | Should -BeLike "*$($skill.Name)*" }
    }

    It 'the plugin README lists every artifact a run produces' {
        $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugins/demo-ei-graphics/README.md') -Raw
        foreach ($artifact in @('ado.json', 'story-understanding.json', 'approved-files.json',
                'session.json', 'session-summary.md')) {
            $raw | Should -BeLike "*$artifact*"
        }
    }

    It 'PLUGIN-INFO.md names the plugin as the folder does' {
        $folderName = Split-Path -Leaf (Join-Path $script:RepoRoot 'plugins' 'demo-ei-graphics')
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'PLUGIN-INFO.md') -Raw) |
            Should -BeLike "*$folderName*"
    }
}
