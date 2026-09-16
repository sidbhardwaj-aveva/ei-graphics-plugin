#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:InstalledRoot = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts'
    $script:ScriptPath = Join-Path $script:InstalledRoot 'Resolve-EiScriptPath.ps1'

    $script:Roster = @(
        'Complete-EiSession.ps1'
        'Convert-EiAdoIntake.ps1'
        'Export-EiSessionBundleToShare.ps1'
        'Export-EiSessionSummary.ps1'
        'Get-EiDomainSkillCatalog.ps1'
        'Invoke-EiStoryIntake.ps1'
        'Resolve-EiScriptPath.ps1'
        'Test-EiScopeDrift.ps1'
        'Write-EiArtifact.ps1'
        'Write-EiSessionEntry.ps1'
    )

    function New-FakeInstall {
        <#
        .SYNOPSIS
            Builds a scripts folder under TestDrive and returns its path.
        .DESCRIPTION
            -Tail is the folder chain below the fake install root, so a test can leave out
            plugins\aveva-ei-graphics and prove that path is refused. -Omit names a roster entry
            to leave out.
        #>
        param([string[]] $Tail, [string] $Omit)
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($part in $Tail) { $folder = Join-Path $folder $part }
        $null = New-Item -ItemType Directory -Path $folder -Force
        foreach ($name in $script:Roster) {
            if ($name -eq $Omit) { continue }
            Set-Content -LiteralPath (Join-Path $folder $name) -Value '# placeholder' -Encoding utf8NoBOM
        }
        $folder
    }

    $script:CoreTail = @('plugins', 'aveva-ei-graphics', 'skills', 'ei-graphics-core', 'scripts')
}

Describe 'Resolve-EiScriptPath' -Tag 'Unit' {

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }

    Context 'resolving one script from the installed layout' {

        It 'returns the absolute path of a named script without being told where it lives' {
            $result = & $script:ScriptPath -Name 'Write-EiSessionEntry.ps1'
            $LASTEXITCODE | Should -Be 0
            $result.status | Should -Be 'resolved'
            $result.path | Should -Be (Join-Path $script:InstalledRoot 'Write-EiSessionEntry.ps1')
            Test-Path -LiteralPath $result.path | Should -BeTrue
        }

        It 'accepts a name with no .ps1 on the end' {
            $result = & $script:ScriptPath -Name 'Complete-EiSession'
            $result.name | Should -Be 'Complete-EiSession.ps1'
            Test-Path -LiteralPath $result.path | Should -BeTrue
        }

        It 'resolves <_> to a file that exists' -ForEach @(
            'Complete-EiSession.ps1'
            'Convert-EiAdoIntake.ps1'
            'Export-EiSessionBundleToShare.ps1'
            'Export-EiSessionSummary.ps1'
            'Get-EiDomainSkillCatalog.ps1'
            'Invoke-EiStoryIntake.ps1'
            'Resolve-EiScriptPath.ps1'
            'Test-EiScopeDrift.ps1'
            'Write-EiArtifact.ps1'
            'Write-EiSessionEntry.ps1'
        ) {
            Test-Path -LiteralPath (& $script:ScriptPath -Name $_).path | Should -BeTrue
        }

        It 'emits JSON for -Json' {
            $text = (& $script:ScriptPath -Name 'Write-EiArtifact.ps1' -Json) -join "`n"
            { $text | ConvertFrom-Json } | Should -Not -Throw
            ($text | ConvertFrom-Json).name | Should -Be 'Write-EiArtifact.ps1'
        }

        It 'refuses a name that is not a core script, and lists the ones that are' {
            $err = pwsh -NoProfile -File $script:ScriptPath -Name 'Invoke-EiGraphicsDoctor.ps1' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)is not a core script'
            ($err -join "`n") | Should -Match 'Complete-EiSession\.ps1'
        }
    }

    Context 'checking the roster' {

        It 'reports the whole roster complete when no name is given' {
            $result = & $script:ScriptPath
            $LASTEXITCODE | Should -Be 0
            $result.status | Should -Be 'complete'
            $result.scripts.Count | Should -Be 10
            @($result.scripts | Where-Object { Test-Path -LiteralPath $_ }).Count | Should -Be 10
        }

        It 'names the missing script and exits 1' {
            $folder = New-FakeInstall -Tail $script:CoreTail -Omit 'Test-EiScopeDrift.ps1'
            $err = pwsh -NoProfile -File $script:ScriptPath -ScriptRoot $folder 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)incomplete'
            ($err -join "`n") | Should -Match 'missing: Test-EiScopeDrift\.ps1'
        }

        It 'fails a named lookup too when the roster is short' {
            $folder = New-FakeInstall -Tail $script:CoreTail -Omit 'Write-EiArtifact.ps1'
            $err = pwsh -NoProfile -File $script:ScriptPath -Name 'Complete-EiSession.ps1' -ScriptRoot $folder 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match 'missing: Write-EiArtifact\.ps1'
        }
    }

    Context 'refusing a path built by hand' {

        It 'refuses a scripts folder that leaves out plugins and the plugin name' {
            # The mistake that emptied the failed session: a full set of files under the wrong root.
            $folder = New-FakeInstall -Tail @('skills', 'ei-graphics-core', 'scripts')
            $err = pwsh -NoProfile -File $script:ScriptPath -Name 'Write-EiSessionEntry.ps1' -ScriptRoot $folder 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)not the core scripts folder'
            ($err -join "`n") | Should -Match ([regex]::Escape('plugins'))
        }

        It 'refuses a top-level scripts folder' {
            $folder = New-FakeInstall -Tail @('scripts')
            $err = pwsh -NoProfile -File $script:ScriptPath -ScriptRoot $folder 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)not the core scripts folder'
        }

        It 'says where to look when the folder does not exist at all' {
            $err = pwsh -NoProfile -File $script:ScriptPath -ScriptRoot (Join-Path $TestDrive 'nowhere') 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)There is no folder at'
        }
    }
}
