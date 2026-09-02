# Build Log — demo-ei-graphics v3

Append only. Never edit an old entry.

## T001 — Repo bootstrap and source check — 2026-08-31T16:10:15Z

**Goal:** Create the repository skeleton, confirm every copy source in Part 2 exists, and
put the three tracking files in place so a later session can resume.

**Resolved $V2 (the old repo):** `C:\Users\siddhant.bhardwaj\OneDrive - AVEVA Solutions Limited\Agent Dev\ei-graphics-plugin`

**Assumptions:** The two repositories sit side by side under the same parent folder, so
`..\ei-graphics-plugin` resolves from the new repo root. Both live in OneDrive, so git
garbage collection is disabled on every commit with `-c gc.auto=0`. The plan file copied to
the repo root is the authoritative build script, and `tools/Test-BuildProgress.ps1` will read
its task headings in T002 rather than carrying its own list. `docs/architecture-v3.md` is a
word-for-word archive of the old `latest-plan.md` and is never edited.

**Files touched:**
- `.gitignore` (new)
- `plan.md` (new)
- `docs/architecture-v3.md` (new, copied)
- `BUILD-PROGRESS.md` (new)
- `BUILD-LOG.md` (new)
- the folder tree from Part 6 (new)

**Acceptance:** All 17 copy sources in the Part 2 table return `True` from `Test-Path`.
`Test-Path` returns `True` for `docs/architecture-v3.md`, `BUILD-PROGRESS.md`, `BUILD-LOG.md`,
`.gitignore` and `plan.md`. `git log --oneline` shows at least one commit.

**Attempts:** 1. The source check found 0 missing files on the first run.

**Decisions:** Created 19 folders from the Part 6 tree and put a `.gitkeep` in each of the 18
that are still empty, so git records them. Used `git init -b main` so the default branch name is
fixed rather than inherited from local git settings. Wrote `BUILD-PROGRESS.md` with a `TODO` row
for all 23 task IDs; the copied `plan.md` contains 23 `#### T0NN` headings, which matches. Left
task titles free of backticks and pipe characters so the table stays easy to parse in T002.

T001 has two commits, not three. The repository did not exist before step 2, so there was no
progress row to mark `IN-PROGRESS` beforehand.

**Result:** DONE at commit 7254028

## T002 — The progress checker — 2026-08-31T16:20:00Z

**Goal:** Write `tools/Test-BuildProgress.ps1`, which decides whether `BUILD-PROGRESS.md` is in a
state a later session can resume from, plus its own Pester tests.

**Assumptions:** The task list is read out of `plan.md` by collecting every `#### T0NN` heading,
never hardcoded, so adding or renumbering a task cannot rot the checker. A commit value is
accepted as a real SHA when it is 7 to 40 lowercase hexadecimal characters; the em dash is the
only other legal value for a row that is not `DONE`. The word `pending` is counted across the
whole table and its position does not matter, because the repair procedure in Part 8 legitimately
puts it in a middle row. The three path parameters exist so the tests can point at fixtures under
`$TestDrive` instead of the live files. This script lives in `tools/`, so T020's parameter roster
and line ceiling do not apply to it, and it needs no `-Help` switch.

**Files touched:**
- `tools/Test-BuildProgress.ps1` (new)
- `tests/tools/Test-BuildProgress.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1` exits 0, and all 20 tests
in `tests/tools/Test-BuildProgress.Tests.ps1` pass.

**Attempts:** 1 for the checker itself. The environment needed two fixes first, described below.

**Decisions:**

The machine had only Pester 3.4.0, which cannot run these tests. Installed Pester for the current
user. The first install pulled 6.1.0, which rejects a `BeforeEach` block written directly in the
file root, and which would also have put the copied v2 tests in T013 and T014 at risk, because
those were written against Pester 5. Removed 6.1.0 and pinned the machine to 5.7.1. Also moved
`BeforeEach` inside the `Describe` block, so the test file is valid under both versions.

Checked the task list in both directions. A plan task with no row is an error, and a row with no
plan heading is an error too. Part 10 warns that every guard bug found while reviewing the plan
was a hardcoded list drifting away from its source, so one direction is not enough.

Accepted a commit SHA as 7 to 40 lowercase hexadecimal characters. Anything else in the Commit
column of a `DONE` row is an error, which is what catches an em dash placeholder left behind by
mistake.

Wrote the report messages to stderr and kept the result object on stdout. Running the script with
`-File` and without `-Json` prints nothing on stdout, because `exit` skips the display formatter,
so the stderr summary line is what a person actually reads. Called in process with `&`, the object
comes back normally, which is what the tests use.

**Result:** DONE at commit c179400

## T003 — The test harness — 2026-08-31T16:40:00Z

**Goal:** Copy `tests/Invoke-PesterTests.ps1` from the old repository, then give it a `-Path`
parameter and make it fail when no tests run.

**Assumptions:** The old harness is 25 lines, already carries `#Requires -Version 7.0`, sets
`$config.Filter.Tag = @('Unit')` and ends with `exit $result.FailedCount`. Every test we write
carries the `Unit` tag, and so do both copied test files, so keeping that filter loses nothing.
A run that discovers zero tests is treated as a failure, because otherwise every later task's
check command becomes a false pass. `-Path` accepts a string array so a subset can be named, and
it defaults to the `tests` folder beside the script rather than to `$PSScriptRoot` alone, which is
the same folder. The code coverage parameters are kept as the old file had them, because the
harness sits outside `plugins/` and T020 does not police its parameter list.

**Files touched:**
- `tests/Invoke-PesterTests.ps1` (copied from the old repository, then changed)

**Acceptance:** All three checks in T003 hold.

1. `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 and runs T002's 20 tests.
2. `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1 -Path ./tests/tools` exits 0.
3. `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1 -Path ./tests/does-not-exist` exits 1.

**Attempts:** 2. The first version failed check 3 and exited 0 on a path that does not exist.

**Decisions:**

The plan asks for `exit 1` when `TotalCount` is zero. That alone was not enough. Pester throws
when it finds no test files, so `Invoke-Pester` never returned and `$result` stayed null. The
zero test guard then compared `$null` against `0`, which is false, and the script fell through to
`exit $result.FailedCount`, which is also null, so it exited 0. That is the exact false pass this
task exists to remove.

Fixed it two ways together. `Invoke-Pester` now runs inside a `try` with `-ErrorAction Stop`, and
the guard tests for a null result as well as a zero count. Either path now exits 1 with a message
naming the path that was searched.

Kept the `Unit` tag filter, the `Detailed` verbosity and the two code coverage parameters exactly
as the old harness had them. Only the two changes the task calls for were made.

**Result:** DONE at commit c61eb07

## T004 — Four schemas: three written, one copied — 2026-08-31T16:55:00Z

**Goal:** Put four schemas under `skills/ei-graphics-core/schemas/`. Write
`story-understanding.schema.json`, `approved-files.schema.json` and `session.schema.json` from the
shapes in `docs/architecture-v3.md`. Copy `ado.schema.json` byte for byte and record its hash.

**Assumptions:** `Test-Json -Schema` on PowerShell 7.6 handles draft-07 well enough for these
four files, and the schema text is passed as a string rather than a file path. All three written
schemas use draft-07, set `additionalProperties` to false, and carry a populated `required` list.
The hash format is the literal text `sha256:` followed by 64 lowercase hexadecimal characters,
anchored at both ends, which matches the `adoHash` and `understandingHash` fields beside it.
Every field of the `summary` object in `session.schema.json` is optional, because `-Finalize`
writes them only at the end and a check partway through a session must still pass. Each session
entry declares `filesRead`, `filesModified`, `humanInput` and `scriptOutput` as optional; without
them, `additionalProperties: false` would reject every real entry. `scriptOutput` is left as a
free-form object, because it holds whatever a called script returned. The copied `ado.schema.json`
is not edited, not loosened, and not rewritten in T013.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/story-understanding.schema.json` (new)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/approved-files.schema.json` (new)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/session.schema.json` (new)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/ado.schema.json` (copied, unedited)
- `tests/data/ported-file-hashes.json` (new, one entry so far)
- `tests/demo-ei-graphics/skills/ei-graphics-core/schemas/Schemas.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 33 new tests
passing, on top of T002's 20.

**Attempts:** 2. The first run failed 16 tests on a PowerShell detail, not on the schemas.

**Decisions:**

Copied `ado.schema.json` and compared the source and destination hashes in the same run, so the
copy is provably byte for byte. Recorded it as the first and so far only entry in
`tests/data/ported-file-hashes.json`. T020 will assert that file holds exactly 6 entries once
T013 and T014 have added the other 5.

