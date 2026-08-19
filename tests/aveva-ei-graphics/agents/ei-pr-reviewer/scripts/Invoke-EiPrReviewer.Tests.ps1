#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiPrReviewer' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'agents' 'ei-pr-reviewer' 'scripts' 'Invoke-EiPrReviewer.ps1'
    }

    It 'returns needs-manual-review when changed files are not provided' {
        $output = & $script:ScriptPath -Json
        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
    }

    It 'returns pass with advisory finding for TODO in non-high-risk path' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiPrReview_' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $filePath = Join-Path $tempRoot 'GeneralService.cs'

        try {
            @'
public class GeneralService
{
    // TODO: Improve error message handling
}
'@ | Set-Content -LiteralPath $filePath

            $output = & $script:ScriptPath -ChangedFiles @($filePath) -PrSanityPath 'PRValidation_EIGSanity' -Json
            $LASTEXITCODE | Should -Be 0
            $result = $output | ConvertFrom-Json
            $result.status | Should -Be 'pass'
            $result.advisoryFindings.Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns blocked when high-risk path is changed without sanity path' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiPrReview_' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $filePath = Join-Path $tempRoot 'DistributionBoardService.cs'

        try {
            @'
public class DistributionBoardService
{
    public void ValidateVoltage() { }
}
'@ | Set-Content -LiteralPath $filePath

            $output = & $script:ScriptPath -ChangedFiles @($filePath) -Json
            $LASTEXITCODE | Should -Be 1
            $result = $output | ConvertFrom-Json
            $result.status | Should -Be 'blocked'
            ($result.blockingFindings | Where-Object { $_.gate -eq 'R-006' }).Count | Should -BeGreaterThan 0
            $result.requiresSmeReviewFindings.Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns needs-manual-review when high-risk path has sanity path but still requires SME review' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiPrReview_' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $filePath = Join-Path $tempRoot 'CableRoutingService.cs'

        try {
            @'
public class CableRoutingService
{
    public void Execute() { }
}
'@ | Set-Content -LiteralPath $filePath

            $output = & $script:ScriptPath -ChangedFiles @($filePath) -PrSanityPath 'PRValidation_EIGSanity' -Json
            $LASTEXITCODE | Should -Be 1
            $result = $output | ConvertFrom-Json
            $result.status | Should -Be 'needs-manual-review'
            $result.blockingFindings.Count | Should -Be 0
            $result.requiresSmeReviewFindings.Count | Should -BeGreaterThan 0
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
