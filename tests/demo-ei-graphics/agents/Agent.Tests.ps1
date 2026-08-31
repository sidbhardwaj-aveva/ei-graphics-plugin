#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $plugin = Join-Path $repoRoot 'plugins' 'demo-ei-graphics'
    $script:AgentPath = Join-Path $plugin 'agents' 'ei-graphics.agent.md'
    $references = Join-Path $plugin 'skills' 'ei-graphics-core' 'references'
    $script:DelegationPath = Join-Path $references 'rnd-delegation.md'
    $script:CheckpointPath = Join-Path $references 'checkpoint-templates.md'

    $script:Agent = Get-Content -LiteralPath $script:AgentPath -Raw
    $script:Delegation = Get-Content -LiteralPath $script:DelegationPath -Raw
    $script:Checkpoints = Get-Content -LiteralPath $script:CheckpointPath -Raw

    # Phrases are matched against a flattened copy, so re-wrapping a line cannot break a check.
    $script:AgentFlat = $script:Agent -replace '\s+', ' '

    # The archive names these as used. bug-diagnosis and the rest are deliberately not here.
    $script:RndSkills = @(
        'code-review', 'git-commit', 'create-pr', 'git-rebase', 'csharp-conventions',
        'refactor', 'nuget-manager', 'test-value-analysis', 'pr-security-compliance',
        'get-reviewresults', 'mermaid-diagrams'
    )
}

Describe 'ei-graphics.agent.md' -Tag 'Unit' {

    It 'is under 80 lines' {
        @(Get-Content -LiteralPath $script:AgentPath).Count | Should -BeLessThan 80
    }

    It 'has frontmatter with a name and a description' {
        $script:Agent | Should -Match '(?s)\A---\r?\n.*?\r?\n---\r?\n'
        $script:Agent | Should -Match '(?m)^name:\s*ei-graphics\s*$'
        $script:Agent | Should -Match '(?m)^description:\s*\S'
    }

    It 'contains <_>' -ForEach @('skill-first', 'Stop when done', '.ei-session-logs/') {
        $script:Agent | Should -BeLike "*$_*"
    }

    It 'points at both reference files' {
        $script:Agent | Should -BeLike '*references/rnd-delegation.md*'
        $script:Agent | Should -BeLike '*references/checkpoint-templates.md*'
    }

    It 'carries a plain-language block naming short sentences and the next action' {
        $script:AgentFlat | Should -Match '(?i)short sentences'
        $script:AgentFlat | Should -Match '(?i)next action'
    }

    It 'spells out the stop rule for a failed intake' {
        $script:AgentFlat | Should -Match '(?i)Convert-EiAdoIntake'
        $script:AgentFlat | Should -Match '(?i)report the failure and stop'
        $script:AgentFlat | Should -Match '(?i)without an `ado\.json`'
    }

    It 'tells the agent never to fetch the story from ADO again' {
        $script:AgentFlat | Should -Match '(?i)never fetch the story from ADO again'
    }

    It 'tells the agent never to invent a domain identifier' {
        $script:AgentFlat | Should -Match '(?i)never invent a domain'
    }

    It 'says a comment can override the description' {
        $script:AgentFlat | Should -Match '(?i)comment can correct the description'
    }

    It 'contains none of the dropped names: <_>' -ForEach @(
        'lifecycle', 'EIWF-', 'Format-EiWorkflowSummary', 'ei-graphics-workflow'
    ) {
        $script:Agent | Should -Not -BeLike "*$_*"
    }
}

Describe 'the agent reference files' -Tag 'Unit' {

    It 'rnd-delegation.md names the aveva-rnd skill <_>' -ForEach @(
        'code-review', 'git-commit', 'create-pr', 'git-rebase', 'csharp-conventions',
        'refactor', 'nuget-manager', 'test-value-analysis', 'pr-security-compliance',
        'get-reviewresults', 'mermaid-diagrams'
    ) {
        $script:Delegation | Should -BeLike "*$_*"
    }

    It 'rnd-delegation.md names all 11 and says so' {
        $named = @($script:RndSkills | Where-Object { $script:Delegation -like "*$_*" })
        $named.Count | Should -Be 11
        $script:Delegation | Should -Match '11 skills'
    }

    It 'rnd-delegation.md carries the no-domain-skill block' {
        $script:Delegation | Should -Match '(?m)^### No matching domain skill\s*$'
        $script:Delegation | Should -Match '(?i)What this means'
        $script:Delegation | Should -Match '(?i)What would help me'
    }

    It 'checkpoint-templates.md carries the four Checkpoint 2 headings' {
        foreach ($heading in @("Files I'll change", 'Tests I''ll verify', 'New tests needed?', 'Risks')) {
            $script:Checkpoints | Should -BeLike "*$heading*"
        }
    }

    It 'checkpoint-templates.md sends the approved list to the artifact writer' {
        $script:Checkpoints | Should -BeLike '*Write-EiArtifact.ps1 -ArtifactType approved-files*'
        $script:Checkpoints | Should -BeLike '*Test-EiScopeDrift.ps1*'
    }
}
