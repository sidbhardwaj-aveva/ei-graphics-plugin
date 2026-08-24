#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run the `domain-context` lifecycle stage: resolve candidate story terms into EI domain packs.

.DESCRIPTION
This is the stage wrapper, not a second vocabulary implementation. Every lookup is delegated to
`Invoke-EiVocabularyNavigator.ps1`, which owns the vocabulary map, alias matching and confidence.
This script decides only which of the caller's candidate terms are allowed to survive.

The split is deliberate and matches the scope layer: the caller proposes candidate terms, the script
disposes of them against `references/domain-pack-policy.json`. A term survives three independent
checks -- the story actually mentions it, the navigator resolves it to at least one URI, and its
confidence clears the floor. Terms that fail any of those are recorded in `unresolvedTerms` rather
than dropped, so the narrowing stays auditable.

The navigator is called with the term alone and never with the story text. Passing the story as
context would make every candidate match the union of everything the story mentions, which would
hand the scope resolver a domain context far wider than the terms it was given. The story text is
used only to prove the term belongs to this story.

After vocabulary resolution, the domain skill registry is consulted to detect which domain SKILL.md
files are relevant to the story. Matched skills contribute a `domainSkills` array to the artifact:
each entry carries the skill's Key Files and a note that those files are candidate evidence, not
automatic scope. If no domain is detected the array is empty and no gate is raised; vocabulary
resolution alone is sufficient to pass the stage.

The stage fails closed. If too few terms resolve, or the aggregate confidence is below the floor,
the stage is blocked instead of writing a thin domain context that would let the scope resolver
guess at the domain.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Payload holds the artifact).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [string[]]$Terms = @(),
    [string]$PolicyPath = '',
    [string]$RegistryPath = '',
    [string]$StageId = 'domain-context',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateScripts = Join-Path $PSScriptRoot '..' '..' 'ei-workflow-state' 'scripts'
. (Join-Path $stateScripts 'helpers' 'EiWorkflowState.ps1')

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'StateDir' -Value $StateDir
$result = Set-EiDetail -Result $result -Name 'StageId' -Value $StageId

$stagePath = Join-Path $stateScripts 'Set-EiWorkflowStage.ps1'
$writePath = Join-Path $stateScripts 'Write-EiWorkflowArtifact.ps1'
$readPath = Join-Path $stateScripts 'Read-EiWorkflowArtifact.ps1'
$navigatorPath = Join-Path $PSScriptRoot 'Invoke-EiVocabularyNavigator.ps1'

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot '..' 'references' 'domain-pack-policy.json'
}

if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    $RegistryPath = Join-Path $PSScriptRoot '..' 'references' 'domain-skill-registry.json'
}

$domainSkillReaderPath = Join-Path $PSScriptRoot 'helpers' 'Read-EiDomainSkillContext.ps1'

