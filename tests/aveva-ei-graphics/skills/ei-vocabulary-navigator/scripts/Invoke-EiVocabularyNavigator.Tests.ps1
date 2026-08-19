#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiVocabularyNavigator' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-vocabulary-navigator' 'scripts' 'Invoke-EiVocabularyNavigator.ps1'
    }

    It 'returns a mapped vocabulary entry for cable' {
        $output = & $script:ScriptPath -Term 'cable' -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.term | Should -Be 'cable'
        ($result.domainModels -contains 'Cable') | Should -BeTrue
        ($result.services -contains 'CableService') | Should -BeTrue
    }

    It 'returns ambiguity alternatives for signal' {
        $output = & $script:ScriptPath -Term 'signal' -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        ($result.ambiguities -contains 'Signal') | Should -BeTrue
        ($result.ambiguities -contains 'SignalPropagator') | Should -BeTrue
    }

    It 'returns empty mappings and zero confidence for an unknown term' {
        $output = & $script:ScriptPath -Term 'nonexistent-term' -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.confidence | Should -Be 0
        $result.matchedUris | Should -BeNullOrEmpty
    }
}
