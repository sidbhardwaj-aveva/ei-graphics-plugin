#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'New-EiWorkflowResult' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'New-EiWorkflowResult.ps1'
        $script:InitPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts' 'Initialize-EiWorkflowState.ps1'
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'builds and persists a schema-valid contract' {
        $output = & $script:ScriptPath -StateDir $script:StateDir -Status blocked -Summary 'Scope stages are not implemented yet.' -NextAction 'Wait for Phase B.' -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Result.workflow | Should -Be 'ei-graphics-workflow'
        $result.Details.Result.status | Should -Be 'blocked'
        $result.Details.Result.storyId | Should -Be '123456'
        $result.Details.Result.stateDir | Should -Be '.copilottracking/ei-graphics/123456'
        Test-Path -LiteralPath (Join-Path $script:StateDir 'workflow-result.json') | Should -BeTrue
    }

    It 'reports every lifecycle gate with its recorded result' {
        $output = & $script:ScriptPath -StateDir $script:StateDir -Status blocked -Summary 'x' -NextAction 'y' -Json
        $gates = ($output | ConvertFrom-Json).Details.Result.gates

        @($gates).Count | Should -BeGreaterThan 0
        @($gates | Where-Object { $_.result -ne 'not-run' }).Count | Should -Be 0
        @($gates | Where-Object { $_.stage -eq 'scope-approval' -and $_.id -eq 'human-approval' }).Count | Should -Be 1
    }

    It 'marks artifacts that do not exist yet as absent' {
        $output = & $script:ScriptPath -StateDir $script:StateDir -Status blocked -Summary 'x' -NextAction 'y' -Json
        $artifacts = ($output | ConvertFrom-Json).Details.Result.artifacts

        @($artifacts | Where-Object { $_.name -eq 'workflow-state' }).exists | Should -BeTrue
        @($artifacts | Where-Object { $_.name -eq 'pr' }).exists | Should -BeFalse
    }

    It 'refuses to return a contract while the run is still in-progress' {
        $output = & $script:ScriptPath -StateDir $script:StateDir -Summary 'x' -NextAction 'y' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-RESULT-STATUS*'
    }

    It 'refuses to build a contract from unusable state' {
        Set-Content -LiteralPath (Join-Path $script:StateDir 'workflow-state.json') -Value '{ not json'

        $output = & $script:ScriptPath -StateDir $script:StateDir -Status blocked -Summary 'x' -NextAction 'y' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-UNUSABLE*'
    }
}
