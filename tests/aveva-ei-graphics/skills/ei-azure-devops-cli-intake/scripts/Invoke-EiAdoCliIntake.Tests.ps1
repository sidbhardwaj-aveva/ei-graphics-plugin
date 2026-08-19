#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiAdoCliIntake' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoCliIntake.ps1'
    }

    It 'returns blocked when neither workItemUrl nor workItemId is provided' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        $result.reason | Should -Be 'missing-work-item-url-or-id'
    }

    It 'returns retrieved when URL and mock payload are provided' {
        $mock = @'
{
    "fields": {
        "System.Title": "Loop drawing issue",
        "System.Description": "canvas drawing not visible from control loop"
    }
}
'@

        $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_workitems/edit/4913134' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'retrieved'
        $result.workItemContext.workItemId | Should -Be '4913134'
        $result.workItemContext.organization | Should -Be 'ei-org'
        $result.workItemContext.project | Should -Be 'ei-project'
        $result.workItemContext.authSource | Should -Be 'cli-mock-json'
    }

    It 'returns failed when URL does not contain work item id' {
        $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_boards/board/t/team/Stories' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'failed'
        $result.reason | Should -Be 'missing-work-item-id-in-url'
    }
}
