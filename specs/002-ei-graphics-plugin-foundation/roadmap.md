# Roadmap: EI Graphics Plugin

## Purpose

This roadmap separates immediate plugin work from later workflow and platform improvements so Phase 1 stays practical and evidence-backed.

## Phase 0: Foundation Complete

- Plugin scaffold created and registered.
- Planning workspace created.
- Workflow discovery report captured from the EI codebase.
- Phase 1 capability map locked.

## Phase 1: Immediate Plugin Work

### Outcome

Deliver a safe PR-support workflow that improves diagnosis, architecture validation, verification support, and reviewer handoff without attempting autonomous code changes.

### Current progress

- Contract layer complete for the Phase 1 capabilities.
- Deterministic slices complete for `ei-layer-guard`, `ei-bug-reproducer`, `ei-vocabulary-navigator`, `ei-test-scaffolder`, first-pass `ei-pr-reviewer` packaging, and `ei-graphics-workflow` orchestration runtime.
- Focused Pester coverage for current deterministic EI slices is passing.
- Spec synchronization gate added to prevent planning/implementation drift.
- Remaining: ADO live integration validation hardening and richer PR evidence field expansion.
- Sequencing lock: RND-pattern-based agent adaptation starts only after current hardening tasks are stable.

### Capabilities

- `ei-bug-reproducer`
- `ei-vocabulary-navigator`
- `ei-layer-guard`
- `ei-test-scaffolder`
- `ei-pr-reviewer`
- `ei-graphics-workflow.agent`

### Deliverables

- Finalized contract docs for the capabilities above
- Exact architecture and review gates
- Deterministic scripts for the highest-value checks
- Pester coverage for deterministic scripts

## Phase 2: Workflow Hardening

### Outcome

Use the plugin to reinforce better engineering workflow across diagnosis, testing, and review.

### Candidate improvements

- PR template and evidence checklist alignment
- Test naming guidance and linting
- TODO and tech-debt tracking support
- Better local review and sanity preparation guidance

## Phase 2A: RND-Pattern Adaptation Design (EI-Specific)

### Outcome

Reuse mature RND workflow patterns as references and convert them into EI-specific contracts and rule sets without copy/paste adoption.

### Candidate improvements

- Define EI adaptation blueprints for selected agents (inputs, outputs, deterministic rules)
- Prioritize first adapted set for core workflow support
- Author EI-specific contracts for adapted agents before implementation

## Phase 3: Deeper Verification Support

### Outcome

Reduce late regression surprises by widening verification support around high-risk EI areas.

### Candidate improvements

- Integration-test discovery and scaffolding patterns
- Coverage threshold reporting
- Sanity-scope recommendation based on affected area
- Higher-confidence blast-radius reporting

## Phase 4: Longer-Horizon Workflow Improvements

### Outcome

Address codebase and platform friction that the plugin alone should not try to solve immediately.

### Candidate improvements

- Standardized DI approach
- Better structured tracing and performance diagnostics
- Container-friendly or lighter-weight test execution
- Dead-code cleanup support and build-artifact hygiene

## Sequencing notes

- Phase 1 should complete before any attempt to automate fix generation.
- Phase 2 and 3 can overlap only after the gates and contracts from Phase 1 are stable.
- Phase 2A begins only after Phase 1 hardening items (including live ADO validation) are stable.
- Phase 4 items are deliberately separated because they depend on broader codebase and team changes, not just plugin work.
