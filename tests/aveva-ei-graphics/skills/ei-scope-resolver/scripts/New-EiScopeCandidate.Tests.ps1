#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'New-EiScopeCandidate' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-scope-resolver' 'scripts' 'New-EiScopeCandidate.ps1'

        function script:New-AdoArtifact {
            param([hashtable]$Override = @{})
            $doc = @{
                storyId     = '123456'
                storyRef    = 'https://dev.azure.com/example/_workitems/edit/123456'
                summary     = 'Stop termination labels overlapping when they share a cable point.'
                description = 'When two termination arrangements share a cable connection point, their labels overlap in the drawing output. The label placement rule must avoid overlap.'
            }
            foreach ($key in $Override.Keys) { $doc[$key] = $Override[$key] }
            $doc | ConvertTo-Json -Depth 5
        }

        function script:New-DomainContextArtifact {
            param([array]$KeyFiles = @())
            @{
                source       = 'ei-domain-skill-registry'
                domainSkills = @(
                    @{
                        domainId    = 'termination-drawing'
                        displayName = 'Termination Drawing'
                        summary     = 'Generates termination drawings from LOC model data.'
                        keyFiles    = $KeyFiles
                        keyFilesNote = 'Key files are candidate evidence, not automatic scope.'
                    }
                )
            } | ConvertTo-Json -Depth 10
        }
    }

    BeforeEach {
        # Minimal fake repository with a source file and a test file.
        $script:Repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'src' 'Ei.Graphics.Rendering') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Repo 'tests' 'Ei.Graphics.Rendering.Tests') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Repo 'src' 'Ei.Graphics.Rendering' 'LabelPlacement.cs')              -Value '// placement'
        Set-Content -LiteralPath (Join-Path $script:Repo 'tests' 'Ei.Graphics.Rendering.Tests' 'LabelPlacementTests.cs') -Value '// tests'

        $script:AdoPath     = Join-Path $TestDrive 'ado.json'
        $script:ContextPath = Join-Path $TestDrive 'domain-context.json'
        $script:OutPath     = Join-Path $TestDrive 'candidate.json'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── Success cases ─────────────────────────────────────────────────────────

    Context 'ADO and domain context with key files' {
        It 'writes a valid candidate.json with evidence from story and key files' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; purpose = 'label placement rule' }
            ))

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            $output.Status | Should -Be 'Valid'

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $candidate.confidence | Should -BeGreaterOrEqual 0
            $candidate.confidence | Should -BeLessOrEqual 1
            $candidate.rationale  | Should -Not -BeNullOrEmpty
            @($candidate.evidence).Count | Should -BeGreaterThan 0
        }

        It 'includes a story evidence entry with kind "story"' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $storyEvidence = @($candidate.evidence | Where-Object { $_.kind -eq 'story' })
            $storyEvidence.Count | Should -BeGreaterThan 0
        }

        It 'adds domain-skill key files as evidence with kind "domain-skill-key-file"' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; purpose = 'placement rule' }
            ))

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $keyFileEvidence = @($candidate.evidence | Where-Object { $_.kind -eq 'domain-skill-key-file' })
            $keyFileEvidence.Count | Should -Be 1
            $keyFileEvidence[0].value | Should -Be 'src/Ei.Graphics.Rendering/LabelPlacement.cs'
        }

        It 'promotes a key file that exists in the repository to proposedFiles' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; purpose = 'placement rule' }
            ))

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($candidate.proposedFiles).Count | Should -BeGreaterThan 0
            @($candidate.proposedFiles | ForEach-Object { $_.path }) | Should -Contain 'src/Ei.Graphics.Rendering/LabelPlacement.cs'
        }

        It 'does NOT promote a key file that does not exist in the repository' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/NonExistent.cs'; purpose = 'does not exist' }
            ))

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($candidate.proposedFiles).Count | Should -Be 0
        }

        It 'routes a key file under a tests folder to relatedTests not proposedFiles' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs'; purpose = 'tests for placement' }
            ))

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            @($candidate.proposedFiles).Count | Should -Be 0
            @($candidate.relatedTests).Count  | Should -Be 1
            $candidate.relatedTests[0].target | Should -Be 'tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs'
        }

        It 'sets confidence to 0.5 when domain key file evidence is present' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; purpose = 'placement rule' }
            ))

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $candidate.confidence | Should -Be 0.5
        }

        It 'sets confidence to 0.3 when only story text evidence is present (no key files)' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @())

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $candidate.confidence | Should -Be 0.3
        }

        It 'reports evidence count and proposedFiles count in Details' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact -KeyFiles @(
                @{ file = 'src/Ei.Graphics.Rendering/LabelPlacement.cs'; purpose = 'placement rule' }
            ))

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json

            $output.Details.EvidenceCount      | Should -BeGreaterThan 0
            $output.Details.ProposedFilesCount | Should -BeGreaterOrEqual 0
        }
    }

    # ── Failure cases ──────────────────────────────────────────────────────────

    Context 'missing inputs' {
        It 'fails with EISC-NO-OUTPUT when neither StateDir nor OutputPath is provided' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Status     | Should -Be 'Invalid'
            $output.Errors[0]  | Should -BeLike 'EISC-NO-OUTPUT*'
        }

        It 'fails with EISC-ADO-MISSING when ado.json does not exist' {
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            $output = & $script:ScriptPath `
                -AdoPath (Join-Path $TestDrive 'no-ado.json') `
                -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Errors[0] | Should -BeLike 'EISC-ADO-MISSING*'
        }

        It 'fails with EISC-ADO-INVALID when ado.json is missing storyId' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact -Override @{ storyId = '' })
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Errors[0] | Should -BeLike 'EISC-ADO-INVALID*'
        }

        It 'fails with EISC-ADO-INVALID when ado.json is not valid JSON' {
            Set-Content -LiteralPath $script:AdoPath     -Value 'not-json-{'
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Errors[0] | Should -BeLike 'EISC-ADO-INVALID*'
        }

        It 'fails with EISC-DOMAIN-MISSING when domain-context.json does not exist' {
            Set-Content -LiteralPath $script:AdoPath -Value (script:New-AdoArtifact)

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath `
                -DomainContextPath (Join-Path $TestDrive 'no-context.json') `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Errors[0] | Should -BeLike 'EISC-DOMAIN-MISSING*'
        }

        It 'fails with EISC-STATE-MISSING when StateDir does not exist' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            $output = & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -StateDir (Join-Path $TestDrive 'no-such-dir') -Json | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 1
            $output.Errors[0] | Should -BeLike 'EISC-STATE-MISSING*'
        }
    }

    # ── Candidate validity for downstream consumers ────────────────────────────

    Context 'output shape' {
        It 'always includes all optional arrays (even when empty)' {
            Set-Content -LiteralPath $script:AdoPath     -Value (script:New-AdoArtifact)
            Set-Content -LiteralPath $script:ContextPath -Value (script:New-DomainContextArtifact)

            & $script:ScriptPath `
                -AdoPath $script:AdoPath -DomainContextPath $script:ContextPath `
                -RepositoryRoot $script:Repo -OutputPath $script:OutPath -Json | Out-Null

            $candidate = Get-Content -LiteralPath $script:OutPath -Raw | ConvertFrom-Json
            $candidate.PSObject.Properties['proposedModules'] | Should -Not -BeNull
            $candidate.PSObject.Properties['relatedTests']    | Should -Not -BeNull
            $candidate.PSObject.Properties['protectedAreas']  | Should -Not -BeNull
            $candidate.PSObject.Properties['dependencies']    | Should -Not -BeNull
            $candidate.PSObject.Properties['excluded']        | Should -Not -BeNull
            $candidate.PSObject.Properties['risks']           | Should -Not -BeNull
            $candidate.PSObject.Properties['unresolved']      | Should -Not -BeNull
        }
    }
}
