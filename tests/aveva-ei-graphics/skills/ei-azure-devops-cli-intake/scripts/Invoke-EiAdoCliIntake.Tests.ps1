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
        $result.workItemContext.authSource | Should -Be 'cli-mock-json'
    }

    It 'records the fixed organization and project rather than the ones named in the url' {
        $mock = '{ "fields": { "System.Title": "Symbol extents boundary" } }'

        $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_workitems/edit/4913134' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.workItemContext.organization | Should -Be 'AVEVA-VSTS'
        $result.workItemContext.project | Should -Be 'Dabacon Products'
    }

    It 'does not read a reserved url segment such as _workitems as the project' {
        $mock = '{ "fields": { "System.Title": "Symbol extents boundary" } }'

        $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/AVEVA-VSTS/_workitems/edit/4983245' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.workItemContext.workItemId | Should -Be '4983245'
        $result.workItemContext.project | Should -Be 'Dabacon Products'
    }

    It 'resolves the id from a markdown link surrounded by prose' {
        $mock = '{ "fields": { "System.Title": "Missing headers and terminals" } }'
        $pasted = 'Please pick up [Bug 4983245 SR350 - EPT Termination Drawing Missing Headers and Terminals in Old Workflow](https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245) next.'

        $output = & $script:ScriptPath -WorkItemUrl $pasted -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.workItemContext.workItemId | Should -Be '4983245'
        $result.workItemContext.workItemUrl | Should -Be 'https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245'
    }

    It 'returns failed when URL does not contain work item id' {
        $output = & $script:ScriptPath -WorkItemUrl 'https://dev.azure.com/ei-org/ei-project/_boards/board/t/team/Stories' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'failed'
        $result.reason | Should -Be 'missing-work-item-id-in-url'
    }

    It 'resolves work item id from a boards URL with workitem query parameter' {
        $mock = '{ "fields": { "System.Title": "Stop termination labels overlapping" } }'
        $boardsUrl = 'https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_boards/board/t/Engineering%20and%20Schematics%20-%20EI%20Graphics/Stories?workitem=3408091'
        $output = & $script:ScriptPath -WorkItemUrl $boardsUrl -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'retrieved'
        $result.workItemContext.workItemId | Should -Be '3408091'
        $result.workItemContext.organization | Should -Be 'AVEVA-VSTS'
        $result.workItemContext.project | Should -Be 'Dabacon Products'
    }

    It 'resolves the work item id from a pasted markdown link whose href is not an ADO url' {
        $mock = @'
{
    "fields": {
        "System.Title": "Insertion of tstrip header symbol below previous symbol is not observing the symbol extents boundary"
    }
}
'@

        $pasted = '[Bug 4965976 SR205 - Insertion of tstrip header symbol below previous symbol is not observing the symbol extents boundary](vscode-file://vscode-app/c:/Program%20Files/Microsoft%20VS%20Code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)'
        $output = & $script:ScriptPath -WorkItemUrl $pasted -Organization 'ei-org' -Project 'ei-project' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'retrieved'
        $result.workItemContext.workItemId | Should -Be '4965976'
        $result.workItemContext.workItemUrl | Should -BeNullOrEmpty
    }

    It 'resolves the work item id from a plain reference title' {
        $mock = '{ "fields": { "System.Title": "Symbol extents boundary" } }'

        $output = & $script:ScriptPath -WorkItemId 'Bug 4965976 SR205 - symbol extents boundary' -Organization 'ei-org' -Project 'ei-project' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'retrieved'
        $result.workItemContext.workItemId | Should -Be '4965976'
    }

    It 'uses the ADO url when a markdown link points at the work item' {
        $mock = '{ "fields": { "System.Title": "Symbol extents boundary" } }'

        $pasted = '[Bug 4965976](https://dev.azure.com/ei-org/ei-project/_workitems/edit/4965976)'
        $output = & $script:ScriptPath -WorkItemUrl $pasted -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.workItemContext.workItemId | Should -Be '4965976'
        $result.workItemContext.workItemUrl | Should -Be 'https://dev.azure.com/ei-org/ei-project/_workitems/edit/4965976'
    }

    It 'returns failed when a pasted reference carries no work item id' {
        $output = & $script:ScriptPath -WorkItemUrl '[Insertion of tstrip header symbol SR205](vscode-file://vscode-app/workbench.html)' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'failed'
        $result.reason | Should -Be 'missing-work-item-id-in-reference'
    }

    It 'returns failed for a bare url that is neither an ADO address nor carries a label' {
        $output = & $script:ScriptPath -WorkItemUrl 'https://example.com/not-an-ado-url' -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'failed'
        $result.reason | Should -Be 'unsupported-work-item-url-host'
    }

    It 'includes acceptance criteria in the plain-text description' {
        $mock = '{ "fields": { "System.Title": "Review of existing termination diagram settings", "System.Description": "<div>Parent context.</div>", "Microsoft.VSTS.Common.AcceptanceCriteria": "<div><p>Controlled via the tstrip header symbol</p></div>" } }'

        $output = & $script:ScriptPath -WorkItemId '3774939' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.descriptionText | Should -BeLike '*Parent context.*'
        $result.descriptionText | Should -BeLike '*Controlled via the tstrip header symbol*'
    }

    It 'collects images embedded in acceptance criteria' {
        $mock = '{ "fields": { "System.Title": "Termination diagram settings", "Microsoft.VSTS.Common.AcceptanceCriteria": "<div><img src=\"https://dev.azure.com/AVEVA-VSTS/3c9dc12c/_apis/wit/attachments/5da955e2?fileName=image.png\" alt=Image></div>" } }'

        $output = & $script:ScriptPath -WorkItemId '3774939' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        @($result.attachmentUrls).Count | Should -Be 1
        @($result.attachmentUrls)[0].url | Should -Be 'https://dev.azure.com/AVEVA-VSTS/3c9dc12c/_apis/wit/attachments/5da955e2?fileName=image.png'
    }

    It 'decodes html-encoded attachment urls so the download query survives' {
        $mock = '{ "fields": { "System.Title": "Termination diagram settings", "Microsoft.VSTS.Common.AcceptanceCriteria": "<div><img src=\"https://dev.azure.com/AVEVA-VSTS/_apis/wit/attachments/5da955e2?fileName=image.png&amp;download=true\"></div>" } }'

        $output = & $script:ScriptPath -WorkItemId '3774939' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        @($result.attachmentUrls)[0].url | Should -Be 'https://dev.azure.com/AVEVA-VSTS/_apis/wit/attachments/5da955e2?fileName=image.png&download=true'
    }

    It 'deduplicates an image that appears in more than one content field' {
        $mock = '{ "fields": { "System.Title": "Termination diagram settings", "System.Description": "<img src=\"https://dev.azure.com/AVEVA-VSTS/_apis/wit/attachments/abc?fileName=image.png\">", "Microsoft.VSTS.Common.AcceptanceCriteria": "<img src=\"https://dev.azure.com/AVEVA-VSTS/_apis/wit/attachments/abc?fileName=image.png\">" } }'

        $output = & $script:ScriptPath -WorkItemId '3774939' -CliWorkItemJson $mock -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        @($result.attachmentUrls).Count | Should -Be 1
    }
}
