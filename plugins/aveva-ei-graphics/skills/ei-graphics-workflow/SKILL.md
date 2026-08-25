---
name: ei-graphics-workflow
description: 'Lifecycle controller for EI Graphics work. Owns prerequisites, dependency preflight, stage ordering, artifact initialisation, the scope checkpoint, resume behaviour, gate evaluation, retry limits, IMPLEMENT vs ITERATE routing, and the workflow result contract. Load this skill to run an EI Graphics story end to end.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
  - search
metadata:
  dependencies:
    - code-review
    - get-reviewresults
    - create-audit
    - git-commit
    - create-pr
    - bug-diagnosis
    - speckit-bootstrap
---

# EI Graphics Workflow

## Goal

Take an EI Graphics story from Azure DevOps to a reviewed pull request without ever silently
expanding scope, skipping a gate, or trusting a writer stage.

This skill is the lifecycle owner. `ei-graphics.agent.md` is a thin conversational entry point that
collects input, loads this skill, and reports the returned contract. Leaf skills own *how* a stage
is performed; this skill owns *when*, *in what order*, *with what evidence*, and *when to block*.

```text
workflow -> skill -> artifact -> gate -> next skill
```

Do not use `runSubagent` anywhere in this lifecycle. Stages run through skills, scripts, and
supported skill delegation; reasoning agents are workers, never lifecycle owners.

## Determinism boundary

LLMs are non-deterministic. The same prompt can return different output on different runs, and the
same written rule can be interpreted differently each time. Correctness in this lifecycle therefore
never rests on model judgement.

| Use AI for | Use a PowerShell script for |
|---|---|
| Reasoning and interpretation | Any rule that must be enforced identically every run |
| Diagnosis, hypothesis forming, drafting | Gate pass/fail decisions |
| Choosing an approach, summarising evidence | Validation, schema checks, scope checks |
| Explaining a block to the user | Anything that returns a Valid/Invalid status |

Rules of thumb:

- If a step can pass or fail, it is a script with an exit code and a Pester test — not a prompt.
- A gate result must be reproducible by a second person running the same command.
- The agent may explain a gate result. It may never overrule, re-derive, or infer one.
- Prose in a `SKILL.md` guides reasoning; it is never the enforcement mechanism for a gate.

## Ownership boundary

| This skill owns | This skill must not do |
|---|---|
| Stage order and routing | Reimplement a leaf skill's logic |
| Prerequisite and dependency preflight | Assume dependency metadata installed a plugin |
| State initialisation, resume, and iteration index | Pass state through narrative context |
| Gate evaluation and BLOCK decisions | Treat "no evidence" as a pass |
| Retry ceiling and escalation | Run an unbounded autonomous repair loop |
| The result contract returned to the agent | Duplicate R&D or Core capabilities |

## Path resolution (run once)

Every script resolves its own dependencies through `$PSScriptRoot`, so the working directory is
irrelevant. Capture the roots once and invoke scripts with `&`.

```powershell
$eiSkills   = "<plugins>/aveva-ei-graphics/skills"
$workflow   = "$eiSkills/ei-graphics-workflow/scripts"
$stateSkill = "$eiSkills/ei-workflow-state/scripts"
```

## Progressive-disclosure fallback

If the host exposes a callable `skill` tool, invoke the named skill. If it does not, read that
skill's `SKILL.md` and execute its documented scripts exactly. Never silently omit a stage because
a skill could not be invoked — that is a BLOCK.

## Step 1 — Prerequisite and dependency preflight

```powershell
& "$workflow/Validate-EiWorkflowPrerequisites.ps1" -RepositoryRoot '<repo>' -Phase A -Json
```

Checks PowerShell 7+, git availability and work tree, the local EI skills, and the cross-plugin
capabilities declared in `references/required-capabilities.json`. Add `-PluginSearchRoot` for a
non-standard install location, or `-NoDefaultSearchRoots` to restrict discovery to the roots you
pass. A missing required plugin returns `EIWF-DEPENDENCY-MISSING` with, for example:

> `aveva-rnd is not installed. Install it from the marketplace and retry.`

`Status: Invalid` is a hard stop. Do not continue and do not substitute a local reimplementation.

