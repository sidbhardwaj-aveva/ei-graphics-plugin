---
name: ei-graphics-core
description: Usage reference for the ten core scripts of an Electrical and Instrumentation (EI) Graphics session, from ADO intake through the shared session bundle.
---
# EI Graphics Core
Ten scripts, all in `scripts/`. The schemas they check against are in `schemas/`.
They all behave the same way. JSON goes to stdout and messages go to stderr. Exit code 0 means it
worked and 1 means it did not. Nothing prompts for input. `-Help` prints the synopsis and exits 0.
Each script says below what a second run of it does. Two of them leave something behind.
Artifacts are written under `<Root>/.ei-session-logs/<storyId>/`. `-Root` defaults to the current
folder, so you rarely pass it.
## `Resolve-EiScriptPath.ps1`
Turns the name of a core script into the absolute path of the installed file.

**Parameters:** `-Name`, `-ScriptRoot`, `-Json`, `-Help`. `-ScriptRoot` defaults to the folder the
script sits in, so the installed layout needs no argument.

With no `-Name` it checks the whole roster instead, which is what the preflight runs. A folder that
does not end `plugins\aveva-ei-graphics\skills\ei-graphics-core\scripts` is refused. That holds
even when it contains files of the right names, so a path built by hand cannot quietly succeed.

**Output:** with `-Name`, the status, the name, the resolved path and the scripts folder. Without
it, the status, the scripts folder and the full roster of paths.

**Exit codes:** 0 when the roster is complete and any named script resolved. 1 when the folder is
missing, is not the core scripts folder, is short a script, or the name is not a core script.
**Run again:** safe. It writes nothing.
## `Write-EiArtifact.ps1`
Checks a payload against its schema, then writes it as JSON.

**Parameters:** `-StoryId`, `-ArtifactType`, `-InputObject`, `-InputJson`, `-Root`, `-Json`,
`-Help`. `-ArtifactType` is one of `story-understanding`, `approved-files` or `ado`. Give the
payload as an object through `-InputObject`, or as text through `-InputJson`.

**Writes:** `.ei-session-logs/<storyId>/<artifact-type>.json`.
**Output:** the path it wrote and the hash it stamped.

For `story-understanding` and `approved-files` it stamps `hash`, never for `ado`, whose schema
allows no such field. `adoHash` inside `story-understanding.json` binds the ADO content instead,
and this script stamps that too, from the `ado.json` beside it. Never work it out yourself. An
`approved-files` list may be empty, which says a person approved changing nothing.

**Exit codes:** 0 when the payload passed and the file was written. 1 when it failed, and the
schema errors are listed on stderr.
**Run again:** safe. The same payload writes over the same file.
## `Write-EiSessionEntry.ps1`
Appends one entry to the session log, and creates the log on the first call.

**Shared parameters:** `-StoryId`, `-Root`, `-Json`, `-Help`.
**To append an entry:** `-Phase`, `-Action`, `-Reasoning`, `-Outcome`, `-DurationMs`,
`-TokensUsed`, `-FilesRead`, `-FilesModified`, `-HumanInput`, `-ScriptOutput`, `-Evidence`.
**To close the session:** `-Finalize`, `-Force`, `-TestsRun`, `-TestsPassed`, `-HumanInteractions`,
`-SessionOutcome`, `-DomainSkillUsed`, `-BugPatternMatched`, `-CommentDeviations`.

The two sets are mutually exclusive. Passing one from each is an error, not a partial write.
`-SessionOutcome` is not called `-Outcome` because the entry and the summary both hold a field
named `outcome`, and one parameter cannot mean two things. `-Evidence` names a `file` and
optionally a `line`, a `symbol` and a `quote`; `-CommentDeviations` names a `commentId` and its
`effect`. Both are lists of hashtables, a missing key is an error, and both surface in the summary.

`-Finalize` works out `completedAt`, `totalDurationMs`, `totalTokens` and `filesModified` from the
entries already written. You supply the rest.

**Writes:** `.ei-session-logs/<storyId>/session.json`, through a temporary file, so a second
append cannot truncate it.
**Output:** the path, the entry count, and the entry just written.
**Exit codes:** 0 on success. 1 when the phase is unknown, or the result would not validate.
**Run again:** not safe. A repeated append leaves a second entry, and the totals `-Finalize` works
out from the entries then count it twice. Check the entry count in the output before appending the
same entry again, and remove a duplicate from `session.json` before finalizing. `-Finalize` itself
refuses a session that already holds a summary, and exits 1 rather than replacing it. Pass `-Force`
when the recorded outcome is wrong and you mean to replace it.
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
**Run again:** safe. It renders the same file from the same session log.
## `Export-EiSessionBundleToShare.ps1`
Copies a completed local session bundle to an internal review share.

**Parameters:** `-StoryId`, `-Root`, `-SharePath`, `-Json`, `-Help`.

It copies `ado.json`, `story-understanding.json`, `approved-files.json`, `session.json`, and
`session-summary.md` into a unique directory under `-SharePath`. Full bundles contain story text,
comments, interaction records, and evidence. Use only a share approved for that material.

