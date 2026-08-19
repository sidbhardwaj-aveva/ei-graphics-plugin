#!/usr/bin/env pwsh
<#
.SYNOPSIS
Record an immutable request to widen a sealed scope.

.DESCRIPTION
When implementation needs a file the sealed ApprovedScope does not authorise, the answer is never
to edit the seal. This script records what was needed, who needed it, and which sealed version it
was raised against, and then stops. The request is an input to a human decision, not a decision.

A request is answered by re-resolving the scope, re-analysing it and sealing a new ApprovedScope
version. Earlier sealed versions and earlier requests are never rewritten.

Paths already inside the sealed scope are not a change, and paths inside a declared protected area
are refused outright: a protected area is never widened by request.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][AllowEmptyString()][string]$RequestedBy,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Reason,
    [string[]]$Path = @(),
    [ValidateSet('modify', 'add', 'delete')][string]$ChangeIntent = 'modify',
    [ValidateSet('scope-validation', 'human')][string]$DetectedBy = 'human',
    [int]$Version = 0,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeValidator.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir

if ([string]::IsNullOrWhiteSpace($RequestedBy)) {
    $result = Add-EiError -Result $result -Code 'EISV-CHANGE-REQUESTER-MISSING' -Message 'A scope change request needs an explicit requester. An unattributed request cannot be answered.'
    Exit-EiResult -Result $result -Json:$Json
}

if ([string]::IsNullOrWhiteSpace($Reason)) {
    $result = Add-EiError -Result $result -Code 'EISV-CHANGE-INPUT' -Message 'A scope change request needs a reason. "The implementation needed it" is what the approver is being asked to judge.'
    Exit-EiResult -Result $result -Json:$Json
}

$requested = @(@($Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ConvertTo-EiNormalPath -Path ([string]$_) } | Select-Object -Unique)

if ($requested.Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EISV-CHANGE-INPUT' -Message 'Supply at least one -Path. A request that names no file authorises nothing.'
    Exit-EiResult -Result $result -Json:$Json
}

$sealedVersions = @(Get-EiApprovedScopeVersion -StateDir $StateDir)
if ($Version -lt 1) {
    if ($sealedVersions.Count -eq 0) {
        $result = Add-EiError -Result $result -Code 'EISV-SEAL-MISSING' -Message "No sealed ApprovedScope was found in '$StateDir'. There is no approved scope to change."
        Exit-EiResult -Result $result -Json:$Json
    }

    $Version = [int]$sealedVersions[-1]
}

$hashGate = & "$PSScriptRoot/../../ei-graphics-workflow/scripts/Test-EiApprovedScopeHash.ps1" -StateDir $StateDir -Version $Version -Json | ConvertFrom-Json

if ($hashGate.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-SEAL-UNVERIFIED' -Message "ApprovedScope v$Version did not pass the scope-hash gate, so a change cannot be raised against it: $(@($hashGate.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'approved-scope' -Version $Version -Json | ConvertFrom-Json

if ($readResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-ARTIFACT-UNREADABLE' -Message "ApprovedScope v$Version could not be read from state: $(@($readResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$sealed = $readResult.Details.Payload
$scope = $sealed.scope

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $sealed.storyId
$result = Set-EiDetail -Result $result -Name 'BasedOnApprovedScopeVersion' -Value $Version

$scopePaths = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(@(ConvertTo-EiArray $scope.proposedFiles) | ForEach-Object { ConvertTo-EiNormalPath -Path ([string]$_.path) }),
    [System.StringComparer]::OrdinalIgnoreCase)

$protectedAreas = @(ConvertTo-EiArray $scope.protectedAreas)
$protectedHits = [System.Collections.Generic.List[string]]::new()
$outside = [System.Collections.Generic.List[string]]::new()
$alreadyInScope = [System.Collections.Generic.List[string]]::new()

foreach ($candidate in $requested) {
    $area = @($protectedAreas | Where-Object { Test-EiPathInArea -Path $candidate -Area ([string]$_.path) } | Select-Object -First 1)

    if ($area.Count -gt 0) {
        $protectedHits.Add("$candidate (protected area '$($area[0].path)')")
        continue
    }

    if ($scopePaths.Contains($candidate)) {
        $alreadyInScope.Add($candidate)
        continue
    }

    $outside.Add($candidate)
}

$result = Set-EiDetail -Result $result -Name 'AlreadyInScope' -Value @($alreadyInScope)
$result = Set-EiDetail -Result $result -Name 'ProtectedConflicts' -Value @($protectedHits)

if ($protectedHits.Count -gt 0) {
    $result = Add-EiError -Result $result -Code 'EISV-CHANGE-PROTECTED' -Message "A protected area is never widened by request: $(@($protectedHits) -join '; '). Remove the path or change the protected area with the people who declared it."
    Exit-EiResult -Result $result -Json:$Json
}

if ($outside.Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EISV-CHANGE-REDUNDANT' -Message "Every requested path is already authorised by ApprovedScope v$Version, so there is no change to approve."
    Exit-EiResult -Result $result -Json:$Json
}

$requestVersions = @(Get-EiScopeChangeRequestVersion -StateDir $StateDir)
$requestVersion = if ($requestVersions.Count -eq 0) { 1 } else { [int]$requestVersions[-1] + 1 }

$artifact = [ordered]@{
    schemaVersion               = $script:EiScopeChangeSchemaVersion
    requestedBy                 = $RequestedBy.Trim()
    requestedAt                 = Get-EiUtcTimestamp
    storyId                     = [string]$sealed.storyId
    storyRef                    = if ($null -eq $sealed.storyRef) { $null } else { [string]$sealed.storyRef }
    version                     = $requestVersion
    supersedes                  = if ($requestVersion -gt 1) { $requestVersion - 1 } else { $null }
    basedOnApprovedScopeVersion = $Version
    basedOnContentHash          = [string]$sealed.contentHash
    detectedBy                  = $DetectedBy
    reason                      = $Reason.Trim()
    requestedPaths              = @(foreach ($candidate in $outside) {
            [ordered]@{
                path         = $candidate
                changeIntent = $ChangeIntent
                reason       = $Reason.Trim()
            }
        })
}

$artifactJson = $artifact | ConvertTo-Json -Depth 20

$schemaCheck = Test-EiJsonAgainstSchema -Content $artifactJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'scope-change-request.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EISV-ARTIFACT-SCHEMA' -Message "Scope change request failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$writeResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'scope-change-request' -Content $artifactJson -Version $requestVersion -Json | ConvertFrom-Json

if ($writeResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-ARTIFACT-WRITE' -Message "Scope change request v$requestVersion could not be persisted: $(@($writeResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Path' -Value $writeResult.Details.Path
$result = Set-EiDetail -Result $result -Name 'Version' -Value $requestVersion
$result = Set-EiDetail -Result $result -Name 'RequestedPaths' -Value @($outside)
$result = Set-EiDetail -Result $result -Name 'RequestedBy' -Value $artifact.requestedBy
$result = Set-EiDetail -Result $result -Name 'BasedOnContentHash' -Value $artifact.basedOnContentHash
$result = Set-EiDetail -Result $result -Name 'Payload' -Value ($artifactJson | ConvertFrom-Json)

$result = Add-EiWarning -Result $result -Message "ApprovedScope v$Version is unchanged. Re-resolve, re-analyse and seal a new version to answer this request."

if ($alreadyInScope.Count -gt 0) {
    $result = Add-EiWarning -Result $result -Message "Already authorised and therefore not requested: $(@($alreadyInScope) -join ', ')."
}

Exit-EiResult -Result $result -Json:$Json
