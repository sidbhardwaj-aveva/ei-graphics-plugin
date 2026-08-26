# Progress Log: EI Graphics Plugin Initiative

## 2026-08-10

### Entry 1

- Established strategic direction:
  - Dedicated EI Graphics plugin
  - Orchestrator agent plus modular skills
  - Hard legacy safety gates
  - ADO bug workflow integration
  - EI domain ontology support

### Entry 2

- Scaffolded planning directory and baseline files in specs/002-ei-graphics-plugin-foundation.
- Formalized plan, tasks, risks, and decision records.
- Marked initiative state as planning complete, implementation pending.

### Entry 3

- Executed deterministic new-plugin scaffold script for `aveva-ei-graphics`.
- Confirmed plugin creation under `plugins/aveva-ei-graphics` and automatic update of `.github/plugin/marketplace.json`.
- Added required secondary registry entry in `.claude-plugin/marketplace.json`.
- Added `/plugins/aveva-ei-graphics/` line to `.github/CODEOWNERS`.
- Replaced sample template positioning with EI Graphics-specific scaffold intent.

### Entry 4

- Reconciled planning artifacts after status mismatch report.
- Updated plan current-status text to reflect implementation scaffold progress.
- Removed residual sample template artifacts from the plugin scaffold to keep an EI-only structure.
- Updated plugin manifest author to the repository owner.

### Entry 5

- Received workflow-discovery report produced from the real EI codebase.
- Confirmed that workflow and capability design must be refined from codebase evidence rather than assumptions.
- Updated planning artifacts to prioritize diagnosis, architecture guardrails, verification support, and PR review in Phase 1.

### Entry 6

- Locked the Phase 1 capability map to five workflow-supporting capabilities.
- Added future-state workflow steps and scaffold-to-capability migration guidance to the plan.
- Advanced task tracking from capability discovery into contract rewrite and gate-definition work.

### Entry 7

- Defined exact Phase 1 architecture and review gates in `workflow-gates.md`.
- Rewrote the plugin contracts to match the finalized Phase 1 capability set.
- Added `roadmap.md` to separate immediate plugin implementation from later workflow improvements.

### Entry 8

- Implemented deterministic `ei-layer-guard` script slice with architecture/review checks aligned to Phase 1 gates.
- Implemented deterministic `ei-bug-reproducer` script slice for evidence-backed diagnosis support.
- Implemented deterministic `ei-vocabulary-navigator` script slice with initial ontology-backed dataset.

### Entry 9

- Added focused Pester suites for the three implemented deterministic slices.
- Ran focused validation for:
  - `Invoke-EiLayerGuard.Tests.ps1`
  - `Invoke-EiBugReproducer.Tests.ps1`
  - `Invoke-EiVocabularyNavigator.Tests.ps1`
- Result: passing locally (14 passed, 0 failed).

### Entry 10

- Added `tools/Test-EiGraphicsSpecSync.ps1` hard-block gate.
- Added `tests/tools/Test-EiGraphicsSpecSync.Tests.ps1` unit tests for the new gate.
- Updated planning workspace operating model and workflow gates to require spec synchronization for EI plugin changes.

### Entry 11

- Implemented deterministic `ei-test-scaffolder` script slice at:
  - `plugins/aveva-ei-graphics/skills/ei-test-scaffolder/scripts/Invoke-EiTestScaffolder.ps1`
- Added focused unit tests at:
  - `tests/aveva-ei-graphics/skills/ei-test-scaffolder/scripts/Invoke-EiTestScaffolder.Tests.ps1`
- Updated `ei-test-scaffolder` contract status to reflect deterministic slice availability.
- Re-ran focused EI deterministic suites (test scaffolder + layer guard + bug reproducer + vocabulary navigator).
- Result: passing locally (17 passed, 0 failed).

### Entry 12

- Extended `ei-bug-reproducer` with a deterministic ADO bug-context retrieval path by bug ID.
- Added safe fallbacks that return `needs-manual-review` with explicit retrieval reasons when auth/context/data are missing.
- Implemented first deterministic `ei-pr-reviewer` slice for gate packaging:
  - `R-004` new TODO debt detection
  - `R-005` domain-risk SME escalation
  - `R-006` sanity-path expectation for high-risk changes
- Added focused tests for both new slices and re-ran EI deterministic suites.
- Result: passing locally (23 passed, 0 failed).

### Entry 13

- Wired `ei-graphics-workflow.agent` to consume deterministic outputs from:
  - `ei-bug-reproducer` (including ADO retrieval status and fallback reasons)
  - `ei-pr-reviewer` deterministic gate packaging
- Added explicit end-to-end output wiring rules for PR evidence packaging, including:
  - gate findings aggregation
  - readiness decision rules
  - structured `prEvidencePackage` fields

### Entry 14

- Implemented deterministic orchestrator runtime script:
  - `plugins/aveva-ei-graphics/agents/ei-graphics-workflow/scripts/Invoke-EiGraphicsWorkflow.ps1`
- Added focused orchestrator tests:
  - `tests/aveva-ei-graphics/agents/ei-graphics-workflow/scripts/Invoke-EiGraphicsWorkflow.Tests.ps1`
- Validated full focused EI deterministic suite including orchestrator, reviewer, bug reproducer, layer guard, vocabulary navigator, and test scaffolder.
- Result: passing locally (26 passed, 0 failed).

### Entry 15

- Confirmed delivery sequencing with EI team: continue current Phase 1 hardening plan before starting new adapted agents from RND references.
- Added explicit adaptation backlog tasks to the todo list:
  - T-034 adaptation blueprint definition
  - T-035 phased adaptation prioritization
  - T-036 EI-specific contracts for first adapted set
- Updated roadmap to add a dedicated adaptation-design phase that starts only after Phase 1 hardening stabilization.
- Logged formal sequencing decision in `decisions.md` (D-013).

### Entry 16

- Implemented T-012 hardening updates in `ei-bug-reproducer` for live ADO retrieval robustness:
  - bug ID format validation before live lookup
  - organization/project resolution from pipeline-style environment context
  - status-specific live retrieval fallback reasons for auth/not-found/throttle/server/request failure classes
- Extended focused unit coverage for invalid bug ID and environment-based context resolution behavior.
- Re-ran focused EI suites for bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (15 passed, 0 failed).

### Entry 17

- Extended T-012 fallback calibration with reason-based confidence caps and transient classification for live retrieval failures.
- Added and stabilized focused unit coverage for unavailable live retrieval scenarios with reason-specific assertions.
- Re-ran focused EI suites for bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (16 passed, 0 failed).

### Entry 18

- Attempted T-012 live environment calibration probe in local shell.
- Probe result: required ADO runtime context was not present (`hasOrg=False`, `hasProject=False`, `hasToken=False`), so no live retrieval request was executed.
- Added explicit prerequisite tracking so live calibration can resume immediately once org/project/token context is available.

### Entry 19

- Live calibration probe with organization, project, and PAT context returned an auth redirect pattern (`302` with HTML sign-in redirection) rather than a work item payload.
- Calibrated `ei-bug-reproducer` ADO retrieval to suppress federated auth redirects and classify redirect-loop signatures as `ado-auth-failed` instead of generic request failure.
- Re-ran focused EI suites for bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (16 passed, 0 failed).

### Entry 20

