#!/usr/bin/env pwsh
<#
.SYNOPSIS
Read and re-validate an EI Graphics workflow artifact before the next stage consumes it.

.DESCRIPTION
The workflow re-reads every artifact it just wrote. A missing or schema-invalid artifact is a BLOCK
state, never an implicit pass.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details (Details.Artifact holds the payload).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][string]$Name,
    [int]$Version = 1,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/helpers/EiWorkflowState.ps1"

$result = New-EiResult
$result = Set-EiDetail -Result $result -Name 'Artifact' -Value $Name

$entry = Get-EiArtifactEntry -Name $Name
if ($null -eq $entry) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-UNKNOWN' -Message "Artifact '$Name' is not declared in the artifact registry."
    Exit-EiResult -Result $result -Json:$Json
}

$fileName = Resolve-EiArtifactFileName -Entry $entry -Version $Version
$artifactPath = Join-Path $StateDir $fileName
$result = Set-EiDetail -Result $result -Name 'Path' -Value $artifactPath

if (-not (Test-Path -LiteralPath $artifactPath)) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-MISSING' -Message "Required artifact '$Name' was not found at '$artifactPath'."
    Exit-EiResult -Result $result -Json:$Json
}

$content = Get-Content -LiteralPath $artifactPath -Raw

try {
    $artifact = $content | ConvertFrom-Json
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-INVALID' -Message "Artifact '$Name' is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

if ([string]::IsNullOrWhiteSpace([string]$entry.schema)) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCHEMA-PENDING' -Message "Artifact '$Name' has no schema yet, so its content cannot be trusted."
    Exit-EiResult -Result $result -Json:$Json
}

$schemaCheck = Test-EiJsonAgainstSchema -Content $content -SchemaPath (Join-Path (Get-EiSchemaRoot) $entry.schema)
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-SCHEMA' -Message "Artifact '$Name' failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$result = Set-EiDetail -Result $result -Name 'Owner' -Value $entry.owner
$result = Set-EiDetail -Result $result -Name 'Artifact' -Value $Name
$result = Set-EiDetail -Result $result -Name 'Payload' -Value $artifact

Exit-EiResult -Result $result -Json:$Json
