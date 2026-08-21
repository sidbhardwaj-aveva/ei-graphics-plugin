# EI Graphics Plugin Foundation Planning Workspace

This directory formalizes planning, status tracking, and execution control for the EI Graphics plugin initiative.

## Purpose

Create a dedicated AVEVA plugin for EI Graphics that:
- Integrates with Azure DevOps (ADO) for bug intake and workflow automation
- Applies strict legacy-safe gates before recommending or applying fixes
- Encodes EI Graphics domain knowledge (for example: loop, wire, cable)
- Supports developers and QA in a shared, repeatable, test-first workflow

## Files in this workspace

- plan.md: Full implementation plan, milestones, architecture, and acceptance criteria
- todo-list.md: Actionable task tracker with status, owners, and dependencies
- current-status.md: Current execution state and what has already been decided
- decisions.md: Architecture and process decisions with rationale
- risks-and-mitigations.md: Risk register and mitigation strategy
- progress-log.md: Time-ordered execution journal
- markdown.md: Documentation standards for this planning workspace

## Operating model

1. Update todo-list.md when a task starts or completes.
2. Append progress entries to progress-log.md for every meaningful update.
3. Update current-status.md at least once per planning or implementation session.
4. Record any major technical/process decision in decisions.md.
5. Keep plan.md stable; revise only when scope or strategy changes.
6. Run `pwsh -NoProfile -File ./tools/Test-EiGraphicsSpecSync.ps1 -FromRef origin/main -ToRef HEAD` before PR completion; plugin changes without spec updates are blocked.

The `design/` subfolder holds the Phase 1 and Phase 2A architecture, risk, and verification
documents. They live here rather than inside `plugins/` so the shipped plugin package stays clean.

## Initial state

This workspace has been scaffolded from the EI Graphics discovery discussion and is ready for implementation planning and execution.
