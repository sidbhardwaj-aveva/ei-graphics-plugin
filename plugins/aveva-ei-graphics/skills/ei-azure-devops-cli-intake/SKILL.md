---
name: ei-azure-devops-cli-intake
description: 'Resolve Azure DevOps work item URLs and fetch normalized work item context via Azure CLI for EI Graphics workflows.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
metadata:
  dependencies:
    - prerequisite-validator
---

# EI Azure DevOps CLI Intake

## Goal

Allow developers to provide a work item URL and automatically resolve organization, project, and work item context for EI workflows.

## Inputs

- `workItemUrl` (optional): Azure DevOps work item URL.
- `workItemId` (optional): numeric work item ID.
- `organization` (optional): Azure DevOps organization.
- `project` (optional): Azure DevOps project.
- `cliWorkItemJson` (optional): deterministic mock payload for tests.

At least one of `workItemUrl` or `workItemId` is required.

## Output contract

Return JSON with:

- `status`: retrieved | failed | blocked
- `reason`
- `workItemContext`
- `descriptionText`

## Rules

1. Parse URL context deterministically before any network call.
2. Never print tokens.
3. Return explicit failure reasons for missing context, auth failures, and not-found cases.
4. Return normalized plain-text description assembled from title, description, and repro fields.

## Lifecycle stage

`scripts/Invoke-EiAdoIntakeStage.ps1` runs the `ado-intake` stage of the IMPLEMENT lifecycle. It does not
re-implement retrieval: it calls `Invoke-EiAdoCliIntake.ps1`, then decides what the run is allowed to
believe afterwards.

- Takes `storyId` from `workflow-state.json`, never from the caller, so the artifact cannot be written
  under an id the run was not initialised with.
- Writes the `ado` artifact (`schemas/ado.schema.json`, owned by `ei-workflow-state`).
- Evaluates the `artifact-present` gate by reading the persisted artifact back; the gate is never
  asserted from intent.
- A retrieval that did not reach `retrieved` blocks the stage with the intake's own reason. A partial
  story is never sealed.

## Implementation status

Deterministic slice implemented in `scripts/Invoke-EiAdoCliIntake.ps1`; lifecycle stage implemented in
`scripts/Invoke-EiAdoIntakeStage.ps1`.
