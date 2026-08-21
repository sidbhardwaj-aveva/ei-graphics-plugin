# EI Graphics Phase 1 — Risk and Gap Review

Date: 2026-08-11
Input: ei-graphics-phase1-architecture.md
Scope: Review only. No production files modified. No agents, skills, SpecKit, or extensions.yml changed.

---

## 1. Executive summary

Phase 1 is directionally sound. The lifecycle decomposition, the ApprovedScope contract, the domain pack split, and the deterministic-gate philosophy are all consistent with patterns that already exist and work in this repository.

Three findings from this review materially change the risk picture:

**Finding A — The SpecKit chain is wired for human handoff, not automatic chaining.**
`speckit.specify`, `speckit.clarify`, `speckit.plan`, `speckit.tasks`, `speckit.constitution`, and `speckit.workflow` all declare `handoffs:` frontmatter. Only `ai-ready-workflow` declares `agents:` and uses `runSubagent`. No file in the repository invokes any `speckit.*` agent via `runSubagent`. There is also explicit counter-evidence: the bug-diagnosis skill instructs *"Do NOT invoke the bug fix workflow via `runSubagent`... The user switches to AVEVA's Implementation Workflow themselves."* Phase 1's automation assumption rests on a path nobody in this repository has taken, and one case where it was deliberately rejected.

**Finding B — The proven state-propagation mechanism is files on disk, not agent return values.**
Every working multi-stage workflow writes JSON under `.copilottracking/<stage>/` and the next stage re-reads that file. The AI-Ready orchestrator states this explicitly: *"The AGENTS generator reads `phase-1-discovery.json` directly... No additional data-passing is required."* Subagent return values are used only as coarse status signals, and the create-backlog orchestrator adds a **Verify** step that re-reads the validation file after a subagent returns rather than trusting its narrative. Meanwhile, no script in ei-graphics writes anything to disk — `prEvidencePackage` exists only in memory. ApprovedScope as currently described has no durable substrate.

**Finding C — `speckit.implement` will make out-of-scope changes by design.**
Step 4 of that agent creates or modifies ignore files (`.gitignore`, `.dockerignore`, `.eslintignore`, `.prettierignore`, and others) on every run. Step 7 instructs *"Setup first: Initialize project structure, dependencies, configuration"* and *"Polish and validation: ... performance optimization, documentation."* Its only human gate is a checklist prompt the user can clear by answering "yes". A domain skill will not make this agent safe. Enforcement must be external and deterministic.

None of these invalidate the architecture. All three mean Phase 2 must be a proof exercise, not a build exercise, and the proof order should change: the cheapest, most decisive spike is whether the SpecKit chain can be driven programmatically at all.

**Recommendation: proceed to Phase 2 spikes with a revised order and a go/no-go gate after the first spike. Do not begin implementation.**

---

## 2. Confirmed architectural strengths

These are supported by direct repository evidence and need no further proof.

| Strength | Evidence |
|---|---|
| Deterministic script gating works and is idiomatic here | `Invoke-EiPrReviewer.ps1` blocks via exit code; `-Json` contracts across EI and R&D scripts |
| Artifact-backed handoff between stages is a proven pattern | `.copilottracking/` JSON files consumed across ai-ready, code-review, create-backlog workflows |
| Orchestrator-with-subagents is proven | `ai-ready-workflow` runs 5 subagents across 3 waves with batching, resume, and a 3-retry cap |
| Distrust-the-child verification is an established pattern | create-backlog orchestrator re-reads `validation-result.json` after each subagent returns |
| Hook insertion points exist at every lifecycle stage | 18 hook points; `EXECUTE_COMMAND` handling present in 9 SpecKit agents |
| Retry ceilings and HALT semantics have precedent | ai-ready-workflow: *"Maximum 3 correction retries... If still failing after retries, HALT"* |
| Thin-agent / fat-skill domain packaging is validated | The sample Termination Drawing agent plus its skill demonstrates the shape end to end |
| Domain-risk escalation to a human already exists | R-005 / R-006 in the PR reviewer force SME review on domain-risk paths |

