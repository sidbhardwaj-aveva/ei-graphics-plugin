#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Scope approval-readiness analysis' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $stateScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $resolverScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts'
        $validatorScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-validator' 'scripts'

        $script:InitPath = Join-Path $stateScripts 'Initialize-EiWorkflowState.ps1'
        $script:NewScopePath = Join-Path $resolverScripts 'New-EiProposedScope.ps1'
        $script:AnalysisPath = Join-Path $validatorScripts 'Invoke-EiScopeAnalysis.ps1'

        function script:New-EiFile {
            param([string]$Root, [string]$RelativePath)
            $full = Join-Path $Root $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value '// content'
        }

        function script:Set-EiCandidate {
            param([string]$Path, [scriptblock]$Mutate)
            $candidate = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            & $Mutate $candidate
            Set-Content -LiteralPath $Path -Value ($candidate | ConvertTo-Json -Depth 20)
        }
    }

    BeforeEach {
        $script:Repo = Join-Path $TestDrive 'repo'
        script:New-EiFile -Root $script:Repo -RelativePath 'src/Ei.Graphics.Rendering/LabelPlacement.cs'

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

        function script:Invoke-EiResolve {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null
        }
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'a narrow, provable scope' {
        BeforeEach { script:Invoke-EiResolve }

        It 'passes the gate' {
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Status | Should -Be 'Valid'
            $result.Details.Verdict | Should -Be 'pass'
            @($result.Details.BlockingCodes).Count | Should -Be 0
        }

        It 'records the canonical hash of the scope it judged' {
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $result.Details.ContentHash | Should -Match '^sha256:[0-9a-f]{64}$'
        }

        It 'writes evidence to both the shared artifact and the per-stage copy' {
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null

            $shared = Join-Path $script:StateDir 'validation.json'
            $staged = Join-Path $script:StateDir 'validation' 'scope-analysis.json'

            Test-Path -LiteralPath $shared | Should -BeTrue
            Test-Path -LiteralPath $staged | Should -BeTrue

            $evidence = Get-Content -LiteralPath $staged -Raw | ConvertFrom-Json
            $evidence.gate | Should -Be 'scope-analysis'
            $evidence.validator | Should -Be 'ei-scope-validator'
            $evidence.verdict | Should -Be 'pass'
            $evidence.approvedScopeVersion | Should -BeNullOrEmpty
        }

        It 'classifies every proposed path as in-scope' {
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null

            $evidence = Get-Content -LiteralPath (Join-Path $script:StateDir 'validation.json') -Raw | ConvertFrom-Json
            @($evidence.paths).Count | Should -Be 1
            $evidence.paths[0].classification | Should -Be 'in-scope'
        }

        It 'never mutates the proposed scope' {
            $before = Get-Content -LiteralPath (Join-Path $script:StateDir 'proposed-scope.json') -Raw
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null
            Get-Content -LiteralPath (Join-Path $script:StateDir 'proposed-scope.json') -Raw | Should -Be $before
        }
    }

    Context 'a scope the resolver did not resolve' {
        It 'blocks rather than softening the resolver finding' {
            & $script:NewScopePath -StoryInputPath $script:StoryPath -CandidatePath $script:CandidatePath `
                -RepositoryRoot $script:Repo -StateDir $script:StateDir -Json | Out-Null

            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Details.ScopeStatus | Should -Be 'needs-review'
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-SCOPE-NOT-RESOLVED'
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-SCOPE-NOT-APPROVABLE*'
        }
    }

    Context 'a scope that is honest but not approvable' {
        It 'blocks a scope spread across too many implementation areas' {
            script:New-EiFile -Root $script:Repo -RelativePath 'src/Ei.Graphics.Layout/LayoutEngine.cs'
            script:New-EiFile -Root $script:Repo -RelativePath 'src/Ei.Graphics.Model/LabelModel.cs'

            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.proposedFiles = @(
                    $c.proposedFiles[0],
                    [pscustomobject]@{ path = 'src/Ei.Graphics.Layout/LayoutEngine.cs'; changeIntent = 'modify'; symbols = @('Arrange'); evidence = @('E1'); confidence = 0.85 },
                    [pscustomobject]@{ path = 'src/Ei.Graphics.Model/LabelModel.cs'; changeIntent = 'modify'; symbols = @('Label'); evidence = @('E1'); confidence = 0.85 }
                )
                $c.relatedTests = @(
                    $c.relatedTests[0],
                    [pscustomobject]@{ target = 'tests/Ei.Graphics.Layout.Tests/LayoutEngineTests.cs'; kind = 'targeted'; evidence = @('E1') },
                    [pscustomobject]@{ target = 'tests/Ei.Graphics.Model.Tests/LabelModelTests.cs'; kind = 'targeted'; evidence = @('E1') }
                )
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.ImplementationAreas).Count | Should -Be 3
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-AREA-SPREAD'
        }

        It 'blocks a file proposed below the per-file confidence floor' {
            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.proposedFiles[0].confidence = 0.4
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-FILE-CONFIDENCE-LOW'
        }

        It 'blocks a modification that names no symbol' {
            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.proposedFiles[0].symbols = @()
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-SYMBOLS-MISSING'
        }

        It 'blocks a file no related test names' {
            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.relatedTests = @(
                    [pscustomobject]@{ target = 'tests/Ei.Graphics.Rendering.Tests/RenderPipelineTests.cs'; kind = 'targeted'; evidence = @('E2') }
                )
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-TEST-COVERAGE-GAP'
        }

        It 'blocks a scope carrying a high-severity risk' {
            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.risks = @(
                    [pscustomobject]@{ id = 'R1'; description = 'Placement is shared with the print path'; severity = 'high'; mitigation = 'Pin the print path with a test first' }
                )
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Details.BlockingCodes) | Should -Contain 'EISV-RISK-HIGH'
        }

        It 'still records evidence when it blocks' {
            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.proposedFiles[0].symbols = @()
            }

            script:Invoke-EiResolve
            & $script:AnalysisPath -StateDir $script:StateDir -Json | Out-Null

            $evidence = Get-Content -LiteralPath (Join-Path $script:StateDir 'validation' 'scope-analysis.json') -Raw | ConvertFrom-Json
            $evidence.verdict | Should -Be 'block'
            @($evidence.findings | Where-Object { $_.code -eq 'EISV-SYMBOLS-MISSING' }).Count | Should -Be 1
        }
    }

    Context 'advisory findings' {
        It 'records a deletion without blocking approval' {
            script:New-EiFile -Root $script:Repo -RelativePath 'src/Ei.Graphics.Rendering/LegacyLabel.cs'

            script:Set-EiCandidate -Path $script:CandidatePath -Mutate {
                param($c)
                $c.proposedFiles = @(
                    $c.proposedFiles[0],
                    [pscustomobject]@{ path = 'src/Ei.Graphics.Rendering/LegacyLabel.cs'; changeIntent = 'delete'; symbols = @(); evidence = @('E1'); confidence = 0.8 }
                )
            }

            script:Invoke-EiResolve
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.Verdict | Should -Be 'pass'
            @($result.Details.FindingCodes) | Should -Contain 'EISV-DELETE-PRESENT'
            @($result.Warnings) -join ' ' | Should -BeLike '*EISV-DELETE-PRESENT*'
        }
    }

    Context 'a missing proposal' {
        It 'refuses to analyse a scope that was never written' {
            $result = & $script:AnalysisPath -StateDir $script:StateDir -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            @($result.Errors) -join ' ' | Should -BeLike '*EISV-ARTIFACT-UNREADABLE*'
            Test-Path -LiteralPath (Join-Path $script:StateDir 'validation.json') | Should -BeFalse
        }
    }
}
