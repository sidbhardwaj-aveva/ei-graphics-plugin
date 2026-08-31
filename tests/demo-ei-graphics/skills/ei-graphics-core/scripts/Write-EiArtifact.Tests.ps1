#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:ScriptPath = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core' 'scripts' 'Write-EiArtifact.ps1'
    $script:SchemaDir = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core' 'schemas'

    $filler = 'sha256:' + ('b' * 64)

    function New-Understanding {
        [ordered]@{
            schemaVersion    = '1.0.0'
            storyId          = '4965976'
            adoHash          = 'sha256:' + ('b' * 64)
            status           = 'confirmed'
            understanding    = [ordered]@{
                subject         = 'Core connectors are missing after an update'
                expectedOutcome = 'They are inserted at the restored levels'
                requirements    = @([ordered]@{ text = 'Do not skip insertion'; source = 'description' })
            }
            proposedDomains  = @([ordered]@{ domainId = 'termination-drawing'; reason = 'Core connectors'; confidence = 'high' })
            confirmedDomains = @('termination-drawing')
            complexity       = [ordered]@{ assessment = 'small'; reasoning = 'One file, one method' }
        }
    }

    function New-AdoPayload {
        [ordered]@{
            schemaVersion = '1.0.0'
            source        = 'ei-azure-devops-cli-intake'
            storyId       = '4965976'
            storyRef      = 'https://dev.azure.com/org/proj/_workitems/edit/4965976'
            summary       = 'Core connector not inserted after update'
            description   = 'After the second update the core connectors are missing.'
            workItem      = [ordered]@{
                id           = '4965976'
                organization = 'org'
                project      = 'proj'
                url          = 'https://dev.azure.com/org/proj/_workitems/edit/4965976'
            }
            retrieval     = [ordered]@{ status = 'retrieved'; reason = 'ok'; authSource = 'az-cli' }
            retrievedAt   = '2026-08-26T09:00:01Z'
        }
    }

    function Invoke-Writer {
        param([hashtable] $Splat)
        $output = & $script:ScriptPath @Splat
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }
}

