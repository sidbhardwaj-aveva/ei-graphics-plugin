#!/usr/bin/env pwsh
<#
.SYNOPSIS
Seal an approved ProposedScope into a versioned, hash-addressed ApprovedScope artifact.

.DESCRIPTION
Sealing is a preservation step, not an analysis step. It takes the ProposedScope exactly as the
resolver produced it, records who approved it and when, and stamps a content hash so any later edit
to the authorisation surface is detectable.

Only a `resolved` proposal can be sealed. `needs-review` and `blocked` are refusals, because an
unanswered finding is not an approval. The scope is never widened, re-derived, or repaired here.

The seal is recorded in `workflow-state.json` only after the artifact has been written and the
`scope-hash` gate has passed against the persisted file.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][AllowEmptyString()][string]$ApprovedBy,
    [AllowEmptyString()][string]$ApprovalNote = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeHash.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir

if ([string]::IsNullOrWhiteSpace($ApprovedBy)) {
    $result = Add-EiError -Result $result -Code 'EIWF-APPROVER-MISSING' -Message 'Sealing requires an explicit approver identity. An unattributed approval is not an approval.'
    Exit-EiResult -Result $result -Json:$Json
}

$readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'proposed-scope' -Json | ConvertFrom-Json

if ($readResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-SOURCE-UNREADABLE' -Message "ProposedScope could not be read from state: $(@($readResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$scope = $readResult.Details.Payload

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $scope.storyId
$result = Set-EiDetail -Result $result -Name 'ScopeStatus' -Value $scope.status

if ($scope.status -ne 'resolved') {
    $codes = @(@($scope.unresolved) | ForEach-Object { $_.code } | Select-Object -Unique)
    $detail = if ($codes.Count -gt 0) { " Outstanding findings: $(@($codes) -join ', ')." } else { '' }
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-NOT-APPROVABLE' -Message "ProposedScope status is '$($scope.status)', so it cannot be sealed.$detail A human must answer every finding and the resolver must return 'resolved' first."
    Exit-EiResult -Result $result -Json:$Json
}

$sealedVersions = @(Get-EiApprovedScopeVersion -StateDir $StateDir)
$version = if ($sealedVersions.Count -eq 0) { 1 } else { [int]$sealedVersions[-1] + 1 }

try {
    $contentHash = Get-EiScopeContentHash -Scope $scope
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-INVALID' -Message "The approved scope could not be canonicalised: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$artifact = [ordered]@{
    schemaVersion    = $script:EiApprovedScopeSchemaVersion
    sealedBy         = 'ei-graphics-workflow'
    storyId          = [string]$scope.storyId
    storyRef         = if ($null -eq $scope.storyRef) { $null } else { [string]$scope.storyRef }
    version          = $version
    supersedes       = if ($version -gt 1) { $version - 1 } else { $null }
    approvedBy       = $ApprovedBy.Trim()
    approvedAt       = Get-EiUtcTimestamp
    approvalNote     = if ([string]::IsNullOrWhiteSpace($ApprovalNote)) { $null } else { $ApprovalNote.Trim() }
    sourceArtifact   = 'proposed-scope'
    hashAlgorithm    = $script:EiScopeHashAlgorithm
    canonicalization = $script:EiScopeCanonicalization
    contentHash      = $contentHash
    scope            = $scope
}

$artifactJson = $artifact | ConvertTo-Json -Depth 40

$schemaCheck = Test-EiJsonAgainstSchema -Content $artifactJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'approved-scope.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-SCHEMA' -Message "Sealed ApprovedScope failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$writeResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'approved-scope' -Content $artifactJson -Version $version -Json | ConvertFrom-Json

if ($writeResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-WRITE' -Message "ApprovedScope v$version could not be persisted: $(@($writeResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$artifactPath = [string]$writeResult.Details.Path
$result = Set-EiDetail -Result $result -Name 'Path' -Value $artifactPath

# The seal is only trustworthy once it survives a round trip through the gate that will police it later.
$gateResult = & "$PSScriptRoot/Test-EiApprovedScopeHash.ps1" -Path $artifactPath -Json | ConvertFrom-Json

if ($gateResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-MISMATCH' -Message "ApprovedScope v$version did not survive its own scope-hash gate, so the seal was not recorded in state: $(@($gateResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$sealResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Set-EiApprovedScopeSeal.ps1" -StateDir $StateDir -ContentHash $contentHash -Version $version -Json | ConvertFrom-Json

if ($sealResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-SEAL-FAILED' -Message "ApprovedScope v$version was written but the seal could not be recorded in state: $(@($sealResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Version' -Value $version
$result = Set-EiDetail -Result $result -Name 'ContentHash' -Value $contentHash
$result = Set-EiDetail -Result $result -Name 'ApprovedBy' -Value $artifact.approvedBy
$result = Set-EiDetail -Result $result -Name 'ApprovedAt' -Value $artifact.approvedAt
$result = Set-EiDetail -Result $result -Name 'Supersedes' -Value $artifact.supersedes
$result = Set-EiDetail -Result $result -Name 'ProposedFileCount' -Value @($scope.proposedFiles).Count
$result = Set-EiDetail -Result $result -Name 'Payload' -Value ($artifactJson | ConvertFrom-Json)

Exit-EiResult -Result $result -Json:$Json
