#!/usr/bin/env pwsh
<#
.SYNOPSIS
Create or resume the file-backed state for an EI Graphics workflow run.

.DESCRIPTION
Materialises `.copilottracking/ei-graphics/<story-id>/` and `workflow-state.json` from the
lifecycle definition owned by `ei-graphics-workflow`. When a valid state file already exists the
run is resumable and the existing state is returned unchanged.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$StoryId,
    [ValidateSet('IMPLEMENT', 'ITERATE')][string]$WorkflowPath = 'IMPLEMENT',
    [AllowEmptyString()][string]$StoryRef = '',
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$TrackingDir = '.copilottracking',
    [string]$LifecycleDefinitionPath = '',
    [AllowEmptyString()][string]$CreatedBy = '',
    [switch]$Force,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiWorkflowState.ps1"

$result = New-EiResult

if (-not (Test-EiStoryId -StoryId $StoryId)) {
    $result = Add-EiError -Result $result -Code 'EIWF-STORY-ID' -Message "Story id '$StoryId' is not a safe state directory name. Use letters, digits, dot, dash or underscore."
    Exit-EiResult -Result $result -Json:$Json
}

if ([string]::IsNullOrWhiteSpace($LifecycleDefinitionPath)) {
    $lifecycleFile = "lifecycle-$($WorkflowPath.ToLowerInvariant()).json"
    $LifecycleDefinitionPath = Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' (Join-Path 'ei-graphics-workflow' (Join-Path 'references' $lifecycleFile))))
}

if (-not (Test-Path -LiteralPath $LifecycleDefinitionPath)) {
    $result = Add-EiError -Result $result -Code 'EIWF-LIFECYCLE-MISSING' -Message "Lifecycle definition not found at '$LifecycleDefinitionPath'."
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $lifecycle = Get-Content -LiteralPath $LifecycleDefinitionPath -Raw | ConvertFrom-Json
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-LIFECYCLE-INVALID' -Message "Lifecycle definition is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

if ($lifecycle.path -ne $WorkflowPath) {
    $result = Add-EiError -Result $result -Code 'EIWF-LIFECYCLE-INVALID' -Message "Lifecycle definition declares path '$($lifecycle.path)' but '$WorkflowPath' was requested."
    Exit-EiResult -Result $result -Json:$Json
}

$stateDir = Resolve-EiStateDir -StoryId $StoryId -WorkspaceRoot $WorkspaceRoot -TrackingDir $TrackingDir
$statePath = Join-Path $stateDir 'workflow-state.json'
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $stateDir
$result = Set-EiDetail -Result $result -Name 'StatePath' -Value $statePath

$stateExists = Test-Path -LiteralPath $statePath

if ($stateExists -and -not $Force) {
    $validatorOutput = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StateDir $stateDir -Json
    $validation = $validatorOutput | ConvertFrom-Json

    if ($validation.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-STATE-CORRUPT' -Message "Existing workflow state is not usable: $(@($validation.Errors) -join '; ')"
        $result = Set-EiDetail -Result $result -Name 'Remediation' -Value 'Re-run with -Force to archive the unusable state and start a fresh run.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $existing = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    if ($existing.path -ne $WorkflowPath) {
        $result = Add-EiError -Result $result -Code 'EIWF-PATH-MISMATCH' -Message "Story '$StoryId' already has an active '$($existing.path)' run; '$WorkflowPath' was requested."
        Exit-EiResult -Result $result -Json:$Json
    }

    $result = Set-EiDetail -Result $result -Name 'Resumed' -Value $true
    $result = Set-EiDetail -Result $result -Name 'WorkflowId' -Value $existing.workflowId
    $result = Set-EiDetail -Result $result -Name 'WorkflowPath' -Value $existing.path
    $result = Set-EiDetail -Result $result -Name 'Stage' -Value $existing.stage
    $result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $existing.status
    $result = Set-EiDetail -Result $result -Name 'StageCount' -Value @($existing.stages).Count
    Exit-EiResult -Result $result -Json:$Json
}

if ($stateExists -and $Force) {
    $backupPath = Join-Path $stateDir ("workflow-state.$((Get-EiUtcTimestamp) -replace '[:\-]', '').bak.json")
    Move-Item -LiteralPath $statePath -Destination $backupPath -Force
    $result = Add-EiWarning -Result $result -Message "Existing workflow state archived to '$backupPath'."
}

$stages = foreach ($stage in @($lifecycle.stages)) {
    [ordered]@{
        id                 = $stage.id
        name               = $stage.name
        owner              = $stage.owner
        artifact           = $stage.artifact
        writesFiles        = [bool]$stage.writesFiles
        gate               = $stage.gate
        implementedInPhase = $stage.implementedInPhase
        status             = 'pending'
        gateResult         = 'not-run'
        startedAt          = $null
        completedAt        = $null
        blockReason        = $null
    }
}

$stages = @($stages)
if ($stages.Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EIWF-LIFECYCLE-INVALID' -Message 'Lifecycle definition contains no stages.'
    Exit-EiResult -Result $result -Json:$Json
}

$timestamp = Get-EiUtcTimestamp
$relativeStateDir = (Join-Path $TrackingDir (Join-Path 'ei-graphics' $StoryId)) -replace '\\', '/'

$state = [ordered]@{
    schemaVersion         = $script:EiStateSchemaVersion
    workflowId            = [guid]::NewGuid().ToString()
    storyId               = $StoryId
    storyRef              = if ([string]::IsNullOrWhiteSpace($StoryRef)) { $null } else { $StoryRef }
    path                  = $WorkflowPath
    status                = 'in-progress'
    stage                 = $stages[0].id
    stateDir              = $relativeStateDir
    createdAt             = $timestamp
    createdBy             = if ([string]::IsNullOrWhiteSpace($CreatedBy)) { $env:USERNAME } else { $CreatedBy }
    updatedAt             = $timestamp
    approvedScopeHash     = $null
    approvedScopeVersion  = $null
    iterationIndex        = 0
    correctionAttempts    = 0
    maxCorrectionAttempts = 3
    stages                = $stages
    blocks                = @()
}

$stateJson = $state | ConvertTo-Json -Depth 20
$schemaCheck = Test-EiJsonAgainstSchema -Content $stateJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'workflow-state.schema.json')

if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-SCHEMA' -Message "Generated workflow state failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stateDir 'validation') -Force | Out-Null
Set-Content -LiteralPath $statePath -Value $stateJson -Encoding utf8

$result = Set-EiDetail -Result $result -Name 'Resumed' -Value $false
$result = Set-EiDetail -Result $result -Name 'WorkflowId' -Value $state.workflowId
$result = Set-EiDetail -Result $result -Name 'WorkflowPath' -Value $state.path
$result = Set-EiDetail -Result $result -Name 'Stage' -Value $state.stage
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $state.status
$result = Set-EiDetail -Result $result -Name 'StageCount' -Value $stages.Count

Exit-EiResult -Result $result -Json:$Json