## Step 2 — Determine the path

| Input | Path |
|---|---|
| ADO story URL or id with no existing state | `IMPLEMENT` |
| Existing branch/PR with review feedback or CI failures | `ITERATE` |
| Existing state for the story and the user asks to continue | Resume the recorded path |

`IMPLEMENT` and `ITERATE` are distinct lifecycles sharing one sealed `ApprovedScope`. `ITERATE`
never restarts intake and never re-derives scope.

## Step 3 — Initialise or resume state

```powershell
& "$stateSkill/Initialize-EiWorkflowState.ps1" -StoryId '<story-id>' -WorkflowPath IMPLEMENT -StoryRef '<url>' -WorkspaceRoot '<repo>' -Json
```

State lives in `<repo>/.copilottracking/ei-graphics/<story-id>/` and is owned by `ei-workflow-state`.
The root parameter here is `-WorkspaceRoot` (alias `-RepositoryRoot`) and defaults to the current
directory. `Details.Resumed = true` means an interrupted run continues from `Details.Stage`;
re-running a completed stage is not allowed. Requesting the other path against an active run returns
`EIWF-PATH-MISMATCH`.

## Step 4 — Run stages in the recorded order

The ordered stage list is data, not prose: `references/lifecycle-implement.json` and
`references/lifecycle-iterate.json`. `Initialize-EiWorkflowState.ps1` materialises those stages into
`workflow-state.json`, so the state file is the authoritative run plan.

### IMPLEMENT

```text
preflight -> state-init -> ado-intake -> domain-context -> scope-candidate -> proposed-scope
-> scope-analysis -> scope-approval (HUMAN) -> specification -> plan -> tasks -> implementation
-> targeted-tests -> regression-tests -> scope-validation -> invariant-validation
-> code-review -> audit -> commit -> pr
```

### ITERATE

```text
preflight -> state-recovery -> scope-recovery -> iteration-recovery -> diagnosis -> correction
-> targeted-tests -> regression-tests -> scope-validation -> invariant-validation
-> code-review -> audit -> commit -> pr-update
```

For every stage:

1. Mark the stage `running` with `Set-EiWorkflowStage.ps1 -Action start`.
2. Invoke the owning skill (or its documented scripts).
3. Write the stage result with `Write-EiWorkflowArtifact.ps1`.
4. Re-read it with `Read-EiWorkflowArtifact.ps1`. The next stage consumes the artifact, not the
   narrative.
5. Evaluate the stage gate.
6. Record the outcome with `Set-EiWorkflowStage.ps1 -Action complete -GateResult pass`, or
   `-Action block -BlockCode ... -BlockMessage ...`. Only a passing gate completes a stage, and
   `workflow-state.json` is never edited by hand.

### Every writing stage is untrusted

Any stage with `"writesFiles": true` in the lifecycle definition — including `specification`,
`plan`, `tasks`, and `implementation` — must be followed by an independent scope validation before
the next stage starts. SpecKit writers have been observed creating files outside the requested task
scope, so prompt instructions are not the safety boundary; the validator is.

### Stage: `scope-candidate`

`ei-scope-resolver` owns this stage. It generates `candidate.json` — the evidence document that
seeds the scope resolver. The script does not manage stage transitions; the workflow marks the
stage started and complete around the call.

```powershell
& "$eiSkills/ei-scope-resolver/scripts/New-EiScopeCandidate.ps1" `
    -AdoPath           '<state-dir>/ado.json' `
    -DomainContextPath '<state-dir>/domain-context.json' `
    -RepositoryRoot    '<repo>' -StateDir '<state-dir>' -Json

& "$workflow/Validate-EiWorkflowPrerequisites.ps1" -RepositoryRoot '<repo>' -Phase B `
    -StateDir '<state-dir>' -NoDefaultSearchRoots -Json
```

After the script exits 0, call:
- `Set-EiWorkflowStage.ps1 -Action start -StageId scope-candidate`
- `Set-EiWorkflowStage.ps1 -Action complete -GateResult pass -StageId scope-candidate`

