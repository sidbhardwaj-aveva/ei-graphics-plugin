#!/usr/bin/env pwsh
#Requires -Modules Pester

Describe 'EI workflow artifact read and write' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $skillScripts = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts'
        $script:WritePath = Join-Path $skillScripts 'Write-EiWorkflowArtifact.ps1'
        $script:ReadPath = Join-Path $skillScripts 'Read-EiWorkflowArtifact.ps1'
        $script:InitPath = Join-Path $skillScripts 'Initialize-EiWorkflowState.ps1'

        $script:ValidResult = @{
            schemaVersion = '1.0.0'
            workflow      = 'ei-graphics-workflow'
            path          = 'IMPLEMENT'
            storyId       = '123456'
            status        = 'blocked'
            stage         = 'preflight'
            stateDir      = '.copilottracking/ei-graphics/123456'
            summary       = 'Blocked on an unimplemented stage.'
            artifacts     = @()
            gates         = @()
            blocks        = @()
            nextAction    = 'Wait for the owning phase to land.'
        } | ConvertTo-Json -Depth 10
    }

    BeforeEach {
        & $script:InitPath -StoryId '123456' -WorkspaceRoot $TestDrive -Json | Out-Null
        $script:StateDir = Join-Path $TestDrive '.copilottracking' 'ei-graphics' '123456'
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes an active artifact that satisfies its schema' {
        $output = & $script:WritePath -StateDir $script:StateDir -Name 'workflow-result' -Content $script:ValidResult -Json
        $LASTEXITCODE | Should -Be 0
        ($output | ConvertFrom-Json).Status | Should -Be 'Valid'
        Test-Path -LiteralPath (Join-Path $script:StateDir 'workflow-result.json') | Should -BeTrue
    }

    It 'blocks an artifact that violates its schema' {
        $output = & $script:WritePath -StateDir $script:StateDir -Name 'workflow-result' -Content '{"schemaVersion":"1.0.0"}' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-SCHEMA*'
        Test-Path -LiteralPath (Join-Path $script:StateDir 'workflow-result.json') | Should -BeFalse
    }

    It 'blocks content that is not valid JSON' {
        $output = & $script:WritePath -StateDir $script:StateDir -Name 'workflow-result' -Content '{ not json' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-INVALID*'
    }

    It 'blocks an artifact that is reserved for a later phase' {
        $output = & $script:WritePath -StateDir $script:StateDir -Name 'specification' -Content '{"id":1}' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-SCHEMA-PENDING*'
    }

    It 'blocks an artifact that is not in the registry' {
        $output = & $script:WritePath -StateDir $script:StateDir -Name 'not-registered' -Content '{}' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-UNKNOWN*'
    }

    It 'blocks a write when the state directory was never initialised' {
        $output = & $script:WritePath -StateDir (Join-Path $TestDrive 'missing') -Name 'workflow-result' -Content $script:ValidResult -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-STATE-DIR-MISSING*'
    }

    It 'reads back a written artifact for the next stage' {
        & $script:WritePath -StateDir $script:StateDir -Name 'workflow-result' -Content $script:ValidResult -Json | Out-Null

        $output = & $script:ReadPath -StateDir $script:StateDir -Name 'workflow-result' -Json
        $LASTEXITCODE | Should -Be 0

        $result = $output | ConvertFrom-Json
        $result.Status | Should -Be 'Valid'
        $result.Details.Payload.storyId | Should -Be '123456'
        $result.Details.Owner | Should -Be 'ei-graphics-workflow'
    }

    It 'blocks a read when the required artifact is absent' {
        $output = & $script:ReadPath -StateDir $script:StateDir -Name 'workflow-result' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-MISSING*'
    }

    It 'blocks a read when the stored artifact no longer satisfies its schema' {
        & $script:WritePath -StateDir $script:StateDir -Name 'workflow-result' -Content $script:ValidResult -Json | Out-Null
        Set-Content -LiteralPath (Join-Path $script:StateDir 'workflow-result.json') -Value '{"schemaVersion":"1.0.0"}'

        $output = & $script:ReadPath -StateDir $script:StateDir -Name 'workflow-result' -Json
        $LASTEXITCODE | Should -Be 1
        ($output | ConvertFrom-Json).Errors[0] | Should -BeLike 'EIWF-ARTIFACT-SCHEMA*'
    }
}