The 16 failures were all the same mistake. An ordered dictionary in PowerShell does not expose a
`Clone` method, although a plain hashtable does. Replaced it with a small `Copy-Payload` helper
that builds a fresh ordered dictionary key by key. Key order matters here, because these payloads
are turned into JSON.

Set the session entry `phase` list to the seven phases the archive's worked example uses:
`ado-intake`, `understanding`, `human-checkpoint`, `complexity`, `implementation`, `validation`
and `commit`. T008 needs a closed list so it can reject an invalid `-Phase`.

Left `scriptOutput` free-form, with no `type` keyword. It holds whatever a called script returned,
and the layer guard, the drift check and a test runner all return different shapes. Pinning it
would break the first script whose output changed.

Gave `summary` no `required` list at all, rather than an empty one. That is what lets a session
that is still running validate, which the plan calls load-bearing.

**Result:** DONE at commit 3b3eb31

## T005 — The domain skill registry — 2026-08-31T17:10:00Z

**Goal:** Write `references/domain-skill-registry.json` as a plain index, and
`schemas/domain-skill-registry.schema.json` beside the other four schemas.

**Assumptions:** A `skillPath` is written relative to the plugin folder, so
`skills/termination-drawing/SKILL.md` resolves from `plugins/demo-ei-graphics/`. That is the form
the archive uses, and it is what T010 and T020 will resolve against. The registry holds no
detection terms and no synonyms; matching a story to a domain is the agent's job, using the
descriptions `Get-EiDomainSkillCatalog.ps1` returns. The schema lives in `schemas/` while the data
stays in `references/`, so a reader can tell the contract from the content. No test counts the
domains against a hardcoded number; every count is read from the registry, because adding a domain
skill later must stay a two-file change. The `termination-drawing` skill folder does not exist
yet, so this task does not check that the path resolves. T020 does, once T015 has copied it.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/references/domain-skill-registry.json` (new)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/domain-skill-registry.schema.json` (new)
- `tests/demo-ei-graphics/skills/ei-graphics-core/references/DomainSkillRegistry.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 10 new tests
passing.

**Attempts:** 1.

**Decisions:**

Constrained `skillPath` with the pattern `skills/<name>/SKILL.md` and `id` to lowercase letters,
digits and hyphens. A test then asserts that the path names the same folder as the id, so a typo
in either one is caught by the other.

Checked for the absence of detection terms in both the registry and its schema. Checking only the
data would let someone add the field to the schema and open the door again.

Every count in the tests is read from the registry. Nothing asserts that there is one domain,
because Part 10 says adding a domain skill later must stay a two-file change.

**Result:** DONE at commit 1ebf8c4

## T006 — ei-graphics-core SKILL.md and the plain-language checker — 2026-08-31T17:20:00Z

**Goal:** Write `skills/ei-graphics-core/SKILL.md` as a usage reference for the six core scripts,
then build the Part 3 plain-language checker that scans every file a person reads.

**Assumptions:** `SKILL.md` is written from the parameter rosters in Part 7, because none of the
six scripts exists yet. Its `name` must equal the folder name, `ei-graphics-core`. The checker
hardcodes its target list, because whether a file is human-facing cannot be read off the
filesystem; Part 10 accepts this as the one deliberate exception, and T021 catches its drift by
asserting every listed path exists by then. Part 3 names ten files and `session-summary.md` is
rendered at run time into a gitignored folder, so nine paths are scanned here and T009 covers the
tenth with golden files. Most of the nine do not exist yet, so the scanner reads whichever are
present and ignores the rest. Sentence splitting is done on `.`, `?` and `!` followed by
whitespace, with common abbreviations and version numbers left alone, and fenced code blocks,
tables, headings, link targets and inline code removed before counting. Jargon is matched on word
boundaries and ignoring case, because `termination` must not trip a rule aimed at `terminate`.
The backtick rule checks for a `Verb-EiNoun` name or a `.ps1`, `.json` or `.md` file name that is
not already inside backticks, a fenced block, a link target or a heading.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/SKILL.md` (new)
- `tests/data/jargon-terms.txt` (new, the 18 words from Part 3)
- `tests/PlainLanguageRules.psm1` (new)
- `tests/PlainLanguage.Tests.ps1` (new)
- `tests/demo-ei-graphics/skills/ei-graphics-core/Skill.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 91 tests
passing, 28 of them new.

**Attempts:** 2. The first draft of `SKILL.md` came out at 136 lines, over the 120 line ceiling.

**Decisions:**

Put the four rules in `tests/PlainLanguageRules.psm1` rather than inside the test file. T009 has to
apply the same four rules to the rendered summary, which never exists on disk and so cannot be
scanned here. Two copies of the rules would drift apart. The plan only asks T009 to reuse the word
list, so this goes a little further, and the module is the smaller thing to maintain. It sits
under `tests/`, so it is outside both of T020's sets and outside T019's scan of skill documents.

Cut `SKILL.md` from 136 lines to 118 by folding the writes, output and exit code lines together
per script, rather than by dropping content.

Added `AVEVA` to the acronym exemption list, alongside the seven Part 3 names. It is a company
name, not an acronym, and there is no expansion to write for it. Expanded `EI` properly instead,
as Electrical and Instrumentation, in the skill description.

Frontmatter is scanned, not skipped. The `key:` prefix is stripped and the value is treated as
prose, because the description is written for a person. That is what forced the description to be
shortened into two sentences.

Sentence splitting happens after headings, table rows, list markers and inline code are removed.
Splitting on a full stop also splits version numbers such as 7.0, which only makes the resulting
fragments shorter, so it can never cause a false failure of the 25 word rule.

The backtick rule looks for two things only: a `Verb-EiNoun` name, and a file name ending in
`.ps1`, `.psm1`, `.json`, `.md` or `.txt`. Matching bare paths as well produced too many false
hits, and Part 3's own worked example is a script name.

**Result:** DONE at commit 367b3da

## T007 — Write-EiArtifact.ps1 — 2026-08-31T17:45:00Z

**Goal:** A schema-checked JSON writer for `story-understanding`, `approved-files` and `ado`.

**Assumptions:** `Test-Json -Schema` takes the schema as text, and the schema files sit at
`$PSScriptRoot/../schemas/<artifact-type>.schema.json`. The canonical form used for the digest is
compact JSON with object keys sorted ascending by ordinal, encoded as UTF-8 with no byte order
mark, with the `hash` property left out. Ordinal sorting is done with `[StringComparer]::Ordinal`
rather than `Sort-Object`, because `Sort-Object` compares by culture and would give a different
order on some machines. The file on disk is written with sorted keys, indented, UTF-8 with no byte
order mark and LF line endings; the digest is taken over the compact form, so the two can never
disagree. A `hash` field is stamped for `story-understanding` and `approved-files` only. It is
never stamped for `ado`, because the copied `ado.schema.json` sets `additionalProperties` to false
and declares no such property. Writing the same payload twice produces the same file and the same
hash, so the script is safe to run again.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiArtifact.ps1` (new, 117 lines)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiArtifact.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0. All 15 tests for
this script pass, covering a valid write, a rejected payload, running twice, a stable hash across
runs, a stable hash when the input key order changes, an `ado` write that validates against the
copied schema, and an `ado.json` with no `hash` property.

**Attempts:** 2. Six tests failed on the first run.

**Decisions:**

All six failures were the array unrolling trap that Part 8 warns about. `ConvertTo-CanonicalNode`
returned `@(...)` for a list, and PowerShell unrolled a one-item array back into a bare object, so
`proposedDomains` and `files` arrived at the schema as objects rather than arrays. Returning
`, $items` instead stops the unrolling. One of the failing tests, the one comparing hashes across
two key orders, had been passing for the wrong reason: both runs failed and both hashes were null.
That is a useful reminder that comparing two results is not a test unless each one is also known
to be good.

Sorted keys with `[StringComparer]::Ordinal` rather than `Sort-Object`. `Sort-Object` compares by
culture, so the same payload could hash differently on two machines.

Hashed the compact form, and wrote the indented form to disk. The file stays readable, and the
digest is still whitespace independent, because it is recomputed from the parsed content.

Validated the payload with the `hash` already stamped onto it. The two written schemas both
require `hash`, so validating before stamping would fail every time.

`-ArtifactType ado` is carved out in one place only, at the stamping step. Everything else about
the three artifact types is identical.

**Result:** DONE at commit 9568e0c

## T008 — Write-EiSessionEntry.ps1 — 2026-08-31T18:00:00Z