---

## 3. Unresolved architectural risks

### 3.1 Orchestration (Risk 1) — **Partially confirmed**

Answering the specific questions:

| Question | Status | Evidence |
|---|---|---|
| Can one agent invoke another? | Confirmed | `agents:` frontmatter + `runSubagent` in ai-ready-workflow; inline delegation in the bugdiagnosis alias |
| Can agents execute sequentially? | Confirmed | Three ordered waves with explicit wait-for-all barriers |
| Can the parent continue after a child completes? | Confirmed | Orchestrator resumes, evaluates gates, dispatches next wave |
| Can structured output be returned stage to stage? | **Partially — via files, not via return values** | See 3.2 |
| Can deterministic scripts run between agents? | Confirmed | Orchestrator runs PowerShell between waves; hooks emit `EXECUTE_COMMAND` |
| Can the workflow continue without manual handoffs? | **Unverified for the SpecKit chain** | SpecKit stages use `handoffs:` with `send: true`, a user-facing affordance |

What is actually supported: purpose-built subagents listed in an orchestrator's `agents:` array, driven by `runSubagent`, coordinated through files.

What is an assumption: that `speckit.specify → plan → tasks → implement` can be driven the same way. Those agents are declared `user-invocable: false` and wired with `handoffs:`. They are exposed as subagents, but no repository evidence shows them being invoked that way, and the bug-diagnosis skill explicitly routes around doing so.

The chained requirement in the review brief — Agent A → structured state → Agent B → structured state → Agent C → parent continues — is **confirmed for the ai-ready pattern** and **unverified for the SpecKit lifecycle**. Phase 1 depends on the latter.

### 3.2 Structured state propagation (Risk 2) — **Confirmed via artifacts, unsupported in-band**

The mechanism question has a clear answer in this repository: state survives transitions **only when it is written to a file and re-read**. It does not survive as narrative context.

Supporting evidence:
- AI-Ready explicitly avoids data-passing: the downstream generator reads the Phase 1 discovery JSON directly.
- Subagent returns are consumed as `success` / `fail` status only.
- The create-backlog orchestrator treats a subagent's own report as insufficient and re-reads the validation artifact before proceeding.

Implication for Phase 1: ApprovedScope, analysis state, domain context, and PR evidence must each be a file with a schema, and every consumer must re-read it. If ApprovedScope is summarised into a prompt, it is no longer a contract — it becomes mutable context, which is exactly Risk 3.

Gap: ei-graphics currently writes nothing to disk. A repository-wide search for `Set-Content`, `Out-File`, or `.copilottracking` across the plugin returns no persistence in any script. The architecture's entire state model has no substrate today.

### 3.3 ApprovedScope immutability (Risk 3) — **Gap**

Phase 1 §10 defines the object and §16 defines the wiring, but does not define its lifecycle. Specifically absent:

- No version identity. `ApprovedScope v1 → v2` is not modelled.
- No seal. Nothing prevents a downstream stage from producing a modified copy and the validator comparing the diff against the *modified* copy — which would make validation vacuous.
- No distinction between **Approved Scope**, **Discovered Dependency**, and **Proposed Scope Expansion**. Phase 1 has one concept where it needs three.
- No scope-change-request path. The brief's flow (out-of-scope dependency → change request → human approval → v2) has no counterpart in the architecture.

Required correction: ApprovedScope must be content-hashed at approval time. The hash is recorded in the approval block. The diff validator recomputes the hash before validating and refuses to run if it does not match. Scope expansion is a separate artifact requiring a new approval and producing v2 — never an in-place edit.

### 3.4 Diff validation strength (Risk 4) — **Too weak as specified**

Phase 1 §17.1 says "compare approved expected files/symbol scope vs actual git diff". The only existing implementation of that idea filters `git diff --name-only` to `.cs|.csproj|.xaml|.json`. Consequences:

