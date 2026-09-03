# Build plan — demo-ei-graphics v3

Give this whole file to Copilot in a new, empty repository. It is the complete build script.
Copy it to the new repo root as `plan.md`.

This file replaces `new-repo-build-plan.md`. That file is dead. Do not read it.

## Before you start

**Three folders matter.**

| What | Where |
|---|---|
| Parent folder | `C:\Users\siddhant.bhardwaj\OneDrive - AVEVA Solutions Limited\Agent Dev` |
| New repo (you build this) | `<parent>\ei-graphics-plugin-v3` |
| Old repo (you copy from) | `<parent>\ei-graphics-plugin` |

The two repos sit side by side. So from the new repo root, the old one is always at
`..\ei-graphics-plugin`.

Create the new folder, run `git init` inside it, and open it as your VS Code workspace before
you start.

### The plugin has a new name

The old plugin is called `aveva-ei-graphics`. This one is called `demo-ei-graphics`.

That name is the plugin's identity. It appears in three places, and all three must match or the
plugin will not load:

1. the folder name — `plugins/demo-ei-graphics/`
2. `plugin.json`, the `name` field
3. `.claude-plugin/marketplace.json`, the `plugins[0].name` field and its `source` path

The test folder matches too: `tests/demo-ei-graphics/`.

**The old name still appears in this plan, and that is correct.** It is the name of the folder
you copy *from*. Every source path keeps it. Every destination path uses the new name. If you
ever copy a source path straight into a destination, you have made a mistake.

Two other plugins, `aveva-rnd` and `aveva-core`, keep their names. They are separate products.
The skill `ei-graphics-core` is inside our plugin and is not renamed.

### Both repos live in OneDrive

Expect sync problems. See Part 8 for the two you will hit. Pause OneDrive sync if you can.

### What you need installed

| Thing | Notes |
|---|---|
| PowerShell 7 or later | Every script we write starts with `#Requires -Version 7.0` |
| Pester 5 or later | We use the `New-PesterConfiguration` API |
| git | Use `git -c gc.auto=0 commit` because of OneDrive |
| `az` CLI with the Azure DevOps extension | Only needed for the live run at the end |
| The `aveva-rnd` and `aveva-core` plugins | Not bundled. Only needed for the live run |

---

## Part 1 — The rules

You are building a plugin from scratch. The build is long. Your session will probably be
interrupted at some point.

**So every task must leave the repo in a state you can resume from.** That is the single most
important requirement here. Everything below serves it.

### Nine rules that never bend

1. **One task at a time.** Never start the next task until the current one says `DONE`.

2. **A task is done when its check command exits with code 0.** Not when it looks right.

3. **Every task ends by recording itself.** In this order: finish the `BUILD-LOG.md` entry,
   then update `BUILD-PROGRESS.md`, then commit. Log first, because the progress checker reads
   the log.

4. **Three commits per task**, always in this order:
   - `build(T0NN): start <title>`
   - `build(T0NN): <title>`
   - `chore(T0NN): record commit sha`

   Never use `git commit --amend`.

   The first task is the exception. It has two commits, not three, because the repo does not
   exist until step 1 of that task. There is no progress row to mark beforehand.

5. **Only machines decide pass or fail.** If a rule can pass or fail, write it as a PowerShell
   script with an exit code and a Pester test. Never let the model judge.

6. **Do not use subagents.** Do the work in the main thread so the log stays complete.

7. **Three attempts, then stop.** Three failed attempts at a check is the limit. Do not make a
   fourth. Mark the task `BLOCKED`, write why in `BUILD-LOG.md`, commit, and ask the human.

8. **No evidence means no pass.** A skipped test is a blocked task, not a green one.

9. **If a task can be read two ways, stop.** Do not pick one. Write the options and your
   recommendation in `BUILD-LOG.md`, set the row to `BLOCKED`, commit, and ask.

---

## Part 2 — Where the files come from

Most of this build is genuinely new. Most tasks write fresh files from the design document.

But six tasks copy working, already-tested files out of the old repo: T001, T003, T004, T013,
T014 and T015. Do not rewrite those from memory. They work, and their tests come with them.

Set this once and use it everywhere:

```powershell
# run from the new repo root
$V2 = (Resolve-Path '..\ei-graphics-plugin').Path

# if the repos are not side by side, use the full path instead
# $V2 = 'C:\Users\siddhant.bhardwaj\OneDrive - AVEVA Solutions Limited\Agent Dev\ei-graphics-plugin'
```

### What gets copied

Sources are relative to `$V2`. Destinations are relative to the new repo root.

**Both columns are spelled out in full on purpose.** The plugin folder is renamed, so no row can
say "same path". Read the destination column. Do not guess it from the source.

| Task | Copy this | To here |
|---|---|---|
| T001 | `latest-plan.md` | `docs/architecture-v3.md` |
| T003 | `tests/Invoke-PesterTests.ps1` | `tests/Invoke-PesterTests.ps1` |
| T004 | `plugins/aveva-ei-graphics/skills/ei-workflow-state/schemas/ado.schema.json` | `plugins/demo-ei-graphics/skills/ei-graphics-core/schemas/ado.schema.json` |
| T013 | `plugins/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/SKILL.md` | `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/SKILL.md` |
| T013 | `plugins/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.ps1` | `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.ps1` |
| T013 | `plugins/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1` | `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiWorkItemReference.ps1` |
| T013 | `plugins/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1` | `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1` |
| T013 | `tests/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.Tests.ps1` | `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/scripts/Invoke-EiAdoCliIntake.Tests.ps1` |
| T013 | `tests/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-123456.json` | `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-123456.json` |
| T013 | `tests/aveva-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-789012.json` | `tests/demo-ei-graphics/skills/ei-azure-devops-cli-intake/fixtures/work-item-789012.json` |
| T014 | `plugins/aveva-ei-graphics/skills/ei-layer-guard/SKILL.md` | `plugins/demo-ei-graphics/skills/ei-layer-guard/SKILL.md` |
| T014 | `plugins/aveva-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1` | `plugins/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1` |
| T014 | `tests/aveva-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.Tests.ps1` | `tests/demo-ei-graphics/skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.Tests.ps1` |
| T015 | `plugins/aveva-ei-graphics/skills/termination-drawing/SKILL.md` | `plugins/demo-ei-graphics/skills/termination-drawing/SKILL.md`, then split |
| T015 | `plugins/aveva-ei-graphics/skills/termination-drawing/SKILL.md` | `tests/fixtures/termination-drawing-v2-SKILL.md` (the before picture) |
| T017 | `plugins/aveva-ei-graphics/.github/plugin/plugin.json` | read only — write a fresh one at `plugins/demo-ei-graphics/.github/plugin/plugin.json` |
| T017 | `.claude-plugin/marketplace.json` at the **old repo root** | read only — write a fresh one at the same place in the new repo |
| T017 | `.github/plugin/marketplace.json` at the **old repo root** | read only — write a fresh one at the same place in the new repo |

### One edit the copied tests do need

The two copied test files find the repo root like this:

```powershell
$repoRoot = Join-Path $PSScriptRoot '..' '..' '..' '..' '..'
```

**Do not touch those `..` chains.** Renaming a folder does not change how deep it sits, so five
levels is still right.

**But the line after it hardcodes the old plugin name**, like this:

```powershell
$script:ScriptPath = Join-Path $repoRoot 'plugins' 'aveva-ei-graphics' 'skills' ...
```

Change `aveva-ei-graphics` to `demo-ei-graphics` in both copied test files. Without this they
point at a folder that does not exist, and T019 fails them anyway for using a banned name.

This is why those two test files are **not** in the hash list. See T020.

### Everything else is written from scratch

That includes all six core scripts, the registry, the agent file, the manifests, and every
document.

There are five schemas. Four are written fresh (three in T004, one in T005). One is copied:
`ado.schema.json`.

**Why we copy `ado.schema.json` from a skill we are otherwise dropping.** It is data, not code.
It has no script references and nothing to dot-source. It describes exactly what the copied
`Invoke-EiAdoCliIntake.ps1` produces. Which skill happened to own it does not matter. Its body
has been read and contains no banned name, so it passes T019 as is.

**Checked:** every source path above exists in the old repo. The two `marketplace.json` files
are at the old repo *root*, not under `plugins/`.

### What we are deliberately not copying

`ei-graphics-workflow`, `ei-workflow-state`, `ei-scope-resolver`, `ei-scope-validator`,
`ei-vocabulary-navigator`, `ei-bug-reproducer`, `ei-test-scaffolder`,
`tools/Test-EiGraphicsSpecSync.ps1`, `Invoke-EiAdoIntakeStage.ps1`, and `EiTestPreflight.ps1`.

These are the scripts v3 exists to delete.

**The one number that was actually counted is 36.** The old repo has 36 `.ps1` files under
`plugins/`, across 10 skill folders. The new repo ends with **10**: four copied from those 36,
and six written fresh. So **32 of the old 36 are dropped**. Do not compute `36 − 10` and say 26;
that would count the six new scripts as survivors. Every other count in this plan comes from
36, 10, 4 and 6. Do not invent a fifth number.

**Why the last two are dropped.** Both exist only to drive the old lifecycle gate.
`Invoke-EiAdoIntakeStage.ps1` dot-sources `EiWorkflowState.ps1` and calls
`Set-EiWorkflowStage.ps1` and `Write-EiWorkflowArtifact.ps1`. `EiTestPreflight.ps1` hardcodes a
path into `ei-workflow-state/scripts/`. Neither can be copied without dragging in the skill we
are removing.

**Do not try to strip them down. Drop them.** If you find yourself reaching for one, read
Part 10 again.

**One thing we do salvage from the dropped stage script: its field mapping.** T012 rebuilds it
from scratch. Read on.

### If the old repo is not there

If `Resolve-Path '..\ei-graphics-plugin'` fails, the new repo was not created beside the old
one. Stop at T001, tell the human the expected layout, and ask.

Do **not** rebuild the copied scripts from this plan's description. They carry behaviour this
document does not specify, and your version would be quietly wrong.

---

## Part 3 — Writing for people

Everything a human reads must make sense to someone who has never seen this repo. That covers
the session summary, the agent's replies, the documents, and every error message.

This is a product requirement, not a style preference. The session summary exists so a
maintainer can act on it. If they have to decode it first, it has failed.

### Four rules, all checked by a script

1. **Sentences of 25 words or fewer.** One idea per sentence.

2. **No jargon from `tests/data/jargon-terms.txt`.** Seed that file with these 18 words, one per
   line. Match whole words only, ignoring case:

   `leverage`, `utilise`, `utilize`, `orchestrate`, `synergy`, `paradigm`, `holistic`, `robust`,
   `seamless`, `facilitate`, `endeavour`, `endeavor`, `commence`, `subsequent`, `aforementioned`,
   `heretofore`, `nomenclature`, `instantiate`

   Use the ordinary word instead. Write "start", not "commence".

3. **Put code names in backticks.** Any `Verb-EiNoun` name, file name, or path in human-facing
   prose sits inside backticks. Then it reads as a name, not as a word.

