#!/usr/bin/env pwsh
<#
.SYNOPSIS
Check the files a writing stage touched against the sealed ApprovedScope.

.DESCRIPTION
This is the `scope-validation` gate. Writer stages are untrusted, so what they actually changed is
compared with what was authorised, path by path. A changed file is in scope only when the sealed
scope names it; nothing is inferred from proximity, directory, or intent.

The seal is verified before the comparison, because a drift check against an edited ApprovedScope
would prove nothing.

The gate never widens a scope and never edits the seal. Out-of-scope drift is answered by a
scope-change request and a new sealed version, not by relaxing this check.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][string]$Stage,
    [string[]]$ChangedPath = @(),
    [AllowEmptyString()][string]$RepositoryRoot = '',
    [int]$Version = 0,
    [AllowEmptyString()][string]$PolicyPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeValidator.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'Stage' -Value $Stage

try {
    $policy = if ([string]::IsNullOrWhiteSpace($PolicyPath)) { Get-EiApprovalPolicy } else { Get-EiApprovalPolicy -PolicyPath $PolicyPath }
}
catch {
    $result = Add-EiError -Result $result -Code 'EISV-POLICY-MISSING' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

$sealedVersions = @(Get-EiApprovedScopeVersion -StateDir $StateDir)
if ($Version -lt 1) {
    if ($sealedVersions.Count -eq 0) {
        $result = Add-EiError -Result $result -Code 'EISV-SEAL-MISSING' -Message "No sealed ApprovedScope was found in '$StateDir'. Nothing authorises these writes."
        Exit-EiResult -Result $result -Json:$Json
    }

    $Version = [int]$sealedVersions[-1]
}

# A drift check against an edited seal would prove nothing, so the seal is verified before it is used.
$hashGate = & "$PSScriptRoot/../../ei-graphics-workflow/scripts/Test-EiApprovedScopeHash.ps1" -StateDir $StateDir -Version $Version -Json | ConvertFrom-Json

if ($hashGate.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-SEAL-UNVERIFIED' -Message "ApprovedScope v$Version did not pass the scope-hash gate, so drift cannot be judged against it: $(@($hashGate.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$readResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'approved-scope' -Version $Version -Json | ConvertFrom-Json

if ($readResult.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EISV-ARTIFACT-UNREADABLE' -Message "ApprovedScope v$Version could not be read from state: $(@($readResult.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$sealed = $readResult.Details.Payload
$scope = $sealed.scope

$candidatePaths = @(@($ChangedPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($candidatePaths.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        $result = Add-EiError -Result $result -Code 'EISV-INPUT-INVALID' -Message "Repository root '$RepositoryRoot' does not exist, so changed files could not be discovered."
        Exit-EiResult -Result $result -Json:$Json
    }

    $porcelain = & git -C $RepositoryRoot -c core.quotepath=false status --porcelain --untracked-files=all 2>&1
    if ($LASTEXITCODE -ne 0) {
        $result = Add-EiError -Result $result -Code 'EISV-DISCOVERY-FAILED' -Message "Changed files could not be discovered from '$RepositoryRoot': $(@($porcelain) -join ' ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $candidatePaths = @(foreach ($line in @($porcelain)) {
            $entry = [string]$line
            if ($entry.Length -le 3) { continue }

            $target = $entry.Substring(3).Trim()
            # A rename is reported as "old -> new"; only the destination was written.
            if ($target -match '\s->\s') { $target = ($target -split '\s->\s', 2)[1] }

            $target.Trim('"')
        })
}

if ($candidatePaths.Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EISV-INPUT-INVALID' -Message 'Supply -ChangedPath or -RepositoryRoot. A stage that reports no changed files at all is not evidence that nothing changed.'
    Exit-EiResult -Result $result -Json:$Json
}

$scopePaths = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(@(ConvertTo-EiArray $scope.proposedFiles) | ForEach-Object { ConvertTo-EiNormalPath -Path ([string]$_.path) }),
    [System.StringComparer]::OrdinalIgnoreCase)

$protectedAreas = @(ConvertTo-EiArray $scope.protectedAreas)

$findings = [System.Collections.Generic.List[object]]::new()
$paths = [System.Collections.Generic.List[object]]::new()

foreach ($candidate in @($candidatePaths | ForEach-Object { ConvertTo-EiNormalPath -Path ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
    $protectedArea = @($protectedAreas | Where-Object { Test-EiPathInArea -Path $candidate -Area ([string]$_.path) } | Select-Object -First 1)

    if ($protectedArea.Count -gt 0) {
        $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-DRIFT-PROTECTED' -Target $candidate -Detail "'$candidate' is inside protected area '$($protectedArea[0].path)'."))
        $paths.Add([ordered]@{ path = $candidate; classification = 'protected'; detail = [string]$protectedArea[0].reason })
        continue
    }

    if ($scopePaths.Contains($candidate)) {
        $paths.Add([ordered]@{ path = $candidate; classification = 'in-scope'; detail = "Authorised by ApprovedScope v$Version." })
        continue
    }

    if (Test-EiPathAllowedByPolicy -Path $candidate -Policy $policy) {
        $paths.Add([ordered]@{ path = $candidate; classification = 'allowed'; detail = 'Workflow bookkeeping, not implementation output.' })
        continue
    }

    $findings.Add((New-EiValidationFinding -Policy $policy -Code 'EISV-DRIFT-OUT-OF-SCOPE' -Target $candidate -Detail "'$candidate' is not named by ApprovedScope v$Version."))
    $paths.Add([ordered]@{ path = $candidate; classification = 'out-of-scope'; detail = "Not named by ApprovedScope v$Version." })
}

$outOfScope = @($paths | Where-Object { $_.classification -in @('out-of-scope', 'protected') })
$summary = if ($outOfScope.Count -gt 0) {
    "Stage '$Stage' changed $($outOfScope.Count) file(s) that ApprovedScope v$Version does not authorise."
}
else {
    "Stage '$Stage' stayed inside ApprovedScope v$Version across $($paths.Count) changed file(s)."
}

$evidence = New-EiValidationEvidence -Gate 'scope-validation' -Stage $Stage -StoryId ([string]$sealed.storyId) `
    -ApprovedScopeVersion $Version -ContentHash ([string]$sealed.contentHash) -Summary $summary -Findings @($findings) -Paths @($paths)

try {
    $saved = Save-EiValidationEvidence -StateDir $StateDir -Evidence $evidence
}
catch {
    $result = Add-EiError -Result $result -Code 'EISV-EVIDENCE-WRITE' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $sealed.storyId
$result = Set-EiDetail -Result $result -Name 'ApprovedScopeVersion' -Value $Version
$result = Set-EiDetail -Result $result -Name 'ContentHash' -Value $sealed.contentHash
$result = Set-EiDetail -Result $result -Name 'Verdict' -Value $evidence.verdict
$result = Set-EiDetail -Result $result -Name 'ChangedPathCount' -Value $paths.Count
$result = Set-EiDetail -Result $result -Name 'OutOfScopePaths' -Value @($paths | Where-Object { $_.classification -eq 'out-of-scope' } | ForEach-Object { $_.path })
$result = Set-EiDetail -Result $result -Name 'ProtectedPaths' -Value @($paths | Where-Object { $_.classification -eq 'protected' } | ForEach-Object { $_.path })
$result = Set-EiDetail -Result $result -Name 'EvidencePath' -Value $saved.Path
$result = Set-EiDetail -Result $result -Name 'StageEvidencePath' -Value $saved.StagePath
$result = Set-EiDetail -Result $result -Name 'Summary' -Value $summary

foreach ($finding in @($findings)) {
    $result = Add-EiError -Result $result -Code $finding.code -Message $finding.message
}

Exit-EiResult -Result $result -Json:$Json
