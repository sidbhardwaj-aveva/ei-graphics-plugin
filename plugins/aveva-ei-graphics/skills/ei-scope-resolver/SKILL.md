---
name: ei-scope-resolver
description: 'Propose the smallest defensible implementation scope for an EI Graphics story: evidence-linked files, modules and tests, plus the questions that must be answered before anyone may approve it. Proposes only; never authorises a change.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
  - search
---

# EI Scope Resolver

## Goal

Turn a story into a **ProposedScope**: the smallest set of files, modules and tests that can be
defended with evidence, together with everything the resolver could not resolve.

This skill owns the `proposed-scope` stage of the IMPLEMENT lifecycle. It writes the
`proposed-scope` artifact and nothing else.

## Boundary

| The resolver does | The resolver never does |
|---|---|
| Propose a narrow, evidence-linked scope | Approve, authorise or lock a scope |
| Record what it could not resolve | Guess to make a story look resolvable |
| Drop anything it cannot defend | Include a file because it is "probably relevant" |
| Lower its own status | Raise a status, or clear a finding |
| Read the repository | Modify the repository |

There is no ApprovedScope here. Approval is a separate, human-owned stage.

## The conservatism rule

> A scope that is too small produces a question. A scope that is too large produces an unreviewable
> change.

So the resolver prefers `blocked` or `needs-review` over quiet inclusion. If a file cannot be tied
to evidence, it is **removed** from the proposal, recorded in `excluded`, and the removal is
recorded in `unresolved`. The proposal never silently broadens.

## Determinism boundary

| Decided by the model | Decided by the scripts |
|---|---|
| Which files, modules and symbols are candidates | Whether a candidate survives |
| What evidence supports each candidate | Whether that evidence exists |
| The rationale for the scope shape | Whether the scope is within policy limits |
| Which dependencies exist and what they are | Whether a dependency has been absorbed into scope |
| Which areas are protected and why | Whether a proposal overlaps one |
| — | The final `status` |

The model never writes `status`. It is derived from the recorded findings, every time, by
`Resolve-EiScopeStatus`.

## How to produce a candidate scope

Work in this order and stop as soon as you are guessing.

1. **Read the story.** Extract the behaviour being changed, not the implementation you imagine.
2. **Anchor on domain context.** Use the supplied domain context to name the implementation area.
   With no domain context you cannot confirm the area, and the scope can never be `resolved`.
3. **Search for the anchor terms**, then for the symbols those searches reveal. Record each search
   term and each path you relied on as an `evidence` entry.
4. **Propose only what the evidence covers.** Every proposed file cites at least one evidence id.
   If you cannot cite one, do not propose the file.
5. **Name the dependencies.** Anything the change touches that is outside the area is a
   `dependencies` entry with `resolution: unresolved` — not an extra file.
6. **Declare protected areas** you noticed (shared contracts, generated code, public API surfaces).
7. **Name the tests** that would prove the change.
8. **State your confidence and rationale.** The rationale must explain why this is the *smallest*
   defensible scope, not why it is a complete one.
9. **List anything still unclear** as an `unresolved` entry with an `EISR-*` code.

### Candidate document

`New-EiProposedScope.ps1` consumes a candidate JSON document you write:

```json
{
  "confidence": 0.82,
  "rationale": "Story changes only the label placement rule; the renderer owns that rule.",
  "evidence": [
    { "id": "E1", "kind": "story", "value": "labels overlap when two terminations share a point", "note": null },
    { "id": "E2", "kind": "path", "value": "src/Ei.Graphics.Rendering/LabelPlacement.cs", "note": "contains the placement rule" }
  ],
  "proposedFiles": [
    { "path": "src/Ei.Graphics.Rendering/LabelPlacement.cs", "changeIntent": "modify", "symbols": ["Resolve"], "evidence": ["E1", "E2"], "confidence": 0.86 }
  ],
  "proposedModules": [
    { "name": "Ei.Graphics.Rendering", "projectPath": "src/Ei.Graphics.Rendering/Ei.Graphics.Rendering.csproj", "evidence": ["E2"] }
  ],
  "relatedTests": [
    { "target": "tests/Ei.Graphics.Rendering.Tests/LabelPlacementTests.cs", "kind": "targeted", "evidence": ["E2"] }
  ],
  "protectedAreas": [],
  "dependencies": [],
  "excluded": [],
  "risks": [],
  "unresolved": []
}
```

`status` and `generatedAt` are not yours to write. The script derives them.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/New-EiProposedScope.ps1` | Apply policy to a candidate scope and emit the `proposed-scope` artifact |
| `scripts/Test-EiProposedScope.ps1` | Deterministic gate for the `proposed-scope` stage |
| `scripts/helpers/EiScopeResolver.ps1` | Shared helpers (dot-sourced, not executed) |
| `references/scope-policy.json` | Limits and rule severities |

### Produce a scope

```powershell
./scripts/New-EiProposedScope.ps1 `
  -StoryInputPath   ./story.json `
  -CandidatePath    ./candidate.json `
  -DomainContextPath ./domain-context.json `
  -RepositoryRoot   . `
  -StateDir         .copilottracking/ei-graphics/123456 `
  -Json