**After generation, the model MUST review `candidate.json`** before running `New-EiProposedScope.ps1`.
Adjust evidence entries, confidence, and proposedFiles as needed. The generated confidence is
deliberately conservative (0.5 at most) so the model cannot rubber-stamp the candidate.

If the prerequisite check with `-Phase B -StateDir` returns `EIWF-CANDIDATE-MISSING` or
`EIWF-CANDIDATE-INVALID`, re-run `New-EiScopeCandidate.ps1` or correct the candidate manually.

| Gate outcome | Action |
|---|---|
| `Valid` and candidate.json present | Complete the stage |
| `EISC-*` error | BLOCK; check inputs and re-run |
| `EIWF-CANDIDATE-MISSING` or `EIWF-CANDIDATE-INVALID` from prerequisites | BLOCK; regenerate or fix the candidate before continuing |

### Stage: `proposed-scope`

`ei-scope-resolver` owns this stage. It writes the `proposed-scope` artifact itself, so this
lifecycle does **not** call `Write-EiWorkflowArtifact.ps1` separately for it.

```powershell
& "$eiSkills/ei-scope-resolver/scripts/New-EiProposedScope.ps1" `
    -StoryInputPath '<story.json>' -CandidatePath '<state-dir>/candidate.json' `
    -DomainContextPath '<domain-context.json>' -RepositoryRoot '<repo>' -StateDir '<state-dir>' -Json

& "$eiSkills/ei-scope-resolver/scripts/Test-EiProposedScope.ps1" -StateDir '<state-dir>' -Json
```

| Gate outcome | Action |
|---|---|
| `Valid` | Complete the stage with `-GateResult pass` |
| `EISR-SCOPE-NOT-RESOLVED` | BLOCK; a human answers the recorded findings and the resolver re-runs |
| Any other `EISR-*` | BLOCK; the artifact is untrustworthy |

### Stage: `scope-analysis`

`ei-scope-validator` owns this stage. It decides whether the scope is narrow and provable enough to
be worth a human decision, and it writes the evidence the approver is later shown.

```powershell
& "$eiSkills/ei-scope-validator/scripts/Invoke-EiScopeAnalysis.ps1" -StateDir '<state-dir>' -Json
```

Every threshold lives in `ei-scope-validator/references/approval-policy.json`, which defers the hard
size limits to the resolver's `scope-policy.json`. Nothing here is judged by the model: the script
reads the `proposed-scope` artifact, records findings against that policy, and writes a
`scope-analysis` evidence file under `<state-dir>/validation/` carrying the verdict, the summary, the
presented paths, the findings, and the canonical `contentHash` of the scope that was analysed.

| Gate outcome | Action |
|---|---|
| `Valid`, verdict `pass` | Complete the stage with `-GateResult pass`; advisory findings return as warnings for the approver to read |
| `EISV-SCOPE-NOT-APPROVABLE` | BLOCK; the blocking findings (`EISV-SCOPE-NOT-RESOLVED`, `EISV-AREA-SPREAD`, `EISV-FILE-CONFIDENCE-LOW`, `EISV-SYMBOLS-MISSING`, `EISV-TEST-COVERAGE-GAP`, `EISV-RISK-HIGH`) must be answered and the resolver re-run |
| `EISV-ARTIFACT-UNREADABLE`, `EISV-SCOPE-UNHASHABLE`, `EISV-POLICY-MISSING`, `EISV-EVIDENCE-WRITE` | BLOCK; the analysis could not be grounded, so no approval may be requested |

The analysis is read-only with respect to the scope. It never edits, widens, or downgrades a
finding, and it never analyses a scope the resolver did not mark `resolved` into readiness.

**Boundary against `Test-EiProposedScope.ps1`.** The two gates answer different questions and
neither substitutes for the other.

| | `Test-EiProposedScope.ps1` (`ei-scope-resolver`) | `Invoke-EiScopeAnalysis.ps1` (`ei-scope-validator`) |
|---|---|---|
| Question | Is the artifact internally consistent and within the hard limits? | Is the scope it describes defensible enough for a human to approve? |
| Codes | `EISR-*` | `EISV-*` |
| Output | A validation result only | Persisted `scope-analysis` evidence, including the analysed `contentHash` |

