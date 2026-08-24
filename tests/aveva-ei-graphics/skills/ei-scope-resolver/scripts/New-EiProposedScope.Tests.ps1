#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'New-EiProposedScope' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts' 'New-EiProposedScope.ps1'
        $script:SchemaPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'schemas' 'proposed-scope.schema.json'

        function script:New-JsonFile {
            param([string]$Path, $Value)
            Set-Content -LiteralPath $Path -Value ($Value | ConvertTo-Json -Depth 20) -Encoding utf8
            $Path
        }

        function script:New-Candidate {
            param([hashtable]$Override = @{})

            $candidate = @{
                confidence      = 0.85
                rationale       = 'The story changes only the label placement rule, which lives in one file.'
                evidence        = @(
                    @{ id = 'E1'; kind = 'story'; value = 'labels overlap when two terminations share a point'; note = $null },
                    @{ id = 'E2'; kind = 'path'; value = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; note = 'holds the placement rule' }
                )
                proposedFiles   = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @('Resolve'); evidence = @('E1', 'E2'); confidence = 0.86 }
                )
                proposedModules = @(
                    @{ name = 'Ei.Graphics.Rendering'; projectPath = 'src/Ei.Graphics.Rendering/Ei.Graphics.Rendering.csproj'; evidence = @('E2') }
                )
                relatedTests    = @(
                    @{ target = 'tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs'; kind = 'targeted'; evidence = @('E2') }
                )
                protectedAreas  = @()
                dependencies    = @()
                excluded        = @()
                risks           = @()
                unresolved      = @()
            }

            foreach ($key in $Override.Keys) { $candidate[$key] = $Override[$key] }
            $candidate
        }
    }

    BeforeEach {
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src/Ei.Graphics.Rendering') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'tests/Ei.Graphics.Rendering.Tests') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src/Ei.Graphics.Rendering/LabelPlacement.cs') -Value '// placement'
        Set-Content -LiteralPath (Join-Path $script:Repo 'tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs') -Value '// tests'

        $script:StoryPath = script:New-JsonFile (Join-Path $TestDrive 'story.json') @{
            storyId  = '123456'
            storyRef = 'https://dev.azure.com/example/_workitems/edit/123456'
            summary  = 'Stop termination labels overlapping when they share a point.'
        }

        $script:ContextPath = script:New-JsonFile (Join-Path $TestDrive 'domain-context.json') @{
            source      = 'ei-domain-skill-registry'
            domainSkills = @(
                @{ domainId = 'termination-drawing'; displayName = 'Termination Drawing'; summary = ''; keyFiles = @(); keyFilesNote = 'Key files are candidate evidence.' }
            )
        }

        $script:OutPath = Join-Path $TestDrive 'proposed-scope.json'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:OutPath -Force -ErrorAction SilentlyContinue
    }

    Context 'a clear story' {
        It 'resolves to a narrow, evidence-linked scope' {
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate)

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Status | Should -Be 'Valid'
            $result.Details.ScopeStatus | Should -Be 'resolved'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $artifact.status | Should -Be 'resolved'
            $artifact.storyId | Should -Be '123456'
            $artifact.resolver | Should -Be 'ei-scope-resolver'
            @($artifact.proposedFiles).Count | Should -Be 1
            $artifact.proposedFiles[0].path | Should -Be 'src/Ei.Graphics.Rendering/LabelPlacement.cs'
            @($artifact.proposedModules).Count | Should -Be 1
            @($artifact.relatedTests).Count | Should -Be 1
            @($artifact.unresolved).Count | Should -Be 0
        }
    }

    Context 'a missing domain context' {
        It 'never resolves without domain context' {
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate)

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'needs-review'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-CONTEXT-MISSING'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $artifact.domainContext | Should -BeNullOrEmpty
        }

        It 'rejects a domain context path that was supplied but does not exist' {
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate)

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath (Join-Path $TestDrive 'absent.json') -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Status | Should -Be 'Invalid'
            $result.Errors[0] | Should -BeLike 'EISR-INPUT-INVALID*'
            Test-Path -LiteralPath $script:OutPath | Should -BeFalse
        }
    }

    Context 'cross-area dependencies' {
        It 'records an unresolved dependency without pulling it into scope' {
            $candidate = script:New-Candidate @{
                dependencies = @(
                    @{ name = 'SignalRouting'; kind = 'cross-area'; resolution = 'unresolved'; detail = 'Routing owns the anchor points.' }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'needs-review'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-DEPENDENCY-UNRESOLVED'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($artifact.dependencies).Count | Should -Be 1
            @($artifact.proposedFiles | Where-Object { $_.path -like '*SignalRouting*' }).Count | Should -Be 0
        }

        It 'drops a proposed file that belongs to an unresolved dependency' {
            $candidate = script:New-Candidate @{
                dependencies  = @(
                    @{ name = 'SignalRouting'; kind = 'cross-area'; resolution = 'unresolved'; detail = 'Routing owns the anchor points.' }
                )
                proposedFiles = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @('Resolve'); evidence = @('E1'); confidence = 0.86 },
                    @{ path = 'src/SignalRouting/Router.cs'; changeIntent = 'modify'; symbols = @(); evidence = @('E1'); confidence = 0.5 }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'blocked'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-DEPENDENCY-ABSORBED'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($artifact.proposedFiles).Count | Should -Be 1
            @($artifact.excluded | Where-Object { $_.target -eq 'src/SignalRouting/Router.cs' }).Count | Should -Be 1
        }
    }

    Context 'the scope refuses to broaden' {
        It 'flags a scope that exceeds the breadth limit' {
            $files = @()
            for ($i = 1; $i -le 13; $i++) {
                $files += @{ path = "src/Ei.Graphics.Rendering/File$i.cs"; changeIntent = 'modify'; symbols = @(); evidence = @('E2'); confidence = 0.8 }
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate @{ proposedFiles = $files })

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'needs-review'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-SCOPE-BREADTH'
        }

        It 'drops a path that cites no evidence instead of including it' {
            $candidate = script:New-Candidate @{
                proposedFiles = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @('Resolve'); evidence = @('E2'); confidence = 0.86 },
                    @{ path = 'src/Ei.Graphics.Rendering/Guessed.cs'; changeIntent = 'modify'; symbols = @(); evidence = @(); confidence = 0.3 }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'blocked'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-EVIDENCE-MISSING'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($artifact.proposedFiles | Where-Object { $_.path -eq 'src/Ei.Graphics.Rendering/Guessed.cs' }).Count | Should -Be 0
            @($artifact.excluded | Where-Object { $_.target -eq 'src/Ei.Graphics.Rendering/Guessed.cs' }).Count | Should -Be 1
        }

        It 'drops a path that cites an evidence id the artifact does not contain' {
            $candidate = script:New-Candidate @{
                proposedFiles = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @('Resolve'); evidence = @('E9'); confidence = 0.86 }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 0
            $result.Details.ScopeStatus | Should -Be 'blocked'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-EVIDENCE-MISSING'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-EMPTY-SCOPE'
        }

        It 'drops a path inside a declared protected area' {
            $candidate = script:New-Candidate @{
                protectedAreas = @(
                    @{ path = 'src/Ei.Graphics.Contracts'; reason = 'Public contract surface.' }
                )
                proposedFiles  = @(
                    @{ path = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; changeIntent = 'modify'; symbols = @(); evidence = @('E2'); confidence = 0.8 },
                    @{ path = 'src/Ei.Graphics.Contracts/ILabel.cs'; changeIntent = 'modify'; symbols = @(); evidence = @('E2'); confidence = 0.8 }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $result.Details.ScopeStatus | Should -Be 'blocked'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-PROTECTED-OVERLAP'

            $artifact = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($artifact.proposedFiles).Count | Should -Be 1
        }

        It 'flags a path that cannot be verified in the repository' {
            $candidate = script:New-Candidate @{
                proposedFiles = @(
                    @{ path = 'src/Ei.Graphics.Rendering/DoesNotExist.cs'; changeIntent = 'modify'; symbols = @(); evidence = @('E2'); confidence = 0.9 }
                )
            }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $result.Details.ScopeStatus | Should -Be 'needs-review'
            $result.Details.UnresolvedCodes | Should -Contain 'EISR-PATH-UNVERIFIED'
        }
    }

    Context 'the artifact contract' {
        It 'produces an artifact that validates against the published schema' {
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate)

            & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $content = Get-Content -LiteralPath $script:OutPath -Raw
            $schema = Get-Content -LiteralPath $script:SchemaPath -Raw
            Test-Json -Json $content -Schema $schema | Should -BeTrue
        }

        It 'rejects a candidate with no rationale and writes nothing' {
            $candidate = script:New-Candidate
            $candidate.Remove('rationale')
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') $candidate

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EISR-INPUT-INVALID*'
            Test-Path -LiteralPath $script:OutPath | Should -BeFalse
        }

        It 'rejects a story input with an unusable story id' {
            $storyPath = script:New-JsonFile (Join-Path $TestDrive 'bad-story.json') @{ storyId = '../escape'; storyRef = $null; summary = 'x' }
            $candidatePath = script:New-JsonFile (Join-Path $TestDrive 'candidate.json') (script:New-Candidate)

            $result = & $script:ScriptPath -StoryInputPath $storyPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EISR-INPUT-INVALID*'
        }

        It 'rejects malformed candidate JSON' {
            $candidatePath = Join-Path $TestDrive 'candidate.json'
            Set-Content -LiteralPath $candidatePath -Value '{ not json'

            $result = & $script:ScriptPath -StoryInputPath $script:StoryPath -CandidatePath $candidatePath `
                -DomainContextPath $script:ContextPath -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $LASTEXITCODE | Should -Be 1
            $result.Errors[0] | Should -BeLike 'EISR-INPUT-INVALID*'
        }
    }
}