| Change class | Detected by current approach? | Note |
|---|---|---|
| Modified file, matching extension | Yes | |
| New file, matching extension | Yes | |
| Deleted file | No | `--name-only` does not distinguish; deletions need `--name-status` |
| Renamed file | No | Appears as unrelated add + delete without `-M` |
| File with a non-listed extension | **No** | Filter silently drops it |
| Ignore files created by the implement agent | **No** | `.gitignore` and similar are excluded by the filter |
| Generated / build output | Partially | Depends on ignore rules, not on the validator |
| Formatter-induced churn | No | Indistinguishable from intentional edits at file level |
| Symbol-level change inside an in-scope file | No | File-level check passes regardless of what changed |
| Test file changes | Yes, but unclassified | Cannot tell "added expected test" from "weakened failing test" |

Architectural requirement (not implementation): the validator needs **both** levels, applied asymmetrically for cost control.

- **File-level, universally**: `--name-status` with rename detection, no extension filtering, every path classified as in-scope / out-of-scope / known-benign.
- **Symbol-level, selectively**: only for files flagged as domain-risk or protected in ApprovedScope. Universal symbol-level analysis is not affordable and not necessary.
- **Classification, not just detection**: an out-of-scope path must be labelled (generated, formatter, dependency, unexplained). Only "unexplained" should block outright; the others should escalate with evidence.

Weakening a test to make it pass deserves explicit treatment. It is the most likely silent failure in an autonomous fix loop and file-level scope checking cannot see it.

### 3.5 Domain pack / lifecycle boundary (Risk 5) — **Mostly clean, three ambiguities**

The separation is technically sound. Knowledge, vocabulary, invariants, and tests are inert data; orchestration and safety are behaviour. That split holds.

Three responsibilities remain ambiguous:

1. **Domain knowledge influencing planning.** "LOC-0 must process first" is a design constraint, not merely a post-hoc check. Phase 1 wires packs into scope resolution (§16) and diff validation (§17.4), but not into Plan or Tasks. A pack that can only judge after the fact will produce late failures where early guidance was possible. Requirement: define a read-only pack→plan context injection point.

2. **Who executes an invariant.** The pack declares the rule; something must run it. If each pack ships its own validator script, safety logic fragments across packs and the path-neutrality and exit-code conventions will drift. Requirement: packs declare rules as data; ei-graphics owns the single execution engine.

3. **Domain code navigation.** The symptom→cause table is domain knowledge, but its consumer is the scope resolver, a lifecycle component. Requirement: an explicit, read-only interface — the resolver queries the pack; the pack never calls the resolver.

Responsibility assignment, as it should read:

| Concern | Owner |
|---|---|
| Terms, relationships, invariants, bug patterns, test commands | Domain pack |
| Pack selection, scope resolution, approval, orchestration | ei-graphics |
| Spec / plan / tasks / implement execution | R&D SpecKit agents |
| Reusable deterministic capability | Skill |
| Rule execution and blocking | ei-graphics validator engine |

### 3.6 Domain pack selection (Risk 6) — **Gap, unproven**

Phase 1 §16 states the resolver "matches story text against vocabulary map and domain pack manifests". That is LLM matching over a five-term vocabulary. Undefined:

- Is selection deterministic or inferred? Currently implicitly inferred.
- Can multiple packs apply? `domainPacks[]` is plural but no merge or conflict rule exists.
- What if none applies? Undefined — the dangerous default is silent generic behaviour with full write tooling.
- What if the wrong pack is selected? No detection, no cost model. A wrong pack supplies wrong invariants, which is worse than none.
- Can selection change after scope analysis? Undefined, and it interacts badly with an immutable ApprovedScope.
- Does the human approve the selection? `domainPacks[]` sits inside ApprovedScope, so approval implicitly covers it — but Phase 1 never states that the selection is *shown* at the checkpoint.

Required corrections: selection must be explicitly surfaced in the approval prompt; no-pack must be an explicit BLOCK or a declared degraded mode with reduced automation; pack changes after approval must invalidate the scope and require re-approval.

### 3.7 Vocabulary versus domain knowledge (Risk 7) — **Partially addressed**