Run the resolver gate first. A scope that passes `Test-EiProposedScope.ps1` can still fail
`scope-analysis`: a well-formed artifact may still be too broad, too thinly evidenced, or untestable.

### Stage: `scope-approval`

This skill owns the orchestration around the `human-approval` gate. It does not make the decision
and it cannot manufacture one. `Resolve-EiScopeApproval.ps1` is the only supported entry point, and
it delegates hashing, sealing, and versioning to `New-EiApprovedScope.ps1` rather than
reimplementing them.

```powershell
& "$workflow/Resolve-EiScopeApproval.ps1" -StateDir '<state-dir>' -Decision request -Json

& "$workflow/Resolve-EiScopeApproval.ps1" -StateDir '<state-dir>' -Decision approve `
    -DecidedBy '<who approved>' -Note '<why>' -Json

& "$workflow/Resolve-EiScopeApproval.ps1" -StateDir '<state-dir>' -Decision reject `
    -DecidedBy '<who rejected>' -Note '<why>' -Json
```

`request` presents the analysed scope and pauses the run. `approve` requires an approver identity
and seals the scope. `reject` requires both a decider and a reason, because an unexplained refusal
cannot be answered.

The stage transitions travel with the decision, so this stage is **not** completed separately by the
caller. `request` starts the stage before pausing, because a pause taken on a stage that was never
started can never be completed. A successful `approve` completes the stage with `-GateResult pass`
against the version it just sealed, and `reject` blocks it. Every transition still goes through
`Set-EiWorkflowStage.ps1` and `Set-EiWorkflowApproval.ps1`, so `workflow-state.json` is never
hand-edited.

> Because the stage is started through the normal ordering rules, `request` returns
> `EIWF-APPROVAL-NOT-REQUESTED` while any earlier lifecycle stage is still pending, so `ado-intake`,
> `domain-context`, `proposed-scope` and `scope-analysis` must all have completed first.

#### The five states

| State | Reached by | Meaning |
|---|---|---|
| resolved | `proposed-scope` passed the resolver gate | There is an artifact to analyse; nothing has been shown to a human |
| requires review | `scope-analysis` returned verdict `block` | `EIWF-APPROVAL-NOT-READY`; the approver is not asked until the blocking findings are answered |
| awaiting approval | `-Decision request` succeeded | `status: awaiting-approval`. A real pause: `Set-EiWorkflowStage.ps1` refuses to start any stage while it is set |
| approved-sealed | `-Decision approve` succeeded | `approved-scope.v{n}.json` is written, the seal is recorded, the stage completes with `gateResult: pass`, and the run returns to `in-progress` |
| rejected-blocked | `-Decision reject` succeeded | The stage is blocked with `EIWF-SCOPE-REJECTED` and the recorded reason; re-resolve, re-run `scope-analysis`, request again |

The pause is entered and left only through `Set-EiWorkflowApproval.ps1 -Action request|grant`, so
`workflow-state.json` is still never hand-edited. Granting the pause records that a decision was
taken; it is not the decision. The decision itself lives in the sealed `ApprovedScope` for an
approval, or in the block record for a refusal.

A decision may not be taken out of order. `approve` and `reject` both require status
`awaiting-approval` and otherwise return `EIWF-APPROVAL-NOT-REQUESTED`, so what the approver was
shown is always on record. An approval without `-DecidedBy` returns `EIWF-APPROVER-MISSING`: an
unattributed approval is not an approval.

#### Staleness — an approval is bound to the scope that was analysed

Before sealing, `approve` recomputes the canonical hash of the current `proposed-scope` and compares
it with the `contentHash` recorded in the `scope-analysis` evidence. If the proposal changed after
the human was asked, the approval is stale and **nothing is sealed**:

> `EIWF-APPROVAL-STALE` — the approver was shown `sha256:<a>` but the scope now hashes to
> `sha256:<b>`. Re-run `scope-analysis` and ask again.

This is what stops a scope being widened between the moment a human agrees and the moment the seal
is taken. Analysis evidence is kept per stage precisely so a later validating stage cannot overwrite
what the approver saw.

