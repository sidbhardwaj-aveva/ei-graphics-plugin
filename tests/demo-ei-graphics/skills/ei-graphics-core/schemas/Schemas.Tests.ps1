#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $script:SchemaDir = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core' 'schemas'
    $script:HashFile = Join-Path $repoRoot 'tests' 'data' 'ported-file-hashes.json'
    $script:AdoSchemaRelative = 'plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/ado.schema.json'

    function Copy-Payload {
        param([Parameter(Mandatory)] $Source)
        $copy = [ordered]@{}
        foreach ($key in $Source.Keys) { $copy[$key] = $Source[$key] }
        $copy
    }

    function Get-Schema {
        param([Parameter(Mandatory)] [string] $Name)
        Get-Content -LiteralPath (Join-Path $script:SchemaDir $Name) -Raw
    }

    function Test-AgainstSchema {
        param(
            [Parameter(Mandatory)] $Payload,
            [Parameter(Mandatory)] [string] $SchemaName
        )
        $json = $Payload | ConvertTo-Json -Depth 20
        $json | Test-Json -Schema (Get-Schema -Name $SchemaName) -ErrorAction SilentlyContinue
    }

    $goodHash = 'sha256:' + ('a' * 64)

    $script:GoodUnderstanding = [ordered]@{
        schemaVersion = '1.0.0'
        storyId       = '4965976'
        adoHash       = $goodHash
        status        = 'confirmed'
        understanding = [ordered]@{
            subject         = 'Core connectors are not inserted after a wire is added back'
            expectedOutcome = 'Core connectors appear at the restored levels after the second update'
            requirements    = @(
                [ordered]@{ text = 'The existsInBoth check must not suppress insertion'; source = 'description' }
            )
        }
        proposedDomains  = @(
            [ordered]@{ domainId = 'termination-drawing'; reason = 'Core connector insertion during a drawing update'; confidence = 'high' }
        )
        confirmedDomains = @('termination-drawing')
        complexity       = [ordered]@{ assessment = 'small'; reasoning = 'One file, one method' }
        hash             = $goodHash
    }

    $script:GoodApprovedFiles = [ordered]@{
        schemaVersion     = '1.0.0'
        storyId           = '4965976'
        understandingHash = $goodHash
        approvedAt        = '2026-08-26T09:02:45Z'
        approvedBy        = 'a.person'
        approvalType      = 'direct'
        files             = @(
            [ordered]@{ path = 'src/Manager/CoreConnectorManager.cs'; intent = 'modify'; reason = 'Fix the early return' }
        )
        hash              = $goodHash
    }

    $script:GoodSession = [ordered]@{
        schemaVersion = '1.0.0'
        storyId       = '4965976'
        startedAt     = '2026-08-26T09:00:00Z'
        agent         = 'ei-graphics'
        verbosity     = 'verbose'
        entries       = @(
            [ordered]@{
                timestamp  = '2026-08-26T09:00:01Z'
                phase      = 'ado-intake'
                action     = 'retrieve-story'
                reasoning  = 'A story URL was given, so the intake script runs first.'
                outcome    = 'Retrieved the title, the description and three comments.'
                durationMs = 4200
                tokensUsed = $null
            }
        )
    }

    $script:GoodAdo = [ordered]@{
        schemaVersion    = '1.0.0'
        source           = 'ei-azure-devops-cli-intake'
        storyId          = '4965976'
        storyRef         = 'https://dev.azure.com/org/proj/_workitems/edit/4965976'
        summary          = 'Core connector not inserted after update'
        description      = 'After the second update the core connectors are missing.'
        workItem         = [ordered]@{
            id           = '4965976'
            organization = 'org'
            project      = 'proj'
            url          = 'https://dev.azure.com/org/proj/_workitems/edit/4965976'
        }
        retrieval        = [ordered]@{ status = 'retrieved'; reason = 'ok'; authSource = 'az-cli' }
        retrievedAt      = '2026-08-26T09:00:01Z'
        commentRetrieval = [ordered]@{ status = 'retrieved'; reason = 'ok' }
        comments         = @(
            [ordered]@{ id = '12'; author = 'a.person'; createdDate = '2026-08-25T10:00:00Z'; text = 'It is the existsInBoth path.' }
        )
    }
}