Phase 1 §14 now records the measured gap and §13 introduces packs, so the conflation is acknowledged. It is not yet resolved structurally: the architecture still has only two tiers — a term map and prose in a `SKILL.md`.

Prose is neither selectable nor checkable. The knowledge model needs explicit layers:

| Layer | Purpose | Machine-usable? |
|---|---|---|
| Terms | Map domain word to code identifier | Yes — drives retrieval |
| Relationships | How concepts connect | Partially — drives scope expansion reasoning |
| Workflows / pipelines | Execution order and phases | Reasoning only |
| Invariants | What must never break | Yes — drives blocking checks |
| Implementation patterns | Idiomatic approach | Reasoning only |
| Historical bug patterns | Known failure modes | Partially — drives diagnosis hints |

Phase 1 collapses layers 2 through 6 into "the pack". Only layers 1 and 4 currently have a path to becoming deterministic. The architecture should say so rather than implying the whole pack is enforceable.

### 3.8 Generic implementation agent safety (Risk 8) — **High risk, concrete evidence**

`speckit.implement` is a general-purpose executor with no scope concept. Directly evidenced behaviours that conflict with ApprovedScope:

- Creates or modifies ignore files for every detected technology — unconditional out-of-scope writes.
- "Setup first: Initialize project structure, dependencies, configuration."
- "Polish and validation: Unit tests, performance optimization, documentation."
- Sole human gate is a checklist prompt cleared by answering "yes".
- Halts on task failure, not on repeated test failure.

Requirement classification:

| Requirement | Class | Sufficient alone? |
|---|---|---|
| Domain pack summary in stage context | Prompt/context | No |
| ApprovedScope file path and minimal-change directive | Prompt/context | No |
| `before_implement` hook: re-read and seal-check ApprovedScope | Extension hook | No |
| `after_implement` hook: run diff validation | Extension hook | No — see below |
| Post-hoc diff vs sealed scope, run by the wrapper | Deterministic validation | **Yes — this is the load-bearing control** |
| Invariant checks on changed hunks | Deterministic validation | Complements the above |
| Ignore-file writes classified as known-benign | Deterministic validation | Prevents false positives |
| Forking `speckit.implement` | Agent specialization | Not required for MVP if the above hold |

One caveat that Phase 1 does not state: hooks live in the *target repository's* `.specify/extensions.yml`, which is an editable file in the workspace being modified. Safety that depends only on a hook can be disabled by editing a YAML file — potentially by the very agent under supervision. The wrapper must therefore run its own validation outside the hook mechanism. Hooks are for convenience and early feedback; the wrapper's own gate is the control.

### 3.9 Autonomous fix loop (Risk 9) — **Gap**

Phase 1 §7 step 15 reads "Bug-fix loop (if failures)" with no bound of any kind. The underlying agent only halts on task failure. Nothing in the architecture prevents an indefinite modify-test-modify cycle, and nothing re-checks scope *during* the loop — validation is described as a final gate only, so drift accumulates unobserved until the end.

Required: a maximum attempt count with an established precedent to follow (3 corrections then HALT); scope re-validation after **every** attempt rather than only at the end; a no-new-files rule inside the loop unless the file is already in ApprovedScope; divergence detection (blocking if diff size grows across consecutive attempts); and mandatory escalation with accumulated evidence on exhaustion.

### 3.10 ITERATE state recovery (Risk 10) — **Gap**

Recoverability assessment:

| Item | Recoverable | Source |
|---|---|---|
| Original story | Yes | ADO work item via branch or PR link |
| Current diff, commits, branch | Yes | Git |
| Test and CI results | Yes | CI system |
| Review comments | Yes | PR threads |
| **ApprovedScope** | **No** | Nothing persists it |
| **Domain pack selection** | **No** | Part of ApprovedScope |
| **Original implementation intent** | **Partial** | Inferable from spec/plan if `.specify` artifacts were committed |
| **Per-iteration attribution** | **No** | No iteration marker on commits |

The blocking issue is that Phase 1 §11 lists three storage *options* and selects none — Open Question 1 is still open, and every ITERATE capability depends on its answer. This is the single highest-leverage unresolved decision in the document.

