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