- Reviewed `aveva-rnd` shared Azure DevOps helpers (`Get-AdoToken.ps1`, `Invoke-AdoRestMethod.ps1`, and retry/common wrappers) to align EI connectivity behavior with proven patterns.
- Implemented EI-specific adaptation of that strategy in `ei-bug-reproducer`:
  - normalized trimmed org/project/bug inputs
  - optional Azure CLI token acquisition path when requested
  - `Invoke-WebRequest` response validation for redirect/auth and non-JSON payload patterns
  - explicit failure classification from HTTP status/content-shape before field extraction
- Re-ran focused EI suites for bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (16 passed, 0 failed).

### Entry 21

- Confirmed successful live ADO retrieval for a real work item using explicit org/project inputs with `-UseAzCliToken`.
- Retrieval output now resolves as:
  - `retrieval.status = retrieved`
  - `retrieval.reason = ado-live`
  - `authSource = az-cli-token`
- Marked T-012 as complete for the current scope.

### Entry 22

- Adapted RND-style URL-driven intake for EI bug reproducer so developers can provide a work item URL instead of manually supplying bug ID, organization, and project.
- Added deterministic URL parsing for supported Azure DevOps hosts and extraction of work item ID from common route shapes.
- Added focused tests for URL success path and missing-ID URL blocking behavior.
- Re-ran focused EI suites for bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (18 passed, 0 failed).

### Entry 23

- Implemented new EI skill `ei-azure-devops-cli-intake` (RND-pattern-inspired, EI-owned) for URL-driven work item context resolution and Azure CLI retrieval.
- Wired `ei-bug-reproducer` to consume the new intake skill path, so a work item URL can drive bug ID/org/project/description population before fallback retrieval.
- Added focused tests for the new skill and updated bug reproducer wiring assertions.
- Re-ran focused EI suites across intake, bug reproducer, orchestrator, and PR reviewer.
- Result: passing locally (21 passed, 0 failed).

## 2026-08-11

### Entry 24

- Continued agent development per sequencing lock by executing Phase 2A adaptation-design tasks.
- Completed EI adaptation blueprint and rollout prioritization for the first adapted contract set (ADO ingest, diagnosis-to-spec, EI code review).
- Authored new EI agent contracts:
  - `plugins/aveva-ei-graphics/agents/ei-ado-ingest.agent.md`
  - `plugins/aveva-ei-graphics/agents/ei-bug-diagnosis-to-spec.agent.md`
  - `plugins/aveva-ei-graphics/agents/ei-code-review.agent.md`
- Updated EI plugin README to include newly added agents and the URL intake skill in the capability map.
- Updated planning tracker statuses (T-034, T-035, T-036) to `Done`.

### Entry 25

- Implemented deterministic adapted-agent runtime for `ei-ado-ingest`:
  - `plugins/aveva-ei-graphics/agents/ei-ado-ingest/scripts/Invoke-EiAdoIngest.ps1`
- Added focused Pester coverage for the new runtime contract mapping:
  - `tests/aveva-ei-graphics/agents/ei-ado-ingest/scripts/Invoke-EiAdoIngest.Tests.ps1`
- Validated focused adapted-agent runtime suite locally.
- Result: passing locally (3 passed, 0 failed).

### Entry 26

- Implemented deterministic adapted-agent runtime for `ei-code-review`:
  - `plugins/aveva-ei-graphics/agents/ei-code-review/scripts/Invoke-EiCodeReview.ps1`
- Added focused Pester coverage for the EI code-review runtime:
  - `tests/aveva-ei-graphics/agents/ei-code-review/scripts/Invoke-EiCodeReview.Tests.ps1`
- Validated focused adapted-agent runtime suite locally.
- Result: passing locally (3 passed, 0 failed).

### Entry 27

- Implemented deterministic adapted-agent runtime for `ei-bug-diagnosis-to-spec`:
  - `plugins/aveva-ei-graphics/agents/ei-bug-diagnosis-to-spec/scripts/Invoke-EiBugDiagnosisToSpec.ps1`
- Added focused Pester coverage for the EI diagnosis-to-spec runtime:
  - `tests/aveva-ei-graphics/agents/ei-bug-diagnosis-to-spec/scripts/Invoke-EiBugDiagnosisToSpec.Tests.ps1`
- Validated focused adapted-agent runtime suite locally.
- Result: passing locally (3 passed, 0 failed).

### Entry 28

- Wired orchestrator (`Invoke-EiGraphicsWorkflow.ps1`) to call all three adapted agent runtimes:
  - `ei-ado-ingest` for URL-driven intake context resolution
  - `ei-code-review` for adapted review packaging with PR evidence
  - `ei-bug-diagnosis-to-spec` for implementation-handoff spec generation
- Added `WorkItemUrl` parameter to orchestrator for URL-driven entry.
- Adapted outputs returned under `result.adaptedAgents` in orchestrator output.
- Re-ran full EI suite across all agents and skills.
- Result: passing locally (43 passed, 0 failed).

### Entry 29

- Added git-diff auto-discovery to orchestrator: when `ChangedFiles` is empty, runs `git diff --name-only` against the base branch to self-populate changed `.cs`, `.csproj`, `.xaml`, `.json` files.
- Added `DiffBaseBranch` parameter (defaults to `origin/main`) for custom base branch control.
- Added focused test for auto-discovery using a temp git repo with two commits.
- Re-ran orchestrator suite.
- Result: passing locally (4 passed, 0 failed).

### Entry 30

- Fixed crash in ADO CLI intake when non-absolute URI (e.g. `'...'`) was passed as `WorkItemUrl`.
- Added `IsAbsoluteUri` and empty-host guard before host comparison.
- Full EI suite re-validated: 44 passed, 0 failed.

### Entry 31

- Added `plugins/aveva-ei-graphics/INSTRUCTIONS.md` with usage examples, parameter reference, workflow steps, test commands, commit convention, and full change log.

### Entry 32

- Fixed git-diff auto-discovery: relative paths from `git diff --name-only` are now resolved to absolute paths using `git rev-parse --show-toplevel`.
- Previously, layer guard and reviewer could not read files when the orchestrator was invoked from outside the repo root or from a different codebase.
- Orchestrator tests re-validated: 4 passed, 0 failed.

### Entry 33

- Closed a Phase A gap: `ei-graphics-workflow` documented stage transitions (`running`, `gateResult`, `complete`) with no deterministic script to perform them, which left `workflow-state.json` open to hand-editing by a non-deterministic agent.
- Added `plugins/aveva-ei-graphics/skills/ei-workflow-state/scripts/Set-EiWorkflowStage.ps1` as the only supported mutation path, with `start`, `complete` and `block` actions.
- Rules enforced deterministically: lifecycle order, `pending -> running -> complete`, mandatory passing gate result for gated stages, schema-valid required artifact before completion, and no advancement on a blocked run.
- Failed validation never mutates state: the candidate is checked against `workflow-state.schema.json` and `Validate-EiWorkflowState.ps1` before it is committed.
- Added `tests/aveva-ei-graphics/skills/ei-workflow-state/scripts/Set-EiWorkflowStage.Tests.ps1`; `ei-workflow-state` suite passing locally (48 passed, 0 failed).
- No lifecycle ordering, artifact registry, or Phase B/C behaviour was changed by this correction.

### Entry 34