4. **Spell out an acronym the first time each file uses it.** These are exempt: ADO, CLI, JSON,
   PR, YAML, SHA, MD.

**Every error message names the file and says what to do next.** "Validation failed" is not
good enough. This is:

> `approved-files.json` has no `hash` field. Re-run `Write-EiArtifact.ps1`.

### Which files this covers

**It applies to files we write ourselves:**

- the rendered `session-summary.md`
- `agents/ei-graphics.agent.md`
- `plugins/demo-ei-graphics/skills/ei-graphics-core/SKILL.md`
- `plugins/demo-ei-graphics/skills/ei-azure-devops-cli-intake/SKILL.md` (T013 rewrites it, so it
  counts as ours)
- the root `README.md`, the plugin `README.md`, `PLUGIN-INFO.md`, `INSTRUCTIONS.md`
- `skills/ei-graphics-core/references/rnd-delegation.md` and `checkpoint-templates.md`
- the messages our own scripts write to stderr

That is ten files, and it is the complete list. T006's checker hardcodes exactly these paths.

**One of the ten is not a repo file.** `session-summary.md` is rendered at run time into
`.ei-session-logs/`, which is gitignored, so a filesystem scan will never find it. T009's golden
files carry the check for that one instead. T006 skips it, leaving nine paths to scan.

**It does not apply to copied files, or to build paperwork.** So it skips `plan.md`,
`docs/architecture-v3.md`, `BUILD-LOG.md`, `BUILD-PROGRESS.md`,
`.github/copilot-instructions.md`, anything under `tests/`, and every copied file.

**Copied files are exempt even after we reorganise them.** The `termination-drawing` skill is a
worked example: T015 splits it into six files, but the words are the old author's, not ours.
Judging it by our rules would mean rewriting technical prose we were told to preserve. One of
its critical rules already contains the word "subsequent", which is on the jargon list. That is
fine. It is exempt.

The same goes for `ei-layer-guard/SKILL.md`, which we copy without changing a word.

### Why whole-word matching matters

The `termination-drawing` skill uses the word "termination" hundreds of times. If the checker
matched substrings, a word like `terminate` would flood it with false hits. Someone would then
delete the checker. Match on word boundaries.

### What we deliberately do not check

Tone, and whether an explanation is actually useful. Those are human judgements, and rule 5 in
Part 1 forbids turning a judgement into a test.

The four rules above are rough stand-ins. Real readability gets confirmed by a person at T022.

---

## Part 4 — Tracking progress

Three files, all committed to git. Together they let a fresh Copilot session pick up where the
last one stopped, without re-reading the whole repo.

Build them in T001 and T002, before anything else.

### `BUILD-PROGRESS.md` — where are we

The single source of truth. A table with exactly these columns:

```markdown
# Build Progress — demo-ei-graphics v3

**Plan:** `plan.md`
**Current task:** T007
**Last verified green:** T006 (2026-08-31T14:22:10Z)

| ID | Task | Status | Commit | Acceptance verified at |
|----|------|--------|--------|------------------------|
| T001 | Repo bootstrap | DONE | a1b2c3d | 2026-08-31T12:04:00Z |
| T002 | Progress gate script | DONE | e4f5g6h | 2026-08-31T12:31:00Z |
| T007 | Write-EiArtifact.ps1 | IN-PROGRESS | — | — |
| T008 | Write-EiSessionEntry.ps1 | TODO | — | — |
```

**Status is one of exactly four words:** `TODO`, `IN-PROGRESS`, `DONE`, `BLOCKED`.

**The rules the checker enforces:**

- At most one row is `IN-PROGRESS`.
- Every `DONE` row has a timestamp, and a Commit value that is either a SHA or the word
  `pending`.
- The word `pending` appears in **at most one row in the whole table**, and only in a `DONE`
  row. It produces a warning, not an error. It is the normal state between the task commit and
  the SHA commit. Two `pending` values anywhere is an error.

  **Position does not matter, only the count.** An earlier draft demanded that `pending` sit in
  the last `DONE` row. That made the repair procedure in Part 8 impossible, because fixing an
  early task while later ones are done legitimately puts `pending` in the middle. T021 requires
  zero `pending` rows.
- No `TODO` row sits above an `IN-PROGRESS` row. Tasks run in order.
- The `Current task` header matches the `IN-PROGRESS` row, or the first `TODO` row if there is
  none.
- Every task ID in Part 7 appears exactly once. The checker gets that list by reading `plan.md`
  and collecting every `#### T0NN` heading. It does not carry its own copy.
- An `IN-PROGRESS` row must have a matching `## T0NN` block in `BUILD-LOG.md` containing an
  `**Assumptions:**` line.

### `BUILD-LOG.md` — the journal

Only ever append. Never edit an old entry. One block per task attempt:

```markdown
## T007 — Write-EiArtifact.ps1 — 2026-08-31T13:10:00Z

**Goal:** Schema-checked JSON writer for story-understanding and approved-files.
**Assumptions:** Test-Json -Schema works on the installed PowerShell 7; canonical JSON uses
  sorted keys and no trailing whitespace.
**Files touched:**
- plugins/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiArtifact.ps1 (new)
- tests/demo-ei-graphics/skills/ei-graphics-core/scripts/Write-EiArtifact.Tests.ps1 (new)

**Acceptance:** `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1 -Path ...` exits 0
**Attempts:** 2 (first failed: Test-Json needs -SchemaFile on 7.4 and later)
**Decisions:** Chose Test-Json over a hand-written checker. Rejected
  ConvertFrom-Json -AsHashtable because property order is lost.
**Result:** DONE at commit e4f5g6h
```

The `**Assumptions:**` line is required, and you write it in step 1, **before** doing the work.
It is what rule 9 produces. A resuming session reads it to understand why things are the way
they are. Being wordy here is correct. Being terse is not.

### `tools/Test-BuildProgress.ps1` — the checker

It checks the rules listed above. Its contract matches the old repo's convention:

```
Output object: { Status = 'Valid'|'Invalid'; Errors = @(); Warnings = @(); Details = @{} }
Exit code:     0 means valid, 1 means invalid
-Json switch:  JSON to stdout, messages to stderr
```

Run it as part of every task's check. If `BUILD-PROGRESS.md` is broken, the build is not
resumable, so the task has not really passed.

---

## Part 5 — Resuming after a break

### Paste this into a fresh Copilot session

```
Resume the demo-ei-graphics v3 build.

1. Read plan.md, all of it.
2. Read BUILD-PROGRESS.md and the last 3 entries of BUILD-LOG.md.
3. Run: pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1
   If it exits 1, fix BUILD-PROGRESS.md before doing anything else.
4. If a DONE row has Commit = "pending", find the SHA instead of redoing the task:
   git log -1 --format=%h --grep="^build(T0NN):"
   Write it into the Commit column and make the chore(T0NN) commit. Do NOT redo the task.
5. Run: git status --porcelain
   - Clean tree, one IN-PROGRESS row -> the task started but wrote nothing. Redo it.
   - Dirty tree, one IN-PROGRESS row -> the task was cut off mid-write. Re-run its check
     command. If it passes, finish the task. If it fails, finish the work, then re-check.
   - Clean tree, no IN-PROGRESS row  -> start the first TODO task.
   - Dirty tree, no IN-PROGRESS row  -> STOP. Show me the diff and ask before touching anything.
6. Run: pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
   Everything marked DONE must still pass. If not, that is a regression: set the failing task
   back to IN-PROGRESS and fix it before moving on.
   SKIP this step if the last DONE task is T001 or T002. The test harness does not exist yet.
7. Continue from the first task that is not DONE.

Rules: one task at a time; the check must exit 0 before DONE; three commits per task (two for
T001); three tries then mark BLOCKED and stop.
```

### The loop to follow for every task

```
1. Set the row to IN-PROGRESS. Update the "Current task" header.
   Append the BUILD-LOG.md block with its **Assumptions:** line now, before any work.
   Commit: build(T0NN): start <title>
2. Do the work.
3. Run the task's check command. It must exit 0.
   - If not, fix and retry. After the third failed attempt, stop: set BLOCKED, log, commit.
4. Run: pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1   (must exit 0)
5. Run: pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1   (must exit 0)
   SKIP for T001 and T002 only. No harness exists until T003.
6. Finish the BUILD-LOG.md block: attempts, decisions, result.
7. Set the row to DONE, fill in the timestamp, set Commit to the word `pending`.
8. Commit: build(T0NN): <title>
9. Write the resulting SHA into the Commit column, replacing `pending`.
   Commit: chore(T0NN): record commit sha
```

**T001 skips steps 1, 4 and 5.** The repo, the checker and the harness do not exist yet. It runs
steps 2, 3, 6, 7, 8 and 9 only. That is why it has two commits instead of three.

The step 1 commit is what makes an interrupted task detectable. Do not skip it.

**Never use `git commit --amend`.** The `pending` marker and the `chore` commit exist so that
amending is never needed. History stays honest.

---

## Part 6 — What the finished repo looks like

```
ei-graphics-plugin-v3/
├── BUILD-PROGRESS.md                  # where we are            (T001)
├── BUILD-LOG.md                       # the journal             (T001)
├── plan.md                            # this file               (T001)
├── README.md                          # what it is, how to run  (T018)
├── PLUGIN-INFO.md                     #                         (T018)
├── .gitignore                         #                         (T001)
├── .claude-plugin/marketplace.json    # REPO ROOT               (T017)
├── .github/plugin/marketplace.json    # REPO ROOT               (T017)
├── .github/copilot-instructions.md    #                         (T018)
├── docs/
│   └── architecture-v3.md             # copy of latest-plan.md  (T001), never edited
├── tools/
│   └── Test-BuildProgress.ps1         # progress checker        (T002)
├── plugins/demo-ei-graphics/
│   ├── .github/plugin/plugin.json     # "name": "demo-ei-graphics"  (T017)
│   ├── README.md                      #                         (T018)
│   ├── INSTRUCTIONS.md                #                         (T018)
│   ├── agents/
│   │   └── ei-graphics.agent.md       # about 60 lines          (T016)
│   └── skills/
│       ├── ei-graphics-core/          # 6 scripts + schemas     (T004–T012, T016)
│       │   ├── SKILL.md
│       │   ├── schemas/
│       │   │   ├── story-understanding.schema.json
│       │   │   ├── approved-files.schema.json
│       │   │   ├── session.schema.json
│       │   │   ├── ado.schema.json     # COPIED, strict, unedited
│       │   │   └── domain-skill-registry.schema.json
│       │   ├── references/
│       │   │   ├── domain-skill-registry.json
│       │   │   ├── rnd-delegation.md
│       │   │   └── checkpoint-templates.md
│       │   └── scripts/
│       │       ├── Write-EiArtifact.ps1
│       │       ├── Write-EiSessionEntry.ps1
│       │       ├── Export-EiSessionSummary.ps1
│       │       ├── Get-EiDomainSkillCatalog.ps1
│       │       ├── Test-EiScopeDrift.ps1
│       │       └── Convert-EiAdoIntake.ps1
│       ├── ei-azure-devops-cli-intake/   # copied  (T013)
│       ├── ei-layer-guard/               # copied  (T014)
│       └── termination-drawing/          # copied and split (T015)
│           ├── SKILL.md
│           └── references/
│               ├── architecture.md
│               ├── composite-key-system.md
│               ├── update-flow.md
│               ├── log-analysis.md
│               └── bug-patterns.md
└── tests/
    ├── Invoke-PesterTests.ps1
    ├── PlainLanguage.Tests.ps1         # Part 3 checker          (T006)
    ├── NoOrphanReferences.Tests.ps1    #                         (T019)
    ├── ScriptContract.Tests.ps1        #                         (T020)
    ├── data/
    │   ├── forbidden-identifiers.txt
    │   ├── jargon-terms.txt
    │   └── ported-file-hashes.json
    ├── fixtures/
    │   ├── termination-drawing-v2-SKILL.md
    │   └── ado-intake-stdout.json
    ├── tools/Test-BuildProgress.Tests.ps1
    └── demo-ei-graphics/skills/<skill>/scripts/*.Tests.ps1
```

