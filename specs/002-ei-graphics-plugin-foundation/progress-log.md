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
