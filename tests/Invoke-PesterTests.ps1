#!/usr/bin/env pwsh
# Copyright (c) AVEVA.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

param(
    [string] $CoverageOutputPath = '',
    [string] $CoveragePath       = (Join-Path $PSScriptRoot '..' 'plugins')
)

$config                  = New-PesterConfiguration
$config.Run.Path         = $PSScriptRoot
$config.Run.PassThru     = $true
$config.Filter.Tag       = @('Unit')
$config.Output.Verbosity = 'Detailed'

if ($CoverageOutputPath) {
    $config.CodeCoverage.Enabled      = $true
    $config.CodeCoverage.Path         = $CoveragePath
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath   = $CoverageOutputPath
}

$result = Invoke-Pester -Configuration $config
exit $result.FailedCount
