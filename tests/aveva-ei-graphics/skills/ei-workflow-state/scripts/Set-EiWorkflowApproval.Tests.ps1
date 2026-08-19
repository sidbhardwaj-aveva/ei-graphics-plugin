#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Workflow approval checkpoint' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:ApprovalPath = Join-Path $stateScripts 'Set-EiWorkflowApproval.ps1'
        $script:StagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'

        function script:Get-EiState {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        }

        function script:Get-EiStateText {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw
        }
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'pausing a run for a decision' {
        It 'moves an in-progress run to awaiting-approval' {
            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.WorkflowStatus | Should -Be 'awaiting-approval'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'awaiting-approval'
        }

        It 'leaves stage bookkeeping to Set-EiWorkflowStage' {
            $before = (script:Get-EiState -StateDir $script:StateDir).stage

            & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | Out-Null

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.stage | Should -Be $before
            @($state.stages | Where-Object { $_.id -eq 'scope-approval' })[0].status | Should -Be 'pending'
        }

        It 'refuses to pause twice' {
            & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | Out-Null
            $before = script:Get-EiStateText -StateDir $script:StateDir

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-STATE*'
            script:Get-EiStateText -StateDir $script:StateDir | Should -Be $before
        }

        It 'refuses a stage that does not own the human-approval gate' {
            $before = script:Get-EiStateText -StateDir $script:StateDir

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'proposed-scope' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-STAGE*'
            script:Get-EiStateText -StateDir $script:StateDir | Should -Be $before
        }

        It 'refuses a stage the lifecycle does not declare' {
            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'not-a-stage' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-STAGE-UNKNOWN*'
        }

        It 'refuses a stage that has already been decided' {
            & $script:StagePath -StateDir $script:StateDir -StageId 'scope-approval' -Action block `
                -BlockCode 'EIWF-SCOPE-REJECTED' -BlockMessage 'Rejected earlier in the run.' -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-STAGE*'
        }
    }

    Context 'releasing a paused run' {
        It 'returns an awaiting-approval run to in-progress' {
            & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action grant -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.WorkflowStatus | Should -Be 'in-progress'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'in-progress'
        }

        It 'refuses to release a run that was never paused' {
            $before = script:Get-EiStateText -StateDir $script:StateDir

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action grant -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-STATE*'
            script:Get-EiStateText -StateDir $script:StateDir | Should -Be $before
        }
    }

    Context 'state it cannot trust' {
        It 'refuses to run against unusable state' {
            Set-Content -LiteralPath (Join-Path $script:StateDir 'workflow-state.json') -Value '{ "not": "state" }'

            $result = & $script:ApprovalPath -StateDir $script:StateDir -StageId 'scope-approval' -Action request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-STATE-UNUSABLE*'
        }
    }
}
