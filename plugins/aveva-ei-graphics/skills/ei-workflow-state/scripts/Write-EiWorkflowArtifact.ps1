#!/usr/bin/env pwsh
<#
.SYNOPSIS
Write a schema-validated EI Graphics workflow artifact into the story state directory.

.DESCRIPTION
Every lifecycle stage persists its result through this script so that the next stage consumes an
artifact rather than narrative context. Artifacts whose schema is not implemented yet are blocked.

.OUTPUTS
PSCustomObject with Status, Errors, Warnings and Details.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateDir,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
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

if ($entry.status -ne 'active' -or [string]::IsNullOrWhiteSpace([string]$entry.schema)) {
    $result = Add-EiError -Result $result -Code 'EIWF-SCHEMA-PENDING' -Message "Artifact '$Name' is reserved for implementation phase $($entry.implementedInPhase) and has no schema yet. Writing it now would create unvalidated state."
    Exit-EiResult -Result $result -Json:$Json
}

if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    $result = Add-EiError -Result $result -Code 'EIWF-STATE-DIR-MISSING' -Message "State directory '$StateDir' does not exist. Initialise the workflow first."
    Exit-EiResult -Result $result -Json:$Json
}

try {
    $null = $Content | ConvertFrom-Json
}
catch {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-INVALID' -Message "Artifact content is not valid JSON: $($_.Exception.Message)"
    Exit-EiResult -Result $result -Json:$Json
}

$schemaCheck = Test-EiJsonAgainstSchema -Content $Content -SchemaPath (Join-Path (Get-EiSchemaRoot) $entry.schema)
if (-not $schemaCheck.IsValid) {
    $result = Add-EiError -Result $result -Code 'EIWF-ARTIFACT-SCHEMA' -Message "Artifact '$Name' failed schema validation: $(@($schemaCheck.Errors) -join '; ')"
    Exit-EiResult -Result $result -Json:$Json
}

$fileName = Resolve-EiArtifactFileName -Entry $entry -Version $Version
$artifactPath = Join-Path $StateDir $fileName
Set-Content -LiteralPath $artifactPath -Value $Content -Encoding utf8

$result = Set-EiDetail -Result $result -Name 'Path' -Value $artifactPath
$result = Set-EiDetail -Result $result -Name 'Owner' -Value $entry.owner
$result = Set-EiDetail -Result $result -Name 'Version' -Value $(if ($entry.versioned) { $Version } else { $null })

Exit-EiResult -Result $result -Json:$Json
