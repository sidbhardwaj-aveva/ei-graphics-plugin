# Phase 2A — SpecKit Agent Orchestration Verification

Date: 2026-08-11
Type: Technical verification experiment (Spike 1 from the Phase 1 risk review)
Scope: Verification only. No production code, agents, skills, SpecKit files, or `.specify/extensions.yml` were modified.

---

## Executive summary

**The critical assumption holds. All four SpecKit stages were invoked programmatically and chained end to end with zero manual handoffs.**

`speckit.specify → speckit.plan → speckit.tasks → speckit.implement` ran as a fully automated chain driven by a parent orchestrator. The parent regained control after every stage. Structured state written by each agent was read by the next and survived all four transitions byte-intact.

This **overturns Finding A** of the Phase 1 risk review, which predicted that `handoffs:` frontmatter and `user-invocable: false` would force human handoffs. Both turn out to be UI affordances, not invocation barriers.

It **confirms Finding B** (files on disk are the reliable state substrate) and **confirms Finding C** with direct evidence — `speckit.implement` created a `.gitignore` nobody asked for, in explicit conflict with the task list it was executing.

**Decision: PROCEED WITH AGENT CHAIN.** The Phase 1 architecture needs no structural change. It needs one correction: the load-bearing safety control must be the wrapper's own post-hoc diff validation, because the agents demonstrably write outside their nominal scope.

---

## 1. Environment

| Item | Value |
|---|---|
| Host | VS Code, GitHub Copilot agent mode |
| Orchestration model | Claude Opus 5 |
| OS / shell | Windows, PowerShell (pwsh) |
| Parent repository | `aveva-agent-plugins` |
| Parent branch at test time | `feat/ei-graphics-plugin-foundation` @ `65cb93b` |
| VS Code workspace folder | `plugins/` (note: **one level below** the git root) |
| Default terminal CWD | git root `aveva-agent-plugins`, **not** the workspace folder |
| SpecKit scaffold | `.specify/` present at git root |
| Invocation mechanism used | `runSubagent` tool, `agentName` = `aveva-rnd:speckit.<stage>.agent` |

### Agent configuration as declared

| Agent | `user-invocable` | `handoffs:` | `agents:` | Invoked successfully |
|---|---|---|---|---|
| `speckit.specify` | `false` | yes (plan, clarify) | none | **Yes** |
| `speckit.plan` | `false` | yes (tasks, checklist) | none | **Yes** |
| `speckit.tasks` | `false` | yes (analyze, implement) | none | **Yes** |
| `speckit.implement` | `false` | none | none | **Yes** |

### Why the risk review's prediction was wrong

Three pieces of evidence explain the discrepancy:

1. **`user-invocable: false` is a menu-visibility flag, not an access control.** It hides the agent from the user's agent picker. It does not affect `runSubagent`. The R&D bootstrap script confirms this reading — `Initialize-SpecKit.ps1` lines 349–363 *strips* the line when deploying agents into a consuming workspace precisely so they appear in the picker:
   ```powershell
   # Strip user-invocable: false line from frontmatter
   $content = $content -replace '(?m)^user-invocable:\s*false\r?\n', ''
   ```
   Nothing in that script grants invocability — it grants *visibility*.

2. **`handoffs:` renders suggestion buttons after a stage completes.** It is an offer to the user, not a barrier. It does not block or gate a programmatic caller. Every SpecKit agent still ran to completion and returned.

3. **The absence of `agents:` frontmatter on SpecKit agents did not prevent invocation.** The plugin's agent registry exposed them to `runSubagent` regardless. The `agents:` array in `ai-ready-workflow` is a declaration of intent, not a prerequisite.

The risk review's counter-evidence — the bug-diagnosis skill's *"Do NOT invoke the bug fix workflow via `runSubagent`"* — is a **policy** decision about a specific workflow, not a **capability** limit. It was correctly identified as a signal but incorrectly read as proof of impossibility.

---

## 2. Test environment (disposable)

Created at `<git-root>/.poc-speckit-orchestration`, since deleted.

### Isolation design

The decisive mechanism is in `.specify/scripts/powershell/common.ps1`:

```powershell
function Find-SpecifyRoot {
    while ($true) {
        if (Test-Path (Join-Path $current ".specify") -PathType Container) { return $current }
        ...
    }
}
```

