#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'ProposedScope artifact and gate' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $scopeScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:WritePath = Join-Path $stateScripts 'Write-EiWorkflowArtifact.ps1'
        $script:ReadPath = Join-Path $stateScripts 'Read-EiWorkflowArtifact.ps1'
        $script:NewScopePath = Join-Path $scopeScripts 'New-EiProposedScope.ps1'
        $script:TestScopePath = Join-Path $scopeScripts 'Test-EiProposedScope.ps1'
    }

    BeforeEach {
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src/Ei.Graphics.Rendering') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src/Ei.Graphics.Rendering/LabelPlacement.cs') -Value '// placement'

        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
        $script:ArtifactPath = Join-Path $script:StateDir 'proposed-scope.json'

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

    Context 'artifact registry activation' {
        It 'persists a resolved scope into the story state directory' {
            $result = & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'resolved'
            Test-Path -LiteralPath $script:ArtifactPath | Should -BeTrue
        }

        It 'round-trips the artifact through the state store' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $read = & $script:ReadPath -StateDir $script:StateDir -Name 'proposed-scope' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $read.Status | Should -Be 'Valid'
            $read.Details.Owner | Should -Be 'ei-scope-resolver'
            $read.Details.Payload.status | Should -Be 'resolved'
        }

        It 'refuses to write proposed-scope content that fails the schema' {
            $result = & $script:WritePath -StateDir $script:StateDir -Name 'proposed-scope' -Content '{"schemaVersion":"1.0.0"}' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EIWF-ARTIFACT-SCHEMA*'
        }
    }

    Context 'the proposed-scope gate' {
        It 'passes a resolved scope' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $gate = & $script:TestScopePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $gate.Status | Should -Be 'Valid'
            $gate.Details.ScopeStatus | Should -Be 'resolved'
            $gate.Details.DerivedStatus | Should -Be 'resolved'
        }

        It 'blocks a scope that still needs review' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $gate = & $script:TestScopePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $gate.Status | Should -Be 'Invalid'
            @($gate.Errors) -join ' ' | Should -BeLike '*EISR-SCOPE-NOT-RESOLVED*'
        }

        It 'detects a status that was raised outside the resolver' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $artifact = Get-Content -LiteralPath $script:ArtifactPath -Raw | ConvertFrom-Json
            $artifact.status = 'resolved'
            Set-Content -LiteralPath $script:ArtifactPath -Value ($artifact | ConvertTo-Json -Depth 20)

            $gate = & $script:TestScopePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($gate.Errors) -join ' ' | Should -BeLike '*EISR-STATUS-MISMATCH*'
        }

        It 'detects evidence that was removed after generation' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $artifact = Get-Content -LiteralPath $script:ArtifactPath -Raw | ConvertFrom-Json
            $artifact.evidence = @($artifact.evidence | Where-Object { $_.id -ne 'E2' })
            Set-Content -LiteralPath $script:ArtifactPath -Value ($artifact | ConvertTo-Json -Depth 20)

            $gate = & $script:TestScopePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($gate.Errors) -join ' ' | Should -BeLike '*EISR-EVIDENCE-MISSING*'
        }

        It 'blocks when the artifact is missing' {
            $gate = & $script:TestScopePath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $gate.Errors[0] | Should -BeLike 'EISR-ARTIFACT-UNREADABLE*'
        }

        It 'requires an artifact source' {
            $gate = & $script:TestScopePath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $gate.Errors[0] | Should -BeLike 'EISR-INPUT-INVALID*'
        }
    }
}
