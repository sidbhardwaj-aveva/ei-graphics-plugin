#!/usr/bin/env pwsh
<#
.SYNOPSIS
Record a sealed ApprovedScope hash and version in an EI Graphics workflow state file.

.DESCRIPTION
`workflow-state.json` is never hand-edited, and the seal fields are not a stage transition, so they
get their own narrow mutation path. Like `Set-EiWorkflowStage.ps1`, the candidate state is validated
before it is committed, so a rejected seal leaves the state file byte-identical.

A seal version is never reused or lowered: every approval produces a new version and a new hash.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][AllowEmptyString()][string]$ContentHash,
    [Parameter(Mandatory)][int]$Version,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiWorkflowState.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir

$statePath = Join-Path $StateDir 'workflow-state.json'
$result = Set-EiDetail -Result $result -Name 'StatePath' -Value $statePath

$stateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $statePath -Json | ConvertFrom-Json
if ($stateValidation.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "Cannot seal a scope against unusable state: $(@($stateValidation.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

if ($ContentHash -notmatch '^sha256:[0-9a-f]{64}$') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-INVALID' -Message "Content hash '$ContentHash' is not a lowercase 'sha256:<64 hex>' digest."
    Exit-EiResult -Result $result -Json:$Json
}

if ($Version -lt 1) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-VERSION-INVALID' -Message "Seal version '$Version' is not a positive version number."
    Exit-EiResult -Result $result -Json:$Json
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$currentVersion = $state.approvedScopeVersion

if ($null -ne $currentVersion -and $Version -le [int]$currentVersion) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-VERSION-INVALID' -Message "State already records ApprovedScope version $currentVersion; version $Version would reuse or lower a sealed scope."
    Exit-EiResult -Result $result -Json:$Json
}

$state.approvedScopeHash = $ContentHash
$state.approvedScopeVersion = $Version
$state.updatedAt = Get-EiUtcTimestamp

$candidateJson = $state | ConvertTo-Json -Depth 20

$schemaCheck = Test-EiJsonAgainstSchema -Content $candidateJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'workflow-state.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-SCHEMA' -Message "Recording the seal would produce schema-invalid state: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$candidatePath = Join-Path ([System.IO.Path]::GetTempPath()) ("ei-workflow-seal-candidate-$([guid]::NewGuid().ToString('N')).json")
Set-Content -LiteralPath $candidatePath -Value $candidateJson -Encoding utf8

try {
    $candidateValidation = & "$PSScriptRoot/Validate-EiWorkflowState.ps1" -StatePath $candidatePath -Json | ConvertFrom-Json

    if ($candidateValidation.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-STATE-UNUSABLE' -Message "Recording the seal would produce invalid state: $(@($candidateValidation.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }
}
finally {
    Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
}

Set-Content -LiteralPath $statePath -Value $candidateJson -Encoding utf8

$result = Set-EiDetail -Result $result -Name 'ApprovedScopeHash' -Value $state.approvedScopeHash
$result = Set-EiDetail -Result $result -Name 'ApprovedScopeVersion' -Value $state.approvedScopeVersion
$result = Set-EiDetail -Result $result -Name 'PreviousVersion' -Value $currentVersion
$result = Set-EiDetail -Result $result -Name 'UpdatedAt' -Value $state.updatedAt

Exit-EiResult -Result $result -Json:$Json
