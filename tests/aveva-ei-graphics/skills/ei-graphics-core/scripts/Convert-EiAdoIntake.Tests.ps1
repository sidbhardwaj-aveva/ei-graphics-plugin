#Requires -Version 7.0
Set-StrictMode -Version Latest

# Discovery-time data. Pester needs -ForEach filled before any BeforeAll block runs.
# The middle two are the reason the check parses the host instead of matching text: both carry
# the words an unanchored pattern looks for, and neither is Azure DevOps.
$RefusedAddresses = @(
    'https://dev.azure.com.attacker.example/_apis/wit/attachments/1?fileName=a.png'
    'https://attacker.example/collect?u=dev.azure.com&fileName=a.png'
    'https://notvisualstudio.com/_apis/wit/attachments/1?fileName=a.png'
    'http://dev.azure.com/org/_apis/wit/attachments/1?fileName=a.png'
)

# Names a work item can put in the fileName part of an attachment address. Four `..` segments
# climb no higher than TestDrive from the attachments folder, so a broken check cannot reach a
# real folder from here.
$HostileNames = @(
    '..%2F..%2F..%2F..%2Fescaped.png'
    '..%5C..%5C..%5C..%5Cescaped.png'
    'C%3A%5CWindows%5CTemp%5Cescaped.png'
    '%20%20'
)

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

    # The download step is driven for real. Only the two things that leave this machine are
    # replaced: the token call, and the request itself, which records what it was given.
    function az {
        $global:LASTEXITCODE = 0
        '{"accessToken":"test-token"}'
    }

    function Invoke-WebRequest {
        param([string] $Uri, $Headers, [string] $OutFile, $ErrorAction)
        $global:EiRequested.Add([pscustomobject]@{
            Uri           = $Uri
            Authorization = $Headers['Authorization']
        })
        Set-Content -LiteralPath $OutFile -Value 'image bytes' -Encoding utf8NoBOM
    }

    function Invoke-Download {
        param([string[]] $Address)

        $global:EiRequested = [System.Collections.Generic.List[object]]::new()
        $intake = Get-Intake
        $intake.attachmentUrls = @($Address | ForEach-Object {
            [pscustomobject]@{ url = $_; source = 'field:System.Description' }
        })

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root -Force

        # Write-Problem goes to the console error stream, which no PowerShell redirection
        # catches. Swapping the writer is what makes the warning readable in process.
        $writer = [System.IO.StringWriter]::new()
        $original = [Console]::Error
        [Console]::SetError($writer)
        try {
            $artifact = & $script:ScriptPath -IntakeJson ($intake | ConvertTo-Json -Depth 20) -StoryId '4965976' -Root $root
        } finally {
            [Console]::SetError($original)
        }

        $folder = Join-Path $root '.ei-session-logs' '4965976' 'attachments'
        [pscustomobject]@{
            Attachments = @($artifact.attachments)
            Requested   = @($global:EiRequested)
            Warnings    = $writer.ToString()
            Root        = $root
            Folder      = $folder
            Files       = @(Get-ChildItem -LiteralPath $folder -File | ForEach-Object { $_.Name })
        }
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

    Context 'it sends the token only to Azure DevOps' {
        It 'downloads from <_> and sends the header there' -ForEach @(
            'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/1111?fileName=rail.png'
            'https://avevagroup.visualstudio.com/EI/_apis/wit/attachments/1111?fileName=rail.png'
        ) {
            $run = Invoke-Download -Address $_
            $run.Requested.Count | Should -Be 1
            $run.Requested[0].Uri | Should -Be $_
            $run.Requested[0].Authorization | Should -Be 'Bearer test-token'
            $run.Attachments.Count | Should -Be 1
            $run.Attachments[0].url | Should -Be $_
        }

        It 'refuses <_>, and sends nothing to it' -ForEach $RefusedAddresses {
            $run = Invoke-Download -Address $_
            $run.Requested.Count | Should -Be 0
            $run.Attachments.Count | Should -Be 0
            $run.Warnings | Should -Match ([regex]::Escape($_))
            @(Get-ChildItem -LiteralPath $run.Folder -File).Count | Should -Be 0
        }

        It 'a refused address leaves the other attachments untouched' {
            $bad = 'https://dev.azure.com.attacker.example/_apis/wit/attachments/1?fileName=a.png'
            $good = 'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/2222?fileName=after.png'
            $run = Invoke-Download -Address @($bad, $good)

            $run.Requested.Count | Should -Be 1
            $run.Requested[0].Uri | Should -Be $good
            $run.Attachments.Count | Should -Be 1
            $run.Attachments[0].url | Should -Be $good
            @(Get-ChildItem -LiteralPath $run.Folder -File).Count | Should -Be 1
        }
    }

    Context 'it saves an attachment under a name it cannot choose' {
        It 'adds the index prefix and changes nothing else about an ordinary name' {
            $run = Invoke-Download -Address 'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/1111?fileName=rail.png'
            $run.Attachments[0].fileName | Should -Be '1-rail.png'
            $run.Files | Should -Be @('1-rail.png')
        }

        It 'writes nothing outside the attachments folder for the name <_>' -ForEach $HostileNames {
            $run = Invoke-Download -Address "https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/1111?fileName=$_"

            $inside = [System.IO.Path]::GetFullPath($run.Folder)
            $stray = @(
                Get-ChildItem -LiteralPath $run.Root -File -Recurse |
                    Where-Object { [System.IO.Path]::GetFullPath($_.DirectoryName) -ne $inside }
            )
            $stray.Count | Should -Be 0 -Because "these were written elsewhere: $($stray.FullName -join ', ')"

            foreach ($attachment in $run.Attachments) {
                [System.IO.Path]::GetFullPath($attachment.localPath) | Should -BeLike "$inside*"
            }
        }

        It 'falls back to the index name when nothing usable is left' {
            $run = Invoke-Download -Address 'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/1111?fileName=%20%20'
            $run.Files | Should -Be @('1-image-1.png')
        }

        It 'keeps only the leaf of a name that carries a folder' {
            $run = Invoke-Download -Address 'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/1111?fileName=C%3A%5CWindows%5CTemp%5Cescaped.png'
            $run.Files | Should -Be @('1-escaped.png')
        }

        It 'saves both attachments when two share a name' {
            $address = 'https://dev.azure.com/avevagroup/EI/_apis/wit/attachments/{0}?fileName=same.png'
            $run = Invoke-Download -Address @(($address -f '1111'), ($address -f '2222'))

            $run.Attachments.Count | Should -Be 2
            $run.Files | Should -Be @('1-same.png', '2-same.png')
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
