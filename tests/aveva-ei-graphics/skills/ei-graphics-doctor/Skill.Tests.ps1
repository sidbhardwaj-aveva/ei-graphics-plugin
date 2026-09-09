#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for the EI Graphics Doctor skill.
.DESCRIPTION
    Tests the diagnostic functions and overall script behavior.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param()

BeforeAll {
    $here = $PSScriptRoot
    $repoRoot = (Resolve-Path (Join-Path $here '..' '..' '..' '..')).Path
    $pluginRoot = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics'
    $doctorRoot = Join-Path $pluginRoot 'skills' 'ei-graphics-doctor'
    $scriptPath = Join-Path $doctorRoot 'scripts' 'Invoke-EiGraphicsDoctor.ps1'
    $skillPath = Join-Path $doctorRoot 'SKILL.md'
}

Describe 'Invoke-EiGraphicsDoctor.ps1' -Tag 'Unit' {
    
    Context 'Script File Validation' {
        It 'Script file exists' {
            Test-Path -LiteralPath $scriptPath | Should -Be $true
        }
        
        It 'Script has required PowerShell header' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Match '#Requires -Version 7\.0'
            $content | Should -Match 'Set-StrictMode -Version Latest'
            $content | Should -Match '\$ErrorActionPreference = .Stop.'
        }
        
        It 'Script has help documentation' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Match '\.SYNOPSIS'
            $content | Should -Match '\.DESCRIPTION'
        }
    }
    
    Context 'Script Execution - Table Mode' {
        It 'Runs without fatal errors' {
            Push-Location -LiteralPath $repoRoot
            try {
                { & pwsh -NoProfile -File $scriptPath } | Should -Not -Throw
            } finally {
                Pop-Location
            }
        }
        
        It 'Exits with code 0 or 1' {
            Push-Location -LiteralPath $repoRoot
            try {
                & pwsh -NoProfile -File $scriptPath
                $exitCode = $LASTEXITCODE
                @(0, 1) | Should -Contain $exitCode
            } finally {
                Pop-Location
            }
        }
        
        It 'Produces diagnostic output to stdout or stderr' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath *>&1
                # Table mode should have diagnostic lines
                $output -join "`n" | Should -Match 'Ready|Blocked|ManualReview'
            } finally {
                Pop-Location
            }
        }
    }
    
    Context 'Script Execution - JSON Mode' {
        It 'Accepts -Json parameter' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath -Json 2>$null
                $output -join "`n" | Should -Match '"status"'
                $output -join "`n" | Should -Match '"violations"'
            } finally {
                Pop-Location
            }
        }
        
        It 'JSON output is valid' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath -Json 2>$null
                $json = $output -join "`n" | ConvertFrom-Json
                $json | Should -Not -BeNullOrEmpty
            } finally {
                Pop-Location
            }
        }
        
        It 'JSON contains required top-level properties' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath -Json 2>$null
                $json = $output -join "`n" | ConvertFrom-Json
                $json.PSObject.Properties.Name | Should -Contain 'status'
                $json.PSObject.Properties.Name | Should -Contain 'violations'
                $json.PSObject.Properties.Name | Should -Contain 'reviewFlags'
                $json.PSObject.Properties.Name | Should -Contain 'affectedAreas'
                $json.PSObject.Properties.Name | Should -Contain 'requiredActions'
                $json.PSObject.Properties.Name | Should -Contain 'checkDetails'
            } finally {
                Pop-Location
            }
        }
        
        It 'JSON status is one of: pass, blocked, needs-manual-review' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath -Json 2>$null
                $json = $output -join "`n" | ConvertFrom-Json
                @('pass', 'blocked', 'needs-manual-review') | Should -Contain $json.status
            } finally {
                Pop-Location
            }
        }
        
        It 'JSON violations and reviewFlags are arrays' {
            Push-Location -LiteralPath $repoRoot
            try {
                $output = & pwsh -NoProfile -File $scriptPath -Json 2>$null
                $document = [System.Text.Json.JsonDocument]::Parse(($output -join "`n"))
                $document.RootElement.GetProperty('violations').ValueKind | Should -Be ([System.Text.Json.JsonValueKind]::Array)
                $document.RootElement.GetProperty('reviewFlags').ValueKind | Should -Be ([System.Text.Json.JsonValueKind]::Array)
            } finally {
                Pop-Location
            }
        }
    }
    
    Context 'Plugin File Structure' {
        It 'Required plugin directories exist' {
            @(
                'agents',
                'skills',
                'skills/ei-azure-devops-cli-intake',
                'skills/ei-graphics-core',
                'skills/ei-layer-guard',
                'skills/termination-drawing',
                'skills/ei-graphics-core/schemas',
                'skills/ei-graphics-core/references'
            ) | ForEach-Object {
                $dir = Join-Path $pluginRoot $_
                Test-Path -LiteralPath $dir -PathType Container | Should -Be $true -Because "Directory should exist: $_"
            }
        }
        
        It 'Required skill SKILL.md files exist' {
            @(
                'skills/ei-azure-devops-cli-intake/SKILL.md',
                'skills/ei-graphics-core/SKILL.md',
                'skills/ei-graphics-doctor/SKILL.md',
                'skills/ei-layer-guard/SKILL.md',
                'skills/termination-drawing/SKILL.md'
            ) | ForEach-Object {
                $file = Join-Path $pluginRoot $_
                Test-Path -LiteralPath $file | Should -Be $true -Because "File should exist: $_"
            }
        }
        
        It 'Agent file exists' {
            $file = Join-Path $pluginRoot 'agents/ei-graphics.agent.md'
            Test-Path -LiteralPath $file | Should -Be $true
        }
        
        It 'Registry file exists' {
            $file = Join-Path $pluginRoot 'skills/ei-graphics-core/references/domain-skill-registry.json'
            Test-Path -LiteralPath $file | Should -Be $true
        }
        
        It 'Required schema files exist' {
            @(
                'ado.schema.json',
                'session.schema.json',
                'story-understanding.schema.json',
                'approved-files.schema.json',
                'domain-skill-registry.schema.json'
            ) | ForEach-Object {
                $file = Join-Path $pluginRoot "skills/ei-graphics-core/schemas/$_"
                Test-Path -LiteralPath $file | Should -Be $true -Because "Schema should exist: $_"
            }
        }
    }
    
    Context 'Skill Registry Validation' {
        It 'Registry file is valid JSON' {
            $registryPath = Join-Path $pluginRoot 'skills/ei-graphics-core/references/domain-skill-registry.json'
            $content = Get-Content -LiteralPath $registryPath -Raw
            { $content | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        }
        
        It 'Registry has required structure' {
            $registryPath = Join-Path $pluginRoot 'skills/ei-graphics-core/references/domain-skill-registry.json'
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
            $registry.PSObject.Properties.Name | Should -Contain 'schemaVersion'
            $registry.PSObject.Properties.Name | Should -Contain 'domains'
        }
        
        It 'All schema files are valid JSON' {
            $schemaDir = Join-Path $pluginRoot 'skills/ei-graphics-core/schemas'
            Get-ChildItem -LiteralPath $schemaDir -Filter '*.schema.json' | ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -Raw
                { $content | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw -Because "Schema should be valid JSON: $($_.Name)"
            }
        }
    }
    
    Context 'Doctor Skill Documentation' {
        It 'Doctor skill SKILL.md exists' {
            Test-Path -LiteralPath $skillPath | Should -Be $true
        }
        
        It 'Doctor SKILL.md has required frontmatter' {
            $content = Get-Content -LiteralPath $skillPath -Raw
            $content | Should -Match '(?m)^---\s*$'
            $content | Should -Match 'name:\s*ei-graphics-doctor'
            $content | Should -Match 'description:'
        }
        
        It 'Doctor SKILL.md has diagnostic workflow section' {
            $content = Get-Content -LiteralPath $skillPath -Raw
            $content | Should -Match '##\s+Diagnostic Workflow'
            $content | Should -Match 'Check 1.*PowerShell'
            $content | Should -Match 'Check 2.*Azure DevOps'
            $content | Should -Match 'Check 6.*Git'
        }
    }
    
    Context 'Regression - missing registry or .git does not crash the report' {
        It 'A corrupted plugin install (registry missing) exits without throwing and reports zero domains' {
            # Plugin files are resolved from the script's own install location, not from -Root,
            # so simulating a missing registry means copying the plugin tree and deleting it there.
            $corruptedPluginRoot = Join-Path $TestDrive 'corrupted-plugin' 'plugins' 'aveva-ei-graphics'
            New-Item -ItemType Directory -Path $corruptedPluginRoot -Force | Out-Null
            Copy-Item -Path (Join-Path $pluginRoot '*') -Destination $corruptedPluginRoot -Recurse -Force
            Remove-Item -LiteralPath (Join-Path $corruptedPluginRoot 'skills' 'ei-graphics-core' 'references' 'domain-skill-registry.json') -Force
            $corruptedScriptPath = Join-Path $corruptedPluginRoot 'skills' 'ei-graphics-doctor' 'scripts' 'Invoke-EiGraphicsDoctor.ps1'
            
            $anyTargetRoot = Join-Path $TestDrive 'any-target'
            New-Item -ItemType Directory -Path $anyTargetRoot -Force | Out-Null
            
            { & pwsh -NoProfile -File $corruptedScriptPath -Root $anyTargetRoot -Json 2>$null } | Should -Not -Throw
            
            $output = & pwsh -NoProfile -File $corruptedScriptPath -Root $anyTargetRoot -Json 2>$null
            $exitCode = $LASTEXITCODE
            @(0, 1) | Should -Contain $exitCode
            
            $json = $output -join "`n" | ConvertFrom-Json
            $json.checkDetails.SkillRegistryAndSchemas.DomainsResolvable | Should -Be 0
            $json.status | Should -Be 'blocked'
        }
        
        It 'Root with no .git exits without throwing and reports git as unconfigured' {
            $noGitRoot = Join-Path $TestDrive 'no-git-root'
            New-Item -ItemType Directory -Path $noGitRoot -Force | Out-Null
            
            { & pwsh -NoProfile -File $scriptPath -Root $noGitRoot -Json 2>$null } | Should -Not -Throw
            
            $output = & pwsh -NoProfile -File $scriptPath -Root $noGitRoot -Json 2>$null
            $exitCode = $LASTEXITCODE
            @(0, 1) | Should -Contain $exitCode
            
            $json = $output -join "`n" | ConvertFrom-Json
            $json.checkDetails.GitConfiguration.UserConfigured | Should -Be $false
            $json.checkDetails.GitConfiguration.GitRepoExists | Should -Be $false
        }
    }
    
    Context 'Regression - plugin files resolve independently of -Root' {
        It 'A -Root with no plugins/ tree still finds the plugin''s own files' {
            $targetRoot = Join-Path $TestDrive 'target-repo-no-plugin-copy'
            New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
            
            $output = & pwsh -NoProfile -File $scriptPath -Root $targetRoot -Json 2>$null
            $json = $output -join "`n" | ConvertFrom-Json
            $json.checkDetails.PluginFileStructure.MissingFiles | Should -Be 0
            $json.checkDetails.SkillRegistryAndSchemas.DomainsNotFound | Should -Be 0
        }
        
        It 'JSON reports both targetRoot and pluginRoot' {
            $output = & pwsh -NoProfile -File $scriptPath -Root $repoRoot -Json 2>$null
            $json = $output -join "`n" | ConvertFrom-Json
            $json.targetRoot | Should -Be $repoRoot
            $json.pluginRoot | Should -Be $pluginRoot
        }
        
        It 'A -Root under a repository subfolder resolves to the real git top level' {
            $gitRoot = Join-Path $TestDrive 'nested-git-root'
            $subfolder = Join-Path $gitRoot 'Engineering' 'Modules' 'EI' 'Source'
            New-Item -ItemType Directory -Path $subfolder -Force | Out-Null
            Push-Location -LiteralPath $gitRoot
            try {
                git init -q
                git -c gc.auto=0 config --local user.name 'Test'
                git -c gc.auto=0 config --local user.email 'test@example.com'
            } finally {
                Pop-Location
            }
            
            $output = & pwsh -NoProfile -File $scriptPath -Root $subfolder -Json 2>$null
            $json = $output -join "`n" | ConvertFrom-Json
            $json.targetRoot | Should -Be (Resolve-Path -LiteralPath $gitRoot).Path
            $json.checkDetails.GitConfiguration.GitRepoExists | Should -Be $true
        }
    }
    
    Context 'Regression - Azure DevOps CLI check uses valid commands' {
        It 'Does not call the invalid "az devops -v" command' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Not -Match 'az devops -v(\s|$)'
        }
        
        It 'Parses "az devops configure -l" as text, not --output json' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Not -Match "az devops configure -l --output json"
        }
    }
    
    Context 'Regression - frontmatter checks use multiline mode' {
        It 'Frontmatter regexes use (?m) so real content after line 1 still matches' {
            $content = Get-Content -LiteralPath $scriptPath -Raw
            $content | Should -Match '\(\?m\)\^---'
            $content | Should -Match '\(\?m\)\^\\s\*name:'
            $content | Should -Match '\(\?m\)\^\\s\*description:'
        }
    }
}