The four-way discrimination the brief asks for — original issue, new reviewer feedback, self-inflicted regression, unrelated feedback — additionally requires a baseline test result set captured at first PR creation and an iteration index recorded per commit. Phase 1 has neither. Without the baseline, a regression introduced by iteration N is indistinguishable from a pre-existing failure.

### 3.11 PR evidence package (Risk 11) — **Real risk, and Phase 1 currently trends toward it**

§11 proposes storing analysis state in the PR evidence package while §12 correctly says implementation state should be reconstructed from SCM/CI. That inconsistency is how evidence packages become serialized copies of everything.

The persistence rule should be: **persist only what cannot be reconstructed.**

| Persist directly | Reference only |
|---|---|
| ApprovedScope (sealed, hashed) | Diff content |
| Domain pack identifiers and versions | File contents |
| Gate results with the scope hash they were evaluated against | Commit messages |
| Iteration index and baseline test result set | CI logs |
| Approval metadata | ADO story body |

Add an explicit size ceiling and a rule that no source code content is embedded in the evidence package. Reference by commit SHA, PR identifier, work item identifier, and CI run identifier.

### 3.12 Git history reliability (Risk 12) — **Under-specified**

Phase 1 §19 carries one guardrail line: history informs, does not auto-apply. That is correct but insufficient, because the failure mode is subtle — historical code often looks more authoritative than it is.

Required validation before treating historical code as evidence: confirm the referenced code still exists at HEAD; check whether the commit was later reverted or superseded; check whether the pattern was changed by a subsequent refactor; prefer commits linked to closed work items over unlinked ones; and treat any pattern absent from current code as a signal it was *deliberately removed*, not as a template.

### 3.13 Deterministic invariants (Risk 13) — **Partially addressed, classification missing**

Phase 1 §17.4 lists seven seed invariants but does not say which are enforceable. Applying the brief's classification:

| Invariant | Class |
|---|---|
| `ConnectivityGroupKey` retained in dedup predicates | Statically checkable — grep on changed hunks |
| Mutable metadata uses update rather than write-once API | Statically checkable — API call pattern on changed hunks |
| Wire validation routes through the terminal-inserted check | AST-checkable — call graph over changed methods |
| Composite key format by LOC level | Test-checkable — behavioural |
| LOC-0 ordering | Test-checkable — behavioural |
| No duplicate insert for a key already inserted | Test-checkable — behavioural |
| Backward compatibility with legacy untagged shapes | **Reasoning-only** |

Two consequences the architecture must state: reasoning-only invariants can never be blocking gates and must surface as advisory findings for human review; and test-checkable invariants only provide coverage if the corresponding tests exist, so a pack must declare which tests enforce which invariant. A pack listing an invariant with no enforcing test or check is documentation, not safety.

### 3.14 Build/test versus domain correctness (Risk 14) — **Separated, but gate roles unstated**

Phase 1 §17.2 bundles build, targeted tests, regression, unexpected-file detection, protected-area checks, and refactor heuristics into a single "final validation gate", which obscures which failures block.

Required gate model:

| Gate | Proves | Blocking? |
|---|---|---|
| Compilation | Syntactic and type validity | Yes |
| Targeted tests | Intended behaviour changed as intended | Yes |
| Regression tests | Nothing adjacent broke | Yes |
| Scope validation | Only approved things changed | Yes |
| Statically checkable invariants | Named domain rules not violated | Yes |
| Reasoning-based invariants | Judgement about domain fit | No — advisory, escalate |
| Human code review | Everything the above cannot see | Yes for domain-risk paths |

The architecture should state plainly that green build plus green tests is necessary and not sufficient, and that domain-risk paths retain a mandatory human gate — which the existing R-005 and R-006 rules already implement.

### 3.15 Failure and escalation model (Risk 15) — **Significant gap**

Phase 1 inherits three status values from the existing script but defines no state machine. Each condition in the brief needs an assigned action:

