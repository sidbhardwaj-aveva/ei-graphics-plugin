#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiCodeReview' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'agents' 'ei-code-review' 'scripts' 'Invoke-EiCodeReview.ps1'
    }

    It 'returns pass with advisory for non-high-risk TODO and includes evidence package' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiCodeReview_' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $filePath = Join-Path $tempRoot 'GeneralService.cs'

        try {
            @'
public class GeneralService
{
    // TODO: improve message text
}
'@ | Set-Content -LiteralPath $filePath

            $bugContext = '{"bugId":"468178","title":"Cable route mismatch"}'
            $output = & $script:ScriptPath `
                -ChangedFiles @($filePath) `
                -PrSanityPath 'PRValidation_EIGSanity' `
                -BugContextJson $bugContext `
                -Json

            $LASTEXITCODE | Should -Be 0
            $result = $output | ConvertFrom-Json
            $result.status | Should -Be 'pass'
            $result.advisoryFindings.Count | Should -BeGreaterThan 0
            $result.prEvidencePackage.adoLinkage.bugId | Should -Be '468178'
            $result.prEvidencePackage.sanityPath | Should -Be 'PRValidation_EIGSanity'
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns blocked for high-risk file without sanity path' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiCodeReview_' + [System.IO.Path]::GetRandomFileName())
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
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when BugContextJson is invalid JSON' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EiCodeReview_' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
        $filePath = Join-Path $tempRoot 'GeneralService.cs'

        try {
            @'
public class GeneralService
{
    public void Execute() { }
}
'@ | Set-Content -LiteralPath $filePath

            { & $script:ScriptPath -ChangedFiles @($filePath) -BugContextJson '{invalid' -Json } | Should -Throw -ExpectedMessage '*BugContextJson is not valid JSON.*'
        }
        finally {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
