# EI Graphics Planning Todo List

## Legend

- Status: Not Started | In Progress | Blocked | Done
- Priority: P0 (critical), P1 (high), P2 (normal)

## Tasks

| ID | Task | Priority | Status | Owner | Depends On | Notes |
|---|---|---|---|---|---|---|
| T-001 | Confirm plugin name and ownership model | P0 | Done | EI Graphics Lead | None | Confirmed plugin name: aveva-ei-graphics |
| T-002 | Create plugin scaffold in plugins directory | P0 | Done | Engineering | T-001 | Created via deterministic new-plugin script |
| T-003 | Add plugin manifest and marketplace entry | P0 | Done | Engineering | T-002 | .github registry updated by script; .claude registry added manually |
| T-004 | Author orchestrator agent skeleton | P0 | Done | Engineering | T-002 | Added EI Graphics workflow agent scaffold |
| T-005 | Define ado-bug-intake skill contract | P0 | Done | Engineering | T-004 | Initial SKILL contract scaffolded |
| T-006 | Define EI ontology v1 (loop/wire/cable/etc.) | P0 | In Progress | Domain SME + Engineering | T-004 | Initial skill contract scaffolded; vocabulary details pending SME sign-off |
| T-007 | Define legacy-impact-analyzer skill | P1 | Done | Engineering | T-006 | Initial SKILL contract scaffolded |
| T-008 | Define regression-gate policy and thresholds | P1 | In Progress | QA + Engineering | T-007 | Initial thresholds documented; final policy values pending QA sign-off |
| T-009 | Add Pester tests for deterministic scripts | P1 | In Progress | Engineering | T-005,T-007,T-008 | Focused suites added for layer guard, bug reproducer, vocabulary navigator, and test scaffolder |
| T-010 | Pilot with dev+QA users | P1 | Not Started | EI Graphics Team | T-004,T-009 | Track quality and speed metrics |
| T-011 | Implement deterministic scripts for each skill | P0 | Done | Engineering | T-005,T-007,T-008 | Deterministic slices implemented for all 5 Phase 1 capabilities |
| T-012 | Wire ADO live integration and auth checks | P0 | Done | Engineering | T-005,T-011 | Live retrieval validated against AVEVA-VSTS/Dabacon Products with Azure CLI token fallback; work item context now resolves with `ado-live` status |
| T-013 | Run plugin structure and targeted tests | P1 | In Progress | Engineering | T-011,T-012 | Focused EI deterministic suites passing locally, including URL-driven work item intake coverage |
| T-014 | Remove residual sample scaffold artifacts | P0 | Done | Engineering | T-004 | Removed sample agent and sample skill tree to keep EI-only scaffold |
| T-015 | Fold workflow-discovery report into plugin plan | P0 | Done | Engineering | T-014 | Discovery now drives workflow refinement and capability prioritization |
| T-016 | Decide Phase 1 capability map from codebase evidence | P0 | Done | Engineering + EI Leads | T-015 | Locked to bug reproducer, vocabulary navigator, layer guard, test scaffolder, and PR reviewer |
| T-017 | Refine scaffolded skill set against discovered workflow | P0 | Done | Engineering | T-016 | Existing scaffold now mapped to refined capability set for future contract updates |
| T-018 | Define architecture and review gates | P0 | Done | Engineering + QA | T-016 | Gate definitions recorded in workflow-gates.md |
| T-019 | Rewrite scaffolded skill contracts to match Phase 1 capability map | P0 | Done | Engineering | T-017,T-018 | Placeholder contracts replaced by bug reproducer, vocabulary navigator, layer guard, test scaffolder, and PR reviewer |
| T-020 | Add future-state workflow section to plugin docs | P1 | Done | Engineering | T-016 | Plan now reflects codebase-backed workflow sequence |
| T-021 | Build phased roadmap | P1 | Done | Engineering | T-018,T-019 | roadmap.md separates immediate plugin work from later workflow improvements |
| T-022 | Implement deterministic slice for ei-layer-guard | P0 | Done | Engineering | T-019 | Initial architecture and schema/manual-review checks implemented |
| T-023 | Implement deterministic slice for ei-bug-reproducer | P0 | Done | Engineering | T-019 | Local evidence heuristics and output contract implemented |
| T-024 | Seed ontology-backed dataset for ei-vocabulary-navigator | P0 | Done | Engineering | T-006,T-019 | Initial vocabulary-map.json added and consumed by script |
| T-025 | Add and validate focused Pester suites for deterministic slices | P0 | Done | Engineering | T-022,T-023,T-024 | Focused run passed: 14 passed, 0 failed |
| T-026 | Enforce EI plugin/spec synchronization gate | P0 | Done | Engineering | T-018 | Added Test-EiGraphicsSpecSync script, tests, and workflow gate linkage |
| T-027 | Implement deterministic slice for ei-test-scaffolder | P0 | Done | Engineering | T-019 | Added contract-compliant scaffolding metadata script with dependency extraction heuristics |
| T-028 | Extend focused EI deterministic test suites | P0 | Done | Engineering | T-027 | Focused run passed: 17 passed, 0 failed |
| T-029 | Implement first deterministic slice for ei-pr-reviewer | P0 | Done | Engineering | T-019,T-018 | Added reviewer script packaging R-004/R-005/R-006 findings and required evidence |
| T-030 | Extend focused suites for ADO and reviewer slices | P0 | Done | Engineering | T-012,T-029 | Focused run passed: 23 passed, 0 failed |
| T-031 | Apply RND-reference reuse policy to remaining EI hardening tasks | P1 | In Progress | Engineering | T-012,T-030 | Reuse `aveva-rnd` patterns for structure only; keep EI implementation domain-specific and independently authored |
| T-032 | Implement deterministic ei-graphics-workflow runtime | P0 | Done | Engineering | T-029,T-030 | Added end-to-end orchestration script with PR evidence package output |
| T-033 | Extend focused EI suites with orchestrator coverage | P0 | Done | Engineering | T-032 | Focused run passed: 26 passed, 0 failed |
| T-037 | Add EI Azure DevOps CLI intake skill and wire URL-driven bug reproducer entry | P0 | Done | Engineering | T-012,T-031 | Added `ei-azure-devops-cli-intake` deterministic slice and wired work item URL intake into `ei-bug-reproducer`; focused run passed: 21 passed, 0 failed |
| T-038 | Implement deterministic runtime slice for ei-ado-ingest adapted agent | P1 | Done | Engineering | T-036,T-037 | Added `Invoke-EiAdoIngest.ps1` to normalize URL/ID intake into EI agent contract |
| T-039 | Add focused tests for ei-ado-ingest adapted runtime | P1 | Done | Engineering | T-038 | Added focused Pester suite and validated locally (3 passed, 0 failed) |
| T-040 | Implement deterministic runtime slice for ei-code-review adapted agent | P1 | Done | Engineering | T-036 | Added `Invoke-EiCodeReview.ps1` to package deterministic reviewer output into EI adapted-agent contract |
| T-041 | Add focused tests for ei-code-review adapted runtime | P1 | Done | Engineering | T-040 | Added focused Pester suite and validated locally (3 passed, 0 failed) |
| T-042 | Implement deterministic runtime slice for ei-bug-diagnosis-to-spec adapted agent | P1 | Done | Engineering | T-036 | Added `Invoke-EiBugDiagnosisToSpec.ps1` to map diagnosis evidence into implementation handoff sections |
| T-043 | Add focused tests for ei-bug-diagnosis-to-spec adapted runtime | P1 | Done | Engineering | T-042 | Added focused Pester suite and validated locally (3 passed, 0 failed) |
| T-044 | Wire adapted runtimes into orchestrator | P1 | Done | Engineering | T-038,T-040,T-042 | Orchestrator now calls all three adapted agents and returns outputs under `adaptedAgents`; full suite: 43 passed, 0 failed |
| T-045 | Add git-diff auto-discovery for changed files in orchestrator | P1 | Done | Engineering | T-044 | Orchestrator self-populates `ChangedFiles` from `git diff --name-only` when empty; `DiffBaseBranch` defaults to `origin/main`; test validated (4/4 passing) |
| T-034 | Define EI adaptation blueprint for selected RND agents | P1 | Done | Engineering + EI Leads | T-012,T-013,T-031 | Defined EI adaptation contract set and workflow intent for first selected patterns; no copy/paste adoption |
| T-035 | Prioritize adapted-agent rollout phases | P1 | Done | Engineering + QA | T-034 | Prioritized first rollout on core workflow support contracts (ADO ingest, diagnosis-to-spec, EI code review) |
| T-036 | Author EI-specific contracts for first adapted agent set | P1 | Done | Engineering | T-035 | Authored first EI contract files: ei-ado-ingest, ei-bug-diagnosis-to-spec, ei-code-review |

## Immediate next actions

1. Continue T-006 ontology details with domain SME examples to expand vocabulary coverage and confidence rules.
2. Pilot the full adapted workflow with a real work-item URL end-to-end.
3. Harden orchestrator handling for live ADO scenarios and broaden reviewer/layer gate evidence fields for PR template auto-fill.
4. After T-012 and T-013 stabilization, start T-034 to define EI-specific adaptation blueprints from RND references.
