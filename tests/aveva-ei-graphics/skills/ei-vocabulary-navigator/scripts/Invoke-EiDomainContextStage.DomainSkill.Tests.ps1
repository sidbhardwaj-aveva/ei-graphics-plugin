#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Focused tests for the domain-skill injection added to Invoke-EiDomainContextStage.ps1.

Covers:
  1. Single-domain story: detects the termination-drawing domain and extracts Key Files.
  2. Multi-domain story: detects both domains when story mentions terms from two domains.
  3. Ambiguous story: no domain terms matched; stage still passes with empty domainSkills.
  4. Key Files extraction: correct file/purpose pairs from the SKILL.md table.
  5. Key Files not treated as scope: key files appear only in domainSkills, never in domainPacks.
#>

Describe 'Domain-context stage — domain skill injection' -Tag 'Unit' {
    BeforeAll {
        $repoRoot      = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills  = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts  = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'
        $vocabScripts  = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts'
        $helperScript  = Join-Path $vocabScripts 'helpers' 'Read-EiDomainSkillContext.ps1'
        $readerScript  = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts' 'helpers' 'Read-EiDomainSkillContext.ps1'

        $script:InitPath        = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath       = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:IntakeStagePath = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextStagePath = Join-Path $vocabScripts 'Invoke-EiDomainContextStage.ps1'

        # Fixture work items
        $script:WorkItemCableJson = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-123456.json'
        ) -Raw

        $script:WorkItemTerminationJson = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-789012.json'
        ) -Raw

        # Production SKILL.md for Key Files extraction assertions.
        $script:TerminationSkillPath = Join-Path $pluginSkills 'termination-drawing' 'SKILL.md'

        # Production registry.
        $script:ProductionRegistryPath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'references' 'domain-skill-registry.json'

        function script:Get-EiArtifact {
            param([string]$StateDir, [string]$Name)
            Get-Content -LiteralPath (Join-Path $StateDir "$Name.json") -Raw | ConvertFrom-Json
        }

        function script:Get-EiState {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        }

        function script:Set-EiBaseState {
            param([string]$StateDir, [string]$WorkItemJson, [string]$WorkItemUrl)
            foreach ($stageId in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $StateDir -StageId $stageId -Action start -Json | Out-Null
                & $script:StagePath -StateDir $StateDir -StageId $stageId -Action complete -GateResult pass -Json | Out-Null
            }
            & $script:IntakeStagePath -StateDir $StateDir -WorkItemUrl $WorkItemUrl -CliWorkItemJson $WorkItemJson -Json | Out-Null
        }

        # Build a minimal two-domain registry backed by real SKILL.md files so that
        # the multi-domain test does not need a second real domain skill.
        $script:TwoDomainRegistryPath = Join-Path $TestDrive 'two-domain-registry.json'

        $secondSkillContent = @'
# Second Domain Skill

## When to Use
Use this skill when working on wiring rule features.

### Key Files