**Goal:** Append one entry to `.ei-session-logs/<storyId>/session.json`, create the envelope on
the first call, and fill in the summary with `-Finalize`.

**Assumptions:** The 21 parameters split into two mutually exclusive sets, `Append` and
`Finalize`, with `Append` as the default. The four shared parameters carry no set name, so they
belong to both. The list of valid phases is read out of `session.schema.json` rather than repeated
in the script, so the two cannot drift apart. An invalid `-Phase` exits 1 with a message naming
the file and listing the phases, rather than failing as a parameter binding error, because a
binding error is not an exit code a caller can act on. Appending is made atomic by writing a
temporary file beside the target and moving it over, so a second append cannot leave a truncated
file behind. `-Finalize` computes `completedAt`, `totalDurationMs`, `totalTokens` and
`filesModified` from the entries already written, and takes the other six summary fields from its
own parameters, because they cannot be derived. `agent` is the literal `ei-graphics` and
`verbosity` starts as `verbose`, matching the schema default.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiSessionEntry.ps1` (new, 184 lines)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiSessionEntry.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0, with all 13 tests
for this script passing.

**Attempts:** 3. Three tests failed on the first run and three on the second, each time for a
different reason.

**Decisions:**

Found a real bug in round one, not just a bad assertion. Reading the log back with
`ConvertFrom-Json` turns every timestamp string into a date object, and writing it out again then
produced `2026-08-31T16:38:52.0000000Z` in place of `2026-08-31T16:38:52Z`. The schema only asks
for a non-empty string, so it validated, and the change would have gone unnoticed until someone
read the file. Added `ConvertTo-PlainValue`, which walks the structure after reading and turns any
date back into the timestamp we wrote. Added a test that appends twice and then asserts the file
holds three timestamps in the short form and none in the long one.

Round two was a PowerShell detail again. An ordered dictionary has `Contains` but not
`ContainsKey`, although a plain hashtable has both. This is the second time in this build that an
ordered dictionary has behaved unlike a hashtable; T004 hit the same class of problem with
`Clone`.

Read the list of valid phases out of `session.schema.json` instead of repeating it in the script.
An unknown phase is reported with the whole list, and exits 1, rather than failing as a parameter
binding error. A binding error is a terminating exception, and a caller cannot act on it.

Used the parameter sets themselves to make the append and finalize parameters exclusive, so
passing one of each fails before anything is written. The test asserts the resulting message,
which proves nothing was half written.

`-Finalize` writes the four derived summary fields always, and the other six only when given. That
keeps a part-finished session valid, which is what T004 built the optional summary for.

**Result:** DONE at commit 45e49b9

## T009 — Export-EiSessionSummary.ps1 — 2026-08-31T18:20:00Z

**Goal:** Render `session-summary.md` from `session.json`, at both detail levels, in words a
maintainer can act on without knowing this repository.

**Assumptions:** Everything in the rendered file is derived from `session.json` alone. The story
title is not, so the heading names the story number only. Detail level is read from the
`verbosity` field, never from a parameter. Shortening the timeline at `concise` means one row per
phase, showing the last entry of that phase, rather than one row per entry; that is a rule a test
can check. The reasoning trail is dropped at `concise`, and the maintainer section is written at
both levels. Human wait time counts only a `human-checkpoint` entry that carries no `humanInput`,
measured from its timestamp to the next entry; counting every checkpoint entry would add the
reply itself to the wait. Times are cut out of the timestamp string with a regular expression
rather than parsed as dates, so no culture setting can change them. Numbers are formatted with
`InvariantCulture`. No cost is shown and no rate is invented, per Part 10. The fixtures and the
golden files are hand-written and committed in the start commit, before the renderer exists, so
the renderer is written to match them and not the other way round.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Export-EiSessionSummary.ps1` (new, 178 lines)
- `tests/fixtures/session-verbose.json`, `session-concise.json`, `session-empty.json` (new)
- `tests/fixtures/session-summary-verbose.md`, `session-summary-concise.md` (new, hand-written)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Export-EiSessionSummary.Tests.ps1` (new)
- `tests/PlainLanguageRules.psm1` (changed, see below)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 136 tests
passing, 17 of them new. Both golden files match the rendered output exactly.

**Attempts:** 2 for the renderer, plus two passes to fit the line ceiling.

**Decisions:**

Committed the fixtures and both golden files in the start commit, before the renderer existed.
The plan asks for that, and the three commit rule does not allow a fourth commit, so folding them
into the start commit satisfies both.

Hit the timestamp problem from T008 again, from the other side. `ConvertFrom-Json` had already
turned every timestamp into a date object, so casting it to a string gave `08/26/2026 09:02:30`
and the parse failed. Checked what the conversion actually produces: a `DateTime` whose `Kind` is
`Utc`. Added one `Get-Moment` helper that accepts a string, a `DateTime` or a `DateTimeOffset`, and
used it for both the clock column and the wait time. This is the third appearance of the same
trap in this build.

Changed `Get-ProseSentence` in `tests/PlainLanguageRules.psm1` to treat a blank line, a heading, a
table row and a new list item as ending a block. Before the change, the three header lines carry no
full stop, so they ran on into the first line of the reasoning trail and produced a single 25 word
sentence, one word away from failing for no real reason. Blockquote markers are stripped too. Ran
the whole suite afterwards: T006 still passes, so this is an improvement rather than a regression.

Shortening the timeline at `concise` means one row per phase, showing the last entry of that
phase. The plan only says "shorten", and this is a rule a test can state exactly: 11 rows become
7. A rule such as truncating each cell would have been untestable.

Human wait time counts only a `human-checkpoint` entry with no `humanInput`, measured to the next
entry. Counting every checkpoint entry would have added the one second reply itself and given
2m 22s where the archive shows 2m 21s.

The heading names the story number only. The archive's example heading also carries the story
title, but no field in `session.schema.json` holds it, and inventing one is not an option.

No cost is rendered, and a test asserts that none of the three fixtures produces the word cost or
a currency amount.

The first version came out at 203 lines against a ceiling of 180. The plan allows raising a
ceiling once, but only when a script cannot meet it without becoming unclear. That was not the
case here, so the ceiling was left alone. Merged the paired emit calls, folded three repeated
fallback assignments into one `Get-Text` helper, and removed one blank line from the help comment.
It now stands at 178 lines with no loss of clarity.

**Result:** DONE at commit 95d3a1b

## T010 — Get-EiDomainSkillCatalog.ps1 — 2026-08-31T18:40:00Z

**Goal:** Read the registry and report each domain skill, with the description and the when-to-use
list taken from the front of its skill document.

**Assumptions:** None were needed. The task stopped before any work began, under rule 9.

**Result:** BLOCKED. No files were changed.

### What is wrong

T010's acceptance says the catalogue for the **real** registry must return the number of entries
the registry declares, each with a non-empty `whenToUse`. That cannot be made to pass yet.

Checked directly:

| Fact | Value |
|---|---|
| Entries in `domain-skill-registry.json` | 1 |
| Its `skillPath` | `skills/termination-drawing/SKILL.md` |
| That file exists in this repository | no |
| That file exists in the old repository | yes |
| The old file has a `## When to Use` heading | yes |
| The old file has a `description` in its frontmatter | yes |

The file arrives in T015, which runs five tasks later. So T010 depends on T015, and the plan runs
them the other way round.

This is not a case of a missing file that a test can tolerate. Rule 8 says a skipped test is a
blocked task, not a green one, so writing the check to ignore an absent skill is not open to me.
T005 already recorded that the path does not resolve yet, and left that check to T020.

### The options

**Option A. Move T015 to run immediately before T010.** Copy and split `termination-drawing`
first, then build the catalogue against it. Nothing in T015 depends on T010, so the swap is safe.
The T015 row moves above T010 in `BUILD-PROGRESS.md`. All 23 task IDs still appear exactly once,
and no TODO row would sit above the running task, so `Test-BuildProgress.ps1` stays green. Every
task keeps its acceptance exactly as the plan writes it. Nothing new is invented.

**Option B. Copy the skill document early, inside T010.** Put
`termination-drawing/SKILL.md` in place during T010 and leave the split to T015. Task order is
untouched. The cost is that T010 quietly does a piece of T015's work, and T015's copy step then
finds the file already there. Two tasks would own one file.

**Option C. Point the content checks at a fixture registry.** Add a small skill document under
`tests/fixtures/`, aim `-RegistryPath` at it for the description and when-to-use checks, and
assert only structure against the real registry. This weakens the acceptance the plan actually
wrote, and the weakening would have to be undone at T021.

