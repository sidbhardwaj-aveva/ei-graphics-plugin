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

Parsing is owned by `scripts/helpers/EiWorkItemReference.ps1` and is deterministic: the same pasted
text always yields the same id. The agent must paste the reference through verbatim and must never
read the id off the link itself.

| Form | Behaviour |
|---|---|
| `https://dev.azure.com/<org>/<project>/_workitems/edit/<id>` | The id comes from the URL |
| `https://dev.azure.com/<org>/_workitems/edit/<id>` | Short link with no project segment; the id comes from the URL |
| `https://dev.azure.com/<org>/<project>/_boards/board/...?workitem=<id>` | Boards view link; the id comes from the query |
| `[Bug 4965976 SR205 - ...](https://dev.azure.com/.../edit/4965976)` | The href is used; the label is ignored |
| `Please fix [Bug 4965976 - ...](<ado-url>) today` | The link is found inside surrounding prose |
| `[Bug 4965976 SR205 - ...](vscode-file://.../workbench.html)` | The href is not an ADO address, so the id comes from the label |
| `Bug 4965976 SR205 - ...` | Same as above, without a link |
| `4983245` (bare id) | Used directly |

The id is taken from an explicit numeric `-WorkItemId`, then from the ADO URL, then from a work item
type prefix (`Bug`, `User Story`, `Task`, `Feature`, ...), a `#` prefix, or a standalone 3+ digit
token in the label. Identifiers glued to letters such as `SR205` are never read as a work item id.

| Failure reason | Cause |
|---|---|
| `missing-work-item-url-or-id` | Nothing was supplied (status `blocked`) |
| `missing-work-item-id-in-url` | An ADO URL was supplied but carries no work item id |
| `missing-work-item-id-in-reference` | A reference was supplied but no id could be read from it |
| `unsupported-work-item-url-host` | A bare non-ADO URL with no label to fall back to |

### Org and project are fixed

Every EI Graphics story lives in the same place, so the pasted link never decides where the work
item is read from. Org and project resolve in this order and stop at the first non-empty tier:

1. Explicit `-Organization` / `-Project` parameters.
2. Environment variables `AZDO_ORG` / `AZDO_PROJECT`.
3. Fixed AVEVA defaults: `organization=AVEVA-VSTS`, `project=Dabacon Products`.

Org and project embedded in the URL are deliberately **not** a tier. A link that names a different
project is recorded under the defaults rather than under whatever the link happened to say, so two
runs of the same story can never disagree about where it came from.

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
- Resolves the retrieval reference when the caller supplies neither `-WorkItemUrl` nor `-WorkItemId`:
  `storyRef` from `workflow-state.json` first, then `storyId`. An explicit parameter always wins.
  `Details.ReferenceSource` reports which of `parameter`, `workflow-state.storyRef` or
  `workflow-state.storyId` was used.
- Writes the `ado` artifact (`schemas/ado.schema.json`, owned by `ei-workflow-state`).
- Evaluates the `artifact-present` gate by reading the persisted artifact back; the gate is never
  asserted from intent.
- A retrieval that did not reach `retrieved` blocks the stage with the intake's own reason. A partial
  story is never sealed.
- `EIAI-STAGE-NOT-STARTED` carrying `EIWF-STAGE-ORDER` means the run was never bootstrapped. The
  answer is `Start-EiWorkflowRun.ps1`, reported in `Details.Remediation`; do not complete `preflight`
  by hand, which the `prerequisites` artifact now prevents anyway.

## Implementation status

Deterministic slice implemented in `scripts/Invoke-EiAdoCliIntake.ps1`; lifecycle stage implemented in
`scripts/Invoke-EiAdoIntakeStage.ps1`. Reference parsing and the fixed org/project live in
`scripts/helpers/EiWorkItemReference.ps1`, which `ei-graphics-workflow`'s `Start-EiWorkflowRun.ps1`
dot-sources so the run and the intake never disagree about which work item was pasted.
