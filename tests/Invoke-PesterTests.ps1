#!/usr/bin/env pwsh
# Copyright (c) AVEVA.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

param(
    [string[]] $Path = @($PSScriptRoot),
    [string] $CoverageOutputPath = '',
    [string] $CoveragePath       = (Join-Path $PSScriptRoot '..' 'plugins')
)

$config                  = New-PesterConfiguration
$config.Run.Path         = $Path
$config.Run.PassThru     = $true
$config.Filter.Tag       = @('Unit')
$config.Output.Verbosity = 'Detailed'

if ($CoverageOutputPath) {
    $config.CodeCoverage.Enabled      = $true
    $config.CodeCoverage.Path         = $CoveragePath
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath   = $CoverageOutputPath
}

$result = $null
try {
    $result = Invoke-Pester -Configuration $config -ErrorAction Stop
} catch {
    [Console]::Error.WriteLine("Pester could not run for path: $($Path -join ', '). $($_.Exception.Message)")
    exit 1
}

# A run that discovers nothing is a failure. Without this, any check command that names a path
# with a typo in it would report success and prove nothing.
if ($null -eq $result -or $result.TotalCount -eq 0) {
    [Console]::Error.WriteLine("No tests ran for path: $($Path -join ', '). Check the path, and check that the tests carry the 'Unit' tag.")
    exit 1
}

exit $result.FailedCount