### Recommendation

**Option A.** It is the smallest change, it keeps every task's acceptance exactly as written, it
needs no new fixture, and it leaves the progress checker green. Option B splits ownership of one
file across two tasks. Option C trades away the check the task exists to make.

Waiting for a decision before going further.

## T010 — decision on task order — 2026-08-31T18:50:00Z

**Assumptions:** none. This block records a decision, not work.

The human chose Option A. T015 now runs immediately before T010. In `BUILD-PROGRESS.md` the T015
row moves above the T010 row, and T010 goes back to `TODO`. All 23 task IDs still appear exactly
once, so `tools/Test-BuildProgress.ps1` stays green, and no task's acceptance changes.

**Result:** unblocked.

## T015 — Copy and split termination-drawing — 2026-08-31T18:52:00Z

**Goal:** Copy the old `termination-drawing/SKILL.md` into the plugin and into
`tests/fixtures/`, then split it into `SKILL.md` plus five reference files, losing nothing.

**Assumptions:** The split is done by machine, not by hand. The file is cut into sections at its
real headings, each heading is assigned to exactly one destination by the table in T015, and the
sections are written back in their original order. That is what makes "no content may be lost"
true by construction rather than by inspection. Counted the file directly before trusting any
number in the plan: it has 504 lines, **55** real headings, and **10** `#`-prefixed lines inside
fenced code blocks that are not headings. Both figures match the plan, including
`### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)`, which two earlier drafts of
the plan lost. Fence tracking flips on any line starting with three backticks, so the ghost lines
never reach the heading list. The frontmatter stays with `SKILL.md`, and its `name` is already
`termination-drawing`, which matches the folder name that T019 will check. The reference files get
no new top-level heading, so the per-file counts stay at 8, 7, 12, 4 and 8 as the plan states.
`SKILL.md` gains one heading, `## References`, which is the 56th. The long PowerShell block under
`### Step 2 — Analyse the Log` moves into `log-analysis.md` and leaves a one-line pointer behind;
the `### Step 2` heading itself stays. This skill is copied content, so Part 3 does not apply to
it, and one of its critical rules legitimately contains a word on the jargon list.

**Files touched:**
- `tests/fixtures/termination-drawing-v2-SKILL.md` (new, the before picture, copied unchanged)
- `plugins/demo-ei-graphics/skills/termination-drawing/SKILL.md` (new, 172 lines)
- `plugins/demo-ei-graphics/skills/termination-drawing/references/architecture.md` (new, 8 headings)
- `.../references/composite-key-system.md` (new, 7 headings)
- `.../references/update-flow.md` (new, 12 headings)
- `.../references/log-analysis.md` (new, 4 headings)
- `.../references/bug-patterns.md` (new, 8 headings)
- `tests/demo-ei-graphics/skills/termination-drawing/TerminationDrawingSplit.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 156 tests
passing, 20 of them new.

**Attempts:** 1.

**Decisions:**

Split by machine rather than by hand. The file is cut into sections at its real headings, every
heading is assigned to exactly one destination, and the sections are written back in source order.
Nothing is retyped, so "no content may be lost" holds by construction. The script refuses to run
if any assigned heading is not found in the source, which is what would catch a typo in the
assignment table.

Counted before trusting the plan. The source has 504 lines, 55 real headings and 10 `#` lines
inside fenced code blocks. Both figures match. 16 headings stayed and 39 moved, which is 55.
`SKILL.md` then gained `## References` as the 56th.

The reference files were given no new top-level heading. Adding one would have made the per-file
counts 9, 8, 13, 5 and 9 rather than the 8, 7, 12, 4 and 8 the plan states, and the point of those
numbers is to check the split.

Moved the long command block out of `### Step 2 — Analyse the Log` into `log-analysis.md`, and
left a one-line pointer. It was appended inside the existing
`### Log Analysis Commands (PowerShell)` section rather than under a new heading, so that file
still has exactly 4 headings.

The heading test checks one direction only: nothing lost, nothing in two files. It does not
compare the two sets for equality and does not assert a total. T023 is allowed to add headings
after the live run, and a frozen set would turn that into a build failure. Missing and duplicated
headings are counted and reported separately, as the plan asks.

Added four tests for the numbers earlier drafts of the plan got wrong: the `### Key Files` table
has 14 rows, `## Common Bug Patterns & Fixes` has 7 patterns, `## Critical Rules (Do NOT Violate)`
has 10 rules, and `### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)` travelled
with its parent section. All four hold.

**Result:** DONE at commit 7552aa4

## T010 — Get-EiDomainSkillCatalog.ps1 — 2026-08-31T19:06:00Z

**Goal:** Read the registry, then read only the front of each skill document, and report what the
agent needs to shortlist a domain.

**Assumptions:** T015 has run, so `skills/termination-drawing/SKILL.md` now exists and the
acceptance can be met against the real registry. A `skillPath` is relative to the plugin folder,
which is two levels above the script's own folder. The frontmatter `description` may be a folded
YAML block written with `>`, as the copied skill uses, so continuation lines indented under it are
joined with a space. The when-to-use list is the bullet list under `## When to Use`, and reading
stops at the next heading; the rest of the skill body is never read. A malformed front is one with
no frontmatter block, or with no `description` in it, and both exit 1. Every count in the tests is
read from the registry, never hardcoded, so adding a domain skill stays a two-file change.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Get-EiDomainSkillCatalog.ps1` (new, 119 lines)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Get-EiDomainSkillCatalog.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 169 tests
passing, 13 of them new. The catalogue for the real registry returns as many entries as the
registry declares, each with a description and a non-empty when-to-use list.

**Attempts:** 2.

**Decisions:**

The failure came from a PowerShell rule rather than the logic. Marking a `[string[]]` parameter
`Mandatory` applies a not-null-or-empty check to every element, so the first blank line in a
markdown file was rejected. Dropped `Mandatory` on both array parameters and left a one-line note
saying why, since removing an attribute looks like an oversight otherwise.

Worked the plugin root out from the registry's own folder with
`[System.IO.Path]::GetFullPath`, not `Resolve-Path`. `Resolve-Path` throws when the path does not
exist, and the failure tests deliberately point `-RegistryPath` at a registry whose skill document
is missing. Throwing there would have given the tests an exception instead of the exit code 1 the
plan asks for.

The copied skill writes its description as a folded YAML block with `>`, so the text sits on the
indented lines below the key. Handled both that and a plain one-line value, and added a test that
the folded form comes back as one line with no leading marker.

Reading stops at the next heading after `## When to Use`, and a test proves a bullet in the
following section is not picked up. Two more tests assert that no part of the skill body reaches
the output.

Every count in the tests is read from the registry. Nothing asserts that there is one domain.

**Result:** DONE at commit 556cfe1

## T011 — Test-EiScopeDrift.ps1 — 2026-08-31T19:18:00Z

**Goal:** Compare the files that actually changed against the files a person approved, and report
drift.

