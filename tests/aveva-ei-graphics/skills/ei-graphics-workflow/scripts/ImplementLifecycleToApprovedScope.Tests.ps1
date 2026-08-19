#!/usr/bin/env pwsh
#Requires -Modules Pester

# One end-to-end proof that the IMPLEMENT lifecycle is reachable as far as a sealed approved scope.
# It runs against the real `lifecycle-implement.json` and the real artifact registry: nothing here
# supplies a test-shaped lifecycle, skips a stage, or writes state by hand. If a stage-ordering rule,
# a schema, or the human-approval gate is ever weakened, this test is what notices.
#
# It carries the `Unit` tag as well as `Integration` because `tests/Invoke-PesterTests.ps1` filters on
# `Unit`, and an integration proof that the standard gate never runs would prove nothing. It earns the
# tag: it is hermetic, uses only checked-in fixtures and TestDrive, and makes no network call.
Describe 'IMPLEMENT lifecycle from ADO intake to approved scope' -Tag 'Unit', 'Integration' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:ValidatePath = Join-Path $stateScripts 'Validate-EiWorkflowState.ps1'
        $script:PrereqPath = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Validate-EiWorkflowPrerequisites.ps1'
        $script:IntakeStagePath = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextStagePath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts' 'Invoke-EiDomainContextStage.ps1'
        $script:ResolverPath = Join-Path $pluginSkills 'ei-scope-resolver' 'scripts' 'New-EiProposedScope.ps1'
        $script:AnalysisPath = Join-Path $pluginSkills 'ei-scope-validator' 'scripts' 'Invoke-EiScopeAnalysis.ps1'
        $script:ApprovalPath = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Resolve-EiScopeApproval.ps1'

        $script:RepoRoot = $repoRoot
        $script:WorkItemJson = Get-Content -LiteralPath (Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-123456.json') -Raw
        $script:CandidatePath = Join-Path $PSScriptRoot '..' 'fixtures' 'candidate-scope-123456.json'
    }

    It 'carries a story from ADO intake through to a sealed approved scope' {
        $workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path (Join-Path $workspace 'src' 'Ei.Graphics.Rendering') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $workspace 'src' 'Ei.Graphics.Rendering' 'LabelPlacement.cs') -Value '// label placement'

        & $script:InitPath -StoryId '123456' -WorkspaceRoot $workspace -Json | Out-Null
        $LASTEXITCODE | Should -Be 0
        $stateDir = Join-Path $workspace '.copilottracking' 'ei-graphics' '123456'

        # preflight -- the gate is the real prerequisite check, not an assertion.
        $prereq = & $script:PrereqPath -RepositoryRoot $script:RepoRoot -Phase C -Json | ConvertFrom-Json
        $prereq.Status | Should -Be 'Valid'
        & $script:StagePath -StateDir $stateDir -StageId 'preflight' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # state-init
        & $script:StagePath -StateDir $stateDir -StageId 'state-init' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'state-init' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # ado-intake
        $intake = & $script:IntakeStagePath -StateDir $stateDir `
            -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
            -CliWorkItemJson $script:WorkItemJson `
            -Summary 'Stop termination labels overlapping when they share a cable point.' -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $intake.Details.GateResult | Should -Be 'pass'

        # domain-context
        $context = & $script:ContextStagePath -StateDir $stateDir -Terms @('cable', 'terminal arrangement', 'canvas drawing') -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $context.Details.GateResult | Should -Be 'pass'

        # proposed-scope -- fed by the two artifacts the Phase C stages just sealed, so the wiring
        # between intake, domain context and scope resolution is exercised rather than simulated.
        $scope = & $script:ResolverPath -StoryInputPath (Join-Path $stateDir 'ado.json') `
            -CandidatePath $script:CandidatePath `
            -DomainContextPath (Join-Path $stateDir 'domain-context.json') `
            -RepositoryRoot $workspace -StateDir $stateDir -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $scope.Details.ScopeStatus | Should -Be 'resolved'
        @($scope.Details.Payload.domainContext.terms) | Should -Contain 'cable'
        $scope.Details.Payload.storyRef | Should -Be 'https://dev.azure.com/example/MyProject/_workitems/edit/123456'
        & $script:StagePath -StateDir $stateDir -StageId 'proposed-scope' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'proposed-scope' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # scope-analysis
        $analysis = & $script:AnalysisPath -StateDir $stateDir -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $analysis.Details.Verdict | Should -Be 'pass'
        & $script:StagePath -StateDir $stateDir -StageId 'scope-analysis' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'scope-analysis' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # scope-approval -- the run pauses for a human, then seals what the human saw.
        $requested = & $script:ApprovalPath -StateDir $stateDir -Decision request -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $requested.Details.WorkflowStatus | Should -Be 'awaiting-approval'

        $approved = & $script:ApprovalPath -StateDir $stateDir -Decision approve `
            -DecidedBy 'approver@aveva.com' -Note 'Narrow and provable.' -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $approved.Details.GateResult | Should -Be 'pass'

        $seal = Get-Content -LiteralPath (Join-Path $stateDir 'approved-scope.v1.json') -Raw | ConvertFrom-Json
        $seal.approvedBy | Should -Be 'approver@aveva.com'
        $seal.storyRef | Should -Be 'https://dev.azure.com/example/MyProject/_workitems/edit/123456'
        @($seal.scope.proposedFiles | ForEach-Object { $_.path }) | Should -Contain 'src/Ei.Graphics.Rendering/LabelPlacement.cs'
        @($seal.scope.domainContext.terms) | Should -Contain 'terminal arrangement'

        # Every stage up to and including approval is complete, on the real lifecycle, with no skips.
        $final = & $script:ValidatePath -StateDir $stateDir -Json | ConvertFrom-Json
        $final.Status | Should -Be 'Valid'
        $final.Details.WorkflowStatus | Should -Be 'in-progress'
        $final.Details.ApprovedScopeHash | Should -Not -BeNullOrEmpty

        $state = Get-Content -LiteralPath (Join-Path $stateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        $walked = @('ado-intake', 'domain-context', 'proposed-scope', 'scope-analysis', 'scope-approval')
        foreach ($stageId in $walked) {
            $stage = @($state.stages) | Where-Object { $_.id -eq $stageId } | Select-Object -First 1
            $stage.status | Should -Be 'complete' -Because "stage '$stageId' must have completed on the real lifecycle"
            $stage.gateResult | Should -Be 'pass' -Because "stage '$stageId' must have passed its gate"
        }
        @($state.blocks).Count | Should -Be 0
    }
}
