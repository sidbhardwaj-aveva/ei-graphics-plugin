# Current Status: EI Graphics Plugin Initiative

## Snapshot

- Date: 2026-08-24
- Phase: Phase C presentation tranche complete; Phase D not started
- Overall status: In progress
- Primary repo: `ei-graphics-plugin` (the `aveva-agent-plugins` monorepo copy is downstream)

## Completed so far

1. Delivery model selected: dedicated plugin with an orchestrator agent plus focused skills.
2. High-level scope aligned to:
   - ADO bug intake and workflow integration
   - Legacy-safe gating before fix recommendation
   - EI domain knowledge for object semantics (loop, wire, cable, related terms)
3. Planning workspace created under specs/002-ei-graphics-plugin-foundation.
4. Core planning artifacts scaffolded for execution control.
5. Plugin scaffold created under plugins/aveva-ei-graphics using repository script.
6. Plugin registries updated:
   - .github/plugin/marketplace.json (via script)
   - .claude-plugin/marketplace.json (manual sync)
7. CODEOWNERS entry added for /plugins/aveva-ei-graphics/.
8. Initial EI Graphics agent and skill contracts scaffolded.
9. Residual hello-world sample artifacts removed from the EI Graphics plugin scaffold.
10. Plugin manifest creator set to the repository owner.
11. Evidence-backed workflow discovery completed from the real EI codebase.
12. Phase 1 capability map locked from workflow evidence.
13. Exact architecture and review gates documented for Phase 1.
14. Scaffolded contracts rewritten to match the finalized Phase 1 capability set.
15. A phased roadmap added to separate immediate plugin work from later workflow improvements.
16. First deterministic script slices implemented for:
   - `ei-bug-reproducer`
   - `ei-layer-guard`
   - `ei-vocabulary-navigator`
