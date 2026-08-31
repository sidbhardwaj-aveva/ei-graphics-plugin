#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..' '..')).Path
    $core = Join-Path $repoRoot 'plugins' 'demo-ei-graphics' 'skills' 'ei-graphics-core'
    $script:ScriptPath = Join-Path $core 'scripts' 'Get-EiDomainSkillCatalog.ps1'
    $script:RealRegistryPath = Join-Path $core 'references' 'domain-skill-registry.json'
    $script:RealRegistry = Get-Content -LiteralPath $script:RealRegistryPath -Raw | ConvertFrom-Json

    function Invoke-Catalog {
        param([string] $RegistryPath)
        if ($RegistryPath) { $output = & $script:ScriptPath -RegistryPath $RegistryPath }
        else { $output = & $script:ScriptPath }
        [pscustomobject]@{ Result = $output; ExitCode = $LASTEXITCODE }
    }

    function New-FakePlugin {
        <#
        .SYNOPSIS
            Builds a plugin-shaped folder so -RegistryPath can point at a broken registry.
        #>
        param([string] $SkillBody, [string] $SkillPath = 'skills/fake-domain/SKILL.md')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $references = Join-Path $root 'skills' 'ei-graphics-core' 'references'
        $null = New-Item -ItemType Directory -Path $references -Force
        if ($null -ne $SkillBody) {
            $skillFile = Join-Path $root ($SkillPath -replace '/', '\')
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $skillFile) -Force
            Set-Content -LiteralPath $skillFile -Value $SkillBody -Encoding utf8NoBOM
        }
        $registry = Join-Path $references 'domain-skill-registry.json'
        Set-Content -LiteralPath $registry -Encoding utf8NoBOM -Value (@{
            schemaVersion = '1.0.0'
            domains       = @(@{ id = 'fake-domain'; displayName = 'Fake Domain'; skillPath = $SkillPath })
        } | ConvertTo-Json -Depth 6)
        $registry
    }
}

Describe 'Get-EiDomainSkillCatalog' -Tag 'Unit' {

    Context 'the real registry' {
        It 'returns one entry per domain the registry declares' {
            # Count read from the registry, never hardcoded.
            $run = Invoke-Catalog
            $run.ExitCode | Should -Be 0
            @($run.Result.skills).Count | Should -Be @($script:RealRegistry.domains).Count
        }

        It 'reports the id, display name and path straight from the registry' {
            $skills = @((Invoke-Catalog).Result.skills)
            foreach ($domain in @($script:RealRegistry.domains)) {
                $entry = $skills | Where-Object { $_.domainId -eq $domain.id }
                $entry | Should -Not -BeNullOrEmpty
                $entry.displayName | Should -Be $domain.displayName
                $entry.skillPath | Should -Be $domain.skillPath
            }
        }

        It 'gives every entry a description and a non-empty when-to-use list' {
            foreach ($entry in @((Invoke-Catalog).Result.skills)) {
                $entry.description | Should -Not -BeNullOrEmpty
                @($entry.whenToUse).Count | Should -BeGreaterThan 0
                foreach ($item in @($entry.whenToUse)) { $item | Should -Not -BeNullOrEmpty }
            }
        }

        It 'joins a folded description written with a greater-than sign' {
            $entry = @((Invoke-Catalog).Result.skills) | Where-Object { $_.domainId -eq 'termination-drawing' }
            $entry.description | Should -BeLike '*Termination Drawing features*'
            $entry.description | Should -Not -Match '^\s*>'
            $entry.description | Should -Not -Match '\r|\n'
        }

        It 'never reads the body of a skill document' {
            # Only the frontmatter description and the When to Use bullets come back.
            $entry = @((Invoke-Catalog).Result.skills) | Where-Object { $_.domainId -eq 'termination-drawing' }
            ($entry | ConvertTo-Json -Depth 10) | Should -Not -Match 'Critical Rules'
            ($entry | ConvertTo-Json -Depth 10) | Should -Not -Match 'Invocation Workflow'
        }

        It 'emits JSON on stdout with -Json' {
            $raw = & $script:ScriptPath -Json
            $parsed = ($raw -join "`n") | ConvertFrom-Json
            @($parsed.skills).Count | Should -Be @($script:RealRegistry.domains).Count
        }
    }

    Context 'it fails with a message that says what to do' {
        It 'exits 1 when a skillPath points at nothing' {
            $registry = New-FakePlugin -SkillBody $null
            $run = Invoke-Catalog -RegistryPath $registry
            $run.ExitCode | Should -Be 1
        }

        It 'exits 1 when the skill document has no frontmatter' {
            $registry = New-FakePlugin -SkillBody "# Fake`n`n## When to Use`n- something"
            (Invoke-Catalog -RegistryPath $registry).ExitCode | Should -Be 1
        }

        It 'exits 1 when the frontmatter has no description' {
            $registry = New-FakePlugin -SkillBody "---`nname: fake-domain`n---`n`n## When to Use`n- something"
            (Invoke-Catalog -RegistryPath $registry).ExitCode | Should -Be 1
        }

        It 'exits 1 when the registry file is missing' {
            (Invoke-Catalog -RegistryPath (Join-Path $TestDrive 'nowhere.json')).ExitCode | Should -Be 1
        }

        It 'exits 1 when the registry is not valid JSON' {
            $path = Join-Path $TestDrive 'broken.json'
            Set-Content -LiteralPath $path -Value '{ not json' -Encoding utf8NoBOM
            (Invoke-Catalog -RegistryPath $path).ExitCode | Should -Be 1
        }
    }

    Context 'a healthy fixture registry' {
        It 'reads the description and the bullets, and stops at the next heading' {
            $body = @(
                '---'
                'name: fake-domain'
                'description: A short description of the fake domain.'
                '---'
                ''
                '# Fake'
                ''
                '## When to Use'
                '- first reason'
                '- second reason'
                ''
                '## Goal'
                '- this bullet belongs to another section'
            ) -join "`n"
            $run = Invoke-Catalog -RegistryPath (New-FakePlugin -SkillBody $body)
            $run.ExitCode | Should -Be 0
            $entry = @($run.Result.skills)[0]
            $entry.description | Should -Be 'A short description of the fake domain.'
            @($entry.whenToUse) | Should -Be @('first reason', 'second reason')
        }
    }

    It 'prints its synopsis and exits 0 for -Help' {
        $null = & $script:ScriptPath -Help
        $LASTEXITCODE | Should -Be 0
    }
}
