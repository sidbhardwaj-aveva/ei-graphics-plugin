#!/usr/bin/env pwsh
<#
.SYNOPSIS
Gate a ProposedScope artifact for the proposed-scope stage.

.DESCRIPTION
This is the deterministic gate for the proposed-scope stage. It re-derives everything it can from
the artifact itself, so a hand-edited or model-edited scope cannot pass: the declared status must
match the status implied by the recorded findings, every proposed path must still be evidence
linked, and no proposed path may sit inside a protected area or an unresolved dependency.

The gate passes only when the artifact is schema-valid, policy-clean and its status is `resolved`.
`needs-review` and `blocked` are BLOCK states, never a pass.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [AllowEmptyString()][string]$Path = '',
    [AllowEmptyString()][string]$StateDir = '',
    [AllowEmptyString()][string]$PolicyPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeResolver.ps1"

$result = New-EiResult

if ([string]::IsNullOrWhiteSpace($Path) -and [string]::IsNullOrWhiteSpace($StateDir)) {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message 'Supply either -Path or -StateDir so the gate has an artifact to check.'
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $policy = if ([string]::IsNullOrWhiteSpace($PolicyPath)) { Get-EiScopePolicy } else { Get-EiScopePolicy -PolicyPath $PolicyPath }
}
catch {
    $result = Add-EiError -Result $result -Code 'EISR-POLICY-MISSING' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

if (-not [string]::IsNullOrWhiteSpace($StateDir)) {
    $readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'proposed-scope' -Json | ConvertFrom-Json

    if ($readResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EISR-ARTIFACT-UNREADABLE' -Message "ProposedScope could not be read from state: $(@($readResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $Path = [string]$readResult.Details.Path
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $result = Add-EiError -Result $result -Code 'EISR-ARTIFACT-MISSING' -Message "ProposedScope was not found at '$Path'."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Path' -Value $Path

$content = Get-Content -LiteralPath $Path -Raw

$schemaCheck = Test-EiJsonAgainstSchema -Content $content -SchemaPath (Join-Path (Get-EiSchemaRoot) 'proposed-scope.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EISR-ARTIFACT-SCHEMA' -Message "ProposedScope failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$artifact = $content | ConvertFrom-Json

if ($artifact.schemaVersion -ne $script:EiScopeSchemaVersion) {
    $result = Add-EiError -Result $result -Code 'EISR-SCHEMA-VERSION' -Message "ProposedScope declares schema version '$($artifact.schemaVersion)'; this resolver produces '$($script:EiScopeSchemaVersion)'."
}

$unresolved = @($artifact.unresolved)
$derivedStatus = Resolve-EiScopeStatus -Unresolved $unresolved

$result = Set-EiDetail -Result $result -Name 'ScopeStatus' -Value $artifact.status
$result = Set-EiDetail -Result $result -Name 'DerivedStatus' -Value $derivedStatus
$result = Set-EiDetail -Result $result -Name 'ProposedFileCount' -Value @($artifact.proposedFiles).Count
$result = Set-EiDetail -Result $result -Name 'UnresolvedCodes' -Value @($unresolved | ForEach-Object { $_.code })

if ($artifact.status -ne $derivedStatus) {
    $result = Add-EiError -Result $result -Code 'EISR-STATUS-MISMATCH' -Message "ProposedScope declares status '$($artifact.status)' but its recorded findings imply '$derivedStatus'. The artifact has been edited outside the resolver."
}

$evidenceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($artifact.evidence) | ForEach-Object { [string]$_.id }), [System.StringComparer]::Ordinal)
$protectedAreas = @($artifact.protectedAreas)
$unresolvedDependencies = @(@($artifact.dependencies) | Where-Object { $_.resolution -eq 'unresolved' })

foreach ($file in @($artifact.proposedFiles)) {
    $unknown = @(@($file.evidence) | Where-Object { -not $evidenceIds.Contains([string]$_) })
    if ($unknown.Count -gt 0) {
        $result = Add-EiError -Result $result -Code 'EISR-EVIDENCE-MISSING' -Message "Proposed file '$($file.path)' cites evidence id(s) $($unknown -join ', ') that the artifact does not contain."
    }

    foreach ($area in $protectedAreas) {
        if (Test-EiPathInArea -Path $file.path -Area $area.path) {
            $result = Add-EiError -Result $result -Code 'EISR-PROTECTED-OVERLAP' -Message "Proposed file '$($file.path)' falls inside protected area '$($area.path)'."
        }
    }

    foreach ($dependency in $unresolvedDependencies) {
        if (Test-EiPathOwnedByDependency -Path $file.path -DependencyName $dependency.name) {
            $result = Add-EiError -Result $result -Code 'EISR-DEPENDENCY-ABSORBED' -Message "Proposed file '$($file.path)' belongs to unresolved dependency '$($dependency.name)'."
        }
    }
}

foreach ($module in @($artifact.proposedModules)) {
    $unknown = @(@($module.evidence) | Where-Object { -not $evidenceIds.Contains([string]$_) })
    if ($unknown.Count -gt 0) {
        $result = Add-EiError -Result $result -Code 'EISR-EVIDENCE-MISSING' -Message "Proposed module '$($module.name)' cites evidence id(s) $($unknown -join ', ') that the artifact does not contain."
    }

    if (@($unresolvedDependencies | Where-Object { $_.name -eq $module.name }).Count -gt 0) {
        $result = Add-EiError -Result $result -Code 'EISR-DEPENDENCY-ABSORBED' -Message "Proposed module '$($module.name)' is still an unresolved dependency."
    }
}

foreach ($test in @($artifact.relatedTests)) {
    $unknown = @(@($test.evidence) | Where-Object { -not $evidenceIds.Contains([string]$_) })
    if ($unknown.Count -gt 0) {
        $result = Add-EiError -Result $result -Code 'EISR-EVIDENCE-MISSING' -Message "Related test '$($test.target)' cites evidence id(s) $($unknown -join ', ') that the artifact does not contain."
    }
}

if (@($artifact.proposedFiles).Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EISR-EMPTY-SCOPE' -Message 'ProposedScope contains no files, so there is nothing to approve.'
}

if (@($artifact.proposedFiles).Count -gt $policy.limits.maxProposedFiles) {
    $result = Add-EiError -Result $result -Code 'EISR-SCOPE-BREADTH' -Message "ProposedScope contains $(@($artifact.proposedFiles).Count) files, above the limit of $($policy.limits.maxProposedFiles)."
}

if (@($artifact.proposedModules).Count -gt $policy.limits.maxProposedModules) {
    $result = Add-EiError -Result $result -Code 'EISR-SCOPE-BREADTH' -Message "ProposedScope contains $(@($artifact.proposedModules).Count) modules, above the limit of $($policy.limits.maxProposedModules)."
}

if ($artifact.status -ne 'resolved') {
    $codes = @($unresolved | ForEach-Object { $_.code }) | Select-Object -Unique
    $result = Add-EiError -Result $result -Code 'EISR-SCOPE-NOT-RESOLVED' -Message "ProposedScope status is '$($artifact.status)'. Outstanding findings: $(@($codes) -join ', '). A human must answer them before the scope can be approved."
}

Exit-EiResult -Result $result -Json:$Json
