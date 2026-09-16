#Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
    $plugin = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics'
    $script:AgentPath = Join-Path $plugin 'agents' 'ei-graphics.agent.md'
    $references = Join-Path $plugin 'skills' 'ei-graphics-core' 'references'
    $script:DelegationPath = Join-Path $references 'rnd-delegation.md'
    $script:CheckpointPath = Join-Path $references 'checkpoint-templates.md'
    $script:LocalInputPath = Join-Path $references 'local-input.md'

    $script:Agent = Get-Content -LiteralPath $script:AgentPath -Raw
    $script:Delegation = Get-Content -LiteralPath $script:DelegationPath -Raw
    $script:Checkpoints = Get-Content -LiteralPath $script:CheckpointPath -Raw
    $script:LocalInput = Get-Content -LiteralPath $script:LocalInputPath -Raw

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

    It 'is under 120 lines' {
        @(Get-Content -LiteralPath $script:AgentPath).Count | Should -BeLessThan 120
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

    It 'runs the preflight before it writes anything' {
        $script:Agent | Should -Match '(?m)^## Preflight\s*$'
        $script:AgentFlat | Should -Match '(?i)Before the first session entry, run `Resolve-EiScriptPath\.ps1`'
        $script:AgentFlat | Should -Match '(?i)with no `-Name`'
        $script:AgentFlat | Should -Match '(?i)Never rebuild a script path by hand'
    }

    It 'stops and reports four things when the preflight fails' {
        $script:AgentFlat | Should -Match '(?i)preflight exits 1'
        $script:AgentFlat | Should -Match ([regex]::Escape('-SessionOutcome setup-failed'))
        foreach ($item in @('the exact command you ran', 'its exit code', 'the artifact path', 'the command that recovers')) {
            $script:AgentFlat | Should -Match ([regex]::Escape($item))
        }
        $script:AgentFlat | Should -Match '(?i)Do not carry on with a path you assembled yourself'
    }

    It 'offers a route for a bug that has no work item' {
        $script:Agent | Should -Match '(?m)^## Intake without a work item\s*$'
        $script:Agent | Should -BeLike '*references/local-input.md*'
        foreach ($kind in @('attached report or image', 'local folder', 'pasted symptom', 'local log')) {
            $script:AgentFlat | Should -Match ([regex]::Escape($kind))
        }
        $script:AgentFlat | Should -Match '(?i)Do not run the intake script and do not expect an `ado\.json`'
        $script:AgentFlat | Should -Match '(?i)why Azure DevOps was not used'
        $script:AgentFlat | Should -Match '(?i)Everything after intake is unchanged'
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

    It 'stops and asks for context when reasoning is not grounded' {
        $script:AgentFlat | Should -Match '(?i)evidence is missing or conflicts'
        $script:AgentFlat | Should -Match '(?i)repeated reasoning adds no evidence'
        $script:AgentFlat | Should -Match '(?i)claim cannot be grounded'
        $script:AgentFlat | Should -Match '(?i)name the missing context'
        $script:AgentFlat | Should -Match '(?i)ask one focused question'
        $script:AgentFlat | Should -Match '(?i)unverified claim as fact'
    }

    It 'tells the agent never to invent a domain identifier' {
        $script:AgentFlat | Should -Match '(?i)never invent a domain'
    }

    It 'requires domain orientation before bug-pattern matching' {
        $script:AgentFlat | Should -Match '(?i)read the selected `SKILL\.md` in full'
        $script:AgentFlat | Should -Match '(?i)references/architecture\.md'
        $script:AgentFlat | Should -Match '(?i)select the relevant references and Key Files'

        $orientationIndex = $script:Agent.IndexOf('Before diagnosing, read the selected `SKILL.md` in full.')
        $patternIndex = $script:Agent.IndexOf('Only then check the bug patterns.')
        $orientationIndex | Should -BeGreaterThan -1
        $patternIndex | Should -BeGreaterThan $orientationIndex
    }

    It 'allows one bounded history hop between orientation and bug patterns' {
        $script:AgentFlat | Should -Match '(?i)run the skill''s history triage before asking for a runtime log'
        $script:AgentFlat | Should -Match '(?i)at most one history hop'
        $script:AgentFlat | Should -Match '(?i)return to the selected Key Files'

        $architectureIndex = $script:Agent.IndexOf('Read its `references/architecture.md` next.')
        $triageIndex = $script:Agent.IndexOf('run the skill''s history triage')
        $patternIndex = $script:Agent.IndexOf('Only then check the bug patterns.')
        $architectureIndex | Should -BeGreaterThan -1
        $triageIndex | Should -BeGreaterThan $architectureIndex
        $patternIndex | Should -BeGreaterThan $triageIndex
    }

    It 'requires evidence of domain reading before diagnosis claims' {
        $script:AgentFlat | Should -Match '(?i)before presenting a diagnosis'
        $script:AgentFlat | Should -Match '(?i)implementation` session entry'
        $script:AgentFlat | Should -Match '(?i)selected `SKILL\.md` read in full'
        $script:AgentFlat | Should -Match '(?i)selected references and source files read in full'
        $script:AgentFlat | Should -Match '(?i)Claim skill support only for conclusions tied to a listed supporting file'
    }

    It 'does not treat a build or empty test output as verification' {
        $script:AgentFlat | Should -Match '(?i)a build is not a test result'
        $script:AgentFlat | Should -Match '(?i)targeted test command reports discovered tests and zero failures'
        $script:AgentFlat | Should -Match '(?i)execution is unconfirmed'
    }

    It 'keeps historical evidence apart from runtime verification' {
        $script:AgentFlat | Should -Match '(?i)Historical evidence is not\s+runtime verification'
        $script:AgentFlat | Should -Match '(?i)root-cause\s+confidence, runtime reproduction and fix verification as three separate lines'
    }

    It 'requires wrapper-only session completion with reported evidence' {
        $script:AgentFlat | Should -Match '(?i)Close only with `Complete-EiSession\.ps1`'
        $script:AgentFlat | Should -Match '(?i)never chain finalization and rendering yourself'
        $script:AgentFlat | Should -Match '(?i)Report its exit code and summary path'
        $script:AgentFlat | Should -Match '(?i)artifact path and failed step'
    }

    It 'shows the canonical installed-plugin session-close command' {
        $script:Agent | Should -Match '\$pluginInstallRoot\s*='
        $script:Agent | Should -Match 'plugins\\aveva-ei-graphics\\skills\\ei-graphics-core\\scripts\\Complete-EiSession\.ps1'
        $script:Agent | Should -Match '& \$sessionClose -StoryId \$storyId -Root \$targetRoot -SessionOutcome \$outcome'
    }

    It 'says a comment can override the description' {
        $script:AgentFlat | Should -Match '(?i)comment can correct the description'
    }

    It 'wires Checkpoint 1 into the intake path' {
        $script:Agent | Should -Match '(?m)^##\s+Confirm the understanding\s*$'
        $script:AgentFlat | Should -Match '(?i)Checkpoint 1'
        $script:AgentFlat | Should -Match '-Phase human-checkpoint'
    }

    It 'asks for the doctor choice once per user' {
        $script:AgentFlat | Should -Match 'doctor-decision\.json'
        $script:AgentFlat | Should -Match '(?i)ask once'
        $script:AgentFlat | Should -Match '-RememberDecision'
        $script:AgentFlat | Should -Match '-DeclineAndRemember'
        $script:AgentFlat | Should -Match '(?i)do not ask or run again'
    }

    It 'names nothing this build dropped' {
        # The list is read from tests/data/forbidden-identifiers.txt. Writing the names here would
        # make this file fail T019's own scan.
        $terms = @(
            Get-Content -LiteralPath (Join-Path $repoRoot 'tests' 'data' 'forbidden-identifiers.txt') |
                ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        )
        $terms.Count | Should -BeGreaterOrEqual 23
        $hits = @($terms | Where-Object { $script:Agent -like "*$_*" })
        $hits.Count | Should -Be 0 -Because "the agent file names: $($hits -join ', ')"
    }

    It 'mentions no lifecycle, which v3 does not have' {
        $script:Agent | Should -Not -Match '(?i)lifecycle'
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

    It 'rnd-delegation.md carries the reasoning escalation block' {
        $script:Delegation | Should -Match '(?m)^## When reasoning is not grounded\s*$'
        $script:Delegation | Should -Match '(?i)repeated reasoning adds no evidence'
        $script:Delegation | Should -Match '(?i)name the missing context'
        $script:Delegation | Should -Match '(?i)ask one focused question'
        $script:Delegation | Should -Match '(?i)unverified claim as fact'
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

    It 'local-input.md describes all five kinds' -ForEach @(
        'attached-report', 'attached-image', 'local-folder', 'pasted-symptom', 'local-log') {
        $script:LocalInput | Should -BeLike "*$_*"
    }

    It 'local-input.md forbids the Azure DevOps intake and the ado.json it would write' {
        $script:LocalInput | Should -Match '(?i)Do not run `Invoke-EiStoryIntake\.ps1`'
        $script:LocalInput | Should -Match '(?i)An absent `ado\.json` is correct on this route'
    }

    It 'local-input.md says what inputSource must carry' {
        foreach ($field in @('inputSource.kind', 'inputSource.reference', 'inputSource.hash', 'inputSource.adoNotUsedBecause')) {
            $script:LocalInput | Should -Match ([regex]::Escape($field))
        }
        $script:LocalInput | Should -Match '(?i)Leave `adoHash` out'
        $script:LocalInput | Should -Match '(?i)refuses a payload that\s+carries neither'
    }

    It 'local-input.md keeps the rest of the workflow unchanged' {
        $script:LocalInput | Should -Match '(?i)Checkpoint 1'
        $script:LocalInput | Should -BeLike '*Get-EiDomainSkillCatalog.ps1*'
        $script:LocalInput | Should -BeLike '*Complete-EiSession.ps1*'
    }

    It 'local-input.md asks for the input to be recorded as evidence' {
        $script:LocalInput | Should -Match '(?m)^## Record the input as evidence\s*$'
        $script:LocalInput | Should -Match '(?i)naming every file you read'
        $script:LocalInput | Should -Match ([regex]::Escape('attachmentUnderstanding'))
    }
}
