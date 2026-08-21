# EI Graphics Workflow Architecture Review

Date: 2026-08-11

## Decision

Phase 1 should change from an EI agent orchestrating multiple agents to a workflow-first architecture:

```text
User
  -> EI Graphics Agent (thin conversational entry)
  -> ei-graphics-workflow skill (lifecycle owner)
  -> EI skills + R&D skills + Core skills
  -> selected reasoning agents
  -> deterministic gates + file-backed artifacts
  -> Git / PR
```

Repository evidence and the disposable POC support this model. The POC proved ordered local capabilities, `.copilottracking` artifact propagation, cross-plugin R&D invocation, fail-closed dependency checks, deterministic blocking gates, and a human approval pause/resume. No production file was changed.

## Existing Architecture

### Workflow skills

The repository already implements workflow skills. Digital Twin's `alarm-investigation-workflow` and `orchestrator-workflow` own prerequisites, phase ordering, validation gates, output initialization, resume logic, and return contracts. Their agents are intentionally thin: `alarm-agent` says operational logic lives in skills and tells the agent to load and follow the workflow skill exactly.

R&D's Create Backlog workflow is the closest implementation pattern:

- Its agent declares `tools: ['execute/runInTerminal', 'read', 'search', 'skill']`.
- It invokes a narrow skill per phase.
- It re-reads `.copilottracking` validation artifacts after a skill returns.
- It blocks, retries, or waits for human input based on the artifact rather than narrative output.

GitHub Copilot skills are surfaced through progressive disclosure. When the host has no callable `skill` tool, the established R&D fallback is to read the skill's `SKILL.md` and execute its documented scripts. A production workflow must use this explicit fallback, never silently omit a required stage.

### Skills

Skills are the reusable capability boundary. They own the specific operation; a workflow owns timing and ordering.

| Lifecycle stage | Existing capability | Plugin | Decision |
|---|---|---|---|
| Fetch ADO story | `ei-azure-devops-cli-intake`, `azure-devops`, `azure-devops-cli` | EI, R&D | Reuse |
| Story analysis | `ei-bug-reproducer`, `ei-vocabulary-navigator` | EI | Reuse |
| 2D context | vocabulary navigator, Termination Drawing sample pack | EI | Reuse navigator; add curated domain packs |
| Scope analysis | No equivalent complete capability | — | New resolver and validator |
| Specification | `speckit.specify`, `speckit-bootstrap` | R&D | Reuse |
| Planning | `speckit.plan` | R&D | Reuse |
| Tasks | `speckit.tasks` | R&D | Reuse |
| Implementation | `speckit.implement` | R&D | Reuse behind external gates |
| Testing | `ei-test-scaffolder`, domain-pack commands | EI | Reuse; add deterministic runner only if needed |
| Validation | `ei-layer-guard` | EI | Reuse; add full diff/scope validator |
| Code review | `code-review`, `get-reviewresults` | R&D | Cross-plugin reuse |
| Audit | `create-audit` | Core | Cross-plugin reuse |
| Commit / PR | `git-commit`, `create-pr` | R&D | Cross-plugin reuse |
| Bug diagnosis | `bug-diagnosis`, `speckit.bugdiagnosis` | R&D | Reuse for ITERATE |

### Agents

Agents should be either thin conversational entries or reasoning workers. The SpecKit agents are reasoning workers; they must not become lifecycle owners. The current `ei-graphics-workflow.agent.md` mixes entry and lifecycle responsibilities. The production shape should instead be a thin `ei-graphics.agent.md` that collects input, invokes `ei-graphics-workflow`, and communicates the resulting contract.

The thin agent should expose `skill`, following the exact established frontmatter convention of the target host. In this repository, the Create Backlog agent supplies concrete evidence for `tools: [..., 'skill']`.

## Cross-Plugin Invocation

Cross-plugin skills are an existing pattern. The USC Docs agent invokes `/aveva-core:create-audit` and explicitly fails if the skill is unavailable. R&D skill frontmatter supports conventional declarations such as:

```yaml
metadata:
  dependencies:
    - create-audit
```

EI should declare, but not treat as installed by, dependencies such as:

```yaml
metadata:
  dependencies:
    - code-review
    - get-reviewresults
    - create-audit
    - git-commit
    - create-pr
```

Required safety dependencies need a preflight. If a plugin is missing, block clearly: `aveva-rnd is not installed. Install it from the marketplace and retry.`

The POC invoked R&D `get-reviewresults` from the disposable workflow and stored its returned JSON. Its `missing` result correctly reported no existing review; that is a valid read-only result and verifies the cross-plugin capability path.

## State, Scope, and Gates

`.copilottracking` is the proven artifact handoff system. Digital Twin writes sessions, progress, and validation caches there. R&D AI Ready, code review, and Create Backlog write and re-read phase artifacts. State must not be passed through narrative context.

