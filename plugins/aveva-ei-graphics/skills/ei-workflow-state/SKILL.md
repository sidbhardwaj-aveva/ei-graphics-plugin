---
name: ei-workflow-state
description: 'Own the file-backed EI Graphics workflow state under .copilottracking/ei-graphics/<story-id>/: schemas, artifact registry, initialisation, resume detection, and schema-validated artifact read/write.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
---

# EI Workflow State

## Goal

Give `ei-graphics-workflow` a recoverable, schema-validated state store so no lifecycle stage
depends on narrative context. Every stage writes an artifact, the workflow re-reads it, and the
next stage consumes the artifact.

This skill owns persistence only. It does not decide lifecycle order, and it never runs a stage.

## State location

```text
.copilottracking/ei-graphics/<story-id>/
  workflow-state.json      # owned by this skill
  workflow-result.json     # owned by ei-graphics-workflow
  validation/              # per-stage validator evidence
```

`<story-id>` must match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`. Anything else is rejected, because the
story id becomes a directory name.

`.copilottracking/` is git-ignored, so state never reaches a commit or PR.

## Artifact registry

`schemas/artifact-registry.json` is the single source of truth for artifact names, file names,
owners, schemas, and the implementation phase that activates them. Artifacts marked `reserved` have
no schema yet and cannot be written — writing them would create unvalidated state.

| Artifact | File | Owner | Status |
|---|---|---|---|
| `workflow-state` | `workflow-state.json` | `ei-workflow-state` | active |
| `workflow-result` | `workflow-result.json` | `ei-graphics-workflow` | active |
| `ado` | `ado.json` | `ei-azure-devops-cli-intake` | reserved (Phase C) |
| `domain-context` | `domain-context.json` | `ei-vocabulary-navigator` | reserved (Phase C) |
| `proposed-scope` | `proposed-scope.json` | `ei-scope-resolver` | active |
| `approved-scope` | `approved-scope.v{version}.json` | `ei-graphics-workflow` | active |
| `scope-change-request` | `scope-change-request.v{version}.json` | `ei-scope-validator` | active |
| `specification` / `plan` / `tasks` / `implementation` | `*.json` | R&D SpecKit workers | reserved (Phase D) |
| `validation` | `validation.json` | `ei-scope-validator` | active |
| `code-review` / `audit` / `pr` | `*.json` | R&D / Core skills | reserved (Phase D) |
| `iteration` / `diagnosis` | `*.json` | `ei-graphics-workflow` / `aveva-rnd:bug-diagnosis` | reserved (Phase E) |

Persist identifiers and references (work item ids, commit SHAs, PR ids, run ids, file paths), never
copies of source code.

## Scripts

All scripts return `{ Status, Errors, Warnings, Details }` and exit `0` for `Valid`, non-zero for
`Invalid`. Invoke them through `$PSScriptRoot`-relative paths so the working directory is
irrelevant.

| Script | Purpose |
|---|---|
| `scripts/Initialize-EiWorkflowState.ps1` | Create or resume `<story-id>` state from the lifecycle definition |
| `scripts/Validate-EiWorkflowState.ps1` | Integrity, ordering, gate, retry and resume checks |
| `scripts/Set-EiWorkflowStage.ps1` | The only supported stage transition: start, complete, block |
| `scripts/Set-EiWorkflowApproval.ps1` | The only supported way into and out of `awaiting-approval` |
| `scripts/Set-EiApprovedScopeSeal.ps1` | The only supported way to record a sealed scope hash and version |
| `scripts/Write-EiWorkflowArtifact.ps1` | Schema-validated artifact write |
| `scripts/Read-EiWorkflowArtifact.ps1` | Schema-validated artifact read for the next stage |

### Initialise or resume

```powershell
& "<skills>/ei-workflow-state/scripts/Initialize-EiWorkflowState.ps1" `
    -StoryId '123456' -WorkflowPath IMPLEMENT -StoryRef '<ado-url>' -Json
```

`Details.Resumed` is `true` when a valid run already exists. Existing state is never overwritten
without `-Force`, and `-Force` archives the previous file as `workflow-state.<timestamp>.bak.json`.

### Validate

```powershell
& "<skills>/ei-workflow-state/scripts/Validate-EiWorkflowState.ps1" -StateDir '<state-dir>' -Json
```

### Transition a stage

`workflow-state.json` is never hand-edited. Every stage movement goes through one script so the
same rules apply on every run.

```powershell
& "<skills>/ei-workflow-state/scripts/Set-EiWorkflowStage.ps1" -StateDir '<state-dir>' -StageId 'preflight' -Action start -Json
& "<skills>/ei-workflow-state/scripts/Set-EiWorkflowStage.ps1" -StateDir '<state-dir>' -StageId 'preflight' -Action complete -GateResult pass -Json
& "<skills>/ei-workflow-state/scripts/Set-EiWorkflowStage.ps1" -StateDir '<state-dir>' -StageId 'preflight' -Action block `
    -BlockCode 'EIWF-DEPENDENCY-MISSING' -BlockMessage '<why>' -Remediation '<fix>' -Json