- Started Phase B with the scope-safety layer's first tranche: `ei-scope-resolver`, the `proposed-scope` artifact, and the stage that produces it. Approval, ApprovedScope, scope hashing, scope-change requests, and `ei-scope-validator` are deliberately not in this tranche.
- Added `plugins/aveva-ei-graphics/skills/ei-scope-resolver/` with `SKILL.md`, `references/scope-policy.json`, `scripts/helpers/EiScopeResolver.ps1`, `scripts/New-EiProposedScope.ps1`, and `scripts/Test-EiProposedScope.ps1`.
- Added `plugins/aveva-ei-graphics/skills/ei-workflow-state/schemas/proposed-scope.schema.json` and activated the `proposed-scope` entry in `artifact-registry.json`, so the artifact can now be written and re-read through the state store.
- Determinism boundary: the model proposes candidate files, modules, symbols and evidence; the scripts decide what survives. Limits and rule severities live in `scope-policy.json`, not in prose.
- Conservative by construction: a proposal with no evidence, an unknown evidence id, an overlap with a declared protected area, or membership of an unresolved dependency is removed from the scope, recorded in `excluded`, and reported in `unresolved`. The scope never broadens silently.
- Status is derived, never asserted: any blocking finding gives `blocked`, any non-blocking finding gives `needs-review`, and only a clean run gives `resolved`. `Test-EiProposedScope.ps1` re-derives the status from the artifact's own findings, so an artifact edited after generation fails with `EISR-STATUS-MISMATCH`.
- Missing domain context can never produce a resolved scope (`EISR-CONTEXT-MISSING`), and a supplied-but-missing domain context path is an input error rather than a silent skip.
- Wired the `proposed-scope` stage into `ei-graphics-workflow/SKILL.md` using `Set-EiWorkflowStage.ps1`, and registered `ei-scope-resolver` in `required-capabilities.json` from Phase B. The lifecycle order was not changed, so a wired IMPLEMENT run still blocks on the unimplemented Phase C stages that precede this one.
- Added `tests/aveva-ei-graphics/skills/ei-scope-resolver/` covering clear, ambiguous, context-free, dependency-absorbing, over-broad, unevidenced and tampered scopes, plus the artifact round trip through the state store.
- Result: 24 new tests passing; full EI Graphics suite passing locally (122 passed, 0 failed).

### Entry 35

- Continued Phase B with the scope-sealing primitive: `ApprovedScope`, deterministic canonicalisation, SHA-256 content hashing, and the `scope-hash` gate. `scope-analysis`, the human approval orchestration, scope-change requests and `ei-scope-validator` are deliberately not in this tranche.
- Added `plugins/aveva-ei-graphics/skills/ei-workflow-state/schemas/approved-scope.schema.json` and flipped only the `approved-scope` entry in `artifact-registry.json` from reserved to active. The other reserved Phase B artifacts were left untouched.
- Added `plugins/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/helpers/EiScopeHash.ps1`, `scripts/New-EiApprovedScope.ps1`, and `scripts/Test-EiApprovedScopeHash.ps1`, placed in `ei-graphics-workflow` because the artifact registry already names it as the owner of `approved-scope`.
- Added `plugins/aveva-ei-graphics/skills/ei-workflow-state/scripts/Set-EiApprovedScopeSeal.ps1` so `approvedScopeHash` and `approvedScopeVersion` are still never hand-edited. It reuses the `Set-EiWorkflowStage.ps1` discipline: the candidate state is validated before it is committed, and a rejected seal leaves the state file byte-identical.
- Hash contract `ei-scope-canonical-v1`: object keys sorted ordinal, no whitespace between tokens, every array sorted by the ordinal value of its canonical elements, numbers in invariant round-trip form, JSON string escaping, and `generatedAt` removed before hashing. Everything else the resolver produced is inside the hash, so adding, removing or renaming a proposed path changes it.
- Sealing preserves rather than reconstructs: the ProposedScope payload is copied verbatim into `approved-scope.v{n}.json`. `needs-review` and `blocked` proposals are refused, an approver identity is mandatory, and approving again seals a new version while earlier versions are never rewritten.
- The seal reaches `workflow-state.json` only after the artifact has been written and has passed its own `scope-hash` gate against the persisted file, so a refused approval leaves both seal fields null.
- Corrected documentation drift found during this step: `ei-workflow-state/SKILL.md` and `ei-graphics-workflow/SKILL.md` still described `proposed-scope` as reserved and Phase B as not implemented, although Entry 34 had activated it in the registry.
- Added `tests/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/EiScopeHash.Tests.ps1` and `New-EiApprovedScope.Tests.ps1` covering hash stability across property order, whitespace and list order, hash change on added/removed/renamed paths, tamper detection, refusal of blocked and needs-review proposals, missing approver identity, version 1 then version 2 sealing, and the seal fields staying null until the gate passes.
- Result: 22 new tests passing; full EI Graphics suite passing locally (144 passed, 0 failed).

### Entry 36

- Completed Phase B by closing the two gates either side of the human decision, plus the orchestration between them: the `scope-analysis` approval-readiness gate, approval orchestration and the `awaiting-approval` pause, the `scope-validation` drift gate, and scope-change requests.
- Added `plugins/aveva-ei-graphics/skills/ei-scope-validator/` with `SKILL.md`, `references/approval-policy.json`, `scripts/helpers/EiScopeValidator.ps1`, `scripts/Invoke-EiScopeAnalysis.ps1`, `scripts/Test-EiScopeDrift.ps1`, and `scripts/New-EiScopeChangeRequest.ps1`.
- Added `plugins/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/Resolve-EiScopeApproval.ps1` as the only supported approval entry point, and `plugins/aveva-ei-graphics/skills/ei-workflow-state/scripts/Set-EiWorkflowApproval.ps1` so the pause is entered and left deterministically and `workflow-state.json` is still never hand-edited.
- Added `scope-change-request.schema.json` and `validation.schema.json`, and flipped the `scope-change-request` and `validation` entries in `artifact-registry.json` from reserved to active. Reserved Phase C/D/E artifacts were left untouched.
- Boundary held against `ei-scope-resolver`: `Test-EiProposedScope.ps1` judges artifact integrity (`EISR-*`), `Invoke-EiScopeAnalysis.ps1` judges approval readiness (`EISV-*`). Analysis runs after the resolver gate and never analyses a non-`resolved` scope into readiness, so the validator can only ever agree with a resolver finding.
- Readiness is data-driven: review thresholds, the per-file confidence floor, the implementation-area limit, the drift allow-list, and every rule severity live in `approval-policy.json`. The validator defers to `scope-policy.json` for hard limits rather than restating them, so the two policies cannot drift apart. Blocking findings (`EISV-SCOPE-NOT-RESOLVED`, `EISV-AREA-SPREAD`, `EISV-FILE-CONFIDENCE-LOW`, `EISV-SYMBOLS-MISSING`, `EISV-TEST-COVERAGE-GAP`, `EISV-RISK-HIGH`) make the verdict `block`; advisory findings are recorded for the approver.
- Approval is bound to what the approver saw: `approve` recomputes the canonical hash of the current `proposed-scope` and compares it with the `contentHash` recorded in the `scope-analysis` evidence. A proposal that changed after the human was asked is `EIWF-APPROVAL-STALE` and nothing is sealed. Analysis evidence is kept per stage so a later validating stage cannot overwrite what the approver was shown.
- Decisions cannot be taken out of order: `approve` and `reject` both require `awaiting-approval` (`EIWF-APPROVAL-NOT-REQUESTED`), an approval without a decider is `EIWF-APPROVER-MISSING`, and a rejection without a reason is refused because an unexplained refusal cannot be answered. A failed seal leaves the run paused (`EIWF-SCOPE-SEAL-FAILED`) rather than advancing.
- Drift validation judges only against a verified seal: `Test-EiScopeDrift.ps1` runs `Test-EiApprovedScopeHash.ps1` first, so an edited ApprovedScope is `EISV-SEAL-UNVERIFIED` and no comparison happens. Paths are classified protected-first, then in-scope by exact name, then against the allow-list, then out-of-scope; nothing is inferred from directory or proximity. An empty change set is `EISV-INPUT-INVALID`, not a pass.
- Scope-change requests widen a scope without ever editing a seal: versioned `scope-change-request.v{n}.json` recording `supersedes`, the sealed version and hash they were raised against, and refusals for protected areas, redundant paths, an unattributed requester, and an unverified seal. Raising a request mutates nothing; it is answered by re-resolving, re-analysing and sealing a new version. No lifecycle declares a `scope-change` stage, so requests are raised out of band against a blocked run.
- Added `tests/aveva-ei-graphics/skills/ei-scope-validator/scripts/Invoke-EiScopeAnalysis.Tests.ps1` (14) and `Test-EiScopeDrift.Tests.ps1` (18), `tests/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/Resolve-EiScopeApproval.Tests.ps1` (11), and `tests/aveva-ei-graphics/skills/ei-workflow-state/scripts/Set-EiWorkflowApproval.Tests.ps1` (9), covering readiness verdicts and per-rule severities, stale approval, out-of-order and unattributed decisions, the pause blocking stage starts, seal-first drift refusal, protected and out-of-scope classification, empty change sets, and request versioning and refusals.
- Result: 52 new tests passing; full EI Graphics suite passing locally (196 passed, 0 failed).