Describe 'Write-EiArtifact' -Tag 'Unit' {

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Root -Force
    }

    It 'writes a valid story-understanding artifact' {
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = (New-Understanding); Root = $script:Root
        }
        $run.ExitCode | Should -Be 0
        Test-Path -LiteralPath $run.Result.path | Should -BeTrue
        $run.Result.path | Should -BeLike '*.ei-session-logs*4965976*story-understanding.json'
    }

    It 'stamps a hash of the right shape' {
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = (New-Understanding); Root = $script:Root
        }
        $run.Result.hash | Should -Match '^sha256:[0-9a-f]{64}$'
        $written = Get-Content -LiteralPath $run.Result.path -Raw | ConvertFrom-Json
        $written.hash | Should -Be $run.Result.hash
    }

    It 'rejects an invalid payload and writes nothing' {
        $bad = New-Understanding
        $bad.status = 'maybe'
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = $bad; Root = $script:Root
        }
        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:Root '.ei-session-logs' '4965976' 'story-understanding.json') | Should -BeFalse
    }

    It 'is safe to run twice' {
        $splat = @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = (New-Understanding); Root = $script:Root
        }
        $first = Invoke-Writer -Splat $splat
        $second = Invoke-Writer -Splat $splat
        $second.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $first.Result.path -Raw) | Should -Be (Get-Content -LiteralPath $second.Result.path -Raw)
    }

    It 'gives the same hash across two runs' {
        $splat = @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = (New-Understanding); Root = $script:Root
        }
        (Invoke-Writer -Splat $splat).Result.hash | Should -Be (Invoke-Writer -Splat $splat).Result.hash
    }

    It 'gives the same hash when the input key order changes' {
        $forward = New-Understanding
        $reversed = [ordered]@{}
        foreach ($key in (@($forward.Keys) | Sort-Object -Descending)) { $reversed[$key] = $forward[$key] }

        $a = Invoke-Writer -Splat @{ StoryId = '1'; ArtifactType = 'story-understanding'; InputObject = $forward; Root = $script:Root }
        $b = Invoke-Writer -Splat @{ StoryId = '2'; ArtifactType = 'story-understanding'; InputObject = $reversed; Root = $script:Root }
        $a.Result.hash | Should -Be $b.Result.hash
    }

    It 'accepts a payload given as text through -InputJson' {
        $text = (New-Understanding) | ConvertTo-Json -Depth 20
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputJson = $text; Root = $script:Root
        }
        $run.ExitCode | Should -Be 0
        $run.Result.hash | Should -Match '^sha256:[0-9a-f]{64}$'
    }

    It 'writes an approved-files artifact' {
        $payload = [ordered]@{
            schemaVersion     = '1.0.0'
            storyId           = '4965976'
            understandingHash = 'sha256:' + ('c' * 64)
            approvedAt        = '2026-08-26T09:02:45Z'
            approvedBy        = 'a.person'
            approvalType      = 'direct'
            files             = @([ordered]@{ path = 'src/A.cs'; intent = 'modify'; reason = 'Fix the guard' })
        }
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'approved-files'
            InputObject = $payload; Root = $script:Root
        }
        $run.ExitCode | Should -Be 0
        $run.Result.hash | Should -Match '^sha256:[0-9a-f]{64}$'
    }

    Context 'the ado artifact is the exception' {
        It 'writes an ado.json that validates against the copied schema' {
            $run = Invoke-Writer -Splat @{
                StoryId = '4965976'; ArtifactType = 'ado'
                InputObject = (New-AdoPayload); Root = $script:Root
            }
            $run.ExitCode | Should -Be 0
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'ado.schema.json') -Raw
            Get-Content -LiteralPath $run.Result.path -Raw | Test-Json -Schema $schema | Should -BeTrue
        }

        It 'writes no hash property onto ado.json' {
            # ado.schema.json sets additionalProperties to false and declares no hash. Stamping one
            # would make every ado.json fail. ADO content is bound instead by adoHash inside
            # story-understanding.json.
            $run = Invoke-Writer -Splat @{
                StoryId = '4965976'; ArtifactType = 'ado'
                InputObject = (New-AdoPayload); Root = $script:Root
            }
            $written = Get-Content -LiteralPath $run.Result.path -Raw | ConvertFrom-Json
            $written.PSObject.Properties.Name | Should -Not -Contain 'hash'
            $run.Result.hash | Should -BeNullOrEmpty
        }
    }

    Context 'it says what to do when something is missing' {
        It 'exits 1 when no payload is given' {
            $run = Invoke-Writer -Splat @{ StoryId = '4965976'; ArtifactType = 'ado'; Root = $script:Root }
            $run.ExitCode | Should -Be 1
        }

        It 'exits 1 when no story id is given' {
            $run = Invoke-Writer -Splat @{ ArtifactType = 'ado'; InputObject = (New-AdoPayload); Root = $script:Root }
            $run.ExitCode | Should -Be 1
        }

        It 'exits 1 when -InputJson is not valid JSON' {
            $run = Invoke-Writer -Splat @{
                StoryId = '4965976'; ArtifactType = 'ado'; InputJson = 'not json'; Root = $script:Root
            }
            $run.ExitCode | Should -Be 1
        }
    }

    It 'writes the file as UTF-8 with no byte order mark and LF line endings' {
        $run = Invoke-Writer -Splat @{
            StoryId = '4965976'; ArtifactType = 'story-understanding'
            InputObject = (New-Understanding); Root = $script:Root
        }
        $bytes = [System.IO.File]::ReadAllBytes($run.Result.path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        ([System.IO.File]::ReadAllText($run.Result.path)) | Should -Not -Match "`r"
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
