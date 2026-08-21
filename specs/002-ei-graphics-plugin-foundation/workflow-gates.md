# Workflow Gates: EI Graphics Plugin

## Purpose

These gates define the exact architecture and review checks for T-018. They are intended for plugin contract design, PR review support, and later deterministic enforcement.

## Gate levels

- `Block`: PR should not proceed until resolved.
- `Manual Review`: PR may proceed only with explicit human sign-off.
- `Advisory`: surface to reviewers but do not block by itself.

## Architecture gates

### A-001 Cross-layer reference gate

- Level: `Block`
- Trigger: application or domain projects reference presentation-layer projects, or a change increases an existing forbidden dependency.
- Evidence examples:
  - `Commands -> UI`
  - `Commands -> 3DPanelDesign`
  - `DomainServices -> Presentation`
- Required action: remove the dependency or provide an approved exception record.

### A-002 Vocabulary and schema change gate

- Level: `Manual Review`
- Trigger: edits to URI constants, class mappings, property mappings, or other semantic-schema files.
- Required evidence:
  - migration or compatibility rationale
  - impacted service/repository list
  - SME sign-off

### A-003 Silent failure gate

- Level: `Block`
- Trigger: new broad `catch (Exception)` handling, especially where errors are swallowed or replaced with null/default behavior.
- Required action: narrow the exception type or document and review the fallback path.

### A-004 Build artifact gate

- Level: `Block`
- Trigger: committed generated binaries, debug artifacts, or output-tree files.
- Required action: remove the artifact from the change set and confirm ignore coverage if needed.

## Review gates

### R-001 ADO linkage gate

- Level: `Block`
- Trigger: PR or change has no linked ADO bug, issue, investigation, or user story.
- Required evidence: linked work item and traceable change summary.

### R-002 Reproduction evidence gate

- Level: `Block`
- Trigger: bug fix has no reproduction evidence or explicit non-repro rationale.
- Required evidence:
  - reproduction steps
  - affected-area reasoning
  - explicit note if runtime validation in E3D is required

### R-003 Verification evidence gate

- Level: `Block`
- Trigger: no unit-test evidence, no test-scope rationale, or missing sanity/regression statement for the affected slice.
- Required evidence:
  - test files added or updated, or explicit rationale why not
  - local verification summary
  - PR sanity expectation or escalation note

### R-004 New TODO debt gate

- Level: `Advisory` by default, `Block` if high-risk path
- Trigger: new TODO, HACK, FIXME, or WORKAROUND comments are introduced.
- Required evidence: ADO tracking reference or justification for immediate follow-up.

### R-005 Domain-risk escalation gate

- Level: `Manual Review`
- Trigger: changes touch wiring rules, cable/core behavior, voltage validation, phase naming, distribution boards, or other electrical domain logic.
- Required evidence:
  - SME or senior engineer review
  - risk summary
  - impacted tests or sanity path

### R-006 PR sanity escalation gate

- Level: `Block`
- Trigger: high-risk areas are changed without a stated PR sanity or regression path.
- Required evidence:
  - expected PR sanity category or downstream QA path
  - note when tests live outside the module repo

### R-007 Spec synchronization gate

- Level: `Block`
- Trigger: any change under `plugins/aveva-ei-graphics/` without at least one matching update under `specs/002-ei-graphics-plugin-foundation/`.
- Required evidence:
  - updated planning or status artifact in the spec folder that reflects the plugin change
  - rationale for what changed and why

## Initial enforcement mapping

| Gate | Primary capability |
|---|---|
| A-001, A-003, A-004 | `ei-layer-guard` |
| R-001, R-002 | `ei-bug-reproducer` + workflow agent |
| R-003 | `ei-test-scaffolder` + workflow agent |
| R-004, R-005, R-006 | `ei-pr-reviewer` |
| R-007 | repository spec-sync gate (`tools/Test-EiGraphicsSpecSync.ps1`) |

## Notes

- These gates are workflow definitions first and deterministic automation targets second.
- Final severity thresholds can still be tuned with QA and EI leads, but Phase 1 should treat the `Block` gates above as the default policy.