### Entry 37

- Re-verified the `scope-analysis` stage end to end against the contracts it depends on, rather than
  re-implementing it: the `scope-analysis` stage and gate in `lifecycle-implement.json`, the
  `ei-scope-validator` entry in `required-capabilities.json`, the active `validation` artifact in
  `artifact-registry.json`, `validation.schema.json`, `approval-policy.json`, and
  `Invoke-EiScopeAnalysis.ps1`. All were already present and consistent from Entry 36.
- Re-confirmed the boundary the two scope skills must hold: `Test-EiProposedScope.ps1` still judges
  only artifact integrity (`EISR-*` — schema, derived status, evidence links, protected overlap,
  absorbed dependencies, resolver hard limits) and carries no approval-readiness or review-breadth
  logic. Approval readiness and review breadth remain solely in `Invoke-EiScopeAnalysis.ps1`
  (`EISV-*`), driven by `approval-policy.json`, which defers hard limits to `scope-policy.json`.
- Closed the one real gap found: `plugins/aveva-ei-graphics/README.md` had drifted behind the
  implementation. Its skills table and structure tree omitted `ei-scope-resolver` and
  `ei-scope-validator`, Phase B was still recorded as `Not implemented`, and the known-limitations
  list still claimed only two artifacts had schemas and that no stage-transition writer existed.
- README limitations rewritten to the current facts: a wired IMPLEMENT run still stops at the
  unimplemented Phase C stages that precede the scope layer, six artifacts now have schemas and the
  rest still fail closed with `EIWF-SCHEMA-PENDING`, `New-EiWorkflowResult.ps1` still resolves
  version 1 only so a later sealed version is under-reported, and drift validation is still unwired
  because the writing stages are Phase D.
- No script, policy, schema, registry, lifecycle or test behaviour was changed by this entry.
- Result: full EI Graphics suite passing locally (196 passed, 0 failed); spec-sync gate PASS.

### Entry 38

- Closed the one functional Phase B gap found by the repository audit: a successful approval sealed
  the ApprovedScope and lifted the pause, but nothing ever completed the `scope-approval` stage, so
  it stayed `running` with `gateResult: not-run` and the run could not advance.
- `Resolve-EiScopeApproval.ps1` now carries the stage with the decision. `request` starts the stage
  before pausing, because a pause taken on a stage that was never started can never be completed.
  `approve` completes it with `-GateResult pass` after the seal and the grant. `reject` already
  blocked it. Every transition still goes through `Set-EiWorkflowStage.ps1` and
  `Set-EiWorkflowApproval.ps1`, so `workflow-state.json` is still never hand-edited.
- Fixed the versioned-artifact trap in the same change: the completion passes the version that was
  actually sealed rather than relying on the `-ArtifactVersion` default of 1, so an approval that
  produced `approved-scope.v2.json` is no longer validated against v1.
- Failure behaviour is unchanged in shape and now covers the stage too: a stale, unattributed or
  out-of-order decision never reaches the stage, a failed seal leaves the run paused and the stage
  open (`EIWF-SCOPE-SEAL-FAILED`), and a seal that cannot be recorded as a lifted pause or a
  completed stage reports `EIWF-APPROVAL-NOT-RECORDED` with the version it sealed.
- The approval suite now drives real stage transitions instead of bypassing them. It initialises
  state from a trimmed IMPLEMENT lifecycle fixture holding the Phase B segment
  (`proposed-scope` -> `scope-analysis` -> `scope-approval`) in its real order, and completes the two
  predecessors through `Set-EiWorkflowStage.ps1`. The fixture exists because the full lifecycle puts
  unimplemented Phase C stages ahead of the scope layer; start-order enforcement itself is not
  bypassed, and remains covered by the `Set-EiWorkflowStage` suite.
- Added three focused tests: the stage completes with a passing `human-approval` gate once the scope
  is sealed; a second approval completes against the version it sealed rather than version 1, proved
  by leaving an unreadable v1 in place; and a failed seal leaves the stage `running` with
  `gateResult: not-run` and the run `awaiting-approval`.
- Updated the `scope-approval` section of `ei-graphics-workflow/SKILL.md` so the documented sequence
  matches the script, including that the caller no longer completes this stage separately.
- No lifecycle, artifact registry, schema, policy or other skill behaviour was changed.
- Result: 3 new tests passing (approval suite 14 passed, 0 failed); full EI Graphics suite passing
  locally (199 passed, 0 failed).

## 2026-08-19

### Entry 39

- Made the Phase B safety layer reachable from a real IMPLEMENT run. Phase B was complete but
  unreachable: `ado-intake` and `domain-context` sit ahead of `proposed-scope` in
  `lifecycle-implement.json`, their artifacts were registered as `reserved` with no schema, and
  `Set-EiWorkflowStage.ps1` refuses to start a stage while an earlier one is incomplete and offers no
  `skip`. Every existing route to approval therefore ran on a trimmed lifecycle fixture. This tranche
  implements the minimum Phase C needed to close that gap and nothing more.
- Added the `ado` and `domain-context` schemas under `ei-workflow-state/schemas/` and flipped both
  registry entries from `reserved` to `active`. These are the only Phase A contract files touched, and
  the change is additive: no existing schema, gate, ordering rule or Phase B script behaviour changed.
- Added `ei-azure-devops-cli-intake/scripts/Invoke-EiAdoIntakeStage.ps1`. It is a stage wrapper, not a
  second intake: retrieval stays in `Invoke-EiAdoCliIntake.ps1`, and the wrapper only decides what the
  run may believe afterwards. `storyId` is taken from `workflow-state.json` rather than the caller, so
  an artifact cannot be written under an id the run was never initialised with. A retrieval that did
  not reach `retrieved` blocks the stage with the intake's own reason instead of sealing a partial
  story, and the `ado` schema admits only `retrieval.status: retrieved` so that refusal cannot be
  written around.
