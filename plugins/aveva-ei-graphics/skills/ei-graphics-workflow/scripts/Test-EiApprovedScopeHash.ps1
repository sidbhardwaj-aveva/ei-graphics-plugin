#!/usr/bin/env pwsh
<#
.SYNOPSIS
Verify that a sealed ApprovedScope still matches its recorded content hash.

.DESCRIPTION
This is the `scope-hash` gate. It recomputes the canonical hash from the embedded scope and compares
it with the hash stored in the artifact, so any edit to the authorisation surface after sealing is
detected. When the story state records the same seal version, the state's `approvedScopeHash` must
agree too.

The gate is read-only. It never rewrites, re-seals or repairs an artifact.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [AllowEmptyString()][string]$StateDir = '',
    [AllowEmptyString()][string]$Path = '',
    [int]$Version = 0,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeHash.ps1"

$result = New-EiResult

if ([string]::IsNullOrWhiteSpace($Path) -and [string]::IsNullOrWhiteSpace($StateDir)) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-INPUT' -Message 'Supply either -Path or -StateDir so the gate has a sealed scope to check.'
    Exit-EiResult -Result $result -Json:$Json
}

if (-not [string]::IsNullOrWhiteSpace($StateDir)) {
    $sealedVersions = @(Get-EiApprovedScopeVersion -StateDir $StateDir)

    if ($Version -lt 1) {
        if ($sealedVersions.Count -eq 0) {
            $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-MISSING' -Message "No sealed ApprovedScope was found in '$StateDir'."
            Exit-EiResult -Result $result -Json:$Json
        }

        $Version = [int]$sealedVersions[-1]
    }

    $readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'approved-scope' -Version $Version -Json | ConvertFrom-Json

    if ($readResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-UNREADABLE' -Message "ApprovedScope v$Version could not be read from state: $(@($readResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $Path = [string]$readResult.Details.Path
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-MISSING' -Message "ApprovedScope was not found at '$Path'."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Path' -Value $Path

$content = Get-Content -LiteralPath $Path -Raw

$schemaCheck = Test-EiJsonAgainstSchema -Content $content -SchemaPath (Join-Path (Get-EiSchemaRoot) 'approved-scope.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-SCHEMA' -Message "ApprovedScope failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$artifact = $content | ConvertFrom-Json

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $artifact.storyId
$result = Set-EiDetail -Result $result -Name 'Version' -Value $artifact.version
$result = Set-EiDetail -Result $result -Name 'ApprovedBy' -Value $artifact.approvedBy
$result = Set-EiDetail -Result $result -Name 'StoredHash' -Value $artifact.contentHash
$result = Set-EiDetail -Result $result -Name 'ProposedFileCount' -Value @($artifact.scope.proposedFiles).Count

if ($artifact.schemaVersion -ne $script:EiApprovedScopeSchemaVersion) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCHEMA-VERSION' -Message "ApprovedScope declares schema version '$($artifact.schemaVersion)'; this workflow seals '$script:EiApprovedScopeSchemaVersion'."
}

if ($artifact.hashAlgorithm -ne $script:EiScopeHashAlgorithm -or $artifact.canonicalization -ne $script:EiScopeCanonicalization) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-CANONICALIZATION' -Message "ApprovedScope was sealed with '$($artifact.hashAlgorithm)' over '$($artifact.canonicalization)'; this gate can only re-derive '$script:EiScopeHashAlgorithm' over '$script:EiScopeCanonicalization'."
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $computedHash = Get-EiScopeContentHash -Scope $artifact.scope
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-INVALID' -Message "The sealed scope could not be canonicalised: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'ComputedHash' -Value $computedHash

if ($computedHash -ne [string]$artifact.contentHash) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-HASH-MISMATCH' -Message "ApprovedScope v$($artifact.version) records '$($artifact.contentHash)' but its content hashes to '$computedHash'. The sealed scope has been edited."
}

$statePath = if ([string]::IsNullOrWhiteSpace($StateDir)) { '' } else { Join-Path $StateDir 'workflow-state.json' }

if (-not [string]::IsNullOrWhiteSpace($statePath) -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $result = Set-EiDetail -Result $result -Name 'StateSealVersion' -Value $state.approvedScopeVersion
    $result = Set-EiDetail -Result $result -Name 'StateSealHash' -Value $state.approvedScopeHash

    if ($null -ne $state.approvedScopeVersion -and [int]$state.approvedScopeVersion -eq [int]$artifact.version -and
        [string]$state.approvedScopeHash -ne [string]$artifact.contentHash) {
        $result = Add-EiError -Result $result -Code 'EIWF-SCOPE-SEAL-MISMATCH' -Message "Workflow state records hash '$($state.approvedScopeHash)' for ApprovedScope v$($artifact.version), but the artifact carries '$($artifact.contentHash)'."
    }
}

Exit-EiResult -Result $result -Json:$Json