Use story-scoped state:

```text
.copilottracking/ei-graphics/<story-id>/
  ado.json
  domain-context.json
  proposed-scope.json
  approved-scope.v1.json
  scope-change-request.v2.json
  specification.json
  plan.json
  tasks.json
  implementation.json
  validation.json
  code-review.json
  iteration.json
  pr.json
  validation/
```

The exact names can evolve, but each artifact must have a single owner and a schema. Persist only what cannot be reconstructed from ADO, Git, CI, or PR systems; store identifiers and references rather than source code copies.

### ApprovedScope

ApprovedScope remains a first-class contract. It should include the story, selected domain packs, files, modules, tests, protected areas, dependencies, risks, expected changes, and human approval metadata. At approval time, serialize a canonical representation and record a content hash. Every subsequent stage recomputes the hash and blocks if it differs.

Scope may not silently expand:

```text
unexpected path or dependency
  -> scope-change request
  -> human approval
  -> approved-scope.v2.json with new hash
  -> continue
```

The POC verified this: stage B read only stage A's JSON artifact, a pending approval blocked the workflow, approval enabled resume, and a post-approval scope edit produced a hash mismatch and block.

### Deterministic safety

LLM prompts and domain skills are advisory. Independent validators are the safety control:

- Full `git diff --name-status -M` with no extension filter and an untracked-file sweep.
- Path classification: in-scope, known-benign, generated, dependency, unexplained.
- Block unexplained out-of-scope paths and protected-area modifications.
- Selective symbol-level validation for domain-risk or protected files.
- Compilation, targeted-test, regression-test, and machine-checkable invariant gates.
- Three maximum correction attempts, validation after each, and halt on persistent failure or growing diff.

Phase 2A already confirmed that `speckit.implement` creates unrequested `.gitignore` files and that `speckit.plan` can create unrequested Copilot instruction files. Scope validation must run after every writing stage. Hooks are useful early feedback but cannot be the sole protection because the target repository can alter them.

## IMPLEMENT Workflow

```text
ADO story URL
  -> ADO intake artifact
  -> vocabulary/domain-pack resolution
  -> proposed scope and deterministic analysis
  -> human ApprovedScope checkpoint
  -> specification / plan / tasks
  -> implementation
  -> targeted and regression tests
  -> scope and invariant validation
  -> /aveva-rnd:code-review
  -> /aveva-core:create-audit
  -> commit
  -> PR
```

Every boundary writes an artifact, re-reads it, and evaluates a gate. Missing artifacts, failed tests, unavailable CI, missing required tooling, or failed validation are BLOCK states.

Phase 2A demonstrated that SpecKit agents can run synchronously and consume disk artifacts. That is capability evidence, not a mandate to build agent-to-agent lifecycle orchestration. The user requirement prohibits `runSubagent` for this migration. The EI workflow therefore controls lifecycle stages through skills, scripts, and supported skill delegation; selected agents remain reasoning workers only.

## ITERATE Workflow

```text
existing PR / branch
  -> recover ApprovedScope, Git, CI, tests, and PR feedback
  -> /aveva-rnd:bug-diagnosis
  -> minimal correction within sealed scope
  -> targeted and regression tests
  -> scope/invariant validation
  -> /aveva-rnd:code-review
  -> /aveva-core:create-audit
  -> commit on same branch
  -> update same PR
```

ITERATE does not restart intake or broaden scope. Store an iteration index, baseline test result references, commit SHA, CI/review identifiers, and gate results. The initial ApprovedScope remains authoritative until a human approves an expansion. R&D `bug-diagnosis` prohibits invoking the Bug Fix Workflow via `runSubagent`; use its diagnosis handoff/state, while preserving EI workflow ownership.

## POC Verification

The disposable `.poc-workflow-skill` used a thin agent declaration with `skill`, a local workflow skill, two local stage skills, PowerShell gates, `.copilottracking/poc-workflow/` state, and R&D `get-reviewresults`.

| Required verification | Result |
|---|---|
| Thin agent can declare and route to a workflow skill | Repository pattern verified |
| Workflow can invoke local skills | Pass: stage A and B |
| Workflow can invoke cross-plugin capability | Pass: R&D `get-reviewresults` |
| Cross-plugin namespace / ownership path | Pass |
| Artifacts can be written and consumed | Pass: stage B consumed `stage-a.json` |
| Ordering is enforced | Pass: stage B before stage A blocked |
| Failed gates stop progress | Pass: missing artifact gate returned Invalid / exit 1 |
| Missing dependency is clear and fail-closed | Pass: marketplace-install message |
| Human checkpoint can pause and resume | Pass: pending blocked; approved resumed |
| Scope tampering is detected | Pass: approval-hash mismatch blocked |

