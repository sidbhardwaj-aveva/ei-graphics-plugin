#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:SkillFolder = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake'
    $script:SkillPath = Join-Path $script:SkillFolder 'SKILL.md'
    $script:Raw = Get-Content -LiteralPath $script:SkillPath -Raw
}

Describe 'ei-azure-devops-cli-intake SKILL.md' -Tag 'Unit' {

    It 'carries a Canonical invocation subsection' {
        $script:Raw | Should -Match '(?m)^###\s+Canonical invocation\s*$'
    }

    It 'shows the three-script pipe in a single powershell code fence' {
        $blocks = @(
            [regex]::Matches($script:Raw, '(?ms)^```powershell\r?\n(.*?)^```\s*$') |
                ForEach-Object { $_.Groups[1].Value }
        )
        $matching = @($blocks | Where-Object {
            ($_ -match 'Invoke-EiAdoCliIntake\.ps1') -and
            ($_ -match 'Convert-EiAdoIntake\.ps1') -and
            ($_ -match 'Write-EiArtifact\.ps1') -and
            ($_ -match '-ArtifactType\s+ado')
        })
        $matching.Count | Should -Be 1 -Because 'one powershell fence should carry the whole three-script pipe end to end'
    }
}
