#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Validate-EiWorkflowPrerequisites' -Tag 'Unit' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
        $script:ScriptPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'Validate-EiWorkflowPrerequisites.ps1'
        $script:ManifestPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'references' 'required-capabilities.json'
    }

    It 'passes at Phase A when only the local state skill is required' {
        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase A -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Found | Should -Contain 'aveva-ei-graphics:ei-workflow-state'
        @($result.Details.MissingLaterPhase).Count | Should -BeGreaterThan 0
    }

    It 'fails closed with a marketplace install message when a required plugin is absent' {
        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase D -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 1

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Invalid'
        ($result.Errors -join "`n") | Should -BeLike '*aveva-rnd is not installed. Install it from the marketplace and retry.*'
        ($result.Errors -join "`n") | Should -BeLike '*aveva-core is not installed*'
    }

    It 'passes at Phase D when every required capability resolves from a search root' {
        $fakeRoot = Join-Path $TestDrive 'plugins'
        foreach ($capability in (Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json).capabilities) {
            $skillDir = Join-Path $fakeRoot (Join-Path $capability.plugin (Join-Path 'skills' $capability.skill))
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value '# stub'
        }

        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase D -PluginSearchRoot $fakeRoot -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Found | Should -Contain 'aveva-rnd:code-review'
        $result.Details.Found | Should -Contain 'aveva-core:create-audit'
        @($result.Details.MissingRequired).Count | Should -Be 0
    }

    It 'blocks when the required-capabilities manifest is missing' {
        $output = & $script:ScriptPath -RequiredCapabilitiesPath (Join-Path $TestDrive 'no-manifest.json') -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-CAPABILITIES-MISSING*'
    }

    It 'blocks from Phase C when the repository root is not a git work tree' {
        $output = & $script:ScriptPath -RepositoryRoot $TestDrive -Phase C -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors -join "`n" | Should -BeLike '*EIWF-GIT-NO-REPO*'
    }
}
