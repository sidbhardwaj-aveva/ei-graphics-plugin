#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Focused tests for Format-EiWorkflowSummary.ps1.

Covers:
  1. Summary contains expected human-readable sections (Story, Understanding, etc.).
  2. Internal terminology (Phase A/B/C/D, artifact names, gate codes) is absent from primary output.
  3. awaiting-approval status shows a "Review Required" section.
  4. blocked status shows plain-language issue description, not a raw code.
  5. Completed checks from passed stages appear in Validation section.
  6. -Technical flag adds diagnostic detail without polluting the primary output.
  7. Domain area section is populated from domain-context artifact when available.
  8. Returns an error for a missing state directory.
#>

Describe 'Format-EiWorkflowSummary' -Tag 'Unit' {
    BeforeAll {
        $repoRoot      = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $pluginSkills  = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills'
        $stateScripts  = Join-Path $pluginSkills 'ei-workflow-state' 'scripts'

        $script:ScriptPath  = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Format-EiWorkflowSummary.ps1'
        $script:InitPath    = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:StagePath   = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
        $script:IntakePath  = Join-Path $pluginSkills 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoIntakeStage.ps1'
        $script:ContextPath = Join-Path $pluginSkills 'ei-vocabulary-navigator' 'scripts' 'Invoke-EiDomainContextStage.ps1'
        $script:ApprovalPath = Join-Path $pluginSkills 'ei-graphics-workflow' 'scripts' 'Resolve-EiScopeApproval.ps1'
        $script:ResolverPath = Join-Path $pluginSkills 'ei-scope-resolver' 'scripts' 'New-EiProposedScope.ps1'
        $script:AnalysisPath = Join-Path $pluginSkills 'ei-scope-validator' 'scripts' 'Invoke-EiScopeAnalysis.ps1'

        $script:WorkItemCableJson = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-123456.json'
        ) -Raw
        $script:WorkItemTerminationJson = Get-Content -LiteralPath (
            Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'fixtures' 'work-item-789012.json'
        ) -Raw
        $script:CandidatePath = Join-Path $repoRoot 'tests' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'fixtures' 'candidate-scope-123456.json'

        # Terms that must never appear in the primary summary output.
        $script:InternalTerms = @(
            'Phase A', 'Phase B', 'Phase C', 'Phase D',
            'EISR-', 'EISV-', 'EIWF-', 'EIVN-', 'EIADO-',
            'artifact-present', 'scope-hash', 'human-approval',
            'workflow-result', 'proposed-scope.json', 'ado.json',
            'domain-context.json', 'approved-scope.v1.json',
            'gateResult', 'blockReason', 'lifecycle-implement'
        )

        function script:InitWorkflow {
            param([string]$StoryId, [string]$WorkspaceRoot)
            & $script:InitPath -StoryId $StoryId -WorkspaceRoot $WorkspaceRoot -Json | Out-Null
            $stateDir = Join-Path $WorkspaceRoot '.copilottracking' 'ei-graphics' $StoryId
            foreach ($id in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $stateDir -StageId $id -Action start -Json | Out-Null
                & $script:StagePath -StateDir $stateDir -StageId $id -Action complete -GateResult pass -Json | Out-Null
            }
            return $stateDir
        }
    }

    BeforeEach {
        $script:StateDir = script:InitWorkflow -StoryId '123456' -WorkspaceRoot $TestDrive
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── 1: Required sections ──────────────────────────────────────────────────────
    Context 'required sections' {
        It 'output contains Story, Understanding, Relevant Area, Proposed Scope, Validation, and Next Step sections' {
            $result = & $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $result.Status | Should -Be 'Valid'
            $summary = $result.Details.Summary

            $summary | Should -BeLike '*## Story*'
            $summary | Should -BeLike '*## Understanding*'
            $summary | Should -BeLike '*## Relevant Area*'
            $summary | Should -BeLike '*## Proposed Scope*'
            $summary | Should -BeLike '*## Validation*'
            $summary | Should -BeLike '*## Next Step*'
        }

        It 'populates Story section from the ado artifact after intake' {
            & $script:IntakePath -StateDir $script:StateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
                -CliWorkItemJson $script:WorkItemCableJson -Json | Out-Null

            $result = & $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json
            $summary = $result.Details.Summary

            $summary | Should -BeLike '*123456*'
            $summary | Should -BeLike '*Termination labels*'
        }
    }

    # ── 2: No internal terminology in primary output ──────────────────────────────
    Context 'no internal terminology in primary output' {
        It 'does not expose phase labels, gate codes, or artifact file names' {
            & $script:IntakePath -StateDir $script:StateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
                -CliWorkItemJson $script:WorkItemCableJson -Json | Out-Null
            & $script:ContextPath -StateDir $script:StateDir -Json | Out-Null

            $result = & $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json
            $summary = $result.Details.Summary

            foreach ($term in $script:InternalTerms) {
                $summary | Should -Not -BeLike "*$term*" -Because "internal term '$term' must not appear in the primary output"
            }
        }

        It 'exposes technical details only when -Technical is supplied' {
            $plain    = (& $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json).Details.Summary
            $detailed = (& $script:ScriptPath -StateDir $script:StateDir -Technical -Json | ConvertFrom-Json).Details.Summary

            $plain    | Should -Not -BeLike '*## Technical Details*'
            $detailed | Should -BeLike '*## Technical Details*'
            $detailed | Should -BeLike '*Gate results:*'
        }
    }

    # ── 3: awaiting-approval shows Review Required section ───────────────────────
    Context 'awaiting-approval status' {
        BeforeEach {
            # Run the full lifecycle up to awaiting-approval using the cable work item.
            $workspace = Join-Path $TestDrive 'ws-approval'
            New-Item -ItemType Directory -Path (Join-Path $workspace 'src' 'Ei.Graphics.Rendering') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $workspace 'src' 'Ei.Graphics.Rendering' 'LabelPlacement.cs') -Value '// stub'
            $script:ApprovalStateDir = script:InitWorkflow -StoryId '900001' -WorkspaceRoot $workspace

            & $script:IntakePath -StateDir $script:ApprovalStateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/900001' `
                -CliWorkItemJson ($script:WorkItemCableJson -replace '"id": 123456', '"id": 900001' -replace '123456', '900001') `
                -Json | Out-Null
            & $script:ContextPath -StateDir $script:ApprovalStateDir -Json | Out-Null
            # scope-candidate: write the known-good fixture and advance the stage.
            Copy-Item -LiteralPath $script:CandidatePath -Destination (Join-Path $script:ApprovalStateDir 'candidate.json') -Force
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'scope-candidate' -Action start    -Json | Out-Null
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'scope-candidate' -Action complete -GateResult pass -Json | Out-Null
            & $script:ResolverPath `
                -StoryInputPath (Join-Path $script:ApprovalStateDir 'ado.json') `
                -CandidatePath $script:CandidatePath `
                -DomainContextPath (Join-Path $script:ApprovalStateDir 'domain-context.json') `
                -RepositoryRoot $workspace `
                -StateDir $script:ApprovalStateDir -Json | Out-Null
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'proposed-scope' -Action start -Json | Out-Null
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'proposed-scope' -Action complete -GateResult pass -Json | Out-Null
            & $script:AnalysisPath -StateDir $script:ApprovalStateDir -Json | Out-Null
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'scope-analysis' -Action start -Json | Out-Null
            & $script:StagePath -StateDir $script:ApprovalStateDir -StageId 'scope-analysis' -Action complete -GateResult pass -Json | Out-Null
            & $script:ApprovalPath -StateDir $script:ApprovalStateDir -Decision request -Json | Out-Null
        }

        AfterEach {
            Remove-Item -LiteralPath (Join-Path $TestDrive 'ws-approval') -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'shows a Review Required section when status is awaiting-approval' {
            $result = & $script:ScriptPath -StateDir $script:ApprovalStateDir -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $result.Details.WorkflowStatus | Should -Be 'awaiting-approval'
            $result.Details.Summary | Should -BeLike '*## Review Required*'
        }

        It 'Review Required section uses plain language without gate codes' {
            $summary = (& $script:ScriptPath -StateDir $script:ApprovalStateDir -Json | ConvertFrom-Json).Details.Summary
            $reviewSection = ($summary -split '## Review Required', 2)[-1] -split '## Next Step', 2 | Select-Object -First 1
            $reviewSection | Should -Not -BeLike '*EIWF-*'
            $reviewSection | Should -Not -BeLike '*human-approval*'
            $reviewSection | Should -BeLike '*approve*'
        }

        It 'Validation section shows checks that passed before the pause' {
            $summary = (& $script:ScriptPath -StateDir $script:ApprovalStateDir -Json | ConvertFrom-Json).Details.Summary
            $summary | Should -BeLike '*Story context retrieved successfully*'
            $summary | Should -BeLike '*Scope analysis completed successfully*'
        }
    }

    # ── 4: blocked status uses plain language ────────────────────────────────────
    Context 'blocked status' {
        It 'blocked stage message appears without raw block codes in primary output' {
            # Block the domain-context stage manually and check formatter output.
            & $script:StagePath -StateDir $script:StateDir -StageId 'ado-intake' -Action start -Json | Out-Null
            & $script:StagePath -StateDir $script:StateDir -StageId 'ado-intake' -Action block `
                -BlockCode 'EIVN-ADO-UNREADABLE' `
                -BlockMessage 'The story details could not be loaded from Azure DevOps.' `
                -Remediation 'Ensure the ADO intake step ran successfully before attempting domain-context.' `
                -Json | Out-Null

            $result = & $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0

            $summary = $result.Details.Summary
            $summary | Should -BeLike '*The story details could not be loaded*'
            $summary | Should -Not -BeLike '*EIVN-ADO-UNREADABLE*'
        }
    }

    # ── 5: Validation section lists completed checks ──────────────────────────────
    Context 'completed checks in Validation' {
        It 'shows "Story context retrieved" after ado-intake passes' {
            & $script:IntakePath -StateDir $script:StateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
                -CliWorkItemJson $script:WorkItemCableJson -Json | Out-Null

            $summary = (& $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json).Details.Summary
            $summary | Should -BeLike '*Story context retrieved successfully*'
        }

        It 'shows "Domain area identified" after domain-context passes' {
            & $script:IntakePath -StateDir $script:StateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
                -CliWorkItemJson $script:WorkItemCableJson -Json | Out-Null
            & $script:ContextPath -StateDir $script:StateDir -Json | Out-Null

            $summary = (& $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json).Details.Summary
            $summary | Should -BeLike '*Domain area identified*'
        }
    }

    # ── 6: Relevant Area section from domain-context artifact ─────────────────────
    Context 'Relevant Area section from domain-context' {
        It 'shows domain name and key file hints when domain was detected' {
            # Use the termination-drawing work item which has detection terms.
            & $script:InitPath -StoryId '789012' -WorkspaceRoot $TestDrive -Json | Out-Null
            $tdStateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '789012'
            foreach ($id in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $tdStateDir -StageId $id -Action start -Json | Out-Null
                & $script:StagePath -StateDir $tdStateDir -StageId $id -Action complete -GateResult pass -Json | Out-Null
            }
            & $script:IntakePath -StateDir $tdStateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/789012' `
                -CliWorkItemJson $script:WorkItemTerminationJson -Json | Out-Null
            & $script:ContextPath -StateDir $tdStateDir -Json | Out-Null

            $summary = (& $script:ScriptPath -StateDir $tdStateDir -Json | ConvertFrom-Json).Details.Summary

            $summary | Should -BeLike '*Termination Drawing*'
            $summary | Should -BeLike '*candidate evidence*'
        }

        It 'shows neutral message when no domain was detected' {
            & $script:IntakePath -StateDir $script:StateDir `
                -WorkItemUrl 'https://dev.azure.com/example/MyProject/_workitems/edit/123456' `
                -CliWorkItemJson $script:WorkItemCableJson -Json | Out-Null
            & $script:ContextPath -StateDir $script:StateDir -Json | Out-Null

            $summary = (& $script:ScriptPath -StateDir $script:StateDir -Json | ConvertFrom-Json).Details.Summary
            $summary | Should -BeLike '*No specific domain area was detected*'
        }
    }

    # ── 7: Missing state directory ────────────────────────────────────────────────
    Context 'missing state directory' {
        It 'returns an error when the state directory does not exist' {
            $badDir = Join-Path $TestDrive 'nonexistent'
            $result = & $script:ScriptPath -StateDir $badDir -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-STATE-MISSING*'
        }
    }
}