**The test folder matches the plugin name.** It is `tests/demo-ei-graphics/`, not the old name.
The copied test files come from the old name and land under the new one.

### Why the two marketplace files sit at the repo root

They use different bases, and this trips people up:

- `.claude-plugin/marketplace.json` sets `"source": "./plugins/demo-ei-graphics"`. That path is
  **relative to the repo root**.
- `.github/plugin/marketplace.json` sets `"pluginRoot": "./plugins"` and then
  `"source": "demo-ei-graphics"`. The `pluginRoot` is relative to the repo root, but the
  `source` is **relative to `pluginRoot`**, not to the root.

Moving either file under `plugins/demo-ei-graphics/` breaks its paths. `plugin.json` stays
inside the plugin folder.

### One difference from the old repo

There is no spec-sync gate here, and no `specs/` folder. `BUILD-PROGRESS.md` and `BUILD-LOG.md`
do that job for the duration of the build.

---

## Part 7 — The tasks

Run every check command from the repo root. Below, `$P` means
`./tests/Invoke-PesterTests.ps1`.

There are 23 tasks in seven phases, Phase 0 through Phase 6.

---

### Phase 0 — Get the repo going

#### T001 — Repo bootstrap and source check

**Do this, in order.**

1. Resolve `$V2 = (Resolve-Path '..\ei-graphics-plugin').Path`. Check that every source path in
   the Part 2 table exists. Print a found/missing table. If the sibling folder does not resolve,
   or anything is missing, stop and ask the human. Do not improvise replacements.
2. Run `git init`.
3. Write the resolved `$V2` into `BUILD-LOG.md`, so a later session inherits it.
4. Create the folder tree from Part 6. Empty folders get a `.gitkeep`.
5. Write `.gitignore` covering `.copilottracking/`, `.ei-session-logs/`, `testResults.xml`,
   `coverage.xml`, `.vscode/`, `azdo-settings.json`.
6. Copy `latest-plan.md` to `docs/architecture-v3.md`.
7. Copy this plan to the repo root as `plan.md`.
8. Create `BUILD-PROGRESS.md` with a `TODO` row for all 23 task IDs, and create `BUILD-LOG.md`.

**Done when.** Every source path returns `True` from `Test-Path`, or the task is `BLOCKED`.
`Test-Path` returns `True` for each of `docs/architecture-v3.md`, `BUILD-PROGRESS.md`,
`BUILD-LOG.md`, `.gitignore` and `plan.md`. `git log --oneline` shows at least one commit.

#### T002 — The progress checker

**Do this.** Write `tools/Test-BuildProgress.ps1` implementing every rule in Part 4.

**Where the task list comes from.** One of the rules is "every task ID appears exactly once", so
the checker needs to know the task IDs. **Do not hardcode them.** Read `plan.md` in the repo root
and collect every heading matching `#### T0NN`. That is the list. A hardcoded list would rot the
moment a task is added or renumbered. T001 step 7 is what puts `plan.md` there.

Give the script three path parameters so its own tests can point at fixtures instead of the live
files: `-PlanPath` defaulting to `./plan.md`, `-ProgressPath` defaulting to
`./BUILD-PROGRESS.md`, and `-LogPath` defaulting to `./BUILD-LOG.md`. This is the same seam as
`-RegistryPath` in T010 and `-ChangedFiles` in T011. T020's parameter check does not apply here,
because this script lives in `tools/`, not under `plugins/`.

Write `tests/tools/Test-BuildProgress.Tests.ps1` covering:

- a valid file passes
- two `IN-PROGRESS` rows fail
- a `DONE` row with an empty commit fails
- a missing task ID fails
- a header that disagrees with the table fails
- `pending` in a `DONE` row gives a warning and exits 0
- the same is true when that row is in the middle of the table, not last — this is the repair
  case and it must pass
- two `pending` values anywhere is an error
- `pending` in a row that is not `DONE` is an error
- an `IN-PROGRESS` row whose `BUILD-LOG.md` block has no `**Assumptions:**` line is an error

**Done when.** `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1` exits 0.

#### T003 — The test harness

**Do this.** Copy the one file listed for T003 in Part 2, then **change it**. The old version is
not good enough for us:

- It has no `-Path` parameter. It hardcodes `$config.Run.Path = $PSScriptRoot`.
- It exits 0 when zero tests run. That turns every later check into a false pass.

Add a `[string[]] $Path` parameter so we can run a subset. Make it `exit 1` when
`$result.TotalCount -eq 0`. Keep `$config.Filter.Tag = @('Unit')`, because all the copied tests
carry that tag.

**Done when.** All three of these hold:

1. `pwsh -NoProfile -File $P` exits 0, and T002's tests ran and passed.
2. `pwsh -NoProfile -File $P -Path ./tests/tools` exits 0 and runs only that subset.
3. `pwsh -NoProfile -File $P -Path ./tests/does-not-exist` **exits 1**. This proves it fails
   closed.

---

### Phase 1 — Schemas

#### T004 — Four schemas: three written, one copied

**Write these three** under `skills/ei-graphics-core/schemas/`. Their shapes are in
`docs/architecture-v3.md`:

- `story-understanding.schema.json`
- `approved-files.schema.json`
- `session.schema.json`

All three use draft-07, set `additionalProperties: false`, and have a populated `required` list.
All artifacts we write use `"schemaVersion": "1.0.0"`.

**Four details that are easy to miss:**

- `story-understanding.schema.json` and `approved-files.schema.json` must declare `hash` as
  **required**. Its format is the literal text `sha256:` followed by 64 lowercase hex
  characters, anchored at both ends. That matches the `adoHash` and `understandingHash` fields
  beside it.
- `session.schema.json` includes a `verbosity` field. It is `"verbose"` or `"concise"`, and
  defaults to `"verbose"`.
- `session.schema.json` declares the `summary` object with its 11 fields — `completedAt`,
  `totalDurationMs`, `totalTokens`, `filesModified`, `testsRun`, `testsPassed`,
  `humanInteractions`, `outcome`, `domainSkillUsed`, `bugPatternMatched`, `commentDeviations` —
  and every one is **optional**. `-Finalize` writes them only at the end, so a check partway
  through must still pass.
- Each session entry declares these optional fields: `filesRead`, `filesModified`, `humanInput`,
  `scriptOutput`.

**The last two points are load-bearing.** With `additionalProperties: false` and those fields
undeclared, every real entry gets rejected.

**Copy `ado.schema.json`, do not write it.** Take it byte for byte from the row in Part 2. A
complete, strict draft-07 schema for exactly what `Invoke-EiAdoCliIntake.ps1` produces already
exists. It declares `schemaVersion`, `source`, `storyId`, `storyRef`, `summary`, `description`,
`workItem` with `id`/`organization`/`project`/`url`, `retrieval` with `status`/`reason`/
`authSource`, `retrievedAt`, `attachments[]`, `commentRetrieval`, and `comments[]`.

**Do not change it, do not loosen it, and do not rewrite it later in T013.** The ADO `SKILL.md`
names it as the artifact's schema.

Record its SHA-256 in `tests/data/ported-file-hashes.json`.

**Done when.** A new Pester file shows that every schema parses through
`Get-Content | Test-Json -Schema` against a good fixture and rejects a bad one. A session
fixture with no `summary` still validates. An entry carrying all four optional fields validates.
`ado.schema.json` matches its recorded hash, and rejects an object with an extra top-level
property. `$P` exits 0.

#### T005 — The domain skill registry

**Do this.** Write `references/domain-skill-registry.json`. It is an index and nothing more:
`schemaVersion`, then `domains[]` where each entry is `{ id, displayName, skillPath }`. One
entry for now: `termination-drawing`.

No detection terms. No synonyms.

Also write `schemas/domain-skill-registry.schema.json`. The schema lives in `schemas/`; the data
stays in `references/`.

**Done when.** The registry validates against its schema. A Pester test shows the registry has
no `detectionTerms` or `synonyms` keys. **Count the domains by reading the registry, never
against a hardcoded number.** `$P` exits 0.

---

### Phase 2 — The core scripts

One task per script, each with its own Pester file.

**All six scripts share a contract:**

- `#Requires -Version 7.0`
- `Set-StrictMode -Version Latest`
- `$ErrorActionPreference = 'Stop'`
- paths resolved relative to `$PSScriptRoot`
- JSON on stdout, messages on stderr
- exit 0 on success, 1 on failure
- safe to run twice
- never prompt for input

**Every stderr message follows Part 3.** It names the file, says what was wrong in plain words,
and says what to do next. A bare "validation failed", or a raw exception dump, is a defect. The
person reading it is usually not the person who wrote the script.

**Every script we write has a `-Help` switch.** It prints the synopsis and exits 0. Copied
scripts are exempt; see T020.

**Declare only the parameters the checks actually use.** No speculative extras. T020 compares
each `param()` block against the roster written in the task below, and the lists must match
exactly.

**Each roster below is complete as written.** It already includes `-Help`, and `-Json` where the
script emits structured output. Those are not implicit extras sitting outside the budget.

#### T006 — `ei-graphics-core/SKILL.md` and the plain-language checker

**Write the skill document first.** It is a usage reference for the six scripts. Keep it to 120
lines or fewer. Give it YAML frontmatter with `name` (which must equal the folder name,
`ei-graphics-core`) and `description`. For each script, give its parameters, its output shape,
and its exit codes.

No workflow narrative. The agent owns the flow.

**Then build the Part 3 checker**, because this is the first file in the repo that a human
reads. Create `tests/data/jargon-terms.txt` with the 18 words from Part 3, one per line. Write
`tests/PlainLanguage.Tests.ps1` implementing the four rules.

**The checker hardcodes its target list.** Part 3 names ten files, and that list is closed —
nothing in this build adds an eleventh. Put those ten paths in the test file. Skip
`session-summary.md`, which is rendered at run time into a gitignored folder and so is never on
disk to scan; T009 covers it with golden files instead. That leaves nine paths to scan.

Some of the nine do not exist yet at T006. Scan whichever are present and ignore the rest. T021
is where the plan checks that all nine have arrived.

**Done when.** A Pester test shows `SKILL.md` exists, has valid frontmatter with `name` and
`description`, is 120 lines or fewer, and mentions all six script names.