| Condition | Action |
|---|---|
| Story ambiguous | Escalate — clarification before scope |
| Scope undeterminable | Block |
| Domain pack missing | Block, or declared degraded mode with reduced automation |
| Vocabulary ambiguous | Escalate — present candidates, request selection |
| Implementation needs an unexpected file | Block, then scope change request |
| Tests fail repeatedly | Retry to ceiling, then escalate |
| Invariant unverifiable | Continue with advisory finding, mandatory human review |
| Feedback conflicts with the story | Escalate — never silently reinterpret intent |
| CI unavailable | Block — do not treat absent evidence as passing |
| Required tooling unavailable | Block |

The governing principle Phase 1 should adopt: **fail closed**. Missing evidence is never equivalent to passing evidence. Two conditions in this table — unavailable CI and unavailable tooling — are exactly where an under-specified system defaults to "continue", and that is the most consequential silent failure available to it.

### 3.16 MVP scope (Risk 16) — **At risk of inflation**

The current MVP list contains thirteen items, two of which are open-ended ("2D domain context injection", "vocabulary-backed retrieval"). Those two can absorb unlimited effort.

Should be explicitly excluded and stated as such:

- Vocabulary mining automation — curate one pack by hand
- More than one domain pack
- Embedding or retrieval-augmented infrastructure
- Symbol-level validation for all files — domain-risk paths only
- Reasoning-based invariant enforcement
- Screenshot and attachment analysis
- Automatic PR creation — evidence package plus manual creation is sufficient
- Multi-repository or cross-solution scope
- Autonomous fix loops beyond the attempt ceiling

A defensible MVP: one domain, one story class (bug fix), file-level scope validation plus the two grep-checkable invariants, manual PR creation, and one ITERATE cycle on the same branch.

---

## 4. Technical gaps

Gaps in the architecture as written, independent of the risks above:

1. **No persistence layer exists.** No ei-graphics script writes to disk. Every state concept in Phase 1 is currently unimplementable.
2. **No storage location decided.** Open Question 1 remains open and gates §11, §12, and all of ITERATE.
3. **No schema for any artifact.** ApprovedScope is an indented tree in prose, not a versioned schema a validator can reject against.
4. **No integrity mechanism.** No hash, seal, or signature anywhere in the contract chain.
5. **No iteration identity.** Nothing distinguishes iteration N's changes from iteration N-1's.
6. **No baseline capture.** Regression attribution is impossible without a first-PR test result snapshot.
7. **No pack manifest format.** §16 refers to "domain pack manifests" that are otherwise undefined.
8. **No invariant rules format.** §17.4 refers to "a machine-readable rules file" with no structure given.
9. **No degraded-mode definition.** Behaviour with no matching pack is unspecified.
10. **No hook-tampering consideration.** Hook configuration lives in the workspace being modified.

---

## 5. Assumptions requiring proof

| # | Assumption | Where stated | Consequence if false |
|---|---|---|---|
| A1 | SpecKit agents can be driven programmatically without user handoff clicks | §5, §6, §28 | Architecture becomes semi-automatic; approval UX and value proposition change substantially |
| A2 | Structured state survives stage transitions | §10, §11, §16 | ApprovedScope degrades to advisory context; deterministic validation loses its reference |
| A3 | Extension hooks fire reliably and can block | §4, §17 | Pre-implementation enforcement is unavailable; all enforcement moves post-hoc |
| A4 | Diff comparison against ApprovedScope catches meaningful violations | §17.1 | Primary safety control has known blind spots |
| A5 | Domain pack selection from story text is accurate enough | §16 | Wrong invariants applied — worse than no pack |
| A6 | `speckit.implement` can be constrained without forking | §3, §22 | Agent specialization becomes mandatory, raising cost and maintenance |
| A7 | ITERATE can recover enough state to act incrementally | §8 | ITERATE degrades to a full re-run, losing its core benefit |
| A8 | Named invariants are practically checkable | §17.4 | Domain safety reverts to reasoning, which is not a gate |

A1 is the keystone. If it fails, §7, §22, §25, and §28 all require revision.

