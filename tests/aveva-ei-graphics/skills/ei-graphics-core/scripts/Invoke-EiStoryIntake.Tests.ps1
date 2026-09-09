#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:WrapperPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts' 'Invoke-EiStoryIntake.ps1'

    function New-Sandbox {
        <#
            Stage a sandbox with the real wrapper alongside shim sub-scripts that echo canned JSON.
            The wrapper resolves its dependencies from $PSScriptRoot, so copying it into the same
            folder layout makes it call the shims instead of the real scripts.
        #>
        param([hashtable] $Shims)
        $sandbox = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $core = Join-Path $sandbox 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core' 'scripts'
        $ado  = Join-Path $sandbox 'plugins' 'aveva-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'scripts'
        $null = New-Item -ItemType Directory -Path $core -Force
        $null = New-Item -ItemType Directory -Path $ado -Force

        Copy-Item -LiteralPath $script:WrapperPath -Destination (Join-Path $core 'Invoke-EiStoryIntake.ps1')

        Set-Content -LiteralPath (Join-Path $ado 'Invoke-EiAdoCliIntake.ps1') -Value $Shims.Intake -Encoding utf8
        Set-Content -LiteralPath (Join-Path $core 'Convert-EiAdoIntake.ps1')  -Value $Shims.Convert -Encoding utf8
        Set-Content -LiteralPath (Join-Path $core 'Write-EiArtifact.ps1')     -Value $Shims.Write   -Encoding utf8

        [pscustomobject]@{
            SandboxRoot = $sandbox
            Wrapper     = Join-Path $core 'Invoke-EiStoryIntake.ps1'
            IntakeArgs  = Join-Path $sandbox 'intake-args.json'
        }
    }

    $script:HappyIntakeShim = @'
[CmdletBinding()]
param(
    [string]$WorkItemUrl='', [string]$WorkItemId='', [string]$Organization='', [string]$Project='',
    [string]$CliWorkItemJson='', [string]$CliCommentsJson='', [switch]$Json
)
Set-StrictMode -Version Latest
$argsPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))) 'intake-args.json'
@{ WorkItemUrl = $WorkItemUrl; WorkItemId = $WorkItemId } | ConvertTo-Json | Set-Content -LiteralPath $argsPath -Encoding utf8
Write-Output '{"status":"retrieved","workItemContext":{"workItemId":"9999","workItemUrl":"https://example/9999"},"descriptionText":"ok","attachmentUrls":[],"commentRetrieval":{"status":"retrieved","reason":"cli-mock-json"},"comments":[]}'
exit 0
'@

    $script:HappyConvertShim = @'