The checker's own tests must show:

- it **fails closed** — `jargon-terms.txt` exists and yields at least 18 terms before any
  scanning happens, so an emptied file cannot turn it into a silent pass
- a planted jargon word in a covered file fails the suite
- a 30-word sentence fails
- a bare `Write-EiArtifact.ps1` outside backticks fails
- the scanner finds at least one file. An empty target list is an error, not a pass.

`$P` exits 0.

#### T007 — `Write-EiArtifact.ps1`

**Do this.** Write a JSON artifact to `.ei-session-logs/<storyId>/<name>.json`, after checking
it against the matching schema.

**Parameters, exactly these 7:** `-StoryId`, `-ArtifactType`
(`story-understanding` | `approved-files` | `ado`), `-InputObject`, `-InputJson`, `-Root`,
`-Json`, `-Help`.

**Canonical form, exactly.** UTF-8 with no byte order mark. LF line endings. Object keys sorted
ascending by ordinal. No insignificant whitespace. The `hash` property itself is left out of the
digest. Emit `sha256:` followed by 64 lowercase hex characters.

**Stamp `hash` for `story-understanding` and `approved-files` only. Never for `ado`.** The
copied `ado.schema.json` sets `additionalProperties: false` and declares no `hash` property, so
stamping one would make every `ado.json` fail. ADO content is tied down a different way: through
the `adoHash` field inside `story-understanding.json`, computed over the written `ado.json`.

Reject an invalid payload with exit 1 and a list of schema errors.

**Done when.** `$P -Path ./tests/.../Write-EiArtifact.Tests.ps1` exits 0. Tests cover: a valid
write; an invalid payload rejected; writing twice is safe; the hash is the same across two runs;
the hash is the same when the input key order changes; `-ArtifactType ado` writes an `ado.json`
that validates against the copied schema; and the written `ado.json` carries no `hash` property.

For the `ado` test, hand-write a small schema-shaped payload here. `Convert-EiAdoIntake.ps1` does
not exist yet — it arrives in T012, and T012 is where the end-to-end test lives that pipes real
intake output through both scripts.

#### T008 — `Write-EiSessionEntry.ps1`

**Do this.** Append one entry to `.ei-session-logs/<storyId>/session.json`. On the first call,
create the envelope: `schemaVersion`, `storyId`, `startedAt`, `agent`, `verbosity`, `entries[]`.

Appending must be atomic. Write a temporary file, then move it.

**Parameters, exactly these 23, in two mutually exclusive sets.**

- Shared by both (4): `-StoryId`, `-Root`, `-Json`, `-Help`
- Append set (11): `-Phase`, `-Action`, `-Reasoning`, `-Outcome`, `-DurationMs`, `-TokensUsed`,
  `-FilesRead`, `-FilesModified`, `-HumanInput`, `-ScriptOutput`, `-Evidence`
- Finalize set (8): `-Finalize`, `-TestsRun`, `-TestsPassed`, `-HumanInteractions`,
  `-SessionOutcome`, `-DomainSkillUsed`, `-BugPatternMatched`, `-CommentDeviations`

`-Evidence` arrived in T024. Read that task before changing it.

**`-SessionOutcome` is deliberately not called `-Outcome`.** In JSON, the entry field and the
summary field are both named `outcome`. One PowerShell parameter cannot carry two meanings.

Use `[CmdletBinding(DefaultParameterSetName='Append')]` with the two sets.

`-Finalize` **computes** `completedAt`, `totalDurationMs`, `totalTokens` and `filesModified`
from `entries[]`. The other seven are supplied by the agent because they cannot be derived.

**Done when.** Tests show: the first call creates the envelope; three appends give three entries
in order; a rapid second append does not truncate the file; an invalid `-Phase` is rejected;
`-Finalize` writes all 10 summary fields and the result validates against `session.schema.json`;
and passing both an append parameter and `-Finalize` is a parameter-set error, not a silent
partial write. `$P` exits 0.

#### T009 — `Export-EiSessionSummary.ps1`

**Do this.** Render `session-summary.md` from `session.json`.

**Parameters, exactly these 4:** `-StoryId`, `-Root`, `-Json`, `-Help`.

Input is always `<Root>/.ei-session-logs/<StoryId>/session.json`. Output always sits beside it.
There is no `-InputPath` and `-OutputPath` pair, because `-Root` already redirects both, and the
golden-file tests point at a fixture root.

**Verbosity is read from `session.json`. There is no `-Verbosity` parameter.**

Sections, in this order: header, Timeline table, Agent Reasoning Trail, then "For the
maintainer" (skill coverage, improvement opportunity, human wait time, agent efficiency). The
template is in `docs/architecture-v3.md`.

**The header shows Duration and Tokens only. No Cost.** See Part 10.

At `concise` verbosity, drop the Reasoning Trail and shorten the Timeline. **"For the
maintainer" always renders**, at both settings.

**This whole file obeys Part 3.** It is the one artifact whose entire purpose is being read by a
person. Write it the way you would explain the session out loud. Short sentences, ordinary
words, no bare field names. The maintainer section says what to change and why, not just what
happened.

**Commit the `session.json` fixture and the hand-written golden files before you write the
renderer.**

**Done when.** Tests show: the output matches the golden file; a `concise` fixture matches its
own golden and still contains "For the maintainer"; a session with no entries produces a valid
stub instead of crashing; no test asserts a Cost value; and the rendered output passes the four
Part 3 rules.

Reuse `tests/data/jargon-terms.txt` from T006 rather than restating the word list. The golden
files live under `tests/`, which the T006 scanner skips, so this artifact has to check itself.
`$P` exits 0.

#### T010 — `Get-EiDomainSkillCatalog.ps1`

**Do this.** Read the registry. Open each `SKILL.md`. Parse the frontmatter `description` and
the `## When to Use` bullet list. Emit
`{ skills: [{domainId, displayName, skillPath, description, whenToUse[]}] }`.

Never read the full skill body.

**Parameters, exactly these 3:** `-RegistryPath` (defaults to the real
`references/domain-skill-registry.json`, and the failure tests override it), `-Json`, `-Help`.

No `-Root` and no `-DomainId` filter. Nothing in the checks uses either.

**Done when.** Tests show: the catalogue for the real registry returns **the number of entries
the registry declares** — read it, do not hardcode a count — each with a non-empty `whenToUse`;
a `-RegistryPath` pointing at a registry whose `skillPath` is missing exits 1 with a clear
message; malformed frontmatter exits 1. `$P` exits 0.

#### T011 — `Test-EiScopeDrift.ps1`

**Do this.** Read `approved-files.json`. Get the files that actually changed, using
`git diff --name-only` plus untracked files. Report
`{ status: 'pass'|'drift', unapproved[], approvedUnchanged[] }`. Exit 0 on pass, 1 on drift.

**Parameters, exactly these 5:** `-StoryId`, `-Root`, `-ChangedFiles`, `-Json`, `-Help`.

`-ChangedFiles` is the seam that makes this testable. When you supply it, the script does not
shell out to git. When you leave it out, it does. `-StoryId` and `-Root` find
`approved-files.json` the same way T007 wrote it.

There is no seal, and no scope-change-request artifact.

**Write the three test cases first, and watch them fail before you implement.**

**Done when.** Tests show: an exact match passes; an extra file shows up as drift and is listed;
an approved file that was never touched is reported as a warning, not a failure.

Watch out for the old repo's trap: **never** run
`pwsh -File script.ps1 -ChangedFiles $array`. `-File` flattens the array and the check silently
passes. Call it in-process: `& ./script.ps1 -ChangedFiles $paths`. `$P` exits 0.

#### T012 — `Convert-EiAdoIntake.ps1`

**Why this script exists.** `Invoke-EiAdoCliIntake.ps1` fetches a work item and prints one shape
of JSON. `ado.schema.json` demands a different shape and rejects anything extra. In the old
repo, a script called `Invoke-EiAdoIntakeStage.ps1` sat between them and translated. We are not
copying that script, because it drags in the whole lifecycle skill. So we rebuild the
translation, and only the translation.

**Do this.** Read the intake output. Emit an object that matches `ado.schema.json`.

**Parameters, exactly these 7:** `-IntakeJson`, `-StoryId`, `-Summary`, `-Root`,
`-SkipAttachmentDownload`, `-Json`, `-Help`.

**The field mapping, in full.** Left is what the intake script gives you. Right is what the
schema wants.

| Schema field | Where it comes from |
|---|---|
| `schemaVersion` | the literal `"1.0.0"` |
| `source` | the literal `"ei-azure-devops-cli-intake"` |
| `storyId` | the `-StoryId` parameter |
| `storyRef` | `workItemContext.workItemUrl`, or `null` if blank |
| `summary` | the `-Summary` parameter, or `null` if not given |
| `description` | `descriptionText` |
| `workItem.id` | `workItemContext.workItemId`, as a string |
| `workItem.organization` | `workItemContext.organization` |
| `workItem.project` | `workItemContext.project` |
| `workItem.url` | `workItemContext.workItemUrl`, or `null` if blank |
| `retrieval.status` | the top-level `status` |
| `retrieval.reason` | the top-level `reason` |
| `retrieval.authSource` | `workItemContext.authSource` |
| `retrievedAt` | the current time, as `yyyy-MM-ddTHH:mm:ssZ` in UTC |
| `attachments` | downloaded from `attachmentUrls`; see below |
| `commentRetrieval` | copied straight across |
| `comments` | copied across, with `createdDate` reformatted; see below |

**Do not dot-source the old helpers. Write both timestamp helpers inline, both using
`InvariantCulture`.**

`Get-EiUtcTimestamp` lives in `EiWorkflowState.ps1`, which we are dropping. Its one-line body is
`(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')`. **Do not copy that line as it
stands.** In a .NET custom format string, `:` is the *time separator*, and which character it
renders as depends on the current culture. On a machine whose culture uses `.`, this produces
`14.22.10` and fails T012's own `retrievedAt` assertion. Add the culture argument:

`(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)`

The original has this bug. We are not copying it forward.

`ConvertTo-EiIsoTimestamp` does exist in the copied `EiAdoTimestamp.ps1`, but it belongs to a
different skill. Do not reach across skill folders. Rewrite it inline, with the same
`InvariantCulture` argument and **all four of its branches**: null in, null out; a `DateTime`;
a `DateTimeOffset`; and a string passed through unchanged. The `DateTimeOffset` branch is not
optional — `ConvertFrom-Json` decides which type you get, and it can hand you either.

**Refuse anything that is not a clean retrieval.** If the top-level `status` is not
`"retrieved"`, exit 1 and say which work item failed and why. The schema pins
`retrieval.status` to the single value `"retrieved"`, so a failed fetch must never become an
artifact. Do the same if `descriptionText` is empty, because the schema requires at least one
character.

**Check `workItemId` here too.** The schema constrains `workItem.id` to a positive integer with
no leading zero — the pattern `^[1-9][0-9]*`, anchored at both ends. If it is missing, empty or
not a positive integer, exit 1 with a message that names the field and the value you got. Left
to the schema, this surfaces later as a raw validation error out of `Write-EiArtifact.ps1` —
exactly the "validation failed" experience Part 3 exists to prevent.

