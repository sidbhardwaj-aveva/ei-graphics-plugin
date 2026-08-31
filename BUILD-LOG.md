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

**Result:** DONE at commit pending




