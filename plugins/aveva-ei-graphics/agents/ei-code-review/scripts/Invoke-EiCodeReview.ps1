[CmdletBinding()]
param(
    [string[]]$ChangedFiles = @(),
    [string[]]$ChangedAreas = @(),
    [string]$PrSanityPath = '',
    [string]$BugContextJson = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pluginRoot = Join-Path $PSScriptRoot '..' '..' '..'
$reviewerScript = Join-Path $pluginRoot 'agents' 'ei-pr-reviewer' 'scripts' 'Invoke-EiPrReviewer.ps1'

if (-not (Test-Path -LiteralPath $reviewerScript -PathType Leaf)) {
    throw "Required script not found: $reviewerScript"
}

$reviewerOutput = & $reviewerScript `
    -ChangedFiles $ChangedFiles `
    -ChangedAreas $ChangedAreas `
    -PrSanityPath $PrSanityPath `
    -Json

$reviewerResult = $null
if (-not [string]::IsNullOrWhiteSpace(($reviewerOutput -join ''))) {
    $reviewerResult = $reviewerOutput | ConvertFrom-Json -Depth 20
}

if ($null -eq $reviewerResult) {
    throw 'PR reviewer script returned empty output.'
}

$bugContext = $null
if (-not [string]::IsNullOrWhiteSpace($BugContextJson)) {
    try {
        $bugContext = $BugContextJson | ConvertFrom-Json -Depth 20
    }
    catch {
        throw 'BugContextJson is not valid JSON.'
    }
}

$prEvidencePackage = [PSCustomObject]@{
    adoLinkage = [PSCustomObject]@{
        bugId = if ($null -ne $bugContext -and $bugContext.PSObject.Properties['bugId']) { [string]$bugContext.bugId } else { '' }
        title = if ($null -ne $bugContext -and $bugContext.PSObject.Properties['title']) { [string]$bugContext.title } else { '' }
    }
    riskSummary = [PSCustomObject]@{
        blockingSignals = @($reviewerResult.blockingFindings)
        requiresSmeReview = @($reviewerResult.requiresSmeReviewFindings)
    }
    sanityPath = if ([string]::IsNullOrWhiteSpace($PrSanityPath)) { 'not-provided' } else { $PrSanityPath }
    changedAreas = @($ChangedAreas | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$result = [PSCustomObject]@{
    status = [string]$reviewerResult.status
    blockingFindings = @($reviewerResult.blockingFindings)
    advisoryFindings = @($reviewerResult.advisoryFindings)
    requiresSmeReviewFindings = @($reviewerResult.requiresSmeReviewFindings)
    requiredEvidence = @($reviewerResult.requiredEvidence)
    prEvidencePackage = $prEvidencePackage
    recommendedNextAction = [string]$reviewerResult.recommendedNextAction
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
}
else {
    $result
}

if ($result.status -eq 'pass') {
    exit 0
}

exit 1