`New-EiApprovedScope.ps1` reads `proposed-scope`, refuses `needs-review` and `blocked`, requires an
approver identity, and copies the scope **verbatim** into `approved-scope.v{n}.json`. It never
reconstructs, re-derives, or broadens a scope. Approving again seals a new version; earlier versions
are never rewritten, so the approval chain stays auditable.

The seal is recorded in `workflow-state.json` (`approvedScopeHash`, `approvedScopeVersion`) only
after the artifact has been written **and** has passed `Test-EiApprovedScopeHash.ps1` against the
persisted file. A refused approval leaves both seal fields untouched.

```powershell
& "$workflow/Test-EiApprovedScopeHash.ps1" -StateDir '<state-dir>' -Json
```

If sealing fails, the run stays paused for approval (`EIWF-SCOPE-SEAL-FAILED`) instead of advancing,
and the stage is left open rather than completed. If the seal succeeds but the pause cannot be
lifted, or the stage cannot be completed afterwards, `EIWF-APPROVAL-NOT-RECORDED` reports both
facts: the version that was sealed, and what did not get recorded.

The stage is completed against `Details.Version` from the seal, not against version 1, so a later
approval is validated against the `approved-scope.v{n}.json` it actually produced.

#### The hash contract

`contentHash` is `sha256:<64 lowercase hex>` over the UTF-8 bytes of the `ei-scope-canonical-v1`
serialisation of the embedded scope.

| Canonicalisation rule | Effect |
|---|---|
| Object keys sorted ordinal, no whitespace between tokens | Property order and formatting cannot change the hash |
| Every array sorted by the ordinal value of its canonical elements | Arrays in a scope are sets, so list order cannot change the hash |
| Numbers written in invariant round-trip form, integers without a decimal point | `1` and `1.0` are the same number |
| Strings escaped to JSON, with whitespace inside a string preserved | A renamed path is a different path |
| `generatedAt` removed before hashing | Regenerating an unchanged scope does not invalidate a seal |

Everything else the resolver produced — every proposed path, change intent, symbol, module, test,
protected area, dependency, evidence entry, exclusion, risk, confidence and the rationale — is
inside the hash. Adding, removing, or renaming a proposed path changes it, and so does editing the
justification behind it.

`Test-EiApprovedScopeHash.ps1` is read-only. It recomputes the hash from the persisted artifact,
compares it with the stored `contentHash`, and, when state records the same version, requires
`approvedScopeHash` to agree. It never repairs or re-seals.

### Stage: `scope-validation`

`ei-scope-validator` owns this gate. Writer stages are untrusted, so what a stage actually changed
is compared with what the seal authorised, path by path. It runs after **every** stage carrying the
`scope-validation` gate — not only at the dedicated `scope-validation` stage — which is why `-Stage`
is mandatory: evidence is written per stage so one writer cannot overwrite another's result.

```powershell
& "$eiSkills/ei-scope-validator/scripts/Test-EiScopeDrift.ps1" -StateDir '<state-dir>' `
    -Stage '<stage-id>' -RepositoryRoot '<repo>' -Json

& "$eiSkills/ei-scope-validator/scripts/Test-EiScopeDrift.ps1" -StateDir '<state-dir>' `
    -Stage '<stage-id>' -ChangedPath 'src/a.cs','src/b.cs' -Json
```

**The seal is verified first.** Before any comparison, the script resolves the sealed version
(latest unless `-Version` is given) and runs `Test-EiApprovedScopeHash.ps1` against it. A drift check
against an edited `ApprovedScope` would prove nothing, so an unverified seal is
`EISV-SEAL-UNVERIFIED` and no comparison happens. No seal at all is `EISV-SEAL-MISSING`: nothing
authorises the writes.

Changed files come from `-ChangedPath`, or are discovered from `-RepositoryRoot` via
`git status --porcelain --untracked-files=all`, where a rename resolves to its destination because
only the destination was written.

Each changed path is classified in this order:

