#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiTestScaffolder' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-test-scaffolder' 'scripts' 'Invoke-EiTestScaffolder.ps1'
    }

    It 'returns blocked when target class is missing' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        $result.manualAssertionsRequired | Should -BeTrue
    }

    It 'returns needs-manual-review when test project path is not supplied' {
        $output = & $script:ScriptPath -TargetClass 'CableService' -Methods @('ValidateCable') -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        ($result.suggestedTestNames -contains 'ValidateCable_WhenInvoked_ExpectedBehavior') | Should -BeTrue
        $result.outputPaths | Should -BeNullOrEmpty
    }

    It 'returns ready and resolves constructor dependencies when class file and test project path are supplied' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiTestScaffolder_' + [System.IO.Path]::GetRandomFileName())
        $classDir = Join-Path $tempRoot 'src'
        $testDir = Join-Path $tempRoot 'tests'
        New-Item -Path $classDir -ItemType Directory -Force | Out-Null
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null

        try {
            $classPath = Join-Path $classDir 'CableService.cs'
            @'
public class CableService
{
    public CableService(ICableRepository cableRepository, ILogger logger)
    {
    }

    public bool ValidateCable(string id)
    {
        return true;
    }
}
'@ | Set-Content -LiteralPath $classPath

            $output = & $script:ScriptPath -TargetClass $classPath -TestProjectPath $testDir -Json
            $LASTEXITCODE | Should -Be 0
            $result = $output | ConvertFrom-Json

            $result.status | Should -Be 'ready'
            ($result.mockDependencies -contains 'ICableRepository') | Should -BeTrue
            ($result.mockDependencies -contains 'ILogger') | Should -BeTrue
            $result.resolverSetupRequired | Should -BeTrue
            ($result.suggestedTestNames -contains 'ValidateCable_WhenInvoked_ExpectedBehavior') | Should -BeTrue
            ($result.outputPaths | Select-Object -First 1) | Should -Match 'CableService\.Tests\.cs$'
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
