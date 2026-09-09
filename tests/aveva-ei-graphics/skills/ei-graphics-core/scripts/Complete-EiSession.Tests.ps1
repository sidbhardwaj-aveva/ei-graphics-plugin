#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:WrapperPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts' 'Complete-EiSession.ps1'

    function New-Sandbox {
        <#
            Stage a sandbox with the real wrapper alongside shim sub-scripts. The wrapper resolves
            its dependencies from $PSScriptRoot, so copying it into the same folder layout makes
            it call the shims instead of the real scripts.
        #>
        param([hashtable] $Shims)
        $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $core = Join-Path $sandbox 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts'
        $null = New-Item -ItemType Directory -Path $core -Force

        Copy-Item -LiteralPath $script:WrapperPath -Destination (Join-Path $core 'Complete-EiSession.ps1')

        Set-Content -LiteralPath (Join-Path $core 'Write-EiSessionEntry.ps1')          -Value $Shims.Finalize -Encoding utf8
        Set-Content -LiteralPath (Join-Path $core 'Export-EiSessionSummary.ps1')       -Value $Shims.Summary  -Encoding utf8
        Set-Content -LiteralPath (Join-Path $core 'Export-EiSessionBundleToShare.ps1') -Value $Shims.Bundle   -Encoding utf8

        [pscustomobject]@{
            SandboxRoot = $sandbox
            Wrapper     = Join-Path $core 'Complete-EiSession.ps1'
            CallLog     = Join-Path $sandbox 'call-log.json'
        }
    }

    # Every shim writes its own step name to the call log, so the tests can prove which steps
    # ran. The log path is derived by climbing five levels from the shim's $PSScriptRoot: from
    # scripts up through ei-graphics-core, skills, aveva-ei-graphics, plugins, to the sandbox
    # root, where the log lives.
    $script:HappyFinalizeShim = @'
[CmdletBinding()]
param(
    [string]$StoryId, [string]$Root='.', [switch]$Finalize, [string]$SessionOutcome,
    [string]$Phase, [string]$Action, [string]$Outcome, [string]$Reasoning,
    [object[]]$Evidence, [string]$Status, [string]$BugPatternMatched, [string]$DomainSkillUsed,
    [object[]]$CommentDeviations, [int]$DurationMs, [int]$TokensUsed, [int]$FilesRead,
    [int]$FilesModified, [int]$TestsRun, [int]$TestsPassed, [int]$HumanInteractions,
    [string]$HumanInput, [string]$ScriptOutput, [switch]$Json, [switch]$Help
)
Set-StrictMode -Version Latest
if ($Help) { 'SYNOPSIS'; exit 0 }
$callLog = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))) 'call-log.json'
@{ step = 'finalize'; StoryId = $StoryId; SessionOutcome = $SessionOutcome; Finalize = [bool]$Finalize } | ConvertTo-Json -Compress | Add-Content -LiteralPath $callLog -Encoding utf8
Write-Output '{"path":"stub/session.json","storyId":"4965976"}'
exit 0
'@

    $script:HappySummaryShim = @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
if ($Help) { 'SYNOPSIS'; exit 0 }
$callLog = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))) 'call-log.json'
@{ step = 'summary'; StoryId = $StoryId } | ConvertTo-Json -Compress | Add-Content -LiteralPath $callLog -Encoding utf8
Write-Output '{"path":"stub/session-summary.md","storyId":"4965976","verbosity":"verbose"}'
exit 0
'@

    $script:HappyBundleShim = @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [string]$SharePath, [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
if ($Help) { 'SYNOPSIS'; exit 0 }
$callLog = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))) 'call-log.json'
@{ step = 'bundle'; StoryId = $StoryId; SharePath = $SharePath } | ConvertTo-Json -Compress | Add-Content -LiteralPath $callLog -Encoding utf8
Write-Output '{"storyId":"4965976","sourcePath":"stub/local","status":"exported","exportedPath":"stub/share/4965976-001"}'
exit 0
'@

    function Get-CallSteps {
        param([string] $Path)
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        @(Get-Content -LiteralPath $Path | ForEach-Object { ($_ | ConvertFrom-Json).step })
    }
}