| Classification | Meaning | Effect |
|---|---|---|
| `protected` | Inside a `protectedAreas` entry of the sealed scope | `EISV-DRIFT-PROTECTED`, blocking — checked first, so a protected path is never rescued by also being named in scope |
| `in-scope` | Named exactly by a `proposedFiles` path | Authorised |
| `allowed` | Matches `drift.allowedPathPrefixes` in `approval-policy.json` (`.copilottracking`) | Workflow bookkeeping, not implementation output |
| `out-of-scope` | Everything else | `EISV-DRIFT-OUT-OF-SCOPE`, blocking |

A changed file is in scope only when the sealed scope **names** it. Nothing is inferred from
proximity, directory, or intent.

**An empty change set is an input error, not a pass.** If neither `-ChangedPath` nor
`-RepositoryRoot` yields a path, the script returns `EISV-INPUT-INVALID` — a stage that reports no
changed files at all is not evidence that nothing changed. This is the fail-closed rule applied to
its own inputs.

The gate never widens a scope and never edits the seal. Out-of-scope drift is answered by a
scope-change request and a new sealed version, not by relaxing this check.

## Gates

| Gate | Owner | Blocks when |
|---|---|---|
| `prerequisites` | this skill | Tooling or a required plugin is missing |
| `state-integrity` | `ei-workflow-state` | State is missing, corrupt, out of order, or over the retry ceiling |
| `artifact-present` | `ei-workflow-state` | The stage artifact is missing or schema-invalid |
| `domain-pack-selection` | `ei-vocabulary-navigator` + domain pack | No pack, ambiguous packs, or a pack changed after approval |
| `scope-analysis` | `ei-scope-validator` | Proposed scope is unresolvable or too broad to defend |
| `human-approval` | human | Scope is not explicitly approved |
| `scope-hash` | this skill | The recomputed `ApprovedScope` hash differs from the sealed one |
| `scope-validation` | `ei-scope-validator` | Unexplained, protected-area, or out-of-scope paths changed |
| `test-evidence` | this skill | Targeted or regression evidence is missing or failing |
| `invariant-validation` | `ei-layer-guard` + domain pack | A machine-checkable domain invariant fails |
| `ci-evidence` | this skill | CI cannot supply the required evidence |

## Fail-closed states

Missing required artifact, failed test, failed scope validation, scope hash mismatch, missing
required dependency, missing CI evidence, missing required tooling, protected-area modification,
unexplained changed path, invalid domain-pack selection, or repeated correction failure are all
BLOCK. Record the block in `workflow-state.blocks`, set `status: blocked`, return the contract, and
stop. Never interpret absent evidence as a pass.

## Retry policy

At most **3** correction attempts. Each attempt runs fix → tests → scope validation → invariant
validation and increments `correctionAttempts`. Halt and escalate to a human when the ceiling is
reached, when the diff grows unexpectedly, when scope expands, when validation keeps failing, or
when required evidence is unavailable.

## Scope may never expand silently

An unexpected file or dependency does not authorise a change. The seal is never edited to fit what
implementation turned out to need; a request is recorded and a human answers it.

```powershell
& "$eiSkills/ei-scope-validator/scripts/New-EiScopeChangeRequest.ps1" -StateDir '<state-dir>' `
    -RequestedBy '<who needs it>' -Reason '<why the sealed scope is insufficient>' `
    -Path 'src/needed.cs' -ChangeIntent modify -DetectedBy scope-validation -Json
```

The script verifies the seal first (`EISV-SEAL-UNVERIFIED`, `EISV-SEAL-MISSING`), then records what
was needed, who needed it, and which sealed version and `contentHash` it was raised against — and
then stops. The request is an input to a human decision, never a decision.

| Refusal | Why |
|---|---|
| `EISV-CHANGE-REQUESTER-MISSING` | An unattributed request cannot be answered |
| `EISV-CHANGE-INPUT` | No reason, or no `-Path`; a request that names no file authorises nothing |
| `EISV-CHANGE-PROTECTED` | A protected area is never widened by request — take it up with the people who declared it |
| `EISV-CHANGE-REDUNDANT` | Every requested path is already authorised, so there is no change to approve |

Paths already inside the sealed scope are dropped from the request and reported as a warning rather
than failing it.