Describe 'ei-graphics-core schemas' -Tag 'Unit' {

    Context 'every schema parses' {
        It 'parses <_>' -ForEach @('story-understanding.schema.json', 'approved-files.schema.json', 'session.schema.json', 'ado.schema.json') {
            $path = Join-Path $script:SchemaDir $_
            Test-Path -LiteralPath $path | Should -BeTrue
            { Get-Content -LiteralPath $path -Raw | Test-Json } | Should -Not -Throw
        }

        It '<_> declares draft-07 and refuses extra top-level properties' -ForEach @('story-understanding.schema.json', 'approved-files.schema.json', 'session.schema.json') {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir $_) -Raw | ConvertFrom-Json
            $schema.'$schema' | Should -Be 'http://json-schema.org/draft-07/schema#'
            $schema.additionalProperties | Should -BeFalse
            $schema.required.Count | Should -BeGreaterThan 0
        }
    }

    Context 'story-understanding.schema.json' {
        It 'accepts a good payload' {
            Test-AgainstSchema -Payload $script:GoodUnderstanding -SchemaName 'story-understanding.schema.json' | Should -BeTrue
        }

        It 'requires hash' {
            $bad = Copy-Payload $script:GoodUnderstanding
            $bad.Remove('hash')
            Test-AgainstSchema -Payload $bad -SchemaName 'story-understanding.schema.json' | Should -BeFalse
        }

        It 'rejects a hash that is not sha256 followed by 64 lowercase hex characters' {
            $bad = Copy-Payload $script:GoodUnderstanding
            $bad.hash = 'sha256:NOTHEX'
            Test-AgainstSchema -Payload $bad -SchemaName 'story-understanding.schema.json' | Should -BeFalse
        }

        It 'rejects an uppercase hash, because the pattern is anchored and lowercase' {
            $bad = Copy-Payload $script:GoodUnderstanding
            $bad.hash = 'sha256:' + ('A' * 64)
            Test-AgainstSchema -Payload $bad -SchemaName 'story-understanding.schema.json' | Should -BeFalse
        }

        It 'rejects an extra top-level property' {
            $bad = Copy-Payload $script:GoodUnderstanding
            $bad.somethingElse = 'no'
            Test-AgainstSchema -Payload $bad -SchemaName 'story-understanding.schema.json' | Should -BeFalse
        }

        It 'rejects a status outside draft and confirmed' {
            $bad = Copy-Payload $script:GoodUnderstanding
            $bad.status = 'maybe'
            Test-AgainstSchema -Payload $bad -SchemaName 'story-understanding.schema.json' | Should -BeFalse
        }
    }

    Context 'approved-files.schema.json' {
        It 'accepts a good payload' {
            Test-AgainstSchema -Payload $script:GoodApprovedFiles -SchemaName 'approved-files.schema.json' | Should -BeTrue
        }

        It 'requires hash' {
            $bad = Copy-Payload $script:GoodApprovedFiles
            $bad.Remove('hash')
            Test-AgainstSchema -Payload $bad -SchemaName 'approved-files.schema.json' | Should -BeFalse
        }

        It 'rejects a malformed hash' {
            $bad = Copy-Payload $script:GoodApprovedFiles
            $bad.hash = 'sha256:abc'
            Test-AgainstSchema -Payload $bad -SchemaName 'approved-files.schema.json' | Should -BeFalse
        }

        It 'rejects an empty file list' {
            $bad = Copy-Payload $script:GoodApprovedFiles
            $bad.files = @()
            Test-AgainstSchema -Payload $bad -SchemaName 'approved-files.schema.json' | Should -BeFalse
        }

        It 'rejects an approval type it does not know' {
            $bad = Copy-Payload $script:GoodApprovedFiles
            $bad.approvalType = 'rubber-stamped'
            Test-AgainstSchema -Payload $bad -SchemaName 'approved-files.schema.json' | Should -BeFalse
        }
    }

    Context 'session.schema.json' {
        It 'accepts a good payload' {
            Test-AgainstSchema -Payload $script:GoodSession -SchemaName 'session.schema.json' | Should -BeTrue
        }

        It 'accepts a session with no summary, because -Finalize writes it only at the end' {
            $payload = Copy-Payload $script:GoodSession
            $payload.Keys | Should -Not -Contain 'summary'
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeTrue
        }

        It 'accepts a summary carrying all ten fields' {
            $payload = Copy-Payload $script:GoodSession
            $payload.summary = [ordered]@{
                completedAt       = '2026-08-26T09:03:37Z'
                totalDurationMs   = 216000
                totalTokens       = 7682
                filesModified     = @('CoreConnectorManager.cs')
                testsRun          = 12
                testsPassed       = 12
                humanInteractions = 2
                outcome           = 'fixed'
                domainSkillUsed   = 'termination-drawing'
                bugPatternMatched = 'Core Connector Update'
            }
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeTrue
        }

        It 'accepts a summary carrying only one field, because every summary field is optional' {
            $payload = Copy-Payload $script:GoodSession
            $payload.summary = [ordered]@{ outcome = 'fixed' }
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeTrue
        }

        It 'accepts an entry carrying all four optional fields' {
            $payload = Copy-Payload $script:GoodSession
            $payload.entries = @(
                [ordered]@{
                    timestamp     = '2026-08-26T09:02:45Z'
                    phase         = 'implementation'
                    action        = 'read-source'
                    reasoning     = 'Looking for the early return.'
                    outcome       = 'Found it.'
                    durationMs    = 1200
                    tokensUsed    = 3400
                    filesRead     = @('src/Manager/CoreConnectorManager.cs')
                    filesModified = @('src/Manager/CoreConnectorManager.cs')
                    humanInput    = 'yes, that is correct'
                    scriptOutput  = [ordered]@{ status = 'pass'; violations = @() }
                }
            )
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeTrue
        }

        It 'rejects a phase it does not know' {
            $payload = Copy-Payload $script:GoodSession
            $payload.entries = @(
                [ordered]@{ timestamp = 'x'; phase = 'daydreaming'; action = 'a'; outcome = 'b' }
            )
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeFalse
        }

        It 'rejects a verbosity outside verbose and concise' {
            $payload = Copy-Payload $script:GoodSession
            $payload.verbosity = 'chatty'
            Test-AgainstSchema -Payload $payload -SchemaName 'session.schema.json' | Should -BeFalse
        }

        It 'declares verbosity with a default of verbose' {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'session.schema.json') -Raw | ConvertFrom-Json
            $schema.properties.verbosity.default | Should -Be 'verbose'
        }

        It 'declares all ten summary fields' {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'session.schema.json') -Raw | ConvertFrom-Json
            $declared = $schema.properties.summary.properties.PSObject.Properties.Name
            $expected = @('completedAt', 'totalDurationMs', 'totalTokens', 'filesModified', 'testsRun',
                'testsPassed', 'humanInteractions', 'outcome', 'domainSkillUsed', 'bugPatternMatched')
            $declared | Should -HaveCount 10
            foreach ($field in $expected) { $declared | Should -Contain $field }
        }

        It 'declares no required list on summary, so a part-finished session still validates' {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'session.schema.json') -Raw | ConvertFrom-Json
            $schema.properties.summary.PSObject.Properties.Name | Should -Not -Contain 'required'
        }
    }

    Context 'ado.schema.json is copied, not written here' {
        It 'still matches the hash recorded in ported-file-hashes.json' {
            $recorded = (Get-Content -LiteralPath $script:HashFile -Raw | ConvertFrom-Json).files.$script:AdoSchemaRelative
            $recorded | Should -Match '^sha256:[0-9a-f]{64}$'
            $actual = 'sha256:' + (Get-FileHash -LiteralPath (Join-Path $script:SchemaDir 'ado.schema.json') -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -Be $recorded
        }

        It 'accepts a good payload' {
            Test-AgainstSchema -Payload $script:GoodAdo -SchemaName 'ado.schema.json' | Should -BeTrue
        }

        It 'rejects an object with an extra top-level property' {
            $bad = Copy-Payload $script:GoodAdo
            $bad.hash = 'sha256:' + ('a' * 64)
            Test-AgainstSchema -Payload $bad -SchemaName 'ado.schema.json' | Should -BeFalse
        }

        It 'declares no hash property, which is why Write-EiArtifact.ps1 never stamps one on ado.json' {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'ado.schema.json') -Raw | ConvertFrom-Json
            $schema.properties.PSObject.Properties.Name | Should -Not -Contain 'hash'
        }

        It 'pins retrieval status to retrieved, so a failed fetch can never become an artifact' {
            $schema = Get-Content -LiteralPath (Join-Path $script:SchemaDir 'ado.schema.json') -Raw | ConvertFrom-Json
            $schema.properties.retrieval.properties.status.enum | Should -Be @('retrieved')
        }
    }
}
