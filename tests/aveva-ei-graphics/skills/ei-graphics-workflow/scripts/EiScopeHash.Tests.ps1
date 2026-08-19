#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'ApprovedScope canonicalisation and content hash' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        . (Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'helpers' 'EiScopeHash.ps1')

        $script:CompactScope = @'
{"schemaVersion":"1.0.0","resolver":"ei-scope-resolver","storyId":"123456","generatedAt":"2026-01-01T00:00:00Z","status":"resolved","confidence":0.85,"proposedFiles":[{"path":"src/A.cs","changeIntent":"modify","symbols":["One","Two"],"evidence":["E1"],"confidence":0.9},{"path":"src/B.cs","changeIntent":"add","symbols":[],"evidence":["E2"],"confidence":0.8}],"protectedAreas":[],"rationale":"Smallest defensible scope."}
'@

        $script:BaselineHash = Get-EiScopeContentHash -Scope ($script:CompactScope | ConvertFrom-Json)
    }

    It 'is stable across JSON property ordering' {
        $reordered = @'
{"rationale":"Smallest defensible scope.","proposedFiles":[{"confidence":0.9,"evidence":["E1"],"symbols":["One","Two"],"changeIntent":"modify","path":"src/A.cs"},{"confidence":0.8,"evidence":["E2"],"symbols":[],"changeIntent":"add","path":"src/B.cs"}],"protectedAreas":[],"confidence":0.85,"status":"resolved","generatedAt":"2026-01-01T00:00:00Z","storyId":"123456","resolver":"ei-scope-resolver","schemaVersion":"1.0.0"}
'@

        Get-EiScopeContentHash -Scope ($reordered | ConvertFrom-Json) | Should -Be $script:BaselineHash
    }

    It 'is stable across insignificant whitespace' {
        $pretty = $script:CompactScope | ConvertFrom-Json | ConvertTo-Json -Depth 20

        Get-EiScopeContentHash -Scope ($pretty | ConvertFrom-Json) | Should -Be $script:BaselineHash
    }

    It 'is stable when the proposed file list is reordered' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.proposedFiles = @($scope.proposedFiles[1], $scope.proposedFiles[0])

        Get-EiScopeContentHash -Scope $scope | Should -Be $script:BaselineHash
    }

    It 'ignores the generation timestamp' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.generatedAt = '2027-12-31T23:59:59Z'

        Get-EiScopeContentHash -Scope $scope | Should -Be $script:BaselineHash
    }

    It 'changes when a proposed path is added' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.proposedFiles = @($scope.proposedFiles) + @([PSCustomObject]@{
                path         = 'src/C.cs'
                changeIntent = 'modify'
                symbols      = @()
                evidence     = @('E3')
                confidence   = 0.7
            })

        Get-EiScopeContentHash -Scope $scope | Should -Not -Be $script:BaselineHash
    }

    It 'changes when a proposed path is removed' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.proposedFiles = @($scope.proposedFiles[0])

        Get-EiScopeContentHash -Scope $scope | Should -Not -Be $script:BaselineHash
    }

    It 'changes when a proposed path is renamed' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.proposedFiles[0].path = 'src/Renamed.cs'

        Get-EiScopeContentHash -Scope $scope | Should -Not -Be $script:BaselineHash
    }

    It 'changes when a protected area is added to the seal' {
        $scope = $script:CompactScope | ConvertFrom-Json
        $scope.protectedAreas = @([PSCustomObject]@{ path = 'src/Legacy'; reason = 'Legacy renderer.' })

        Get-EiScopeContentHash -Scope $scope | Should -Not -Be $script:BaselineHash
    }

    It 'emits a lowercase sha256 digest' {
        $script:BaselineHash | Should -Match '^sha256:[0-9a-f]{64}$'
    }

    It 'refuses to canonicalise a scope that is nothing but excluded fields' {
        { Get-EiCanonicalScopeText -Scope ('{"generatedAt":"2026-01-01T00:00:00Z"}' | ConvertFrom-Json) } | Should -Throw
    }
}
