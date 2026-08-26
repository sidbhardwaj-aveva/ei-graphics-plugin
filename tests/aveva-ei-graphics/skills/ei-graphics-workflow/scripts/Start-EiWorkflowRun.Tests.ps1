#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Start-EiWorkflowRun' -Tag 'Unit' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
        $script:ScriptPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'Start-EiWorkflowRun.ps1'

        function script:Get-BootstrapState {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        }

        function script:Get-BootstrapStage {
            param([psobject]$State, [string]$StageId)
            @($State.stages) | Where-Object { $_.id -eq $StageId } | Select-Object -First 1
        }
    }

    Context 'IMPLEMENT bootstrap' {
        BeforeEach {
            $script:Workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:Workspace -Force | Out-Null
        }

        It 'initialises state and records preflight and state-init in a single call' {
            $output = & $script:ScriptPath -StoryId '4983245' -StoryRef 'https://dev.azure.com/x/_workitems/edit/4983245' `
                -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json
            $LASTEXITCODE | Should -Be 0

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Valid'
            $result.Details.Resumed | Should -BeFalse
            $result.Details.StagesCompleted | Should -Be @('preflight', 'state-init')
            $result.Details.NextStage | Should -Be 'ado-intake'
            $result.Details.SessionId | Should -Not -BeNullOrEmpty

            $state = Get-BootstrapState -StateDir $result.Details.StateDir
            (Get-BootstrapStage -State $state -StageId 'preflight').status | Should -Be 'complete'
            (Get-BootstrapStage -State $state -StageId 'preflight').gateResult | Should -Be 'pass'
            (Get-BootstrapStage -State $state -StageId 'state-init').status | Should -Be 'complete'
            $state.storyRef | Should -Be 'https://dev.azure.com/x/_workitems/edit/4983245'
        }

        It 'writes an in-progress session start marker under the supplied session id' {
            $logDir = Join-Path $script:Workspace 'session-logs'

            $result = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace `
                -SessionId '11111111-2222-3333-4444-555555555555' -EntryPoint 'ado-id' `
                -LogDir $logDir -NoDefaultSearchRoots -Json | ConvertFrom-Json

            $result.Status | Should -Be 'Valid'
            $logFile = Join-Path $logDir '11111111-2222-3333-4444-555555555555.json'
            Test-Path -LiteralPath $logFile | Should -BeTrue
            (Get-Content -LiteralPath $logFile -Raw | ConvertFrom-Json).finalStatus | Should -Be 'in-progress'
        }

        It 'is safe to re-run and does not re-transition completed stages' {
            $first = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json
            $firstStartedAt = (Get-BootstrapStage -State (Get-BootstrapState -StateDir $first.Details.StateDir) -StageId 'preflight').startedAt

            $second = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0

            $second.Status | Should -Be 'Valid'
            $second.Details.Resumed | Should -BeTrue
            $second.Details.NextStage | Should -Be 'ado-intake'
            (Get-BootstrapStage -State (Get-BootstrapState -StateDir $second.Details.StateDir) -StageId 'preflight').startedAt |
                Should -Be $firstStartedAt
        }

        It 'surfaces later-phase capability gaps as warnings rather than errors' {
            $result = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json

            $result.Status | Should -Be 'Valid'
            @($result.Details.Prerequisites.MissingLaterPhase).Count | Should -BeGreaterThan 0
            ($result.Warnings -join "`n") | Should -BeLike '*needed from Phase D*'
        }
    }

    Context 'fail-closed behaviour' {
        BeforeEach {
            $script:Workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:Workspace -Force | Out-Null
        }

        It 'blocks the preflight stage and returns Invalid when a required capability is missing' {
            $output = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace `
                -Phase D -NoDefaultSearchRoots -Json
            $LASTEXITCODE | Should -Be 1

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Invalid'
            ($result.Errors -join "`n") | Should -BeLike '*EIWF-BOOTSTRAP-PREFLIGHT*'

            $state = Get-BootstrapState -StateDir $result.Details.StateDir
            $state.status | Should -Be 'blocked'
            (Get-BootstrapStage -State $state -StageId 'preflight').status | Should -Be 'blocked'
            @($state.blocks)[-1].code | Should -Be 'EIWF-PREREQUISITES'
            @($state.blocks)[-1].remediation | Should -Not -BeNullOrEmpty
        }

        It 'does not advance past state initialisation when the story id is rejected' {
            $output = & $script:ScriptPath -StoryId '../escape' -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json
            $LASTEXITCODE | Should -Be 1

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Invalid'
            ($result.Errors -join "`n") | Should -BeLike '*EIWF-BOOTSTRAP-STATE*'
            ($result.Errors -join "`n") | Should -BeLike '*EIWF-STORY-ID*'
        }
    }

    Context 'preflight gate evidence' {
        BeforeEach {
            $script:Workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:Workspace -Force | Out-Null
        }

        It 'persists the passing gate verdict as the prerequisites artifact' {
            $result = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json
            $result.Status | Should -Be 'Valid'

            $evidencePath = Join-Path $result.Details.StateDir 'prerequisites.json'
            Test-Path -LiteralPath $evidencePath | Should -BeTrue

            $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
            $evidence.gate | Should -Be 'prerequisites'
            $evidence.stage | Should -Be 'preflight'
            $evidence.verdict | Should -Be 'pass'
            $evidence.storyId | Should -Be '4983245'
            $evidence.workflowPath | Should -Be 'IMPLEMENT'
            $evidence.phase | Should -Be 'A'
            @($evidence.found).Count | Should -BeGreaterThan 0
            @($evidence.errors).Count | Should -Be 0
        }

        It 'records a block verdict in the evidence when the gate fails' {
            $result = & $script:ScriptPath -StoryId '4983245' -WorkspaceRoot $script:Workspace `
                -Phase D -NoDefaultSearchRoots -Json | ConvertFrom-Json
            $result.Status | Should -Be 'Invalid'

            $evidence = Get-Content -LiteralPath (Join-Path $result.Details.StateDir 'prerequisites.json') -Raw | ConvertFrom-Json
            $evidence.verdict | Should -Be 'block'
            $evidence.phase | Should -Be 'D'
            @($evidence.missingRequired).Count | Should -BeGreaterThan 0
        }

        It 'refuses a hand-completed preflight when no evidence was written' {
            $stateScripts = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
            $init = & (Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1') -StoryId '4983245' `
                -WorkflowPath IMPLEMENT -WorkspaceRoot $script:Workspace -Json | ConvertFrom-Json
            $stagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'

            (& $stagePath -StateDir $init.Details.StateDir -StageId 'preflight' -Action start -Json | ConvertFrom-Json).Status |
                Should -Be 'Valid'

            $completed = & $stagePath -StateDir $init.Details.StateDir -StageId 'preflight' `
                -Action complete -GateResult pass -Json | ConvertFrom-Json

            $completed.Status | Should -Be 'Invalid'
            ($completed.Errors -join "`n") | Should -BeLike '*EIWF-ARTIFACT-MISSING*'
            ($completed.Errors -join "`n") | Should -BeLike '*prerequisites*'
        }
    }

    Context 'resolving the pasted work item reference' {
        BeforeEach {
            $script:Workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:Workspace -Force | Out-Null
            $script:PastedLink = '[Bug 4983245 SR350 - EPT Termination Drawing Missing Headers and Terminals in Old Workflow](https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245)'
            $script:PastedUrl = 'https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245'
        }

        It 'derives the story id from a pasted markdown link supplied as the story ref' {
            $result = & $script:ScriptPath -StoryId '' -StoryRef $script:PastedLink `
                -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Status | Should -Be 'Valid'
            $result.Details.StoryId | Should -Be '4983245'

            $state = Get-BootstrapState -StateDir $result.Details.StateDir
            $state.storyId | Should -Be '4983245'
            $state.storyRef | Should -Be $script:PastedUrl
        }

        It 'derives the story id when the pasted link arrives as the story id' {
            $result = & $script:ScriptPath -StoryId $script:PastedLink `
                -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StoryId | Should -Be '4983245'
            $result.Details.StoryRef | Should -Be $script:PastedUrl
        }

        It 'leaves a story id that is already usable alone' {
            $result = & $script:ScriptPath -StoryId 'manual-story' `
                -WorkspaceRoot $script:Workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StoryId | Should -Be 'manual-story'
        }
    }

    Context 'ITERATE bootstrap' {
        It 'records preflight only and leaves state-recovery to its owner' {
            $workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null

            $result = & $script:ScriptPath -StoryId '4983245' -WorkflowPath ITERATE `
                -WorkspaceRoot $workspace -NoDefaultSearchRoots -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0

            $result.Status | Should -Be 'Valid'
            $result.Details.StagesCompleted | Should -Be @('preflight')
            $result.Details.NextStage | Should -Be 'state-recovery'
            (Get-BootstrapStage -State (Get-BootstrapState -StateDir $result.Details.StateDir) -StageId 'state-recovery').status |
                Should -Be 'pending'
        }
    }
}
