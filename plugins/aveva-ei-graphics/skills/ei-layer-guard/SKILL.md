---
name: ei-layer-guard
description: 'Detect cross-layer references and architecture violations in EI Graphics changes before PR creation.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - read
  - search
  - powershell
---

# EI Layer Guard

## Goal

Validate that changed EI Graphics projects and files do not introduce or extend forbidden architecture boundaries.

## Inputs

- `changedFiles` (optional): array of changed source or project files
- `changedProjects` (optional): array of changed `.csproj` files
- `solutionPath` (optional): path to the target solution or repo root

## Output contract

Return JSON with:

- `status`: pass | blocked | needs-manual-review
- `violations`
- `reviewFlags`
- `affectedLayers`
- `requiredActions`

## Rules

1. Block on detected cross-layer references such as application or domain code referencing presentation projects.
2. Flag additions of broad `catch (Exception)` handling as review findings.
3. Flag committed build artifacts or generated debug files as review findings.
4. Keep the output read-only and evidence-backed.

## Implementation status

Initial deterministic script target is `scripts/Invoke-EiLayerGuard.ps1` with focused unit-test coverage for cross-layer references, broad exception handling, and build-artifact detection.