[CmdletBinding()]
param([string]$IntakeJson, [string]$StoryId, [string]$Summary, [string]$Root='.', [switch]$SkipAttachmentDownload, [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
if ($Help) { 'SYNOPSIS'; exit 0 }
$body = @{ schemaVersion = '1.0.0'; source = 'ado'; storyId = $StoryId; sawIntake = ($IntakeJson.Length -gt 0) } | ConvertTo-Json -Compress
Write-Output $body
exit 0
'@

    $script:HappyWriteShim = @'
[CmdletBinding()]
param([string]$StoryId, [string]$ArtifactType, [object]$InputObject, [string]$InputJson, [string]$Root='.', [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
if ($Help) { 'SYNOPSIS'; exit 0 }
$body = @{ path = "stub/$ArtifactType.json"; storyId = $StoryId; hash = $null; sawInput = ($InputJson.Length -gt 0) } | ConvertTo-Json -Compress
Write-Output $body
exit 0
'@
}

Describe 'Invoke-EiStoryIntake' -Tag 'Unit' {

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:WrapperPath -Help
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 when no -WorkItem is given' {
        $err = pwsh -NoProfile -File $script:WrapperPath -StoryId '4965976' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($err -join "`n") | Should -Match '(?i)No -WorkItem was given'
    }

    It 'exits 1 when no -StoryId is given' {
        $err = pwsh -NoProfile -File $script:WrapperPath -WorkItem '9999' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($err -join "`n") | Should -Match '(?i)No -StoryId was given'
    }

    Context 'the three-step pipe against shims' {

        It 'runs all three steps and returns the write result' {
            $env = New-Sandbox -Shims @{ Intake = $script:HappyIntakeShim; Convert = $script:HappyConvertShim; Write = $script:HappyWriteShim }
            $out = pwsh -NoProfile -File $env.Wrapper -WorkItem '9999' -StoryId '4965976' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $result = ($out -join "`n") | ConvertFrom-Json
            $result.path | Should -Be 'stub/ado.json'
            $result.storyId | Should -Be '4965976'
            $result.hash | Should -BeNullOrEmpty
            $result.sawInput | Should -BeTrue -Because 'Write-EiArtifact must have received the converted JSON'
        }

        It 'routes a bare integer to -WorkItemId' {
            $env = New-Sandbox -Shims @{ Intake = $script:HappyIntakeShim; Convert = $script:HappyConvertShim; Write = $script:HappyWriteShim }
            $null = pwsh -NoProfile -File $env.Wrapper -WorkItem '9999' -StoryId '4965976' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $captured = Get-Content -LiteralPath $env.IntakeArgs -Raw | ConvertFrom-Json
            $captured.WorkItemId | Should -Be '9999'
            $captured.WorkItemUrl | Should -BeNullOrEmpty
        }

        It 'routes a URL to -WorkItemUrl' {
            $env = New-Sandbox -Shims @{ Intake = $script:HappyIntakeShim; Convert = $script:HappyConvertShim; Write = $script:HappyWriteShim }
            $url = 'https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/9999'
            $null = pwsh -NoProfile -File $env.Wrapper -WorkItem $url -StoryId '4965976' -Json 2>&1
            $LASTEXITCODE | Should -Be 0
            $captured = Get-Content -LiteralPath $env.IntakeArgs -Raw | ConvertFrom-Json
            $captured.WorkItemUrl | Should -Be $url
            $captured.WorkItemId | Should -BeNullOrEmpty
        }

        It 'exits 1 and names the failing step when the intake shim fails' {
            $failingIntake = @'
[CmdletBinding()]
param([string]$WorkItemUrl='', [string]$WorkItemId='', [string]$Organization='', [string]$Project='', [string]$CliWorkItemJson='', [string]$CliCommentsJson='', [switch]$Json)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('intake broke on purpose')
exit 1
'@
            $env = New-Sandbox -Shims @{ Intake = $failingIntake; Convert = $script:HappyConvertShim; Write = $script:HappyWriteShim }
            $err = pwsh -NoProfile -File $env.Wrapper -WorkItem '9999' -StoryId '4965976' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)Step 1 failed'
            ($err -join "`n") | Should -Match '(?i)Invoke-EiAdoCliIntake\.ps1'
        }

        It 'exits 1 and names the failing step when the converter shim fails' {
            $failingConvert = @'
[CmdletBinding()]
param([string]$IntakeJson, [string]$StoryId, [string]$Summary, [string]$Root='.', [switch]$SkipAttachmentDownload, [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('converter broke on purpose')
exit 1
'@
            $env = New-Sandbox -Shims @{ Intake = $script:HappyIntakeShim; Convert = $failingConvert; Write = $script:HappyWriteShim }
            $err = pwsh -NoProfile -File $env.Wrapper -WorkItem '9999' -StoryId '4965976' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)Step 2 failed'
            ($err -join "`n") | Should -Match '(?i)Convert-EiAdoIntake\.ps1'
        }

        It 'exits 1 and names the failing step when the writer shim fails' {
            $failingWrite = @'
[CmdletBinding()]
param([string]$StoryId, [string]$ArtifactType, [object]$InputObject, [string]$InputJson, [string]$Root='.', [switch]$Json, [switch]$Help)
Set-StrictMode -Version Latest
[Console]::Error.WriteLine('writer broke on purpose')
exit 1
'@
            $env = New-Sandbox -Shims @{ Intake = $script:HappyIntakeShim; Convert = $script:HappyConvertShim; Write = $failingWrite }
            $err = pwsh -NoProfile -File $env.Wrapper -WorkItem '9999' -StoryId '4965976' 2>&1
            $LASTEXITCODE | Should -Be 1
            ($err -join "`n") | Should -Match '(?i)Step 3 failed'
            ($err -join "`n") | Should -Match '(?i)Write-EiArtifact\.ps1'
        }
    }
}