---

## 6. Risk classification

| Risk / Gap | Severity | Phase 1 Status | Must Prove Before Implementation? | Proposed Phase 2 Proof |
|---|---|---|---|---|
| Agent orchestration | **Critical** | Partially confirmed | **Yes** | Drive `speckit.plan` then `speckit.tasks` programmatically; confirm parent resumes |
| Structured state propagation | **Critical** | Confirmed via artifacts only | **Yes** | Write scope artifact, consume across 3 stages, assert byte-identical |
| ApprovedScope immutability | High | Gap | **Yes** | Hash at approval; validator refuses on mismatch |
| Scope expansion | High | Gap | **Yes** | Force an out-of-scope dependency; confirm block and change-request path |
| Diff validation | **Critical** | Too weak | **Yes** | Rename, delete, generated file, ignore file, weakened test — all detected |
| Domain pack selection | Medium | Gap | Partially | Ten stories against one pack; measure correct/incorrect/no-match |
| Domain / lifecycle boundary | Medium | Mostly clean | No | Resolve on paper before building |
| Vocabulary vs domain knowledge | Medium | Partially addressed | No | Define layered model on paper |
| Generic implementation safety | **Critical** | Gap | **Yes** | Run implement under supervision; confirm ignore-file writes are caught |
| Autonomous fix loop | High | Gap | **Yes** | Induce persistent failure; confirm ceiling, HALT, escalation |
| ITERATE state recovery | High | Gap | **Yes** | Reconstruct scope from a real PR; apply delta-only correction |
| PR evidence | Medium | Inconsistent | No | Define minimum persisted set on paper |
| Git history reliability | Low | Under-specified | No | Add validation rules on paper |
| Deterministic invariants | High | Partially addressed | **Yes** | One grep and one AST invariant blocking a real diff |
| Build/test vs domain correctness | Medium | Separated, roles unstated | No | Formalise the gate table |
| Failure / escalation | High | Gap | Partially | State machine on paper; prove fail-closed for unavailable CI |
| MVP scope | High | At risk | **Yes** | Written exclusion list agreed before any build |

---

## 7. Recommended Phase 2 technical spikes

Reordered by decisiveness per unit of cost. This supersedes the 2A–2E sequence in §25 of the architecture.

**Spike 1 — SpecKit invocability (go/no-go).**
Drive `speckit.plan` followed by `speckit.tasks` programmatically from a wrapper in a throwaway workspace. Confirm the child executes, the parent resumes, and no user handoff click is required. Smallest possible scope; highest information yield. If this fails, stop and revise the architecture before running any further spike.

**Spike 2 — Artifact-backed scope contract.**
Write a scope artifact to disk with a schema and a content hash. Have three consecutive stages read it. Assert byte-identical content at each read and that the validator refuses to run on hash mismatch. Proves A2 and A3 together.

**Spike 3 — Diff validator fidelity.**
Construct a diff containing a rename, a deletion, a generated file, an agent-created ignore file, an out-of-extension file, and a weakened test. Measure detection. This calibrates how much safety the primary control actually provides.

**Spike 4 — Constrained implementation.**
Run `speckit.implement` on a trivial task with a sealed scope and post-hoc validation. Confirm its ignore-file writes are detected and classified rather than silently accepted. Proves A6 and validates the benign-classification design.

**Spike 5 — Invariant enforcement.**
Implement one grep-checkable and one AST-checkable invariant from the Termination Drawing seed set. Confirm each blocks a genuinely violating diff and passes a compliant one. Proves A8 and calibrates cost.

**Spike 6 — Hook reliability.**
Register a mandatory `before_implement` and `after_implement` hook. Confirm both fire and that a failing hook actually blocks. Also confirm the wrapper's independent validation still runs when the hook is disabled. Proves A3 and the tamper-resistance requirement.

**Spike 7 — ITERATE recovery.**
From a real PR, recover the scope artifact and apply a delta-only correction on the same branch. Confirm attribution of a change to its originating iteration. Proves A7.

