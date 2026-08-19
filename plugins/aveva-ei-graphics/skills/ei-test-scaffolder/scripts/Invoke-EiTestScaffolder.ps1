[CmdletBinding()]
param(
    [string]$TargetClass = '',
    [string[]]$Methods = @(),
    [string]$TestProjectPath = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ClassFile {
    param([string]$InputTarget)

    if ([string]::IsNullOrWhiteSpace($InputTarget)) {
        return ''
    }

    if (Test-Path -LiteralPath $InputTarget -PathType Leaf) {
        return (Resolve-Path -LiteralPath $InputTarget).Path
    }

    $cwd = Get-Location
    $candidateName = if ($InputTarget.EndsWith('.cs', [System.StringComparison]::OrdinalIgnoreCase)) { $InputTarget } else { "$InputTarget.cs" }

    $matches = @(Get-ChildItem -Path $cwd -Recurse -File -Filter $candidateName -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) {
        return ''
    }

    return $matches[0].FullName
}

function Get-ClassName {
    param(
        [string]$InputTarget,
        [string]$ClassFile
    )

    if (-not [string]::IsNullOrWhiteSpace($ClassFile)) {
        return [System.IO.Path]::GetFileNameWithoutExtension($ClassFile)
    }

    $trimmed = $InputTarget.Trim()
    if ($trimmed.EndsWith('.cs', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [System.IO.Path]::GetFileNameWithoutExtension($trimmed)
    }

    return $trimmed
}

function Get-ClassMethods {
    param(
        [string]$ClassFile,
        [string]$ClassName,
        [string[]]$RequestedMethods
    )

    if (@($RequestedMethods).Count -gt 0) {
        return @($RequestedMethods | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    if (-not [string]::IsNullOrWhiteSpace($ClassFile) -and (Test-Path -LiteralPath $ClassFile -PathType Leaf)) {
        $content = Get-Content -LiteralPath $ClassFile -Raw
        $pattern = 'public\s+(?:async\s+)?[A-Za-z0-9_<>\[\]\.?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('
        $methodMatches = [regex]::Matches($content, $pattern)
        $names = @()
        foreach ($m in $methodMatches) {
            $name = $m.Groups[1].Value
            if ($name -and $name -ne $ClassName -and $name -notin @('Equals', 'GetHashCode', 'ToString')) {
                $names += $name
            }
        }

        $uniqueNames = @($names | Select-Object -Unique)
        if ($uniqueNames.Count -gt 0) {
            return $uniqueNames
        }
    }

    return @('Execute')
}

function Get-ConstructorDependencyTypes {
    param(
        [string]$ClassFile,
        [string]$ClassName
    )

    if ([string]::IsNullOrWhiteSpace($ClassFile) -or -not (Test-Path -LiteralPath $ClassFile -PathType Leaf)) {
        return @()
    }

    $content = Get-Content -LiteralPath $ClassFile -Raw
    $constructorPattern = 'public\s+' + [regex]::Escape($ClassName) + '\s*\(([^)]*)\)'
    $match = [regex]::Match($content, $constructorPattern)

    if (-not $match.Success) {
        return @()
    }

    $parameterList = $match.Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($parameterList)) {
        return @()
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in ($parameterList -split ',')) {
        $part = $segment.Trim()
        if (-not $part) {
            continue
        }

        $tokens = @($part -split '\s+' | Where-Object { $_ })
        if ($tokens.Count -lt 2) {
            continue
        }

        $typeToken = $tokens[0]
        if (-not $result.Contains($typeToken)) {
            $result.Add($typeToken)
        }
    }

    return @($result)
}

if ([string]::IsNullOrWhiteSpace($TargetClass)) {
    $blocked = [PSCustomObject]@{
        status = 'blocked'
        suggestedTestNames = @()
        mockDependencies = @()
        resolverSetupRequired = $false
        outputPaths = @()
        manualAssertionsRequired = $true
    }

    if ($Json) { $blocked | ConvertTo-Json -Depth 6 } else { $blocked }
    exit 1
}

$classFile = Resolve-ClassFile -InputTarget $TargetClass
$className = Get-ClassName -InputTarget $TargetClass -ClassFile $classFile
$methodNames = @(Get-ClassMethods -ClassFile $classFile -ClassName $className -RequestedMethods $Methods)
$dependencyTypes = @(Get-ConstructorDependencyTypes -ClassFile $classFile -ClassName $className)

$suggestedTestNames = @(
    foreach ($method in $methodNames) {
        "${method}_WhenInvoked_ExpectedBehavior"
    }
)

$resolverSetupRequired = @($dependencyTypes).Count -gt 0
$outputPaths = @()

if (-not [string]::IsNullOrWhiteSpace($TestProjectPath)) {
    $outputPaths += (Join-Path $TestProjectPath ("$className.Tests.cs"))
}

if ([string]::IsNullOrWhiteSpace($TestProjectPath)) {
    $status = 'needs-manual-review'
}
else {
    $status = 'ready'
}

$result = [PSCustomObject]@{
    status = $status
    suggestedTestNames = @($suggestedTestNames)
    mockDependencies = @($dependencyTypes)
    resolverSetupRequired = $resolverSetupRequired
    outputPaths = @($outputPaths)
    manualAssertionsRequired = $true
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}

if ($status -eq 'ready') {
    exit 0
}

exit 1
