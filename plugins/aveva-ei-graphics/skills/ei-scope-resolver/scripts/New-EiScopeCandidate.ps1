#!/usr/bin/env pwsh
<#
.SYNOPSIS
Generate an initial scope candidate from the sealed ADO and domain-context artifacts.

.DESCRIPTION
Reads ado.json and domain-context.json to produce candidate.json — the evidence file consumed
by New-EiProposedScope.ps1 at the scope-candidate lifecycle stage.

The candidate is a starting point. The model reviews it and may adjust evidence, proposedFiles,
and confidence before running the scope resolver. Evidence comes from three sources:

  1. Story title and description text (kind: "story").
  2. Key Files declared by each matched domain skill (kind: "domain-skill-key-file"). Key files
     are candidate evidence; they are NOT automatically proposed scope.
  3. Repository file search: source files whose names contain terms from the story title (kind: "path").

proposedFiles includes only key files that physically exist under RepositoryRoot. Repository search
hits are added to evidence only — the model decides whether to promote them to proposedFiles.

The script does NOT manage lifecycle stage transitions. The caller is responsible for marking
the scope-candidate stage started and complete.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
Status = Valid  → candidate.json written, Details.WrittenTo is set.
Status = Invalid → nothing was written, Details contains the error list.

.EXAMPLE
& ./New-EiScopeCandidate.ps1 `
    -AdoPath           .copilottracking/ei-graphics/3408091/ado.json `
    -DomainContextPath .copilottracking/ei-graphics/3408091/domain-context.json `
    -RepositoryRoot    . `
    -StateDir          .copilottracking/ei-graphics/3408091 `
    -Json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AdoPath,
    [Parameter(Mandatory)][string]$DomainContextPath,
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$StateDir = '',
    [string]$OutputPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiScopeResolver.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'AdoPath'           -Value $AdoPath
$result = Set-EiDetail -Result $result -Name 'DomainContextPath' -Value $DomainContextPath
$result = Set-EiDetail -Result $result -Name 'RepositoryRoot'    -Value $RepositoryRoot

# ── Validate output target up front ──────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($StateDir) -and [string]::IsNullOrWhiteSpace($OutputPath)) {
    $result = Add-EiError -Result $result -Code 'EISC-NO-OUTPUT' `
        -Message 'Either -StateDir or -OutputPath must be provided.'
    Exit-EiResult -Result $result -Json:$Json
}

if (-not [string]::IsNullOrWhiteSpace($StateDir) -and -not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    $result = Add-EiError -Result $result -Code 'EISC-STATE-MISSING' `
        -Message "State directory '$StateDir' does not exist. Initialise the workflow first."
    Exit-EiResult -Result $result -Json:$Json
}

# ── Read ADO artifact ─────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $AdoPath)) {
    $result = Add-EiError -Result $result -Code 'EISC-ADO-MISSING' `
        -Message "ADO artifact not found at '$AdoPath'. Run Invoke-EiAdoIntakeStage.ps1 first."
    Exit-EiResult -Result $result -Json:$Json
}

