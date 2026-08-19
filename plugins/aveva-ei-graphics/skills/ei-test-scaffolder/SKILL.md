---
name: ei-test-scaffolder
description: 'Scaffold MSTest verification slices for EI Graphics services and commands using repository conventions.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
  - search
---

# EI Test Scaffolder

## Goal

Generate verification scaffolding that follows EI repository testing conventions without inventing behavioral assertions.

## Inputs

- `targetClass` (required): service or command class to scaffold tests for
- `methods` (optional): array of target methods
- `testProjectPath` (optional): destination test project path

## Output contract

Return JSON with:

- `status`: ready | blocked | needs-manual-review
- `suggestedTestNames`
- `mockDependencies`
- `resolverSetupRequired`: true | false
- `outputPaths`
- `manualAssertionsRequired`: true

## Rules

1. Follow the `Method_Scenario_Expected` naming pattern.
2. Use MSTest structure with the existing `ResolverHelper` and NSubstitute conventions when applicable.
3. Never invent assertions for domain behavior; leave those for the developer.
4. If the required test project cannot be identified, return `needs-manual-review`.

## Implementation status

Deterministic slice implemented.

- Script: `scripts/Invoke-EiTestScaffolder.ps1`
- Unit tests: `tests/aveva-ei-graphics/skills/ei-test-scaffolder/scripts/Invoke-EiTestScaffolder.Tests.ps1`
- Current behavior: returns contract-compliant scaffolding metadata and status (`ready`, `blocked`, `needs-manual-review`) without generating behavioral assertions.