- Added `ei-vocabulary-navigator/scripts/Invoke-EiDomainContextStage.ps1` plus the data-driven
  `references/domain-pack-policy.json`. It follows the resolver's model: the caller proposes candidate
  terms, the script disposes of them. A term survives only if the story text mentions it, the navigator
  matched at least one URI, and its confidence clears the floor. Terms that do not survive are recorded
  in `unresolvedTerms`, and ambiguous terms in `ambiguities`, so the narrowing is auditable rather than
  silent, and the resolver still raises `EISR-AREA-AMBIGUOUS` from them.
- One design trap found and closed while wiring the navigator: calling it with the story text as
  `-ContextText` made every candidate term match the union of everything the story mentioned, so an
  ambiguous term such as `signal` came back carrying the full cable, terminal-arrangement and
  canvas-drawing packs. The stage now calls the navigator with the term alone and uses the story text
  only to prove the term belongs to this story.
- Neither stage asserts its own gate. Both write through `Write-EiWorkflowArtifact.ps1`, then evaluate
  `artifact-present` by reading the persisted artifact back through `Read-EiWorkflowArtifact.ps1`, and
  only then complete through `Set-EiWorkflowStage.ps1` with `-GateResult pass`. Every transition still
  goes through the state skill; `workflow-state.json` is still never hand-edited.
- Added 10 focused unit tests across the two stages, and one end-to-end test that runs the real
  `lifecycle-implement.json` and the real registry from `ado-intake` through `domain-context`,
  `proposed-scope`, `scope-analysis` and human approval to a sealed `approved-scope.v1.json`, asserting
  every stage completed with a passing gate and no blocks. It feeds the resolver from the two sealed
  Phase C artifacts rather than hand-written inputs, so the wiring is exercised rather than simulated.
  It carries the `Unit` tag as well as `Integration` because `tests/Invoke-PesterTests.ps1` filters on
  `Unit`, and an integration proof the standard gate never runs would prove nothing.
- Two existing tests used `ado` as their example of a reserved artifact and correctly failed once it
  became active. They now use `specification` (Phase D), so they prove the reserved-artifact rule
  against an artifact that is genuinely still unimplemented. The rule itself is unchanged.
- Deliberately not in this tranche: Phase D, any file-writing or implementation stage, ADO field
  coverage beyond what `Invoke-EiAdoCliIntake.ps1` already returns, and automatic derivation of
  candidate terms from story text.
- Result: 11 new tests passing; full EI Graphics suite passing locally (210 passed, 0 failed).

## 2026-08-21

### Entry 40

- Repository move: this repo (`ei-graphics-plugin`) is now the primary development repo for the
  plugin. The `aveva-agent-plugins` monorepo copy becomes downstream. Brought over the planning
  workspace (`specs/002-ei-graphics-plugin-foundation/`, including the Phase 1/2A design docs under
  `design/` that were never published inside `plugins/`), the spec-sync gate
  (`tools/Test-EiGraphicsSpecSync.ps1`), and a repository conventions file
  (`.github/copilot-instructions.md`) so a session opened on this folder inherits the same rules.
- Removed the four orphaned adapted agents (`ei-ado-ingest`, `ei-bug-diagnosis-to-spec`,
  `ei-code-review`, `ei-pr-reviewer`): their `.agent.md` definitions, their runtime scripts under
  `plugins/aveva-ei-graphics/agents/<name>/scripts/`, and their Pester suites under
  `tests/aveva-ei-graphics/agents/`. `ei-graphics.agent.md` is now the only agent; the lifecycle is
  owned by the `ei-graphics-workflow` skill, so the picker shows a single entry point.
  `plugin.json` points at the `agents/` folder rather than naming files, so it needed no change.
- Updated the plugin README (agent table, structure tree), `INSTRUCTIONS.md` (the "Running Tests"
  example pointed at a now-deleted path), and the root README (agent count, planning/status
  pointers, and the corrected relationship to the monorepo).
- One stale test disappeared with the removal: `Invoke-EiAdoIngest.Tests.ps1` still expected
  `invalid-work-item-id` where commit `127a870` had changed the reason to
  `missing-work-item-id-in-reference`. It went unnoticed because it belonged to the orphaned set.
- Historical references to the removed agents remain in this planning workspace by design; they are
  dated records, not current documentation.
- Result: full EI Graphics suite passing locally (201 passed, 0 failed, 22 files).

## 2026-08-24

### Entry 41

- Phase C second tranche: domain skill injection into the `domain-context` stage. The domain-context
  artifact now carries a `domainSkills` array alongside the existing vocabulary resolution fields.
  Phase B safety gates and contracts are unchanged; the lifecycle, schemas, and scope-resolver boundary
  all remain intact. Phase D is deliberately not started.
- Added `ei-vocabulary-navigator/references/domain-skill-registry.json`: a data-driven registry mapping
  domain IDs to their SKILL.md paths (relative to the plugin root) and the detection terms that trigger
  them in the story title and description. The registry follows the existing `references/` convention
  already used for `domain-pack-policy.json` and the scope policies. `termination-drawing` is the first
  and currently only registered domain.
- Added `ei-vocabulary-navigator/scripts/helpers/Read-EiDomainSkillContext.ps1`: a stateless helper
  that reads a SKILL.md and returns `{ domainId, displayName, summary, keyFiles[], keyFilesNote }`.
  Key Files are extracted from the first markdown table under the "Key Files" heading at any level.
  The parser skips code blocks, strips backtick quoting from file paths, ignores the header and
  separator rows, and stops at the next heading or at a non-table non-blank line. Returns empty
  `keyFiles` when no Key Files section is found.
- Extended `Invoke-EiDomainContextStage.ps1` with a new `-RegistryPath` parameter (defaults to the
  production registry). After vocabulary resolution passes its confidence gate, the script loads the
  registry, case-insensitively scans the combined story title and description for each domain's
  detection terms, and for every match calls `Read-EiDomainSkillContext.ps1` to load the SKILL.md.
  The resulting `domainSkills` array is added to the artifact. A missing or unparseable registry is a
  warning, not a block: vocabulary resolution alone is sufficient to pass the stage, so a domain-skill
  lookup failure never prevents the run from reaching scope resolution. Each domain skill entry carries
  `keyFilesNote` explicitly labelling Key Files as candidate evidence, not automatic scope. The scope-
  resolver receives the enriched domain-context artifact unchanged; nothing in `New-EiProposedScope.ps1`
  or downstream scripts was modified.
- Updated `domain-context.schema.json` to add an optional `domainSkills` array property with item
  schema enforcing `domainId`, `displayName`, `summary`, `keyFiles[]` (`file`+`purpose`), and
  `keyFilesNote`. The property is not in `required`, so pre-existing artifacts without it still pass.
- Added test fixture `tests/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-789012.json`:
  a termination-drawing story with detection terms (`TerminationDrawing`, `insertedTags`, `UpdateDrawing`,
  `EquipmentInserter`) in the title and description, and with `cable` and `terminal arrangement` in the
  description so the vocabulary gate passes without new vocabulary entries.
- Added candidate scope fixture `tests/aveva-ei-graphics/skills/ei-graphics-workflow/fixtures/candidate-scope-789012.json`
  for the integration test.
- Added `tests/aveva-ei-graphics/skills/ei-vocabulary-navigator/scripts/Invoke-EiDomainContextStage.DomainSkill.Tests.ps1`
  with five focused tests:
  1. Single-domain story: termination-drawing detected, Key Files injected, stage completes.
  2. Multi-domain story: two domains detected via custom registry when story contains terms from each.
  3. Ambiguous story: no domain terms match, `domainSkills` is empty, stage still passes.
  4. Key Files extraction: correct file/purpose pairs from the SKILL.md table; empty set when no
     Key Files section exists.
  5. Key Files not treated as scope: Key Files appear only in `domainSkills`, never in `domainPacks`;
     `keyFilesNote` is present on every domain skill entry.