```

`-StoryInputPath` supplies `{ "storyId", "storyRef", "summary" }`. Use `-StateDir` to persist
through `Write-EiWorkflowArtifact.ps1`, or `-OutputPath` to write a standalone file.

The script exits **0 whenever it produced a trustworthy artifact**, whatever that artifact's scope
status is — a `blocked` scope is a successful resolution of an unclear story. It exits 1 only when
no artifact could be produced at all (bad input, missing policy, failed schema, failed write).

### Gate a scope

```powershell
./scripts/Test-EiProposedScope.ps1 -StateDir .copilottracking/ei-graphics/123456 -Json
```

Exit 0 requires schema-valid **and** policy-clean **and** `status: resolved`. `needs-review` and
`blocked` are BLOCK states.

The gate re-derives the status from the artifact's own findings and re-checks evidence, protected
areas and dependency absorption, so an artifact edited after generation fails with
`EISR-STATUS-MISMATCH`.

## Status derivation

| Findings recorded in `unresolved` | Status |
|---|---|
| Any entry with `blocking: true` | `blocked` |
| Only non-blocking entries | `needs-review` |
| None | `resolved` |

## Policy rules

Limits and severities live in `references/scope-policy.json`, not in prose.

| Code | Trigger | Blocking | Drops the item |
|---|---|---|---|
| `EISR-EVIDENCE-MISSING` | A proposal cites no evidence, or an unknown evidence id | yes | yes |
| `EISR-PROTECTED-OVERLAP` | A proposed path sits inside a declared protected area | yes | yes |
| `EISR-DEPENDENCY-ABSORBED` | A proposed path or module belongs to an unresolved dependency | yes | yes |
| `EISR-EMPTY-SCOPE` | No file survived the checks | yes | — |
| `EISR-CONTEXT-MISSING` | No domain context, or no terms in it | no | — |
| `EISR-AREA-AMBIGUOUS` | Domain context reported ambiguous terms | no | — |
| `EISR-SCOPE-BREADTH` | More files or modules than the policy allows | no | — |
| `EISR-DEPENDENCY-UNRESOLVED` | A dependency is recorded as unresolved | no | — |
| `EISR-PATH-UNVERIFIED` | A proposed path could not be found under the repository root | no | — |
| `EISR-CONFIDENCE-LOW` | Confidence below `limits.minConfidence` | no | — |
| `EISR-TESTS-MISSING` | No related tests proposed | no | — |

A path "belongs to" a dependency when the dependency name appears as a whole path segment, or as a
file name without its extension. Substring matching would be guesswork, so it is not used.

Script-level failures, which produce no artifact at all:

| Code | Meaning |
|---|---|
| `EISR-INPUT-INVALID` | Missing or malformed story, candidate or domain-context input |
| `EISR-POLICY-MISSING` | `scope-policy.json` could not be loaded |
| `EISR-ARTIFACT-SCHEMA` | Generated artifact failed schema validation |
| `EISR-ARTIFACT-WRITE` | Artifact could not be persisted to state |

Gate-only codes: `EISR-ARTIFACT-MISSING`, `EISR-ARTIFACT-UNREADABLE`, `EISR-STATUS-MISMATCH`,
`EISR-SCHEMA-VERSION`, `EISR-SCOPE-NOT-RESOLVED`.

A supplied-but-missing `-DomainContextPath` is `EISR-INPUT-INVALID`, never a silent skip. Omitting
the parameter is a deliberate choice, and it costs you `EISR-CONTEXT-MISSING`.

## Implementation status

| Capability | State |
|---|---|
| ProposedScope schema and artifact | Implemented (Phase B) |
| Policy-driven narrowing and status derivation | Implemented (Phase B) |
| Proposed-scope stage gate | Implemented (Phase B) |
| ApprovedScope sealing and the `scope-hash` gate | Implemented (Phase B) — owned by `ei-graphics-workflow`, not this skill |
| Human approval orchestration and the `awaiting-approval` status | Implemented (Phase B) — owned by `ei-graphics-workflow`, not this skill |
| Scope-change requests and drift validation | Implemented (Phase B) — owned by `ei-scope-validator`, not this skill |
| Automatic candidate generation from ADO and vocabulary artifacts | Not implemented |

The `ado-intake` and `domain-context` stages that precede this one are implemented (Phase C), so a
wired run reaches the resolver. The resolver does not yet derive its own candidates from those
artifacts: the scripts take explicit inputs, so the caller still supplies the candidate set.
