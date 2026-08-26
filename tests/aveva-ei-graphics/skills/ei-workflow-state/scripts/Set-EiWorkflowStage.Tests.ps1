#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Set-EiWorkflowStage' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $skillScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $script:ScriptPath = Join-Path $skillScripts 'Set-EiWorkflowStage.ps1'
        $script:InitPath = Join-Path $skillScripts 'Initialize-EiWorkflowState.ps1'
        $script:ValidatePath = Join-Path $skillScripts 'Validate-EiWorkflowState.ps1'
        $script:WritePath = Join-Path $skillScripts 'Write-EiWorkflowArtifact.ps1'

        $script:ValidResult = @{
            schemaVersion = '1.0.0'
            workflow      = 'ei-graphics-workflow'
            path          = 'IMPLEMENT'
            storyId       = '654321'
            status        = 'blocked'
            stage         = 'second'
            stateDir      = '.copilottracking/ei-graphics/654321'
            summary       = 'Artifact fixture for the transition tests.'
            artifacts     = @()
            gates         = @()
            blocks        = @()
            nextAction    = 'None.'
        } | ConvertTo-Json -Depth 10

        # A minimal three-stage lifecycle lets the artifact rules be exercised without touching the real lifecycle files.
        # `third` carries a Phase D artifact so the reserved-artifact rule can be proved against an artifact that is
        # genuinely still unimplemented, rather than one that later phases will activate.
        $script:TestLifecycle = @{
            schemaVersion = '1.0.0'
            path          = 'IMPLEMENT'
            description   = 'Test-only lifecycle for stage transition coverage.'
            stages        = @(
                @{ id = 'first'; name = 'First'; owner = 'test'; artifact = $null; writesFiles = $false; gate = $null; implementedInPhase = 'A' },
                @{ id = 'second'; name = 'Second'; owner = 'test'; artifact = 'workflow-result'; writesFiles = $false; gate = 'artifact-present'; implementedInPhase = 'A' },
                @{ id = 'third'; name = 'Third'; owner = 'test'; artifact = 'specification'; writesFiles = $false; gate = 'artifact-present'; implementedInPhase = 'D' }
            )
        } | ConvertTo-Json -Depth 10
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
        $script:StatePath = Join-Path $script:StateDir 'workflow-state.json'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'valid transitions' {
        It 'starts a pending stage and records it as the current stage' {
            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json
            $LASTEXITCODE | Should -Be 0

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Valid'
            $result.Details.StageStatus | Should -Be 'running'
            $result.Details.CurrentStage | Should -Be 'preflight'

            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            $state.stages[0].status | Should -Be 'running'
            $state.stages[0].startedAt | Should -Not -BeNullOrEmpty
        }

        It 'completes a running stage with a passing gate and advances to the next stage' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 0

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Valid'
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'
            $result.Details.CurrentStage | Should -Be 'state-init'

            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            $state.stages[0].gateResult | Should -Be 'pass'
            $state.stages[0].completedAt | Should -Not -BeNullOrEmpty
            $state.stage | Should -Be 'state-init'
        }

        It 'completes a stage whose required artifact is present and schema-valid' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'state-init' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'state-init' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).Details.Artifact | Should -Be 'workflow-state'
        }

        It 'treats starting an already running stage as re-entry and keeps the original startedAt' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null
            $startedAt = (Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json).stages[0].startedAt

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json
            $LASTEXITCODE | Should -Be 0

            $result = $output | ConvertFrom-Json
            $result.Status | Should -Be 'Valid'
            $result.Details.Resumed | Should -BeTrue
            $result.Details.StageStatus | Should -Be 'running'
            $result.Warnings.Count | Should -Be 1

            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            $state.stages[0].startedAt | Should -Be $startedAt
            $state.stage | Should -Be 'preflight'
        }

        It 'leaves the state usable for the Phase A validator after a transition' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null

            $output = & $script:ValidatePath -StateDir $script:StateDir -Json
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).Details.NextStage | Should -Be 'state-init'
        }
    }

    Context 'invalid transitions' {
        It 'rejects completing a stage that was never started' {
            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-TRANSITION-INVALID*'
        }

        It 'rejects starting a stage while an earlier stage is incomplete' {
            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'ado-intake' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STAGE-ORDER*'
        }

        It 'rejects an unknown stage id' {
            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'invented-stage' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STAGE-UNKNOWN*'
        }

        It 'rejects a transition when no state exists' {
            $output = & $script:ScriptPath -StateDir (Join-Path $TestDrive 'missing') -StageId 'preflight' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-UNUSABLE*'
        }

        It 'rejects restarting or re-completing an already complete stage' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null

            $restart = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($restart | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-TRANSITION-INVALID*'

            $recomplete = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 1
            ($recomplete | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-TRANSITION-INVALID*'
        }
    }

    Context 'gate rules' {
        It 'rejects completing a gated stage without a gate result' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-GATE-REQUIRED*'
        }

        It 'rejects completing a stage whose gate blocked' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult block -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-GATE-INVALID*'

            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            $state.stages[0].status | Should -Be 'running'
            $state.stages[0].gateResult | Should -Be 'not-run'
        }
    }

    Context 'artifact rules' {
        BeforeEach {
            $script:LifecyclePath = Join-Path $TestDrive 'lifecycle-test.json'
            Set-Content -LiteralPath $script:LifecyclePath -Value $script:TestLifecycle -Encoding utf8

            & $script:InitPath -StoryId '654321' -WorkspaceRoot $TestDrive -LifecycleDefinitionPath $script:LifecyclePath -Json | Out-Null
            $script:ArtifactStateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '654321'

            & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'first' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'first' -Action complete -Json | Out-Null
            & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'second' -Action start -Json | Out-Null
        }

        It 'rejects completing a stage whose required artifact is missing' {
            $output = & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'second' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-MISSING*'
        }

        It 'completes the same stage once the artifact has been written' {
            & $script:WritePath -StateDir $script:ArtifactStateDir -Name 'workflow-result' -Content $script:ValidResult -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'second' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).Details.StageStatus | Should -Be 'complete'
        }

        It 'rejects completing a stage whose artifact is reserved for a later phase' {
            & $script:WritePath -StateDir $script:ArtifactStateDir -Name 'workflow-result' -Content $script:ValidResult -Json | Out-Null
            & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'second' -Action complete -GateResult pass -Json | Out-Null
            & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'third' -Action start -Json | Out-Null

            # Written directly because the artifact writer refuses reserved artifacts; presence must still not satisfy the stage.
            Set-Content -LiteralPath (Join-Path $script:ArtifactStateDir 'specification.json') -Value '{"id":1}' -Encoding utf8

            $output = & $script:ScriptPath -StateDir $script:ArtifactStateDir -StageId 'third' -Action complete -GateResult pass -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-SCHEMA-PENDING*'
        }
    }

    Context 'blocking' {
        It 'blocks a running stage and records the block on the workflow' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action block `
                -BlockCode 'EIWF-DEPENDENCY-MISSING' -BlockMessage 'aveva-rnd is not installed.' `
                -Remediation 'Install it from the marketplace and retry.' -Json
            $LASTEXITCODE | Should -Be 0

            $result = $output | ConvertFrom-Json
            $result.Details.WorkflowStatus | Should -Be 'blocked'
            $result.Details.BlockCount | Should -Be 1

            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            $state.stages[0].status | Should -Be 'blocked'
            $state.stages[0].gateResult | Should -Be 'block'
            $state.blocks[0].code | Should -Be 'EIWF-DEPENDENCY-MISSING'
            $state.blocks[0].remediation | Should -Be 'Install it from the marketplace and retry.'
        }

        It 'rejects a block without a code and message' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null

            $output = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action block -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-BLOCK-INPUT*'
        }

        It 'rejects advancing any stage while the workflow is blocked' {
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action block -BlockCode 'EIWF-TEST' -BlockMessage 'Blocked for test.' -Json | Out-Null

            $restart = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($restart | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-TRANSITION-INVALID*'

            $next = & $script:ScriptPath -StateDir $script:StateDir -StageId 'state-init' -Action start -Json
            $LASTEXITCODE | Should -Be 1
            ($next | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-TRANSITION-INVALID*'
        }
    }

    Context 'contract' {
        It 'never mutates state when validation fails' {
            $before = Get-Content -LiteralPath $script:StatePath -Raw

            & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'invented-stage' -Action start -Json | Out-Null
            & $script:ScriptPath -StateDir $script:StateDir -StageId 'ado-intake' -Action start -Json | Out-Null

            Get-Content -LiteralPath $script:StatePath -Raw | Should -Be $before
        }

        It 'returns the shared result contract in JSON' {
            $result = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start -Json | ConvertFrom-Json

            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            $result.PSObject.Properties.Name | Should -Contain 'Details'
            $result.Details.Action | Should -Be 'start'
            $result.Details.StageId | Should -Be 'preflight'
        }

        It 'returns an object rather than JSON when -Json is not supplied' {
            $result = & $script:ScriptPath -StateDir $script:StateDir -StageId 'preflight' -Action start
            $LASTEXITCODE | Should -Be 0
            $result.Status | Should -Be 'Valid'
        }
    }
}