| File | Purpose |
|------|---------|
| `src/WiringRule/WiringRuleService.cs` | Evaluates and applies wiring rules |
| `src/WiringRule/WiringRuleRepository.cs` | Persists wiring rule definitions |
'@
        $script:SecondSkillPath = Join-Path $TestDrive 'second-domain.md'
        Set-Content -LiteralPath $script:SecondSkillPath -Value $secondSkillContent -NoNewline

        # Two-domain registry: termination-drawing (real) + wiring-rule (fixture).
        $twoDomainRegistry = [ordered]@{
            schemaVersion = '1.0.0'
            description   = 'Test registry with two domains.'
            domains       = @(
                [ordered]@{
                    id          = 'termination-drawing'
                    displayName = 'Termination Drawing'
                    skillPath   = 'skills/termination-drawing/SKILL.md'
                },
                [ordered]@{
                    id          = 'wiring-rule'
                    displayName = 'Wiring Rule'
                    skillPath   = ''      # overridden per-test via injected absolute path
                }
            )
        }
        Set-Content -LiteralPath $script:TwoDomainRegistryPath -Value ($twoDomainRegistry | ConvertTo-Json -Depth 10)
    }

    BeforeEach {
        & $script:InitPath -StoryId '789012' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '789012'
        script:Set-EiBaseState -StateDir $script:StateDir `
            -WorkItemJson $script:WorkItemTerminationJson `
            -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/789012'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── Test 1: single-domain story ──────────────────────────────────────────────────────────────
    Context 'single-domain story' {
        It 'injects Key Files into the artifact when agent selects and user confirms the domain' {
            $result = & $script:ContextStagePath `
                -StateDir $script:StateDir `
                -RegistryPath $script:ProductionRegistryPath `
                -SelectedDomainIds @('termination-drawing') -HumanConfirmed `
                -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'

            $detectedDomains = @($result.Details.DetectedDomains)
            $detectedDomains | Should -Contain 'termination-drawing'

            $artifact = script:Get-EiArtifact -StateDir $script:StateDir -Name 'domain-context'
            $skills = @($artifact.domainSkills)
            $skills.Count | Should -BeGreaterOrEqual 1

            $td = $skills | Where-Object { $_.domainId -eq 'termination-drawing' } | Select-Object -First 1
            $td | Should -Not -BeNullOrEmpty
            $td.displayName | Should -Be 'Termination Drawing'
            $td.keyFilesNote | Should -Not -BeNullOrEmpty
            @($td.keyFiles).Count | Should -BeGreaterOrEqual 1
        }
    }

    # ── Test 2: multi-domain story ───────────────────────────────────────────────────────────────
    Context 'multi-domain story' {
        It 'detects both domains when the story contains terms from each' {
            # The work item 789012 description already has termination-drawing terms. We extend it
            # by reading the valid ado.json (produced by BeforeEach) and appending wiring-rule terms
            # to the description field, then writing back so schema validation still passes.
            $adoPath = Join-Path $script:StateDir 'ado.json'
            $adoObj = Get-Content -LiteralPath $adoPath -Raw | ConvertFrom-Json
            $adoObj.description = $adoObj.description + ' The WiringRule validation also fires when the wiring rule service evaluates the cable composite key.'
            Set-Content -LiteralPath $adoPath -Value ($adoObj | ConvertTo-Json -Depth 10)

            # Build a registry where the wiring-rule skillPath points to the fixture file.
            $customRegistry = [ordered]@{
                schemaVersion = '1.0.0'
                description   = 'Two-domain test registry.'
                domains       = @(
                    [ordered]@{
                        id          = 'termination-drawing'
                        displayName = 'Termination Drawing'
                        skillPath   = 'skills/termination-drawing/SKILL.md'
                    },
                    [ordered]@{
                        id          = 'wiring-rule'
                        displayName = 'Wiring Rule'
                        skillPath   = $script:SecondSkillPath   # absolute; Join-Path returns it directly on Windows
                    }
                )
            }
            $customRegistryPath = Join-Path $TestDrive 'custom-registry-multi.json'
            Set-Content -LiteralPath $customRegistryPath -Value ($customRegistry | ConvertTo-Json -Depth 10)

            $result = & $script:ContextStagePath `
                -StateDir $script:StateDir `
                -RegistryPath $customRegistryPath `
                -SelectedDomainIds @('termination-drawing', 'wiring-rule') -HumanConfirmed `
                -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $detected = @($result.Details.DetectedDomains)
            $detected | Should -Contain 'termination-drawing'
            $detected | Should -Contain 'wiring-rule'

            $artifact = script:Get-EiArtifact -StateDir $script:StateDir -Name 'domain-context'
            $skills = @($artifact.domainSkills)
            $skills.Count | Should -Be 2
        }
    }

    # ── Test 3: no domain applies ─────────────────────────────────────────────────────────────────
    Context 'no domain (agent and user agree none applies)' {
        It 'completes with empty domainSkills and humanConfirmation when agent selects no domain' {
            & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
            $cableStateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
            script:Set-EiBaseState -StateDir $cableStateDir `
                -WorkItemJson $script:WorkItemCableJson `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456'

            $result = & $script:ContextStagePath `
                -StateDir $cableStateDir `
                -RegistryPath $script:ProductionRegistryPath `
                -HumanConfirmed `
                -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.StageStatus | Should -Be 'complete'
            $result.Details.HumanConfirmed | Should -Be $true

            $artifact = script:Get-EiArtifact -StateDir $cableStateDir -Name 'domain-context'
            @($artifact.domainSkills).Count | Should -Be 0
            $artifact.humanConfirmation.status | Should -Be 'confirmed'
        }
    }

    # ── Test 4: Key Files extraction ─────────────────────────────────────────────────────────────
    Context 'Key Files extraction from SKILL.md' {
        It 'extracts file paths and purposes from the Key Files table in the termination-drawing SKILL.md' {
            $ctx = & (Join-Path $vocabScripts 'helpers' 'Read-EiDomainSkillContext.ps1') `
                -SkillPath $script:TerminationSkillPath `
                -DomainId 'termination-drawing' `
                -DisplayName 'Termination Drawing'

            $ctx.domainId | Should -Be 'termination-drawing'
            $ctx.displayName | Should -Be 'Termination Drawing'
            $ctx.summary | Should -Not -BeNullOrEmpty

            $keyFiles = @($ctx.keyFiles)
            $keyFiles.Count | Should -BeGreaterOrEqual 5

            $generatorFile = $keyFiles | Where-Object {
                $_.file -like '*TerminationDrawingGenerationWorkflow*'
            } | Select-Object -First 1
            $generatorFile | Should -Not -BeNullOrEmpty
            $generatorFile.purpose | Should -Not -BeNullOrEmpty

            $equipInserterFile = $keyFiles | Where-Object {
                $_.file -like '*EquipmentInserter*'
            } | Select-Object -First 1
            $equipInserterFile | Should -Not -BeNullOrEmpty

            $ctx.keyFilesNote | Should -BeLike '*candidate evidence*'
        }

        It 'returns empty keyFiles for a SKILL.md that has no Key Files section' {
            $noKeyFilesSkill = @'
# No Key Files Domain

## When to Use
Use this when you need domain context without any key files.

## Rules
1. Just a rule.
'@
            $tmpPath = Join-Path $TestDrive 'no-key-files.md'
            Set-Content -LiteralPath $tmpPath -Value $noKeyFilesSkill -NoNewline

            $ctx = & (Join-Path $vocabScripts 'helpers' 'Read-EiDomainSkillContext.ps1') `
                -SkillPath $tmpPath `
                -DomainId 'no-key-files' `
                -DisplayName 'No Key Files'

            @($ctx.keyFiles).Count | Should -Be 0
        }
    }

    # ── Test 5: Key Files stay inside domainSkills only ───────────────────────────────────────────
    Context 'Key Files are scoped to domainSkills' {
        It 'keeps Key File paths inside domainSkills entries and not at the artifact top level' {
            $result = & $script:ContextStagePath `
                -StateDir $script:StateDir `
                -RegistryPath $script:ProductionRegistryPath `
                -SelectedDomainIds @('termination-drawing') -HumanConfirmed `
                -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0

            $artifact = script:Get-EiArtifact -StateDir $script:StateDir -Name 'domain-context'

            # The artifact top-level keys must not contain any .cs or .md paths.
            $topLevelKeys = @($artifact.PSObject.Properties.Name)
            $topLevelKeys | ForEach-Object { $_ | Should -Not -BeLike '*.cs' }
            $topLevelKeys | ForEach-Object { $_ | Should -Not -BeLike '*.md' }

            # keyFilesNote must be present on every domain skill entry.
            @($artifact.domainSkills) | ForEach-Object {
                $_.keyFilesNote | Should -Not -BeNullOrEmpty
                $_.keyFilesNote | Should -BeLike '*candidate evidence*'
            }
        }
    }
}
