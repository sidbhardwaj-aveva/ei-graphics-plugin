---
name: ei-azure-devops-cli-intake
description: Resolve an Azure DevOps work item reference and fetch its story text, images and discussion through the ADO CLI. Returns one JSON object on stdout for `Convert-EiAdoIntake.ps1` to translate.
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - powershell
  - read
---

# Electrical and Instrumentation (EI) Azure DevOps CLI Intake

## Goal

Let a developer paste a work item link and get back the story, its images and its discussion.
Nobody has to read an identifier off the link by eye.

## Inputs

- `workItemUrl` (optional): an ADO work item link, or a pasted reference. See below.
- `workItemId` (optional): the numeric work item identifier, or a reference title such as
  `Bug 4965976 SR205 - ...`.
- `organization` (optional): the ADO organization.
- `project` (optional): the ADO project.
- `cliWorkItemJson` (optional): a fixed payload, so a test never touches the network.
- `cliCommentsJson` (optional): a fixed discussion payload, for the same reason.

You must supply either `workItemUrl` or `workItemId`.

### Accepted reference forms

`scripts/helpers/EiWorkItemReference.ps1` owns the parsing, and it is deterministic. The same
pasted text always gives the same identifier. Paste the reference through as it stands. Never read
the identifier off the link yourself.

| Form | Behaviour |
|---|---|
| `https://dev.azure.com/<org>/<project>/_workitems/edit/<id>` | The identifier comes from the link |
| `https://dev.azure.com/<org>/_workitems/edit/<id>` | Short link with no project part; the identifier comes from the link |
| `https://dev.azure.com/<org>/<project>/_boards/board/...?workitem=<id>` | Board link; the identifier comes from the query |
| `[Bug 4965976 SR205 - ...](https://dev.azure.com/.../edit/4965976)` | The target is used and the label is ignored |
| `Please fix [Bug 4965976 - ...](<ado-url>) today` | The link is found inside the surrounding words |
| `[Bug 4965976 SR205 - ...](vscode-file://.../workbench.html)` | The target is not an ADO address, so the label supplies the identifier |
| `Bug 4965976 SR205 - ...` | The same, without a link |
| `4983245` (bare number) | Used as it stands |

The identifier is taken from an explicit numeric `-WorkItemId` first, then from the ADO link.
Failing both, it is read from the label. There it may follow a work item type word, such as `Bug`,
`User Story`, `Task` or `Feature`. It may also follow a `#` prefix, or stand alone as a number of
three digits or more. Something glued to letters, such as `SR205`, is never read as a work item
identifier.

| Failure reason | Cause |
|---|---|
| `missing-work-item-url-or-id` | Nothing was supplied. The status is `blocked` |
| `missing-work-item-id-in-url` | An ADO link was supplied but carries no identifier |
| `missing-work-item-id-in-reference` | A reference was supplied but no identifier could be read from it |
| `unsupported-work-item-url-host` | A bare link to somewhere else, with no label to fall back on |

### The organization and the project are fixed

Every EI Graphics story lives in the same place. The pasted link never decides where the work item
is read from. The organization and the project resolve in this order, stopping at the first one
that is set:

1. The `-Organization` and `-Project` parameters.
2. The `AZDO_ORG` and `AZDO_PROJECT` environment variables.
3. The fixed defaults, `AVEVA-VSTS` and `Dabacon Products`.

Whatever the link says is deliberately not one of those tiers. A link naming a different project
is still recorded under the defaults. Two runs of the same story can then never disagree about
where it came from.

## Output contract

One JSON object on stdout, with these fields:

- `status`: `retrieved`, `failed` or `blocked`
- `reason`
- `workItemContext`
- `descriptionText`
- `attachmentUrls`: each embedded image, as `{ url, source }`
- `commentRetrieval`: `{ status, reason }` for the discussion
- `comments`: the discussion in order, as `{ id, author, createdDate, text }`

The script writes no file and exits 0 on success.

### What feeds the story text

One ordered list of fields feeds both `descriptionText` and `attachmentUrls`. A field can never be
read for its words but skipped for its pictures:

`System.Title`, `System.Description`, `Microsoft.VSTS.Common.AcceptanceCriteria`,
`Microsoft.VSTS.TCM.ReproSteps`, `System.ReproSteps`.

Acceptance criteria is on that list because EI stories often keep the real requirement there,
along with the screenshots, rather than in the description. Leaving it out made the agent fetch
the work item again by hand. It also reported a story with images as having none.

### The discussion

`az boards work-item show` does not return the discussion at all. Comments are fetched separately,
through `az rest` against `_apis/wit/workItems/<id>/comments`. EI stories often carry corrections
there that replace what the description says. A run that cannot see them is working from a stale
story.

Comments are scanned for images alongside the story fields. Every image records its `source` as
`field:<FieldName>` or `comment:<id>`, so a picture can be traced to whoever posted it.

Fetching the discussion is best effort and never stops the run. The outcome is always reported, so
an unread discussion is never mistaken for an empty one:

| `commentRetrieval.status` | `reason` | Meaning |
|---|---|---|
| `retrieved` | `ado-cli` or `mock-json` | The discussion was read, and `comments` is complete |
| `skipped` | `mock-run-without-comments` | A fixed work item was supplied with no fixed discussion |
| `unavailable` | `comments-request-failed`, `comments-invalid-json` or `mock-comments-invalid` | It could not be read. Treat `comments` as unknown, not empty |

`createdDate` is written as an invariant `yyyy-MM-ddTHH:mm:ssZ` string.

That matters more than it looks. `ConvertFrom-Json` turns a timestamp string into a date object,
and casting that back to text renders it in whatever culture the machine is set to. The artifact
would then differ from one machine to the next. Every step that reads the payload and writes it
out again must reformat rather than cast. `scripts/helpers/EiAdoTimestamp.ps1` owns
`ConvertTo-EiIsoTimestamp` for that reason.

## Rules

1. Work out the reference before making any network call.
2. Never print a token.
3. Give an explicit reason for missing context, for a refused sign-in, and for a work item that
   was not found.
4. Return plain text, assembled from the fields listed above.
5. Decode an encoded `src` value before returning it, so an `&amp;` in an image link does not cut
   the download query short.
6. Always report how the discussion fetch went. Never present an unread discussion as an empty one.

## What happens next

This script only retrieves. It writes nothing to disk.

Pipe its output into `Convert-EiAdoIntake.ps1`, which turns it into the shape
`ado.schema.json` wants and downloads the images. Then pipe that into
`Write-EiArtifact.ps1 -ArtifactType ado`, which checks it against the schema and writes
`ado.json`. Both live in the `ei-graphics-core` skill.

If either of those two exits with a code other than 0, stop and report it. Never carry on to
understanding the story without an `ado.json`.