The schema also constrains `retrieval.authSource` and `storyId`. Those come from our own
parameters or from a field the intake script always populates, so a plain schema error is an
acceptable outcome for them. `workItemId` is the one that realistically arrives malformed.

**Downloading attachments.** For each entry in `attachmentUrls`:

1. Create `<Root>/.ei-session-logs/<StoryId>/attachments/` if it does not exist.
2. Get a token once, with
   `az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798`, and read
   `accessToken` from its JSON.
3. Work out the file name from the `fileName` query parameter in the URL. If there is none, use
   `image-<n>.png`. Prefix it with the 1-based index so two attachments cannot collide.
4. Download with `Invoke-WebRequest`, passing `Authorization: Bearer <token>`.
5. Only if the download succeeded, add `{ url, localPath, fileName, source }` to `attachments`.
   `source` is the `source` value on that same `attachmentUrls` entry, or the literal `unknown`
   if the entry has none. The schema allows `source` but does not require it.

A failed download is a **warning on stderr, not a failure**. Skip that attachment and carry on.
The same applies if no token is available. `attachments` is optional in the schema, so an empty
list or a missing key both validate.

`-SkipAttachmentDownload` skips the whole step and emits no `attachments` key. It exists so the
tests never touch the network.

**This is the one core script that writes files on its own.** Phase 2's contract says a script
puts its artifact on stdout and its messages on stderr, and this one still does. The downloaded
images are a deliberate exception: they land on disk under
`.ei-session-logs/<StoryId>/attachments/`, and the artifact records where. Nothing else in the
script touches the filesystem, and `-SkipAttachmentDownload` turns even this off.

**Done when.** Tests show, using `tests/fixtures/ado-intake-stdout.json` — a hand-written file
holding one realistic intake payload:

- with `-SkipAttachmentDownload`, the output validates against `ado.schema.json`
- every field in the table above lands in the right place, checked one by one
- a payload whose `status` is `"failed"` exits 1 and names the work item
- a payload with an empty `descriptionText` exits 1
- `retrievedAt` matches `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`
- a comment whose `createdDate` arrives as a `DateTime` is written back as that same ISO shape
- piping the output into `Write-EiArtifact.ps1 -ArtifactType ado` produces a valid `ado.json`
  with no `hash` property

The download path itself is **not** covered by a test. It needs a real token and a real network,
so it gets exercised in the live run at T022. Do not fake it with a mocked web request, and do
not claim it is covered.

`$P` exits 0.

---

### Phase 3 — The copied skills

#### T013 — Copy `ei-azure-devops-cli-intake`

**Do this.** Copy the 5 files and 2 fixtures listed for T013 in Part 2. There is no strip step.

`Invoke-EiAdoCliIntake.ps1` dot-sources only `helpers/EiWorkItemReference.ps1` and
`helpers/EiAdoTimestamp.ps1`. It has no workflow or lifecycle references and already works on
its own. It writes JSON to **stdout** and exits 0. It produces no file.

The flow is: the agent runs the intake script, pipes its stdout into `Convert-EiAdoIntake.ps1`
from T012, and pipes that into `Write-EiArtifact.ps1 -ArtifactType ado`.

Add fixture-driven test cases using `-CliWorkItemJson` with the two copied fixtures.

**`ado.schema.json` was already copied in T004. Do not touch it here.**

**Two edits you must make:**

1. In the copied test file, change `aveva-ei-graphics` to `demo-ei-graphics` on the line that
   builds `$script:ScriptPath`.
2. Rewrite `SKILL.md`. It is a lifecycle-era document, with 12 banned-term hits in a "Lifecycle
   stage" section. Keep its script usage content. Drop every stage and workflow reference. It
   also gains a line about `Convert-EiAdoIntake.ps1`.

**Record the SHA-256 of the three non-test scripts only:** `Invoke-EiAdoCliIntake.ps1`,
`EiWorkItemReference.ps1`, `EiAdoTimestamp.ps1`. Put them in
`tests/data/ported-file-hashes.json`.

**Do not hash `SKILL.md`, the test file, or the two JSON fixtures.** We edit the first two in
this very task, so a recorded hash would break T020 the moment the edit lands.

**Those three scripts are copied byte for byte and must not be edited.**

**Done when.** The copied Pester file passes and `$P` exits 0.

A grep for `workflow-state`, `lifecycle` or `EIWF-` returns zero hits **across those three
scripts**. If it does not, stop and ask. Do not edit a copied script to satisfy it.

`SKILL.md` is checked instead by T019's term scan, which it must pass after the rewrite.

A test shows the full chain — intake stdout, then `Convert-EiAdoIntake.ps1`, then
`Write-EiArtifact.ps1` — produces a schema-valid `ado.json`. The three recorded hashes match.

#### T014 — Copy `ei-layer-guard`

**Do this.** Copy the 3 files listed for T014 in Part 2.

`SKILL.md` and `Invoke-EiLayerGuard.ps1` are copied **without a single change**. `SKILL.md` has
been checked and contains zero banned identifiers, so it needs no rewrite. It is already a clean
pass/fail gate.

**The test file needs one edit.** Change `aveva-ei-graphics` to `demo-ei-graphics` on line 7,
where it builds `$script:ScriptPath`. Without this it points at a folder that does not exist.

Check that the guard still returns `pass`, `blocked` or `needs-manual-review`, and still honours
`-Json`.

**Record the SHA-256 of the two unedited files only:** `SKILL.md` and `Invoke-EiLayerGuard.ps1`.

**Do not hash the test file.** You just edited it. Recording a hash for a file you edit is how
T020 breaks.

**Done when.** The copied Pester file passes and `$P` exits 0. Both recorded hashes match.

#### T015 — Copy and split `termination-drawing`

**Do this.** Copy the old `SKILL.md` to two places: its destination in the plugin, and
`tests/fixtures/termination-drawing-v2-SKILL.md`, which is the before picture the test compares
against.

Then split it into six files. **No content may be lost.** Nothing is deleted, only moved.

**The split, heading by heading.** The old file has 55 headings. After the split there are 56,
because `SKILL.md` gains a `## References` section. Every heading lands in exactly one file.

`SKILL.md` keeps 17 headings:

`# Termination Drawing Skill` · `## When to Use` · `## Goal` · `## Inputs` ·
`## Output Contract` · `## Invocation Workflow` and its five `### Step N` headings ·
`## Testing` with `### Running Tests`, `### Test Structure` and
`### Key Test Scenarios for LOC Update` · `## Critical Rules (Do NOT Violate)` ·
`## References` (new)

`references/architecture.md` takes 8:

`## Architecture Overview` · `### Pipeline` · `### Key Files` · `## Core Concepts` ·
`### LOC (Level of Connectivity)` · `### Connectivity Sides` · `### BackLayerShape` ·
`## Codebase Location`

`references/composite-key-system.md` takes 7:

`## Shape Metadata & Composite Key System` · `### Purpose` · `### Metadata Values ...` ·
`### Composite Key in insertedTags` · `### UpdateDrawing Logic` ·
`### IsShapeFoundOnDrawing (Equipment/Terminal)` ·
`### Wire/Link/LoopWire Terminal Validation`

`references/update-flow.md` takes 12:

`## Drawing Update Flow (isUpdate = true)` · `### Key Rules` ·
`## Model Builder Key Concepts` · `### Grouping` · `### Connected Equipment Placement` ·
`### Wire Direction` · `### Deduplication` ·
`## Drawing Update Trigger (IsDrawingUpdateRequired)` · `### LOC Change Detection` ·
`## MetaDataHelper API Rules` · `## Core Connector Update (existsInBoth)` ·
`### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)`

**That last one is easy to miss.** It is the only child of
`## Core Connector Update (existsInBoth)`, it sits at the very end of the section, and an earlier
draft of this plan lost it. Move the parent and the child together.

`references/log-analysis.md` takes 4:

`## Diagnostic Logging` · `### Enable` · `### Key Log Patterns` ·
`### Log Analysis Commands (PowerShell)`

`references/bug-patterns.md` takes 8:

`## Common Bug Patterns & Fixes` and its seven numbered `### N.` headings

17 + 8 + 7 + 12 + 4 + 8 = 56. Use that to check your own work while splitting. It is not what the
test asserts — see "Done when" below for why.

Sixteen of `SKILL.md`'s 17 come from the fixture; `## References` is new. So the fixture side is
16 + 8 + 7 + 12 + 4 + 8 = 55, which is what the no-content-lost check compares against.

**Four things earlier drafts of this plan got wrong. Do not repeat them.**

- The `### Key Files` table has **14 rows**, not 9. All 14 move to `architecture.md`. Nothing is
  trimmed. An earlier draft said "keep the top 9", which contradicted "no content may be lost".
- There is no section called "Gotchas". The section is `## Common Bug Patterns & Fixes` and it
  has **7** patterns, not 6.
- `## Critical Rules (Do NOT Violate)` has **10** numbered rules. They all stay in `SKILL.md`.
- The file has **55** headings, not 54. An earlier draft dropped
  `### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)` and gave `update-flow.md`
  11 instead of 12. Count the file yourself before you trust any number in this task.

**The heading test must strip fenced code blocks first.** The old file contains PowerShell and
C# comments starting with `#` inside triple-backtick blocks. Lines like
`# Model + insertion summary` and `# Key shape actions` are code comments, not headings. Strip
everything between fence markers before you extract headings, in **both** the fixture and the
destination files. Without this the test finds ghost headings and fails for no reason.

**Keeping `SKILL.md` small.** Move the long PowerShell block under `### Step 2 — Analyse the
Log` into `log-analysis.md` and leave a one-line pointer. The `### Step 2` heading itself stays
in `SKILL.md`.

The `## References` section must say **when** to load each file, not just list them.

There is no `evals/` folder.

**Done when.** A Pester test shows:

- `SKILL.md` is under 180 lines and under 5000 tokens, estimated as characters divided by 4
- all five reference files exist and are not empty
- every `references/*.md` is linked from `SKILL.md`
- after stripping code fences, **every heading in the committed fixture appears in exactly one
  destination**, either `SKILL.md` or one reference file, never both
- zero missing headings and zero duplicates, reported as separate counts

**The test checks one direction only: nothing lost, nothing duplicated.** It must **not** demand
that the two sets match exactly, and it must not assert a total heading count. Headings may be
added later. T015 itself adds `## References`, and T023 may add more after the live run. A test
that froze the heading set, or froze the number 56, would turn any future improvement to this
skill into a build failure.

The 56 in the split table is a sanity figure for whoever does T015. It is not a rule for all
time, so it does not go in the test.

This is the no-content-lost check. It compares against the fixture, not against memory. `$P`
exits 0.

---

### Phase 4 — The agent and the packaging

#### T016 — `agents/ei-graphics.agent.md`

**Do this.** Write about 60 lines. Include exactly the rules listed under "Lean agent.md" in
`docs/architecture-v3.md`:

