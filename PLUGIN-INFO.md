# EI Graphics Plugin — Reference

## Overview

Development and distribution repository for the **`aveva-ei-graphics`** agent plugin.

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

## Usage

Start with the `EI Graphics` agent. It is a thin conversational entry point that collects the work
item, routes to IMPLEMENT or ITERATE, and hands off to the `ei-graphics-workflow` skill, which owns
the lifecycle.

## Repository layout

```
plugins/aveva-ei-graphics/
├── .github/plugin/plugin.json
├── agents/          1 agent   (EI Graphics conversational entry point)
└── skills/          9 skills  (workflow controller, state, scope resolve/validate, ADO intake,
                                vocabulary, layer guard, test scaffolder, bug reproducer)
specs/002-ei-graphics-plugin-foundation/
                                Planning workspace: plan, roadmap, todo list, current status,
                                progress log, decisions, risks, and design/ history
tests/aveva-ei-graphics/        Pester tests for the gate scripts
tools/                          Repository gates (spec-sync)
```

## Planning and status

Before starting a tranche, read `specs/002-ei-graphics-plugin-foundation/current-status.md` and the
tail of `progress-log.md`. Repository conventions live in `.github/copilot-instructions.md`.

Any change under `plugins/aveva-ei-graphics/**` requires a matching change under
`specs/002-ei-graphics-plugin-foundation/**`:

```powershell
pwsh -NoProfile -File ./tools/Test-EiGraphicsSpecSync.ps1 -FromRef origin/main -ToRef HEAD
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

This plugin also exists inside the `AVEVA-Copilot-Access/aveva-agent-plugins` monorepo. **Active
development now happens here**; the monorepo copy is downstream.

When a tranche lands here, mirror `plugins/aveva-ei-graphics/**` and `tests/aveva-ei-graphics/**`
back to the monorepo so the two stay aligned.

Marketplace manifests are provided for both hosts:

- `.github/plugin/marketplace.json`
- `.claude-plugin/marketplace.json`
