#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Human scope-approval orchestration' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $resolverScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts'
        $flowScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts'
        $validatorScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-validator' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:NewScopePath = Join-Path $resolverScripts 'New-EiProposedScope.ps1'
        $script:AnalysisPath = Join-Path $validatorScripts 'Invoke-EiScopeAnalysis.ps1'
        $script:ApprovalPath = Join-Path $flowScripts 'Resolve-EiScopeApproval.ps1'
        $script:SealPath = Join-Path $flowScripts 'New-EiApprovedScope.ps1'

        # The real IMPLEMENT lifecycle puts unimplemented Phase C stages ahead of the scope layer, and
        # `Set-EiWorkflowStage.ps1` refuses to start a stage out of order. This fixture keeps the Phase B
        # segment in its real order so the approval stage can be driven without bypassing that rule.
        $script:LifecyclePath = Join-Path $TestDrive 'lifecycle-phase-b.json'
        Set-Content -LiteralPath $script:LifecyclePath -Value (@{
                schemaVersion = '1.0.0'
                path          = 'IMPLEMENT'
                description   = 'Phase B segment of the IMPLEMENT lifecycle, used to exercise scope-approval stage transitions.'
                stages        = @(
                    @{ id = 'proposed-scope'; name = 'Conservative proposed scope resolution'; owner = 'ei-scope-resolver'; artifact = 'proposed-scope'; writesFiles = $false; gate = 'artifact-present'; implementedInPhase = 'B' },
                    @{ id = 'scope-analysis'; name = 'Deterministic proposed-scope analysis'; owner = 'ei-scope-validator'; artifact = 'validation'; writesFiles = $false; gate = 'scope-analysis'; implementedInPhase = 'B' },
                    @{ id = 'scope-approval'; name = 'Human scope approval and scope sealing'; owner = 'human'; artifact = 'approved-scope'; writesFiles = $false; gate = 'human-approval'; implementedInPhase = 'B' }
                )
            } | ConvertTo-Json -Depth 10)

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
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src/Ei.Graphics.Rendering') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src/Ei.Graphics.Rendering/LabelPlacement.cs') -Value '// placement'

        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -LifecycleDefinitionPath $script:LifecyclePath -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'

        $script:StoryPath = Join-Path $TestDrive 'story.json'
        Set-Content -LiteralPath $script:StoryPath -Value (@{
                storyId  = '123456'
                storyRef = 'https://dev.azure.com/example/_workitems/edit/123456'
                summary  = 'Stop termination labels overlapping when they share a point.'
            } | ConvertTo-Json -Depth 10)

        $script:ContextPath = Join-Path $TestDrive 'domain-context.json'
        Set-Content -LiteralPath $script:ContextPath -Value (@{
                source      = 'ei-domain-skill-registry'
                domainSkills = @(
                    @{ domainId = 'termination-drawing'; displayName = 'Termination Drawing'; summary = ''; keyFiles = @(); keyFilesNote = 'Key files are candidate evidence.' }
                )
            } | ConvertTo-Json -Depth 10)

        $script:CandidatePath = Join-Path $TestDrive 'candidate.json'
        Set-Content -LiteralPath $script:CandidatePath -Value (@{
                confidence      = 0.85
                rationale       = 'The story changes only the label placement rule, which lives in one file.'
                evidence        = @(
                    @{ id = 'E1'; kind = 'story'; value = 'labels overlap'; note = $null },
                    @{ id = 'E2'; kind = 'path'; value = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; note = $null }
                )
                proposedFiles   = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @('Resolve'); evidence = @('E1', 'E2'); confidence = 0.86 }
                )
                proposedModules = @()
                relatedTests    = @(
                    @{ target = 'tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs'; kind = 'targeted'; evidence = @('E2') }
                )
                protectedAreas  = @()
                dependencies    = @()
                excluded        = @()
                risks           = @()
                unresolved      = @()
            } | ConvertTo-Json -Depth 20)

        function script:Invoke-EiResolve {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null
        }

        # The approval stage can only start once the stages ahead of it are complete, so the harness
        # advances them the same way the workflow would.
        function script:Complete-EiScopeStages {
            foreach ($stageId in @('proposed-scope', 'scope-analysis')) {
                & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action start -Json | Out-Null
                & $script:StagePath -StateDir $script:StateDir -StageId $stageId -Action complete -GateResult pass -Json | Out-Null
            }
        }
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'asking for a decision' {
        It 'refuses to ask before the scope has been analysed' {
            script:Invoke-EiResolve

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-NOT-READY*'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'in-progress'
        }

        It 'refuses to ask when analysis blocked the scope' {
            $candidate = Get-Content -LiteralPath $script:CandidatePath -Raw | ConvertFrom-Json
            $candidate.proposedFiles[0].symbols = @()
            Set-Content -LiteralPath $script:CandidatePath -Value ($candidate | ConvertTo-Json -Depth 20)

            script:Invoke-EiResolve
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-NOT-READY*'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'in-progress'
        }

        It 'pauses the run and reports what the approver is being shown' {
            script:Invoke-EiResolve
            $analysis = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json
            script:Complete-EiScopeStages

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.WorkflowStatus | Should -Be 'awaiting-approval'
            $result.Details.AnalysedHash | Should -Be $analysis.Details.ContentHash
            @($result.Details.PresentedPaths) | Should -Contain 'src/Ei.Graphics.Rendering/LabelPlacement.cs'
            (script:Get-EiStage -StateDir $script:StateDir -StageId 'scope-approval').status | Should -Be 'running'
        }
    }

    Context 'granting approval' {
        BeforeEach {
            script:Invoke-EiResolve
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null
            script:Complete-EiScopeStages
        }

        It 'refuses an approval with no approver identity' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVER-MISSING*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
        }

        It 'refuses an approval that was never asked for' {
            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve -DecidedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-NOT-REQUESTED*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
        }

        It 'seals the scope and releases the run' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve `
                -DecidedBy 'approver@aveva.com' -Note 'Narrow and provable.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ApprovedScopeVersion | Should -Be 1
            $result.Details.WorkflowStatus | Should -Be 'in-progress'

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.approvedScopeVersion | Should -Be 1
            $state.approvedScopeHash | Should -Be $result.Details.ContentHash

            $seal = Get-Content -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Raw | ConvertFrom-Json
            $seal.approvedBy | Should -Be 'approver@aveva.com'
            $seal.approvalNote | Should -Be 'Narrow and provable.'
        }

        It 'refuses to seal a scope that changed after it was analysed' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $scopePath = Join-Path $script:StateDir 'proposed-scope.json'
            $scope = Get-Content -LiteralPath $scopePath -Raw | ConvertFrom-Json
            $scope.rationale = 'Rewritten after the approver was asked.'
            Set-Content -LiteralPath $scopePath -Value ($scope | ConvertTo-Json -Depth 30)

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve -DecidedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-STALE*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'awaiting-approval'
        }
    }

    Context 'completing the approval stage' {
        BeforeEach {
            script:Invoke-EiResolve
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null
            script:Complete-EiScopeStages
        }

        It 'completes the stage with a passing human-approval gate once the scope is sealed' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve `
                -DecidedBy 'approver@aveva.com' -Note 'Narrow and provable.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'
            $result.Details.WorkflowStatus | Should -Be 'in-progress'

            $stage = script:Get-EiStage -StateDir $script:StateDir -StageId 'scope-approval'
            $stage.status | Should -Be 'complete'
            $stage.gateResult | Should -Be 'pass'
            $stage.completedAt | Should -Not -BeNullOrEmpty
        }

        It 'completes against the version it sealed rather than version 1' {
            # An earlier seal exists and is then made unreadable, so a completion that still assumed
            # version 1 would fail instead of validating the version this approval produced.
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'earlier@aveva.com' -Json | Out-Null
            Set-Content -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Value '{ "schemaVersion": "1.0.0" }'

            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve `
                -DecidedBy 'approver@aveva.com' -Note 'Re-approved after the change request.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ApprovedScopeVersion | Should -Be 2
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'

            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v2.json') | Should -BeTrue
            (script:Get-EiState -StateDir $script:StateDir).approvedScopeVersion | Should -Be 2
        }

        It 'leaves the stage open and the run paused when sealing fails' {
            # State records v1 while the artifact is gone, so the next seal recomputes v1 and is refused.
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'earlier@aveva.com' -Json | Out-Null
            Remove-Item -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Force

            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision approve `
                -DecidedBy 'approver@aveva.com' -Note 'Narrow and provable.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-SCOPE-SEAL-FAILED*'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'awaiting-approval'

            $stage = script:Get-EiStage -StateDir $script:StateDir -StageId 'scope-approval'
            $stage.status | Should -Be 'running'
            $stage.gateResult | Should -Be 'not-run'
            $stage.completedAt | Should -BeNullOrEmpty
        }
    }

    Context 'recording a rejection' {
        BeforeEach {
            script:Invoke-EiResolve
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null
            script:Complete-EiScopeStages
            & $script:ApprovalPath -StateDir $script:StateDir -Decision request -Json | Out-Null
        }

        It 'refuses a rejection with no decider or reason' {
            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision reject -DecidedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-INPUT*'
            (script:Get-EiState -StateDir $script:StateDir).status | Should -Be 'awaiting-approval'
        }

        It 'blocks the run and records who refused and why' {
            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision reject `
                -DecidedBy 'approver@aveva.com' -Note 'The print path is not covered by any test.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Details.Recorded | Should -BeTrue
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-SCOPE-REJECTED*'

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.status | Should -Be 'blocked'
            $block = @($state.blocks)[-1]
            $block.code | Should -Be 'EIWF-SCOPE-REJECTED'
            $block.message | Should -BeLike '*approver@aveva.com*print path*'
        }

        It 'does not seal anything when the scope is refused' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision reject `
                -DecidedBy 'approver@aveva.com' -Note 'Too broad.' -Json | Out-Null

            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
            (script:Get-EiState -StateDir $script:StateDir).approvedScopeVersion | Should -BeNullOrEmpty
        }

        It 'refuses to reject a run with no decision pending' {
            & $script:ApprovalPath -StateDir $script:StateDir -Decision reject `
                -DecidedBy 'approver@aveva.com' -Note 'Too broad.' -Json | Out-Null

            $result = & $script:ApprovalPath -StateDir $script:StateDir -Decision reject `
                -DecidedBy 'approver@aveva.com' -Note 'Still too broad.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-APPROVAL-NOT-REQUESTED*'
        }
    }
}