$adoRaw = $null
try { $adoRaw = Get-Content -LiteralPath $AdoPath -Raw | ConvertFrom-Json }
catch {
    $result = Add-EiError -Result $result -Code 'EISC-ADO-INVALID' `
        -Message "ADO artifact at '$AdoPath' is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$storyId      = [string](Get-EiJsonValue -InputObject $adoRaw -Name 'storyId'      -Default '')
$storySummary = [string](Get-EiJsonValue -InputObject $adoRaw -Name 'summary'      -Default '')
$storyDesc    = [string](Get-EiJsonValue -InputObject $adoRaw -Name 'description'  -Default '')

if ([string]::IsNullOrWhiteSpace($storyId)) {
    $result = Add-EiError -Result $result -Code 'EISC-ADO-INVALID' `
        -Message "ADO artifact at '$AdoPath' is missing storyId."
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $storyId

# ── Read domain-context artifact ──────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $DomainContextPath)) {
    $result = Add-EiError -Result $result -Code 'EISC-DOMAIN-MISSING' `
        -Message "Domain-context artifact not found at '$DomainContextPath'. Run Invoke-EiDomainContextStage.ps1 first."
    Exit-EiResult -Result $result -Json:$Json
}

$domainRaw = $null
try { $domainRaw = Get-Content -LiteralPath $DomainContextPath -Raw | ConvertFrom-Json }
catch {
    $result = Add-EiError -Result $result -Code 'EISC-DOMAIN-INVALID' `
        -Message "Domain-context artifact at '$DomainContextPath' is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$domainSkills = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $domainRaw -Name 'domainSkills'))

# ── Build evidence entries ────────────────────────────────────────────────────
$evidence        = [System.Collections.Generic.List[object]]::new()
$keyFileEvidenceMap = [System.Collections.Generic.Dictionary[string, string]]::new()  # rel-path -> evidenceId
$evidenceCounter = 0

function script:New-EiEvidenceId {
    $script:evidenceCounter++
    "E$($script:evidenceCounter)"
}

# 1. Story text evidence — summary and a trimmed description.
if (-not [string]::IsNullOrWhiteSpace($storySummary)) {
    $id = script:New-EiEvidenceId
    $evidence.Add([ordered]@{ id = $id; kind = 'story'; value = $storySummary; note = 'story title' })
}

if (-not [string]::IsNullOrWhiteSpace($storyDesc) -and $storyDesc -ne $storySummary) {
    $id = script:New-EiEvidenceId
    $truncated = if ($storyDesc.Length -gt 300) { $storyDesc.Substring(0, 300) + '…' } else { $storyDesc }
    $evidence.Add([ordered]@{ id = $id; kind = 'story'; value = $truncated; note = 'story description' })
}

# 2. Domain skill key files.
foreach ($skill in $domainSkills) {
    $domainId = [string](Get-EiJsonValue -InputObject $skill -Name 'domainId'     -Default '')
    $keyFiles = @(ConvertTo-EiArray (Get-EiJsonValue -InputObject $skill -Name 'keyFiles'))
    foreach ($kf in $keyFiles) {
        $file    = [string](Get-EiJsonValue -InputObject $kf -Name 'file'    -Default '')
        $purpose = [string](Get-EiJsonValue -InputObject $kf -Name 'purpose' -Default '')
        if ([string]::IsNullOrWhiteSpace($file)) { continue }

        $normFile = $file -replace '\\', '/'
        if ($keyFileEvidenceMap.ContainsKey($normFile)) { continue }

        $id   = script:New-EiEvidenceId
        $note = if ([string]::IsNullOrWhiteSpace($purpose)) { "key file for domain '$domainId'" } else { $purpose }
        $evidence.Add([ordered]@{ id = $id; kind = 'domain-skill-key-file'; value = $normFile; note = $note })
        $keyFileEvidenceMap[$normFile] = $id
    }
}

# 3. Repository file search — filenames containing terms from the story title.
$stopwords = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('this', 'that', 'with', 'from', 'when', 'where', 'what', 'which', 'will', 'have',
                'been', 'then', 'they', 'their', 'should', 'would', 'could', 'does', 'into', 'also',
                'more', 'some', 'such', 'each', 'other', 'than', 'over', 'only', 'both', 'after',
                'before', 'under', 'while', 'about', 'against', 'between'),
    [System.StringComparer]::OrdinalIgnoreCase
)

$searchTerms = @(
    ($storySummary -replace '[^A-Za-z0-9 ]', ' ') -split '\s+' |
    Where-Object { $_.Length -ge 4 -and -not $stopwords.Contains($_) } |
    Select-Object -Unique -First 10
)

