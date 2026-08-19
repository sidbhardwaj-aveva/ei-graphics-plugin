[CmdletBinding()]
param(
    [string]$BugContextJson = '',
    [string]$DiagnosisJson = '',
    [string]$VocabularyMappingsJson = '',
    [string]$ArchitectureFindingsJson = '',
    [string]$ReviewFindingsJson = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-JsonInput {
    param(
        [string]$Value,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return ($Value | ConvertFrom-Json -Depth 20)
    }
    catch {
        throw "$Name is not valid JSON."
    }
}

$bugContext = Convert-JsonInput -Value $BugContextJson -Name 'BugContextJson'
$diagnosis = Convert-JsonInput -Value $DiagnosisJson -Name 'DiagnosisJson'
$vocabularyMappings = Convert-JsonInput -Value $VocabularyMappingsJson -Name 'VocabularyMappingsJson'
$architectureFindings = Convert-JsonInput -Value $ArchitectureFindingsJson -Name 'ArchitectureFindingsJson'
$reviewFindings = Convert-JsonInput -Value $ReviewFindingsJson -Name 'ReviewFindingsJson'

if ($null -eq $bugContext -or $null -eq $diagnosis) {
    $result = [PSCustomObject]@{
        status = 'blocked'
        specSummary = ''
        functionalRequirements = @()
        nonFunctionalConstraints = @()
        risksAndAssumptions = @()
        testExpectations = @()
        handoffChecklist = @('Provide bugContext and diagnosis evidence in JSON form.')
        nextAction = 'Collect required diagnosis evidence, then rerun.'
    }

    if ($Json) { $result | ConvertTo-Json -Depth 10 } else { $result }
    exit 1
}

$confidence = 0.0
if ($diagnosis.PSObject.Properties['confidence']) {
    try {
        $confidence = [double]$diagnosis.confidence
    }
    catch {
        $confidence = 0.0
    }
}

$status = 'ready-for-implementation'
if ($confidence -lt 0.5) {
    $status = 'needs-manual-review'
}

$affectedAreas = @()
if ($diagnosis.PSObject.Properties['affectedAreas']) {
    $affectedAreas = @($diagnosis.affectedAreas)
}

$title = if ($bugContext.PSObject.Properties['title']) { [string]$bugContext.title } else { '' }
$bugId = if ($bugContext.PSObject.Properties['bugId']) { [string]$bugContext.bugId } else { '' }

$functionalRequirements = [System.Collections.Generic.List[string]]::new()
$functionalRequirements.Add('Reproduce and isolate the reported EI issue deterministically before code changes.')
if (-not [string]::IsNullOrWhiteSpace($bugId)) {
    $functionalRequirements.Add("Maintain traceability to work item $bugId.")
}
foreach ($area in $affectedAreas) {
    if (-not [string]::IsNullOrWhiteSpace([string]$area)) {
        $functionalRequirements.Add("Validate behavior for affected area: $area.")
    }
}

$nonFunctionalConstraints = [System.Collections.Generic.List[string]]::new()
$nonFunctionalConstraints.Add('Preserve legacy-safe behavior and avoid architecture boundary violations.')
$nonFunctionalConstraints.Add('All deterministic script changes must include focused Pester coverage.')

$risksAndAssumptions = [System.Collections.Generic.List[string]]::new()
if ($confidence -lt 0.5) {
    $risksAndAssumptions.Add('Diagnosis confidence is low; assumptions require manual validation before implementation.')
}
if ($null -ne $vocabularyMappings -and $vocabularyMappings.PSObject.Properties['ambiguities']) {
    if (@($vocabularyMappings.ambiguities).Count -gt 0) {
        $risksAndAssumptions.Add('Vocabulary mapping ambiguities detected; confirm domain term intent with SME.')
    }
}
if ($null -ne $architectureFindings -and $architectureFindings.PSObject.Properties['violations']) {
    if (@($architectureFindings.violations).Count -gt 0) {
        $risksAndAssumptions.Add('Architecture violations present; resolve before implementation completion.')
    }
}
if ($null -ne $reviewFindings -and $reviewFindings.PSObject.Properties['requiresSmeReviewFindings']) {
    if (@($reviewFindings.requiresSmeReviewFindings).Count -gt 0) {
        $risksAndAssumptions.Add('SME review required for domain-risk changes.')
    }
}

$testExpectations = [System.Collections.Generic.List[string]]::new()
if ($diagnosis.PSObject.Properties['relatedTests']) {
    foreach ($testRef in @($diagnosis.relatedTests)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$testRef)) {
            $testExpectations.Add("Validate related test path: $testRef")
        }
    }
}
if ($testExpectations.Count -eq 0) {
    $testExpectations.Add('Add or update focused deterministic tests for affected behavior.')
}

$handoffChecklist = [System.Collections.Generic.List[string]]::new()
$handoffChecklist.Add('Include reproduction evidence and expected behavior delta in PR description.')
$handoffChecklist.Add('Include architecture/risk gate outcomes and required SME evidence.')
$handoffChecklist.Add('Include focused test evidence for deterministic slices.')

$summaryTitle = if ([string]::IsNullOrWhiteSpace($title)) { 'EI bug diagnosis handoff' } else { $title }
$specSummary = "Implementation handoff for $summaryTitle"

$nextAction = if ($status -eq 'needs-manual-review') {
    'Raise confidence with additional diagnosis evidence and SME confirmation before implementation.'
}
else {
    'Proceed with implementation tasks using this handoff as the execution baseline.'
}

$result = [PSCustomObject]@{
    status = $status
    specSummary = $specSummary
    functionalRequirements = @($functionalRequirements | Select-Object -Unique)
    nonFunctionalConstraints = @($nonFunctionalConstraints | Select-Object -Unique)
    risksAndAssumptions = @($risksAndAssumptions | Select-Object -Unique)
    testExpectations = @($testExpectations | Select-Object -Unique)
    handoffChecklist = @($handoffChecklist | Select-Object -Unique)
    nextAction = $nextAction
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
}
else {
    $result
}

if ($status -eq 'ready-for-implementation') {
    exit 0
}

exit 1
