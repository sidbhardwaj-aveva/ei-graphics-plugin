#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Focused tests for Read-EiSessionLogs.ps1.

Covers:
  1. Returns Valid with a warning when the log root does not exist.
  2. Returns Valid with a warning when no JSON files are present.
  3. Report is generated from a single session log.
  4. Summary table includes session count, completion count, and gate failure count.
  5. Top improvement notes section is present when notes exist.
  6. Block frequency table is populated from block entries.
  7. -StoryId filter limits results to that story.
  8. -Last N parameter returns only the N most-recent sessions.
  9. Details.Sessions contains parsed session objects.
 10. Details.TotalSessions matches the number of parsed files.
#>

Describe 'Read-EiSessionLogs' -Tag 'Unit' {
    BeforeAll {
        $repoRoot          = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'Read-EiSessionLogs.ps1'

        function script:WriteSessionLog {
            param([string]$LogRoot, [string]$StoryId, [string]$Suffix = '', [hashtable]$Overrides = @{})

            $dir = Join-Path $LogRoot $StoryId
            $null = New-Item -ItemType Directory -Path $dir -Force

            $doc = [ordered]@{
                schemaVersion   = '1.0.0'
                sessionId       = [System.Guid]::NewGuid().ToString()
                storyId         = $StoryId
                workflowPath    = 'IMPLEMENT'
                agentVersion    = '1.0.0'
                startedAt       = '2026-08-01T10:00:00Z'
                endedAt         = '2026-08-01T10:05:00Z'
                durationSeconds = 300
                stages          = @(
                    [ordered]@{ id = 'preflight'; name = 'preflight'; startedAt = $null; endedAt = $null; durationSeconds = $null; status = 'complete'; gateResult = 'pass'; blockReason = $null }
                )
                gates           = @()
                blocks          = @()
                finalStatus     = 'completed'
                summary         = 'Test run completed.'
                tokenUsage      = [ordered]@{ promptTokens = $null; completionTokens = $null; totalTokens = $null; estimatedCostUSD = $null; note = 'not available' }
                inputs          = [ordered]@{ storyRef = $null; entryPoint = $null; diffBaseBranch = $null }
                improvementNotes = @()
            }

            foreach ($key in $Overrides.Keys) { $doc[$key] = $Overrides[$key] }

            $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
            $file = Join-Path $dir "$timestamp-$Suffix.json"
            $doc | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding UTF8
            return $file
        }
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.ei-session-logs') -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── 1: No log root ────────────────────────────────────────────────────────
    It 'returns Valid with a warning when the log root does not exist' {
        $result = & $script:ScriptPath -LogRoot (Join-Path $TestDrive 'nonexistent') -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $result.Status | Should -Be 'Valid'
        $result.Warnings | Should -Not -BeNullOrEmpty
        $result.Details.Report | Should -BeLike '*No session logs found*'
    }

    # ── 2: Empty log directory ────────────────────────────────────────────────
    It 'returns Valid with a warning when no JSON files are present' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        $null = New-Item -ItemType Directory -Path $logRoot -Force
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $result.Status | Should -Be 'Valid'
        $result.Warnings | Should -Not -BeNullOrEmpty
    }

    # ── 3: Report generated from a single session ─────────────────────────────
    It 'generates a Markdown report from a single session log' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '111' -Suffix 'aaa'
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $result.Status | Should -Be 'Valid'
        $result.Details.Report | Should -BeLike '*EI Graphics Session Log Report*'
        $result.Details.Report | Should -BeLike '*Summary*'
    }

    # ── 4: Summary table values ───────────────────────────────────────────────
    It 'summary table includes session count, completion count, and gate failure count' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '222' -Suffix 'bbb' -Overrides @{ finalStatus = 'completed' }
        script:WriteSessionLog -LogRoot $logRoot -StoryId '222' -Suffix 'ccc' -Overrides @{ finalStatus = 'blocked' }

        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $report = $result.Details.Report

        $report | Should -BeLike '*Total sessions*2*'
        $report | Should -BeLike '*Completed*1*'
        $report | Should -BeLike '*Blocked*1*'
        $report | Should -BeLike '*Gate failures*0*'
    }

    # ── 5: Improvement notes section ─────────────────────────────────────────
    It 'improvement notes section appears when notes exist in session logs' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '333' -Suffix 'ddd' -Overrides @{
            improvementNotes = @(
                [ordered]@{ category = 'timing'; note = 'Stage X was slow.' }
            )
        }
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $result.Details.Report | Should -BeLike '*Top Improvement Notes*'
        $result.Details.Report | Should -BeLike '*Stage X was slow*'
    }

    # ── 6: Block frequency table ──────────────────────────────────────────────
    It 'most common blocks section is populated from block entries' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '444' -Suffix 'eee' -Overrides @{
            blocks = @(
                [ordered]@{ code = 'EIWF-CANDIDATE-MISSING'; stage = 'scope-candidate'; message = 'candidate.json not found' }
            )
        }
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $result.Details.Report | Should -BeLike '*Most Common Blocks*'
        $result.Details.Report | Should -BeLike '*EIWF-CANDIDATE-MISSING*'
    }

    # ── 7: -StoryId filter ────────────────────────────────────────────────────
    It 'filters sessions to the specified story when -StoryId is provided' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '555' -Suffix 'fff'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '666' -Suffix 'ggg'

        $result = & $script:ScriptPath -LogRoot $logRoot -StoryId '555' -Json | ConvertFrom-Json
        $result.Details.TotalSessions | Should -Be 1
        $result.Details.Sessions[0].storyId | Should -Be '555'
    }

    # ── 8: -Last N parameter ──────────────────────────────────────────────────
    It '-Last N limits the number of sessions returned' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        # Write 3 sessions for the same story
        for ($i = 1; $i -le 3; $i++) {
            Start-Sleep -Milliseconds 10   # ensure distinct timestamps
            script:WriteSessionLog -LogRoot $logRoot -StoryId '777' -Suffix "s$i"
        }
        $result = & $script:ScriptPath -LogRoot $logRoot -Last 2 -Json | ConvertFrom-Json
        $result.Details.TotalSessions | Should -Be 2
    }

    # ── 9: Sessions detail ────────────────────────────────────────────────────
    It 'Details.Sessions contains parsed session objects' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '888' -Suffix 'hhh'
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $result.Details.Sessions | Should -Not -BeNullOrEmpty
        $result.Details.Sessions[0].schemaVersion | Should -Be '1.0.0'
    }

    # ── 10: TotalSessions count ───────────────────────────────────────────────
    It 'Details.TotalSessions matches number of parsed files' {
        $logRoot = Join-Path $TestDrive '.ei-session-logs'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '999' -Suffix 'iii'
        script:WriteSessionLog -LogRoot $logRoot -StoryId '999' -Suffix 'jjj'
        $result = & $script:ScriptPath -LogRoot $logRoot -Json | ConvertFrom-Json
        $result.Details.TotalSessions | Should -Be 2
    }
}
