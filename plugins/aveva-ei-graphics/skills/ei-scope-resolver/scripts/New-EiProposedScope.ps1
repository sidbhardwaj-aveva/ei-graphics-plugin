#!/usr/bin/env pwsh
<#
.SYNOPSIS
Turn a candidate scope into a policy-checked ProposedScope artifact for an EI Graphics story.

.DESCRIPTION
The model decides which files, modules and symbols might be involved and supplies the evidence for
each. This script decides what survives. Every rule in `references/scope-policy.json` either removes
an item that cannot be defended or lowers the resolver status; nothing here can raise a status or
add a path. A scope therefore never broadens silently.

The artifact carries its own findings in `unresolved`, so `Test-EiProposedScope.ps1` can re-derive
the status from the artifact alone.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StoryInputPath,
    [Parameter(Mandatory)][string]$CandidatePath,
    [AllowEmptyString()][string]$DomainContextPath = '',
    [string]$RepositoryRoot = (Get-Location).Path,
    [AllowEmptyString()][string]$PolicyPath = '',
    [AllowEmptyString()][string]$StateDir = '',
    [AllowEmptyString()][string]$OutputPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeResolver.ps1"

$result = New-EiResult

function Read-EiScopeInput {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found at '$Path'."
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        throw "$Label is not valid JSON: $($_.Exception.Message)"
    }
}

try {
    $policy = if ([string]::IsNullOrWhiteSpace($PolicyPath)) { Get-EiScopePolicy } else { Get-EiScopePolicy -PolicyPath $PolicyPath }
}
catch {
    $result = Add-EiError -Result $result -Code 'EISR-POLICY-MISSING' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $story = Read-EiScopeInput -Path $StoryInputPath -Label 'Story input'
    $candidate = Read-EiScopeInput -Path $CandidatePath -Label 'Candidate scope'
    $domainContextRaw = if ([string]::IsNullOrWhiteSpace($DomainContextPath)) { $null } else { Read-EiScopeInput -Path $DomainContextPath -Label 'Domain context' }
}
catch {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message $_.Exception.Message
    Exit-EiResult -Result $result -Json:$Json
}

$storyId = [string](Get-EiJsonValue -InputObject $story -Name 'storyId' -Default '')
if (-not (Test-EiStoryId -StoryId $storyId)) {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message "Story input must supply a valid 'storyId'; found '$storyId'."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $storyId

$rationale = [string](Get-EiJsonValue -InputObject $candidate -Name 'rationale' -Default '')
if ([string]::IsNullOrWhiteSpace($rationale)) {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message 'Candidate scope must supply a rationale explaining why this is the smallest defensible scope.'
    Exit-EiResult -Result $result -Json:$Json
}

$confidenceValue = Get-EiJsonValue -InputObject $candidate -Name 'confidence'
if ($null -eq $confidenceValue -or -not ($confidenceValue -is [double] -or $confidenceValue -is [int] -or $confidenceValue -is [decimal])) {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message 'Candidate scope must supply a numeric confidence between 0 and 1.'
    Exit-EiResult -Result $result -Json:$Json
}

$confidence = [double]$confidenceValue
if ($confidence -lt 0 -or $confidence -gt 1) {
    $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message "Candidate confidence '$confidence' is outside the range 0..1."
    Exit-EiResult -Result $result -Json:$Json
}

$evidence = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'evidence'))) {
    $id = [string](Get-EiJsonValue -InputObject $item -Name 'id' -Default '')
    $kind = [string](Get-EiJsonValue -InputObject $item -Name 'kind' -Default '')
    $value = [string](Get-EiJsonValue -InputObject $item -Name 'value' -Default '')

    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($value)) {
        $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message 'Every evidence entry needs an id, a kind and a value.'
        Exit-EiResult -Result $result -Json:$Json
    }

    $note = Get-EiJsonValue -InputObject $item -Name 'note'
    $evidence += , ([ordered]@{ id = $id; kind = $kind; value = $value; note = if ($null -eq $note) { $null } else { [string]$note } })
}

$evidenceIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($evidence | ForEach-Object { $_.id }), [System.StringComparer]::Ordinal)

$protectedAreas = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'protectedAreas'))) {
    $path = [string](Get-EiJsonValue -InputObject $item -Name 'path' -Default '')
    $reason = [string](Get-EiJsonValue -InputObject $item -Name 'reason' -Default '')
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($reason)) { continue }
    $protectedAreas += , ([ordered]@{ path = $path; reason = $reason })
}

