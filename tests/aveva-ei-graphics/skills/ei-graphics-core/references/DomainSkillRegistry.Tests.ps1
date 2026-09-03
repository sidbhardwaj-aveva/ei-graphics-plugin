#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $skillRoot = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' 'ei-graphics-core'
    $script:RegistryPath = Join-Path $skillRoot 'references' 'domain-skill-registry.json'
    $script:SchemaPath = Join-Path $skillRoot 'schemas' 'domain-skill-registry.schema.json'
    $script:RegistryRaw = Get-Content -LiteralPath $script:RegistryPath -Raw
    $script:SchemaRaw = Get-Content -LiteralPath $script:SchemaPath -Raw
    $script:Registry = $script:RegistryRaw | ConvertFrom-Json
}

Describe 'domain-skill-registry' -Tag 'Unit' {

    It 'the registry and its schema both exist' {
        Test-Path -LiteralPath $script:RegistryPath | Should -BeTrue
        Test-Path -LiteralPath $script:SchemaPath | Should -BeTrue
    }

    It 'the registry validates against its schema' {
        $script:RegistryRaw | Test-Json -Schema $script:SchemaRaw | Should -BeTrue
    }

    It 'the schema is draft-07 and refuses extra properties' {
        $schema = $script:SchemaRaw | ConvertFrom-Json
        $schema.'$schema' | Should -Be 'http://json-schema.org/draft-07/schema#'
        $schema.additionalProperties | Should -BeFalse
        $schema.properties.domains.items.additionalProperties | Should -BeFalse
    }

    It 'declares exactly the three fields an index needs' {
        $schema = $script:SchemaRaw | ConvertFrom-Json
        $declared = $schema.properties.domains.items.properties.PSObject.Properties.Name
        $declared | Should -HaveCount 3
        $declared | Should -Contain 'id'
        $declared | Should -Contain 'displayName'
        $declared | Should -Contain 'skillPath'
    }

    It 'carries no detection terms and no synonyms' {
        # Matching a story to a domain is the agent's job. Keyword lists here would turn adding a
        # skill into a tuning exercise.
        $script:RegistryRaw | Should -Not -Match 'detectionTerms'
        $script:RegistryRaw | Should -Not -Match 'synonyms'
        $script:SchemaRaw | Should -Not -Match 'detectionTerms'
        $script:SchemaRaw | Should -Not -Match 'synonyms'
    }

    It 'every entry has an id, a display name and a skill path' {
        # Count read from the registry, never hardcoded, so adding a domain skill stays a
        # two-file change.
        $script:Registry.domains.Count | Should -BeGreaterThan 0
        foreach ($domain in $script:Registry.domains) {
            $domain.id | Should -Not -BeNullOrEmpty
            $domain.displayName | Should -Not -BeNullOrEmpty
            $domain.skillPath | Should -Not -BeNullOrEmpty
        }
    }

    It 'every skill path names the folder that matches its own id' {
        foreach ($domain in $script:Registry.domains) {
            $domain.skillPath | Should -Be "skills/$($domain.id)/SKILL.md"
        }
    }

    It 'every id appears only once' {
        $ids = @($script:Registry.domains | ForEach-Object { $_.id })
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'rejects a registry with an extra key on a domain entry' {
        $bad = @{
            schemaVersion = '1.0.0'
            domains       = @(
                @{
                    id             = 'termination-drawing'
                    displayName    = 'Termination Drawing'
                    skillPath      = 'skills/termination-drawing/SKILL.md'
                    detectionTerms = @('core', 'wire')
                }
            )
        } | ConvertTo-Json -Depth 6
        $bad | Test-Json -Schema $script:SchemaRaw -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'rejects a registry with no domains at all' {
        $bad = @{ schemaVersion = '1.0.0'; domains = @() } | ConvertTo-Json -Depth 6
        $bad | Test-Json -Schema $script:SchemaRaw -ErrorAction SilentlyContinue | Should -BeFalse
    }
}