never re-fetch from ADO · **stop if the ADO intake fails** · no step narration · direct output
style · never invent a domain ID · comments override the description · log every step to the
session · run the layer guard before committing · branch on small versus large complexity ·
skill-first file resolution, the four-point block · make surgical changes only · verify before
saying you are done · surface test gaps · never edit before you understand the cause · stop when
done · the no-domain-skill fallback, word for word · set up `.gitignore` on first run

**Spell out the stop rule.** If `Convert-EiAdoIntake.ps1` or
`Write-EiArtifact.ps1 -ArtifactType ado` exits non-zero, report the failure and stop. Never
carry on to story understanding without an `ado.json`.

Cut everything listed under "What's cut".

**Turn "direct output style" into the Part 3 rules, written as instructions to the agent.**
Short sentences. Ordinary words, no jargon. Name the file and the next action when reporting a
problem. Explain a decision before showing the diff. Never answer with a bare identifier or a
raw error dump. The person reading is often not the person who wrote the code.

**Two things do not go in this file.** The `aveva-rnd` delegation table and the Checkpoint 2
template would blow the line budget. Write them into
`skills/ei-graphics-core/references/rnd-delegation.md` and `.../references/checkpoint-templates.md`,
and put one pointer line to each in the agent file.

**Done when.** A Pester test shows the agent file is under 80 lines, has valid frontmatter, and
contains the literal strings `skill-first`, `Stop when done`, `.ei-session-logs/`, a pointer to
each reference file, and a plain-language block naming both "short sentences" and "next action".

It contains none of `lifecycle`, `EIWF-`, `Format-EiWorkflowSummary`, `ei-graphics-workflow`.

The test also checks the two reference files: `rnd-delegation.md` names all 11 `aveva-rnd`
skills, and `checkpoint-templates.md` contains the four Checkpoint 2 headings — "Files I'll
change", "Tests I'll verify", "New tests needed?", "Risks".

All three files are on Part 3's covered list, so the T006 checker already scans them. `$P`
exits 0.

#### T017 — The manifests

**Do this.** Write three files:

- `.claude-plugin/marketplace.json` at the **repo root**
- `.github/plugin/marketplace.json` at the **repo root**
- `plugins/demo-ei-graphics/.github/plugin/plugin.json` inside the plugin

**The three name fields must agree:**

- `plugin.json` gets `"name": "demo-ei-graphics"`
- `.claude-plugin/marketplace.json` gets `plugins[0].name` of `demo-ei-graphics` and
  `plugins[0].source` of `./plugins/demo-ei-graphics`
- the marketplace file's own top-level `name` is the catalogue entry, and is
  `demo-ei-graphics-plugin`

**The old repo uses the old name in all of these. Do not copy those values across.**
Descriptions describe v3 only.

**The two marketplace files use different bases.** This is the detail that catches people:

- In `.claude-plugin/marketplace.json`, `source` resolves from the **repo root**.
- In `.github/plugin/marketplace.json`, `pluginRoot` resolves from the repo root, but `source`
  resolves from **`pluginRoot`**. So its `source` is the bare name `demo-ei-graphics`, with no
  `./plugins/` prefix.

**`plugin.json` keeps the folder-pointer form:** `"skills": "skills/"`, `"agents": "agents/"`.
Manifests must never list individual skill names, or adding a skill becomes a manifest edit.

**Done when.** A Pester test shows:

- all three files parse as JSON
- `.claude-plugin/marketplace.json`'s `source` resolves from the repo root and the folder exists
- `.github/plugin/marketplace.json`'s `pluginRoot` resolves from the repo root, and its `source`
  resolves **from `pluginRoot`**, and that folder exists
- `plugin.json`'s `skills` and `agents` resolve from the plugin folder, and both exist and are
  not empty
- neither marketplace file has a `skillPath` key — do not assert one
- `plugin.json`'s `name` equals the name of the **plugin folder** — the folder that directly
  contains `.github/`, which is `plugins/demo-ei-graphics`. Get it by walking up from
  `plugin.json`: its own folder is `plugin`, then `.github`, then the plugin folder. Take the leaf
  name of that third folder. It must also equal `plugins[0].name` in
  `.claude-plugin/marketplace.json`.

**Read both names from the filesystem. Do not hardcode the string**, or the check cannot catch a
half-finished rename.

- the description strings contain none of `ITERATE routing`, `scope control`, or
  `gated delivery lifecycle`. All three old files contain these, so scan all three.

Stray old-name strings anywhere else in the repo get caught by T019. No need to repeat that scan
here. `$P` exits 0.

#### T018 — The documents

**Do this.** Write five files:

- root `README.md` — what this is, the prerequisites checklist from `docs/architecture-v3.md`,
  how to run it, how to read a session summary, and the manual skill-improvement loop
- `plugins/demo-ei-graphics/README.md` — the skills table, the folder tree, the artifacts table
- root `PLUGIN-INFO.md`
- `plugins/demo-ei-graphics/INSTRUCTIONS.md`
- `.github/copilot-instructions.md` — the per-task loop from Part 5, the machines-decide rule,
  the PowerShell conventions, and the OneDrive and git traps

The first four describe v3 only, and are written for someone who has never seen this repo. Part
3 applies and the T006 scanner enforces it.

**Done when.** A Pester test shows all five documents exist and are not empty, and that
`copilot-instructions.md` contains the literal strings `Test-BuildProgress.ps1`, `gc.auto=0` and
`Set-StrictMode`.

**T018 does not run its own banned-name scan.** T019 scans the whole repo, documents included,
and its term file does not exist yet at this point. Checking against it here would block the
task for no reason. Stale names get caught one task later. `$P` exits 0.

---

### Phase 5 — The guards, and a green build

#### T019 — The no-orphan check

**Do this.** Write `tests/NoOrphanReferences.Tests.ps1`.

**The banned terms live in `tests/data/forbidden-identifiers.txt`, one per line, not in the test
body.** Otherwise the test matches itself.

Seed it with these 23:

`New-EiWorkflowResult` · `New-EiScopeCandidate` · `vocabulary-map` · `domain-pack-policy` ·
`lifecycle-iterate` · `lifecycle-implement` · `Invoke-EiVocabularyNavigator` ·
`Invoke-EiBugReproducer` · `ei-scope-resolver` · `ei-scope-validator` · `ei-workflow-state` ·
`ei-test-scaffolder` · `ei-graphics-workflow` · `Validate-EiWorkflowPrerequisites` ·
`Format-EiWorkflowSummary` · `workflow-state.json` · `EIWF-` · `ei-vocabulary-navigator` ·
`ei-bug-reproducer` · `Test-EiGraphicsSpecSync` · `Invoke-EiAdoIntakeStage` ·
`EiTestPreflight` · `aveva-ei-graphics`

Two notes on that list. `ei-vocabulary-navigator` and `ei-bug-reproducer` were previously banned
only by script name, so prose like "the old ei-vocabulary-navigator did this" slipped through.
And `aveva-ei-graphics` is the old plugin name, which must not survive anywhere in the built
repo.

**Skip these locations**, and this is the only place the list is written:

`docs/**` · `BUILD-LOG.md` · `BUILD-PROGRESS.md` · `plan.md` ·
`tests/data/forbidden-identifiers.txt` · `tests/fixtures/**` · `.git/**`

**`docs/**` is load-bearing. Do not remove it.** `docs/architecture-v3.md` is a word-for-word
archive containing 24 lines that match banned names, and we never edit it.

**`plan.md` and `BUILD-LOG.md` matter for the rename in particular.** Both legitimately name the
old folder as a copy source.

**Done when.** `$P` exits 0, plus four self-checks:

1. **It fails closed.** The term file exists, parses, is not empty, and yields at least 23 terms
   before any scanning. A missing or emptied file must not turn the guard into a silent pass.
2. A planted term in a scanned location makes the suite fail.
3. Every entry in Part 2's "what we are deliberately not copying" list appears in the term file.
   Skills by folder name, scripts by file name without the `.ps1`. Check the whole list, not
   just the skill folders.
4. For every `skills/*/SKILL.md`, frontmatter exists and its `name` equals the folder name.

#### T020 — The script contract check

**Scope: every `.ps1` under `plugins/`.** `tests/` and `tools/` are out of scope.

**Two sets**, because copied files must not be edited to satisfy a contract written for ours.

**Our set — the six core scripts.** Each must have `#Requires -Version 7.0`,
`Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, a `[switch] $Help` that
prints the synopsis and exits 0, no `Read-Host` or `Pause`, and a line ceiling.

**The ceilings live in the test file, as one hashtable at the top of
`tests/ScriptContract.Tests.ps1`:**

| Script | Ceiling |
|---|---|
| `Write-EiArtifact` | 120 |
| `Write-EiSessionEntry` | 200 |
| `Export-EiSessionSummary` | 180 |
| `Get-EiDomainSkillCatalog` | 120 |
| `Test-EiScopeDrift` | 100 |
| `Convert-EiAdoIntake` | 160 |

**A ceiling may be raised once.** If a script cannot meet its ceiling without becoming unclear,
change that one entry **in the test file, not in `plan.md`**. The plan is not edited mid-build.
Record the script, the old value, the new value and the reason in the current task's
`BUILD-LOG.md` block. Ceilings may be raised, never removed, and never raised twice for the same
script.

**Parameter check.** The script's `param()` block must contain **exactly** the parameter names
listed in its task above, no extras and none missing. Every roster in Part 7 uses the same
"Parameters, exactly these N" wording so the check can find it, and every roster already
includes `-Help` and `-Json` where they apply.

This is a set comparison against a written list, not static analysis of test bodies.

**Anchor the parse on the `#### T0NN` heading, not on the marker text.** Two rosters say
"exactly these 7" — T007 and T012 — so neither the marker nor the count identifies a task on its
own. Walk the plan section by section: find the task heading, then find the roster inside that
section. This is the same read that T002 does.

**The roster is not always on one line.** T008's 21 names sit in three bullets below its marker,
not beside it. Read to the end of the roster block, not to the end of the marker line.

Getting this parse wrong is the worst failure in the build, because it produces a green suite
that checked nothing. Give the parser its own test: assert it recovers the exact expected name
set for T008 and for T012, and that it fails loudly rather than returning an empty set when a
roster cannot be found.

**T008 is the split one.** Its 21 names span two parameter sets. Compare against their union,
not against either set alone.

**The copied set — hardcode this list:** `Invoke-EiAdoCliIntake.ps1`, `EiWorkItemReference.ps1`,
`EiAdoTimestamp.ps1`, `Invoke-EiLayerGuard.ps1`.

They get a reduced contract only: `Set-StrictMode` is present, nothing prompts, and there is no
parameter budget. **None of them has `#Requires` or `-Help`. That is expected and must not be
"fixed".**

Note that `tests/Invoke-PesterTests.ps1` is in neither set. It lives outside `plugins/`, and
T003 deliberately modifies it, so it is neither ours nor copied-intact.

**Every `.ps1` under `plugins/` must land in exactly one of the two sets.** Scan the folder,
then check the scanned list against the two sets in both directions:

- a script found on disk that is in neither set is an **error**, not a skip. Otherwise a stray
  script slips past both contracts and no one notices.
- a name listed in either set with no file on disk is also an error. That catches a rename or a
  deletion.

This is the same both-ways rule as the registry check below, for the same reason.

