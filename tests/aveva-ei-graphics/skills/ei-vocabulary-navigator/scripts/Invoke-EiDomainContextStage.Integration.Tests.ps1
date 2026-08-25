#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Integration test: proves that an IMPLEMENT lifecycle run in which the domain-context stage
detects a domain skill (termination-drawing) and injects its Key Files successfully carries the
enriched domain-context artifact through proposed-scope, scope-analysis, and scope-approval to a
sealed approved-scope.

Invariants verified:
  - domainSkills is present in the domain-context artifact after the stage completes.
  - Key Files from the SKILL.md appear in domainSkills, not in domainPacks.
  - The scope-resolver receives the enriched artifact (domain-context.json contains domainSkills).
  - A sealed approved-scope.v1.json is produced: it contains the domain context terms.
  - All stages up to and including scope-approval are complete with gate pass on the real lifecycle.

This test makes no network calls and touches no shared state.
#>

Describe 'IMPLEMENT lifecycle with domain skill injection through to approved scope' -Tag 'Unit', 'Integration' {
    BeforeAll {
        $repoRoot     = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'

        $script:InitPath         = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath        = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:ValidatePath     = Join-Path $stateScripts 'Validate-EiWorkflowState.ps1'
        $script:PrereqPath       = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Validate-EiWorkflowPrerequisites.ps1'
        $script:IntakeStagePath  = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextStagePath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts' 'Invoke-EiDomainContextStage.ps1'
        $script:ResolverPath     = Join-Path $pluginSkills 'ei-scope-resolver' 'scripts' 'New-EiProposedScope.ps1'
        $script:AnalysisPath     = Join-Path $pluginSkills 'ei-scope-validator' 'scripts' 'Invoke-EiScopeAnalysis.ps1'
        $script:ApprovalPath     = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Resolve-EiScopeApproval.ps1'

        $script:RepoRoot       = $repoRoot
        $script:WorkItemJson   = Get-Content -LiteralPath (Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-789012.json') -Raw
        $script:CandidatePath  = Join-Path $PSScriptRoot '..' 'fixtures' 'candidate-scope-789012.json'
    }

    It 'carries a domain-skill-enriched story from ADO intake through to a sealed approved scope' {
        $workspace = Join-Path $TestDrive 'workspace'
        New-Item -ItemType Directory -Path (Join-Path $workspace 'src' 'Ei.CanvasDrawings') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $workspace 'src' 'Ei.CanvasDrawings' 'EquipmentInserter.cs') -Value '// equipment inserter'

        & $script:InitPath -StoryId '789012' -WorkspaceRoot $workspace -Json | Out-Null
        $LASTEXITCODE | Should -Be 0
        $stateDir = Join-Path $workspace '.copilottracking' 'ei-graphics' '789012'

        # preflight
        $prereq = & $script:PrereqPath -RepositoryRoot $script:RepoRoot -Phase C -Json | ConvertFrom-Json
        $prereq.Status | Should -Be 'Valid'
        & $script:StagePath -StateDir $stateDir -StageId 'preflight' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'preflight' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # state-init
        & $script:StagePath -StateDir $stateDir -StageId 'state-init' -Action start -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'state-init' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # ado-intake — uses the termination-drawing work item (789012) which has detection terms.
        $intake = & $script:IntakeStagePath -StateDir $stateDir `
            -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/789012' `
            -CliWorkItemJson $script:WorkItemJson `
            -Summary 'Fix TerminationDrawing update: use composite key instead of plain ID in insertedTags.' `
            -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $intake.Details.GateResult | Should -Be 'pass'

        # domain-context — agent selects termination-drawing and user confirms.
        $context = & $script:ContextStagePath -StateDir $stateDir `
            -SelectedDomainIds @('termination-drawing') -HumanConfirmed `
            -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $context.Details.GateResult | Should -Be 'pass'
        $context.Details.HumanConfirmed | Should -Be $true

        # Verify domain skill injection in the persisted artifact.
        $domainCtxArtifact = Get-Content -LiteralPath (Join-Path $stateDir 'domain-context.json') -Raw | ConvertFrom-Json

        $domainCtxArtifact.source | Should -Be 'ei-domain-skill-registry'

        # Domain skill was injected.
        $skills = @($domainCtxArtifact.domainSkills)
        $skills.Count | Should -BeGreaterOrEqual 1

        $td = $skills | Where-Object { $_.domainId -eq 'termination-drawing' } | Select-Object -First 1
        $td | Should -Not -BeNullOrEmpty
        $td.displayName | Should -Be 'Termination Drawing'

        $keyFiles = @($td.keyFiles)
        $keyFiles.Count | Should -BeGreaterOrEqual 1
        $td.keyFilesNote | Should -BeLike '*candidate evidence*'

        # Key Files are inside domainSkills only — not as top-level artifact keys.
        $topKeys = @($domainCtxArtifact.PSObject.Properties.Name)
        $topKeys | ForEach-Object { $_ | Should -Not -BeLike '*.cs' }

        # scope-candidate: write the known-good fixture and advance the stage before proposed-scope.
        Copy-Item -LiteralPath $script:CandidatePath -Destination (Join-Path $stateDir 'candidate.json') -Force
        & $script:StagePath -StateDir $stateDir -StageId 'scope-candidate' -Action start    -Json | Out-Null
        & $script:StagePath -StateDir $stateDir -StageId 'scope-candidate' -Action complete -GateResult pass -Json | Out-Null
        $LASTEXITCODE | Should -Be 0

        # proposed-scope — the domain-context.json (now enriched) is passed as context.
        $scope = & $script:ResolverPath `
            -StoryInputPath (Join-Path $stateDir 'ado.json') `
            -CandidatePath $script:CandidatePath `
            -DomainContextPath (Join-Path $stateDir 'domain-context.json') `
            -RepositoryRoot $workspace `
            -StateDir $stateDir `
            -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $scope.Details.ScopeStatus | Should -Be 'resolved'
        $scope.Details.Payload.domainContext.source | Should -Be 'ei-domain-skill-registry'
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

        # scope-approval — request, then seal.
        $requested = & $script:ApprovalPath -StateDir $stateDir -Decision request -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $requested.Details.WorkflowStatus | Should -Be 'awaiting-approval'

        $approved = & $script:ApprovalPath -StateDir $stateDir -Decision approve `
            -DecidedBy 'reviewer@aveva.com' `
            -Note 'Narrow scope: composite key fix in one inserter file.' `
            -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $approved.Details.GateResult | Should -Be 'pass'

        # Verify the sealed approved scope.
        $seal = Get-Content -LiteralPath (Join-Path $stateDir 'approved-scope.v1.json') -Raw | ConvertFrom-Json
        $seal.approvedBy | Should -Be 'reviewer@aveva.com'
        @($seal.scope.proposedFiles | ForEach-Object { $_.path }) | Should -Contain 'src/Ei.CanvasDrawings/EquipmentInserter.cs'
        @($seal.scope.domainContext.terms) | Should -Contain 'termination-drawing'

        # All stages from ado-intake through scope-approval must be complete with a passing gate.
        $state = Get-Content -LiteralPath (Join-Path $stateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        foreach ($stageId in @('ado-intake', 'domain-context', 'scope-candidate', 'proposed-scope', 'scope-analysis', 'scope-approval')) {
            $stage = @($state.stages) | Where-Object { $_.id -eq $stageId } | Select-Object -First 1
            $stage.status | Should -Be 'complete' -Because "stage '$stageId' must be complete on the real lifecycle"
            $stage.gateResult | Should -Be 'pass' -Because "stage '$stageId' must have a passing gate"
        }
        @($state.blocks).Count | Should -Be 0

        # State integrity check.
        $validation = & $script:ValidatePath -StateDir $stateDir -Json | ConvertFrom-Json
        $validation.Status | Should -Be 'Valid'
        $validation.Details.ApprovedScopeHash | Should -Not -BeNullOrEmpty
    }
}
