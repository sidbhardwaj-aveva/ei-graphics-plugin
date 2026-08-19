[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Term,

    [string]$ContextText = '',

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dataPath = Join-Path $PSScriptRoot '..' 'data' 'vocabulary-map.json'
$data = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json -Depth 10

$searchText = (($Term + ' ' + $ContextText).Trim()).ToLowerInvariant()
$matched = @(
    $data.terms | Where-Object {
        $entry = $_
        $entry.term.ToLowerInvariant() -eq $Term.ToLowerInvariant() -or
        $searchText.Contains($entry.term.ToLowerInvariant()) -or
        @($entry.aliases | Where-Object { $searchText.Contains($_.ToLowerInvariant()) }).Count -gt 0
    }
)

$ambiguities = [System.Collections.Generic.List[string]]::new()
foreach ($ambiguous in $data.ambiguousTerms) {
    if ($searchText.Contains($ambiguous.term.ToLowerInvariant())) {
        foreach ($alternative in $ambiguous.alternatives) {
            if (-not $ambiguities.Contains($alternative)) {
                $ambiguities.Add($alternative)
            }
        }
    }
}

$matchedUris = [System.Collections.Generic.List[string]]::new()
$domainModels = [System.Collections.Generic.List[string]]::new()
$repositoryInterfaces = [System.Collections.Generic.List[string]]::new()
$services = [System.Collections.Generic.List[string]]::new()
$commands = [System.Collections.Generic.List[string]]::new()
$confidenceValues = [System.Collections.Generic.List[double]]::new()

foreach ($entry in $matched) {
    foreach ($value in $entry.matchedUris) { if (-not $matchedUris.Contains($value)) { $matchedUris.Add($value) } }
    foreach ($value in $entry.domainModels) { if (-not $domainModels.Contains($value)) { $domainModels.Add($value) } }
    foreach ($value in $entry.repositoryInterfaces) { if (-not $repositoryInterfaces.Contains($value)) { $repositoryInterfaces.Add($value) } }
    foreach ($value in $entry.services) { if (-not $services.Contains($value)) { $services.Add($value) } }
    foreach ($value in $entry.commands) { if (-not $commands.Contains($value)) { $commands.Add($value) } }
    $confidenceValues.Add([double]$entry.confidence)
}

$confidence = if ($confidenceValues.Count -gt 0) {
    [Math]::Round((($confidenceValues | Measure-Object -Average).Average), 2)
}
else {
    0.0
}

$result = [PSCustomObject]@{
    term = $Term
    matchedUris = @($matchedUris)
    domainModels = @($domainModels)
    repositoryInterfaces = @($repositoryInterfaces)
    services = @($services)
    commands = @($commands)
    ambiguities = @($ambiguities)
    confidence = $confidence
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

exit 0