**Assumptions:** `approved-files.json` is found the same way T007 wrote it, at
`<Root>/.ei-session-logs/<StoryId>/approved-files.json`. `-ChangedFiles` is the seam that makes
the script testable: supply it and the script uses that list, leave it out and the script asks git
for its diff plus its untracked files. The three test cases are written and watched failing before
the script exists, as the task asks. Paths are compared after turning every backslash into a
forward slash and trimming any leading `./`, because git reports forward slashes while a caller on
Windows may not. Comparison is case sensitive, since the repositories this runs against are read
on case sensitive systems too. An approved file nobody touched is a warning and does not change
the exit code; only an unapproved change does. There is no seal and no scope-change-request
artifact, per Part 10. The tests call the script in process with `&`, never with `pwsh -File`,
which flattens an array argument and would let the check pass silently.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Test-EiScopeDrift.ps1` (new, 99 lines)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Test-EiScopeDrift.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 180 tests
passing, 11 of them new.

**Attempts:** 1, after the tests were watched failing.

**Decisions:**

Wrote all 11 tests first and ran them against a script that did not exist. All 11 failed with a
command-not-found error, which is the proof the task asks for that they are really exercising the
script rather than passing by accident.

Told an omitted `-ChangedFiles` apart from an empty one with
`$PSBoundParameters.ContainsKey('ChangedFiles')`. Testing the variable for emptiness would have
sent the "nothing changed at all" case off to git, and that test would then depend on the state of
this repository.

Added a test that passes three files and asserts three come back. That is the array flattening
trap in Part 8 written as a check, so nobody can quietly switch the call to `pwsh -File` later.

Compared paths after turning backslashes into forward slashes and dropping a leading `./`. Used
`-cnotcontains` so the comparison stays case sensitive, because these repositories are also read
on case sensitive systems, where two names differing only in case are two different files.

The warning for an approved file nobody touched goes to stderr and leaves the exit code at 0. Only
an unapproved change makes it 1.

**Result:** DONE at commit 5907ded

## T012 — Convert-EiAdoIntake.ps1 — 2026-08-31T19:30:00Z

**Goal:** Translate the intake script's output into the shape `ado.schema.json` demands, and fetch
the images attached to the work item.

**Assumptions:** Read the intake script directly rather than trusting a summary of it. Its success
output carries `status`, `reason`, `workItemContext` with `workItemUrl`, `workItemId`,
`organization`, `project` and `authSource`, plus `descriptionText`, `attachmentUrls`,
`commentRetrieval` and `comments`. `attachmentUrls` is a plain array of strings today, so an entry
with no `source` is the normal case and becomes the literal `unknown`; an object entry carrying a
`source` is handled too, because the plan describes one. Both timestamp helpers are written inline
with `InvariantCulture`, and neither old helper file is dot-sourced. The original
`Get-EiUtcTimestamp` has a real bug that is not copied forward: without a culture argument, the
`:` in the format string is the culture's time separator, so a machine using `.` would render
`14.22.10` and fail this task's own `retrievedAt` check. `ConvertTo-EiIsoTimestamp` is rewritten
with all four branches, because `ConvertFrom-Json` may hand back a `DateTime` or a
`DateTimeOffset` and a string must pass through untouched. A payload that did not retrieve
cleanly, an empty description, or a work item id that is not a positive integer each exit 1 with a
message naming the field and the value, rather than surfacing later as a raw schema error out of
`Write-EiArtifact.ps1`. The download path is not covered by a test and is not mocked; it is
exercised in the live run at T022.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Convert-EiAdoIntake.ps1` (new, 160 lines)
- `tests/fixtures/ado-intake-stdout.json` (new, hand-written)
- `tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Convert-EiAdoIntake.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 203 tests
passing, 23 of them new. Every row of the field mapping table is checked one by one.

**Attempts:** 1 for the logic, plus two passes to fit the line ceiling.

**Decisions:**

Read the intake script's success path rather than working from the plan's summary of it, and built
the fixture from the shape it really emits. Worth knowing: `attachmentUrls` is an array of plain
strings, not of objects. The plan describes an entry that may carry its own `source`, so both are
handled, and a bare string becomes `source` of `unknown`.

Wrote both timestamp helpers inline with `InvariantCulture`, and dot-sourced neither old helper.
The original `Get-EiUtcTimestamp` has a real defect that is deliberately not carried forward: with
no culture argument, `:` in the format string is the culture's time separator, so a machine set to
use `.` would produce `14.22.10` and fail this task's own `retrievedAt` check.

`ConvertTo-IsoTimestamp` keeps all four branches. The fixture exercises two of them in one run: the
first comment's date is a real timestamp, which `ConvertFrom-Json` hands over as a `DateTime`, and
the second is the text "yesterday afternoon", which must pass through unchanged. Both are asserted.

Checked the work item id here rather than leaving it to the schema, and covered four bad values:
empty, `0`, `007` and `abc`. Left to the schema, a malformed id surfaces much later as a raw
validation error out of `Write-EiArtifact.ps1`, which is the "validation failed" experience Part 3
exists to prevent.

The download path has no test and is not mocked. It needs a real token and a real network, so it is
exercised in the live run at T022 and nowhere else.

The first version was 174 lines against a ceiling of 160. Trimmed to exactly 160 by shortening the
help comment, folding `Get-UtcTimestamp` onto one line, joining the paired stderr sentences into
single messages, and removing blank lines between statements that belong together. The ceiling was
left alone, because the script fits without becoming unclear.

**Result:** DONE at commit 7329c09

## T013 — Copy ei-azure-devops-cli-intake — 2026-08-31T19:48:00Z

**Goal:** Copy the five files and two fixtures, make the two edits the task calls for, record three
hashes, and prove the whole chain from intake to a schema-valid `ado.json`.

**Assumptions:** The three scripts are copied byte for byte and never edited, so their hashes go
into `tests/data/ported-file-hashes.json`. `SKILL.md`, the copied test file and the two JSON
fixtures are deliberately not hashed, because the first two are edited in this very task. The
copied test file gets exactly the one edit the plan prescribes: the plugin name on the line that
builds `$script:ScriptPath`. The five-level `..` chain above it is untouched, because renaming a
folder does not change how deep it sits. The new fixture-driven cases and the end-to-end chain test
go in a separate file rather than into the copied one, so the copied file keeps a single, easily
reviewed change. The rewritten `SKILL.md` is on Part 3's covered list, so it must pass the four
plain-language rules; that rules out the word URL in prose, which is not one of the seven exempt
acronyms, so the prose says link and `workItemUrl` stays in backticks as a field name. The whole
`## Lifecycle stage` section goes, along with the sentence naming the dropped stage script and the
reference to the dropped run script. A line about `Convert-EiAdoIntake.ps1` is added.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/SKILL.md` (copied, then rewritten)
- `.../scripts/Invoke-EiAdoCliIntake.ps1` (copied, unedited, hashed)
- `.../scripts/helpers/EiWorkItemReference.ps1` (copied, unedited, hashed)
- `.../scripts/helpers/EiAdoTimestamp.ps1` (copied, unedited, hashed)
- `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.Tests.ps1` (copied, one edit)
- `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-123456.json` (copied)
- `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-789012.json` (copied)
- `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/AdoIntakeChain.Tests.ps1` (new)
- `tests/data/ported-file-hashes.json` (changed, now 4 entries)
- `tests/fixtures/ado-intake-stdout.json` (corrected, see below)
- `tests/PlainLanguageRules.psm1` (changed, see below)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 239 tests
passing. The copied Pester file passes all 23 of its own tests. A grep for `workflow-state`,
`lifecycle` or `EIWF-` across the three copied scripts returns zero hits. All three recorded hashes
match.

**Attempts:** 3 for the rewritten `SKILL.md`, which the plain-language checker rejected twice.

**Decisions:**

**A correction to what T012 assumed.** T012's block states that `attachmentUrls` is an array of
plain strings. That is wrong. Reading the copied script directly shows it builds
`[PSCustomObject]@{ url = ...; source = ... }` for every image, and the copied test file has a case
named for it. The T012 block is left as written, because the log is append only, and the record is
corrected here instead.

Two things follow. `tests/fixtures/ado-intake-stdout.json` was rewritten to carry the real object
shape, with sources of `field:System.Description` and `comment:12`. T012's 23 tests still pass
against it, because `Convert-EiAdoIntake.ps1` was already written to accept a string or an object.
The object branch is the one that runs in real use, and it now has a test.

The end-to-end test does not use a hand-written payload at all. It runs the real
`Invoke-EiAdoCliIntake.ps1` against each copied fixture through `-CliWorkItemJson`, pipes the
result through `Convert-EiAdoIntake.ps1`, then through `Write-EiArtifact.ps1 -ArtifactType ado`,
and checks the written file against `ado.schema.json`. Proving the chain by running it is worth
more than proving it against a payload I wrote myself.

The copied test file got exactly one edit, the plugin name. A test now asserts three things about
it: the new name is present, the old name is absent, and the five-level `..` chain above it is
still five levels. That last one is easy to break and hard to notice.

The new fixture-driven cases went into a separate file, so the copied test file keeps a single
reviewable change.

`SKILL.md` lost the whole `## Lifecycle stage` section, the `## Implementation status` section, the
sentence naming the dropped stage script, and the `metadata.dependencies` entry pointing at a skill
this build does not ship. It gained a `## What happens next` section naming
`Convert-EiAdoIntake.ps1` and `Write-EiArtifact.ps1`, and the stop rule for a non-zero exit.

The plain-language checker earned its keep here. It caught a 30 word sentence, a 38 word sentence,
a bare script name in the description, and the word `MIT` from the `license:` line. The first three
were real defects in my writing and were fixed. The fourth was a defect in the checker: it treated
every frontmatter value as prose. `name`, `license`, `allowed_actions` and `allowedTools` are
machine fields, not writing. `Get-PlainLanguageText` now takes only the `description` value, folded
lines included. The whole suite was re-run afterwards and T006 still passes.

Avoiding the word URL in prose was not a stylistic choice. It is a three letter acronym that Part 3
does not exempt, so the checker requires it to be spelled out. Writing link instead is plainer
anyway, and `workItemUrl` stays in backticks where it is a field name.

