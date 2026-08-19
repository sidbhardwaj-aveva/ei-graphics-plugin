#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Post-write scope drift validation' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $resolverScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts'
        $flowScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts'
        $validatorScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-validator' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:NewScopePath = Join-Path $resolverScripts 'New-EiProposedScope.ps1'
        $script:SealPath = Join-Path $flowScripts 'New-EiApprovedScope.ps1'
        $script:DriftPath = Join-Path $validatorScripts 'Test-EiScopeDrift.ps1'
        $script:ChangeRequestPath = Join-Path $validatorScripts 'New-EiScopeChangeRequest.ps1'
    }

    BeforeEach {
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src/Ei.Graphics.Rendering') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src/Ei.Graphics.Rendering/LabelPlacement.cs') -Value '// placement'

        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'

        $storyPath = Join-Path $TestDrive 'story.json'
        Set-Content -LiteralPath $storyPath -Value (@{
                storyId  = '123456'
                storyRef = 'https://dev.azure.com/example/_workitems/edit/123456'
                summary  = 'Stop termination labels overlapping when they share a point.'
            } | ConvertTo-Json -Depth 10)

        $contextPath = Join-Path $TestDrive 'domain-context.json'
        Set-Content -LiteralPath $contextPath -Value (@{
                source      = 'ei-vocabulary-navigator'
                terms       = @('label placement')
                ambiguities = @()
                confidence  = 0.9
            } | ConvertTo-Json -Depth 10)

        $candidatePath = Join-Path $TestDrive 'candidate.json'
        Set-Content -LiteralPath $candidatePath -Value (@{
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
                protectedAreas  = @(
                    @{ path = 'src/Ei.Graphics.Core'; reason = 'Shared geometry kernel; changes here affect every drawing.' }
                )
                dependencies    = @()
                excluded        = @()
                risks           = @()
                unresolved      = @()
            } | ConvertTo-Json -Depth 20)

        & $script:NewScopePath -StoryInputPath $storyPath -CandidatePath $candidatePath `
            -DomainContextPath $contextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

        & $script:SealPath -StateDir $script:StateDir -ApprovedBy 'approver@aveva.com' -ApprovalNote 'Narrow and provable.' -Json | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'writes inside the sealed scope' {
        It 'passes and records the version it judged against' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.Verdict | Should -Be 'pass'
            $result.Details.ApprovedScopeVersion | Should -Be 1
            @($result.Details.OutOfScopePaths).Count | Should -Be 0
        }

        It 'accepts a Windows-separated path as the same file' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src\Ei.Graphics.Rendering\LabelPlacement.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.Verdict | Should -Be 'pass'
        }

        It 'allows workflow bookkeeping paths without authorising them as scope' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs', '.copilottracking/ei-graphics/123456/validation.json' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $evidence = Get-Content -LiteralPath (Join-Path $script:StateDir 'validation' 'implementation.json') -Raw | ConvertFrom-Json
            @($evidence.paths | Where-Object { $_.classification -eq 'allowed' }).Count | Should -Be 1
        }

        It 'writes per-stage evidence so one stage cannot overwrite another' {
            & $script:DriftPath -StateDir $script:StateDir -Stage 'specification' -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs' -Json | Out-Null
            & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs' -Json | Out-Null

            Test-Path -LiteralPath (Join-Path $script:StateDir 'validation' 'specification.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:StateDir 'validation' 'implementation.json') | Should -BeTrue
        }
    }

    Context 'writes outside the sealed scope' {
        It 'blocks a file the sealed scope does not name' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs', 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Details.Verdict | Should -Be 'block'
            @($result.Details.OutOfScopePaths) | Should -Contain 'src/Ei.Graphics.Rendering/LabelMetrics.cs'
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-DRIFT-OUT-OF-SCOPE*'
        }

        It 'does not treat a sibling in an authorised folder as authorised' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/Nested/Deep.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.OutOfScopePaths).Count | Should -Be 1
        }

        It 'blocks a write into a protected area' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Core/Geometry.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.ProtectedPaths) | Should -Contain 'src/Ei.Graphics.Core/Geometry.cs'
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-DRIFT-PROTECTED*'
        }

        It 'leaves the sealed scope untouched when it blocks' {
            $sealPath = Join-Path $script:StateDir 'approved-scope.v1.json'
            $before = Get-Content -LiteralPath $sealPath -Raw

            & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' -ChangedPath 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | Out-Null

            Get-Content -LiteralPath $sealPath -Raw | Should -Be $before
        }
    }

    Context 'evidence the gate cannot trust' {
        It 'refuses to judge drift against a tampered seal' {
            $sealPath = Join-Path $script:StateDir 'approved-scope.v1.json'
            $seal = Get-Content -LiteralPath $sealPath -Raw | ConvertFrom-Json
            $seal.scope.proposedFiles[0].path = 'src/Ei.Graphics.Rendering/LabelMetrics.cs'
            Set-Content -LiteralPath $sealPath -Value ($seal | ConvertTo-Json -Depth 30)

            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-SEAL-UNVERIFIED*'
        }

        It 'refuses to run before anything has been sealed' {
            Remove-Item -LiteralPath (Join-Path $script:StateDir 'approved-scope.v1.json') -Force

            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' `
                -ChangedPath 'src/Ei.Graphics.Rendering/LabelPlacement.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-SEAL-MISSING*'
        }

        It 'treats an empty change set as an input error, not a pass' {
            $result = & $script:DriftPath -StateDir $script:StateDir -Stage 'implementation' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-INPUT-INVALID*'
        }
    }

    Context 'raising a scope-change request' {
        It 'records the request against the sealed version and hash' {
            $result = & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'The placement rule reads metrics that must change with it.' `
                -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -DetectedBy scope-validation -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.Version | Should -Be 1

            $request = Get-Content -LiteralPath (Join-Path $script:StateDir 'scope-change-request.v1.json') -Raw | ConvertFrom-Json
            $request.basedOnApprovedScopeVersion | Should -Be 1
            $request.basedOnContentHash | Should -Match '^sha256:[0-9a-f]{64}$'
            $request.supersedes | Should -BeNullOrEmpty
            @($request.requestedPaths).Count | Should -Be 1
        }

        It 'never mutates the sealed scope it was raised against' {
            $sealPath = Join-Path $script:StateDir 'approved-scope.v1.json'
            $before = Get-Content -LiteralPath $sealPath -Raw

            & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'Metrics must change too.' -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | Out-Null

            Get-Content -LiteralPath $sealPath -Raw | Should -Be $before
        }

        It 'appends a superseding version rather than editing the first request' {
            & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'Metrics must change too.' -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | Out-Null

            $firstBefore = Get-Content -LiteralPath (Join-Path $script:StateDir 'scope-change-request.v1.json') -Raw

            $second = & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'The anchor helper is needed as well.' -Path 'src/Ei.Graphics.Rendering/LabelAnchor.cs' -Json | ConvertFrom-Json

            $second.Details.Version | Should -Be 2
            Get-Content -LiteralPath (Join-Path $script:StateDir 'scope-change-request.v1.json') -Raw | Should -Be $firstBefore

            $request = Get-Content -LiteralPath (Join-Path $script:StateDir 'scope-change-request.v2.json') -Raw | ConvertFrom-Json
            $request.supersedes | Should -Be 1
        }

        It 'refuses to request a protected area' {
            $result = & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'The kernel needs a tweak.' -Path 'src/Ei.Graphics.Core/Geometry.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-CHANGE-PROTECTED*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'scope-change-request.v1.json') | Should -BeFalse
        }

        It 'refuses a request for paths that are already authorised' {
            $result = & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'Just in case.' -Path 'src/Ei.Graphics.Rendering/LabelPlacement.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-CHANGE-REDUNDANT*'
        }

        It 'refuses an unattributed request' {
            $result = & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy '  ' `
                -Reason 'Metrics must change too.' -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-CHANGE-REQUESTER-MISSING*'
        }

        It 'leaves the workflow state untouched' {
            $statePath = Join-Path $script:StateDir 'workflow-state.json'
            $before = Get-Content -LiteralPath $statePath -Raw

            & $script:ChangeRequestPath -StateDir $script:StateDir -RequestedBy 'dev@aveva.com' `
                -Reason 'Metrics must change too.' -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -Json | Out-Null

            Get-Content -LiteralPath $statePath -Raw | Should -Be $before
        }
    }
}