Suggested gating: Spike 1 alone, then review. Spikes 2 through 4 as the second block, then review. Spikes 5 through 7 only if the first two blocks pass.

---

## 8. Required changes to Phase 1 architecture

Not applied — listed for decision after this review.

1. **§5 / §6 / §28** — Downgrade orchestration language. Distinguish the proven subagent pattern from the unproven SpecKit-chaining assumption. Record the bug-diagnosis skill's explicit prohibition as counter-evidence.
2. **§10** — Add version identity, content hash, seal semantics, and read-only enforcement to ApprovedScope. Introduce ProposedScope and ScopeChangeRequest as distinct artifacts.
3. **§11** — Replace "storage options" with a decision. Add the schema requirement and the persist-versus-reference rule.
4. **§16** — Define pack manifest format, multi-pack merge rules, no-match behaviour, and explicit surfacing of pack selection at the approval checkpoint.
5. **§17** — Split the validation gate into blocking and advisory tiers. Add rename/delete/generated/ignore-file handling. Specify file-level universally and symbol-level for domain-risk paths only. Add test-weakening detection.
6. **§17.4** — Classify each seed invariant by enforcement class. State that reasoning-only invariants are advisory. Require each invariant to name its enforcing check or test.
7. **§7 step 15** — Define the fix loop bound, per-iteration scope re-validation, no-new-files rule, divergence detection, and escalation.
8. **§8** — Add baseline test result capture and per-iteration commit attribution.
9. **New section** — Failure and escalation state machine with the fail-closed principle.
10. **§22** — Add the explicit exclusion list.
11. **§25** — Replace with the revised spike sequence in section 7 above.
12. **New note** — Hook configuration lives in the workspace under modification; wrapper validation must not depend solely on it.

---

## 9. Must prove before implementation

Non-negotiable. Each has a named falsifiable outcome.

1. A SpecKit agent can be invoked programmatically and the parent resumes afterwards.
2. A structured artifact survives three stage transitions byte-identical.
3. A validator refuses to operate when the scope hash does not match.
4. The diff validator detects renames, deletions, generated files, agent-created ignore files, and out-of-extension changes.
5. `speckit.implement`'s ignore-file writes are detected and classified rather than silently accepted.
6. At least one domain invariant blocks a real violating diff.
7. A fix loop terminates at its ceiling and escalates rather than continuing.
8. ITERATE recovers a scope artifact from a real PR and applies a delta-only correction.
9. Unavailable CI produces a block, not a pass.

---

## 10. Final recommendation

**Proceed to Phase 2 as a proof exercise. Do not begin implementation.**

The Phase 1 architecture is sound in structure and consistent with proven repository patterns. Its weaknesses are concentrated in unproven assumptions rather than incorrect design, which is the better failure mode at this stage — assumptions can be tested cheaply, whereas structural errors cannot.

Three conditions attach to proceeding:

**Run Spike 1 in isolation first.** Whether SpecKit agents can be driven programmatically determines whether the architecture is automatic or semi-automatic. That single answer affects §7, §22, §25, and §28. Running other spikes before knowing it risks building proofs for an architecture that needs revision.

**Decide state persistence before Spikes 2 through 7.** Open Question 1 gates ApprovedScope, ITERATE, and the evidence package. It is a design decision, not a research question, and it can be settled now.

**Agree the MVP exclusion list before any build work.** The two open-ended MVP items are the most likely source of scope inflation, and the domain pack concept is expansive enough to absorb unlimited effort.

The highest-value correction available is small: make ApprovedScope a real file with a schema and a hash. It converts the central contract from a diagram into something a script can enforce, and it is a prerequisite for most of the remaining proofs.

One caution worth stating plainly. The most dangerous outcome is not a spike that fails — it is a spike that appears to succeed because a capable model compensated for a missing control. Each spike must assert on artifacts and exit codes, never on an agent's own account of what it did. That is precisely the lesson already encoded in the create-backlog orchestrator's Verify step, and it should be the standing rule for Phase 2.

---

Status: Risk review complete. Awaiting decision on which Phase 2 spikes to authorise.
