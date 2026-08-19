#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Validate-EiWorkflowState' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $skillScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $script:ScriptPath = Join-Path $skillScripts 'Validate-EiWorkflowState.ps1'
        $script:InitPath = Join-Path $skillScripts 'Initialize-EiWorkflowState.ps1'
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
        $script:StatePath = Join-Path $script:StateDir 'workflow-state.json'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports a freshly initialised run as valid and resumable' {
        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Resumable | Should -BeTrue
        $result.Details.NextStage | Should -Be 'preflight'
    }

    It 'blocks when no state file exists' {
        $output = & $script:ScriptPath -StateDir (Join-Path $TestDrive 'missing') -Json
        $LASTEXITCODE | Should -Be 1

        $result = $output | ConvertFrom-Json
        $result.Errors[0] | Should -BeLike 'EIWF-STATE-MISSING*'
        $result.Details.Resumable | Should -BeFalse
    }

    It 'blocks when neither -StateDir nor -StatePath is supplied' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-INPUT*'
    }

    It 'blocks when the state file is not valid JSON' {
        Set-Content -LiteralPath $script:StatePath -Value '{ not json'

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-CORRUPT*'
    }

    It 'blocks when the state file violates the schema' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.status = 'nearly-done'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-SCHEMA*'
    }

    It 'blocks when lifecycle order was bypassed' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.stages[2].status = 'complete'
        $state.stages[2].gateResult = 'pass'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STAGE-ORDER*'
    }

    It 'blocks when a stage is complete without a passing gate' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.stages[0].status = 'complete'
        $state.stage = $state.stages[1].id
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-GATE-UNVERIFIED*'
    }

    It 'blocks when correction attempts exceed the ceiling' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.correctionAttempts = 4
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-RETRY-EXCEEDED*'
    }

    It 'blocks when the workflow is blocked without a recorded reason' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.status = 'blocked'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-BLOCK-UNEXPLAINED*'
    }

    It 'blocks when the current stage is not part of the lifecycle' {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        $state.stage = 'invented-stage'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath

        $output = & $script:ScriptPath -StateDir $script:StateDir -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STAGE-UNKNOWN*'
    }
}