- Added `tests/aveva-ei-graphics/skills/ei-vocabulary-navigator/scripts/Invoke-EiDomainContextStage.Integration.Tests.ps1`:
  one end-to-end test running the real lifecycle from ADO intake (story 789012) through domain-context
  (with domain skill detection), proposed-scope, scope-analysis, and human approval to a sealed
  `approved-scope.v1.json`. It asserts `domainSkills` in the artifact, Key Files absent from
  `domainPacks`, all stages complete with a passing gate, and zero blocks.
- Deliberately not in this tranche: Phase D, automatic extraction of candidate scope terms from Key
  Files, a second registered domain beyond `termination-drawing`, and any changes to the scope-resolver
  or approval policy.

### Entry 42

- Vocabulary mechanism removed from the domain-context path. Domain detection and domain knowledge
  discovery now come exclusively from `domain-skill-registry.json` → SKILL.md files. The vocabulary
  navigator (`Invoke-EiVocabularyNavigator.ps1`) and `vocabulary-map.json` are retained because
  `Invoke-EiBugReproducer.ps1` uses them directly; only the domain-context stage path was changed.
- `Invoke-EiDomainContextStage.ps1` rewritten: removed `-Terms` and `-PolicyPath` parameters, the
  `$navigatorPath` link, policy file read, vocabulary resolution loop, and the three blocking gate
  codes (`EIVN-NO-CANDIDATE-TERMS`, `EIVN-DOMAIN-PACK-UNRESOLVED`, `EIVN-CONFIDENCE-LOW`). The stage
  now reads the ADO artifact, matches story text against `domain-skill-registry.json`, calls
  `Read-EiDomainSkillContext.ps1` for each match, writes the artifact, and completes. No domain match
  is not a gate failure.
- `domain-context.schema.json` updated: `required` now `[schemaVersion, source, storyId, generatedAt,
  domainSkills]`; `source` enum changed from `["ei-vocabulary-navigator"]` to
  `["ei-domain-skill-registry"]`; removed `confidence`, `terms`, `domainPacks`, `ambiguities`,
  `unresolvedTerms`; `domainSkills` moved from optional to required.
- `New-EiProposedScope.ps1` updated: reads `domainSkills` array from the domain-context artifact,
  extracts `domainId` from each entry as `terms`, and sets `source` from the artifact.
  `EISR-CONTEXT-MISSING` now fires only when no domain-context file is passed (not when `terms` is
  empty). `EISR-AREA-AMBIGUOUS` removed entirely.
- All test files updated to remove `-Terms` parameter calls and old `ei-vocabulary-navigator` fixture
  shapes; integration and lifecycle tests assert `source = 'ei-domain-skill-registry'` and
  `domainContext.terms` contains domain IDs (e.g. `termination-drawing`) rather than vocabulary terms.
  Fixed stray closing braces in `Invoke-EiDomainContextStage.Tests.ps1` (parse error). Fixed fixture
  relative path for `work-item-789012.json` in the same file.
- Full test suite: 209 tests, 0 failures.

### Entry 43

- Human-readable output tranche. Added `Format-EiWorkflowSummary.ps1` as a deterministic
  presentation layer in `ei-graphics-workflow/scripts/`. The script reads the workflow state and
  available artifacts (ado, domain-context, proposed-scope, scope-analysis evidence, approved-scope)
  and builds a structured markdown summary with these sections: Story → Understanding → Relevant
  Area → Proposed Scope → Validation → Review Required (when awaiting approval) → Next Step.
- Internal terminology is kept out of the primary output: lifecycle phase labels, gate codes
  (`EISR-*`, `EISV-*`, `EIWF-*`), artifact file names, and block reason codes are never shown
  unless the caller opts in with `-Technical`, which appends a gate-result table and raw block
  records for developer debugging.
- Updated `ei-graphics.agent.md`: the "Reporting the contract" section is replaced by instructions
  to run `Format-EiWorkflowSummary.ps1` and present `Details.Summary` verbatim. The formatter
  is declared the canonical presentation layer. The "Implementation status" section no longer
  references phase labels.
- Added 13 focused Pester tests covering: required sections present, no internal terminology in
  primary output, awaiting-approval shows Review Required, blocked surfaces plain-language reason
  (not the code), validation lists completed checks, domain area populated from domain-context
  artifact, -Technical reveals diagnostic detail, missing state directory returns an error.
- Full test suite: 222 tests, 0 failures. Spec-sync gate: PASS.

## Tranche T-047 / T-048 / T-049 — scope-candidate stage + fast-fail prerequisite + tests

- Root cause of 21-minute stall in story 3408091: `candidate.json` was absent when the workflow
  advanced to `proposed-scope`, and the agent had to stop and wait for a manually-supplied file.
  No fast-fail or auto-generation existed.

- Added `scope-candidate` lifecycle stage between `domain-context` and `proposed-scope` in
  `lifecycle-implement.json`. Registered `candidate` artifact in `artifact-registry.json` with a
  new `candidate.schema.json`.

- Created `plugins/aveva-ei-graphics/skills/ei-scope-resolver/scripts/New-EiScopeCandidate.ps1`:
  deterministic generator that reads sealed `ado.json` and `domain-context.json` and writes a
  candidate.json evidence document. Evidence comes from story text, domain-skill key files, and
  a filename-term repository search. Key files that exist in the repository are promoted to
  `proposedFiles`; repository search hits appear in evidence only (model reviews before promoting).
  Conservative confidence baseline: 0.5 (with key files), 0.3 (story only).

- Updated `Validate-EiWorkflowPrerequisites.ps1`: added `-StateDir` parameter. Phase B+ check
  emits `EIWF-CANDIDATE-MISSING` when `candidate.json` is absent from StateDir, and
  `EIWF-CANDIDATE-INVALID` when it is present but malformed.

- Added `tests/aveva-ei-graphics/skills/ei-scope-resolver/scripts/New-EiScopeCandidate.Tests.ps1`
  (15 tests) and extended `Validate-EiWorkflowPrerequisites.Tests.ps1` with 6 candidate gate tests.
  Updated `ImplementLifecycleToApprovedScope.Tests.ps1` to run the `scope-candidate` stage using
  `New-EiScopeCandidate.ps1` rather than a hand-crafted fixture file.

- Updated `ei-scope-resolver/SKILL.md` and `ei-graphics-workflow/SKILL.md` to document the new
  stage, script, and evidence generation rules.

## Tranche T-050 — Session logging system + progressive stage capture

- Added `New-EiSessionLog.ps1` (`ei-graphics-workflow/scripts/`) — writes a per-run JSON session
  log to `.ei-session-logs/<storyId>/<sessionId>.json` (gitignored). Captures: timing per stage,
  gate results, block codes, token usage, estimated cost, and auto-generated improvement notes
  (slow stages, gate failures, correction attempts, interrupted runs).
- Added `Read-EiSessionLogs.ps1` — scans `.ei-session-logs/` and produces a Markdown improvement
  report. Supports `-StoryId` filter and `-Last N` limit.
- Added `session-log.schema.json` in `ei-workflow-state/schemas/` — JSON Schema (draft-07) for
  session log files.
- Stable filename (`<sessionId>.json`) enables the **progressive overwrite pattern**: writing with
  the same `$sessionId` after every `Set-EiWorkflowStage.ps1 -Action complete` call and at every
  BLOCK exit ensures interrupted sessions reflect the furthest stage reached, not just the Step 0
  start marker.