function Block-EiDomainContextStage {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Remediation
    )

    $blocked = & $stagePath -StateDir $StateDir -StageId $StageId -Action block `
        -BlockCode $Code -BlockMessage $Message -Remediation $Remediation -Json | ConvertFrom-Json

    $updated = Add-EiError -Result $Result -Code $Code -Message $Message
    if ($blocked.Status -ne 'Valid') {
        $updated = Add-EiWarning -Result $updated -Message "The stage could not be recorded as blocked: $(@($blocked.Errors) -join '; ')"
    }

    Set-EiDetail -Result $updated -Name 'StageStatus' -Value 'blocked'
}

if (-not (Test-Path -LiteralPath $PolicyPath)) {
    $result = Add-EiError -Result $result -Code 'EIVN-POLICY-MISSING' -Message "Domain-pack policy was not found at '$PolicyPath'. The gate cannot be evaluated without its thresholds."
    Exit-EiResult -Result $result -Json:$Json
}

$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$thresholds = $policy.thresholds

$statePayload = & $readPath -StateDir $StateDir -Name 'workflow-state' -Json | ConvertFrom-Json
if ($statePayload.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STATE-UNREADABLE' -Message "Workflow state could not be read from '$StateDir': $(@($statePayload.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$storyId = $statePayload.Details.Payload.storyId
$result = Set-EiDetail -Result $result -Name 'StoryId' -Value $storyId

# The story text is read from the sealed ado artifact rather than passed in, so the domain context
# can only ever describe the story the run actually intook.
$adoArtifact = & $readPath -StateDir $StateDir -Name 'ado' -Json | ConvertFrom-Json
if ($adoArtifact.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-ADO-UNREADABLE' -Message "The ado artifact could not be read, so there is no story to resolve terms against: $(@($adoArtifact.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$contextText = $adoArtifact.Details.Payload.description

$candidates = @(@($Terms) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
$result = Set-EiDetail -Result $result -Name 'CandidateTerms' -Value $candidates

$started = & $stagePath -StateDir $StateDir -StageId $StageId -Action start -Json | ConvertFrom-Json
if ($started.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STAGE-NOT-STARTED' -Message "Stage '$StageId' could not be started: $(@($started.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

if (@($candidates).Count -eq 0) {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-NO-CANDIDATE-TERMS' `
        -Message 'No candidate domain terms were supplied, so there is nothing to resolve.' `
        -Remediation 'Name the EI domain terms the story is about via -Terms and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$packs = [System.Collections.Generic.List[object]]::new()
$ambiguities = [System.Collections.Generic.List[object]]::new()
$unresolved = [System.Collections.Generic.List[string]]::new()

foreach ($candidate in $candidates) {
    $lookupRaw = & $navigatorPath -Term $candidate -Json
    $lookup = $null
    try { $lookup = ($lookupRaw -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { $lookup = $null }

    if ($null -eq $lookup) {
        $unresolved.Add($candidate)
        continue
    }

    if (@($lookup.ambiguities).Count -gt 0) {
        $ambiguities.Add([ordered]@{ term = $candidate; alternatives = @($lookup.ambiguities) })
    }

    $mentioned = $contextText.IndexOf($candidate, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    $confidence = [double]$lookup.confidence
    if (-not $mentioned -or @($lookup.matchedUris).Count -eq 0 -or $confidence -lt [double]$thresholds.minTermConfidence) {
        $unresolved.Add($candidate)
        continue
    }

    $packs.Add([ordered]@{
            term                 = $candidate
            matchedUris          = @($lookup.matchedUris)
            domainModels         = @($lookup.domainModels)
            repositoryInterfaces = @($lookup.repositoryInterfaces)
            services             = @($lookup.services)
            commands             = @($lookup.commands)
            confidence           = [math]::Round($confidence, 2)
        })
}

$result = Set-EiDetail -Result $result -Name 'ResolvedTerms' -Value @($packs | ForEach-Object { $_.term })
$result = Set-EiDetail -Result $result -Name 'UnresolvedTerms' -Value @($unresolved)

if ($packs.Count -lt [int]$thresholds.minResolvedTerms) {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-DOMAIN-PACK-UNRESOLVED' `
        -Message "Only $($packs.Count) of $(@($candidates).Count) candidate terms resolved to known EI vocabulary; the policy requires at least $($thresholds.minResolvedTerms)." `
        -Remediation 'Correct the candidate terms, or extend the vocabulary map, and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$aggregate = [math]::Round((($packs | ForEach-Object { [double]$_.confidence } | Measure-Object -Average).Average), 2)
$result = Set-EiDetail -Result $result -Name 'Confidence' -Value $aggregate

if ($aggregate -lt [double]$thresholds.minAggregateConfidence) {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-CONFIDENCE-LOW' `
        -Message "Resolved domain context confidence $aggregate is below the floor of $($thresholds.minAggregateConfidence)." `
        -Remediation 'Disambiguate the candidate terms so they match the vocabulary map directly, then re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

# ── Domain skill injection ────────────────────────────────────────────────────
# Detect which domain SKILL.md files are relevant to this story and inject their
# Key Files as candidate evidence. No domain match is not a failure.
$domainSkills = [System.Collections.Generic.List[object]]::new()
$storySummary     = [string]$adoArtifact.Details.Payload.summary
$storyDescription = [string]$adoArtifact.Details.Payload.description
$storySearchText  = (($storySummary + ' ' + $storyDescription + ' ' + $contextText).Trim())

if (Test-Path -LiteralPath $RegistryPath) {
    try {
        $registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
        $pluginRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..' '..')).Path

        foreach ($domain in @($registry.domains)) {
            $matched = $false
            foreach ($term in @($domain.detectionTerms)) {
                if ($storySearchText.IndexOf([string]$term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $matched = $true
                    break
                }
            }
            if (-not $matched) { continue }

            $domainSkillPathRaw = [string]$domain.skillPath
            $skillAbsPath = if ([System.IO.Path]::IsPathRooted($domainSkillPathRaw)) {
                $domainSkillPathRaw
            } else {
                Join-Path $pluginRoot $domainSkillPathRaw
            }
            try {
                $ctx = & $domainSkillReaderPath `
                    -SkillPath $skillAbsPath `
                    -DomainId ([string]$domain.id) `
                    -DisplayName ([string]$domain.displayName)
                $domainSkills.Add($ctx)
            }
            catch {
                $result = Add-EiWarning -Result $result `
                    -Message "Could not load domain skill '$($domain.id)' from '$skillAbsPath': $($_.Exception.Message)"
            }
        }
    }
    catch {
        $result = Add-EiWarning -Result $result `
            -Message "Domain skill registry could not be parsed from '$RegistryPath': $($_.Exception.Message)"
    }
}
else {
    $result = Add-EiWarning -Result $result `
        -Message "Domain skill registry was not found at '$RegistryPath'; no domain skill context will be injected."
}

$result = Set-EiDetail -Result $result -Name 'DetectedDomains' -Value @($domainSkills | ForEach-Object { $_.domainId })

$artifact = [ordered]@{
    schemaVersion   = $script:EiStateSchemaVersion
    source          = 'ei-vocabulary-navigator'
    storyId         = $storyId
    generatedAt     = Get-EiUtcTimestamp
    confidence      = $aggregate
    terms           = @($packs | ForEach-Object { $_.term })
    domainPacks     = @($packs)
    ambiguities     = @($ambiguities)
    unresolvedTerms = @($unresolved)
    domainSkills    = @($domainSkills)
}

$written = & $writePath -StateDir $StateDir -Name 'domain-context' -Content ($artifact | ConvertTo-Json -Depth 10) -Json | ConvertFrom-Json
if ($written.Status -ne 'Valid') {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-ARTIFACT-UNWRITABLE' `
        -Message "The domain-context artifact could not be persisted: $(@($written.Errors) -join '; ')" `
        -Remediation 'Fix the reported schema or state-directory problem and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

# The gate passes on evidence, not on intent: the persisted artifact has to read back and validate.
$readBack = & $readPath -StateDir $StateDir -Name 'domain-context' -Json | ConvertFrom-Json
if ($readBack.Status -ne 'Valid') {
    $result = Block-EiDomainContextStage -Result $result -Code 'EIVN-ARTIFACT-ABSENT' `
        -Message "The domain-context artifact did not read back after being written: $(@($readBack.Errors) -join '; ')" `
        -Remediation 'Inspect the state directory for a truncated or hand-edited domain-context.json and re-run the domain-context stage.'
    Exit-EiResult -Result $result -Json:$Json
}

$completed = & $stagePath -StateDir $StateDir -StageId $StageId -Action complete -GateResult pass -Json | ConvertFrom-Json
if ($completed.Status -ne 'Valid') {
    $result = Add-EiError -Result $result -Code 'EIVN-STAGE-NOT-COMPLETED' -Message "Stage '$StageId' could not be completed: $(@($completed.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'StageStatus' -Value 'complete'
$result = Set-EiDetail -Result $result -Name 'GateResult' -Value 'pass'
$result = Set-EiDetail -Result $result -Name 'WorkflowStatus' -Value $completed.Details.WorkflowStatus
$result = Set-EiDetail -Result $result -Name 'Path' -Value $written.Details.Path
$result = Set-EiDetail -Result $result -Name 'Payload' -Value $readBack.Details.Payload

Exit-EiResult -Result $result -Json:$Json