**Result:** DONE at commit a85ce8b

## T014 — Copy ei-layer-guard — 2026-08-31T20:06:00Z

**Goal:** Copy the three files, change the plugin name in the copied test file, and record two
hashes.

**Assumptions:** `SKILL.md` and `Invoke-EiLayerGuard.ps1` are copied without a single change, so
both are hashed. The test file is the only edited file, and it is deliberately not hashed;
recording a hash for a file we then edit is how T020 breaks. The one edit is the plugin name on the
line that builds `$script:ScriptPath`, and the five-level `..` chain above it stays as it is. This
`SKILL.md` is copied content, so Part 3 does not apply to it and it is not on T006's list; it has
already been checked and holds no banned identifier, so it needs no rewrite. The guard is expected
to keep returning `pass`, `blocked` or `needs-manual-review`, and to keep honouring `-Json`. After
this task `tests/data/ported-file-hashes.json` should hold 6 entries, which is the number T020 will
assert.

**Files touched:**
- `plugins/demo-ei-graphics/skills/ei-layer-guard/SKILL.md` (copied, unedited, hashed)
- `plugins/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1` (copied, unedited, hashed)
- `tests/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.Tests.ps1` (copied, one edit)
- `tests/demo-ei-graphics/skills/ei-layer-guard/scripts/LayerGuardCopy.Tests.ps1` (new)
- `tests/data/ported-file-hashes.json` (changed, now 6 entries)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 254 tests
passing. The copied Pester file passes all 7 of its own tests. Both recorded hashes match.

**Attempts:** 1.

**Decisions:**

Nothing needed rewriting. `SKILL.md` and the script were copied byte for byte, and a scan confirms
neither mentions a dropped skill or the old plugin name. The one edit was the plugin name in the
test file.

Added a test asserting that the test file is **absent** from `ported-file-hashes.json`. The plan
warns that recording a hash for a file we edit is how T020 breaks, so the absence is worth checking
rather than merely intending.

Checked the guard still returns one of `pass`, `blocked` or `needs-manual-review`, and still writes
parsable JSON under `-Json`. The assertion is that the status is one of the three, not which one,
so the test does not freeze behaviour we did not write.

`tests/data/ported-file-hashes.json` now holds 6 entries: 3 from T013, 2 from here and
`ado.schema.json` from T004. That is the number T020 will assert, together with the file list.

The count of `.ps1` files under `plugins/` is now 10, which matches Part 9: six written fresh,
three copied with the ADO intake, one copied with the layer guard.

**Result:** DONE at commit 60b59ac

## T016 — agents/ei-graphics.agent.md — 2026-08-31T20:18:00Z

**Goal:** Write the agent file at about 60 lines, plus the two reference files that keep it short.

**Assumptions:** The rules come from the archive's "Lean agent.md" list, and everything under its
"What's cut" list is left out. The archive names 11 `aveva-rnd` skills as used, which is the number
the test will check for in `rnd-delegation.md`: `code-review`, `git-commit`, `create-pr`,
`git-rebase`, `csharp-conventions`, `refactor`, `nuget-manager`, `test-value-analysis`,
`pr-security-compliance`, `get-reviewresults` and `mermaid-diagrams`. The Checkpoint 2 template has
four headings, taken from the archive: "Files I'll change", "Tests I'll verify", "New tests
needed?" and "Risks". The agent file, `rnd-delegation.md` and `checkpoint-templates.md` are all on
Part 3's covered list, so all three must pass the four plain-language rules; that again rules out
unexplained acronyms such as PR, which is exempt, and others which are not. The archive's "direct
output style" line is not copied as it stands. It is rewritten as the Part 3 rules addressed to the
agent, because Part 10 says Part 3 changes what the agent writes and nothing else.

**Files touched:**
- `plugins/demo-ei-graphics/agents/ei-graphics.agent.md` (new, 69 lines)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/references/rnd-delegation.md` (new)
- `plugins/demo-ei-graphics/skills/ei-graphics-core/references/checkpoint-templates.md` (new)
- `tests/demo-ei-graphics/agents/Agent.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 287 tests
passing, 30 of them new. The agent file is 69 lines, under the 80 line limit. All three files pass
the four plain-language rules.

**Attempts:** 3. One test assertion was brittle, and one plain-language rule caught a real problem.

**Decisions:**

The `aveva-rnd` delegation table and the Checkpoint 2 template went into the two reference files,
with one pointer line each in the agent file. Both would have blown the line budget.

Counted the 11 `aveva-rnd` skills from the archive's "Used" list rather than guessing. The test
checks each of the 11 by name **and** asserts the count is 11, so adding a twelfth without
thinking would fail.

The first failure was mine, in the test rather than the file. A phrase assertion broke because the
sentence happened to wrap across two lines. Fixed by matching against a whitespace-flattened copy
of the file. A content check that breaks when a paragraph is re-wrapped is a check nobody will keep.

The second failure was more interesting. The agent file's own plain-language rule said: write
"start", not "commence". The checker flagged `commence`, correctly, because it was scanning the
prose and there it was. The word is being named as an example, not used. Putting it in backticks
marks it as a token rather than as writing, and the checker strips inline code before scanning.
Part 3 itself has the same sentence, which is why the rule needed a way to quote a banned word.

The archive's "direct output style" line was not copied. It is rewritten as instructions to the
agent, in the same plain words the rest of the file uses.

Everything on the archive's "What's cut" list is absent, and four tests assert that the dropped
names do not appear.

**Result:** DONE at commit 65a506d

## T017 — The manifests — 2026-08-31T20:34:00Z

**Goal:** Write the two marketplace files at the repository root and `plugin.json` inside the
plugin, with the three name fields agreeing.

**Assumptions:** The old files were read for their structure only. Every value that names the old
plugin, and every description, is written fresh. The two marketplace files genuinely use different
bases: in `.claude-plugin/marketplace.json` the `source` resolves from the repository root, while
in `.github/plugin/marketplace.json` the `pluginRoot` resolves from the root but the `source`
resolves from `pluginRoot`, so it is the bare folder name with no prefix. The catalogue entry name
is `demo-ei-graphics-plugin` in both marketplace files, while the plugin itself is
`demo-ei-graphics`. The test reads both names off the filesystem rather than comparing against a
string in the test, because a hardcoded string cannot catch a half-finished rename. The plugin
folder is found by walking up from `plugin.json`: its own folder is `plugin`, then `.github`, then
the plugin folder. `plugin.json` keeps the folder-pointer form, so adding a skill is never a
manifest edit. Neither marketplace file has a `skillPath` key and the test must not ask for one.
The keyword list drops `workflow` and `lifecycle`, because v3 has neither.

**Files touched:**
- `.claude-plugin/marketplace.json` (new, at the repository root)
- `.github/plugin/marketplace.json` (new, at the repository root)
- `plugins/demo-ei-graphics/.github/plugin/plugin.json` (new, inside the plugin)
- `tests/Manifests.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 302 tests
passing, 15 of them new.

**Attempts:** 1.

**Decisions:**

Read both plugin names off the filesystem rather than comparing them against a string written in
the test. The plugin folder is found by walking up from `plugin.json` three levels, exactly as the
plan describes. A hardcoded string would pass happily through a half-finished rename, which is the
one failure this check exists to catch.

Treated the two marketplace files separately, because they really do use different bases. The test
resolves the first `source` from the repository root and the second from `pluginRoot`, and also
asserts that the second carries no `plugins` prefix. Getting that backwards is the mistake the plan
warns about, and it would only show up when the plugin failed to load.

Added a check that `plugin.json` names none of the skill folders found on disk. That is the
filesystem-driven way to state "manifests must never list individual skills", and it will keep
holding as skills are added.

Every description was written fresh. None of the three files carries `ITERATE routing`,
`scope control` or `gated delivery lifecycle`, and a test scans all three for those phrases. Also
dropped `workflow` and `lifecycle` from the keyword list, since this build has neither.

**Result:** DONE at commit b95a93d

## T018 — The documents — 2026-08-31T20:44:00Z

**Goal:** Write the five documents: two readme files, the plugin information file, the plugin
instructions, and the instructions this build follows.

**Assumptions:** The first four are written for someone who has never seen this repository, and
Part 3 applies to them, so the T006 scanner will check them. `.github/copilot-instructions.md` is
build paperwork and Part 3 explicitly exempts it, so it may name things such as PowerShell
conventions plainly. The prerequisites checklist is copied from the archive's preflight list: `az`
signed in with ADO access, a clean git tree, the dotnet toolkit available, the product repository
cloned, and an editor with agent mode. There is no automated preflight, by decision, so the
checklist is prose and not a script. This task runs no banned-name scan of its own, because T019
scans the whole repository one task later and its term file does not exist yet. Writing the word
URL in prose is avoided again, for the same reason as T013: it is not one of the seven exempt
acronyms.

**Files touched:**
- `README.md` (new)
- `PLUGIN-INFO.md` (new)
- `plugins/demo-ei-graphics/README.md` (new)
- `plugins/demo-ei-graphics/INSTRUCTIONS.md` (new)
- `.github/copilot-instructions.md` (new)
- `tests/Documents.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 319 tests
passing, 17 of them new. All five documents exist and are not empty, and
`copilot-instructions.md` names `Test-BuildProgress.ps1`, `gc.auto=0` and `Set-StrictMode`.

