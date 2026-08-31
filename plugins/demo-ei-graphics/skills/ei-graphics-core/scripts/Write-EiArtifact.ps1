#Requires -Version 7.0
<#
.SYNOPSIS
    Checks an artifact against its schema, then writes it as JSON.

.DESCRIPTION
    Writes .ei-session-logs/<StoryId>/<ArtifactType>.json. For story-understanding and
    approved-files it stamps a hash over the canonical form of the payload. It never does that
    for ado, because ado.schema.json declares no hash property.
#>
[CmdletBinding()]
param(
    [string] $StoryId,
    [ValidateSet('story-understanding', 'approved-files', 'ado')]
    [string] $ArtifactType,
    $InputObject,
    [string] $InputJson,
    [string] $Root = '.',
    [switch] $Json,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $PSCommandPath; exit 0 }

function Write-Problem { param([string] $Message) [Console]::Error.WriteLine($Message) }

function ConvertTo-CanonicalNode {
    param($Node)
    if ($null -eq $Node) { return $null }
    if ($Node -is [string] -or $Node.GetType().IsPrimitive -or $Node -is [decimal]) { return $Node }
    if ($Node -is [System.Collections.IDictionary]) {
        $keys = [string[]] @($Node.Keys)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $sorted = [ordered]@{}
        foreach ($key in $keys) { $sorted[$key] = ConvertTo-CanonicalNode -Node $Node[$key] }
        return $sorted
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $keys = [string[]] @($Node.PSObject.Properties.Name)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $sorted = [ordered]@{}
        foreach ($key in $keys) { $sorted[$key] = ConvertTo-CanonicalNode -Node $Node.$key }
        return $sorted
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        # The comma stops PowerShell unrolling a one-item array back into a bare object.
        $items = @(foreach ($item in $Node) { ConvertTo-CanonicalNode -Node $item })
        return , $items
    }
    $Node
}

function Get-CanonicalHash {
    param([Parameter(Mandatory)] $Payload)
    $copy = ConvertTo-CanonicalNode -Node $Payload
    $copy.Remove('hash')
    $compact = $copy | ConvertTo-Json -Depth 30 -Compress
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($compact)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { 'sha256:' + [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

if (-not $StoryId) { Write-Problem 'No -StoryId was given. Pass the story number the artifact belongs to.'; exit 1 }
if (-not $ArtifactType) { Write-Problem 'No -ArtifactType was given. Use story-understanding, approved-files or ado.'; exit 1 }
if ($null -eq $InputObject -and -not $InputJson) {
    Write-Problem 'No payload was given. Pass an object through -InputObject, or text through -InputJson.'
    exit 1
}

$payload = $InputObject
if ($InputJson) {
    try { $payload = $InputJson | ConvertFrom-Json -AsHashtable }
    catch { Write-Problem "The text passed to -InputJson is not valid JSON. $($_.Exception.Message)"; exit 1 }
}

$canonical = ConvertTo-CanonicalNode -Node $payload
if ($ArtifactType -ne 'ado') { $canonical['hash'] = Get-CanonicalHash -Payload $payload }

$schemaPath = Join-Path $PSScriptRoot '..' 'schemas' "$ArtifactType.schema.json"
if (-not (Test-Path -LiteralPath $schemaPath)) {
    Write-Problem "The schema for '$ArtifactType' is missing. Expected it at: $schemaPath"
    exit 1
}

$body = $canonical | ConvertTo-Json -Depth 30
$schemaErrors = @()
try { $null = $body | Test-Json -Schema (Get-Content -LiteralPath $schemaPath -Raw) -ErrorAction Stop }
catch { $schemaErrors = @($_.Exception.Message) }

if ($schemaErrors.Count -gt 0) {
    Write-Problem "The $ArtifactType payload for story $StoryId does not match $ArtifactType.schema.json:"
    foreach ($problem in $schemaErrors) { Write-Problem "  $problem" }
    Write-Problem 'Fix the payload and run this script again. Nothing was written.'
    exit 1
}

$folder = Join-Path (Resolve-Path -LiteralPath $Root).Path '.ei-session-logs' $StoryId
if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
$target = Join-Path $folder "$ArtifactType.json"
[System.IO.File]::WriteAllText($target, ($body -replace "`r`n", "`n") + "`n", [System.Text.UTF8Encoding]::new($false))

$stamped = $null
if ($ArtifactType -ne 'ado') { $stamped = $canonical['hash'] }

$result = [pscustomobject]@{
    path         = $target
    artifactType = $ArtifactType
    storyId      = $StoryId
    hash         = $stamped
}

if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result }
exit 0
