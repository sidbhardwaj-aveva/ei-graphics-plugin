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

- `workItemUrl` (optional): Azure DevOps work item URL, or a pasted reference (see below).
- `workItemId` (optional): numeric work item ID, or a reference title such as `Bug 4965976 SR205 - ...`.
- `organization` (optional): Azure DevOps organization.
- `project` (optional): Azure DevOps project.
- `cliWorkItemJson` (optional): deterministic mock payload for tests.

At least one of `workItemUrl` or `workItemId` is required.

### Accepted reference forms

| Form | Behaviour |
|---|---|
| `https://dev.azure.com/<org>/<project>/_workitems/edit/<id>` | Org, project and id come from the URL |
| `https://dev.azure.com/<org>/<project>/_boards/board/...?workitem=<id>` | Org, project and id come from the URL; boards view link |
| `[Bug 4965976 SR205 - ...](https://dev.azure.com/.../edit/4965976)` | The href is used; the label is ignored |
| `[Bug 4965976 SR205 - ...](vscode-file://.../workbench.html)` | The href is not an ADO address, so the id comes from the label; org and project are resolved via the fallback chain below |
| `Bug 4965976 SR205 - ...` | Same as above, without a link |
| `4983245` (bare id) | Org and project are resolved via the fallback chain below |

The id is taken from a work item type prefix (`Bug`, `User Story`, `Task`, `Feature`, ...), a `#`
prefix, or a standalone 3+ digit token. Identifiers glued to letters such as `SR205` are never read
as a work item id. A reference that carries no id fails with `missing-work-item-id-in-reference`.

### Org and project resolution order

When org or project cannot be extracted from the URL, the script resolves them in this order and
stops at the first tier that yields a non-empty value:

1. Explicit `-Organization` / `-Project` parameters.
2. Environment variables `AZDO_ORG` / `AZDO_PROJECT`.
3. Hardcoded AVEVA defaults: `organization=AVEVA-VSTS`, `project=Dabacon Products`.

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
