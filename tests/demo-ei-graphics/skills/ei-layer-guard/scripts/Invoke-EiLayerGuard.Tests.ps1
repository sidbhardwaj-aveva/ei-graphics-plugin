#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiLayerGuard' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-layer-guard' 'scripts' 'Invoke-EiLayerGuard.ps1'
    }

    It 'returns pass when an application project references only allowed non-presentation projects' {
        $projectPath = Join-Path $TestDrive 'Aveva.EI.Commands.csproj'
        @'
<Project>
  <ItemGroup>
    <ProjectReference Include="..\Aveva.EI.DomainServices\Aveva.EI.DomainServices.csproj" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $projectPath

        $output = & $script:ScriptPath -ChangedProjects $projectPath -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'pass'
        $result.violations | Should -BeNullOrEmpty
    }

    It 'returns blocked when an application project references a presentation project' {
        $projectPath = Join-Path $TestDrive 'Aveva.EI.Commands.csproj'
        @'
<Project>
  <ItemGroup>
    <ProjectReference Include="..\Aveva.EI.UI\Aveva.EI.UI.csproj" />
  </ItemGroup>
</Project>
'@ | Set-Content -LiteralPath $projectPath

        $output = & $script:ScriptPath -ChangedProjects $projectPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        ($result.violations[0].Code) | Should -Be 'EILG001'
    }

    It 'returns blocked when a changed source file introduces catch Exception' {
        $filePath = Join-Path $TestDrive 'Example.cs'
        @'
try {
    Invoke-Something
}
catch (Exception ex) {
    throw
}
'@ | Set-Content -LiteralPath $filePath

        $output = & $script:ScriptPath -ChangedFiles $filePath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        ($result.reviewFlags[0].Code) | Should -Be 'EILG003'
    }

    It 'returns blocked when a changed path is a build artifact' {
        $artifactPath = Join-Path $TestDrive 'x64\Debug\ScriptService.cs'
        $artifactDirectory = Split-Path -Parent $artifactPath
        New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
        'class ScriptService {}' | Set-Content -LiteralPath $artifactPath

        $output = & $script:ScriptPath -ChangedFiles $artifactPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        ($result.reviewFlags[0].Code) | Should -Be 'EILG004'
    }

    It 'returns needs-manual-review when a schema mapping file changes' {
        $mappingPath = Join-Path $TestDrive 'ClassUris.cs'
        'public static class ClassUris {}' | Set-Content -LiteralPath $mappingPath

        $output = & $script:ScriptPath -ChangedFiles $mappingPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        ($result.reviewFlags[0].Code) | Should -Be 'EILG002'
    }

    It 'returns needs-manual-review when mapping attributes are detected in a source file' {
        $mappingPath = Join-Path $TestDrive 'MappedObject.cs'
        @'
[ClassMapping]
public class MappedObject {}
'@ | Set-Content -LiteralPath $mappingPath

        $output = & $script:ScriptPath -ChangedFiles $mappingPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        ($result.reviewFlags[0].Code) | Should -Be 'EILG002'
    }

    It 'returns needs-manual-review when no inputs are provided' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
    }
}