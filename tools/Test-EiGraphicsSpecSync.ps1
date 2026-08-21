#!/usr/bin/env pwsh
# Copyright (c) AVEVA.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#!
.SYNOPSIS
    Enforces EI Graphics spec updates when EI plugin files change.

.DESCRIPTION
    Fails when changes are detected under plugins/aveva-ei-graphics without at
    least one corresponding change under specs/002-ei-graphics-plugin-foundation.

    Input can be provided either as:
      - A git range via -FromRef/-ToRef
      - An explicit set of changed paths via -ChangedPaths

    Exit codes:
      0 = pass
      1 = policy violation
      2 = usage or git command error

.PARAMETER FromRef
    Base git ref for range mode.

.PARAMETER ToRef
    Head git ref for range mode. Defaults to HEAD.

.PARAMETER ChangedPaths
    Explicit list of changed paths relative to repository root.

.PARAMETER PluginPrefix
    Repository-relative EI plugin path prefix to enforce.

.PARAMETER SpecPrefix
    Repository-relative EI planning/spec path prefix to enforce.
#>
param(
    [string]   $FromRef,
    [string]   $ToRef = 'HEAD',
    [string[]] $ChangedPaths,
    [string]   $PluginPrefix = 'plugins/aveva-ei-graphics/',
    [string]   $SpecPrefix   = 'specs/002-ei-graphics-plugin-foundation/'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Normalize-RepoPath {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $normalized = ($Path -replace '\\', '/').Trim()
    $normalized = $normalized -replace '/+', '/'
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }

    return $normalized
}

function Ensure-TrailingSlash {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    if ($Path.EndsWith('/', [System.StringComparison]::Ordinal)) {
        return $Path
    }

    return "$Path/"
}

function Get-RangePaths {
    param(
        [string] $From,
        [string] $To
    )

    $paths = & git diff --name-only --diff-filter=ACMRTD "$From..$To" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Unable to read changed files for range '$From..$To': $($paths -join "`n")"
        exit 2
    }

    return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

if ((-not $ChangedPaths -or $ChangedPaths.Count -eq 0) -and [string]::IsNullOrWhiteSpace($FromRef)) {
    Write-Error 'Provide either -ChangedPaths or -FromRef/-ToRef.'
    exit 2
}

if (-not $ChangedPaths -or $ChangedPaths.Count -eq 0) {
    $ChangedPaths = Get-RangePaths -From $FromRef -To $ToRef
}

$pluginPrefixNormalized = Ensure-TrailingSlash -Path (Normalize-RepoPath -Path $PluginPrefix)
$specPrefixNormalized   = Ensure-TrailingSlash -Path (Normalize-RepoPath -Path $SpecPrefix)

$normalizedPaths = @(
    $ChangedPaths |
        ForEach-Object { Normalize-RepoPath -Path $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$pluginChanges = @(
    $normalizedPaths |
        Where-Object { $_.StartsWith($pluginPrefixNormalized, [System.StringComparison]::OrdinalIgnoreCase) }
)

$specChanges = @(
    $normalizedPaths |
        Where-Object { $_.StartsWith($specPrefixNormalized, [System.StringComparison]::OrdinalIgnoreCase) }
)

Write-Host ''
Write-Host 'EI Graphics Spec Sync Gate'
Write-Host '---'
Write-Host "Plugin prefix: $pluginPrefixNormalized"
Write-Host "Spec prefix:   $specPrefixNormalized"
Write-Host "Changed files: $($normalizedPaths.Count)"
Write-Host '---'

if ($pluginChanges.Count -eq 0) {
    Write-Host "PASS: No changes detected under '$pluginPrefixNormalized'."
    exit 0
}

if ($specChanges.Count -eq 0) {
    Write-Host "FAIL: Changes under '$pluginPrefixNormalized' require at least one update under '$specPrefixNormalized'."
    Write-Host ''
    Write-Host 'Plugin changes detected:'
    foreach ($path in $pluginChanges) {
        Write-Host "  - $path"
    }
    exit 1
}

Write-Host "PASS: Detected $($pluginChanges.Count) EI plugin change(s) and $($specChanges.Count) matching spec change(s)."
exit 0
