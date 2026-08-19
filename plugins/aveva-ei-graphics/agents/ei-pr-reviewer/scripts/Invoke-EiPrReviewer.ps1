[CmdletBinding()]
param(
    [string[]]$ChangedFiles = @(),
    [string]$PrSanityPath = '',
    [string[]]$ChangedAreas = @(),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Finding {
    param(
        [string]$Gate,
        [string]$Severity,
        [string]$Path,
        [string]$Message
    )

    [PSCustomObject]@{
        gate = $Gate
        severity = $Severity
        path = $Path
        message = $Message
    }
}

function Test-IsDomainRiskPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalized = ($Path -replace '\\', '/').ToLowerInvariant()
    return $normalized -match '(wiringrule|cable|core|voltage|phase|distributionboard|terminationdrawing|classuris|attributeuris)'
}

function Test-IsDomainRiskContent {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $false
    }

    $text = $Content.ToLowerInvariant()
    return $text -match '(wiring\s*rule|cable|core|voltage|phase\s*naming|distribution\s*board|termination\s*drawing|classmapping|propertymapping)'
}

$blockingFindings = [System.Collections.Generic.List[object]]::new()
$advisoryFindings = [System.Collections.Generic.List[object]]::new()
$requiresSmeReviewFindings = [System.Collections.Generic.List[object]]::new()
$requiredEvidence = [System.Collections.Generic.List[string]]::new()

$normalizedAreas = @($ChangedAreas | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$hasHighRisk = $false

if (@($ChangedFiles).Count -eq 0) {
    $requiredEvidence.Add('Provide changed file paths to run EI PR review gates.')
    $result = [PSCustomObject]@{
        status = 'needs-manual-review'
        blockingFindings = @()
        advisoryFindings = @()
        requiresSmeReviewFindings = @()
        requiredEvidence = @($requiredEvidence)
        recommendedNextAction = 'Provide changed files and rerun reviewer.'
    }

    if ($Json) { $result | ConvertTo-Json -Depth 8 } else { $result }
    exit 1
}

foreach ($file in $ChangedFiles) {
    if ([string]::IsNullOrWhiteSpace($file)) {
        continue
    }

    $isHighRiskPath = Test-IsDomainRiskPath -Path $file
    if ($isHighRiskPath) {
        $hasHighRisk = $true
    }

    $content = ''
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $content = Get-Content -LiteralPath $file -Raw
        if (Test-IsDomainRiskContent -Content $content) {
            $hasHighRisk = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($content) -and $content -match '(?im)\b(TODO|HACK|FIXME|WORKAROUND)\b') {
        $severity = if ($isHighRiskPath -or $hasHighRisk) { 'Block' } else { 'Advisory' }
        $finding = New-Finding -Gate 'R-004' -Severity $severity -Path $file -Message 'New TODO/HACK/FIXME/WORKAROUND marker detected in changed file.'
        if ($severity -eq 'Block') {
            $blockingFindings.Add($finding)
            $requiredEvidence.Add('Provide linked ADO tracking or remove TODO/HACK/FIXME/WORKAROUND from high-risk changes.')
        }
        else {
            $advisoryFindings.Add($finding)
            $requiredEvidence.Add('Provide linked ADO tracking for new TODO/HACK/FIXME/WORKAROUND markers.')
        }
    }
}

if ($hasHighRisk -or (@($normalizedAreas | Where-Object { $_ -match '(?i)(wiring|cable|core|voltage|phase|distribution)' }).Count -gt 0)) {
    $requiresSmeReviewFindings.Add((New-Finding -Gate 'R-005' -Severity 'ManualReview' -Path '' -Message 'Domain-risk change detected; SME review required for electrical logic-sensitive areas.'))
    $requiredEvidence.Add('Provide SME review, risk summary, and impacted test/sanity path for domain-risk changes.')
}

if ($hasHighRisk -and [string]::IsNullOrWhiteSpace($PrSanityPath)) {
    $blockingFindings.Add((New-Finding -Gate 'R-006' -Severity 'Block' -Path '' -Message 'High-risk area changed without a PR sanity or regression path statement.'))
    $requiredEvidence.Add('Provide expected PR sanity category or downstream QA regression path.')
}

$status = 'pass'
if ($blockingFindings.Count -gt 0) {
    $status = 'blocked'
}
elseif ($requiresSmeReviewFindings.Count -gt 0) {
    $status = 'needs-manual-review'
}

$recommendedNextAction = switch ($status) {
    'blocked' { 'Resolve blocking review gates before requesting PR approval.' }
    'needs-manual-review' { 'Obtain SME review evidence and include sanity/test rationale in the PR description.' }
    default { 'Proceed to human PR review with advisory findings documented.' }
}

$result = [PSCustomObject]@{
    status = $status
    blockingFindings = @($blockingFindings)
    advisoryFindings = @($advisoryFindings)
    requiresSmeReviewFindings = @($requiresSmeReviewFindings)
    requiredEvidence = @($requiredEvidence | Select-Object -Unique)
    recommendedNextAction = $recommendedNextAction
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}

if ($status -eq 'pass') {
    exit 0
}

exit 1