$dependencies = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'dependencies'))) {
    $name = [string](Get-EiJsonValue -InputObject $item -Name 'name' -Default '')
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $detail = Get-EiJsonValue -InputObject $item -Name 'detail'
    $dependencies += , ([ordered]@{
            name       = $name
            kind       = [string](Get-EiJsonValue -InputObject $item -Name 'kind' -Default 'internal')
            resolution = [string](Get-EiJsonValue -InputObject $item -Name 'resolution' -Default 'unresolved')
            detail     = if ($null -eq $detail) { $null } else { [string]$detail }
        })
}

$unresolvedDependencies = @($dependencies | Where-Object { $_.resolution -eq 'unresolved' })

$excluded = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'excluded'))) {
    $target = [string](Get-EiJsonValue -InputObject $item -Name 'target' -Default '')
    $reason = [string](Get-EiJsonValue -InputObject $item -Name 'reason' -Default '')
    if ([string]::IsNullOrWhiteSpace($target) -or [string]::IsNullOrWhiteSpace($reason)) { continue }
    $excluded += , ([ordered]@{ target = $target; reason = $reason })
}

$drops = [ordered]@{}

function Add-EiScopeDrop {
    param([string]$Code, [string]$Target, [string]$Reason)

    if (-not $drops.Contains($Code)) { $drops[$Code] = [System.Collections.Generic.List[string]]::new() }
    $drops[$Code].Add($Target)
    $script:DroppedTargets += , ([ordered]@{ target = $Target; reason = $Reason })
}

$script:DroppedTargets = @()

function Get-EiEvidenceProblem {
    param([AllowNull()]$Refs)

    $ids = @(ConvertTo-EiArray $Refs | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -eq 0) { return 'no evidence was cited' }

    $unknown = @($ids | Where-Object { -not $evidenceIds.Contains($_) })
    if ($unknown.Count -gt 0) { return "it cites unknown evidence id(s) $($unknown -join ', ')" }

    return ''
}

$proposedFiles = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'proposedFiles'))) {
    $path = [string](Get-EiJsonValue -InputObject $item -Name 'path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path)) { continue }

    $refs = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $item -Name 'evidence') | ForEach-Object { [string]$_ })
    $evidenceProblem = Get-EiEvidenceProblem -Refs $refs

    if (-not [string]::IsNullOrWhiteSpace($evidenceProblem)) {
        Add-EiScopeDrop -Code 'EISR-EVIDENCE-MISSING' -Target $path -Reason "Removed from scope because $evidenceProblem."
        continue
    }

    $protectedHit = @($protectedAreas | Where-Object { Test-EiPathInArea -Path $path -Area $_.path } | Select-Object -First 1)
    if ($protectedHit.Count -gt 0) {
        Add-EiScopeDrop -Code 'EISR-PROTECTED-OVERLAP' -Target $path -Reason "Removed from scope because it falls inside protected area '$($protectedHit[0].path)'."
        continue
    }

    $dependencyHit = @($unresolvedDependencies | Where-Object { Test-EiPathOwnedByDependency -Path $path -DependencyName $_.name } | Select-Object -First 1)
    if ($dependencyHit.Count -gt 0) {
        Add-EiScopeDrop -Code 'EISR-DEPENDENCY-ABSORBED' -Target $path -Reason "Removed from scope because it belongs to unresolved dependency '$($dependencyHit[0].name)'."
        continue
    }

    $symbols = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $item -Name 'symbols') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($symbols.Count -gt $policy.limits.maxSymbolsPerFile) {
        $symbols = @($symbols | Select-Object -First $policy.limits.maxSymbolsPerFile)
    }

    $fileConfidence = Get-EiJsonValue -InputObject $item -Name 'confidence' -Default $confidence

    $proposedFiles += , ([ordered]@{
            path         = $path
            changeIntent = [string](Get-EiJsonValue -InputObject $item -Name 'changeIntent' -Default 'modify')
            symbols      = $symbols
            evidence     = $refs
            confidence   = [double]$fileConfidence
        })
}

