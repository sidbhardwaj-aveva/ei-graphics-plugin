#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:SkillFolder = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:SkillPath = Join-Path $script:SkillFolder 'SKILL.md'
    $script:Lines = @(Get-Content -LiteralPath $script:SkillPath)
    $script:Raw = Get-Content -LiteralPath $script:SkillPath -Raw

    $script:CoreScripts = @(
        'Write-EiArtifact.ps1'
        'Write-EiSessionEntry.ps1'
        'Export-EiSessionSummary.ps1'
        'Get-EiDomainSkillCatalog.ps1'
        'Test-EiScopeDrift.ps1'
        'Convert-EiAdoIntake.ps1'
    )
}

Describe 'ei-graphics-core SKILL.md' -Tag 'Unit' {

    It 'exists' {
        Test-Path -LiteralPath $script:SkillPath | Should -BeTrue
    }

    It 'has frontmatter with a name and a description' {
        $script:Raw | Should -Match '(?s)\A---\r?\n.*?\r?\n---\r?\n'
        $script:Raw | Should -Match '(?m)^name:\s*\S'
        $script:Raw | Should -Match '(?m)^description:\s*\S'
    }

    It 'has a name equal to its folder name' {
        $declared = ([regex]::Match($script:Raw, '(?m)^name:\s*(\S+)\s*$')).Groups[1].Value
        $declared | Should -Be (Split-Path -Leaf $script:SkillFolder)
    }

    It 'is 120 lines or fewer' {
        $script:Lines.Count | Should -BeLessOrEqual 120
    }

    It 'names <_>' -ForEach @(
        'Write-EiArtifact.ps1'
        'Write-EiSessionEntry.ps1'
        'Export-EiSessionSummary.ps1'
        'Get-EiDomainSkillCatalog.ps1'
        'Test-EiScopeDrift.ps1'
        'Convert-EiAdoIntake.ps1'
    ) {
        $script:Raw | Should -BeLike "*$_*"
    }

    It 'gives every script a parameter list, an output shape and its exit codes' {
        foreach ($name in $script:CoreScripts) {
            $section = [regex]::Match($script:Raw, "(?ms)^## ``$([regex]::Escape($name))``\s*$.*?(?=^## |\z)")
            $section.Success | Should -BeTrue -Because "$name needs its own section"
            $section.Value | Should -Match 'Parameters'
            $section.Value | Should -Match 'Output'
            $section.Value | Should -Match 'Exit codes'
        }
    }

    It 'carries no workflow narrative, because the agent owns the flow' {
        $script:Raw | Should -Not -Match '(?i)\blifecycle\b'
        $script:Raw | Should -Not -Match '(?i)\bstage\b'
    }
}