**Attempts:** 2. One sentence in the root readme ran to 27 words.

**Decisions:**

All nine of Part 3's covered files now exist, and all nine pass the four rules. This is the first
task at which the T006 scanner has had its whole list to work with. T021 will assert the same
thing, which is the check that the hardcoded list has not drifted.

Wrote two tests that read the filesystem rather than a list. The plugin readme must name every
skill folder that exists on disk, and it must name every artifact a run produces. A skill added
later without a readme entry will fail the first of those.

Put the traps this build actually paid for into `copilot-instructions.md`, not the ones the plan
predicted. The array flattening trap and the culture-sensitive sort came from the plan. The three
about ordered dictionaries, timestamp round-tripping and Pester discovery data were learned here,
in T004, T008, T009 and T006.

Ran no banned-name scan in this task. T019 scans the whole repository one task later, and its term
file does not exist yet, so checking here would have blocked the task for no reason.

**Result:** DONE at commit 7247517

## T019 — The no-orphan check — 2026-08-31T20:56:00Z

**Goal:** Scan the built repository for any name belonging to a skill or script this build dropped,
including the old plugin name.

**Assumptions:** The banned terms live in `tests/data/forbidden-identifiers.txt`, one per line, and
not in the test body; otherwise the test matches itself. The seeded list holds the 23 names the
plan gives. The skipped locations are exactly the seven the plan names, and no others: `docs/**`,
`BUILD-LOG.md`, `BUILD-PROGRESS.md`, `plan.md`, the term file itself, `tests/fixtures/**` and
`.git/**`. The `docs` exclusion is load-bearing, because `docs/architecture-v3.md` is a word for
word archive holding many lines that match, and it is never edited. `plan.md` and `BUILD-LOG.md`
both legitimately name the old plugin folder as a copy source. The scan is case insensitive and
matches a plain substring, not a whole word, because these are identifiers rather than English.
The fail-closed check runs before any scanning and requires at least 23 terms, so an emptied file
cannot turn the guard into a silent pass. Part 2's list of what is deliberately not copied is
checked against the term file in full, skills by folder name and scripts by file name without the
extension.

**Files touched:**
- `tests/data/forbidden-identifiers.txt` (new, 23 terms)
- `tests/NoOrphanReferences.Tests.ps1` (new)
- `tests/demo-ei-graphics/agents/Agent.Tests.ps1` (changed, see below)
- `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/AdoIntakeChain.Tests.ps1` (changed)
- `tests/demo-ei-graphics/skills/ei-layer-guard/scripts/LayerGuardCopy.Tests.ps1` (changed)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 419 tests
passing, 100 of them new. The scan covers every file in the repository outside the seven skipped
locations, and finds nothing.

**Attempts:** 3.

**Decisions:**

The first run failed four files, and every one of them was the same mistake the plan warns about:
a test that names a banned term matches itself. Three of my earlier test files asserted the
absence of `EIWF-`, `Format-EiWorkflowSummary`, `ei-graphics-workflow` and `aveva-ei-graphics` by
writing those names out. The guard was right to flag them.

Fixed it properly rather than by widening the skip list. All three now read the terms from
`tests/data/forbidden-identifiers.txt` and assert that none of them appears. One list, read
everywhere. The skip list stays at exactly the seven locations the plan names.

The fourth failure was in this file itself. It held Part 2's not-copied list as a literal array.
That list is now parsed out of the first paragraph under plan.md's
"What we are deliberately not copying" heading, and the backticked names are reduced to leaf names
with any extension stripped. Deriving it from the plan means the check cannot drift away from the
plan, and this file no longer trips its own scan.

A parser that quietly returns nothing would make the whole check vacuous, so there is a test that
it recovered at least ten names before any of them are looked up. The same reasoning as T020's
parser test.

The old plugin folder name is read off the old repository on disk, not typed here, for the same
self-matching reason.

Kept `lifecycle` out of the term file, because the plan seeds `lifecycle-iterate` and
`lifecycle-implement` rather than the bare word. The agent file is checked for the bare word
separately, where writing it is safe.

**Result:** DONE at commit 8cdc553

## T020 — The script contract check — 2026-08-31T21:08:00Z

**Goal:** Check every `.ps1` under `plugins/` against one of two contracts, and check the recorded
hashes, the script count and the registry.

**Assumptions:** The roster parser is anchored on the `#### T0NN` heading, never on the marker
text, because two rosters say "exactly these 7" and neither the marker nor the count identifies a
task on its own. Inside a task's section, the parser finds the "Parameters, exactly these N"
marker and then reads every `-Name` token to the end of the roster block, which may span several
bullets: T008's 21 names sit in three bullets below its marker, not beside it. Reading stops at
the next paragraph that is not part of the roster. The parser gets its own test, asserting the
exact expected name set for T008 and T012, and asserting that it fails loudly rather than
returning nothing when a roster cannot be found. Getting this parse wrong is the worst failure
available here, because it produces a green suite that checked nothing. The line ceilings live in
one hashtable at the top of the test file, as the plan requires, and none has been raised. The
copied set is hardcoded and gets the reduced contract only: `Set-StrictMode` present, nothing
prompts, no parameter budget, and no requirement for `#Requires` or `-Help`. Every `.ps1` found
under `plugins/` must fall in exactly one set, checked in both directions.