- Bugs fixed during implementation: DateTime locale-drift (ConvertFrom-Json converts UTC ISO 8601
  to locale-formatted string; fixed via `script:AsIsoUtc` + `[DateTimeOffset]::Parse`); gate
  detail was `""` instead of `null` when `blockReason` is null (fixed with explicit null check).
- Updated `ei-graphics-workflow/SKILL.md` Step 6 to document the progressive logging pattern:
  call `New-EiSessionLog.ps1` after **every** stage completion and BLOCK exit, not only once at
  the end of the workflow.
- Added 21 Pester tests for `New-EiSessionLog.ps1` and 10 for `Read-EiSessionLogs.ps1`.
  Full test suite: 289 tests, 0 failures. Spec-sync gate: PASS.

## Tranche T-051 — `ado-intake` resolves its work item reference from state

- Defect: `ei-graphics-workflow/SKILL.md` documents the stage call as
  `Invoke-EiAdoIntakeStage.ps1 -StateDir <dir> -Json`, but the script passed neither a URL nor an id
  to `Invoke-EiAdoCliIntake.ps1` unless the caller supplied one. The documented call therefore always
  blocked the run with `EIAI-INTAKE-FAILED (missing-work-item-url-or-id)` even though
  `workflow-state.json` already carried `storyRef` and `storyId`.
- Observed cost on story 4983245: three consecutive blocked `ado-intake` attempts, an attempted
  `Set-EiWorkflowStage.ps1 -Action unblock` (no such action), and a recovery via
  `Initialize-EiWorkflowState.ps1 -Force` that discarded the run before the fourth attempt succeeded
  with an explicit `-WorkItemUrl`.
- Fix: `Invoke-EiAdoIntakeStage.ps1` resolves an omitted reference from workflow state — `storyRef`
  first, then `storyId` — and records the origin in `Details.ReferenceSource`
  (`parameter` | `workflow-state.storyRef` | `workflow-state.storyId`). An explicit
  `-WorkItemUrl`/`-WorkItemId` still takes precedence, so overrides are unchanged.
- Not a retrieval problem: `az` and `Invoke-EiAdoCliIntake.ps1` worked on every attempt that was
  given a reference, so swapping in the `aveva-rnd` ADO intake would not have changed the outcome.
- Added three tests to `Invoke-EiAdoIntakeStage.Tests.ps1` (storyRef fallback, storyId fallback,
  explicit parameter precedence). Documentation updated in `ei-azure-devops-cli-intake/SKILL.md` and
  the `ado-intake` stage section of `ei-graphics-workflow/SKILL.md`.
- Known limitation left open: a blocked stage has no retry path. `Set-EiWorkflowStage.ps1` allows
  only `start | complete | block`, `start` requires a `pending` stage and an `in-progress` workflow,
  and `state.blocks` is append-only while `workflow-state.json` records no per-stage attempt count —
  so repeated failures of the same stage are not observable after the fact.

## Tranche T-052 — one-call workflow bootstrap

- Problem: starting a run cost seven separate script invocations — `Initialize-EiWorkflowState.ps1`,
  `New-EiSessionLog.ps1`, `Validate-EiWorkflowPrerequisites.ps1`, then `start` and `complete` on both
  `preflight` and `state-init`. In an agent host each invocation is its own approval prompt, so the
  user approved seven terminal commands before the run touched the story at all.
- Fix: added `Start-EiWorkflowRun.ps1` to `ei-graphics-workflow/scripts/`. It runs the whole sequence
  in one process and returns one contract with `StateDir`, `SessionId`, `Resumed`, `StagesCompleted`,
  `NextStage` and the full `Prerequisites` detail.
- Consolidation is not permission to skip. Every underlying script is still called and is still the
  sole owner of its step; in particular `workflow-state.json` is still mutated only through
  `Set-EiWorkflowStage.ps1`.
- Fails closed. A failing `prerequisites` gate blocks `preflight` with `EIWF-PREREQUISITES` and
  returns `EIWF-BOOTSTRAP-PREFLIGHT`, rather than leaving a run that looks startable. State that
  cannot be initialised returns `EIWF-BOOTSTRAP-STATE`. Only the session-log write is non-fatal,
  because a missing local log must never stop a run.
- Idempotent. Stages already `complete` are skipped, so re-running after an interruption preserves
  `startedAt` and does not re-evaluate a gate.
- `-StateDir` is deliberately not forwarded to the preflight: from Phase B that makes it assert
  `candidate.json`, which by definition does not exist at bootstrap time. That check belongs to the
  later re-validation before `proposed-scope`.
- `ITERATE` stops after `preflight`. Its second stage, `state-recovery`, also recovers branch and PR
  evidence — more than the bootstrap performed — so it stays `pending` for `ei-workflow-state`.
- Also closes the documentation gap behind T-051's stage-order block: `SKILL.md` told the agent to
  run the preflight and init scripts but never to record the matching transitions, which is why
  `ado-intake` refused to start behind a `pending` `preflight`.
- Added `Start-EiWorkflowRun.Tests.ps1` (7 tests): single-call stage recording, start-marker
  contents, idempotent re-run with preserved `startedAt`, later-phase gaps as warnings, fail-closed
  block on a missing required capability, rejected story id, and the `ITERATE` stop point.
- Documentation: `ei-graphics-workflow/SKILL.md` Steps 0–3 restructured around the single call
  (Step 0 path choice, Step 1 bootstrap, Step 2 what it performs, Step 3 how to read the result),
  and `INSTRUCTIONS.md` now documents `Start-EiWorkflowRun.ps1` in place of the individual scripts.

## Tranche T-053 — deterministic work item reference parsing, fixed org and project

- Problem 1 — the agent read the id off the link. The real input is always a pasted markdown link
  such as `[Bug 4983245 SR350 - <title>](https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_workitems/edit/4983245)`,
  but nothing turned that into `-StoryId`. The model did it, so the first deterministic value in the
  whole run came out of a non-deterministic step.
- Problem 2 — a short link corrupted the project. `Resolve-FromWorkItemUrl` took URL segment 1 as the
  project unconditionally, so `https://dev.azure.com/AVEVA-VSTS/_workitems/edit/4983245` — the form
  ADO emits when the project is omitted — sealed `project = "_workitems"` into `ado.json`.
- Problem 3 — the link decided the org and project. They were resolved from the URL first and only
  fell back to the AVEVA defaults, so the same story pasted from two different links could be
  recorded two different ways.
- Problem 4 — the markdown-link regex was anchored `^...$`, so a link with any prose around it was
  discarded and the run silently fell back to reading an id out of the label.
- Fix: added `ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1` as the single owner
  of reference parsing (`Split-EiWorkItemReference`, `Get-EiWorkItemIdFromLabel`,
  `Get-EiAdoUrlWorkItemId`, `Resolve-EiWorkItemReference`) and of the fixed org/project constants.
  `Invoke-EiAdoCliIntake.ps1` now delegates to it instead of carrying its own four parsing
  functions.
- Org and project are fixed: `-Organization`/`-Project`, then `AZDO_ORG`/`AZDO_PROJECT`, then
  `AVEVA-VSTS` / `Dabacon Products`. The URL is deliberately not a tier. Every EI Graphics story
  lives in the same project, so a link can no longer move a run somewhere else or seal a reserved
  `_`-prefixed segment as the project.
- `Start-EiWorkflowRun.ps1` dot-sources the same helper, so `-StoryId` may now be left empty when
  `-StoryRef` carries the link. The id is derived by script, and `storyRef` is normalised to a bare
  URL so `Format-EiWorkflowSummary.ps1` never nests one markdown link inside another.