**Done when.** `$P` exits 0, and the test also shows:

- Every file in `tests/data/ported-file-hashes.json` still matches its recorded SHA-256.

  **That file holds exactly 6 entries:** the 3 ADO non-test scripts from T013, the 2 layer-guard
  files from T014, and `ado.schema.json` from T004. Nothing else.

  **Deliberately absent, because we edit them:** `ei-azure-devops-cli-intake/SKILL.md`, both
  copied `.Tests.ps1` files, and the two JSON fixtures. A hash recorded for a file we then edit
  would fail this very check.

  **Assert the count and the file list together.** A bare count that disagrees with its own
  contents is exactly how this check rots.
- The total `.ps1` count under `plugins/` is 12 or fewer. Expected: 10.
- **The registry is complete both ways.** Every folder under `skills/` containing a `SKILL.md`
  is either listed in `domain-skill-registry.json` or in this hardcoded allowlist:
  `ei-graphics-core`, `ei-azure-devops-cli-intake`, `ei-layer-guard`. And every `skillPath` in
  the registry resolves to a file that exists.

#### T021 — Everything green, before the live run

**Do this.** Confirm that rows T001 through T020 are all `DONE` with a real SHA, that zero
`pending` markers remain, and that no row is `BLOCKED`.

T022 and T023 may still be `TODO`. They need a human and a live ADO connection, so this task
cannot require them.

**Also close the T006 gap here.** T006's plain-language checker scans whichever of its nine
target files exist at the time, because most of them do not exist yet at T006. By T021 they all
should. Assert that all nine are now present on disk, and fail if any is missing. Without this,
a file that was never written would have been silently skipped by every run of the checker.

**Done when.** `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1` exits 0, **and**
`pwsh -NoProfile -File $P` exits 0, **and** a grep for `pending` in the Commit column of
`BUILD-PROGRESS.md` returns zero hits, **and** all nine plain-language targets exist.

#### T024 — Evidence behind the reasoning

**Why this task exists.** A person read a real `session-summary.md` and could not check any of
it. The trail said a comment named a field, and named neither the comment, the file, nor the
line. Prose about evidence is not evidence. The reader had to take the agent's word for it.

**Do this.** Let an entry carry the evidence its reasoning rests on, and render it.

`session.schema.json` gains an optional `evidence` array on each entry. Every item names a
`file`. Each may also carry a `line`, a `symbol` and a `quote`, the last being the exact text
that was read. Nothing else is allowed.

`Write-EiSessionEntry.ps1` gains `-Evidence` in the append set, taking hashtables or the objects
`ConvertFrom-Json` produces. An item with no `file` is an error, not a silent drop.

`Export-EiSessionSummary.ps1` renders the evidence under the reasoning it belongs to, as a
bullet per item: the file as a link, the line as a `#L` fragment, the symbol in backticks, and
the quote in a fenced block beneath. The link is written relative to the summary file, which
sits two folders below the repository root, so it opens from the rendered page.

**The quote goes in a fenced block, and the link text in backticks.** Both are then invisible to
the Part 3 rules, which is right: quoted source is not our prose, and must not be reworded to
pass a readability check.

At `concise` verbosity the reasoning trail is dropped, and the evidence goes with it.

**Two line ceilings are raised here.** Record the old and new values in `BUILD-LOG.md`.

**Done when.** Tests show: an entry records its evidence and reads back unchanged; an item with
no `file` exits 1 with a message naming the missing key; the rendered summary links the file
with its line and shows the quote in a fenced block; an entry with no evidence renders no
evidence heading; and the rendered output still passes the four Part 3 rules. The golden files
are updated in the same commit. `$P` exits 0.

#### T025 — Comment deviations in the summary

**Why this task exists.** A comment on the work item can override the story description. The
agent confirms which comments it followed in `story-understanding.json`, but the rendered
`session-summary.md` never told the maintainer. So a reader saw what was built, but not that a
comment, and not the description, decided a part of it.

**Do this.** Carry the comment overrides into the summary, and render them for the maintainer.

`session.schema.json` gains an optional `commentDeviations` array on the `summary` object. Every
item names a `commentId` and the `effect` it had, both required, nothing else allowed.

`Write-EiSessionEntry.ps1` gains `-CommentDeviations` in the finalize set, taking hashtables or
the objects `ConvertFrom-Json` produces. An item missing either field is an error, not a silent
drop.

`Export-EiSessionSummary.ps1` adds one line to the "For the maintainer" section: **Comment
corrections**. It lists each override as `comment <id>: <effect>`, or says `None recorded.` when
there were none. The line renders at both verbosity settings, because the maintainer section
always does.

**Two line ceilings are raised here.** `Write-EiSessionEntry` and `Export-EiSessionSummary` both
gained a small normaliser and renderer. Record the old and new values in `BUILD-LOG.md`.

**Done when.** Tests show: the summary records its comment overrides and reads back unchanged; an
item with no `effect` exits 1 with a message naming the missing key; the rendered summary lists
each override under "Comment corrections"; a summary with none says so plainly; and the rendered
output still passes the four Part 3 rules. The golden files are updated in the same commit. `$P`
exits 0.

---

### Phase 6 — The live run, with a human watching

#### T022 — Dry run against story 4965976

**Do this.** Run the agent end to end against the real story, with `az` logged in and the target
repo cloned. Do not merge anything. Stop before creating a PR.

Record the run in `BUILD-LOG.md`.

**Done when.** A human confirms all of this:

- fewer than 10 terminal commands were used
- `ado.json`, `story-understanding.json`, `approved-files.json`, `session.json` and
  `session-summary.md` all appear under `.ei-session-logs/4965976/`
- both human checkpoints actually paused for input
- **attachments were downloaded.** If the story has images, the `attachments` array is populated
  and every `localPath` points at a file that exists under
  `.ei-session-logs/4965976/attachments/`. This is the one place the download path in T012 gets
  exercised. If the story has no images, say so in the log rather than leaving it blank.
- **the readability check no test can make.** Give `session-summary.md` to someone who has never
  worked on this plugin. Ask them what the agent did, and what they should do next. If they
  cannot say, the summary has failed, green suite or not. Write down what confused them, and fix
  it in T023.

#### T023 — Read the summary, improve the skill

**Do this.** Follow the manual improvement loop. Read the maintainer section. Find coverage gaps,
meaning files the agent read that were not in Key Files. Patch
`termination-drawing/SKILL.md` or one of its reference files. Note the change in `BUILD-LOG.md`.

**You may add headings. You may not remove or duplicate them.** T015's heading test is written to
allow additions for exactly this reason. What it still forbids is losing a heading that came from
the v2 fixture, or putting the same heading in two files. If your patch needs to move a heading,
move it whole and keep it in one place.

The plain-language rules in Part 3 do not apply here. This skill is copied content and is exempt.

**Done when.** `$P` exits 0 after the edit, and `BUILD-LOG.md` has a T023 block listing the gaps
found, or an explicit "none found".

---

## Part 8 — When things go wrong

| What happened | What to do |
|---|---|
| A check failed three times | Set the row to `BLOCKED`, write the full diagnosis in `BUILD-LOG.md`, commit, stop and ask the human. Do not move on. |
| The session died mid-task | The next session follows Part 5. The step 1 commit identifies the interrupted task. |
| A `DONE` row shows `pending` | Find the SHA with `git log -1 --format=%h --grep="^build(T0NN):"`. Do not redo the task. |
| A `DONE` task started failing again | Set that row back to `IN-PROGRESS`, fix it, re-check, restore it to `DONE`. Log it as a regression. The repaired row will briefly carry `pending` in the middle of the table. That is legal. Part 4 counts `pending`, it does not care where. |
| `BUILD-PROGRESS.md` is malformed | Fix it to satisfy Part 4 **first**. `Test-BuildProgress.ps1` decides, not judgement. |
| A task turns out to be wrong or unneeded | Do not quietly drop it. Add a `BUILD-LOG.md` entry, set the status to `DONE` with the note `superseded — see log`, and record why. |
| `git rm -r` asks you to retry the deletion | This is OneDrive. Answer `n`, then use `Remove-Item -Recurse -Force`. Commit with `git -c gc.auto=0 commit`. |
| A task can be read two ways | Rule 9. Do not pick one. Log the options and your recommendation, set `BLOCKED`, ask. |

### Four PowerShell traps from the old repo

Do not rediscover these.

- **Never** write an array-normalising helper using `ValueFromPipeline` together with
  `, @($Value)`. The pipeline re-wraps each element, and multi-element JSON arrays arrive as
  `Object[]` items whose properties read as empty. Use a plain positional parameter that returns
  `@($Value)`.
- Path-segment helpers: wrap the result in `@()` at the call site. Otherwise a single-segment
  result is a string, and `$x[0]` gives you a character.
- `Should -Throw -ExpectedMessage` matches with `-like`, so a substring needs `*wildcards*`.
- **Never** run a gate as `pwsh -File script.ps1 -ChangedPaths $array`. The `-File` switch
  flattens the argument and the gate silently passes. Call it in-process:
  `& ./script.ps1 -ChangedPaths $paths`.

---

## Part 9 — Finished when

All of the following, checked in one sitting.

1. `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1` exits 0. Nothing is `BLOCKED`.
   Everything is `DONE`.
2. `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1` exits 0.
3. `git status --porcelain` is empty.
4. `git log --oneline` shows the three-commit group per task, in order — `build(T0NN): start`,
   then `build(T0NN):`, then `chore(T0NN): record commit sha`. T001 is the exception with two.
5. `plugins/demo-ei-graphics/skills/` contains exactly four skills: `ei-graphics-core`,
   `ei-azure-devops-cli-intake`, `ei-layer-guard`, `termination-drawing`.

   This is a snapshot of the finished build, not a permanent cap. Adding domain skills later is
   expected.
6. The `.ps1` count under `plugins/` is 12 or fewer. Expected 10: six core, three ADO, one layer
   guard.

   Of the old repo's 36, four survive as copies and 32 are dropped. The other six are written
   fresh here.
7. `BUILD-LOG.md` has an entry for every task, T001 through T023. That includes the resolved
   `$V2` path from T001 and the live-run notes from T022.
8. Every human-facing file passes the Part 3 checker, and the T022 reader test was actually run
   on a person who does not know this plugin. Their reaction is written down in `BUILD-LOG.md`,
   whether it went well or not.

---

## Part 10 — Decisions

These are binding. Where `docs/architecture-v3.md` disagrees with anything here, **this section
wins.** The archive states outdated positions on cost, on the `ado.json` writer, and on "no other
skills needed".

**Refer to these by name, not by number.** Numbers shift when a decision is added.

**Core scripts live in a skill.** They go in `skills/ei-graphics-core/`. This departs from the
archive's "No other skills needed". Two reasons. The archive already accepts a `SKILL.md` that
is purely a usage reference for scripts, so we are adding one more slot, not a new pattern. And
it gives us the `references/` folder that the agent file's line budget needs.

**Cost is dropped from the session summary.** The archive shows `**Cost:** ~$0.08` in the
header. But `summary` carries `totalTokens` with no cost field and no rate, and the sample entry
has `"tokensUsed": null`. The renderer cannot work out a price and must not invent one. No
`costUsd` field is added. The header shows Duration and Tokens only.