`Get-RepoRoot` prefers `.specify` over git. A sandbox carrying its own `.specify` therefore **becomes** the SpecKit repo root for any script run with the CWD set there, regardless of the enclosing git repository. Verified empirically:

```
RepoRoot = ...\.poc-speckit-orchestration
HasGit   = False
Branch   = main
```

This is a reusable, verified isolation primitive for `ei-graphics`.

Isolation layers applied:

| Layer | Control | Effect |
|---|---|---|
| Root resolution | Sandbox owns `.specify` | Parent repo never resolved as SpecKit root |
| Git | No `.git` (Tests 1–3) | `Test-HasGit` false; branch validation skipped; no git operations |
| Hooks | Sandbox `extensions.yml` declares `hooks: {}` | Parent's mandatory `before_specify` branch hook and all `after_*` auto-commit hooks could not fire |
| Prompt constraint | Explicit "never write outside SANDBOX" | Respected by all four agents |
| Git isolation (Test 4) | `git init` inside sandbox, own baseline commit | Exact diff capture; parent repo unreachable |

The production `.specify/extensions.yml` was **not** modified. The sandbox file was a new file in a disposable directory.

### Containment result

Parent repository git state, before and after the full four-stage chain:

```
HEAD   = 65cb93ba77dde13f5adf364c64c4015a3bd44685   (unchanged)
BRANCH = feat/ei-graphics-plugin-foundation          (unchanged)
STATUS = identical to baseline
```

No commit, no branch, no file created or modified outside the sandbox by any agent.

---

## 3. Test 1 — `speckit.specify` invocation

**Result: PASS**

| Question | Answer |
|---|---|
| Invocation mechanism | `runSubagent(agentName: "aveva-rnd:speckit.specify.agent", prompt: ...)` |
| Invocation succeeded | Yes |
| Agent actually executed | Yes — verified on disk, not from narrative |
| Context received | The prompt only. Feature description, sandbox path, and directory override. No conversation history was inherited |
| Output produced | `specs/001-fixture-validation/spec.md` (7 FRs, 1 user story, 5 acceptance scenarios), `checklists/requirements.md`, `.specify/feature.json` |
| Control returned to caller | **Yes** — orchestrator resumed and executed its own verification logic |
| Manual interaction required | **None.** Zero questions asked |

Test story used: *"Add a small validation method to a test fixture."*

Two latent user-handoff branches exist in the specify workflow and neither was taken:
- Unresolved `[NEEDS CLARIFICATION]` markers → present questions and wait. Not triggered; the agent resolved three ambiguities as documented assumptions instead.
- Quality validation failing after 3 iterations → warn user. Not triggered; passed on iteration 2.

There is **no unconditional handoff** in the specify workflow.

---

## 4. Test 2 — `speckit.specify → speckit.plan`

**Result: PASS**

