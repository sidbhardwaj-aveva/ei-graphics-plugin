# Decision Log: EI Graphics Plugin

## D-001: Build a dedicated EI Graphics plugin

- Status: Accepted
- Date: 2026-08-10
- Decision: Create a separate EI Graphics plugin rather than extending only existing generic workflows.
- Rationale:
  - Domain semantics are materially different from generic/R&D workflows.
  - Legacy-safe controls need first-class enforcement.
  - Team ownership and lifecycle are clearer in a dedicated plugin.

## D-002: Use orchestrator agent + modular skills

- Status: Accepted
- Date: 2026-08-10
- Decision: Implement one orchestrator agent and multiple focused skills.
- Rationale:
  - Common workflow is conversational and cross-step.
  - Deterministic high-risk steps should be isolated as reusable skills.

## D-003: Enforce hard safety gates in Phase 1

- Status: Accepted
- Date: 2026-08-10
- Decision: High-risk legacy changes are blocked unless mandatory checks pass.
- Rationale:
  - Prevent regressions in legacy EI graphics codebase.
  - Aligns with safety-first rollout model.

## D-004: PR-only execution in Phase 1

- Status: Accepted
- Date: 2026-08-10
- Decision: No direct merge automation; produce evidence-backed PR recommendations.
- Rationale:
  - Keeps human oversight while retaining workflow speed.

## D-005: EI ontology is a core capability

- Status: Accepted
- Date: 2026-08-10
- Decision: Include ontology/domain skill from day one.
- Rationale:
  - Correct interpretation of domain entities is required for accurate bug triage/fix.

## D-006: Remove sample scaffold artifacts immediately

- Status: Accepted
- Date: 2026-08-10
- Decision: Remove `aveva-ei-graphics` sample template agent/skill artifacts and keep only EI-specific agent and skills.
- Rationale:
  - Avoid dual execution paths and operator confusion.
  - Keep plugin structure aligned with current implementation intent and status reporting.

## D-007: Use codebase evidence to refine the workflow before implementing deterministic skills

- Status: Accepted
- Date: 2026-08-10
- Decision: Treat the EI codebase workflow-discovery report as the primary input for refining the plugin workflow and capability set before building deterministic scripts.
- Rationale:
  - The existing workflow was not concrete enough to implement safely from assumptions alone.
  - The EI codebase shows critical gates around architecture, reproduction, regression, and review that must be reflected in the plugin design.

## D-008: Prioritize architecture, diagnosis, and review support in Phase 1

- Status: Accepted
- Date: 2026-08-10
- Decision: Prioritize capabilities for bug reproduction, vocabulary navigation, layer guardrails, test scaffolding, and PR review over deeper automation of code changes.
- Rationale:
  - The codebase shows high blast-radius areas, weak handoffs, and late regression feedback.
  - Safer near-term value comes from better diagnosis and verification support than from aggressive auto-fix flows.

## D-009: Lock the Phase 1 capability map to five workflow-supporting capabilities

- Status: Accepted
- Date: 2026-08-10
- Decision: Phase 1 will center on `ei-bug-reproducer`, `ei-vocabulary-navigator`, `ei-layer-guard`, `ei-test-scaffolder`, and `ei-pr-reviewer`.
- Rationale:
  - These capabilities directly address the strongest evidence-backed workflow gaps in diagnosis, architecture safety, verification support, and PR review.
  - They provide immediate value without overcommitting to unsafe autonomous code-change behavior.

## D-010: Deliver deterministic slices before full capability completion

- Status: Accepted
- Date: 2026-08-10
- Decision: Implement deterministic slices first for the highest-risk/highest-value capabilities (`ei-layer-guard`, `ei-bug-reproducer`, `ei-vocabulary-navigator`) before completing all remaining Phase 1 capabilities.
- Rationale:
  - This reduces delivery risk by proving the script + test pattern early.
  - It provides immediate utility in diagnosis and architecture safety while keeping PR-only human oversight.

## D-011: Enforce spec synchronization as a hard-block gate

- Status: Accepted
- Date: 2026-08-10
- Decision: Any change under `plugins/aveva-ei-graphics/` must include at least one corresponding update under `specs/002-ei-graphics-plugin-foundation/`.
- Rationale:
  - Keeps workflow, status, and governance artifacts aligned with implementation reality.
  - Prevents documentation drift during iterative plugin development.

## D-012: Reuse RND patterns as references, not templates

- Status: Accepted
- Date: 2026-08-10
- Decision: Use `plugins/aveva-rnd` agents/skills/scripts as implementation references for structure, guardrails, and integration patterns, while keeping EI plugin behavior domain-specific and independently authored.
- Rationale:
  - RND plugin contains mature workflow and integration patterns that reduce avoidable design risk.
  - EI domain logic and safety gates are specialized and must not be copied as generic template behavior.

## D-013: Sequence adaptation after active Phase 1 hardening

- Status: Accepted
- Date: 2026-08-10
- Decision: Continue the current EI implementation/hardening plan first (especially live ADO validation and evidence hardening), and only then start adapting selected RND agent patterns into EI-specific contracts.
- Rationale:
  - The current workflow runtime and gate model need stabilization before introducing additional adapted agent surfaces.
  - Sequencing reduces concurrent change risk and keeps deterministic validation signals clear.
  - This preserves the no-copy policy while still enabling structured reuse once the baseline is stable.