**Files touched:**
- `tests/ScriptContract.Tests.ps1` (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0 with 477 tests
passing, 58 of them new. All six of our scripts are within their ceilings, all six declare exactly
the parameters their task lists, all six recorded hashes match, and the script count is 10.

**Attempts:** 2. The roster parser was wrong on the first run, and its own tests caught it.

**Decisions:**

The parser bug is worth recording, because the plan calls this the worst failure available here.
The first version read from the marker until it ran out of lines that looked like a roster, which
swallowed the paragraph below. For T010 that paragraph says "No `-Root` and no `-DomainId` filter",
so the parser reported 5 names where the roster lists 3, and the check failed against a correct
script. Reading too much is the safe direction; reading too little would have passed silently.

The rule is now simpler and matches how the plan is actually written. The roster is the marker's
own paragraph, ending at the blank line. Only when that paragraph carries no parameter names, which
is true of T008 alone, does the parser fall through to the bullet block below it. That handles both
shapes without special-casing a task by name.

The parser has five tests of its own. Two check exact name sets, for T008's 21 across three
bullets and T012's 7. One proves T007 and T012 are told apart although both rosters say seven. Two
prove it throws rather than returning nothing when the heading or the marker is missing.

Parameters are read from the script with the PowerShell parser, not with a regular expression, so
attributes and line breaks inside the `param()` block cannot confuse it.

The copied set gets a test asserting each of the four has **no** `-Help` switch. The plan says
their absence is expected and must not be fixed, so stating it as a check stops a well-meaning
edit later.

The hash check asserts the count and the file list together, as the plan requires. A count that
disagrees with its own contents is how a check like this rots.

No ceiling was raised. All six scripts fit as written.

**Result:** DONE at commit 4e68ec1

## T021 — Everything green, before the live run — 2026-08-31T21:24:00Z

**Goal:** Confirm every task up to T020 is `DONE` with a real commit, that no `pending` marker or
`BLOCKED` row is left, and that all nine plain-language targets now exist.

**Assumptions:** T022 and T023 may still be `TODO`, because both need a person and a live Azure
DevOps connection, so this task cannot require them. The nine target paths are the ones T006 named
and hardcoded; asserting here that all nine exist is the check that catches that hardcoded list
drifting away from the repository, which Part 10 calls the one deliberate exception to building
lists from the filesystem. The `pending` check reads the Commit column of every row, not the raw
file text, so the word appearing in a task title could not hide a real one. A row is accepted as
done only when its commit value is 7 to 40 lowercase hexadecimal characters, which is the same
rule `tools/Test-BuildProgress.ps1` applies.

**Files touched:**
- `tests/EverythingGreen.Tests.ps1` (new)

**Acceptance:** All four conditions hold.

1. `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1` exits 0.
2. `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0, with 498 tests passing.
3. A grep for `pending` in the Commit column returns zero hits.
4. All nine plain-language targets exist on disk.

**Attempts:** 2.

**Decisions:**

The first run failed three checks, all for the same reason: T021 was asserting its own
completion. While this task runs, its row is `IN-PROGRESS` with no commit and no timestamp, so a
rule reading "everything except T022 and T023 must be DONE" can never pass. Narrowed the scope to
T001 through T020, which is what the plan actually says.

The `pending` check reads the Commit column of each parsed row rather than searching the file text.
A task title containing that word would otherwise produce a false hit, and a real one could hide
behind it.

Closed the T006 gap. That checker hardcodes nine paths, because whether a file is human-facing
cannot be read off the filesystem, and at T006 only one of the nine existed. All nine now exist and
all nine pass. Two tests cover it: one per path, and one asserting the list is nine long and that
nine were found. Without the second, a shortened list would still pass every per-path check.

Added two shape checks from Part 9: the plugin ships exactly the four named skills, and the script
count under `plugins/` is 12 or fewer.

T022 and T023 remain `TODO`. Both need a person and a live Azure DevOps connection, and rule 8
forbids claiming a pass without evidence.

**Result:** DONE at commit 2abf97f

## T022 — Dry run against story 4965976 — 2026-09-02T09:00:00Z

**Goal:** Run the plugin against the real story, with a person watching, and confirm the five
things the task lists.

**Assumptions:** `az` is signed in as siddhant.bhardwaj@aveva.com and story 4965976 is reachable.
It is a Bug, state Closed, titled "SR205 - Insertion of tstrip header symbol below previous symbol
is not observing the symbol extents boundary". Note that this is not the story the archive's worked
example describes, so the run is judged on its own terms rather than against that example. The
organization and project come from the fixed defaults, `AVEVA-VSTS` and `Dabacon Products`, because
the pasted link never decides where a work item is read from. `aveva-rnd` and `aveva-core` are
installed as agent plugins and also cloned beside this repository, so the delegation targets exist.
The product code is at `C:\Git\dabacon-products\Engineering\Modules\EI\Source`, on `main`, with a
clean tree and 2452 C# files. All three files the `termination-drawing` skill names in its Key
Files table resolve there, which is the first real evidence that skill-first resolution will work.
The story is a Bug in state `Closed`, so the fix may already be present in the code; that is
checked before anything is changed rather than assumed either way. The attachment download in
`Convert-EiAdoIntake.ps1` is run for real here, because it is the one path in this build with no
test behind it, by decision, since it needs a real token and a real network.

**A correction to T011 and T012, recorded here because the log is append only.** Part 9's
"three commits per task, in order" check was run for the first time at the end of T021 and found
that T011 and T012 each have only two commits. Both are missing their `build(T0NN): start` commit.
The content discipline held in both cases: each has its `IN-PROGRESS` row and its
`**Assumptions:**` block written before any work, and that was verified. What slipped was
committing that state on its own. The defect is not repairable. Inserting a commit means rewriting
history, which would change every SHA already recorded in `BUILD-PROGRESS.md` and turn one small
fault into twenty wrong records. T010's four commits are not a defect: the extra one is the blocked
commit Part 8 requires.

**Run one: story 4965976, a closed bug.**

The chain ran end to end with no failure: intake, then `Convert-EiAdoIntake.ps1`, then
`Write-EiArtifact.ps1 -ArtifactType ado`, giving a schema-valid `ado.json` with no `hash` property.

**The attachment download works.** Five images were fetched with a real token over the real
network, and every `localPath` points at a file that exists: 37654, 3159, 85286, 47272 and 3037
bytes. Their sources were attributed correctly, two to `System.Description`, two to
`Microsoft.VSTS.TCM.ReproSteps` and one to a comment. This is the one path in the build with no
test behind it, by decision, and it worked on first contact with the real world. It also settles a
question the old skill document raised: two of the five images came from the repro steps field, so
dropping that field from the content list really would have reported a story with images as having
none.

Three design decisions paid off measurably. Reading the discussion changed the answer: the
description had been rewritten twice by the reporter, and the third comment said the spacing was
validated as correct in a later build. An agent that ignored comments would have confidently fixed
a bug that was already fixed. Skill-first resolution behaved honestly: none of the seven bug
patterns mentions extents, spacing, a header symbol or an insertion point, and the agent reported
that rather than forcing a match. Refusing to edit before the cause is understood produced the
right outcome, which was to change nothing.

The verification found `SpacingCalculator.cs`, whose `TopVerticalDistance` and
`BottomVerticalDistance` prefer the symbol's extended bounding box over its plain one whenever the
extended box is defined. That is the extents-driven spacing the story asks for. It arrived in the
commit "Drawing Update and Extended Boundary" on 4 August and was refined by "Spacing isues" on
13 August, which sits between the corrected description on 11 August and the validation comment on
24 August. No code was changed.

**A vocabulary gap worth keeping.** The story says symbol extents. The code says extended bounding
box. A search for the story's own words returns zero files in the drawings area.

**Run two: story 513452, a 2020 user story in state New.**

Run at the request of the person watching, in place of a second pass at 4965976. It exercises the
path run one never reached: the catalogue returns `termination-drawing`, but all seven of its
when-to-use entries are about termination drawings, and the story's own terms return zero hits
across the whole skill. The agent reported no matching domain skill, word for word from
`references/rnd-delegation.md`, rather than forcing the only domain it had.

It also surfaced three things instead of guessing: the acceptance criteria point at a slide deck
that is linked rather than attached, so the examples that define correct behaviour cannot be read;
the story asks its own open question about multi-tier terminals; and it has sat in state `New`
since September 2021. The person agreed it is not actionable as written. No scope was proposed and
no source file was read.

**Three defects found by reading the run one summary as a maintainer would.**

1. It said "1 file changed" when nothing was changed. `ado.json` had been passed to
   `-FilesModified`, and `-Finalize` rolls that into the summary, so the agent's own output was
   counted as a source edit. A maintainer-facing file that states something false is worse than one
   that says nothing.
2. It said "Human wait time: 0s" when the real wait was about five minutes. The arithmetic was
   right and the data was wrong, because both checkpoint entries were written afterwards in one
   batch.
3. The improvement opportunity mixed source files with the agent's own artifacts and the skill's
   own documents, so the useful entries were buried.

**Run two proves the first two are fixed by logging discipline, not by code.** Writing the
`present-understanding` checkpoint entry before asking, and keeping artifacts out of `-FilesModified`,
turned `0s` into a true `2m 13s` and `1 file changed` into `0 files changed`. The third is not
fixable that way and is left for T023: the renderer has to separate source reads from the agent's
own reads, because "check them against the Key Files table" only makes sense for source files.

**One more defect, in the copied intake script.** The stored `ado.json` holds `U+00C6` where an
apostrophe belongs, and contains no `U+2019` anywhere. This was checked against the file bytes, not
the console, so it is real corruption and not a rendering artefact. The script is copied byte for
byte and hashed, so it is recorded here rather than edited.

**A fourth defect, and the one with teeth: T019's guard scans run output.** The scan walks the
whole repository with `-Force` and skips exactly the seven locations the plan names.
`.ei-session-logs/` is not one of them, because on a clean checkout that folder does not exist, so
nothing revealed this until a live run created it. All 13 files from these two runs are now inside
the scan, which is why the suite went from 498 tests to 511. They pass, but only by luck: a story
whose description happened to mention one of the 23 banned identifiers would fail the build, and
the failing text would be someone else's story rather than anything in this repository. That folder
is gitignored and is not part of the built repository, so it belongs in the same category as the
archive, the fixtures and `.git`. Fixing it means adding an eighth entry to a list the plan pins
down at seven, so it is raised for a decision rather than changed here.

**Status.** T022 is not complete, and its row stays `IN-PROGRESS`. Of its five conditions, the
artifact list is four of five, because no file change was approved on either story, so
`approved-files.json` was correctly never written. The attachment condition passed on run one, and
run two had no images, which is recorded here as the plan asks. The command budget held. Two
conditions remain unmet: neither story reached the second checkpoint, because neither warranted a
code change, and no fresh reader has yet been given the summary. Rule 8 says no evidence means no
pass.





