if ($searchTerms.Count -gt 0 -and (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
    $termPattern = ($searchTerms | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $sourceExts  = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.cs', '.ps1', '.psm1', '.psd1', '.ts', '.tsx', '.js', '.py', '.json'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $skipPattern = [regex]'[\\/](\.git|obj|bin|node_modules|out|dist)[\\/]'

    $hits = Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $sourceExts.Contains($_.Extension) -and
            -not $skipPattern.IsMatch($_.FullName) -and
            $_.Name -match "(?i)($termPattern)"
        } | Select-Object -First 20

    foreach ($hit in $hits) {
        $rel = ($hit.FullName.Substring($RepositoryRoot.TrimEnd('\', '/').Length).TrimStart('\', '/')) -replace '\\', '/'
        if ($keyFileEvidenceMap.ContainsKey($rel)) { continue }

        $id = script:New-EiEvidenceId
        $evidence.Add([ordered]@{ id = $id; kind = 'path'; value = $rel; note = 'filename matches story terms' })
        # Repository search hits are NOT auto-promoted to proposedFiles — the model decides.
    }
}

# ── Guard: at least one evidence entry is required ────────────────────────────
if ($evidence.Count -eq 0) {
    $result = Add-EiError -Result $result -Code 'EISC-EVIDENCE-EMPTY' `
        -Message 'No evidence could be derived: story text is empty, no domain key files exist, and repository search found nothing.'
    Exit-EiResult -Result $result -Json:$Json
}

# ── Build proposedFiles from verified key files only ─────────────────────────
$proposedFiles = [System.Collections.Generic.List[object]]::new()
$relatedTests  = [System.Collections.Generic.List[object]]::new()

foreach ($normFile in @($keyFileEvidenceMap.Keys)) {
    $evidenceId = $keyFileEvidenceMap[$normFile]
    $absPath    = Join-Path $RepositoryRoot $normFile

    if (-not (Test-Path -LiteralPath $absPath)) { continue }

    if ($normFile -match '(?i)(test|spec)(s)?[\\/]|\.Tests?\.' ) {
        $relatedTests.Add([ordered]@{
            target   = $normFile
            kind     = 'targeted'
            evidence = @($evidenceId)
        })
    }
    else {
        $proposedFiles.Add([ordered]@{
            path         = $normFile
            changeIntent = 'modify'
            symbols      = @()
            evidence     = @($evidenceId)
            confidence   = 0.5
        })
    }
}

# ── Confidence: higher when we have domain-skill key file evidence ─────────────
$hasKeyFileEvidence = $keyFileEvidenceMap.Count -gt 0
$confidence = if ($hasKeyFileEvidence) { 0.5 } else { 0.3 }

# ── Rationale ─────────────────────────────────────────────────────────────────
$domainNames = @(
    $domainSkills | ForEach-Object {
        [string](Get-EiJsonValue -InputObject $_ -Name 'displayName' -Default '')
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
) -join ', '

$rationale = if ([string]::IsNullOrWhiteSpace($domainNames)) {
    "Auto-generated candidate for story '$storyId'. Evidence is preliminary; review and adjust before running New-EiProposedScope.ps1."
} else {
    "Auto-generated candidate for story '$storyId' covering domain(s): $domainNames. " +
    "Key files from the domain skill(s) provide the evidence base. " +
    "Review evidence, adjust confidence, and confirm proposedFiles before running New-EiProposedScope.ps1."
}

# ── Assemble candidate document ───────────────────────────────────────────────
# Use strongly-typed lists for all array fields so that empty arrays serialise as [] not null.
$candidateProposedFiles   = [System.Collections.Generic.List[object]]$proposedFiles
$candidateRelatedTests    = [System.Collections.Generic.List[object]]$relatedTests
$candidateEvidence        = [System.Collections.Generic.List[object]]$evidence

$candidate = [ordered]@{
    confidence      = $confidence
    rationale       = $rationale
    evidence        = $candidateEvidence
    proposedFiles   = $candidateProposedFiles
    proposedModules = [System.Collections.Generic.List[object]]::new()
    relatedTests    = $candidateRelatedTests
    protectedAreas  = [System.Collections.Generic.List[object]]::new()
    dependencies    = [System.Collections.Generic.List[object]]::new()
    excluded        = [System.Collections.Generic.List[object]]::new()
    risks           = [System.Collections.Generic.List[object]]::new()
    unresolved      = [System.Collections.Generic.List[object]]::new()
}

$candidateJson = $candidate | ConvertTo-Json -Depth 20

# ── Write output ──────────────────────────────────────────────────────────────
$written = $false

if (-not [string]::IsNullOrWhiteSpace($StateDir)) {
    $writePath = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts' 'Write-EiWorkflowArtifact.ps1'
    $writeResult = & $writePath -StateDir $StateDir -Name 'candidate' -Content $candidateJson -Json | ConvertFrom-Json
    if ($writeResult.Status -ne 'Valid') {
        $result = Add-EiError -Result $result -Code 'EISC-WRITE-FAILED' `
            -Message "Failed to write candidate artifact to '$StateDir': $(@($writeResult.Errors) -join '; ')"
        Exit-EiResult -Result $result -Json:$Json
    }
    $result = Set-EiDetail -Result $result -Name 'WrittenTo' -Value (Join-Path $StateDir 'candidate.json')
    $written = $true
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Set-Content -LiteralPath $OutputPath -Value $candidateJson -Encoding utf8
    $result = Set-EiDetail -Result $result -Name 'WrittenTo' -Value $OutputPath
    $written = $true
}

# ── Summary details ───────────────────────────────────────────────────────────
$result = Set-EiDetail -Result $result -Name 'Confidence'        -Value $confidence
$result = Set-EiDetail -Result $result -Name 'EvidenceCount'     -Value $evidence.Count
$result = Set-EiDetail -Result $result -Name 'ProposedFilesCount' -Value $proposedFiles.Count
$result = Set-EiDetail -Result $result -Name 'RelatedTestsCount'  -Value $relatedTests.Count

Exit-EiResult -Result $result -Json:$Json