```

| Action | Allowed from | Enforced rules |
|---|---|---|
| `start` | `pending` | Workflow is `in-progress`; every earlier stage is `complete` or `skipped` |
| `complete` | `running` | A gated stage must supply `-GateResult pass`; a required artifact must read back schema-valid |
| `block` | `pending`, `running` | `-BlockCode` and `-BlockMessage` are mandatory; workflow status becomes `blocked` |

A gate result is never assumed, `-GateResult block` cannot complete a stage, a complete stage cannot
be restarted or re-completed, and a blocked run advances nothing until the owning checkpoint clears
it. The candidate state is validated against the schema **and** `Validate-EiWorkflowState.ps1`
before it is committed, so a rejected transition leaves `workflow-state.json` byte-identical.

### Pause for a human decision

`awaiting-approval` is a real pause, not a label. While it is set, `start` refuses every stage, so
nothing advances until a decision is recorded.

```powershell
& "<skills>/ei-workflow-state/scripts/Set-EiWorkflowApproval.ps1" -StateDir '<state-dir>' `
    -StageId 'scope-approval' -Action request -Json
& "<skills>/ei-workflow-state/scripts/Set-EiWorkflowApproval.ps1" -StateDir '<state-dir>' `
    -StageId 'scope-approval' -Action grant -Json
```

| Action | Allowed from | Enforced rules |
|---|---|---|
| `request` | `in-progress` | The named stage owns the `human-approval` gate and has not been decided |
| `grant` | `awaiting-approval` | The same stage checks apply; a pause that was never requested cannot be granted |

The checkpoint records that a decision was taken; it is not the decision. The decision itself lives
in the sealed ApprovedScope for an approval, or in a block record for a refusal — which is why this
script cannot manufacture one. It deliberately leaves `state.stage` and every stage status alone, so
stage bookkeeping stays with `Set-EiWorkflowStage.ps1`, and it validates the candidate before
committing, so a refused checkpoint leaves `workflow-state.json` byte-identical.

### Record a sealed scope

`approvedScopeHash` and `approvedScopeVersion` are not a stage transition, so they have their own
narrow mutation path with the same validate-before-commit discipline.

```powershell
& "<skills>/ei-workflow-state/scripts/Set-EiApprovedScopeSeal.ps1" -StateDir '<state-dir>' `
    -ContentHash 'sha256:<64 hex>' -Version 1 -Json
```

A seal version is never reused or lowered, and a hash that is not a lowercase `sha256:<64 hex>`
digest is rejected. `ei-graphics-workflow` calls this only after the sealed artifact has been
written and has passed its own `scope-hash` gate; it is not for hand use.

### Read and write artifacts

```powershell
& "<skills>/ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1" -StateDir '<state-dir>' -Name 'workflow-result' -Content $json -Json
& "<skills>/ei-workflow-state/scripts/Read-EiWorkflowArtifact.ps1"  -StateDir '<state-dir>' -Name 'workflow-result' -Json
```

A versioned artifact takes `-Version`, which fills the `{version}` placeholder in its registered
file name: `approved-scope.v2.json` is `-Name 'approved-scope' -Version 2`.

## Block codes

| Code | Meaning |
|---|---|
| `EIWF-STORY-ID` | Story id is not a safe state directory name |
| `EIWF-LIFECYCLE-MISSING` / `EIWF-LIFECYCLE-INVALID` | Lifecycle definition missing or malformed |
| `EIWF-STATE-MISSING` | No state file; a stage was attempted before initialisation |
| `EIWF-STATE-CORRUPT` / `EIWF-STATE-SCHEMA` | State unreadable or schema-invalid |
| `EIWF-PATH-MISMATCH` | IMPLEMENT/ITERATE requested against a run of the other path |
| `EIWF-STAGE-UNKNOWN` / `EIWF-STAGE-ORDER` | Current stage unknown, or lifecycle order bypassed |
| `EIWF-STATE-UNUSABLE` | A transition was attempted against missing or invalid state |
| `EIWF-TRANSITION-INVALID` | The requested stage transition is not allowed from the current status |
| `EIWF-GATE-REQUIRED` / `EIWF-GATE-INVALID` | A gate result was not supplied, or did not pass |
| `EIWF-BLOCK-INPUT` | A block was raised without a code and a message |
| `EIWF-GATE-UNVERIFIED` | A stage is complete without a passing gate |
| `EIWF-RETRY-EXCEEDED` | Correction attempts exceeded the ceiling of 3 |
| `EIWF-BLOCK-UNEXPLAINED` | Blocked status with no recorded block |
| `EIWF-ARTIFACT-UNKNOWN` / `EIWF-ARTIFACT-MISSING` | Artifact not registered, or required artifact absent |
| `EIWF-ARTIFACT-INVALID` / `EIWF-ARTIFACT-SCHEMA` | Artifact not JSON, or schema-invalid |
| `EIWF-SCHEMA-PENDING` | Artifact reserved for a later implementation phase |
| `EIWF-STATE-DIR-MISSING` | Artifact write attempted before initialisation |
| `EIWF-SCOPE-HASH-INVALID` | A seal was offered without a lowercase `sha256:<64 hex>` digest |
| `EIWF-SCOPE-VERSION-INVALID` | A seal would reuse or lower an already sealed scope version |
| `EIWF-APPROVAL-STATE` | A pause was requested or granted from a status that does not allow it |
| `EIWF-APPROVAL-STAGE` | The named stage does not own the `human-approval` gate, or has already been decided |

Absence of evidence is never a pass.

## Implementation status

Phase A implements the state store, the state and result schemas, the artifact registry,
initialisation/resume, and deterministic stage transitions. Phase B has since activated
`proposed-scope`, `approved-scope`, `validation` and `scope-change-request`, and added the seal
recording script and the approval checkpoint. Artifacts for SpecKit, review, audit, and PR stages
are registered but reserved until their owning phase lands.

Not yet modelled, because the architecture does not encode a rule for them: clearing a `blocked`
run, the `skipped` stage status, and correction-attempt increments (Phase E). Those transitions
belong to their owning phase and must not be improvised here.