**`ado.json` is produced by two of our scripts, and its schema is copied unchanged.** The
archive names `Invoke-EiAdoIntakeStage.ps1` as the writer, but we are not copying that script —
it exists only to drive the old lifecycle gate.

Without a replacement, nothing in v3 could write `ado.json` at all. The intake script's output
and the schema have different shapes, and the translation between them lived in that dropped
script.

So we rebuild the translation as `Convert-EiAdoIntake.ps1` (T012), and `Write-EiArtifact.ps1`
does the validating and writing. The schema itself is copied byte for byte. It is complete,
strict, and describes exactly what the copied intake script produces. **The writer changes. The
contract does not.** Do not write a replacement schema, and do not loosen it.

**Attachments are downloaded.** `Convert-EiAdoIntake.ps1` fetches the images attached to a work
item and records their local paths. The alternative was to leave `attachments` out entirely,
which the schema permits since the field is optional. We kept it, because graphics work
frequently depends on a screenshot in the story.

The cost is a network call and an `az` token inside a script that is otherwise pure data
transformation. Failures are warnings, not errors, and the download path is only exercised in
the live run at T022. Do not mock it.

**`docs/architecture-v3.md` is an archive and is never edited.** It is not in its own "Docs to
rewrite" list. Its outdated statements get corrected here, not there.

**Adding a domain skill later must stay a two-file change.** One `skills/<domain>/SKILL.md`, plus
one entry in `domain-skill-registry.json`. Nothing else may need editing.

That is why the manifests use folder pointers (T017), why no test hardcodes a skill count (T005,
T010), and why items 5 and 6 in Part 9 are scoped to the finished build. This design should hold
to roughly 20 domain skills. Past that, revisit whether a flat registry is still right.

**The registry holds no detection terms.** It is an index: id, display name, path. Matching a
story to a domain is the agent's job, using the descriptions that
`Get-EiDomainSkillCatalog.ps1` returns. Putting keyword lists in the registry would make adding
a skill a tuning exercise.

**The session log carries a `verbosity` field.** It lives in `session.json` and is read by the
renderer. It is never passed as a parameter, because the setting belongs to the session, not to
one render.

**There is no scope seal, and no scope-change-request artifact.** `Test-EiScopeDrift.ps1`
reports drift and exits non-zero. Deciding what to do about it is the human's job. The old
repo's seal-and-request machinery was part of the lifecycle gate we are removing.

**There is no `evals/` folder.** The archive mentions one. We are not building an evaluation
harness in this pass.

**`ei-layer-guard` is copied without any change to its skill or script.** It is already a clean
pass/fail gate with no lifecycle references. Only its test file is edited, and only to fix the
renamed folder in a hardcoded path.

**The `caveman` skill collection was reviewed and rejected.** Its product skills drive a
token-cost engine that is out of scope. Its six work-pattern skills would add competing
`description` lines, and caveman's own guidance warns that they "compete for activation on
ordinary work". That is exactly what the lean agent design avoids.

Four *ideas* were borrowed: the fail-closed term file, frontmatter name matching the folder
name, the two-way registry check, and a compile-time byte budget. **No code**, because that repo
is third-party licensed.

**This rejection stands, and Part 3 is not a way to smuggle it back in.** Plain-language output
is a v3 requirement in its own right, reached independently. The session summary only earns its
keep if a maintainer can read it cold. It is about writing clearly for a human, not about
adopting anyone's house voice. It changes what the agent *writes*, never how it thinks or which
skill it picks.

**Part 3 applies only to files we write ourselves.** Copied files are exempt, even after we
reorganise them in T015. Their words belong to the original author. Judging them by our rules
would mean rewriting technical prose we were told to preserve, and one of
`termination-drawing`'s critical rules already contains a word on the jargon list.

**The plugin is renamed to `demo-ei-graphics`.** The old one is `aveva-ei-graphics`. This is a
demo and testing build in a fresh repo, so the new name is the plugin's real identity, not a
label.

It is the folder name, `plugin.json`'s `name`, and `plugins[0].name` plus `source` in
`.claude-plugin/marketplace.json`. Those three must agree or the plugin will not load. That is
why T017 reads them from the filesystem rather than comparing against a hardcoded string. A
half-finished rename is the failure it guards against.

The old name survives only as a copy *source*, in the Part 2 table and in
`docs/architecture-v3.md`. T019 bans it everywhere else.

The skill `ei-graphics-core` and the sibling plugins `aveva-rnd` and `aveva-core` are not
affected.

**Watch for one failure pattern above all others.** Every guard bug found while reviewing this
plan was *a hardcoded list drifting away from the filesystem*. Any new check must either build
its list from the filesystem or assert both directions.

Worked examples: T020 scans `plugins/` and requires every script found to fall in exactly one of
its two sets, and every name in those sets to exist on disk. T005 and T010 read the registry
rather than counting skills. T002 reads the task IDs out of `plan.md`.

**T006 is the one deliberate hardcoded list**, because "is this file human-facing?" cannot be
answered from the filesystem. Its drift is caught the other way: T021 asserts every path on the
list now exists. The list is also closed — nothing in this build adds to it — and Part 3 is where
it is written down.

---

## Part 11 — Facts this plan relies on

All of these were checked by reading the files directly.

**Cite the archive by quoted text, not by line number.** `latest-plan.md` is about 836 lines and
those numbers drift.

- `tests/Invoke-PesterTests.ps1` in the old repo is 25 lines. It has
  `param([string]$CoverageOutputPath='', [string]$CoveragePath=…)`, sets
  `$config.Run.Path = $PSScriptRoot` and `$config.Filter.Tag = @('Unit')`, and ends with
  `exit $result.FailedCount`. **It has no `-Path` parameter and exits 0 when no tests run.**
  Hence the two changes in T003. It does carry `#Requires -Version 7.0` already.

- `EiTestPreflight.ps1` is 49 lines. It defines only `New-EiTestPreflightEvidence` and hardcodes
  a path into `ei-workflow-state/scripts/Write-EiWorkflowArtifact.ps1`. Its only consumer is
  `Invoke-EiAdoIntakeStage.Tests.ps1`. Both are dropped together.

- `Invoke-EiAdoIntakeStage.ps1` is 246 lines. It dot-sources `EiWorkflowState.ps1` and calls
  `Set-EiWorkflowStage.ps1`, `Write-EiWorkflowArtifact.ps1` and `Read-EiWorkflowArtifact.ps1`.
  It cannot be copied without the lifecycle skill.

  **Its one valuable part is the field mapping**, which starts at the `$artifact = [ordered]@{`
  block. T012 rebuilds that mapping and nothing else.

- `Invoke-EiAdoCliIntake.ps1` is 379 lines. It dot-sources only `EiWorkItemReference.ps1` and
  `EiAdoTimestamp.ps1`. It has zero workflow references. It writes to stdout and exits 0.

  **Its output does not match `ado.schema.json`.** It emits `status`, `reason`,
  `workItemContext`, `descriptionText`, `attachmentUrls`, `commentRetrieval` and `comments`.
  Only the last two match the schema one for one. This is exactly why T012 exists.

  On a failed fetch it emits `status = 'failed'` with `reason = 'ado-response-missing-fields'`
  and exits 1.

- **Timestamp helpers are split across two files, and only one of them is copied.**
  `ConvertTo-EiIsoTimestamp` is in `ei-azure-devops-cli-intake/scripts/helpers/EiAdoTimestamp.ps1`,
  which we copy. `Get-EiUtcTimestamp` is in `ei-workflow-state/scripts/helpers/EiWorkflowState.ps1`,
  which we drop. So T012 writes both inline rather than reaching across skills.

- **The failed-intake guarantee comes free with the schema.** `ado.schema.json` pins
  `retrieval.status` to the single-value list `["retrieved"]`, and its own description says:
  "Only a successful retrieval becomes an artifact: a failed intake blocks the stage instead of
  persisting a partial story."

  So a failed payload can never become an artifact. T012 rejects it, and even if it did not, the
  schema would. T016's stop rule tells the agent to *notice*.

- **T020's starting point:** none of `Invoke-EiAdoCliIntake.ps1`, `EiWorkItemReference.ps1`,
  `EiAdoTimestamp.ps1` or `Invoke-EiLayerGuard.ps1` has `#Requires` or a `-Help` switch. All
  have `Set-StrictMode`. None prompts. That is why the copied contract is reduced.

- The old repo has 36 `.ps1` files under `plugins/` across 10 skill folders. The new repo keeps
  4 and adds 6, so 32 are dropped.

- `ado.schema.json` sits in the old repo at
  `plugins/aveva-ei-graphics/skills/ei-workflow-state/schemas/ado.schema.json`. Read end to end:
  draft-07, `additionalProperties: false`, 9 required top-level fields, strict nested objects for
  `workItem`, `retrieval` and `commentRetrieval`, plus `attachments[]` and `comments[]`.

  It declares **no `hash` property**, which is why T007 carves `ado` out of hashing.
  `attachments` is **not** in the required list, and each attachment item allows an optional
  `source` alongside the required `url`, `localPath` and `fileName`. It contains no banned name.

- **Both copied test files hardcode the old plugin folder name.**
  `Invoke-EiLayerGuard.Tests.ps1` does it at line 7, and `Invoke-EiAdoCliIntake.Tests.ps1` does
  the same. Both need that one string changed. The five-level `..` chain above it is correct and
  must not be touched.

- **Clean, no action needed:** `ei-layer-guard/SKILL.md` and `termination-drawing/SKILL.md`
  contain zero banned names. So T014's copy-unchanged and T015's baseline fixture are both safe.

  `ei-azure-devops-cli-intake/SKILL.md` is the one exception, with 12 banned-term hits in a
  "Lifecycle stage" section. That is why T013 rewrites it.

- **`termination-drawing/SKILL.md` structure, counted directly:** 55 real headings once fenced
  code blocks are stripped. The `### Key Files` table has 14 data rows.
  `## Common Bug Patterns & Fixes` has 7 numbered patterns.
  `## Critical Rules (Do NOT Violate)` has 10 numbered rules. There is no section called
  "Gotchas".

  `## Core Connector Update (existsInBoth)` has one child heading,
  `### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)`. Two drafts of this plan
  missed it and stated 54.

  About ten `#`-prefixed lines sit inside code fences and are **not** headings, including
  `# Model + insertion summary` and `# Key shape actions`.

- **`.github/plugin/marketplace.json` in the old repo uses `"source": "aveva-ei-graphics"`, with
  no `./plugins/` prefix.** Its `source` is relative to `pluginRoot`, not to the repo root.
  `.claude-plugin/marketplace.json` uses `"./plugins/aveva-ei-graphics"`, which *is* relative to
  the root. The two files genuinely use different bases. T017's test must handle each one
  separately.

- `docs/architecture-v3.md` contains 24 lines matching a banned name. All of them are legitimate
  history. This is why the `docs/**` exclusion in T019 is load-bearing.

- `ei-graphics-core` appears **zero** times in the archive. It is this plan's invention.
