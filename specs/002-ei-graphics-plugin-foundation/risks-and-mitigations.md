# Risk Register: EI Graphics Plugin

## R-001: Incorrect domain classification

- Risk: The system misclassifies loop/wire/cable entities.
- Impact: Wrong diagnosis and low-quality fix recommendations.
- Likelihood: Medium
- Mitigation:
  - Build ontology with explicit definitions and disambiguation rules.
  - Add confidence scores and require manual validation below threshold.

## R-002: Legacy regressions

- Risk: Proposed fix breaks legacy behaviors.
- Impact: High severity production issues.
- Likelihood: High
- Mitigation:
  - Mandatory layer and review gates aligned to `workflow-gates.md`.
  - Hard-block policy on high-risk change surfaces.

## R-003: ADO dependency or auth failures

- Risk: Workflow cannot pull bug data reliably.
- Impact: Interrupted triage workflow.
- Likelihood: Medium
- Mitigation:
  - Pre-flight auth validation skill.
  - Fallback guidance and explicit failure handling.

## R-004: Over-automation without sufficient evidence

- Risk: Auto-fix suggestions are trusted without adequate verification.
- Impact: Unsafe code changes.
- Likelihood: Medium
- Mitigation:
  - Require reproducibility evidence and test logs in outputs.
  - Phase 1 enforces PR-only and human approval.

## R-005: Scope expansion too early

- Risk: Initiative grows faster than validation capability.
- Impact: Delayed delivery and low confidence.
- Likelihood: Medium
- Mitigation:
  - Strict phase scope and milestone gates.
  - Add capabilities only after pilot metric thresholds are met.

## R-006: Planning and implementation drift

- Risk: EI plugin code changes outpace updates to the planning/spec workspace.
- Impact: Team loses shared context, review quality drops, and gate intent becomes unclear.
- Likelihood: Medium
- Mitigation:
  - Enforce `R-007` spec synchronization gate for EI plugin changes.
  - Require at least one updated artifact under `specs/002-ei-graphics-plugin-foundation/` per EI plugin change set.
