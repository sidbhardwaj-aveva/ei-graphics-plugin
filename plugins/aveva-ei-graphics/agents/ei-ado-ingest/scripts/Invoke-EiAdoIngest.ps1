[CmdletBinding()]
param(
    [string]$WorkItemUrl = '',
    [string]$BugId = '',
    [string]$Organization = '',
    [string]$Project = '',
    [string]$CliWorkItemJson = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pluginRoot = Join-Path $PSScriptRoot '..' '..' '..'
$intakeScript = Join-Path $pluginRoot 'skills' 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoCliIntake.ps1'

if (-not (Test-Path -LiteralPath $intakeScript -PathType Leaf)) {
    throw "Required script not found: $intakeScript"
}

$intakeOutput = & $intakeScript `
    -WorkItemUrl $WorkItemUrl `
    -WorkItemId $BugId `
    -Organization $Organization `
    -Project $Project `
    -CliWorkItemJson $CliWorkItemJson `
    -Json

$intakeResult = $null
if (-not [string]::IsNullOrWhiteSpace(($intakeOutput -join ''))) {
    $intakeResult = $intakeOutput | ConvertFrom-Json -Depth 20
}

if ($null -eq $intakeResult) {
    throw 'ADO intake script returned empty output.'
}

$status = 'needs-manual-review'
if ($intakeResult.status -eq 'retrieved') {
    $status = 'resolved'
}
elseif ($intakeResult.status -eq 'blocked') {
    $status = 'blocked'
}

$reason = [string]$intakeResult.reason
$confidence = if ($status -eq 'resolved') { 0.95 } elseif ($status -eq 'blocked') { 0.0 } else { 0.3 }
$context = $intakeResult.workItemContext
$workItemId = if ($null -ne $context) { [string]$context.workItemId } else { '' }

$nextAction = switch ($status) {
    'resolved' { 'Continue with diagnosis workflow using normalized ADO context.' }
    'blocked' { 'Provide a work item URL or bug ID to continue.' }
    default { 'Provide missing context or manual bug description, then retry intake.' }
}

$result = [PSCustomObject]@{
    status = $status
    retrieval = [PSCustomObject]@{
        status = [string]$intakeResult.status
        reason = $reason
        authSource = if ($null -ne $context) { [string]$context.authSource } else { '' }
    }
    context = [PSCustomObject]@{
        bugId = $workItemId
        organization = if ($null -ne $context) { [string]$context.organization } else { '' }
        project = if ($null -ne $context) { [string]$context.project } else { '' }
        workItemUrl = if ($null -ne $context) { [string]$context.workItemUrl } else { '' }
    }
    descriptionText = [string]$intakeResult.descriptionText
    title = ''
    confidence = $confidence
    nextAction = $nextAction
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

if ($status -eq 'resolved') {
    exit 0
}

exit 1
