---
name: ei-scope-validator
description: 'Judge an EI Graphics scope twice: before approval, whether a ProposedScope is narrow and provable enough to put in front of a human; after every writing stage, whether what was actually changed is inside the sealed ApprovedScope. Records findings and raises scope-change requests; never widens a scope.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
  - search
---

# EI Scope Validator

## Goal

Own the two gates that stand either side of a human approval:

| Gate | Stage | Question |
|---|---|---|
| `scope-analysis` | `scope-analysis` | Is this proposal narrow and provable enough to be worth a human decision? |
| `scope-validation` | after every stage with `writesFiles: true` | Did the writer stay inside the sealed scope? |

It also owns the `scope-change-request` artifact, which is how a scope is widened without ever
editing a seal.

## Boundary against `ei-scope-resolver`

These two skills answer different questions and must not drift into each other.

| `Test-EiProposedScope.ps1` (resolver) | `Invoke-EiScopeAnalysis.ps1` (validator) |
|---|---|
| Artifact integrity and deterministic consistency | Approval readiness |
| Is the declared status the one the findings imply? | Is this scope defensible enough to approve? |
| Is every path still evidence-linked? | Is every path provable by a named test? |
| Is the scope inside the resolver's hard limits? | Is the scope inside the *review* thresholds? |
| Fails when the artifact was edited outside the resolver | Fails when the scope is honest but too broad or too vague |

Analysis runs **after** the resolver gate, never instead of it. A scope the resolver did not mark
`resolved` is never analysed into readiness — the validator can only ever agree with a resolver
finding, never soften one.

## Determinism boundary

Every threshold is data:

- `references/approval-policy.json` — review thresholds, the per-file confidence floor, the
  implementation-area limit, the drift allow-list, and the rule catalogue with each rule's severity.
- `ei-scope-resolver/references/scope-policy.json` — the hard size limits and the scope-level
  confidence floor. These are **not** restated here; the validator defers to the resolver policy.

A finding's severity comes from the policy, not from the script, and never from the model.
`blocking` findings make the verdict `block`; `advisory` findings are recorded for the approver and
do not block.

## Gate 1 — `scope-analysis`

```powershell
& "<skills>/ei-scope-validator/scripts/Invoke-EiScopeAnalysis.ps1" -StateDir '<state-dir>' -Json
```

Checks, in policy order:

| Code | Severity | Fires when |
|---|---|---|
| `EISV-SCOPE-NOT-RESOLVED` | blocking | The resolver did not return `resolved` |
| `EISV-AREA-SPREAD` | blocking | The files span more implementation areas than one story should |
| `EISV-FILE-CONFIDENCE-LOW` | blocking | A file is below the per-file confidence floor |
| `EISV-SYMBOLS-MISSING` | blocking | A `modify` names no symbol, so the blast radius is the whole file |
| `EISV-TEST-COVERAGE-GAP` | blocking | No related test names a proposed file |
| `EISV-RISK-HIGH` | blocking | A high-severity risk is recorded |
| `EISV-BREADTH-REVIEW` | advisory | More files than a routine change, still within the resolver limit |
| `EISV-ADDED-FILE-BREADTH` | advisory | Several new files |
| `EISV-DELETE-PRESENT` | advisory | The scope deletes files |
| `EISV-DEPENDENCY-UNRESOLVED` | advisory | An unresolved dependency sits beside the scope |

An implementation area is the first *n* directory segments of a path (`areaSegmentDepth`), so
`src/Ei.Graphics.Rendering/LabelPlacement.cs` sits in `src/Ei.Graphics.Rendering`. A related test
names a file when the test target contains the file's stem — anything looser would be the model
guessing at coverage.

The evidence records the canonical hash of the scope it judged. That hash is what binds a later
approval to what the approver was actually shown.

## Gate 2 — `scope-validation`

```powershell
& "<skills>/ei-scope-validator/scripts/Test-EiScopeDrift.ps1" -StateDir '<state-dir>' `
    -Stage 'implementation' -RepositoryRoot '<repo>' -Json

& "<skills>/ei-scope-validator/scripts/Test-EiScopeDrift.ps1" -StateDir '<state-dir>' `
    -Stage 'implementation' -ChangedPath 'src/A.cs','src/B.cs' -Json
```

The seal is verified first: a drift check against an edited ApprovedScope proves nothing, so a
failing `scope-hash` gate is `EISV-SEAL-UNVERIFIED` and the comparison never runs.

Each changed path is then classified against the sealed scope:

| Classification | Meaning |
|---|---|
| `in-scope` | The sealed scope names this exact path |
| `protected` | Inside a declared protected area — `EISV-DRIFT-PROTECTED` |
| `allowed` | Matches `drift.allowedPathPrefixes`; workflow bookkeeping, not implementation output |
| `out-of-scope` | Everything else — `EISV-DRIFT-OUT-OF-SCOPE` |

Membership is by exact path, never by directory or proximity. "It is in the same folder" is not
authorisation.

Reporting no changed paths at all is an input error, not a pass: `EISV-INPUT-INVALID`. Absent
evidence is never evidence of absence.

## Evidence

Both gates write the `validation` artifact. Because `validation.json` is a single file that each
validating stage overwrites, every run also keeps a per-stage copy in the registered `validation/`
directory:

```text
.copilottracking/ei-graphics/<story-id>/
  validation.json                  # the most recent validation evidence
  validation/scope-analysis.json   # kept, and read by the approval checkpoint
  validation/implementation.json   # kept
```

Evidence is written whether the verdict is `pass` or `block`, because a block with no record of why
is indistinguishable from a stage that never ran. The validator writes only its own evidence: it
never touches `workflow-state.json`, the ProposedScope, or a seal.

## Scope-change requests

```powershell
& "<skills>/ei-scope-validator/scripts/New-EiScopeChangeRequest.ps1" -StateDir '<state-dir>' `
    -RequestedBy '<who>' -Reason '<why the sealed scope is insufficient>' `
    -Path 'src/Ei.Graphics.Rendering/LabelMetrics.cs' -DetectedBy scope-validation -Json
```

The request is immutable and append-only: `scope-change-request.v1.json`, `v2.json`, and so on. It
records the sealed version and hash it was raised against, so it cannot be re-pointed at a different
seal later.

| Refusal | Reason |
|---|---|
| `EISV-CHANGE-PROTECTED` | A protected area is never widened by request |
| `EISV-CHANGE-REDUNDANT` | Every requested path is already authorised, so there is nothing to approve |
| `EISV-CHANGE-REQUESTER-MISSING` | An unattributed request cannot be answered |
| `EISV-SEAL-UNVERIFIED` | The seal it would be raised against is not intact |

Raising a request changes nothing. It does not mutate the seal, the workflow state, or the scope. A
request is answered by re-resolving, re-analysing, and sealing a **new** ApprovedScope version.

## Exit codes

Every script returns the shared result contract and exits `0` for `Valid`, `1` for `Invalid`. A
blocking finding is `Invalid`.

## Implementation status

| Capability | Status |
|---|---|
| `scope-analysis` gate and approval-readiness policy | Implemented (Phase B) |
| `scope-validation` drift gate and validation evidence | Implemented (Phase B) |
| `scope-change-request` artifact | Implemented (Phase B) |
| A `scope-change` lifecycle stage | Not modelled — the artifact registry names the stage, but no lifecycle declares it. Requests are raised out of band when a gate blocks. |
| Drift validation wired into every writing stage | Not implemented — the writing stages are Phase D |
