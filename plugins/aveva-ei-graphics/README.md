# AVEVA EI Graphics Plugin

Shared workflow and domain capabilities for EI Graphics engineering teams.

## What this plugin does

This plugin provides the foundation for a legacy-safe EI Graphics workflow that combines:

- Bug reproduction and affected-area discovery
- EI domain and vocabulary navigation
- Architecture and layer guardrails
- Test scaffolding and PR review support

Deterministic Phase 1 slices are implemented for bug reproduction, vocabulary navigation, layer guardrails, test scaffolding, and first-pass PR review packaging.

## Agents

| Agent | Purpose |
|-------|---------|
| `EI Graphics` (`ei-graphics.agent.md`) | Thin conversational entry point: collects the story or PR, routes IMPLEMENT vs ITERATE, invokes `ei-graphics-workflow`, reports the contract |

The lifecycle itself is owned by the `ei-graphics-workflow` skill, not by additional agents.

## Skills

| Skill | Purpose |
|-------|---------|
| `ei-graphics-workflow` | Lifecycle controller: preflight, stage ordering, gates, retry ceiling, IMPLEMENT/ITERATE routing, result contract |
| `ei-workflow-state` | File-backed workflow state, artifact registry, schemas, resume, and schema-validated artifact read/write |
| `ei-scope-resolver` | Conservative ProposedScope resolution and the artifact-integrity gate over it |
| `ei-scope-validator` | `scope-analysis` approval-readiness gate, `scope-validation` drift gate, and scope-change requests |
| `ei-bug-reproducer` | Build reproduction guidance, affected-area hypotheses, and related test context from ADO bugs and repo evidence |
| `ei-azure-devops-cli-intake` | Resolve a pasted Azure DevOps work item reference to a work item id and retrieve normalized intake content via CLI; reads title, description, acceptance criteria and repro steps, downloads embedded images, and fixes organization and project to `AVEVA-VSTS` / `Dabacon Products` |
| `ei-vocabulary-navigator` | Resolve EI domain terms into URIs, models, repositories, services, and command paths |
| `ei-layer-guard` | Detect cross-layer references and architecture violations before PR creation |
| `ei-test-scaffolder` | Scaffold MSTest verification slices aligned to EI conventions |

## Architecture

```text
user
  -> ei-graphics.agent.md          (thin conversational entry)
  -> ei-graphics-workflow          (lifecycle owner)
  -> EI skills + R&D skills + Core skills
  -> deterministic gates
  -> .copilottracking/ei-graphics/<story-id>/
  -> Git / PR
```

Cross-plugin capabilities (`/aveva-rnd:code-review`, `/aveva-rnd:get-reviewresults`,
`/aveva-rnd:git-commit`, `/aveva-rnd:create-pr`, `/aveva-rnd:bug-diagnosis`,
`/aveva-core:create-audit`) are reused, never reimplemented here. Dependency metadata does not
install a plugin, so the workflow preflights them and fails closed.

### Determinism boundary

LLMs are non-deterministic — the same prompt can yield different output, and the same rule can be
interpreted differently between runs. So the split is deliberate:

- **AI** handles reasoning and interpretation: diagnosis, drafting, choosing an approach,
  explaining a result.
- **Deterministic PowerShell** handles anything that must be enforced identically every single
  time: gates, validation, schema and scope checks.

If a step can pass or fail, it is a script with an exit code and a Pester test — not a prompt. The
agent reports gate results; it never re-derives or overrules them.

## Plugin structure

```text
aveva-ei-graphics/
├── .github/plugin/plugin.json
├── README.md
├── agents/
│   └── ei-graphics.agent.md
└── skills/
    ├── ei-graphics-workflow/SKILL.md
    ├── ei-workflow-state/SKILL.md
    ├── ei-scope-resolver/SKILL.md
    ├── ei-scope-validator/SKILL.md
    ├── ei-azure-devops-cli-intake/SKILL.md
    ├── ei-bug-reproducer/SKILL.md
    ├── ei-vocabulary-navigator/SKILL.md
    ├── ei-layer-guard/SKILL.md
    └── ei-test-scaffolder/SKILL.md
```

## Implementation notes

- Phase 1 is PR-oriented and human-reviewed by design.
- High-risk legacy surfaces and architecture violations are expected to hard-block until required checks pass.
- Every deterministic script added in this plugin must ship with Pester tests.
- Tests use Pester 5+ syntax and run under the repository runner (`tests/Invoke-PesterTests.ps1`).

## Workflow implementation status

| Phase | Scope | Status |
|-------|-------|--------|
| A | Thin agent, workflow skill, state store, schemas, result contract, preflight | Implemented |
| B | Scope resolution, ProposedScope/ApprovedScope, approval checkpoint, scope validator | Implemented |
| C | `ado-intake` and `domain-context`: the two context stages ahead of the scope layer, their artifacts, and the `domain-pack-selection` gate | Implemented |
| D | IMPLEMENT writing and evidence stages: SpecKit spec/plan/tasks/implement, tests, invariant validation, review, audit, commit, PR | Not implemented |
| E | ITERATE stages: iteration recovery, diagnosis, minimal correction, tests, review, audit, same branch and PR | Not implemented |

Phase membership is defined by `implementedInPhase` in the `ei-graphics-workflow` lifecycle
references; this table only summarises it.

### Known limitations

- A wired IMPLEMENT run reaches `preflight -> state-init -> ado-intake -> domain-context ->
  proposed-scope -> scope-analysis -> scope-approval` and stops there. The stages after approval are
  Phase D and BLOCK. No stage is ever silently skipped.
- `domain-context` does not derive candidate terms from the story on its own. The caller proposes
  terms and the stage decides which survive, so a run with no terms blocks rather than guessing.
- `workflow-state`, `workflow-result`, `ado`, `domain-context`, `proposed-scope`, `approved-scope`,
  `scope-change-request` and `validation` have schemas. The remaining registry artifacts are
  `reserved`, and writing one fails closed with `EIWF-SCHEMA-PENDING`.
- Cross-plugin discovery is filesystem-based across known install roots. Hosts with a different
  layout must pass `-PluginSearchRoot`.
- `New-EiWorkflowResult.ps1` resolves versioned artifacts at version 1 only, so a run that sealed a
  later `approved-scope` version is under-reported by the result contract.
- Drift validation is not yet wired into the writing stages, because those stages are Phase D.

