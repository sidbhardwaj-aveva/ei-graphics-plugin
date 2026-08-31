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

**Result:** DONE at commit pending