17. Initial ontology-backed vocabulary dataset added for vocabulary navigation.
18. Focused Pester suites added for the deterministic slices and passing locally (14/14).
19. Spec synchronization hard-block gate added so EI plugin changes require corresponding updates in this planning folder.
20. Deterministic `ei-test-scaffolder` script slice implemented with contract-compliant output and dependency extraction heuristics.
21. Focused Pester validation extended to 4 EI skill suites and passing locally (17/17).
22. `ei-bug-reproducer` extended with an ADO live retrieval path by bug ID, with explicit safe fallback to manual review when auth/context/data are missing.
23. First deterministic `ei-pr-reviewer` slice implemented for gate packaging of R-004 (TODO debt), R-005 (domain-risk escalation), and R-006 (sanity-path expectation).
24. Focused Pester validation extended to EI bug reproducer, reviewer, and supporting deterministic suites (23/23 passing).
25. Workflow orchestrator contract wired to package bug retrieval, review findings, and PR evidence into a structured end-to-end output.
26. Reuse policy established to reference `plugins/aveva-rnd` patterns while keeping EI agents and skills independently authored for domain-specific behavior.
27. Deterministic `ei-graphics-workflow` orchestration script implemented for end-to-end PR evidence packaging across bug, vocabulary, architecture, verification, and review outputs.
28. Focused EI deterministic suites now include orchestrator runtime coverage and pass locally (26/26).
29. Sequencing lock applied: continue active Phase 1 hardening first; begin RND-pattern-based adapted-agent design only after hardening stabilization.
30. T-012 hardening slice added for ADO retrieval context resolution and deterministic fallback reasons, with focused EI suites passing (15/15).
31. T-012 calibration extended with reason-based confidence caps and transient classification for live retrieval failures, with focused EI suites passing (16/16).
32. Live ADO probe calibration identified auth redirect behavior (302 to sign-in); bug reproducer now suppresses federated redirect and maps redirect loops to auth failure classification.
33. EI bug reproducer now follows RND-style ADO request strategy: explicit content-type/redirect validation, structured response classification, optional Azure CLI token fallback, and context normalization.
34. Live ADO retrieval now succeeds with explicit org/project context and Azure CLI token fallback (`authSource=az-cli-token`, `retrieval.reason=ado-live`) against a real work item.
35. EI bug reproducer now accepts Azure DevOps work item URLs and auto-resolves bug ID, organization, and project context for URL-driven entry.
36. Added `ei-azure-devops-cli-intake` skill and wired `ei-bug-reproducer` to consume URL-driven ADO context and description retrieval via the new intake path.
37. Defined EI-specific adapted-agent contract set for RND-pattern-inspired Phase 2A expansion.
38. Authored first adapted agent contracts for `ei-ado-ingest`, `ei-bug-diagnosis-to-spec`, and `ei-code-review`.
39. Updated plugin README and planning task tracker to reflect adaptation rollout prioritization and contract readiness.
40. Implemented deterministic `ei-ado-ingest` runtime script to normalize ADO URL/ID intake output for agent-level consumption.
41. Added focused Pester coverage for `ei-ado-ingest` runtime contract mapping and validated locally (3/3 passing).
42. Implemented deterministic `ei-code-review` runtime script to package deterministic reviewer findings into the adapted EI code-review contract.
43. Added focused Pester coverage for `ei-code-review` runtime and validated locally (3/3 passing).
44. Implemented deterministic `ei-bug-diagnosis-to-spec` runtime script to convert diagnosis evidence into implementation-handoff spec sections.
45. Added focused Pester coverage for `ei-bug-diagnosis-to-spec` runtime and validated locally (3/3 passing).
46. Wired orchestrator to call all three adapted runtimes (`ei-ado-ingest`, `ei-code-review`, `ei-bug-diagnosis-to-spec`) for end-to-end adapted flow.
47. Added `WorkItemUrl` parameter to orchestrator for URL-driven intake entry point.
48. Full EI suite validated locally (43/43 passing).
49. Added git-diff auto-discovery to orchestrator so `ChangedFiles` self-populates from `git diff --name-only` when not supplied.
50. Added `DiffBaseBranch` parameter (defaults to `origin/main`) to control the diff base.
51. Added focused test for auto-discovery path using a temp git repo; full EI suite validated (4/4 orchestrator, 44/44 total).
52. Fixed crash on non-absolute URIs in ADO CLI intake (e.g. `'...'` input).
53. Added `INSTRUCTIONS.md` with usage, parameters, workflow steps, test commands, commit convention, and full change log.
54. Fixed git-diff auto-discovery to resolve relative paths to absolute using `git rev-parse --show-toplevel`, so layer guard and reviewer can read files from any working directory.
55. Phase A correction: added `Set-EiWorkflowStage.ps1` so workflow stage transitions are deterministic and `workflow-state.json` is never hand-edited, with focused Pester coverage for the no-mutation-on-failure invariant.
56. Phase B first tranche: added the `ei-scope-resolver` skill, the `proposed-scope` artifact and schema, a data-driven scope policy, and the deterministic proposed-scope gate. Scope narrowing is script-decided: anything without evidence, inside a protected area, or belonging to an unresolved dependency is dropped and recorded, and the artifact status is derived, never asserted. Approval, ApprovedScope, hashing, scope-change requests, and `ei-scope-validator` remain out of scope for this tranche.
57. Phase B sealing primitive: added the `approved-scope` artifact and schema, `ei-scope-canonical-v1` canonicalisation with SHA-256 content hashing, `New-EiApprovedScope.ps1`, the read-only `Test-EiApprovedScopeHash.ps1` gate, and `Set-EiApprovedScopeSeal.ps1` so the seal fields in `workflow-state.json` are still never hand-edited. Sealing preserves the approved scope verbatim, refuses `blocked` and `needs-review` proposals, requires an explicit approver, versions every approval without rewriting earlier ones, and records the seal only after the artifact passes its own hash gate. `scope-analysis`, human approval orchestration, scope-change requests, and drift validation remain out of scope for this tranche.
58. Phase B completion tranche: added the `ei-scope-validator` skill with the `scope-analysis` approval-readiness gate, the `scope-validation` drift gate, and the append-only `scope-change-request` artifact, plus `Resolve-EiScopeApproval.ps1` and `Set-EiWorkflowApproval.ps1` for approval orchestration and the `awaiting-approval` pause. Readiness thresholds and rule severities are data in `approval-policy.json`, and the validator defers to the resolver policy for hard limits rather than restating them. An approval is bound to the scope that was analysed: `approve` recomputes the canonical hash and refuses to seal a proposal that changed after the human was asked (`EIWF-APPROVAL-STALE`). Drift is judged only against a verified seal, by exact path, so proximity never authorises a write, and an empty change set is an input error rather than a pass. Out-of-scope drift is answered by a versioned scope-change request and a new sealed version, never by editing a seal. Phase B is now complete; Phases C, D and E remain unimplemented.
59. `scope-analysis` re-verified against its lifecycle stage, capability entry, artifact registry, schema and policy, with the resolver/validator boundary confirmed intact: `Test-EiProposedScope.ps1` carries only artifact-integrity rules (`EISR-*`) and all approval-readiness and review-breadth judgement stays in `Invoke-EiScopeAnalysis.ps1` (`EISV-*`). The only gap found was documentation drift in the plugin README, which still listed Phase B as not implemented, omitted both scope skills, and described limitations that Entries 33–36 had already removed. README corrected; no script, policy, schema, registry, lifecycle or test behaviour changed.
60. Phase B stage-completion gap closed: a successful approval now completes the `scope-approval` stage instead of leaving it `running` with an unrecorded gate. `Resolve-EiScopeApproval.ps1` starts the stage when the decision is requested and completes it with a passing `human-approval` gate after sealing, against the version it actually sealed rather than the `-ArtifactVersion` default of 1. A failed seal still leaves the run paused and the stage open. Transitions remain confined to `Set-EiWorkflowStage.ps1` and `Set-EiWorkflowApproval.ps1`, and no lifecycle, registry, schema or policy changed.
61. Phase C first tranche — the Phase B safety layer is now reachable from a real IMPLEMENT run. Phase B was complete but unreachable: `ado-intake` and `domain-context` sit ahead of `proposed-scope` in the lifecycle, their artifacts were `reserved` with no schema, and stage ordering offers no `skip`, so every route to approval ran on a trimmed lifecycle fixture. Added the `ado` and `domain-context` schemas, activated both registry entries, and added `Invoke-EiAdoIntakeStage.ps1` and `Invoke-EiDomainContextStage.ps1` as stage wrappers over the existing intake and navigator scripts rather than second implementations. Both stages fail closed: a retrieval that did not reach `retrieved` blocks the run instead of sealing a partial story, and a domain context that resolves too little blocks instead of handing the resolver a thin context. Candidate terms are proposed by the caller and disposed of by `domain-pack-policy.json` — a term survives only if the story mentions it, the navigator matched a URI, and confidence clears the floor — with the rest recorded in `unresolvedTerms` and `ambiguities`. Neither stage asserts its gate: `artifact-present` is evaluated by reading the persisted artifact back. The executable path is now `preflight → state-init → ado-intake → domain-context → proposed-scope → scope-analysis → scope-approval` on the real `lifecycle-implement.json`, proved end to end to a sealed `approved-scope.v1.json`. Phase D, all file-writing and implementation stages, and the rest of Phase C remain unimplemented.
62. Phase C second tranche — domain skill injection into the `domain-context` stage. The `domain-context` artifact now carries a `domainSkills` array alongside the existing vocabulary resolution fields. A data-driven `domain-skill-registry.json` in `ei-vocabulary-navigator/references/` maps domain IDs to their SKILL.md paths and detection terms. After vocabulary resolution passes its gate, the stage scans the story title and description for domain detection terms (case-insensitive), loads each matched SKILL.md via `Read-EiDomainSkillContext.ps1`, extracts the Key Files section, and injects the result into the artifact. Key Files are labelled explicitly as candidate evidence via `keyFilesNote`; they never bleed into `domainPacks` and the scope-resolver is unchanged. A missing or unparseable registry is a warning, not a block. `domain-context.schema.json` updated with an optional `domainSkills` property. Added five focused tests (single-domain, multi-domain, ambiguous, Key Files extraction, Key Files not as scope) and one end-to-end integration test from ADO intake through approved-scope sealing using the termination-drawing story fixture. Phase D and automatic term extraction from Key Files remain unimplemented.
63. Vocabulary mechanism removed from the domain-context path. Domain detection now uses only `domain-skill-registry.json` → SKILL.md. The vocabulary navigator and `vocabulary-map.json` are retained for the bug reproducer. `domain-context.schema.json` now requires `domainSkills` and no longer contains vocabulary fields. `EISR-AREA-AMBIGUOUS` and the three vocabulary gate codes removed. `New-EiProposedScope.ps1` reads `domainSkills` and uses domain IDs as `terms` in the proposed-scope `domainContext`. Full suite: 209/209 tests passing.
64. Human-readable output tranche. Added `Format-EiWorkflowSummary.ps1` as a deterministic presentation layer that converts the workflow state and available artifacts into a structured markdown summary with these sections: Story → Understanding → Relevant Area → Proposed Scope → Validation → Review Required (when awaiting approval) → Next Step. Internal terminology (lifecycle phase labels, gate codes, artifact file names, block reason codes) is kept out of the primary output; an opt-in `-Technical` flag appends a gate-result table and block codes for developer debugging. Updated `ei-graphics.agent.md` to use this formatter as the canonical presentation layer rather than translating status codes into prose inline. The agent's "Implementation status" section no longer references phase labels. Added 13 focused Pester tests covering all key output scenarios: required sections present, no internal terminology in primary output, awaiting-approval shows Review Required, blocked surfaces plain-language reason, validation lists completed checks, domain area populated from domain-context, -Technical reveals diagnostic detail. Full suite: 222/222 tests passing.

## Open decisions

1. Confirm first pilot team members (developers and QA).
2. Confirm minimum required regression suite for hard-block gates.
3. Confirm ontology authority sources (docs, SME sign-off, examples).
4. Confirm confidence thresholds and ambiguity handling policy for vocabulary navigation.

## In progress / not started

- In progress: deterministic script implementation for the Phase 1 capability set (all 5 capabilities started with initial deterministic slices)
- In progress: Pester coverage for deterministic slices (focused EI suites passing for implemented slices)
- Complete: ADO integration validation and threshold calibration for current scope.
- Complete: first adapted agent contract set implemented and wired into orchestrator
- Complete: git-diff auto-discovery for zero-config changed file population
- Planned next tranche: implement deterministic script slices for first adapted agent contract set
- Not started: Pilot execution and metric capture

## Readiness assessment

Planning readiness: High
Implementation readiness: High for deterministic design, with first implementation slices and tests in place
