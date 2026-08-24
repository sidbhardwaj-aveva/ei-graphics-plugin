#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'ApprovedScope sealing' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $flowScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts'
        $scopeScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:SealStatePath = Join-Path $stateScripts 'Set-EiApprovedScopeSeal.ps1'
        $script:NewScopePath = Join-Path $scopeScripts 'New-EiProposedScope.ps1'
        $script:SealPath = Join-Path $flowScripts 'New-EiApprovedScope.ps1'
        $script:HashGatePath = Join-Path $flowScripts 'Test-EiApprovedScopeHash.ps1'

        function script:Get-EiState {
            param([string]$StateDir)
            Get-Content -LiteralPath (Join-Path $StateDir 'workflow-state.json') -Raw | ConvertFrom-Json
        }
    }

    BeforeEach {
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src/Ei.Graphics.Rendering') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src/Ei.Graphics.Rendering/LabelPlacement.cs') -Value '// placement'

        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
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
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'a proposal that is not approvable' {
        It 'refuses to seal a blocked proposal' {
            $candidate = Get-Content -LiteralPath $script:CandidatePath -Raw | ConvertFrom-Json
            $candidate.proposedFiles[0].evidence = @('E9')
            Set-Content -LiteralPath $script:CandidatePath -Value ($candidate | ConvertTo-Json -Depth 20)

            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $result = & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Details.ScopeStatus | Should -Be 'blocked'
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-SCOPE-NOT-APPROVABLE*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
        }

        It 'refuses to seal a proposal that still needs review' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $result = & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Details.ScopeStatus | Should -Be 'needs-review'
            @($result.Errors) -join ' ' | Should -BeLike '*EIWF-SCOPE-NOT-APPROVABLE*'
        }

        It 'leaves the seal fields untouched when sealing is refused' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | Out-Null

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.approvedScopeVersion | Should -BeNullOrEmpty
            $state.approvedScopeHash | Should -BeNullOrEmpty
        }
    }

    Context 'approver identity' {
        BeforeEach {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null
        }

        It 'rejects a missing approver identity' {
            $result = & $script:SealPath -StateDir $script:StateDir -ApprovedBy '  ' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EIWF-APPROVER-MISSING*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeFalse
        }
    }

    Context 'sealing a resolved proposal' {
        BeforeEach {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null
        }

        It 'produces version 1 and records the seal in state' {
            $result = & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -ApprovalNote 'Reviewed in refinement.' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.Version | Should -Be 1
            $result.Details.Supersedes | Should -BeNullOrEmpty
            $result.Details.ContentHash | Should -Match '^sha256:[0-9a-f]{64}$'
            $result.Details.Payload.approvedBy | Should -Be 'approver@aveva.com'
            $result.Details.Payload.approvalNote | Should -Be 'Reviewed in refinement.'

            Test-Path -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') | Should -BeTrue

            $state = script:Get-EiState -StateDir $script:StateDir
            $state.approvedScopeVersion | Should -Be 1
            $state.approvedScopeHash | Should -Be $result.Details.ContentHash
        }

        It 'preserves the approved scope rather than reconstructing it' {
            $result = & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | ConvertFrom-Json

            $proposed = Get-Content -LiteralPath (Join-Path $script:StateDir 'proposed-scope.json') -Raw | ConvertFrom-Json
            $sealed = $result.Details.Payload.scope

            ($sealed | ConvertTo-Json -Depth 30) | Should -Be ($proposed | ConvertTo-Json -Depth 30)
        }

        It 'passes its own scope-hash gate' {
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | Out-Null

            $gate = & $script:HashGatePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $gate.Status | Should -Be 'Valid'
            $gate.Details.StoredHash | Should -Be $gate.Details.ComputedHash
        }

        It 're-seals as version 2 without modifying version 1' {
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'first@aveva.com' -Json | Out-Null
            $v1Before = Get-Content -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Raw

            $second = & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'second@aveva.com' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $second.Details.Version | Should -Be 2
            $second.Details.Payload.supersedes | Should -Be 1
            $second.Details.Payload.approvedBy | Should -Be 'second@aveva.com'

            Get-Content -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Raw | Should -Be $v1Before
            (script:Get-EiState -StateDir $script:StateDir).approvedScopeVersion | Should -Be 2
        }

        It 'detects a sealed scope that was edited after approval' {
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | Out-Null

            $artifactPath = Join-Path $script:StateDir 'approved-scope.v1.json'
            $artifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
            $artifact.scope.proposedFiles[0].path = 'src/Ei.Graphics.Rendering/SomethingElse.cs'
            Set-Content -LiteralPath $artifactPath -Value ($artifact | ConvertTo-Json -Depth 40)

            $gate = & $script:HashGatePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($gate.Errors) -join ' ' | Should -BeLike '*EIWF-SCOPE-HASH-MISMATCH*'
        }

        It 'leaves the sealed artifact untouched when the gate rejects it' {
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | Out-Null

            $artifactPath = Join-Path $script:StateDir 'approved-scope.v1.json'
            $artifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
            $artifact.scope.proposedFiles[0].path = 'src/Ei.Graphics.Rendering/SomethingElse.cs'
            Set-Content -LiteralPath $artifactPath -Value ($artifact | ConvertTo-Json -Depth 40)
            $tampered = Get-Content -LiteralPath $artifactPath -Raw

            & $script:HashGatePath -StateDir $script:StateDir -Json | Out-Null

            Get-Content -LiteralPath $artifactPath -Raw | Should -Be $tampered
        }
    }

    Context 'recording the seal in workflow state' {
        BeforeEach {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null
        }

        It 'refuses a hash that is not a sha256 digest and leaves state unchanged' {
            $before = Get-Content -LiteralPath (Join-Path $script:StateDir 'workflow-state.json') -Raw

            $result = & $script:SealStatePath -StateDir $script:StateDir -ContentHash 'not-a-hash' -Version 1 -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EIWF-SCOPE-HASH-INVALID*'
            Get-Content -LiteralPath (Join-Path $script:StateDir 'workflow-state.json') -Raw | Should -Be $before
        }

        It 'refuses to reuse or lower a sealed version' {
            & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -Json | Out-Null
            $hash = (script:Get-EiState -StateDir $script:StateDir).approvedScopeHash

            $result = & $script:SealStatePath -StateDir $script:StateDir -ContentHash $hash -Version 1 -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EIWF-SCOPE-VERSION-INVALID*'
            (script:Get-EiState -StateDir $script:StateDir).approvedScopeVersion | Should -Be 1
        }
    }
}
