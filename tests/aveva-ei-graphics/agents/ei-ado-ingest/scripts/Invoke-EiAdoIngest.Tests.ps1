#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiAdoIngest' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'agents' 'ei-ado-ingest' 'scripts' 'Invoke-EiAdoIngest.ps1'
    }

    It 'returns resolved with normalized context when URL and mock payload are provided' {
        $mockJson = @'
{
  "id": 468178,
  "fields": {
    "System.Title": "Cable route mismatch",
    "System.Description": "<p>Cable path is inconsistent in panel layout.</p>",
    "Microsoft.VSTS.TCM.ReproSteps": "Open model and inspect route."
  }
}
'@

        $output = & $script:ScriptPath `
            -WorkItemUrl 'https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/468178' `
            -CliWorkItemJson $mockJson `
            -Json

        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'resolved'
        $result.context.bugId | Should -Be '468178'
        $result.context.organization | Should -Be 'AVEVA-VSTS'
        $result.context.project | Should -Be 'Dabacon Products'
        $result.retrieval.reason | Should -Be 'mock-json'
        $result.descriptionText | Should -Match 'Cable route mismatch'
    }

    It 'returns blocked when no URL or bug id is provided' {
        $output = & $script:ScriptPath -Json

        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        $result.retrieval.reason | Should -Be 'missing-work-item-url-or-id'
    }

    It 'returns needs-manual-review when work item id is invalid' {
        $output = & $script:ScriptPath -BugId 'abc' -Organization 'AVEVA-VSTS' -Project 'Dabacon Products' -Json

        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        $result.retrieval.reason | Should -Be 'invalid-work-item-id'
    }
}
