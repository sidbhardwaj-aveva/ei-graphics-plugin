#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiBugReproducer' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-bug-reproducer' 'scripts' 'Invoke-EiBugReproducer.ps1'
    }

    It 'returns blocked when neither bugId nor descriptionText is provided' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
    }

    It 'returns ready when description text matches a known EI term' {
        $output = & $script:ScriptPath -DescriptionText 'Customer reports cable termination issue in E3D' -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'ready'
        ($result.affectedAreas -contains 'CableService') | Should -BeTrue
        $result.runtimeRequired | Should -BeTrue
    }

    It 'returns needs-manual-review when only bugId is provided without retrieved description text' {
        $output = & $script:ScriptPath -BugId '4913134' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        $result.bugContext.retrieval.status | Should -Be 'failed'
    }

        It 'returns ready when bugId retrieval succeeds from supplied ADO work item payload' {
                $mock = @'
{
    "fields": {
        "System.Title": "Distribution board cable issue",
        "System.Description": "Cable termination fails in E3D"
    }
}
'@

                $output = & $script:ScriptPath -BugId '4913134' -AdoWorkItemJson $mock -Json
                $LASTEXITCODE | Should -Be 0
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'ready'
                $result.bugContext.retrieval.status | Should -Be 'retrieved'
                ($result.affectedAreas -contains 'CableService') | Should -BeTrue
        }

            It 'resolves work item URL and returns ready when ADO payload is supplied' {
                $mock = @'
{
    "fields": {
        "System.Title": "Loop drawing issue",
        "System.Description": "canvas drawing not visible from control loop"
    }
}
'@

                $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_workitems/edit/4913134' -AdoWorkItemJson $mock -Json
                $LASTEXITCODE | Should -Be 0
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'ready'
                $result.bugContext.bugId | Should -Be '4913134'
                $result.bugContext.organization | Should -Be 'AVEVA-VSTS'
                $result.bugContext.project | Should -Be 'Dabacon Products'
                $result.bugContext.workItemUrl | Should -Be 'https://dev.azure.com/ei-org/ei-project/_workitems/edit/4913134'
                $result.bugContext.retrieval.authSource | Should -Be 'cli-mock-json'
            }

            It 'returns blocked when only work item URL is provided without a work item id' {
                $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_boards/board/t/team/Stories' -Json
                $LASTEXITCODE | Should -Be 1
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'blocked'
                ($result.reproductionHints -join ' ') | Should -Match 'missing-work-item-id-in-url'
            }

        It 'returns needs-manual-review when bugId is provided but org/project is missing for live retrieval' {
                $output = & $script:ScriptPath -BugId '4913134' -Organization 'org-only' -Json
                $LASTEXITCODE | Should -Be 1
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'needs-manual-review'
                $result.bugContext.retrieval.reason | Should -Be 'missing-organization-or-project'
            $result.confidence | Should -Be 0.2
            $result.bugContext.retrieval.isTransient | Should -BeFalse
        }

        It 'returns needs-manual-review when bugId is invalid for ADO lookup' {
            $output = & $script:ScriptPath -BugId 'BUG-4913134' -Organization 'ei-org' -Project 'ei-project' -AccessToken 'token' -Json
            $LASTEXITCODE | Should -Be 1
            $result = $output | ConvertFrom-Json
            $result.status | Should -Be 'needs-manual-review'
            $result.bugContext.retrieval.reason | Should -Be 'invalid-bug-id'
            $result.confidence | Should -Be 0.2
            $result.bugContext.retrieval.isTransient | Should -BeFalse
        }

        It 'resolves organization and project from pipeline environment when not supplied as parameters' {
            $originalCollection = $env:SYSTEM_COLLECTIONURI
            $originalTeamProject = $env:SYSTEM_TEAMPROJECT
            try {
                $env:SYSTEM_COLLECTIONURI = 'https://dev.azure.com/ei-org/'
                $env:SYSTEM_TEAMPROJECT = 'ei-project'

                $output = & $script:ScriptPath -BugId '4913134' -Json
                $LASTEXITCODE | Should -Be 1
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'needs-manual-review'
                $result.bugContext.retrieval.reason | Should -Be 'missing-auth-token'
                $result.bugContext.organization | Should -Be 'ei-org'
                $result.bugContext.project | Should -Be 'ei-project'
                $result.confidence | Should -Be 0.2
                $result.bugContext.retrieval.isTransient | Should -BeFalse
            }
            finally {
                $env:SYSTEM_COLLECTIONURI = $originalCollection
                $env:SYSTEM_TEAMPROJECT = $originalTeamProject
            }
        }

        It 'classifies unavailable live retrieval with reason-specific transient and confidence behavior' {
            $originalCollection = $env:SYSTEM_COLLECTIONURI
            $originalTeamProject = $env:SYSTEM_TEAMPROJECT
            $originalPat = $env:AZURE_DEVOPS_EXT_PAT
            try {
                $env:SYSTEM_COLLECTIONURI = 'https://dev.azure.com/ei-org/'
                $env:SYSTEM_TEAMPROJECT = 'ei-project'
                $env:AZURE_DEVOPS_EXT_PAT = 'dummy-token'

                $output = & $script:ScriptPath -BugId '4913134' -Keywords @('cable') -Json
                $LASTEXITCODE | Should -Be 1
                $result = $output | ConvertFrom-Json
                $result.status | Should -Be 'needs-manual-review'
                @('ado-auth-failed', 'ado-request-failed', 'ado-throttled', 'ado-server-error', 'ado-work-item-not-found') -contains $result.bugContext.retrieval.reason | Should -BeTrue

                if ($result.bugContext.retrieval.reason -eq 'ado-auth-failed') {
                    $result.bugContext.retrieval.isTransient | Should -BeFalse
                    $result.confidence | Should -Be 0.2
                }
                elseif ($result.bugContext.retrieval.reason -eq 'ado-work-item-not-found') {
                    $result.bugContext.retrieval.isTransient | Should -BeFalse
                    $result.confidence | Should -Be 0.3
                }
                else {
                    $result.bugContext.retrieval.isTransient | Should -BeTrue
                    $result.confidence | Should -BeLessOrEqual 0.25
                }
            }
            finally {
                $env:SYSTEM_COLLECTIONURI = $originalCollection
                $env:SYSTEM_TEAMPROJECT = $originalTeamProject
                $env:AZURE_DEVOPS_EXT_PAT = $originalPat
            }
        }

    It 'returns needs-manual-review when no EI vocabulary terms are recognized' {
        $output = & $script:ScriptPath -DescriptionText 'Unexpected issue in a generic subsystem' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        $result.affectedAreas | Should -BeNullOrEmpty
    }
}
