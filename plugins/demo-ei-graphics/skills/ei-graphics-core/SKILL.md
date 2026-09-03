---
name: ei-graphics-core
description: Usage reference for the six core scripts of an Electrical and Instrumentation (EI) Graphics session. Covers the artifact writer, the session log, the rendered summary, the skill catalogue, the drift check, and the ADO converter.
---

# EI Graphics Core

Six scripts, all in `scripts/`. The schemas they check against are in `schemas/`.

They all behave the same way. JSON goes to stdout and messages go to stderr. Exit code 0 means it
worked and 1 means it did not. Running the same command twice is safe. Nothing prompts for input.
`-Help` prints the synopsis and exits 0.

Artifacts are written under `<Root>/.ei-session-logs/<storyId>/`. `-Root` defaults to the current
folder, so you rarely pass it.

## `Write-EiArtifact.ps1`

Checks a payload against its schema, then writes it as JSON.

**Parameters:** `-StoryId`, `-ArtifactType`, `-InputObject`, `-InputJson`, `-Root`, `-Json`,
`-Help`. `-ArtifactType` is one of `story-understanding`, `approved-files` or `ado`. Give the
payload as an object through `-InputObject`, or as text through `-InputJson`.

**Writes:** `.ei-session-logs/<storyId>/<artifact-type>.json`.
**Output:** the path it wrote and the hash it stamped.

For `story-understanding` and `approved-files` it stamps a `hash` field. It never does that for
`ado`, because `ado.schema.json` allows no such field. ADO content is tied down instead by the
`adoHash` field inside `story-understanding.json`.

**Exit codes:** 0 when the payload passed and the file was written. 1 when it failed, and the
schema errors are listed on stderr.

## `Write-EiSessionEntry.ps1`

Appends one entry to the session log, and creates the log on the first call.

**Shared parameters:** `-StoryId`, `-Root`, `-Json`, `-Help`.
**To append an entry:** `-Phase`, `-Action`, `-Reasoning`, `-Outcome`, `-DurationMs`,
`-TokensUsed`, `-FilesRead`, `-FilesModified`, `-HumanInput`, `-ScriptOutput`, `-Evidence`.
**To close the session:** `-Finalize`, `-TestsRun`, `-TestsPassed`, `-HumanInteractions`,
`-SessionOutcome`, `-DomainSkillUsed`, `-BugPatternMatched`.

The two sets are mutually exclusive. Passing one from each is an error, not a partial write.
`-SessionOutcome` is not called `-Outcome` because the entry and the summary both hold a field
named `outcome`, and one parameter cannot mean two things. `-Evidence` is a list of hashtables,
each naming a `file` and optionally a `line`, a `symbol` and a `quote` of the text you read. An
item with no `file` is an error, and the summary renders each one under its reasoning.

`-Finalize` works out `completedAt`, `totalDurationMs`, `totalTokens` and `filesModified` from the
entries already written. You supply the other six.

**Writes:** `.ei-session-logs/<storyId>/session.json`, through a temporary file, so a second
append cannot truncate it.
**Output:** the path, the entry count, and the entry just written.
**Exit codes:** 0 on success. 1 when the phase is unknown, or the result would not validate.

## `Export-EiSessionSummary.ps1`

Renders `session-summary.md` from `session.json`.

**Parameters:** `-StoryId`, `-Root`, `-Json`, `-Help`.

Input is always `<Root>/.ei-session-logs/<StoryId>/session.json`, and the output sits beside it.
There is no separate input or output path, because `-Root` moves both.

Detail level comes from the `verbosity` field inside `session.json`, so there is no parameter for
it. At `concise` the reasoning trail is dropped and the timeline is shortened. The section for the
maintainer is always written.

**Writes:** `.ei-session-logs/<storyId>/session-summary.md`.
**Output:** the path it wrote.
**Exit codes:** 0 on success. 1 when the session log is missing or does not validate.

## `Get-EiDomainSkillCatalog.ps1`

Reads the registry, then reads only the front of each skill document.

**Parameters:** `-RegistryPath`, `-Json`, `-Help`. `-RegistryPath` defaults to
`references/domain-skill-registry.json`, and exists so a test can point at a broken registry.

**Output:** `{ skills: [ { domainId, displayName, skillPath, description, whenToUse[] } ] }`.

The `description` comes from the YAML frontmatter. The `whenToUse` list comes from the
`## When to Use` bullet list. The rest of the skill document is never read.

**Exit codes:** 0 on success. 1 when a `skillPath` points at nothing, or the frontmatter cannot be
read.

## `Test-EiScopeDrift.ps1`

Compares the files that changed against the files that were approved.

**Parameters:** `-StoryId`, `-Root`, `-ChangedFiles`, `-Json`, `-Help`.

Leave `-ChangedFiles` out and the script asks git itself, using the diff plus untracked files.
Pass it and the script uses your list instead. Call the script in process with `&` when you pass a
list. Running it with `pwsh -File` flattens the array and the check quietly passes.

**Output:** `{ status, unapproved[], approvedUnchanged[] }`, where `status` is `pass` or `drift`.
An approved file nobody touched is reported, but it is a warning, not a failure.

**Exit codes:** 0 when nothing unapproved changed. 1 when something did.

## `Convert-EiAdoIntake.ps1`

Turns the output of `Invoke-EiAdoCliIntake.ps1` into the shape `ado.schema.json` wants.

**Parameters:** `-IntakeJson`, `-StoryId`, `-Summary`, `-Root`, `-SkipAttachmentDownload`,
`-Json`, `-Help`.

**Output:** one object ready for `Write-EiArtifact.ps1 -ArtifactType ado`.

It also downloads the images attached to the work item into
`.ei-session-logs/<storyId>/attachments/` and records where each one landed. A download that fails
is a warning, and the rest carry on. `-SkipAttachmentDownload` turns the whole step off.

**Exit codes:** 0 on success. 1 when the intake did not retrieve the story, when the description
is empty, or when the work item id is not a positive number.
