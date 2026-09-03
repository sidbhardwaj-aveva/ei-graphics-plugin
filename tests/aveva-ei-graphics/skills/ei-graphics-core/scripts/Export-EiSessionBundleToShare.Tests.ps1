#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Export-EiSessionBundleToShare.ps1'
    $script:ArtifactNames = @('ado.json', 'story-understanding.json', 'approved-files.json', 'session.json', 'session-summary.md')

    function New-SessionBundle {
        param([string] $StoryId = '4965976')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $folder = Join-Path $root '.ei-session-logs' $StoryId
        $null = New-Item -ItemType Directory -Path $folder -Force
        foreach ($name in $script:ArtifactNames) {
            $content = "artifact: $name"
            if ($name -eq 'session.json') { $content = '{"summary":{"completedAt":"2026-09-03T11:00:00Z"}}' }
            [System.IO.File]::WriteAllText((Join-Path $folder $name), $content, [System.Text.UTF8Encoding]::new($false))
        }
        $root
    }

    function Invoke-Export {
        param([hashtable] $Splat)
        $output = & $script:ScriptPath @Splat
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }
}

Describe 'Export-EiSessionBundleToShare' -Tag 'Unit' {

    It 'copies every completed artifact unchanged into a unique folder' {
        $root = New-SessionBundle
        $share = Join-Path $TestDrive 'share'
        $run = Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = $share; Json = $true }
        $run.ExitCode | Should -Be 0
        $result = $run.Result | ConvertFrom-Json
        $result.status | Should -Be 'exported'
        Test-Path -LiteralPath $result.exportedPath -PathType Container | Should -BeTrue
        foreach ($name in $script:ArtifactNames) {
            $source = Join-Path $root '.ei-session-logs' '4965976' $name
            $copy = Join-Path $result.exportedPath $name
            (Get-FileHash -LiteralPath $copy).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
        }
    }

    It 'does not overwrite an earlier export of the same story' {
        $root = New-SessionBundle
        $share = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $first = (Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = $share; Json = $true }).Result | ConvertFrom-Json
        $second = (Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = $share; Json = $true }).Result | ConvertFrom-Json
        $first.exportedPath | Should -Not -Be $second.exportedPath
        @(Get-ChildItem -LiteralPath $share -Directory).Count | Should -Be 2
    }

    It 'exits 1 when the local bundle is incomplete' {
        $root = New-SessionBundle
        Remove-Item -LiteralPath (Join-Path $root '.ei-session-logs' '4965976' 'ado.json')
        $run = Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = (Join-Path $TestDrive 'share') }
        $run.ExitCode | Should -Be 1
    }

    It 'exits 1 when the session was not finalized' {
        $root = New-SessionBundle
        Set-Content -LiteralPath (Join-Path $root '.ei-session-logs' '4965976' 'session.json') -Encoding utf8NoBOM -Value '{}'
        $run = Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = (Join-Path $TestDrive 'share') }
        $run.ExitCode | Should -Be 1
    }

    It 'keeps the local bundle and exits 0 when the share is unavailable' {
        $root = New-SessionBundle
        $blockedShare = Join-Path $TestDrive 'blocked-share'
        Set-Content -LiteralPath $blockedShare -Encoding utf8NoBOM -Value 'not a directory'
        $run = Invoke-Export -Splat @{ StoryId = '4965976'; Root = $root; SharePath = $blockedShare; Json = $true }
        $run.ExitCode | Should -Be 0
        ($run.Result | ConvertFrom-Json).status | Should -Be 'retained-locally'
        Test-Path -LiteralPath (Join-Path $root '.ei-session-logs' '4965976' 'session-summary.md') | Should -BeTrue
    }

    It 'prints help and exits 0' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}