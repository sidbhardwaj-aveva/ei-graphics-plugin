#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Initialize-EiWorkflowState' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts' 'Initialize-EiWorkflowState.ps1'
    }

    It 'creates a story-scoped state directory and a schema-valid state file' {
        $output = & $script:ScriptPath -StoryId '123456' -WorkflowPath IMPLEMENT -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Resumed | Should -BeFalse
        $result.Details.Stage | Should -Be 'preflight'

        $statePath = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456' 'workflow-state.json'
        Test-Path -LiteralPath $statePath | Should -BeTrue

        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.storyId | Should -Be '123456'
        $state.path | Should -Be 'IMPLEMENT'
        $state.status | Should -Be 'in-progress'
        $state.maxCorrectionAttempts | Should -Be 3
        @($state.stages).Count | Should -BeGreaterThan 0
        @($state.stages | Where-Object { $_.status -ne 'pending' }).Count | Should -Be 0
    }

    It 'creates the validation evidence directory' {
        & $script:ScriptPath -StoryId '222' -WorkspaceRoot $TestDrive -Json | Out-Null
        Test-Path -LiteralPath (Join-Path $TestDrive '.copilottracking' 'ei-graphics' '222' 'validation') | Should -BeTrue
    }

    It 'resumes an existing run instead of overwriting it' {
        & $script:ScriptPath -StoryId '333' -WorkspaceRoot $TestDrive -Json | Out-Null
        $first = (Get-Content -LiteralPath (Join-Path $TestDrive '.copilottracking' 'ei-graphics' '333' 'workflow-state.json') -Raw | ConvertFrom-Json).workflowId

        $output = & $script:ScriptPath -StoryId '333' -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Details.Resumed | Should -BeTrue
        $result.Details.WorkflowId | Should -Be $first
    }

    It 'blocks a story id that is not a safe directory name' {
        $output = & $script:ScriptPath -StoryId '../escape' -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 1

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Invalid'
        $result.Errors[0] | Should -BeLike 'EIWF-STORY-ID*'
    }

    It 'blocks when the requested path differs from the active run' {
        & $script:ScriptPath -StoryId '444' -WorkflowPath IMPLEMENT -WorkspaceRoot $TestDrive -Json | Out-Null

        $output = & $script:ScriptPath -StoryId '444' -WorkflowPath ITERATE -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-PATH-MISMATCH*'
    }

    It 'blocks when existing state is corrupt and points at the -Force remediation' {
        & $script:ScriptPath -StoryId '555' -WorkspaceRoot $TestDrive -Json | Out-Null
        $statePath = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '555' 'workflow-state.json'
        Set-Content -LiteralPath $statePath -Value '{ not json'

        $output = & $script:ScriptPath -StoryId '555' -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 1

        $result = $output | ConvertFrom-Json
        $result.Errors[0] | Should -BeLike 'EIWF-STATE-CORRUPT*'
        $result.Details.Remediation | Should -BeLike '*-Force*'
    }

    It 'archives unusable state when -Force is supplied' {
        & $script:ScriptPath -StoryId '666' -WorkspaceRoot $TestDrive -Json | Out-Null
        $stateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '666'
        Set-Content -LiteralPath (Join-Path $stateDir 'workflow-state.json') -Value '{ not json'

        $output = & $script:ScriptPath -StoryId '666' -WorkspaceRoot $TestDrive -Force -Json
        $LASTEXITCODE | Should -Be 0
        ($output | ConvertFrom-Json).Details.Resumed | Should -BeFalse
        @(Get-ChildItem -LiteralPath $stateDir -Filter 'workflow-state.*.bak.json').Count | Should -Be 1
    }

    It 'blocks when the lifecycle definition is missing' {
        $output = & $script:ScriptPath -StoryId '777' -WorkspaceRoot $TestDrive -LifecycleDefinitionPath (Join-Path $TestDrive 'no-such-lifecycle.json') -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-LIFECYCLE-MISSING*'
    }

    It 'materialises the ITERATE lifecycle when that path is requested' {
        $output = & $script:ScriptPath -StoryId '888' -WorkflowPath ITERATE -WorkspaceRoot $TestDrive -Json
        $LASTEXITCODE | Should -Be 0
        ($output | ConvertFrom-Json).Details.WorkflowPath | Should -Be 'ITERATE'

        $state = Get-Content -LiteralPath (Join-Path $TestDrive '.copilottracking' 'ei-graphics' '888' 'workflow-state.json') -Raw | ConvertFrom-Json
        @($state.stages | Where-Object { $_.id -eq 'scope-recovery' }).Count | Should -Be 1
    }
}
