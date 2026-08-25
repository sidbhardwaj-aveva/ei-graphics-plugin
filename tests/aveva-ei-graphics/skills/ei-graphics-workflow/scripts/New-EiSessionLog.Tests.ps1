#!/usr/bin/env pwsh
#Requires -Modules Pester
<#
.DESCRIPTION
Focused tests for New-EiSessionLog.ps1.

Covers:
  1. Returns Invalid when the state directory does not exist.
  2. Returns Invalid when workflow-state.json is missing.
  3. Returns Invalid when workflow-state.json is malformed.
  4. Writes a valid JSON log file to the target log directory.
  5. Log file contains all required top-level fields.
  6. Duration is calculated correctly from createdAt / updatedAt.
  7. Stage entries are populated from workflow-state.json stages.
  8. Token usage fields are null when not supplied.
  9. Token usage is populated when PromptTokens and CompletionTokens are supplied.
 10. Improvement notes are generated for gate failures.
 11. Improvement notes are generated when corrections were attempted.
 12. SessionId defaults to a GUID when not specified.
 13. Summary is populated from workflow-result.json when present.
 14. Custom -LogDir is respected.
 15. Writing with -FinalStatus in-progress (start marker) records 'in-progress' status.
 16. Start-marker improvement note is present for interrupted sessions.
 17. Writing final log with same SessionId overwrites the start marker.
 18. Overwritten log carries the terminal status, not 'in-progress'.
#>

