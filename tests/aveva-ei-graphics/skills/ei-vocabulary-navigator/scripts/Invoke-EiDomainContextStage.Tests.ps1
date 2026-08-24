#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Domain-context lifecycle stage' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:IntakeStagePath = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextStagePath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts' 'Invoke-EiDomainContextStage.ps1'
        $script:WorkItemJson = Get-Content -LiteralPath (Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-123456.json') -Raw

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
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'

        foreach ($stageId in @('preflight', 'state-init')) {
            & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action start -Json | Out-Null
            & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action complete -GateResult pass -Json | Out-Null
        }

        & $script:IntakeStagePath -StateDir $script:StateDir `
            -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
            -CliWorkItemJson $script:WorkItemJson -Json | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'completing the stage' {
        It 'completes with an empty domainSkills array when no registry entry matches the story' {
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'

            $stage = script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context'
            $stage.status | Should -Be 'complete'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            $artifact.source | Should -Be 'ei-domain-skill-registry'
            @($artifact.domainSkills).Count | Should -Be 0
        }

        It 'detects and injects the termination-drawing domain for a matching story' {
            $workItemJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-789012.json') -Raw
            & $script:InitPath -StoryId '789012' -WorkspaceRoot $TestDrive -Json | Out-Null
            $stateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '789012'
            foreach ($stageId in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $stateDir -StageId $stageId -Action start -Json | Out-Null
                & $script:StagePath -StateDir $stateDir -StageId $stageId -Action complete -GateResult pass -Json | Out-Null
            }
            & $script:IntakeStagePath -StateDir $stateDir -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/789012' -CliWorkItemJson $workItemJson -Json | Out-Null

            $result = & $script:ContextStagePath -StateDir $stateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            @($result.Details.DetectedDomains) | Should -Contain 'termination-drawing'

            $artifact = Get-Content -LiteralPath (Join-Path $stateDir 'domain-context.json') -Raw | ConvertFrom-Json
            @($artifact.domainSkills | Where-Object { $_.domainId -eq 'termination-drawing' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'refusing to run without prerequisites' {
        It 'refuses to run before the ado artifact exists' {
            Remove-Item -LiteralPath (Join-Path $script:StateDir 'ado.json') -Force

            $result = & $script:ContextStagePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-ADO-UNREADABLE*'
            (script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context').status | Should -Be 'pending'
        }
    }
}
