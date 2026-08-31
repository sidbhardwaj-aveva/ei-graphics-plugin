#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:IntakePath = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-azure-devops-cli-intake' 'scripts' 'Invoke-EiAdoCliIntake.ps1'
    $script:ConvertPath = Join-Path $core 'scripts' 'Convert-EiAdoIntake.ps1'
    $script:WriterPath = Join-Path $core 'scripts' 'Write-EiArtifact.ps1'
    $script:AdoSchema = Get-Content -LiteralPath (Join-Path $core 'schemas' 'ado.schema.json') -Raw
    $script:FixtureDir = Join-Path $PSScriptRoot '..' 'fixtures'
    $script:HashFile = Join-Path $repoRoot 'tests' 'data' 'ported-file-hashes.json'

    $script:CopiedScripts = @(
        'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.ps1'
        'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1'
        'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1'
    )
    $script:RepoRoot = $repoRoot

    function Invoke-Intake {
        param([Parameter(Mandatory)] [string] $WorkItemId)
        $json = Get-Content -LiteralPath (Join-Path $script:FixtureDir "work-item-$WorkItemId.json") -Raw
        & $script:IntakePath -WorkItemId $WorkItemId -CliWorkItemJson $json
    }
}

Describe 'ei-azure-devops-cli-intake, as copied' -Tag 'Unit' {

    Context 'the three copied scripts are unedited' {
        It '<_> still matches its recorded hash' -ForEach @(
            'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.ps1'
            'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1'
            'plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1'
        ) {
            $recorded = (Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json).files.$_
            $recorded | Should -Match '^sha256:[0-9a-f]{64}$'
            $actual = 'sha256:' + (Get-FileHash -LiteralPath (Join-Path $script:RepoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -Be $recorded
        }

        It 'none of them mentions a skill this build dropped' {
            # The list is read from tests/data/forbidden-identifiers.txt, never written here.
            $terms = @(
                Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests' 'data' 'forbidden-identifiers.txt') |
                    ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            )
            $terms.Count | Should -BeGreaterOrEqual 23
            foreach ($relative in $script:CopiedScripts) {
                $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot $relative) -Raw
                $hits = @($terms | Where-Object { $raw -like "*$_*" })
                $hits.Count | Should -Be 0 -Because "$relative names: $($hits -join ', ')"
            }
        }

        It 'the copied test file points at the renamed plugin folder' {
            $testFile = Join-Path $PSScriptRoot 'Invoke-EiAdoCliIntake.Tests.ps1'
            $raw = Get-Content -LiteralPath $testFile -Raw
            $pluginName = Split-Path -Leaf (Join-Path $script:RepoRoot 'plugins' 'demo-ei-graphics')
            $raw | Should -BeLike "*'$pluginName'*"
            $terms = @(
                Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests' 'data' 'forbidden-identifiers.txt') |
                    ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            )
            @($terms | Where-Object { $raw -like "*$_*" }).Count | Should -Be 0
            # Renaming a folder does not change how deep it sits, so the chain stays at five.
            $raw | Should -BeLike "*Join-Path `$PSScriptRoot '..' '..' '..' '..' '..'*"
        }
    }

    Context 'driven by the two copied fixtures' {
        It 'retrieves work item <_> from its fixture' -ForEach @('123456', '789012') {
            $intake = Invoke-Intake -WorkItemId $_
            $intake.status | Should -Be 'retrieved'
            $intake.workItemContext.workItemId | Should -Be $_
            $intake.descriptionText | Should -Not -BeNullOrEmpty
            $intake.workItemContext.authSource | Should -Be 'cli-mock-json'
        }

        It 'assembles the description from the title and the body' {
            $intake = Invoke-Intake -WorkItemId '123456'
            $intake.descriptionText | Should -BeLike '*Termination labels overlap*'
            $intake.descriptionText | Should -BeLike '*cable label placement collides*'
            # The prose comes back as plain text, with no markup left in it.
            $intake.descriptionText | Should -Not -Match '<[a-z]'
        }

        It 'reports a thread that was never fetched as skipped, not as empty' {
            (Invoke-Intake -WorkItemId '789012').commentRetrieval.status | Should -Be 'skipped'
        }
    }

    Context 'the whole chain, from intake to a written artifact' {
        It 'produces a schema-valid ado.json for work item <_>' -ForEach @('123456', '789012') {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $root -Force

            $intake = Invoke-Intake -WorkItemId $_
            $artifact = & $script:ConvertPath -IntakeJson ($intake | ConvertTo-Json -Depth 20) `
                -StoryId $_ -SkipAttachmentDownload
            $LASTEXITCODE | Should -Be 0

            $written = & $script:WriterPath -StoryId $_ -ArtifactType 'ado' -InputObject $artifact -Root $root
            $LASTEXITCODE | Should -Be 0

            $raw = Get-Content -LiteralPath $written.path -Raw
            $raw | Test-Json -Schema $script:AdoSchema | Should -BeTrue
            ($raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'hash'
            ($raw | ConvertFrom-Json).workItem.id | Should -Be $_
        }

        It 'carries the attachment source through when the intake reports one' {
            # attachmentUrls entries are objects carrying a source, not bare strings.
            $intakeJson = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests' 'fixtures' 'ado-intake-stdout.json') -Raw
            $entries = @(($intakeJson | ConvertFrom-Json).attachmentUrls)
            $entries[0].url | Should -Not -BeNullOrEmpty
            $entries[0].source | Should -Be 'field:System.Description'
            $entries[1].source | Should -Be 'comment:12'
        }
    }
}
