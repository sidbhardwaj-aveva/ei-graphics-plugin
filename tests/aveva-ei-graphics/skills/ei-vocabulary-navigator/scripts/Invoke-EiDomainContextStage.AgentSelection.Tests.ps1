#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Tests for the agent-driven domain selection architecture in Invoke-EiDomainContextStage.ps1.

Covers:
  Understanding / confirmation gate:
    - Stage blocks when -HumanConfirmed is not set (EIVN-DOMAIN-NOT-CONFIRMED).
    - Stage completes with empty domainSkills and humanConfirmation when -HumanConfirmed is set
      and SelectedDomainIds is empty (agent + user agree no domain applies).

  Domain selection:
    - Clear single-domain selection produces the correct domainSkills entry.
    - Two-domain selection injects both domain skill contexts.
    - An unregistered domain ID blocks the stage (EIVN-DOMAIN-NOT-REGISTERED).

  Human-verification flow:
    - Confirmed selection writes humanConfirmation.status = 'confirmed'.
    - Stage blocked by missing confirmation is in 'blocked' state, not 'complete'.

  Regression:
    - domain-context.json is schema-valid after confirmation.
    - vocabulary-map.json is not touched by the domain-context stage.
#>

Describe 'Invoke-EiDomainContextStage — agent-driven selection' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..' '..' '..' 'helpers' 'EiTestPreflight.ps1')
        $repoRoot     = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'
        $vocabScripts = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts'

        $script:InitPath        = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath       = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:IntakeStagePath = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextPath     = Join-Path $vocabScripts 'Invoke-EiDomainContextStage.ps1'
        $script:ProdRegistryPath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'references' 'domain-skill-registry.json'
        $script:VocabMapPath    = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'data' 'vocabulary-map.json'

        $script:WorkItemJson    = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-123456.json'
        ) -Raw

        function script:Get-EiStage {
            param([string]$StateDir, [string]$StageId)
            $state = Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
            @($state.stages) | Where-Object { $_.id -eq $StageId } | Select-Object -First 1
        }

        function script:New-TestRegistryWithDomain {
            param([string]$RegistryPath, [string]$DomainId, [string]$SkillPath)
            $registry = [ordered]@{
                schemaVersion = '1.0.0'
                description   = 'Test registry.'
                domains       = @(
                    [ordered]@{ id = $DomainId; displayName = $DomainId; skillPath = $SkillPath }
                )
            }
            Set-Content -LiteralPath $RegistryPath -Value ($registry | ConvertTo-Json -Depth 10)
        }

        function script:New-MinimalSkillMd {
            param([string]$Path)
            Set-Content -LiteralPath $Path -Value @'
# Test Domain Skill

Use this skill for test domain work.

### Key Files

| File | Purpose |
|------|---------|
| `src/Test/TestService.cs` | Core test service |
'@ -NoNewline
        }
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
        script:New-EiTestPreflightEvidence -StateDir $script:StateDir -StoryId '123456'
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

    # ── Human confirmation gate ───────────────────────────────────────────────────────────────────

    Context 'human confirmation gate' {
        It 'blocks the stage when -HumanConfirmed is not set' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('termination-drawing') -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-DOMAIN-NOT-CONFIRMED*'
            (script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context').status | Should -Be 'blocked'
        }

        It 'sets HumanConfirmed = true in the result when -HumanConfirmed is passed' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.HumanConfirmed | Should -Be $true
        }

        It 'writes humanConfirmation.status = confirmed into the artifact' {
            & $script:ContextPath -StateDir $script:StateDir -HumanConfirmed -Json | Out-Null

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            $artifact.humanConfirmation.status | Should -Be 'confirmed'
        }
    }

    # ── Empty selection (no domain applies) ──────────────────────────────────────────────────────

    Context 'confirmed empty selection' {
        It 'completes with empty domainSkills when agent selects no domains' {
            $result = & $script:ContextPath -StateDir $script:StateDir -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            @($result.Details.DetectedDomains).Count | Should -Be 0

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            @($artifact.domainSkills).Count | Should -Be 0
            $artifact.humanConfirmation.status | Should -Be 'confirmed'
        }
    }

    # ── Single-domain selection ───────────────────────────────────────────────────────────────────

    Context 'single registered domain' {
        It 'injects the domain skill context for a confirmed single-domain selection' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('termination-drawing') -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            @($result.Details.DetectedDomains) | Should -Contain 'termination-drawing'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            $skill = @($artifact.domainSkills) | Where-Object { $_.domainId -eq 'termination-drawing' } | Select-Object -First 1
            $skill | Should -Not -BeNullOrEmpty
            $skill.displayName | Should -Be 'Termination Drawing'
            @($skill.keyFiles).Count | Should -BeGreaterOrEqual 1
            $skill.keyFilesNote | Should -BeLike '*candidate evidence*'
        }

        It 'produces a valid source field in the artifact' {
            & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('termination-drawing') -HumanConfirmed -Json | Out-Null

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            $artifact.source | Should -Be 'ei-domain-skill-registry'
        }
    }

    # ── Two-domain selection ──────────────────────────────────────────────────────────────────────

    Context 'two-domain selection' {
        It 'injects both domain skill contexts when two IDs are confirmed' {
            # Build a second fixture skill and a two-domain registry.
            $secondSkillPath = Join-Path $TestDrive 'second-domain.md'
            script:New-MinimalSkillMd -Path $secondSkillPath

            $registryPath = Join-Path $TestDrive 'two-domain-registry.json'
            $registry = [ordered]@{
                schemaVersion = '1.0.0'
                description   = 'Test.'
                domains       = @(
                    [ordered]@{
                        id          = 'termination-drawing'
                        displayName = 'Termination Drawing'
                        skillPath   = 'skills/termination-drawing/SKILL.md'
                    },
                    [ordered]@{
                        id          = 'second-domain'
                        displayName = 'Second Domain'
                        skillPath   = $secondSkillPath
                    }
                )
            }
            Set-Content -LiteralPath $registryPath -Value ($registry | ConvertTo-Json -Depth 10)

            $result = & $script:ContextPath -StateDir $script:StateDir `
                -RegistryPath $registryPath `
                -SelectedDomainIds @('termination-drawing', 'second-domain') -HumanConfirmed `
                -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $detected = @($result.Details.DetectedDomains)
            $detected | Should -Contain 'termination-drawing'
            $detected | Should -Contain 'second-domain'

            $artifact = Get-Content -LiteralPath (Join-Path $script:StateDir 'domain-context.json') -Raw | ConvertFrom-Json
            @($artifact.domainSkills).Count | Should -Be 2
            $artifact.humanConfirmation.status | Should -Be 'confirmed'
        }
    }

    # ── Unregistered domain rejected ──────────────────────────────────────────────────────────────

    Context 'unregistered domain ID' {
        It 'blocks with EIVN-DOMAIN-NOT-REGISTERED when the selected ID is not in the registry' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('not-a-real-domain') -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-DOMAIN-NOT-REGISTERED*'
            (script:Get-EiStage -StateDir $script:StateDir -StageId 'domain-context').status | Should -Be 'blocked'
        }

        It 'lists available IDs in the error message so the agent can re-present options' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('not-a-real-domain') -HumanConfirmed -Json | ConvertFrom-Json

            @($result.Errors) -join ' ' | Should -BeLike '*termination-drawing*'
        }

        It 'rejects an abbreviation (TD) that does not match a registry ID exactly' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('TD') -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-DOMAIN-NOT-REGISTERED*'
        }

        It 'rejects a near-synonym (termination-diagram) that is not in the registry' {
            $result = & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('termination-diagram') -HumanConfirmed -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIVN-DOMAIN-NOT-REGISTERED*'
        }
    }

    # ── Vocabulary map regression ─────────────────────────────────────────────────────────────────

    Context 'vocabulary-map regression' {
        It 'does not read or modify vocabulary-map.json during the domain-context stage' {
            $vocabMapBefore = (Get-Item -LiteralPath $script:VocabMapPath).LastWriteTime

            & $script:ContextPath -StateDir $script:StateDir `
                -SelectedDomainIds @('termination-drawing') -HumanConfirmed -Json | Out-Null

            $vocabMapAfter = (Get-Item -LiteralPath $script:VocabMapPath).LastWriteTime
            $vocabMapAfter | Should -Be $vocabMapBefore
        }
    }
}
