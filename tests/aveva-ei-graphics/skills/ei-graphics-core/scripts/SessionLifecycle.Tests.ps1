#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:CoreSkill = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
    $script:Scripts = Join-Path $script:CoreSkill 'scripts'
    $script:Entry = Join-Path $script:Scripts 'Write-EiSessionEntry.ps1'
    $script:Renderer = Join-Path $script:Scripts 'Export-EiSessionSummary.ps1'
    $script:Artifact = Join-Path $script:Scripts 'Write-EiArtifact.ps1'
    $script:Wrapper = Join-Path $script:Scripts 'Complete-EiSession.ps1'

    # The text the history entry quotes. The writer only accepts a quote it finds on disk, so the
    # same string is written to the sandbox file and passed as evidence.
    $script:QuotedLine = 'if (_service.IsContentAssignmentUpdated(id)) { return true; }'
    $script:SourceFile = 'src/CanvasEventManager.cs'

    function New-Root {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force
        $body = @('public class CanvasEventManager', $script:QuotedLine, '// end') -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $root $script:SourceFile), $body + "`n")
        $root
    }

    function Get-SessionPath {
        param([string] $Root, [string] $StoryId, [string] $Name)
        Join-Path $Root '.ei-session-logs' $StoryId $Name
    }

    function Add-Entry {
        param([string] $Root, [string] $StoryId, [hashtable] $Fields)
        $null = & $script:Entry -StoryId $StoryId -Root $Root @Fields
        $LASTEXITCODE
    }

    function New-WorkedSession {
        <#
            A session with the shape a real run leaves behind: an understanding, an implementation
            entry that changed a file, and a validation entry.
        #>
        param([string] $Root, [string] $StoryId)
        $steps = @(
            @{ Phase = 'understanding'; Action = 'confirm-story'; Outcome = 'The story was confirmed with the human.' }
            @{ Phase = 'implementation'; Action = 'apply-fix'; Outcome = 'One method changed.'; FilesModified = @($script:SourceFile) }
            @{ Phase = 'validation'; Action = 'review-change'; Outcome = 'The change was reviewed.' }
        )
        foreach ($step in $steps) {
            $code = Add-Entry -Root $Root -StoryId $StoryId -Fields $step
            if ($code -ne 0) { throw "Staging the session failed on $($step.Action)." }
        }
    }

    function Invoke-Close {
        param([string] $Root, [string] $StoryId, [string] $Outcome, [string] $Wrapper = $script:Wrapper)
        # Run out of process: the wrapper writes its failures straight to the console error stream,
        # which only a child process can hand back.
        $output = pwsh -NoProfile -File $Wrapper -StoryId $StoryId -SessionOutcome $Outcome -Root $Root 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Text     = (@($output | ForEach-Object { $_.ToString() })) -join "`n"
        }
    }

    function Get-Understanding {
        param([string] $StoryId)
        [ordered]@{
            schemaVersion    = '1.0.0'
            storyId          = $StoryId
            status           = 'confirmed'
            understanding    = [ordered]@{
                subject         = 'Equipment renders in the wrong order'
                expectedOutcome = 'The domain sequence governs the order'
                requirements    = @([ordered]@{ text = 'Keep nested items in sequence'; source = 'description' })
            }
            proposedDomains  = @([ordered]@{ domainId = 'termination-drawing'; reason = 'Mounting rail'; confidence = 'high' })
            confirmedDomains = @('termination-drawing')
            complexity       = [ordered]@{ assessment = 'small'; reasoning = 'One method' }
            inputSource      = [ordered]@{
                kind              = 'attached-report'
                reference         = 'ordering-report.pdf'
                hash              = 'sha256:' + ('d' * 64)
                adoNotUsedBecause = 'The report arrived without a work item'
            }
        }
    }
}

