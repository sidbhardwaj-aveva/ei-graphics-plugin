---
name: ei-bug-reproducer
description: 'Build reproduction guidance, affected-area hypotheses, and related test context for EI Graphics bugs from ADO work items and repository evidence.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
  - search
metadata:
  dependencies:
    - prerequisite-validator
---

# EI Bug Reproducer

## Goal

Turn an EI bug or issue into a structured diagnosis starting point with reproduction hints, likely affected code paths, and related tests.

## Inputs

- `bugId` (optional): Azure DevOps work item ID
- `workItemUrl` (optional): Azure DevOps work item URL (`.../_workitems/edit/<id>`) used to auto-resolve organization, project, and work item ID
- `descriptionText` (optional): copied bug or SR description text
- `organization` (optional): ADO organization
- `project` (optional): ADO project
- `keywords` (optional): domain or error keywords to search in the repo
- `useAzCliToken` (optional): use Azure CLI access token acquisition when environment tokens are unavailable

At least one of `bugId`, `workItemUrl`, or `descriptionText` is required.

## Output contract

Return JSON with:

- `status`: ready | blocked | needs-manual-review
- `bugContext`
- `reproductionHints`
- `affectedAreas`
- `recentChanges`
- `relatedTests`
- `runtimeRequired`: true | false
- `confidence`: number in range [0,1]

## Rules

1. Preserve source fidelity when pulling ADO text.
2. Prefer evidence-backed code areas over broad guesses.
3. If runtime reproduction in E3D is likely required, set `runtimeRequired: true`.
4. If evidence is weak or conflicting, return `needs-manual-review`.

## Implementation status

Deterministic slice implemented in `scripts/Invoke-EiBugReproducer.ps1`.

- Includes vocabulary-backed term matching for affected-area hypotheses.
- Includes ADO bug-context retrieval path by bug ID when organization, project, and token context are available.
- Includes work-item URL intake to derive ADO organization/project/ID automatically.
- Falls back to `needs-manual-review` with explicit retrieval reasons when auth/context/data are missing.
