#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'ADO intake lifecycle stage' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        . (Join-Path $PSScriptRoot '..' '..' '..' 'helpers' 'EiTestPreflight.ps1')

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:IntakeStagePath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:WorkItemJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'fixtures' 'work-item-123456.json') -Raw
        $script:WorkItemUrl = 'https://dev.azure.com/example/MyProject/_workitems/edit/123456'

        function script:Get-EiState {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        }

        function script:Get-EiStage {
            param([string]$StateDir, [string]$StageId)
            @((script:Get-EiState -StateDir $StateDir).stages) | Where-Object { $_.id -eq $StageId } | Select-Object -First 1
        }
    }

    BeforeEach {
        # The real IMPLEMENT lifecycle is used deliberately: the point of this stage is that it is
        # reachable in a real run, not only under a test-shaped lifecycle.
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'

        # `ado-intake` sits behind preflight and state-init, and stage ordering is enforced, so the
        # harness advances those the same way the workflow would.
        function script:Complete-EiStagesBeforeIntake {
            script:New-EiTestPreflightEvidence -StateDir $script:StateDir -StoryId '123456'
            foreach ($stageId in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action start -Json | Out-Null
                & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action complete -GateResult pass -Json | Out-Null
            }
        }
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'sealing a retrieved story' {
        BeforeEach { script:Complete-EiStagesBeforeIntake }

        It 'writes the ado artifact and completes the stage with a passing gate' {
            $result = & $script:IntakeStagePath -StateDir $script:StateDir -WorkItemUrl $script:WorkItemUrl `
                -CliWorkItemJson $script:WorkItemJson -Summary 'Stop termination labels overlapping.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'

            $stage = script:Get-EiStage -StateDir $script:StateDir -StageId 'ado-intake'
            $stage.status | Should -Be 'complete'
            $stage.gateResult | Should -Be 'pass'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'ado.json') -Raw | ConvertFrom-Json
            $artifact.source | Should -Be 'ei-azure-devops-cli-intake'
            $artifact.workItem.organization | Should -Be 'AVEVA-VSTS'
            $artifact.workItem.project | Should -Be 'Dabacon Products'
            $artifact.retrieval.status | Should -Be 'retrieved'
            $artifact.description | Should -BeLike '*terminal arrangement labels share a point*'
        }

        It 'takes the story id from workflow state rather than the caller' {
            $result = & $script:IntakeStagePath -StateDir $script:StateDir -WorkItemUrl $script:WorkItemUrl `
                -CliWorkItemJson $script:WorkItemJson -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StoryId | Should -Be '123456'
            $result.Details.Payload.storyId | Should -Be (script:Get-EiState -StateDir $script:StateDir).storyId
        }

        It 'blocks the run instead of sealing a story it could not retrieve' {
            $result = & $script:IntakeStagePath -StateDir $script:StateDir -WorkItemUrl 'https://example.com/not-an-ado-url' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIAI-INTAKE-FAILED*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'ado.json') | Should -BeFalse

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.status | Should -Be 'blocked'
            @($state.blocks)[-1].code | Should -Be 'EIAI-INTAKE-FAILED'
        }
    }

    Context 'stage ordering' {
        It 'refuses to run before the stages ahead of it are complete' {
            $result = & $script:IntakeStagePath -StateDir $script:StateDir -WorkItemUrl $script:WorkItemUrl `
                -CliWorkItemJson $script:WorkItemJson -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIAI-STAGE-NOT-STARTED*'
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-STAGE-ORDER*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'ado.json') | Should -BeFalse
        }
    }

    Context 'resolving the work item reference' {
        # The documented call in ei-graphics-workflow passes only -StateDir, so the stage has to find
        # the reference itself instead of blocking on `missing-work-item-url-or-id`.
        It 'falls back to the storyRef recorded in workflow state' {
            & $script:InitPath -StoryId '123456' -StoryRef $script:WorkItemUrl -WorkspaceRoot $TestDrive -Force -Json | Out-Null
            script:Complete-EiStagesBeforeIntake

            $result = & $script:IntakeStagePath -StateDir $script:StateDir -CliWorkItemJson $script:WorkItemJson -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ReferenceSource | Should -Be 'workflow-state.storyRef'
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.Payload.workItem.id | Should -Be '123456'
            $result.Details.Payload.workItem.organization | Should -Be 'AVEVA-VSTS'
        }

        It 'falls back to the storyId when workflow state carries no storyRef' {
            script:Complete-EiStagesBeforeIntake

            $result = & $script:IntakeStagePath -StateDir $script:StateDir -Organization 'example' -Project 'MyProject' `
                -CliWorkItemJson $script:WorkItemJson -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ReferenceSource | Should -Be 'workflow-state.storyId'
            $result.Details.Payload.workItem.id | Should -Be '123456'
            $result.Details.Payload.workItem.organization | Should -Be 'example'
        }

        It 'prefers an explicit reference over the one held in state' {
            & $script:InitPath -StoryId '123456' -StoryRef 'https://dev.azure.com/other/OtherProject/_workitems/edit/123456' `
                -WorkspaceRoot $TestDrive -Force -Json | Out-Null
            script:Complete-EiStagesBeforeIntake

            $result = & $script:IntakeStagePath -StateDir $script:StateDir -WorkItemUrl $script:WorkItemUrl `
                -CliWorkItemJson $script:WorkItemJson -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ReferenceSource | Should -Be 'parameter'
            $result.Details.Payload.workItem.url | Should -Be $script:WorkItemUrl
        }
    }
}
