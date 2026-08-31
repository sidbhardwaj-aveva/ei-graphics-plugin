#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:RepoRoot = $repoRoot
    $script:SkillFolder = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-layer-guard'
    $script:ScriptPath = Join-Path $script:SkillFolder 'scripts' 'Invoke-EiLayerGuard.ps1'
    $script:HashFile = Join-Path $repoRoot 'tests' 'data' 'ported-file-hashes.json'
}

Describe 'ei-layer-guard, as copied' -Tag 'Unit' {

    It '<_> still matches its recorded hash' -ForEach @(
        'plugins/demo-ei-graphics/skills/ei-layer-guard/SKILL.md'
        'plugins/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1'
    ) {
        $recorded = (Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json).files.$_
        $recorded | Should -Match '^sha256:[0-9a-f]{64}$'
        $actual = 'sha256:' + (Get-FileHash -LiteralPath (Join-Path $script:RepoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
        $actual | Should -Be $recorded
    }

    It 'the test file is not hashed, because this task edits it' {
        $recorded = (Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json).files
        $recorded.PSObject.Properties.Name |
            Should -Not -Contain 'tests/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.Tests.ps1'
    }

    It 'the copied test file points at the renamed plugin folder' {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-EiLayerGuard.Tests.ps1') -Raw
        $raw | Should -BeLike "*'demo-ei-graphics'*"
        $raw | Should -Not -BeLike '*aveva-ei-graphics*'
        # Renaming a folder does not change how deep it sits, so the chain stays at five.
        $raw | Should -BeLike "*Join-Path `$PSScriptRoot '..' '..' '..' '..' '..'*"
    }

    It 'the skill document needed no rewrite' {
        $raw = Get-Content -LiteralPath (Join-Path $script:SkillFolder 'SKILL.md') -Raw
        $raw | Should -Not -Match '(?i)workflow-state|lifecycle|EIWF-|aveva-ei-graphics'
    }

    It 'the skill name matches its folder' {
        $raw = Get-Content -LiteralPath (Join-Path $script:SkillFolder 'SKILL.md') -Raw
        ([regex]::Match($raw, '(?m)^name:\s*(\S+)\s*$')).Groups[1].Value | Should -Be 'ei-layer-guard'
    }

    It 'still reports one of the three outcomes it has always reported' {
        $result = & $script:ScriptPath -ChangedFiles @('src/Anything.cs') -Json
        $status = (($result -join "`n") | ConvertFrom-Json).status
        @('pass', 'blocked', 'needs-manual-review') | Should -Contain $status
    }

    It 'still honours -Json by writing parsable JSON to stdout' {
        $result = & $script:ScriptPath -ChangedFiles @('src/Anything.cs') -Json
        { ($result -join "`n") | ConvertFrom-Json } | Should -Not -Throw
    }
}