**Output:** the local path, the remote path when copied, and a status.
**Exit codes:** 0 after export, or when a share problem leaves the local bundle ready to retry. 1
when the local bundle is missing a file or is not finalized.
**Run again:** not safe. The folder name carries the time and a fresh identifier, so a second run
cannot land on the first one. It leaves a second copy of the story text on the share. Delete the
extra folder, or ask whoever owns the share to.
## `Get-EiDomainSkillCatalog.ps1`
Reads the registry, then reads only the front of each skill document.

**Parameters:** `-RegistryPath`, `-Json`, `-Help`. `-RegistryPath` defaults to
`references/domain-skill-registry.json`, and exists so a test can point at a broken registry.

**Output:** `{ skills: [ { domainId, displayName, skillPath, description, whenToUse[] } ] }`.

The `description` comes from the YAML frontmatter. The `whenToUse` list comes from the
`## When to Use` bullet list. The rest of the skill document is never read.

**Exit codes:** 0 on success. 1 when a `skillPath` points at nothing, or the frontmatter cannot be
read.
**Run again:** safe. It writes nothing.
## `Test-EiScopeDrift.ps1`
Compares the files that changed against the files that were approved.

**Parameters:** `-StoryId`, `-Root`, `-ChangedFiles`, `-Json`, `-Help`.

Leave `-ChangedFiles` out and the script asks git itself, using the diff plus untracked files.
Pass it and the script uses your list instead. Call the script in process with `&` when you pass a
list. Running it with `pwsh -File` flattens the array and the check quietly passes.

**Output:** `{ status, unapproved[], approvedUnchanged[] }`, where `status` is `pass` or `drift`.
An approved file nobody touched is reported, but it is a warning, not a failure.

**Exit codes:** 0 when nothing unapproved changed. 1 when something did.
**Run again:** safe. It writes nothing.
## `Convert-EiAdoIntake.ps1`
Turns the output of `Invoke-EiAdoCliIntake.ps1` into the shape `ado.schema.json` wants.

**Parameters:** `-IntakeJson`, `-StoryId`, `-Summary`, `-Root`, `-SkipAttachmentDownload`,
`-Json`, `-Help`.

**Output:** one object ready for `Write-EiArtifact.ps1 -ArtifactType ado`.

It also downloads the images attached to the work item into
`.ei-session-logs/<storyId>/attachments/` and records where each one landed. A download that fails
is a warning, and the rest carry on. `-SkipAttachmentDownload` turns the whole step off.

The download carries an Azure DevOps token, so only Azure DevOps is contacted. An address is used
only when it is `https` and its host is `dev.azure.com` or ends `.visualstudio.com`. Any other
address is skipped with a warning naming it, and no token is sent to it.

**Exit codes:** 0 on success. 1 when the intake did not retrieve the story, when the description
is empty, or when the work item id is not a positive number.
**Run again:** safe. Each attachment is named from its position and the name on the work item. A
second run writes over the first set instead of adding to it.
## `Invoke-EiStoryIntake.ps1`
Runs `Invoke-EiAdoCliIntake.ps1`, `Convert-EiAdoIntake.ps1`, then
`Write-EiArtifact.ps1 -ArtifactType ado`, in that order. The JSON flows between steps unchanged,
so every attachment link, comment, and hyperlink survives.

**Parameters:** `-WorkItem`, `-StoryId`, `-Root`, `-Json`, `-Help`. A bare integer for
`-WorkItem` routes to `-WorkItemId`; anything else routes to `-WorkItemUrl`.

**Output:** the `ado.json` path, the story id, and the null hash for `ado`.

**Exit codes:** 0 on success. 1 when any step exits non-zero, with the failing step named on
stderr.
**Run again:** safe. Every step it runs writes over its own output.
## `Complete-EiSession.ps1`
Runs `Write-EiSessionEntry.ps1 -Finalize -SessionOutcome`, then `Export-EiSessionSummary.ps1`,
and when `EI_GRAPHICS_SHARE_PATH` is set, `Export-EiSessionBundleToShare.ps1 -SharePath`.

**Parameters:** `-StoryId`, `-SessionOutcome`, `-Root`, `-Force`, `-DomainSkillUsed`,
`-BugPatternMatched`, `-TestsRun`, `-TestsPassed`, `-HumanInteractions`, `-CommentDeviations`,
`-Json`, `-Help`. Everything after `-Force` goes to the finalize step. Pass `-DomainSkillUsed`
whenever a domain skill was used, or the summary tells the maintainer none was.

**Output:** the summary path and, when the share export ran, the exported bundle path.

**Exit codes:** 0 on success. 1 when finalize or summary fails, with the failing step named on
stderr, or when the reported summary file does not exist. A share-export failure only warns.
**Run again:** safe. The finalize step refuses a session already closed, so a second run exits 1
there and never reaches the share. `-Force` is the exception: it reaches the share and leaves a
second copy of the story text. Use it only to replace a wrong outcome, then delete the extra copy.