**Append-only re-approval.** Requests are versioned (`scope-change-request.v{n}.json`, each
recording `supersedes`), and answering one means re-resolving the scope, re-running
`scope-analysis`, and sealing a **new** `ApprovedScope` version with a new hash. Earlier sealed
versions and earlier requests are never rewritten, so the chain from first proposal to final seal
stays auditable. Writing the request always warns that the current `ApprovedScope` is unchanged.

**Requests are raised out of band.** No lifecycle declares a `scope-change` stage: neither
`lifecycle-implement.json` nor `lifecycle-iterate.json` contains one. So the run does not transition
into a request — it BLOCKs on the `scope-validation` gate, the request is recorded against the
blocked state, and the run resumes only once a new version is sealed. This applies identically to
`ITERATE`.

## Cross-plugin reuse

Never reimplement these inside EI:

| Capability | Skill |
|---|---|
| Code review | `/aveva-rnd:code-review` |
| Review results | `/aveva-rnd:get-reviewresults` |
| Bug diagnosis (ITERATE) | `/aveva-rnd:bug-diagnosis` |
| Commit | `/aveva-rnd:git-commit` |
| Pull request | `/aveva-rnd:create-pr` |
| Spec / plan / tasks / implement | R&D SpecKit workers |
| Audit trail | `/aveva-core:create-audit` |

Their outputs are stored as workflow artifacts (`code-review.json`, `audit.json`, `pr.json`).

## Step 5 — Return the result contract

```powershell
& "$workflow/New-EiWorkflowResult.ps1" -StateDir '<state-dir>' -Status blocked `
    -Summary '<one-line outcome>' -NextAction '<what the human must do next>' -Json
```

The contract is validated against `workflow-result.schema.json` and persisted as
`workflow-result.json`:

```json
{
  "schemaVersion": "1.0.0",
  "workflow": "ei-graphics-workflow",
  "path": "IMPLEMENT",
  "storyId": "123456",
  "status": "completed | awaiting-approval | blocked | failed",
  "stage": "scope-approval",
  "stateDir": ".copilottracking/ei-graphics/123456",
  "summary": "...",
  "artifacts": [{ "name": "ado", "path": "...", "exists": true }],
  "gates": [{ "id": "human-approval", "stage": "scope-approval", "result": "not-run", "detail": null }],
  "blocks": [{ "code": "...", "stage": "...", "message": "...", "remediation": "...", "raisedAt": "..." }],
  "nextAction": "..."
}
```

A run may not return while its state is `in-progress`; the terminal status must be explicit.

## Out of scope for the MVP

Broad RAG, automatic vocabulary mining, multiple domain packs, multiple repositories, unbounded
autonomous repair.

## Implementation status

| Phase | Scope | Status |
|---|---|---|
| A | Thin agent, this skill, result contract, story state directory, state schemas, stage transitions | Implemented |
| B | `ei-scope-resolver`, `ei-scope-validator`, ProposedScope, ApprovedScope, approval checkpoint, hashing, scope-change request | Implemented |
| C | The two context stages ahead of the scope layer: `ado-intake` and `domain-context`, with the `ado` and `domain-context` artifacts and the `domain-pack-selection` gate | Implemented |
| D | The IMPLEMENT writing and evidence stages — `specification`, `plan`, `tasks`, `implementation`, `targeted-tests`, `regression-tests`, `invariant-validation`, `code-review`, `audit`, `commit`, `pr` — with validation after every writing stage | Not implemented |
| E | The ITERATE stages — `iteration-recovery`, `diagnosis`, `correction`, tests, review, audit, and `commit` / `pr-update` on the same branch and PR | Not implemented |

`implementedInPhase` in `references/lifecycle-implement.json` and `references/lifecycle-iterate.json`
is the source of truth for this table; the rows above only summarise it. Stages whose phase has not
landed are BLOCK states, not skips. Report the blocked stage and stop.

Phases A to C are complete. A wired IMPLEMENT run executes
`preflight -> state-init -> ado-intake -> domain-context -> proposed-scope -> scope-analysis ->
scope-approval` on the real `lifecycle-implement.json` and reaches a sealed `approved-scope.v1.json`.
It stops at the first Phase D stage, which is a BLOCK and never a skip.
