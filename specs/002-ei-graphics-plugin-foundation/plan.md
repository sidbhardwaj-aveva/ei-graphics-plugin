# Plan: EI Graphics Plugin Foundation

## 1. Objective

Build a dedicated EI Graphics plugin that combines:
- A domain-specific orchestrator agent
- ADO-integrated bug lifecycle skills
- Legacy-safe change gates
- EI Graphics ontology and visual/domain interpretation rules

Primary success goal: reduce risk of breaking legacy EI Graphics code while accelerating bug triage and fix throughput.

## 2. Why a dedicated plugin

A dedicated plugin is required because:
- Workflow overlap with R&D exists, but domain knowledge is materially different
- Legacy constraints require explicit safety gates and deterministic execution
- EI Graphics requires persistent domain semantics beyond generic bug-fix logic

## 3. Scope

### In scope (Phase 1)

- New plugin scaffold (suggested name: aveva-ei-graphics)
- Workflow refinement grounded in the actual EI codebase rather than assumed process
- One orchestrator agent for end-to-end bug handling and PR-readiness support
- Initial capability set to validate or refine from codebase evidence:
  - bug reproduction and affected-area discovery
  - EI vocabulary and entity navigation
  - architecture layer guardrails
  - test scaffolding and verification support
  - PR review and evidence packaging
- Planning and governance artifacts for safe rollout

### Out of scope (Phase 1)

- Fully autonomous direct-to-main code changes
- Broad incident management outside EI Graphics bug workflows
- Full production rollout without pilot metrics

## 4. Proposed architecture

### Plugin structure

plugins/aveva-ei-graphics/
- .github/plugin/plugin.json
- README.md
- agents/
  - ei-graphics-workflow.agent.md
  - ei-pr-reviewer.agent.md
- skills/
  - ei-bug-reproducer/
  - ei-vocabulary-navigator/
  - ei-layer-guard/
  - ei-test-scaffolder/

### Reuse policy

- Reuse mature orchestration and integration patterns from `plugins/aveva-rnd` as references.
- Do not copy agents, prompts, or scripts verbatim from `aveva-rnd`.
- Keep EI workflows, gates, and evidence packaging aligned to EI domain risks and vocabulary.

### Phase 1 capability map

The workflow-discovery report supports the following Phase 1 capability set:

| Capability | Type | Primary workflow step | Why it is Phase 1 |
|---|---|---|---|
| `ei-bug-reproducer` | Agent | Diagnosis | Reproduction and affected-area discovery are weak handoff points today |
| `ei-vocabulary-navigator` | Skill | Diagnosis / Implementation | EI terminology and schema mapping are too domain-specific to infer safely each time |
| `ei-layer-guard` | Skill | Implementation / PR creation | Cross-layer violations are already present and need deterministic enforcement |
| `ei-test-scaffolder` | Skill | Verification | Unit-test support is a practical early accelerator with lower risk than auto-fix logic |
| `ei-pr-reviewer` | Agent | Review | PR review currently lacks structured checks for architecture, TODO debt, and risky catch patterns |

### Capability migration from current scaffold

The initial scaffolded skill names were useful placeholders, but the real EI codebase points to this refined mapping:

| Existing scaffold | Refined Phase 1 direction |
|---|---|
| `ado-bug-intake` | Fold into `ei-bug-reproducer` or keep as a helper capability behind it |
| `ei-graphics-ontology` | Evolve into `ei-vocabulary-navigator` |
| `legacy-impact-analyzer` | Narrow toward `ei-layer-guard` plus review/risk checks |
| `regression-gate` | Fold review and verification concerns into `ei-pr-reviewer` and later explicit sanity gating |

### Workflow sequence

1. Intake bug from ADO (ID, description, attachments, repro context)
2. Reproduce or narrow the issue against the real EI runtime and code paths
3. Normalize terms and map domain entities, services, and repositories
4. Validate architectural and blast-radius risk before implementation guidance
5. Scaffold or recommend verification work (unit tests, coverage rationale, sanity scope)
6. Produce evidence-backed output for PR creation, reviewer handoff, and sanity validation

### Future-state engineering workflow

1. ADO bug or issue is selected with linked SR context.
2. `ei-bug-reproducer` narrows candidate code paths, recent changes, and reproduction guidance.
3. `ei-vocabulary-navigator` resolves EI-specific terms, URIs, and service/repository paths.
4. Developer implements the change with `ei-layer-guard` checking for cross-layer violations.
5. `ei-test-scaffolder` proposes or scaffolds verification work for the affected service/command slice.
6. `ei-pr-reviewer` prepares a first-pass review pack covering architecture, TODO debt, catch patterns, and test evidence.
7. Human reviewers and existing PR sanity pipelines remain the final release gate.

