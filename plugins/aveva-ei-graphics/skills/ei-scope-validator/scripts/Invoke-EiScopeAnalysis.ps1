#!/usr/bin/env pwsh
<#
.SYNOPSIS
Judge whether a ProposedScope is defensible enough to put in front of a human approver.

.DESCRIPTION
This is the `scope-analysis` gate. It answers a different question from
`ei-scope-resolver/scripts/Test-EiProposedScope.ps1`: that gate decides whether the artifact is
internally consistent, this one decides whether the scope it describes is narrow and provable
enough to be worth a human decision.

Every threshold lives in `references/approval-policy.json` and the hard size limits it defers to
live in the resolver's `scope-policy.json`. Nothing here is judged by the model.

The analysis is read-only with respect to the scope: it records findings, never edits, widens or
downgrades them. A scope that the resolver did not mark `resolved` is never analysed into
readiness.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [AllowEmptyString()][string]$PolicyPath = '',
    [AllowEmptyString()][string]$ScopePolicyPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeValidator.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir

try {
    $policy = if ([string]::IsNullOrWhiteSpace($PolicyPath)) { Get-EiApprovalPolicy } else { Get-EiApprovalPolicy -PolicyPath $PolicyPath }
    $scopePolicy = if ([string]::IsNullOrWhiteSpace($ScopePolicyPath)) { Get-EiScopePolicy } else { Get-EiScopePolicy -PolicyPath $ScopePolicyPath }
}
catch {
    $result = Add-EiError -Result $result -Code 'EISV-POLICY-MISSING' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

$readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'proposed-scope' -Json | ConvertFrom-Json

if ($readResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-ARTIFACT-UNREADABLE' -Message "ProposedScope could not be read from state: $(@($readResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$scope = $readResult.Details.Payload
$files = @(ConvertTo-EiArray $scope.proposedFiles)
$tests = @(ConvertTo-EiArray $scope.relatedTests)

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $scope.storyId
$result = Set-EiDetail -Result $result -Name 'ScopeStatus' -Value $scope.status
$result = Set-EiDetail -Result $result -Name 'ProposedFileCount' -Value $files.Count

$findings = [System.Collections.Generic.List[object]]::new()

if ($scope.status -ne 'resolved') {
    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-SCOPE-NOT-RESOLVED' -Detail "ProposedScope status is '$($scope.status)'."))
}

$areas = @(@($files | ForEach-Object { Get-EiImplementationArea -Path $_.path -Depth ([int]$policy.thresholds.areaSegmentDepth) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -Unique)
$result = Set-EiDetail -Result $result -Name 'ImplementationAreas' -Value $areas

if ($areas.Count -gt [int]$policy.thresholds.maxImplementationAreas) {
    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-AREA-SPREAD' -Detail "The scope touches $($areas.Count) implementation areas ($(@($areas) -join ', ')), above the limit of $($policy.thresholds.maxImplementationAreas)."))
}

foreach ($file in $files) {
    $path = [string]$file.path

    if ([double]$file.confidence -lt [double]$policy.thresholds.minFileConfidence) {
        $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-FILE-CONFIDENCE-LOW' -Target $path -Detail "'$path' is proposed with confidence $($file.confidence), below the floor of $($policy.thresholds.minFileConfidence)."))
    }

    if ($file.changeIntent -eq 'modify' -and @(ConvertTo-EiArray $file.symbols).Count -eq 0) {
        $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-SYMBOLS-MISSING' -Target $path -Detail "'$path' is proposed for modification with no named symbol."))
    }

    if ($file.changeIntent -in @('modify', 'add')) {
        $covered = @($tests | Where-Object { Test-EiTestNamesPath -TestTarget ([string]$_.target) -Path $path })
        if ($covered.Count -eq 0) {
            $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-TEST-COVERAGE-GAP' -Target $path -Detail "No related test names '$path'."))
        }
    }
}

foreach ($risk in @(ConvertTo-EiArray $scope.risks)) {
    if ($risk.severity -eq 'high') {
        $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-RISK-HIGH' -Target ([string]$risk.id) -Detail "Risk $($risk.id): $($risk.description)."))
    }
}

if ($files.Count -gt [int]$policy.thresholds.reviewFileCount) {
    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-BREADTH-REVIEW' -Detail "The scope proposes $($files.Count) files, above the review threshold of $($policy.thresholds.reviewFileCount) and within the resolver limit of $($scopePolicy.limits.maxProposedFiles)."))
}

$addedFiles = @($files | Where-Object { $_.changeIntent -eq 'add' })
if ($addedFiles.Count -gt [int]$policy.thresholds.reviewAddedFileCount) {
    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-ADDED-FILE-BREADTH' -Detail "The scope creates $($addedFiles.Count) new files."))
}

$deletedFiles = @($files | Where-Object { $_.changeIntent -eq 'delete' })
if ($deletedFiles.Count -gt 0) {
    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-DELETE-PRESENT' -Detail "The scope deletes $($deletedFiles.Count) file(s): $(@($deletedFiles | ForEach-Object { $_.path }) -join ', ')."))
}

foreach ($dependency in @(ConvertTo-EiArray $scope.dependencies)) {
    if ($dependency.resolution -eq 'unresolved') {
        $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-DEPENDENCY-UNRESOLVED' -Target ([string]$dependency.name) -Detail "Dependency '$($dependency.name)' is unresolved."))
    }
}

try {
    $contentHash = Get-EiScopeContentHash -Scope $scope
}
catch {
    $result = Add-EiError -Result $result -Code 'EISV-SCOPE-UNHASHABLE' -Message "The proposed scope could not be canonicalised, so an approval could not be bound to it: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$paths = foreach ($file in $files) {
    [ordered]@{
        path           = [string]$file.path
        classification = 'in-scope'
        detail         = "Proposed to $($file.changeIntent)."
    }
}

$blocking = @($findings | Where-Object { $_.severity -eq 'blocking' })
$summary = if ($blocking.Count -gt 0) {
    "Scope is not ready for approval: $(@($blocking | ForEach-Object { $_.code } | Select-Object -Unique) -join ', ')."
}
else {
    "Scope is ready for approval: $($files.Count) file(s) across $($areas.Count) implementation area(s), $(@($findings).Count) advisory finding(s)."
}

$evidence = New-EiValidationEvidence -Gate 'scope-analysis' -Stage 'scope-analysis' -StoryId ([string]$scope.storyId) `
    -ApprovedScopeVersion $null -ContentHash $contentHash -Summary $summary -Findings @($findings) -Paths @($paths)

try {
    $saved = Save-EiValidationEvidence -StateDir $StateDir -Evidence $evidence
}
catch {
    $result = Add-EiError -Result $result -Code 'EISV-EVIDENCE-WRITE' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Verdict' -Value $evidence.verdict
$result = Set-EiDetail -Result $result -Name 'ContentHash' -Value $contentHash
$result = Set-EiDetail -Result $result -Name 'EvidencePath' -Value $saved.Path
$result = Set-EiDetail -Result $result -Name 'StageEvidencePath' -Value $saved.StagePath
$result = Set-EiDetail -Result $result -Name 'FindingCodes' -Value @($findings | ForEach-Object { $_.code })
$result = Set-EiDetail -Result $result -Name 'BlockingCodes' -Value @($blocking | ForEach-Object { $_.code } | Select-Object -Unique)
$result = Set-EiDetail -Result $result -Name 'Summary' -Value $summary

foreach ($finding in @($findings | Where-Object { $_.severity -eq 'advisory' })) {
    $result = Add-EiWarning -Result $result -Message "$($finding.code): $($finding.message)"
}

if ($evidence.verdict -eq 'block') {
    $result = Add-EiError -Result $result -Code 'EISV-SCOPE-NOT-APPROVABLE' -Message "$summary The approver is not asked until these are answered."
}

Exit-EiResult -Result $result -Json:$Json
