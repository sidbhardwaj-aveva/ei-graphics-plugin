[CmdletBinding()]
param(
    [string[]]$ChangedFiles = @(),
    [string[]]$ChangedProjects = @(),
    [string]$SolutionPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LayerCategory {
    param([string]$Path)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    if ($name -match '^Aveva\.EI\.(DomainModels|DomainServices)$') {
        return 'Domain'
    }

    if ($name -match '^Aveva\.EI\.(Commands|DbEventManager)$') {
        return 'Application'
    }

    if ($name -match '^Aveva\.EI\.(UI|Ui\.CoreDependent|3DPanelDesign|CanvasDrawings|Excel|Addin|Configuration\.Addin|DbEventsLoad\.Addin)$') {
        return 'Presentation'
    }

    return 'Unknown'
}

function Test-IsPresentationReference {
    param([string]$ProjectReference)

    return $ProjectReference -match 'Aveva\.EI\.(UI|Ui\.CoreDependent|3DPanelDesign|CanvasDrawings|Excel|Addin|Configuration\.Addin|DbEventsLoad\.Addin)\.csproj$'
}

function New-Finding {
    param(
        [string]$Code,
        [string]$Severity,
        [string]$Path,
        [string]$Message
    )

    [PSCustomObject]@{
        Code = $Code
        Severity = $Severity
        Path = $Path
        Message = $Message
    }
}

$projectCandidates = [System.Collections.Generic.List[string]]::new()
foreach ($projectPath in $ChangedProjects) {
    if (-not [string]::IsNullOrWhiteSpace($projectPath)) {
        $projectCandidates.Add($projectPath)
    }
}

foreach ($changedFile in $ChangedFiles) {
    if (-not [string]::IsNullOrWhiteSpace($changedFile) -and [System.IO.Path]::GetExtension($changedFile) -ieq '.csproj') {
        $projectCandidates.Add($changedFile)
    }
}

$projectPaths = @($projectCandidates | Select-Object -Unique)

$result = [ordered]@{
    status = 'pass'
    violations = [System.Collections.Generic.List[object]]::new()
    reviewFlags = [System.Collections.Generic.List[object]]::new()
    affectedLayers = [System.Collections.Generic.List[string]]::new()
    requiredActions = [System.Collections.Generic.List[string]]::new()
}

if ((@($ChangedFiles).Count -eq 0) -and ($projectPaths.Count -eq 0) -and [string]::IsNullOrWhiteSpace($SolutionPath)) {
    $result.status = 'needs-manual-review'
    $result.requiredActions.Add('Provide changed files or project paths for validation.')
}

foreach ($projectPath in $projectPaths) {
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $result.reviewFlags.Add((New-Finding -Code 'EILG000' -Severity 'ManualReview' -Path $projectPath -Message 'Project path could not be read for validation.'))
        continue
    }

    $layer = Get-LayerCategory -Path $projectPath
    if ($layer -ne 'Unknown' -and -not $result.affectedLayers.Contains($layer)) {
        $result.affectedLayers.Add($layer)
    }

    if ($layer -notin @('Domain', 'Application')) {
        continue
    }

    $content = Get-Content -LiteralPath $projectPath -Raw
    $projectReferences = [regex]::Matches($content, '<ProjectReference\s+Include="([^"]+)"')
    foreach ($match in $projectReferences) {
        $referencePath = $match.Groups[1].Value
        if (Test-IsPresentationReference -ProjectReference $referencePath) {
            $result.violations.Add((New-Finding -Code 'EILG001' -Severity 'Block' -Path $projectPath -Message "${layer} project references presentation project '$referencePath'."))
            $result.requiredActions.Add('Remove cross-layer presentation references from domain or application projects.')
        }
    }
}

foreach ($changedFile in $ChangedFiles) {
    if ([string]::IsNullOrWhiteSpace($changedFile)) {
        continue
    }

    if ($changedFile -match '(ClassUris|AttributeUris)\.cs$') {
        $result.reviewFlags.Add((New-Finding -Code 'EILG002' -Severity 'ManualReview' -Path $changedFile -Message 'Vocabulary or schema mapping file changed and requires SME review.'))
        $result.requiredActions.Add('Provide migration or compatibility rationale for EI vocabulary and mapping changes.')
    }

    if ($changedFile -match '(^|[\\/])(bin|obj|x64)([\\/]|$)' -or $changedFile -match '(^|[\\/])(Debug|Release)([\\/]|$)' -or $changedFile -match '\.(dll|exe|pdb|cache)$') {
        $result.reviewFlags.Add((New-Finding -Code 'EILG004' -Severity 'Block' -Path $changedFile -Message 'Committed build or debug artifact detected in change set.'))
        $result.requiredActions.Add('Remove generated or debug artifacts from the change set.')
    }

    if ((Test-Path -LiteralPath $changedFile) -and ([System.IO.Path]::GetExtension($changedFile) -in @('.cs', '.csx', '.ps1'))) {
        $content = Get-Content -LiteralPath $changedFile -Raw
        if ($content -match '\[(ClassMapping|PropertyMapping)\]') {
            $result.reviewFlags.Add((New-Finding -Code 'EILG002' -Severity 'ManualReview' -Path $changedFile -Message 'Class or property mapping attribute change detected and requires SME review.'))
            $result.requiredActions.Add('Provide impacted service or repository list for mapping changes.')
        }
        if ($content -match 'catch\s*\(\s*Exception(?:\s+\$?\w+)?\s*\)') {
            $result.reviewFlags.Add((New-Finding -Code 'EILG003' -Severity 'Block' -Path $changedFile -Message 'Broad catch(Exception) handling detected.'))
            $result.requiredActions.Add('Replace broad catch(Exception) with narrower exception handling or explicit reviewed fallback logic.')
        }
    }
}

if ($result.violations.Count -gt 0 -or @($result.reviewFlags | Where-Object Severity -eq 'Block').Count -gt 0) {
    $result.status = 'blocked'
}
elseif (@($result.reviewFlags | Where-Object Severity -eq 'ManualReview').Count -gt 0 -and $result.status -eq 'pass') {
    $result.status = 'needs-manual-review'
}

$output = [PSCustomObject]$result

if ($Json) {
    $output | ConvertTo-Json -Depth 6
}
else {
    $output
}

if ($result.status -eq 'pass') {
    exit 0
}

exit 1