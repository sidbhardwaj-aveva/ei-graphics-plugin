#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time data. Pester needs -ForEach filled before any BeforeAll block runs.
# The two scripts a second run does not leave alone, what it leaves, and what the reader is told to
# do about it. Write-EiSessionEntry appends; the other reaches the share. Complete-EiSession used to
# belong here and no longer does, because T062 made its finalize step refuse a closed session.
$NotRepeatable = @(
    @{ Script = 'Write-EiSessionEntry.ps1'; Leaves = '(?i)second entry'; Remedy = '(?i)remove a duplicate' }
    @{ Script = 'Export-EiSessionBundleToShare.ps1'; Leaves = '(?i)second copy'; Remedy = '(?i)delete the extra folder' }
)

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
    $script:SkillFolder = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
    $script:SkillPath = Join-Path $script:SkillFolder 'SKILL.md'
    $script:Lines = @(Get-Content -LiteralPath $script:SkillPath)
    $script:Raw = Get-Content -LiteralPath $script:SkillPath -Raw

    $script:CoreScripts = @(
        'Resolve-EiScriptPath.ps1'
        'Write-EiArtifact.ps1'
        'Write-EiSessionEntry.ps1'
        'Export-EiSessionSummary.ps1'
        'Export-EiSessionBundleToShare.ps1'
        'Get-EiDomainSkillCatalog.ps1'
        'Test-EiScopeDrift.ps1'
        'Convert-EiAdoIntake.ps1'
        'Invoke-EiStoryIntake.ps1'
        'Complete-EiSession.ps1'
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

    # Raised from 160 in T060, which gave every script its own statement about a second run.
    It 'is 180 lines or fewer' {
        $script:Lines.Count | Should -BeLessOrEqual 180
    }

    It 'names <_>' -ForEach @(
        'Resolve-EiScriptPath.ps1'
        'Write-EiArtifact.ps1'
        'Write-EiSessionEntry.ps1'
        'Export-EiSessionSummary.ps1'
        'Export-EiSessionBundleToShare.ps1'
        'Get-EiDomainSkillCatalog.ps1'
        'Test-EiScopeDrift.ps1'
        'Convert-EiAdoIntake.ps1'
        'Invoke-EiStoryIntake.ps1'
        'Complete-EiSession.ps1'
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

    It 'no longer promises that any command is safe to run twice' {
        $script:Raw | Should -Not -Match '(?i)running the same command twice is safe'
    }

    It 'says what a second run of each script does' {
        foreach ($name in $script:CoreScripts) {
            $section = [regex]::Match($script:Raw, "(?ms)^## ``$([regex]::Escape($name))``\s*$.*?(?=^## |\z)")
            $section.Success | Should -BeTrue -Because "$name needs its own section"
            $statement = [regex]::Match($section.Value, '(?ms)^\*\*Run again:\*\*\s+(.*?)(?=\r?\n\r?\n|\z)')
            $statement.Success | Should -BeTrue -Because "$name must say what a second run does"
            $statement.Groups[1].Value | Should -Match '(?i)\b(safe|not safe)\b' -Because "$name must answer plainly"
        }
    }

    It 'says what a second run of <Script> leaves behind, and what to do about it' -ForEach $NotRepeatable {
        $section = [regex]::Match($script:Raw, "(?ms)^## ``$([regex]::Escape($Script))``\s*$.*?(?=^## |\z)")
        $statement = [regex]::Match($section.Value, '(?ms)^\*\*Run again:\*\*\s+(.*?)(?=\r?\n\r?\n|\z)').Groups[1].Value
        # The statement wraps across lines, so a phrase can straddle a line break.
        $statement = ($statement -replace '\s+', ' ').Trim()

        $statement | Should -Match '(?i)not safe'
        $statement | Should -Match $Leaves
        $statement | Should -Match $Remedy
    }

    It 'says the close command refuses a second run, and what -Force costs' {
        $section = [regex]::Match($script:Raw, '(?ms)^## `Complete-EiSession\.ps1`\s*$.*?(?=^## |\z)')
        $statement = [regex]::Match($section.Value, '(?ms)^\*\*Run again:\*\*\s+(.*?)(?=\r?\n\r?\n|\z)').Groups[1].Value
        $statement = ($statement -replace '\s+', ' ').Trim()

        $statement | Should -Not -Match '(?i)not safe'
        $statement | Should -Match '(?i)refuses'
        $statement | Should -Match '(?i)exits 1'
        $statement | Should -Match '(?i)-Force'
        $statement | Should -Match '(?i)second copy'
    }

    It 'says the finalize step refuses a session that is already closed' {
        $section = [regex]::Match($script:Raw, '(?ms)^## `Write-EiSessionEntry\.ps1`\s*$.*?(?=^## |\z)')
        $section.Value | Should -Not -Match '(?i)repeating `-Finalize` itself is safe'
        $statement = [regex]::Match($section.Value, '(?ms)^\*\*Run again:\*\*\s+(.*?)(?=\r?\n\r?\n|\z)').Groups[1].Value
        ($statement -replace '\s+', ' ') | Should -Match '(?i)refuses a session that already holds a summary'
    }
}
