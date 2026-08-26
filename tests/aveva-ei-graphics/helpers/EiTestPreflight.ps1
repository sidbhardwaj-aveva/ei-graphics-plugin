#!/usr/bin/env pwsh
<#
.SYNOPSIS
Shared test harness helper: supply the preflight gate evidence a real bootstrap would have written.

.DESCRIPTION
`preflight` owns the `prerequisites` artifact, so it cannot be completed by hand. Harnesses that
only need to reach a later stage therefore write the same evidence `Start-EiWorkflowRun.ps1` writes,
through the same schema-validating writer, rather than being allowed to skip the gate.
#>

function script:New-EiTestPreflightEvidence {
    param(
        [Parameter(Mandatory)][string]$StateDir,
        [AllowEmptyString()][string]$StoryId = '',
        [string]$WorkflowPath = 'IMPLEMENT',
        [string]$Phase = 'A',
        [ValidateSet('pass', 'block')][string]$Verdict = 'pass'
    )

    if ([string]::IsNullOrWhiteSpace($StoryId)) { $StoryId = Split-Path -Path $StateDir -Leaf }

    $writePath = Join-Path $PSScriptRoot '..' '..' '..' 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts' 'Write-EiWorkflowArtifact.ps1'

    $evidence = [ordered]@{
        schemaVersion     = '1.0.0'
        gate              = 'prerequisites'
        stage             = 'preflight'
        storyId           = $StoryId
        workflowPath      = $WorkflowPath
        phase             = $Phase
        generatedAt       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        verdict           = $Verdict
        pwshVersion       = $PSVersionTable.PSVersion.ToString()
        repositoryRoot    = $StateDir
        insideWorkTree    = $true
        searchRoots       = @()
        found             = @()
        missingRequired   = @()
        missingLaterPhase = @()
        errors            = @()
        warnings          = @()
    }

    $written = & $writePath -StateDir $StateDir -Name 'prerequisites' -Content ($evidence | ConvertTo-Json -Depth 10) -Json | ConvertFrom-Json
    if ($written.Status -ne 'Valid') {
        throw "Test preflight evidence could not be written: $(@($written.Errors) -join '; ')"
    }
}
