#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'Invoke-EiBugDiagnosisToSpec' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'agents' 'ei-bug-diagnosis-to-spec' 'scripts' 'Invoke-EiBugDiagnosisToSpec.ps1'
    }

    It 'returns ready-for-implementation with required evidence inputs' {
        $bugContext = '{"bugId":"468178","title":"Cable route mismatch"}'
        $diagnosis = '{"confidence":0.82,"affectedAreas":["CableRoutingService"],"relatedTests":["Tests/CableRouting.Tests.cs"]}'
        $vocab = '{"ambiguities":[]}'

        $output = & $script:ScriptPath `
            -BugContextJson $bugContext `
            -DiagnosisJson $diagnosis `
            -VocabularyMappingsJson $vocab `
            -Json

        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'ready-for-implementation'
        $result.specSummary | Should -Match 'Cable route mismatch'
        $result.functionalRequirements.Count | Should -BeGreaterThan 1
    }

    It 'returns blocked when required diagnosis evidence is missing' {
        $output = & $script:ScriptPath -Json

        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'blocked'
        $result.handoffChecklist.Count | Should -BeGreaterThan 0
    }

    It 'returns needs-manual-review for low-confidence diagnosis' {
        $bugContext = '{"bugId":"468178","title":"Voltage issue"}'
        $diagnosis = '{"confidence":0.41,"affectedAreas":["DistributionBoardService"]}'

        $output = & $script:ScriptPath -BugContextJson $bugContext -DiagnosisJson $diagnosis -Json

        $LASTEXITCODE | Should -Be 1
        $result = $output | ConvertFrom-Json
        $result.status | Should -Be 'needs-manual-review'
        $result.nextAction | Should -Match 'Raise confidence'
    }
}