Describe 'New-EiSessionLog' -Tag 'Unit' {
    BeforeAll {
        $repoRoot        = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
        $script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-workflow' 'scripts' 'New-EiSessionLog.ps1'
        $script:InitPath   = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts' 'Initialize-EiWorkflowState.ps1'
        $script:StagePath  = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-workflow-state' 'scripts' 'Set-EiWorkflowStage.ps1'

        function script:MakeMinimalState {
            param([string]$WorkspaceRoot, [string]$StoryId = '999001')
            & $script:InitPath -StoryId $StoryId -WorkspaceRoot $WorkspaceRoot -Json | Out-Null
            $stateDir = Join-Path $WorkspaceRoot '.copilottracking' 'ei-graphics' $StoryId
            # Complete two early stages so state is not bare
            foreach ($id in @('preflight', 'state-init')) {
                & $script:StagePath -StateDir $stateDir -StageId $id -Action start  -Json | Out-Null
                & $script:StagePath -StateDir $stateDir -StageId $id -Action complete -GateResult pass -Json | Out-Null
            }
            return $stateDir
        }
    }

    AfterEach {
        Remove-Item -LiteralPath (Join-Path $TestDrive '.copilottracking') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $TestDrive '.ei-session-logs') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $TestDrive 'test-logs')         -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $TestDrive 'custom-logs')       -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ── 1: Missing state directory ────────────────────────────────────────────
    It 'returns Invalid when state directory does not exist' {
        $result = & $script:ScriptPath -StateDir (Join-Path $TestDrive 'nonexistent') -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 1
        $result.Status | Should -Be 'Invalid'
        $result.Errors | Should -BeLike '*EILOG-STATE-MISSING*'
    }

    # ── 2: Missing workflow-state.json ────────────────────────────────────────
    It 'returns Invalid when workflow-state.json is missing' {
        $emptyDir = Join-Path $TestDrive 'empty-state'
        $null = New-Item -ItemType Directory -Path $emptyDir -Force
        $result = & $script:ScriptPath -StateDir $emptyDir -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 1
        $result.Status | Should -Be 'Invalid'
        $result.Errors | Should -BeLike '*EILOG-STATE-MISSING*'
    }

    # ── 3: Malformed workflow-state.json ─────────────────────────────────────
    It 'returns Invalid when workflow-state.json is malformed JSON' {
        $badDir = Join-Path $TestDrive 'bad-state'
        $null = New-Item -ItemType Directory -Path $badDir -Force
        Set-Content -LiteralPath (Join-Path $badDir 'workflow-state.json') -Value 'not-json' -Encoding UTF8
        $result = & $script:ScriptPath -StateDir $badDir -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 1
        $result.Status | Should -Be 'Invalid'
        $result.Errors | Should -BeLike '*EILOG-STATE-INVALID*'
    }

    # ── 4: Writes a log file ──────────────────────────────────────────────────
    It 'writes a JSON log file to the resolved log directory' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $result.Status | Should -Be 'Valid'
        $result.Details.LogFile | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $result.Details.LogFile | Should -BeTrue
    }

    # ── 5: Required top-level fields ──────────────────────────────────────────
    It 'log contains all required top-level fields' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json

        $log.schemaVersion  | Should -Be '1.0.0'
        $log.sessionId      | Should -Not -BeNullOrEmpty
        $log.storyId        | Should -Be '999001'
        $log.workflowPath   | Should -Be 'IMPLEMENT'
        $log.agentVersion   | Should -Not -BeNullOrEmpty
        $log.startedAt      | Should -Not -BeNullOrEmpty
        $log.finalStatus    | Should -Not -BeNullOrEmpty
        # stages, gates, blocks, improvementNotes may be empty arrays; use -is [array] to avoid pipeline-empty false-null
        ($log.stages -is [array] -or $null -ne $log.stages) | Should -BeTrue
        ($null -eq $log.gates)             | Should -BeFalse
        ($null -eq $log.blocks)            | Should -BeFalse
        $log.tokenUsage                    | Should -Not -BeNull
        $log.inputs                        | Should -Not -BeNull
        ($null -eq $log.improvementNotes)  | Should -BeFalse
    }

    # ── 6: Duration calculation ───────────────────────────────────────────────
    It 'calculates durationSeconds from createdAt and updatedAt' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        # The state was just created so duration will be very small but non-null
        $log.durationSeconds | Should -Not -BeNull
        $log.durationSeconds | Should -BeGreaterOrEqual 0
    }

    # ── 7: Stage entries ──────────────────────────────────────────────────────
    It 'stage entries are populated from workflow-state.json' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        @($log.stages).Count | Should -BeGreaterThan 0
        $log.stages[0].id   | Should -Not -BeNullOrEmpty
        $log.stages[0].name | Should -Not -BeNullOrEmpty
        $log.stages[0].status    | Should -Not -BeNullOrEmpty
        $log.stages[0].gateResult | Should -Not -BeNullOrEmpty
    }

    # ── 8: Token usage null when not supplied ─────────────────────────────────
    It 'token usage fields are null when not supplied' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        $log.tokenUsage.promptTokens     | Should -BeNull
        $log.tokenUsage.completionTokens | Should -BeNull
        $log.tokenUsage.totalTokens      | Should -BeNull
        $log.tokenUsage.estimatedCostUSD | Should -BeNull
        $log.tokenUsage.note             | Should -BeLike '*not available*'
    }

    # ── 9: Token usage populated when supplied ────────────────────────────────
    It 'token usage is populated when PromptTokens and CompletionTokens are supplied' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -PromptTokens 1500 -CompletionTokens 300 -EstimatedCostUSD 0.0045 -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        $log.tokenUsage.promptTokens     | Should -Be 1500
        $log.tokenUsage.completionTokens | Should -Be 300
        $log.tokenUsage.totalTokens      | Should -Be 1800
        $log.tokenUsage.estimatedCostUSD | Should -Be 0.0045
        $log.tokenUsage.note             | Should -BeLike '*Populated*'
    }

    # ── 10: Improvement notes for gate failures ───────────────────────────────
    It 'generates improvement notes for blocked gates' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        # Manually inject a blocked gate into the state so the logger can detect it
        $stateFile  = Join-Path $stateDir 'workflow-state.json'
        $state      = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $blockedStage = @($state.stages) | Where-Object { $_.id -eq 'preflight' } | Select-Object -First 1
        $blockedStage.gateResult = 'block'
        $blockedStage.gate = 'R-000-preflight'
        $blockedStage.blockReason = 'missing prerequisite'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $stateFile -Encoding UTF8

        $logDir = Join-Path $TestDrive 'test-logs'
        $result = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log    = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json

        $gateNote = @($log.improvementNotes) | Where-Object { $_.category -eq 'gate-failure' }
        $gateNote | Should -Not -BeNullOrEmpty
        $gateNote[0].note | Should -BeLike '*missing prerequisite*'
    }

    # ── 11: Improvement notes for correction attempts ─────────────────────────
    It 'generates improvement notes when correctionAttempts is greater than 0' {
        $stateDir  = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $stateFile = Join-Path $stateDir 'workflow-state.json'
        $state     = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $state.correctionAttempts = 2
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $stateFile -Encoding UTF8

        $logDir = Join-Path $TestDrive 'test-logs'
        $result = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log    = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json

        $corrNote = @($log.improvementNotes) | Where-Object { $_.category -eq 'correction-attempt' }
        $corrNote | Should -Not -BeNullOrEmpty
        $corrNote[0].note | Should -BeLike '*2 correction*'
    }

    # ── 12: Default SessionId is a GUID ──────────────────────────────────────
    It 'sessionId defaults to a valid GUID when not specified' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        [Guid]::TryParse($log.sessionId, [ref][Guid]::Empty) | Should -BeTrue
    }

    # ── 13: Summary from workflow-result.json ─────────────────────────────────
    It 'populates summary from workflow-result.json when present' {
        $stateDir    = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $resultDoc   = [ordered]@{ summary = 'All stages completed.' }
        $resultDoc | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDir 'workflow-result.json') -Encoding UTF8

        $logDir = Join-Path $TestDrive 'test-logs'
        $result = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -Json | ConvertFrom-Json
        $log    = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        $log.summary | Should -Be 'All stages completed.'
    }

    # ── 14: Custom -LogDir is respected ──────────────────────────────────────
    It 'writes the log file to the custom -LogDir path' {
        $stateDir   = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $customDir  = Join-Path $TestDrive 'custom-logs'
        $result     = & $script:ScriptPath -StateDir $stateDir -LogDir $customDir -Json | ConvertFrom-Json
        $result.Details.LogFile | Should -BeLike "$customDir*"
        Test-Path -LiteralPath $result.Details.LogFile | Should -BeTrue
    }

    # ── 15: Start-marker records in-progress ─────────────────────────────────
    It 'records in-progress status when -FinalStatus in-progress is supplied' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $sid      = [System.Guid]::NewGuid().ToString()
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -SessionId $sid -FinalStatus in-progress -Json | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        $log = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        $log.finalStatus | Should -Be 'in-progress'
    }

    # ── 16: Interrupted session gets improvement note ─────────────────────────
    It 'adds an interrupted improvement note for in-progress status' {
        $stateDir = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir   = Join-Path $TestDrive 'test-logs'
        $result   = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -FinalStatus in-progress -Json | ConvertFrom-Json
        $log      = Get-Content -LiteralPath $result.Details.LogFile -Raw | ConvertFrom-Json
        $note = @($log.improvementNotes) | Where-Object { $_.category -eq 'general' -and $_.note -like '*interrupted*' }
        $note | Should -Not -BeNullOrEmpty
    }

    # ── 17: Final log overwrites start marker (same SessionId, same file) ─────
    It 'second call with same SessionId overwrites the start-marker file' {
        $stateDir  = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir    = Join-Path $TestDrive 'test-logs'
        $sid       = [System.Guid]::NewGuid().ToString()
        # First call — start marker
        $r1 = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -SessionId $sid -FinalStatus in-progress -Json | ConvertFrom-Json
        $file1 = $r1.Details.LogFile
        # Second call — final log (same SessionId)
        & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -SessionId $sid -Json | Out-Null
        # Should still be exactly one file (second call overwrote the first)
        $files = @(Get-ChildItem -LiteralPath $logDir -Filter '*.json' -File)
        $files.Count | Should -Be 1
        $files[0].FullName | Should -Be $file1
    }

    # ── 18: Overwritten log carries terminal status ───────────────────────────
    It 'overwritten log has the terminal status from workflow-state.json, not in-progress' {
        $stateDir  = script:MakeMinimalState -WorkspaceRoot $TestDrive
        $logDir    = Join-Path $TestDrive 'test-logs'
        $sid       = [System.Guid]::NewGuid().ToString()
        # Write start marker
        & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -SessionId $sid -FinalStatus in-progress -Json | Out-Null

        # Patch state to a terminal status so the second call doesn't see in-progress
        $stateFile = Join-Path $stateDir 'workflow-state.json'
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $state.status = 'blocked'
        $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $stateFile -Encoding UTF8

        # Write final log — reads 'blocked' from state, no in-progress override
        $r2  = & $script:ScriptPath -StateDir $stateDir -LogDir $logDir -SessionId $sid -Json | ConvertFrom-Json
        $log = Get-Content -LiteralPath $r2.Details.LogFile -Raw | ConvertFrom-Json
        $log.finalStatus | Should -Be 'blocked'
        @($log.improvementNotes | Where-Object { $_.note -like '*interrupted*' }).Count | Should -Be 0
    }
}