## 5. Guardrails and safety model

- No fix recommendation without bug reproduction evidence or explicit reason for non-repro
- High-risk legacy surfaces trigger hard block unless manual approval is provided
- No merge automation in Phase 1; PR-only workflow with test evidence
- All deterministic scripts require Pester coverage and Unit tagging
- Domain-logic changes that affect wiring rules, cable/core behavior, or electrical calculations require SME review
- Architecture violations, bare `catch (Exception)`, and undocumented TODO debt should be treated as blocking or advisory review findings

Exact Phase 1 gate definitions are recorded in `workflow-gates.md`.

## 6. Milestones

### M1 - Foundation scaffold

- Plugin skeleton created
- Marketplace registration added
- Initial README and metadata complete

### M2 - Orchestrator + intake path

- Agent created
- Current-state and future-state workflow documented from codebase evidence
- Bug reproduction and affected-area discovery capability defined and selected for Phase 1

### M3 - Domain and legacy safety

- EI vocabulary navigation skill added with first glossary set
- Architecture/layer guard skill added
- PR review and verification gate policy added
- Phase 1 capability map finalized from workflow evidence

### M4 - Verification and pilot readiness

- Unit tests for deterministic scripts
- Documentation review complete
- Pilot checklist complete

### M4 progress update

- Deterministic scripts and focused tests are implemented for:
  - `ei-layer-guard`
  - `ei-bug-reproducer`
  - `ei-vocabulary-navigator`
- Initial focused Pester validation is passing for the three implemented slices.
- Spec synchronization is now enforced as a repository gate for EI plugin changes.

## 7. Acceptance criteria

1. Team can run a full bug flow from ADO bug ID to PR-ready recommendation.
2. Workflow guidance reflects how the EI codebase actually operates today and highlights required workflow changes.
3. Vocabulary navigation classifies core EI terms with explicit definitions and confidence handling.
4. Architecture and review gates block unsafe change paths by policy.
5. Plugin structure and maintainer/compliance checks pass.
6. Phase 1 capability set is traceable to codebase evidence and documented workflow gaps.

## 8. Dependencies

- Azure DevOps connectivity and auth prerequisites
- Access to EI Graphics legacy documentation and coding standards
- Existing regression test packs and CI artifacts

## 8.1 Reuse strategy

- Reference `plugins/aveva-rnd` for proven agent and script patterns (for example: auth handling, deterministic output contracts, and review packaging structure).
- Keep EI implementation independently authored and domain-specific; do not copy RND artifacts verbatim.
- Validate every reused pattern against EI workflow gates before adoption.

## 9. Metrics to track in pilot

- Repro success rate
- False-positive block rate from safety gates
- Time to triage
- Time to safe fix recommendation
- Regression escape rate

## 10. Current status

Planning scaffold complete. Phase 1 implementation is in progress.
Initial plugin assets are created (manifest, marketplace registration, CODEOWNERS entry, EI workflow agent, and core skill contracts). Workflow discovery from the real EI codebase has been folded into capability design and early deterministic slices.

Current delta:
- First deterministic script/test slices are now implemented for three Phase 1 capabilities.
- Ontology-backed vocabulary data seeding has started.
- Deterministic `ei-test-scaffolder` slice is now implemented with focused unit coverage.
- First deterministic `ei-pr-reviewer` slice is implemented for R-004/R-005/R-006 gate packaging.
- `ei-bug-reproducer` now includes an ADO bug-context retrieval path with safe fallback behavior.
- T-012 hardening adds bug ID validation, environment-based org/project resolution, and status-specific ADO fallback reasons.
- T-012 calibration adds reason-based confidence caps and transient tagging to better prioritize retry vs manual evidence paths.
- Deterministic `ei-graphics-workflow` orchestration runtime is implemented for end-to-end PR evidence packaging.
- Remaining implementation work focuses on ADO live validation hardening, evidence-field expansion, and pilot metrics capture.

## 11. Supporting documents

- `EI-Graphics-Workflow-Analysis.md`: evidence-backed workflow discovery and redesign report
- `workflow-gates.md`: exact architecture and review gates for Phase 1
- `roadmap.md`: phased delivery sequence from immediate plugin work through later workflow improvements