Describe 'Complete-EiSession' -Tag 'Unit' {

    BeforeEach {
        # Every test picks its own value for the share path. Clear the inherited one first, so
        # a prior test cannot leak into this one.
        Remove-Item Env:EI_GRAPHICS_SHARE_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:EI_GRAPHICS_SHARE_PATH -ErrorAction SilentlyContinue
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:WrapperPath -Help
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 when no -StoryId is given' {
        $err = pwsh -NoProfile -File $script:WrapperPath -SessionOutcome 'success' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($err -join "`n") | Should -Match '(?i)No -StoryId was given'
    }

    It 'exits 1 when no -SessionOutcome is given' {
        $err = pwsh -NoProfile -File $script:WrapperPath -StoryId '4965976' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($err -join "`n") | Should -Match '(?i)No -SessionOutcome was given'
    }

    Context 'the close sequence against shims' {

        It 'skips the bundle when EI_GRAPHICS_SHARE_PATH is not set' {
            $box = New-Sandbox -Shims @{ Finalize = $script:HappyFinalizeShim; Summary = $script:HappySummaryShim; Bundle = $script:HappyBundleShim }
            $out = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $result = ($out -join "`n") | ConvertFrom-Json
            $result.summaryPath | Should -Be 'stub/session-summary.md'
            $result.bundlePath | Should -BeNullOrEmpty
            $result.shareStatus | Should -Be 'skipped'
            (Get-CallSteps -Path $box.CallLog) | Should -Be @('finalize', 'summary')
        }

        It 'runs the bundle when EI_GRAPHICS_SHARE_PATH is set' {
            $box = New-Sandbox -Shims @{ Finalize = $script:HappyFinalizeShim; Summary = $script:HappySummaryShim; Bundle = $script:HappyBundleShim }
            $env:EI_GRAPHICS_SHARE_PATH = 'C:/share'
            $out = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $result = ($out -join "`n") | ConvertFrom-Json
            $result.summaryPath | Should -Be 'stub/session-summary.md'
            $result.bundlePath | Should -Be 'stub/share/4965976-001'
            $result.shareStatus | Should -Be 'exported'
            (Get-CallSteps -Path $box.CallLog) | Should -Be @('finalize', 'summary', 'bundle')
        }

        It 'passes the env share path through to the bundle shim' {
            $box = New-Sandbox -Shims @{ Finalize = $script:HappyFinalizeShim; Summary = $script:HappySummaryShim; Bundle = $script:HappyBundleShim }
            $env:EI_GRAPHICS_SHARE_PATH = 'D:/other-share'
            $null = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $bundleRecord = @(Get-Content -LiteralPath $box.CallLog | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.step -eq 'bundle' })[0]
            $bundleRecord.SharePath | Should -Be 'D:/other-share'
        }

        It 'exits 1 and names the failing step when finalize fails' {
            $failingFinalize = @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [switch]$Finalize, [string]$SessionOutcome, [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('finalize broke on purpose')
exit 1
'@
            $box = New-Sandbox -Shims @{ Finalize = $failingFinalize; Summary = $script:HappySummaryShim; Bundle = $script:HappyBundleShim }
            $err = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)Step 1 failed'
            ($err -join "`n") | Should -Match '(?i)Write-EiSessionEntry\.ps1'
            (Get-CallSteps -Path $box.CallLog) | Should -BeNullOrEmpty
        }

        It 'exits 1 and names the failing step when summary fails' {
            $failingSummary = @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('summary broke on purpose')
exit 1
'@
            $box = New-Sandbox -Shims @{ Finalize = $script:HappyFinalizeShim; Summary = $failingSummary; Bundle = $script:HappyBundleShim }
            $err = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)Step 2 failed'
            ($err -join "`n") | Should -Match '(?i)Export-EiSessionSummary\.ps1'
        }

        It 'warns but still exits 0 when the share export fails' {
            $failingBundle = @'
[CmdletBinding()]
param([string]$StoryId, [string]$Root='.', [string]$SharePath, [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('bundle broke on purpose')
exit 1
'@
            $box = New-Sandbox -Shims @{ Finalize = $script:HappyFinalizeShim; Summary = $script:HappySummaryShim; Bundle = $failingBundle }
            $env:EI_GRAPHICS_SHARE_PATH = 'C:/share'
            $out = pwsh -NoProfile -File $box.Wrapper -StoryId '4965976' -SessionOutcome 'success' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            ($out -join "`n") | Should -Match '(?i)Warning:.*Export-EiSessionBundleToShare'
            # The JSON object is at the end of the merged stream. ConvertTo-Json without -Compress
            # produces several lines, so cut from the last line that opens an object down.
            $lines = @($out | ForEach-Object { $_.ToString() })
            $openAt = -1
            for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^\s*\{\s*$') { $openAt = $i; break } }
            $openAt | Should -BeGreaterOrEqual 0 -Because "the wrapper's -Json output must be on the stream"
            $result = ($lines[$openAt..($lines.Count - 1)] -join "`n") | ConvertFrom-Json
            $result.summaryPath | Should -Be 'stub/session-summary.md'
            $result.bundlePath | Should -BeNullOrEmpty
            $result.shareStatus | Should -Be 'failed'
        }
    }
}