The POC did not prove a literal host-wide workflow-skill invocation API because GitHub Copilot exposes skills through progressive disclosure. It did prove the repository model of executable SKILL.md procedures, deterministic scripts, file state, and cross-plugin reuse.

## Component Decisions

### Reuse unchanged

- EI intake, vocabulary navigation, layer guard, test scaffolding, and bug reproduction.
- R&D ADO, code review, review results, commit, PR, diagnosis, and SpecKit capabilities.
- Core audit capability.
- Existing `.copilottracking` JSON and validation conventions.
- EI plugin distribution boundary (`plugin.json`, `skills/`, `agents/`).

### Modify or reframe

- Reframe the existing EI workflow agent as a thin conversational entry.
- Put lifecycle order, preflight, state, checkpoint/resume, and result contract in `ei-graphics-workflow`.
- Update Phase 1 diagrams and prose from agent orchestration to workflow-controlled skills.
- Validate scope after every writing stage.
- Inject selected domain-pack knowledge into scope, plan, tasks, and validation without allowing packs to orchestrate.

### New EI capabilities

- `ei-graphics-workflow`: lifecycle controller.
- `ei-scope-resolver`: ProposedScope from story, vocabulary, domain packs, and targeted code search.
- `ei-scope-validator`: sealed-scope, full diff, protected-area, and scope-change validation.
- `ei-workflow-state`: schemas, resume, and iteration helpers.
- One curated Termination Drawing domain pack with vocabulary, constraints, tests, diagnostics, and machine-readable invariants.

## Risks and Limitations

- Generic SpecKit implementation can write outside task scope; external validation is mandatory.
- Reasoning-only invariants are advisory and require human domain review on risk paths.
- Wrong or missing domain pack selection must block or require an explicit reduced-automation approval.
- Missing CI evidence is not passing evidence.
- Dependency metadata does not install a plugin.
- Hook configuration is editable by the repository under supervision.
- MVP must exclude broad RAG, automatic vocabulary mining, multiple domains, multi-repository work, and unbounded autonomous repair.

## Exact Phase 1 Changes

1. Replace agent-to-agent lifecycle diagrams with thin agent -> workflow skill -> capabilities -> selected agents -> gates.
2. Make `.copilottracking/ei-graphics/<story-id>/` the explicit state location.
3. Define versioned, hashed ApprovedScope and a separate scope-change-request artifact.
4. Replace extension-filtered diff checking with complete name-status, rename-aware, untracked-path validation.
5. Run independent scope validation after all writing stages, not just implementation.
6. Define fail-closed states, gate ownership, and a three-attempt correction ceiling.
7. Define domain-pack selection, no-pack behaviour, and re-approval when selected packs change.
8. Add `skill` to the thin entry agent and document progressive-disclosure fallback.
9. Declare and preflight required cross-plugin dependencies.
10. Make IMPLEMENT and ITERATE distinct workflow paths sharing the original sealed scope.

## Final Answers

| Question | Answer |
|---|---|
| A. Remain a plugin? | Yes. It is the right distribution and integration boundary. |
| B. Thin conversational agent? | Yes. It collects input, invokes the workflow, and reports results. |
| C. Workflow as lifecycle orchestrator? | Yes. It owns order, gates, artifacts, and checkpoints. |
| D. Can R&D skills replace agent-to-agent lifecycle orchestration? | Yes. Skills and scripts provide reusable capabilities; selected agents remain reasoning workers. |
| E. Existing R&D direct reuse? | ADO, code-review, get-reviewresults, create-pr, git-commit, bug-diagnosis, speckit-bootstrap, plus SpecKit workers. |
| F. Cross-plugin skills? | R&D ADO, review, review-results, commit, PR, diagnosis; Core audit. |
| G. Where are agents necessary? | Specification, planning, tasks, implementation reasoning, and genuinely non-deterministic 2D diagnosis. |
| H. File-backed state supports complete lifecycle? | Yes. It is the proven repository mechanism and passed the POC. |
| I. Scope approval pause/resume? | Yes. Persist pending/approved/rejected state and resume only from a valid sealed approval. |
| J. IMPLEMENT and ITERATE as paths? | Yes. IMPLEMENT creates the contract; ITERATE recovers and preserves it on the same PR/branch. |
| K. What remains outside EI? | Generic ADO, review, audit, Git, PR, SpecKit, and diagnosis capabilities stay in R&D/Core. |
| L. Smallest production architecture? | Thin agent + workflow skill + existing EI skills + one domain pack + scope resolver/validator/state helpers + R&D/Core skills. |

## Recommendation

Adopt the workflow-first architecture. Keep EI Graphics as a plugin; add a thin entry agent; make `ei-graphics-workflow` the lifecycle owner; reuse R&D and Core capabilities across plugins; and make sealed artifact-backed scope plus deterministic validation the legacy-safety boundary. Review and approve this architecture before any production workflow implementation.