$proposedModules = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'proposedModules'))) {
    $name = [string](Get-EiJsonValue -InputObject $item -Name 'name' -Default '')
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $refs = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $item -Name 'evidence') | ForEach-Object { [string]$_ })
    $evidenceProblem = Get-EiEvidenceProblem -Refs $refs

    if (-not [string]::IsNullOrWhiteSpace($evidenceProblem)) {
        Add-EiScopeDrop -Code 'EISR-EVIDENCE-MISSING' -Target $name -Reason "Removed from scope because $evidenceProblem."
        continue
    }

    if (@($unresolvedDependencies | Where-Object { $_.name -eq $name }).Count -gt 0) {
        Add-EiScopeDrop -Code 'EISR-DEPENDENCY-ABSORBED' -Target $name -Reason "Removed from scope because it is an unresolved dependency."
        continue
    }

    $projectPath = Get-EiJsonValue -InputObject $item -Name 'projectPath'
    $proposedModules += , ([ordered]@{
            name        = $name
            projectPath = if ($null -eq $projectPath) { $null } else { [string]$projectPath }
            evidence    = $refs
        })
}

$relatedTests = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'relatedTests'))) {
    $target = [string](Get-EiJsonValue -InputObject $item -Name 'target' -Default '')
    if ([string]::IsNullOrWhiteSpace($target)) { continue }

    $refs = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $item -Name 'evidence') | ForEach-Object { [string]$_ })
    $evidenceProblem = Get-EiEvidenceProblem -Refs $refs

    if (-not [string]::IsNullOrWhiteSpace($evidenceProblem)) {
        Add-EiScopeDrop -Code 'EISR-EVIDENCE-MISSING' -Target $target -Reason "Removed from scope because $evidenceProblem."
        continue
    }

    $relatedTests += , ([ordered]@{
            target   = $target
            kind     = [string](Get-EiJsonValue -InputObject $item -Name 'kind' -Default 'targeted')
            evidence = $refs
        })
}

$excluded += $script:DroppedTargets

$domainContext = $null
if ($null -ne $domainContextRaw) {
    $domainSkills = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $domainContextRaw -Name 'domainSkills'))
    $detectedIds  = @($domainSkills | ForEach-Object {
            $id = Get-EiJsonValue -InputObject $_ -Name 'domainId'
            if ($null -ne $id) { [string]$id }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $domainContext = [ordered]@{
        source      = [string](Get-EiJsonValue -InputObject $domainContextRaw -Name 'source' -Default 'ei-domain-skill-registry')
        terms       = @($detectedIds)
        ambiguities = @()
        confidence  = $null
    }
}

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($code in $drops.Keys) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code $code -Detail "Removed: $(@($drops[$code]) -join ', ')."))
}

if ($null -eq $domainContext) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-CONTEXT-MISSING'))
}

if ($proposedFiles.Count -eq 0) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-EMPTY-SCOPE'))
}

if ($proposedFiles.Count -gt $policy.limits.maxProposedFiles) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-SCOPE-BREADTH' -Detail "$($proposedFiles.Count) files exceed the limit of $($policy.limits.maxProposedFiles)."))
}
elseif ($proposedModules.Count -gt $policy.limits.maxProposedModules) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-SCOPE-BREADTH' -Detail "$($proposedModules.Count) modules exceed the limit of $($policy.limits.maxProposedModules)."))
}

if ($unresolvedDependencies.Count -gt 0) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-DEPENDENCY-UNRESOLVED' -Detail "Unresolved: $(@($unresolvedDependencies | ForEach-Object { $_.name }) -join ', ')."))
}

$unverified = @($proposedFiles | Where-Object { -not (Test-EiProposedPathPresent -RepositoryRoot $RepositoryRoot -Path $_.path -ChangeIntent $_.changeIntent) })
if ($unverified.Count -gt 0) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-PATH-UNVERIFIED' -Detail "Unverified: $(@($unverified | ForEach-Object { $_.path }) -join ', ')."))
}

if ($confidence -lt $policy.limits.minConfidence) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-CONFIDENCE-LOW' -Detail "Confidence $confidence is below $($policy.limits.minConfidence)."))
}

if ($relatedTests.Count -eq 0) {
    $findings.Add((New-EiScopeFinding -Policy $policy -Code 'EISR-TESTS-MISSING'))
}

foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'unresolved'))) {
    $code = [string](Get-EiJsonValue -InputObject $item -Name 'code' -Default '')
    $question = [string](Get-EiJsonValue -InputObject $item -Name 'question' -Default '')

    if ($code -notmatch '^EISR-[A-Z-]+$' -or [string]::IsNullOrWhiteSpace($question)) {
        $result = Add-EiError -Result $result -Code 'EISR-INPUT-INVALID' -Message "Candidate unresolved entries need an EISR-* code and a question; found code '$code'."
        Exit-EiResult -Result $result -Json:$Json
    }

    $findings.Add([ordered]@{
            code     = $code
            question = $question
            blocking = [bool](Get-EiJsonValue -InputObject $item -Name 'blocking' -Default $false)
        })
}

$unresolved = @()
$seenFindings = [System.Collections.Generic.HashSet[string]]::new()
foreach ($finding in $findings) {
    if ($seenFindings.Add("$($finding.code)|$($finding.question)")) { $unresolved += , $finding }
}

$risks = @()
foreach ($item in @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $candidate -Name 'risks'))) {
    $id = [string](Get-EiJsonValue -InputObject $item -Name 'id' -Default '')
    $description = [string](Get-EiJsonValue -InputObject $item -Name 'description' -Default '')
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($description)) { continue }

    $risks += , ([ordered]@{
            id          = $id
            description = $description
            severity    = [string](Get-EiJsonValue -InputObject $item -Name 'severity' -Default 'medium')
        })
}

$storyRef = Get-EiJsonValue -InputObject $story -Name 'storyRef'
$storySummary = Get-EiJsonValue -InputObject $story -Name 'summary'

$artifact = [ordered]@{
    schemaVersion   = $script:EiScopeSchemaVersion
    resolver        = 'ei-scope-resolver'
    storyId         = $storyId
    storyRef        = if ($null -eq $storyRef) { $null } else { [string]$storyRef }
    storySummary    = if ($null -eq $storySummary) { $null } else { [string]$storySummary }
    generatedAt     = Get-EiUtcTimestamp
    status          = Resolve-EiScopeStatus -Unresolved $unresolved
    confidence      = $confidence
    domainContext   = $domainContext
    proposedFiles   = @($proposedFiles)
    proposedModules = @($proposedModules)
    relatedTests    = @($relatedTests)
    protectedAreas  = @($protectedAreas)
    dependencies    = @($dependencies)
    evidence        = @($evidence)
    excluded        = @($excluded)
    risks           = @($risks)
    unresolved      = @($unresolved)
    rationale       = $rationale
}

$artifactJson = $artifact | ConvertTo-Json -Depth 20

$schemaCheck = Test-EiJsonAgainstSchema -Content $artifactJson -SchemaPath (Join-Path (Get-EiSchemaRoot) 'proposed-scope.schema.json')
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EISR-ARTIFACT-SCHEMA' -Message "Generated ProposedScope failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

if (-not [string]::IsNullOrWhiteSpace($StateDir)) {
    $writeResult = & "$PSScriptRoot/../../ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1" -StateDir $StateDir -Name 'proposed-scope' -Content $artifactJson -Json | ConvertFrom-Json

    if ($writeResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EISR-ARTIFACT-WRITE' -Message "ProposedScope could not be persisted: $(@($writeResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }

    $result = Set-EiDetail -Result $result -Name 'Path' -Value $writeResult.Details.Path
}
elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $artifactJson -Encoding utf8
    $result = Set-EiDetail -Result $result -Name 'Path' -Value $OutputPath
}

$result = Set-EiDetail -Result $result -Name 'ScopeStatus' -Value $artifact.status
$result = Set-EiDetail -Result $result -Name 'ProposedFileCount' -Value @($proposedFiles).Count
$result = Set-EiDetail -Result $result -Name 'ProposedModuleCount' -Value @($proposedModules).Count
$result = Set-EiDetail -Result $result -Name 'ExcludedCount' -Value @($excluded).Count
$result = Set-EiDetail -Result $result -Name 'UnresolvedCodes' -Value @($unresolved | ForEach-Object { $_.code })
$result = Set-EiDetail -Result $result -Name 'Payload' -Value ($artifactJson | ConvertFrom-Json)

if ($artifact.status -ne 'resolved') {
    $result = Add-EiWarning -Result $result -Message "ProposedScope status is '$($artifact.status)'. It is not approvable until every finding is answered."
}

Exit-EiResult -Result $result -Json:$Json
