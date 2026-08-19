# EI Graphics Plugin

Distribution repository for the **`aveva-ei-graphics`** agent plugin.

The plugin is a gated delivery lifecycle for EI Graphics work. It takes a story from Azure DevOps
(or an existing PR/branch) through domain context, an approved scope checkpoint, implementation,
code review, and pull request — without silently expanding scope or skipping a gate.

Two routes are supported:

- **IMPLEMENT** — new work from an Azure DevOps story.
- **ITERATE** — returning to existing work, including bug reproduction and diagnosis.

## Prerequisites

| Requirement | Notes |
|---|---|
| PowerShell 7+ | All gate scripts target `#Requires -Version 7.0` |
| Pester 5+ | Only needed to run the test suite |
| **`aveva-rnd` plugin** | **Not bundled.** Install from the AVEVA marketplace |
| **`aveva-core` plugin** | **Not bundled.** Install from the AVEVA marketplace |

`aveva-rnd` and `aveva-core` are hard dependencies from **Phase D** onward. Plugin metadata cannot
install another plugin, so the workflow preflights them and **fails closed** with
`EIWF-DEPENDENCY-MISSING` if one is absent.

| Dependency | Skills used | Required from |
|---|---|---|
| `aveva-rnd` | `code-review`, `get-reviewresults`, `git-commit`, `create-pr`, `speckit-bootstrap` | Phase D |
| `aveva-rnd` | `bug-diagnosis` | Phase E |
| `aveva-core` | `create-audit` | Phase D |

Check your environment at any time:

```powershell
./plugins/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/Validate-EiWorkflowPrerequisites.ps1 -Phase D -Json
```

Exit code `0` means `Status = Valid`; `1` means a dependency is missing.

## Installation

Add this repository to `chat.plugins.marketplaces` in your VS Code user settings
(**Preferences: Open User Settings (JSON)**):

```jsonc
"chat.plugins.marketplaces": [
    "https://github.com/AVEVA-Copilot-Access/aveva-agent-plugins",
    "https://github.com/sidbhardwaj-aveva/ei-graphics-plugin"
]
```

Keep the `aveva-agent-plugins` entry — that is where the required `aveva-rnd` and `aveva-core`
plugins come from.

Then reload the window and install the **`aveva-ei-graphics`** plugin from the plugin picker.

Marketplace manifests are provided for both hosts:

- `.github/plugin/marketplace.json`
- `.claude-plugin/marketplace.json`

## Usage

Start with the `EI Graphics` agent. It is a thin conversational entry point that collects the work
item, routes to IMPLEMENT or ITERATE, and hands off to the `ei-graphics-workflow` skill, which owns
the lifecycle.

## Repository layout

```
plugins/aveva-ei-graphics/
├── .github/plugin/plugin.json
├── agents/          5 agents  (entry point, ADO ingest, code review, PR review, bug-diagnosis-to-spec)
└── skills/          9 skills  (workflow controller, state, scope resolve/validate, ADO intake,
                                vocabulary, layer guard, test scaffolder, bug reproducer)
tests/aveva-ei-graphics/        Pester tests for the gate scripts
```

## Determinism

Any rule that can pass or fail is a PowerShell script with an exit code and a Pester test — never
model judgement. A gate result must be reproducible by a second person running the same command.
Agents may explain a gate result; they may never overrule or re-derive one.

## Tests

```powershell
pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
```

## Relationship to `aveva-agent-plugins`

This plugin also ships inside the `AVEVA-Copilot-Access/aveva-agent-plugins` monorepo. That repo is
the upstream source of truth; this repository exists to distribute the plugin to the EI Graphics
team independently.
