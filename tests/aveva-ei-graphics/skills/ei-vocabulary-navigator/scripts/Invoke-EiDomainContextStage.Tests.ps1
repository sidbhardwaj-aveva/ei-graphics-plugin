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

        # The stage reads the story from the sealed ado artifact, so the real intake stage produces it
        # rather than the test hand-writing a state file.
        & $script:IntakeStagePath -StateDir $script:StateDir `
            -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
            -CliWorkItemJson $script:WorkItemJson -Json | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'resolving candidate terms' {
        It 'resolves the terms the story names and completes the stage with a passing gate' {
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Terms @('cable', 'terminal arrangement') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.GateResult | Should -Be 'pass'

            $stage = script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context'
            $stage.status | Should -Be 'complete'
            $stage.gateResult | Should -Be 'pass'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            $artifact.source | Should -Be 'ei-vocabulary-navigator'
            @($artifact.terms) | Should -Contain 'cable'
            @($artifact.terms) | Should -Contain 'terminal arrangement'
            @($artifact.domainPacks | Where-Object { $_.term -eq 'cable' }).repositoryInterfaces | Should -Contain 'ICableRepository'
            $artifact.confidence | Should -BeGreaterOrEqual 0.7
        }

        It 'keeps a term the story never mentions out of the resolved set' {
            # `distribution board` is real EI vocabulary, so the navigator resolves it. It is still
            # not this story's domain, and a caller must not be able to widen the context by naming it.
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Terms @('cable', 'distribution board') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            @($result.Details.ResolvedTerms) | Should -Not -Contain 'distribution board'
            @($result.Details.UnresolvedTerms) | Should -Contain 'distribution board'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            @($artifact.domainPacks | ForEach-Object { $_.term }) | Should -Not -Contain 'distribution board'
        }

        It 'records an ambiguous term without inventing a domain pack for it' {
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Terms @('cable', 'signal') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            @($artifact.ambiguities | ForEach-Object { $_.term }) | Should -Contain 'signal'
            @($artifact.unresolvedTerms) | Should -Contain 'signal'
            @($artifact.domainPacks | ForEach-Object { $_.term }) | Should -Not -Contain 'signal'
        }
    }

    Context 'refusing a domain context it cannot stand behind' {
        It 'blocks the run when no candidate term resolves' {
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Terms @('sprocket alignment') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-DOMAIN-PACK-UNRESOLVED*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'domain-context.json') | Should -BeFalse

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.status | Should -Be 'blocked'
            @($state.blocks)[-1].code | Should -Be 'EIVN-DOMAIN-PACK-UNRESOLVED'
        }

        It 'blocks the run when no candidate terms were supplied at all' {
            $result = & $script:ContextStagePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-NO-CANDIDATE-TERMS*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'domain-context.json') | Should -BeFalse
        }

        It 'refuses to run before the ado artifact exists' {
            Remove-Item -LiteralPath (Join-Path $script:StateDir 'ado.json') -Force

            $result = & $script:ContextStagePath -StateDir $script:StateDir -Terms @('cable') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-ADO-UNREADABLE*'
            (script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context').status | Should -Be 'pending'
        }
    }
}
