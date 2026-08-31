#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Test-EiScopeDrift.ps1'

    function New-ApprovedFiles {
        param([string[]] $Paths, [string] $StoryId = '4965976')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $folder = Join-Path $root '.ei-session-logs' $StoryId
        $null = New-Item -ItemType Directory -Path $folder -Force
        $payload = [ordered]@{
            schemaVersion     = '1.0.0'
            storyId           = $StoryId
            understandingHash = 'sha256:' + ('c' * 64)
            approvedAt        = '2026-08-26T09:02:45Z'
            approvedBy        = 'a.person'
            approvalType      = 'direct'
            files             = @($Paths | ForEach-Object {
                [ordered]@{ path = $_; intent = 'modify'; reason = 'agreed with the reviewer' }
            })
            hash              = 'sha256:' + ('d' * 64)
        }
        Set-Content -LiteralPath (Join-Path $folder 'approved-files.json') -Encoding utf8NoBOM `
            -Value ($payload | ConvertTo-Json -Depth 10)
        $root
    }

    function Invoke-Drift {
        param([string] $Root, [string[]] $ChangedFiles, [string] $StoryId = '4965976')
        # Called in process on purpose. Running this with pwsh -File flattens the array and the
        # gate passes silently, which is the trap Part 8 warns about.
        $output = & $script:ScriptPath -StoryId $StoryId -Root $Root -ChangedFiles $ChangedFiles
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }
}

Describe 'Test-EiScopeDrift' -Tag 'Unit' {

    It 'passes when the changed files match the approved files exactly' {
        $root = New-ApprovedFiles -Paths @('src/A.cs', 'src/B.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('src/A.cs', 'src/B.cs')
        $run.Result.status | Should -Be 'pass'
        @($run.Result.unapproved).Count | Should -Be 0
        @($run.Result.approvedUnchanged).Count | Should -Be 0
        $run.ExitCode | Should -Be 0
    }

    It 'reports drift and names the extra file' {
        $root = New-ApprovedFiles -Paths @('src/A.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('src/A.cs', 'src/Sneaky.cs')
        $run.Result.status | Should -Be 'drift'
        @($run.Result.unapproved) | Should -Be @('src/Sneaky.cs')
        $run.ExitCode | Should -Be 1
    }

    It 'reports an approved file nobody touched as a warning, not a failure' {
        $root = New-ApprovedFiles -Paths @('src/A.cs', 'src/Untouched.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('src/A.cs')
        $run.Result.status | Should -Be 'pass'
        @($run.Result.approvedUnchanged) | Should -Be @('src/Untouched.cs')
        $run.ExitCode | Should -Be 0
    }

    It 'keeps a multi-item list intact when called in process' {
        # Guards the array flattening trap directly.
        $root = New-ApprovedFiles -Paths @('src/A.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('one.cs', 'two.cs', 'three.cs')
        @($run.Result.unapproved).Count | Should -Be 3
    }

    It 'treats backslashes and a leading dot-slash as the same path' {
        $root = New-ApprovedFiles -Paths @('src/A.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('.\src\A.cs')
        $run.Result.status | Should -Be 'pass'
        $run.ExitCode | Should -Be 0
    }

    It 'reports both an unapproved change and an untouched approval at once' {
        $root = New-ApprovedFiles -Paths @('src/A.cs', 'src/B.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @('src/A.cs', 'src/C.cs')
        $run.Result.status | Should -Be 'drift'
        @($run.Result.unapproved) | Should -Be @('src/C.cs')
        @($run.Result.approvedUnchanged) | Should -Be @('src/B.cs')
        $run.ExitCode | Should -Be 1
    }

    It 'passes when nothing changed at all' {
        $root = New-ApprovedFiles -Paths @('src/A.cs')
        $run = Invoke-Drift -Root $root -ChangedFiles @()
        $run.Result.status | Should -Be 'pass'
        @($run.Result.approvedUnchanged) | Should -Be @('src/A.cs')
        $run.ExitCode | Should -Be 0
    }

    It 'emits JSON on stdout with -Json' {
        $root = New-ApprovedFiles -Paths @('src/A.cs')
        $raw = & $script:ScriptPath -StoryId '4965976' -Root $root -ChangedFiles @('src/A.cs') -Json
        (($raw -join "`n") | ConvertFrom-Json).status | Should -Be 'pass'
    }

    It 'exits 1 when there is no approved-files.json' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root -Force
        $null = & $script:ScriptPath -StoryId '4965976' -Root $root -ChangedFiles @('src/A.cs')
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 1 when no story id is given' {
        $null = & $script:ScriptPath -Root $TestDrive -ChangedFiles @('src/A.cs')
        $LASTEXITCODE | Should -Be 1
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
