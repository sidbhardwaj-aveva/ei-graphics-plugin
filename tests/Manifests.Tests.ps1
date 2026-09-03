#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ClaudePath = Join-Path $script:RepoRoot '.claude-plugin' 'marketplace.json'
    $script:GithubPath = Join-Path $script:RepoRoot '.github' 'plugin' 'marketplace.json'
    $script:PluginJsonPath = Join-Path $script:RepoRoot 'plugins' 'aveva-ei-graphics' '.github' 'plugin' 'plugin.json'

    $script:Claude = Get-Content -LiteralPath $script:ClaudePath -Raw | ConvertFrom-Json
    $script:Github = Get-Content -LiteralPath $script:GithubPath -Raw | ConvertFrom-Json
    $script:PluginJson = Get-Content -LiteralPath $script:PluginJsonPath -Raw | ConvertFrom-Json

    # Walk up from plugin.json: its own folder is 'plugin', then '.github', then the plugin folder.
    $script:PluginFolder = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:PluginJsonPath))
    $script:PluginFolderName = Split-Path -Leaf $script:PluginFolder
}

Describe 'The manifests' -Tag 'Unit' {

    It 'all three parse as JSON' {
        foreach ($path in @($script:ClaudePath, $script:GithubPath, $script:PluginJsonPath)) {
            Test-Path -LiteralPath $path | Should -BeTrue
            { Get-Content -LiteralPath $path -Raw | Test-Json } | Should -Not -Throw
        }
    }

    Context 'the two marketplace files use different bases' {
        It 'the claude source resolves from the repository root' {
            $resolved = Join-Path $script:RepoRoot $script:Claude.plugins[0].source
            Test-Path -LiteralPath $resolved | Should -BeTrue
        }

        It 'the github pluginRoot resolves from the repository root' {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $script:Github.metadata.pluginRoot) | Should -BeTrue
        }

        It 'the github source resolves from pluginRoot, not from the repository root' {
            $pluginRoot = Join-Path $script:RepoRoot $script:Github.metadata.pluginRoot
            Test-Path -LiteralPath (Join-Path $pluginRoot $script:Github.plugins[0].source) | Should -BeTrue
            # It is the bare folder name, with no ./plugins/ prefix.
            $script:Github.plugins[0].source | Should -Not -BeLike '*plugins*'
        }

        It 'neither marketplace file declares a skillPath' {
            (Get-Content -LiteralPath $script:ClaudePath -Raw) | Should -Not -Match 'skillPath'
            (Get-Content -LiteralPath $script:GithubPath -Raw) | Should -Not -Match 'skillPath'
        }
    }

    Context 'the three names agree' {
        It 'plugin.json name equals the name of the plugin folder, read from disk' {
            $script:PluginJson.name | Should -Be $script:PluginFolderName
        }

        It 'the claude marketplace names the same plugin as the folder' {
            $script:Claude.plugins[0].name | Should -Be $script:PluginFolderName
        }

        It 'the github marketplace names the same plugin as the folder' {
            $script:Github.plugins[0].name | Should -Be $script:PluginFolderName
        }

        It 'the claude source path ends with the plugin folder name' {
            (Split-Path -Leaf $script:Claude.plugins[0].source) | Should -Be $script:PluginFolderName
        }

        It 'both catalogue entries carry the same top-level name' {
            $script:Claude.name | Should -Be $script:Github.name
            $script:Claude.name | Should -Be "$($script:PluginFolderName)-plugin"
        }
    }

    Context 'plugin.json points at folders, not at individual skills' {
        It 'skills and agents both resolve inside the plugin folder' {
            foreach ($pointer in @($script:PluginJson.skills, $script:PluginJson.agents)) {
                $resolved = Join-Path $script:PluginFolder $pointer
                Test-Path -LiteralPath $resolved | Should -BeTrue
                @(Get-ChildItem -LiteralPath $resolved).Count | Should -BeGreaterThan 0
            }
        }

        It 'names no individual skill, so adding one is never a manifest edit' {
            $raw = Get-Content -LiteralPath $script:PluginJsonPath -Raw
            foreach ($skill in @(Get-ChildItem -LiteralPath (Join-Path $script:PluginFolder 'skills') -Directory)) {
                $raw | Should -Not -BeLike "*$($skill.Name)*"
            }
        }
    }

    Context 'the descriptions describe this build only' {
        It '<_> carries none of the old catalogue phrases' -ForEach @(
            '.claude-plugin/marketplace.json'
            '.github/plugin/marketplace.json'
            'plugins/aveva-ei-graphics/.github/plugin/plugin.json'
        ) {
            $raw = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
            $raw | Should -Not -Match 'ITERATE routing'
            $raw | Should -Not -Match 'scope control'
            $raw | Should -Not -Match 'gated delivery lifecycle'
        }
    }
}