Describe 'The session lifecycle' -Tag 'Unit' {

    BeforeEach {
        # The wrapper exports a bundle when this is set. No test here wants that.
        Remove-Item Env:EI_GRAPHICS_SHARE_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:EI_GRAPHICS_SHARE_PATH -ErrorAction SilentlyContinue
    }

    Context 'a session that recorded nothing' {

        It 'refuses a normal close, and leaves no session behind' {
            $root = New-Root
            $run = Invoke-Close -Root $root -StoryId 'empty-1' -Outcome 'success'
            $run.ExitCode | Should -Be 1
            $run.Text | Should -Match '(?i)has no entries'
            $run.Text | Should -Match '(?i)Step 1 failed'
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'empty-1' -Name 'session.json') | Should -BeFalse
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'empty-1' -Name 'session-summary.md') | Should -BeFalse
        }

        It 'accepts a setup-failed close, so a broken install still reports itself' {
            $root = New-Root
            $run = Invoke-Close -Root $root -StoryId 'empty-2' -Outcome 'setup-failed'
            $run.ExitCode | Should -Be 0
            $session = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'empty-2' -Name 'session.json') -Raw | ConvertFrom-Json
            $session.summary.outcome | Should -Be 'setup-failed'
            $summary = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'empty-2' -Name 'session-summary.md') -Raw
            $summary | Should -Match '(?i)No steps were recorded'
        }
    }

    Context 'a session that recorded work' {

        It 'writes session-summary.md beside session.json' {
            $root = New-Root
            New-WorkedSession -Root $root -StoryId 'worked-1'
            $run = Invoke-Close -Root $root -StoryId 'worked-1' -Outcome 'success'
            $run.ExitCode | Should -Be 0
            $summaryPath = Get-SessionPath -Root $root -StoryId 'worked-1' -Name 'session-summary.md'
            Test-Path -LiteralPath $summaryPath | Should -BeTrue
            (Get-Content -LiteralPath $summaryPath -Raw) | Should -Match '(?m)^# Session: story worked-1$'
        }

        It 'carries the finalized summary inside session.json' {
            $root = New-Root
            New-WorkedSession -Root $root -StoryId 'worked-2'
            (Invoke-Close -Root $root -StoryId 'worked-2' -Outcome 'success').ExitCode | Should -Be 0
            $session = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'worked-2' -Name 'session.json') -Raw | ConvertFrom-Json
            $session.summary.outcome | Should -Be 'success'
            $session.summary.completedAt | Should -Not -BeNullOrEmpty
            @($session.summary.filesModified) | Should -Contain $script:SourceFile
            @($session.entries).Count | Should -Be 3
        }

        It 'reports runtime verification as unconfirmed when no test was executed' {
            $root = New-Root
            New-WorkedSession -Root $root -StoryId 'worked-3'
            (Invoke-Close -Root $root -StoryId 'worked-3' -Outcome 'verification-unconfirmed').ExitCode | Should -Be 0
            $summary = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'worked-3' -Name 'session-summary.md') -Raw
            $summary | Should -Match '(?i)No test run was recorded'
            $summary | Should -Not -Match '(?i)tests passed'
            $summary | Should -Match '(?m)^\*\*Outcome:\*\* verification-unconfirmed$'
        }

        It 'reports a test result only when one was recorded' {
            $root = New-Root
            New-WorkedSession -Root $root -StoryId 'worked-4'
            $null = & $script:Entry -StoryId 'worked-4' -Root $root -Finalize -SessionOutcome 'success' -TestsRun 12 -TestsPassed 12
            $LASTEXITCODE | Should -Be 0
            $null = & $script:Renderer -StoryId 'worked-4' -Root $root
            $LASTEXITCODE | Should -Be 0
            $summary = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'worked-4' -Name 'session-summary.md') -Raw
            $summary | Should -Match '12 of 12 tests passed'
        }
    }

    Context 'history triage' {

        It 'renders evidence a reader can open and check' {
            $root = New-Root
            $code = Add-Entry -Root $root -StoryId 'history-1' -Fields @{
                Phase     = 'implementation'
                Action    = 'trace-history'
                Outcome   = 'Historical provenance recorded apart from validation.'
                Reasoning = 'Git history shows the check arrived with an earlier feature, not with this story.'
                Status    = 'informational'
                Evidence  = @(@{ file = $script:SourceFile; line = 2; symbol = 'IsContentAssignmentUpdated'; quote = $script:QuotedLine })
            }
            $code | Should -Be 0
            (Invoke-Close -Root $root -StoryId 'history-1' -Outcome 'verification-unconfirmed').ExitCode | Should -Be 0

            $summary = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'history-1' -Name 'session-summary.md') -Raw
            $summary | Should -Match ([regex]::Escape("(../../$($script:SourceFile)#L2)"))
            $summary | Should -Match ([regex]::Escape($script:QuotedLine))
            $summary | Should -Match '(?i)IsContentAssignmentUpdated'
        }

        It 'refuses a quote the named file does not hold' {
            $root = New-Root
            $code = Add-Entry -Root $root -StoryId 'history-2' -Fields @{
                Phase    = 'implementation'
                Action   = 'trace-history'
                Outcome  = 'Claimed a line nobody read.'
                Evidence = @(@{ file = $script:SourceFile; quote = 'this line was never in the file' })
            }
            $code | Should -Be 1
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'history-2' -Name 'session.json') | Should -BeFalse
        }
    }

    Context 'the close will not report a summary that was never written' {

        It 'exits 1 after a real finalize when the renderer writes nothing' {
            $root = New-Root
            New-WorkedSession -Root $root -StoryId 'unwritten-1'

            # A copy of the whole skill, so the real finalize step still runs against the real
            # schema while the renderer beside it is the one that lies about its output.
            $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $sandbox -Force
            Copy-Item -LiteralPath $script:CoreSkill -Destination $sandbox -Recurse -Force
            $copiedScripts = Join-Path $sandbox 'ei-graphics-core' 'scripts'
            Set-Content -LiteralPath (Join-Path $copiedScripts 'Export-EiSessionSummary.ps1') -Encoding utf8 -Value @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
Write-Output '{"path":"C:/never-written/session-summary.md","storyId":"unwritten-1"}'
exit 0
'@

            $run = Invoke-Close -Root $root -StoryId 'unwritten-1' -Outcome 'success' -Wrapper (Join-Path $copiedScripts 'Complete-EiSession.ps1')
            $run.ExitCode | Should -Be 1
            $run.Text | Should -Match '(?i)did not create session-summary\.md'
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'unwritten-1' -Name 'session-summary.md') | Should -BeFalse

            # The finalize step really ran, so the failure is the renderer's and nothing else.
            $session = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'unwritten-1' -Name 'session.json') -Raw | ConvertFrom-Json
            $session.summary.outcome | Should -Be 'success'
        }
    }

    Context 'a local report with no Azure DevOps work item' {

        It 'closes the session and never asks for ado.json' {
            $root = New-Root
            $null = & $script:Artifact -StoryId 'local-9' -ArtifactType 'story-understanding' -InputObject (Get-Understanding -StoryId 'local-9') -Root $root
            $LASTEXITCODE | Should -Be 0
            New-WorkedSession -Root $root -StoryId 'local-9'

            $run = Invoke-Close -Root $root -StoryId 'local-9' -Outcome 'success'
            $run.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'local-9' -Name 'ado.json') | Should -BeFalse
            Test-Path -LiteralPath (Get-SessionPath -Root $root -StoryId 'local-9' -Name 'session-summary.md') | Should -BeTrue
            $understanding = Get-Content -LiteralPath (Get-SessionPath -Root $root -StoryId 'local-9' -Name 'story-understanding.json') -Raw | ConvertFrom-Json
            $understanding.inputSource.kind | Should -Be 'attached-report'
            $understanding.PSObject.Properties.Name | Should -Not -Contain 'adoHash'
        }
    }
}
