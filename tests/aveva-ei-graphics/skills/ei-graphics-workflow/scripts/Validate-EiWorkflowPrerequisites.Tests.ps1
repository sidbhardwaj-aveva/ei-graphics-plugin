#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Validate-EiWorkflowPrerequisites' -Tag 'Unit' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
        $script:ScriptPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'Validate-EiWorkflowPrerequisites.ps1'
        $script:ManifestPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'references' 'required-capabilities.json'
    }

    It 'passes at Phase A when only the local state skill is required' {
        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase A -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Found | Should -Contain 'aveva-ei-graphics:ei-workflow-state'
        @($result.Details.MissingLaterPhase).Count | Should -BeGreaterThan 0
    }

    It 'fails closed with a marketplace install message when a required plugin is absent' {
        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase D -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 1

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Invalid'
        ($result.Errors -join "`n") | Should -BeLike '*aveva-rnd is not installed. Install it from the marketplace and retry.*'
        ($result.Errors -join "`n") | Should -BeLike '*aveva-core is not installed*'
    }

    It 'passes at Phase D when every required capability resolves from a search root' {
        $fakeRoot = Join-Path $TestDrive 'plugins'
        foreach ($capability in (Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json).capabilities) {
            $skillDir = Join-Path $fakeRoot (Join-Path $capability.plugin (Join-Path 'skills' $capability.skill))
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value '# stub'
        }

        $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase D -PluginSearchRoot $fakeRoot -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Found | Should -Contain 'aveva-rnd:code-review'
        $result.Details.Found | Should -Contain 'aveva-core:create-audit'
        @($result.Details.MissingRequired).Count | Should -Be 0
    }

    It 'blocks when the required-capabilities manifest is missing' {
        $output = & $script:ScriptPath -RequiredCapabilitiesPath (Join-Path $TestDrive 'no-manifest.json') -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-CAPABILITIES-MISSING*'
    }

    It 'blocks from Phase C when the repository root is not a git work tree' {
        $output = & $script:ScriptPath -RepositoryRoot $TestDrive -Phase C -NoDefaultSearchRoots -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors -join "`n" | Should -BeLike '*EIWF-GIT-NO-REPO*'
    }

    Context 'candidate.json gate (Phase B+ with StateDir)' {
        It 'fails with EIWF-CANDIDATE-MISSING when candidate.json is absent from StateDir' {
            $stateDir = Join-Path $TestDrive 'state'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase B `
                -NoDefaultSearchRoots -StateDir $stateDir -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors -join "`n" | Should -BeLike '*EIWF-CANDIDATE-MISSING*'
        }

        It 'fails with EIWF-CANDIDATE-INVALID when candidate.json is not valid JSON' {
            $stateDir = Join-Path $TestDrive 'state-bad-json'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stateDir 'candidate.json') -Value 'not-json-{' -Encoding utf8

            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase B `
                -NoDefaultSearchRoots -StateDir $stateDir -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors -join "`n" | Should -BeLike '*EIWF-CANDIDATE-INVALID*'
        }

        It 'fails with EIWF-CANDIDATE-INVALID when candidate.json is missing required fields' {
            $stateDir = Join-Path $TestDrive 'state-bad-fields'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stateDir 'candidate.json') `
                -Value '{ "confidence": 0.5 }' -Encoding utf8

            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase B `
                -NoDefaultSearchRoots -StateDir $stateDir -Json
            $LASTEXITCODE | Should -Be 1
            ($output | ConvertFrom-Json).Errors -join "`n" | Should -BeLike '*EIWF-CANDIDATE-INVALID*'
        }

        It 'passes at Phase B when a structurally valid candidate.json is present' {
            $stateDir = Join-Path $TestDrive 'state-valid'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            $validCandidate = @{
                confidence = 0.5
                rationale  = 'Auto-generated from story text.'
                evidence   = @(
                    @{ id = 'E1'; kind = 'story'; value = 'labels overlap'; note = $null }
                )
                proposedFiles   = @()
                proposedModules = @()
                relatedTests    = @()
                protectedAreas  = @()
                dependencies    = @()
                excluded        = @()
                risks           = @()
                unresolved      = @()
            }
            Set-Content -LiteralPath (Join-Path $stateDir 'candidate.json') `
                -Value ($validCandidate | ConvertTo-Json -Depth 10) -Encoding utf8

            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase B `
                -NoDefaultSearchRoots -StateDir $stateDir -Json
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).Status | Should -Be 'Valid'
        }

        It 'skips the candidate check at Phase A even when StateDir is provided' {
            $stateDir = Join-Path $TestDrive 'state-phase-a'
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
            # No candidate.json written — should not matter at Phase A.

            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase A `
                -NoDefaultSearchRoots -StateDir $stateDir -Json
            $LASTEXITCODE | Should -Be 0
            ($output | ConvertFrom-Json).Status | Should -Be 'Valid'
        }

        It 'skips the candidate check when StateDir is not provided even at Phase B' {
            $output = & $script:ScriptPath -RepositoryRoot $script:RepoRoot -Phase B `
                -NoDefaultSearchRoots -Json
            # The test is valid if exit code 0: the candidate check is off when no StateDir.
            # (There may be a PS-version or git warning, but no CANDIDATE error.)
            $errors = ($output | ConvertFrom-Json).Errors
            @($errors | Where-Object { $_ -like '*EIWF-CANDIDATE*' }).Count | Should -Be 0
        }
    }
}
