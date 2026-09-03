#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Convert-EiAdoIntake.ps1'
    $script:WriterPath = Join-Path $core 'scripts' 'Write-EiArtifact.ps1'
    $script:AdoSchema = Get-Content -LiteralPath (Join-Path $core 'schemas' 'ado.schema.json') -Raw
    $script:FixturePath = Join-Path $repoRoot 'tests' 'fixtures' 'ado-intake-stdout.json'
    $script:FixtureText = Get-Content -LiteralPath $script:FixturePath -Raw

    function Get-Intake { $script:FixtureText | ConvertFrom-Json }

    function Invoke-Convert {
        param([string] $IntakeJson, [hashtable] $Extra = @{})
        $splat = @{ IntakeJson = $IntakeJson; StoryId = '4965976'; SkipAttachmentDownload = $true } + $Extra
        $output = & $script:ScriptPath @splat
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }
}

Describe 'Convert-EiAdoIntake' -Tag 'Unit' {

    Context 'a clean retrieval' {
        BeforeEach {
            $script:Run = Invoke-Convert -IntakeJson $script:FixtureText
            $script:Artifact = $script:Run.Result
        }

        It 'exits 0 and its output validates against the copied schema' {
            $script:Run.ExitCode | Should -Be 0
            ($script:Artifact | ConvertTo-Json -Depth 20) | Test-Json -Schema $script:AdoSchema | Should -BeTrue
        }

        It 'sets schemaVersion and source to their fixed values' {
            $script:Artifact.schemaVersion | Should -Be '1.0.0'
            $script:Artifact.source | Should -Be 'ei-azure-devops-cli-intake'
        }

        It 'takes storyId from the parameter, not from the payload' {
            $script:Artifact.storyId | Should -Be '4965976'
        }

        It 'takes storyRef and workItem.url from workItemContext.workItemUrl' {
            $expected = (Get-Intake).workItemContext.workItemUrl
            $script:Artifact.storyRef | Should -Be $expected
            $script:Artifact.workItem.url | Should -Be $expected
        }

        It 'takes description from descriptionText' {
            $script:Artifact.description | Should -Be (Get-Intake).descriptionText
        }

        It 'takes the work item id, organization and project from workItemContext' {
            $context = (Get-Intake).workItemContext
            $script:Artifact.workItem.id | Should -Be $context.workItemId
            $script:Artifact.workItem.id | Should -BeOfType [string]
            $script:Artifact.workItem.organization | Should -Be $context.organization
            $script:Artifact.workItem.project | Should -Be $context.project
        }

        It 'takes retrieval status and reason from the top level, and authSource from the context' {
            $intake = Get-Intake
            $script:Artifact.retrieval.status | Should -Be $intake.status
            $script:Artifact.retrieval.reason | Should -Be $intake.reason
            $script:Artifact.retrieval.authSource | Should -Be $intake.workItemContext.authSource
        }

        It 'stamps retrievedAt as a UTC timestamp with no fractional seconds' {
            $script:Artifact.retrievedAt | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        }

        It 'copies commentRetrieval straight across' {
            $expected = (Get-Intake).commentRetrieval
            $script:Artifact.commentRetrieval.status | Should -Be $expected.status
            $script:Artifact.commentRetrieval.reason | Should -Be $expected.reason
        }

        It 'copies the comments and reformats a date that arrived as a DateTime' {
            # ConvertFrom-Json turns the first createdDate into a DateTime. The second is not a
            # date at all and must pass through untouched.
            @($script:Artifact.comments).Count | Should -Be 2
            $script:Artifact.comments[0].id | Should -Be '12'
            $script:Artifact.comments[0].author | Should -Be 'a.reviewer'
            $script:Artifact.comments[0].createdDate | Should -Be '2026-08-25T10:00:00Z'
            $script:Artifact.comments[1].createdDate | Should -Be 'yesterday afternoon'
        }

        It 'leaves summary null when none is given' {
            $script:Artifact.summary | Should -BeNullOrEmpty
        }

        It 'emits no attachments key when the download is skipped' {
            $script:Artifact.Keys | Should -Not -Contain 'attachments'
        }
    }

    It 'uses -Summary when one is given' {
        $run = Invoke-Convert -IntakeJson $script:FixtureText -Extra @{ Summary = 'Core connector not inserted' }
        $run.Result.summary | Should -Be 'Core connector not inserted'
        ($run.Result | ConvertTo-Json -Depth 20) | Test-Json -Schema $script:AdoSchema | Should -BeTrue
    }

    Context 'it refuses anything that is not a clean retrieval' {
        It 'exits 1 when the status is not retrieved, and names the work item' {
            $intake = Get-Intake
            $intake.status = 'failed'
            $intake.reason = 'ado-response-missing-fields'
            $run = Invoke-Convert -IntakeJson ($intake | ConvertTo-Json -Depth 20)
            $run.ExitCode | Should -Be 1
        }

        It 'exits 1 when the description is empty' {
            $intake = Get-Intake
            $intake.descriptionText = ''
            (Invoke-Convert -IntakeJson ($intake | ConvertTo-Json -Depth 20)).ExitCode | Should -Be 1
        }

        It 'exits 1 when the work item id is <_>' -ForEach @('', '0', '007', 'abc') {
            $intake = Get-Intake
            $intake.workItemContext.workItemId = $_
            (Invoke-Convert -IntakeJson ($intake | ConvertTo-Json -Depth 20)).ExitCode | Should -Be 1
        }

        It 'exits 1 when -IntakeJson is not valid JSON' {
            (Invoke-Convert -IntakeJson 'not json').ExitCode | Should -Be 1
        }

        It 'exits 1 when no story id is given' {
            $null = & $script:ScriptPath -IntakeJson $script:FixtureText -SkipAttachmentDownload
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'feeds Write-EiArtifact.ps1 an ado.json with no hash property' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root -Force

        $artifact = (Invoke-Convert -IntakeJson $script:FixtureText).Result
        $written = & $script:WriterPath -StoryId '4965976' -ArtifactType 'ado' -InputObject $artifact -Root $root
        $LASTEXITCODE | Should -Be 0

        $raw = Get-Content -LiteralPath $written.path -Raw
        $raw | Test-Json -Schema $script:AdoSchema | Should -BeTrue
        ($raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'hash'
        $written.hash | Should -BeNullOrEmpty
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