- Failure reasons are unchanged in spirit and now documented as a table: `missing-work-item-url-or-id`
  (blocked), `missing-work-item-id-in-url`, `missing-work-item-id-in-reference`,
  `unsupported-work-item-url-host`. `invalid-work-item-id` and `missing-organization-or-project` were
  removed from the intake because the resolver can no longer produce either.
- Tests: 5 new intake tests (fixed org/project despite the URL, reserved `_workitems` segment, link
  inside prose, non-ADO bare URL) and 3 new bootstrap tests (id derived from a pasted link as
  `-StoryRef` and as `-StoryId`, non-numeric story id left alone). Existing intake, stage and bug
  reproducer assertions updated to the pinned org/project. Full suite: 307 passed, 0 failed.


## Tranche T-054 — the preflight gate leaves evidence

- The problem: `Validate-EiWorkflowPrerequisites.ps1` computed a verdict that lived only in memory.
  It surfaced in `Details.Prerequisites` and was never written anywhere, so the `gateResult: pass`
  recorded against the `preflight` stage was the caller's word rather than a fact. A run stalled on
  `EIWF-STAGE-ORDER` could be freed by hand-completing `preflight` for an evaluation that never ran.
- The fix reuses the mechanism already in place instead of adding a second one. `preflight` now owns
  a `prerequisites` artifact — `prerequisites.schema.json`, an entry in `artifact-registry.json`,
  and `artifact: "prerequisites"` in both lifecycle files — so the existing artifact check in
  `Set-EiWorkflowStage.ps1 -Action complete` refuses the stage without schema-valid evidence.
- `Start-EiWorkflowRun.ps1` writes the file on both paths. A blocked gate is recorded too, with
  `verdict: block`, so the reason a run stopped survives the process. If the gate passes but the
  evidence cannot be written the run stops with `EIWF-BOOTSTRAP-EVIDENCE` rather than continuing
  toward a stage it can no longer complete.
- `Invoke-EiAdoIntakeStage.ps1` was surfacing raw `EIWF-STAGE-ORDER` text with no way out. It now
  attaches `Details.Remediation` naming `Start-EiWorkflowRun.ps1` and states that hand-completing
  `preflight` is not a substitute.
- Existing state files that record `artifact: null` on `preflight` still validate: verified that
  `Validate-EiWorkflowState.ps1` does not cross-check state stages against the lifecycle file.
- Blast radius: every harness that hand-completed `preflight` was doing exactly what is now
  forbidden. A shared `tests/aveva-ei-graphics/helpers/EiTestPreflight.ps1` writes the evidence, and
  eight harnesses were migrated to it. 3 new bootstrap tests cover the pass verdict, the block
  verdict, and the refusal of a hand-completed preflight. Full suite: 310 passed, 0 failed.


## Tranche T-057 — acceptance criteria and its images reach the run

- The problem: `Invoke-EiAdoCliIntake.ps1` built `descriptionText` from title, description and the
  two repro-steps fields, and scanned only description and repro steps for `<img>` tags.
  `Microsoft.VSTS.Common.AcceptanceCriteria` was in neither list. On story 3774939 that field is
  21,326 characters and carries the only screenshot, against a 486-character description, so the
  run sealed a near-empty story and reported "No accessible images were found in the work item".
- The knock-on cost was paid by the user. With the criteria missing from `ado.json`, the agent went
  back to the CLI with ad-hoc `az boards work-item show` calls and HTML-stripping one-liners, and in
  an agent host each attempt is a separate approval prompt.
- The fix is one ordered content-field list — `System.Title`, `System.Description`,
  `Microsoft.VSTS.Common.AcceptanceCriteria`, `Microsoft.VSTS.TCM.ReproSteps`, `System.ReproSteps` —
  feeding both the plain text and the image scan. A field can no longer be read for its prose but
  skipped for its images, which is the shape of the defect that was just fixed.
- Attachment URLs are HTML-decoded before they are returned, so an `&amp;` in the query no longer
  truncates the download, and `src` is matched with either quote style.
- Verified by replaying the real 3774939 payload through the intake: `descriptionText` goes from
  ~500 to 3,584 characters and one attachment URL is found.
- Approval cost addressed on the other side too. `ei-graphics-workflow/SKILL.md` gained a
  "One invocation, one line" rule and `ei-graphics.agent.md` a "Running scripts" section: each call
  is sent as a single-line command using the absolute script path, never a backtick-continued list
  and never a variable assignment plus the call in one submission, because those forms frequently
  return no captured output and the retry costs another prompt. The agent is also told to view
  `attachments[].localPath` and never to re-fetch the work item.
- Tests: 4 new intake tests (acceptance criteria in the text, an image found in acceptance criteria,
  an HTML-encoded URL decoded, an image repeated across fields deduplicated). Full suite: 314
  passed, 0 failed.


## Tranche T-058 — the discussion thread reaches the run

- The problem: `az boards work-item show` does not return work item comments at all, so nothing the
  team posted after the story was written was ever visible to a run. This is not a marginal gap.
  On bug 4965976 the first two comments are the author writing "The description and details for
  this are incorrect" and then "I've updated the details to explain the problem correctly" — a run
  reading only the fields would have faithfully implemented a story its own author had retracted.
- `Invoke-EiAdoCliIntake.ps1` now fetches `_apis/wit/workItems/<id>/comments` through `az rest`
  with `--resource 499b84ac-1321-427f-aa17-267ca6975798`, so the existing `az` session supplies the
  token and no secret is read, held or printed by the script.
- Comments are normalised to `{ id, author, createdDate, text }` and ordered by id, which makes the
  thread chronological and the sealed artifact byte-identical across runs. `createdDate` is
  formatted as an invariant `yyyy-MM-ddTHH:mm:ssZ` string: `ConvertFrom-Json` converts an ISO-8601
  string into a `DateTime`, and casting that back to a string renders it in the current culture,
  which would otherwise make the artifact machine-dependent.
- Comment HTML is scanned for images on the same path as the story fields, and every attachment
  now records a `source` of `field:<FieldName>` or `comment:<id>`. A picture can therefore be
  attributed to the person who posted it instead of appearing as an unexplained screenshot.
- Retrieval is best-effort and never blocks the stage, but the outcome is always reported, because
  an unread thread and an empty thread are not the same claim:
  `retrieved` | `skipped` (`mock-run-without-comments`) | `unavailable` (`comments-request-failed`,
  `comments-invalid-json`, `mock-comments-invalid`). `Invoke-EiAdoIntakeStage.ps1` warns on
  `unavailable` and seals the status either way.
- `ado.schema.json` gained `comments`, `commentRetrieval` and `attachments[].source`. All three are
  optional, so artifacts sealed before this tranche still validate.
- `ei-graphics.agent.md` gained a **Comments** block in the understanding template. The agent must
  summarise the thread chronologically with attribution, call out explicitly anything that changes,
  narrows or contradicts the description or acceptance criteria, state unanswered questions, never
  report an unread thread as an empty one, and name the field or comment each image came from.
- Verified live: 4965976 returns 3 comments and 5 images, one of which came from a comment.
- Tests: 7 new intake tests (chronological order, invariant timestamp, comment image attribution,
  field attribution, unavailable, skipped, empty-but-retrieved) and 2 new stage tests (thread
  sealed into the artifact, warning plus `unavailable` when it cannot be read). Full suite: 323
  passed, 0 failed.
