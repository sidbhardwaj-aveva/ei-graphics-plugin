#Requires -Version 7.0
Set-StrictMode -Version Latest

# Pester needs -ForEach data at discovery time, so the once-only statements are listed here.
# Each pattern matches every wording the file has ever used for that statement, so a repeat
# cannot come back under a rephrasing.
$OnceOnlyStatement = @(
    @{ Name = 'do not read the identifier off the link'; Pattern = 'identifier off the link' }
    @{ Name = 'the script writes nothing'; Pattern = 'writes no file|writes nothing to disk' }
    @{ Name = 'the scripts take no pipeline input'; Pattern = '(?i)pipeline input' }
    @{ Name = 'an unread discussion is not an empty one'; Pattern = 'an empty one' }
    @{ Name = 'the returned story text is plain'; Pattern = '(?i)is plain text|return plain text' }
)

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

    Context 'the document says each thing once' {

        It 'states <Name> exactly once' -ForEach $OnceOnlyStatement {
            $hits = @([regex]::Matches($script:Raw, $Pattern))
            $hits.Count | Should -Be 1 -Because "'$Name' is stated $($hits.Count) times. One copy, where the reader needs it."
        }

        It 'lists three rules, none of them a summary of a section above' {
            $rules = [regex]::Match($script:Raw, '(?ms)^## Rules\r?\n(.*?)(?=^## )')
            $rules.Success | Should -BeTrue
            $numbered = @([regex]::Matches($rules.Groups[1].Value, '(?m)^\d+\.\s'))
            $numbered.Count | Should -Be 3 -Because 'the rules that restated the sections above them were folded back into those sections'
        }
    }
}