The feature description was **deliberately withheld** from `speckit.plan`. It was told only the technical context (C#/.NET 8, xUnit) and the sandbox path, and instructed to discover the feature from disk.

Proof of genuine consumption — the agent returned verbatim text it could only have obtained by reading Test 1's output:

> **FR-005**: The validity check MUST be read-only: it MUST NOT change the fixture's name, count, or any other observable state, and repeated checks on an unchanged record MUST return the same answer.
>
> **FR-006**: The validity check MUST report a plain true/false answer and MUST NOT signal invalidity by raising an error.

Feature title recovered independently: *Fixture Validation*.

### How state actually transferred

Two independent channels, both file-backed:

1. **SpecKit's own channel.** `speckit.specify` wrote `.specify/feature.json`:
   ```json
   { "feature_directory": "specs/001-fixture-validation" }
   ```
   `speckit.plan` ran `setup-plan.ps1 -Json`, which read that file via `Get-FeaturePathsEnv` and returned `FEATURE_SPEC`, `IMPL_PLAN`, `SPECS_DIR`, `BRANCH`, `HAS_GIT`. This is a **native, deterministic, script-mediated handoff that already exists** — no custom plumbing required.

2. **The POC's test channel.** A synthetic token planted by Test 1 in `state.json` and echoed back by Test 2:
   `SPECIFY_TO_PLAN_TOKEN_A1B2C3` — read and returned correctly.

Artifacts produced: `plan.md`, `research.md`, `data-model.md`, `quickstart.md`.

**Out-of-scope write observed at this stage:** the agent also created `.github/copilot-instructions.md`. This was within the sandbox but was not requested. It is the Phase 1 agent-context step behaving as designed — and it demonstrates that unrequested writes are **not exclusive to `speckit.implement`**.

Manual interaction: none. Two decisions were resolved by informed guess (constitution gates marked N/A with justification; missing `.csproj` recorded as accepted limitation R-004) rather than by asking.

---

## 5. Test 3 — `speckit.specify → speckit.plan → speckit.tasks`

**Result: PASS**

Both the feature description and the plan's decisions were withheld. `speckit.tasks` discovered everything from disk.

Proof of consumption at each depth:

| Source artifact | Evidence returned |
|---|---|
| `plan.md` | Language/Version `C# 12 / .NET 8`; Primary Dependencies `None added. Test-side only: xUnit`; correctly reported no `contracts/` directory exists |
| `research.md` | R-004 content: tests cannot compile — no `.csproj`/`.sln`, project creation forbidden by plan; logged as accepted limitation |
| `spec.md` | Title *Fixture Validation*; **7** functional requirements |
| `state.json` | Read `SPECIFY_TO_PLAN_TOKEN_A1B2C3::PLAN_TO_TASKS_TOKEN_D4E5F6` |

Native channel: `check-prerequisites.ps1 -Json` returned `FEATURE_DIR` and `AVAILABLE_DOCS` = `["research.md","data-model.md","quickstart.md"]` — an automatic inventory of what upstream stages produced.

Output: `tasks.md`, 14 tasks (T001–T014) across 4 phases.

Manual interaction: none. The tasks workflow contains **no user-handoff gate at all**.

Verified: `plan` received the specification; `tasks` received the plan; the orchestrator regained control after each stage; no manual handoff occurred at any point.

---

## 6. State propagation

**Result: PASS**

Mechanism: **file artifact.** Not conversation context, not return values.

Each subagent runs with a fresh context window. It receives the prompt text and nothing else — no conversation history, no parent variables. Everything durable moved through disk.

Final `state.json` after four stages, showing an unbroken chain:

```json
{
  "pocId": "orchestration-test",
  "stage": "implement",
  "testValue": "STATE_PROPAGATION_SUCCESS",
  "stageLog": [
    { "stage": "init",      "writtenBy": "orchestrator" },
    { "stage": "specify",   "writtenBy": "speckit.specify",
      "readTestValue": "STATE_PROPAGATION_SUCCESS" },
    { "stage": "plan",      "writtenBy": "speckit.plan",
      "readTestValue": "STATE_PROPAGATION_SUCCESS",
      "readHandoffTokenFromSpecify": "SPECIFY_TO_PLAN_TOKEN_A1B2C3" },
    { "stage": "tasks",     "writtenBy": "speckit.tasks",
      "readTestValue": "STATE_PROPAGATION_SUCCESS",
      "readHandoffTokenFromPlan": "SPECIFY_TO_PLAN_TOKEN_A1B2C3::PLAN_TO_TASKS_TOKEN_D4E5F6" },
    { "stage": "implement", "writtenBy": "speckit.implement",
      "readTestValue": "STATE_PROPAGATION_SUCCESS",
      "readChainTokenFromTasks": "...::TASKS_TERMINAL_TOKEN_G7H8I9" }
  ]
}
```

`testValue` survived all four transitions unmodified. Each stage read the previous stage's token and carried it forward. Every agent preserved fields it was told not to touch.

### Channel assessment

| Channel | Reliable? | Notes |
|---|---|---|
| **File artifact** | **Yes** | Proven across 4 stages. The mechanism to build on |
| **SpecKit native (`feature.json` + setup scripts)** | **Yes** | Already exists, deterministic, script-mediated. Free reuse |
| Structured return value | Partial | Agents returned accurate structured reports, but only because the prompt demanded a return contract. Treat as a status signal, verify on disk |
| Conversation context | **No** | Subagents get a fresh context. Nothing implicit crosses the boundary |
| Skill output | Not exercised | Not needed — direct invocation succeeded |

**Design consequence for `ei-graphics`:** ApprovedScope must be a file with a schema and a content hash. Every consumer re-reads it. This was already the Phase 1 direction; it is now empirically confirmed as the only reliable option.

---

## 7. Parent continuation

**Result: YES**

The parent orchestrator performed, without interruption:

```
write state.json (stage=init)
  → invoke speckit.specify   → wait → resume → re-read state.json → verify spec.md on disk
  → invoke speckit.plan      → wait → resume → re-read state.json → verify plan.md on disk
  → invoke speckit.tasks     → wait → resume → re-read state.json → verify tasks.md on disk
  → invoke speckit.implement → wait → resume → capture git diff
  → continue with its own reporting logic
```

`runSubagent` is **synchronous and blocking**. The call returns when the child completes. The parent's own state and logic remain fully intact across each call. The distrust-the-child pattern (re-read the artifact rather than trust the narrative) worked exactly as it does in the create-backlog orchestrator, and is recommended for `ei-graphics`.

---

## 8. Manual handoffs

**Result: ZERO manual handoffs were required across the full four-stage chain.**

No human intervened at any point between stages. Every point where a handoff *could* have occurred is listed below with its trigger condition:

| # | Stage | Gate | Trigger condition | Fired? |
|---|---|---|---|---|
| 1 | specify | Present `[NEEDS CLARIFICATION]` questions and wait | Markers survive validation | No — ambiguities resolved as assumptions |
| 2 | specify | Warn user | Quality validation fails 3× | No — passed on iteration 2 |
| 3 | plan | ERROR on gate failure | Constitution gate violated / unresolved clarifications | No |
| 4 | tasks | — | No user-handoff gate exists | N/A |
| 5 | implement | *"Some checklists are incomplete. Proceed anyway? (yes/no)"* | Any checklist item unchecked | **No — but only by luck.** 16/16 items were complete because `speckit.specify` had generated and satisfied its own checklist |
| 6 | implement | Ignore-file vs task-scope conflict | Instructions conflict, no arbitration rule | **Yes, latent** — see §9 |
| 7 | implement | T013 clean-code gate vs useful comment | Rule conflict | **Yes, latent** — resolved unilaterally |

### The one gate that matters

**Gate 5 is the real risk.** `speckit.implement` halts and asks the user whenever any checklist item is unchecked. In this run it passed only because the upstream checklist happened to be complete.

Two viable mitigations for `ei-graphics`:
1. Run `speckit.checklist` in the chain and satisfy items programmatically before `implement`.
2. State an explicit auto-answer policy in the prompt, as this POC did.

Option 1 is the honest one. Option 2 removes a safety gate and should only be used where the wrapper's own deterministic validation replaces it.

Gates 6 and 7 are not formal stops — they are decisions the agent made unilaterally that a human would normally arbitrate. They produce silent, unlogged judgement calls. This is an argument for post-hoc deterministic validation, not for more prompts.

---

## 9. Implementation test — `speckit.implement`

**Result: PASS (executed safely) — with the risk review's Finding C empirically confirmed**

Run in a fully git-isolated sandbox, never against the production 2D workspace.

### Protocol

1. Baseline captured: `git init` in sandbox, all 27 files committed, branch `001-fixture-validation`, working tree clean.
2. Full file inventory recorded.
3. Agent invoked with instructions to behave normally and *not* to self-censor.
4. Final `git status --porcelain`, `git diff --name-status -M`, and ignored-file listing captured.
5. Parent repository re-verified against baseline.

### Files changed

```
=== git status --porcelain ===
 M .copilottracking/orchestration-poc/state.json     ← requested (state artifact)
 M specs/001-fixture-validation/tasks.md             ← expected (T001-T014 marked [X])
 M src/TestFixture.cs                                ← THE INTENDED CHANGE
?? .gitignore                                        ← *** UNEXPECTED ***
?? tests/TestFixtureTests.cs                         ← expected (task T002/T006)
?? evidence/implement-baseline.txt                   ← written by the orchestrator, not the agent
```

The intended change, in full:

```diff
--- a/src/TestFixture.cs
+++ b/src/TestFixture.cs
@@ -6,4 +6,6 @@ public sealed class TestFixture
     public string Name { get; init; } = string.Empty;
 
     public int Count { get; init; }
+
+    public bool IsValid() => Name.Length > 0 && Count >= 0;
 }
```

Correct, minimal, and exactly what was specified.

### The unexpected change

| Category | Finding |
|---|---|
| **Ignore-file changes** | **`.gitignore` created unprompted** at sandbox root with `bin/`, `obj/`, `*.user`, `*.suo`, `packages/`, `.DS_Store`, `Thumbs.db`, `*.tmp`, `*.swp`, `.vscode/`, `.idea/` |
| Configuration changes | None |
| Dependency changes | None |
| Test changes | `tests/TestFixtureTests.cs` created — legitimately, per tasks T002/T006 |
| Unrelated changes | None beyond `.gitignore` |

The agent reported the conflict itself, unprompted:

> Step 4 of my instructions marks ignore-file creation as **REQUIRED**. [...] **This is a finding:** step 4 directly conflicts with tasks.md T003, which states "nothing is written outside `src/`, `tests/`, and `specs/001-fixture-validation/`". No instruction arbitrates the conflict; I followed step 4 because it is marked REQUIRED.

This is decisive. The agent had an explicit, in-scope, machine-readable scope boundary in the task list it was executing, and **overrode it** because its own instructions ranked higher. Confirmed: **no amount of prompt-level or domain-skill scope guidance will constrain `speckit.implement`.** Enforcement must be external, deterministic, and post-hoc.

### Detection check

The Phase 1 diff validator as specified filters `git diff --name-only` to `.cs|.csproj|.xaml|.json`. That filter **silently drops `.gitignore`** — the single unexpected change in this run would have gone undetected. Risk review §3.4 predicted precisely this. Confirmed.

### Safety

- 14/14 tasks completed. Tests authored but not executed (no `.csproj`; accepted limitation R-004).
- Exactly one git command run by the agent, read-only and explicitly scoped: `git -C "<SANDBOX>" rev-parse --git-dir`.
- No commit, push, checkout, or branch operation.
- Parent repository unchanged: `HEAD`, branch, and `git status` identical to baseline.

`speckit.implement` **can** be safely invoked in an isolated environment, provided the sandbox owns its own `.specify` and `.git`, hooks are neutralised, and a full diff is captured afterwards.

---

## 10. Alternative mechanisms

Direct agent invocation succeeded, so no fallback was required. The reuse stack was nonetheless assessed for the record:

| Level | Available? | Verdict |
|---|---|---|
| **Agent** | **Yes — verified** | `runSubagent` with `aveva-rnd:speckit.<stage>.agent`. Synchronous, blocking, returns control. **Use this** |
| **Skill** | Yes | `speckit-bootstrap`, `create-pr`, and the EI skills are invocable. Not needed for the lifecycle chain |
| **Script** | Yes — verified | `setup-plan.ps1`, `check-prerequisites.ps1`, `common.ps1` all run standalone with `-Json` and honour `SPECIFY_FEATURE_DIRECTORY`. Already the deterministic backbone of the native handoff |
| **Hook** | Present, untested | 18 `before_*`/`after_*` points in `extensions.yml`. Deliberately neutralised here to protect the parent repo. Reliability is Spike 6 |
| **Extension** | Present | The `git` extension supplies branch/commit commands via hooks |
| **Artifact-driven** | **Yes — verified** | `.specify/feature.json` plus `.copilottracking/` JSON. The reliable state substrate |

**Highest level of existing R&D capability that can be automatically orchestrated: the agent level** — the top of the stack. No downgrade to skills or scripts is necessary.

---

## 11. Final decision

```
Can SpecKit agents be programmatically orchestrated?
                    │
             ┌──────┴──────┐
             │             │
            YES ◄── VERIFIED
             │
             ▼
      Can structured state propagate?
             │
            YES ◄── VERIFIED (file artifact, 4 stages)
             │
             ▼
      PROCEED WITH AGENT CHAIN
```

### Direct answers

| | Question | Answer |
|---|---|---|
| **A** | Can we invoke `speckit.specify` programmatically? | **YES.** `runSubagent`, `aveva-rnd:speckit.specify.agent`. No user interaction |
| **B** | Can we invoke `speckit.plan` programmatically? | **YES.** Consumed Test 1's spec verbatim without being told its contents |
| **C** | Can we invoke `speckit.tasks` programmatically? | **YES.** Consumed plan, research, and spec. No handoff gate exists in this stage |
| **D** | Can they be chained automatically? | **YES.** All four stages ran back to back with zero human intervention |
| **E** | Can structured state be passed reliably between them? | **YES — via files only.** `testValue` and chained tokens survived all four transitions. Conversation context does **not** cross the subagent boundary |
| **F** | Can the parent orchestrator continue after each stage? | **YES.** `runSubagent` is synchronous and blocking; parent state and logic remain intact |
| **G** | Can `speckit.implement` be safely invoked in an isolated environment? | **YES, with controls.** Sandbox must own `.specify` and `.git`, hooks neutralised, full diff captured. It **will** write outside the task scope — `.gitignore` was created unprompted |
| **H** | If direct invocation fails, what R&D mechanism substitutes? | **Not needed.** Fallback order remains skill → script (`setup-plan.ps1`, `check-prerequisites.ps1` are standalone and JSON-contracted) → hook → artifact-driven |
| **I** | Minimum change required to the Phase 1 architecture? | **Four corrections — see below.** No structural redesign |

### Minimum changes to Phase 1

1. **§5, §6 — Upgrade the orchestration claim from inferred to verified.** Record the mechanism precisely: `runSubagent` with `aveva-rnd:speckit.<stage>.agent`; `user-invocable: false` is menu visibility only; `handoffs:` is a suggestion affordance, not a barrier. Risk-review Finding A and assumption A1 are **closed as false alarms**.

2. **§11 — Close Open Question 1. Decide the storage location now.** The evidence permits no alternative: state must be a file. Adopt `.copilottracking/ei-graphics/<story-id>/` for `ApprovedScope`, analysis state, and gate results, with `.specify/feature.json` reused as the native SpecKit link. This unblocks §12 and all of ITERATE.

3. **§17.1 — Replace the extension-filtered diff check.** Mandate `git diff --name-status -M` with **no extension filter**, plus a separate untracked-file sweep. The one unexpected change in this experiment (`.gitignore`) is invisible to the currently specified `.cs|.csproj|.xaml|.json` filter. Add a `known-benign` classification so agent-created ignore files are reported and accepted rather than either blocking or being silently dropped.

4. **§22 — State the enforcement principle explicitly.** `speckit.implement` overrode a written, in-scope task-list boundary because its own instructions outranked it. Therefore: *prompt-level and domain-skill scope guidance is advisory; the wrapper's own post-hoc deterministic diff validation is the only load-bearing control.* Do **not** fork `speckit.implement` — reuse it and validate its output.

Additionally, add to the MVP:
- Run `speckit.checklist` inside the chain, or declare an explicit auto-answer policy, so the `implement` checklist gate cannot stall an automated run (Manual Handoff #5).
- Note that unrequested writes are **not** confined to `implement` — `speckit.plan` created `.github/copilot-instructions.md`. Scope validation must cover every stage, not just implementation.

### Preferred outcome — status

```
ADO Story URL
      ↓
ei-graphics                    ← to build
      ↓
Scope Analysis                 ← to build
      ↓
Human Scope Approval           ← single checkpoint, unchanged
      ↓
AUTOMATED R&D WORKFLOW         ← *** VERIFIED IN THIS EXPERIMENT ***
      ↓
Implementation                 ← VERIFIED, requires external diff validation
      ↓
Validation                     ← Spike 3
      ↓
Git / PR                       ← existing git agents + create-pr skill
```

The platform does not prevent automation. No manual handoff needs to be introduced between the SpecKit stages.

### Assumptions resolved

| # | Assumption | Status |
|---|---|---|
| A1 | SpecKit agents drivable without user handoff | **PROVEN TRUE** — was the keystone risk |
| A2 | Structured state survives stage transitions | **PROVEN TRUE via files**; proven false for conversation context |
| A6 | `speckit.implement` constrainable without forking | **PROVEN TRUE**, conditional on external post-hoc validation |
| A3 | Hooks fire reliably and can block | **UNTESTED** — deliberately neutralised. Spike 6 |
| A4 | Diff comparison catches violations | **PROVEN INSUFFICIENT as specified**. Spike 3 |
| A5, A7, A8 | Pack selection, ITERATE recovery, invariant checkability | Untouched. Spikes 5–7 |

### Recommended next step

Proceed to **Spike 2 (artifact-backed scope contract)** and **Spike 3 (diff validator fidelity)**. Spike 3 is now the highest-value remaining item: the safety control has a confirmed blind spot and a confirmed adversary.

---

## 12. Teardown

The disposable sandbox `<git-root>/.poc-speckit-orchestration` — including its nested git repository, `.specify` scaffold, generated SpecKit artifacts, test fixture, and evidence files — has been deleted. Nothing outside it was created or modified at any point.

Verified unchanged after teardown: parent repository `HEAD`, branch, and working-tree status.
