# aveva-ei-graphics

One agent and five skills for working on Electrical and Instrumentation (EI) Graphics stories.

## Quick Start

Run this before your first story:

```powershell
pwsh -NoProfile -File ./plugins/aveva-ei-graphics/skills/ei-graphics-doctor/scripts/Invoke-EiGraphicsDoctor.ps1
```

It checks:
- PowerShell 7.0+ is installed
- Azure DevOps CLI and authentication are working
- Plugin files are complete
- Skill list and schemas are valid
- Session log folder is writable
- Git is safe to use in a OneDrive folder

**Status:** `Ready` = good to go | `ManualReview` = warning, but work can continue | `Blocked` = fix required

For automated checks, add the `-Json` flag.

## Skills

| Skill | What it is for | When it is read |
|---|---|---|
| `ei-graphics-core` | Nine scripts for session files and checks | When the agent uses a session file |
| `ei-azure-devops-cli-intake` | Gets a story, images, and comments | At the start |
| `ei-graphics-doctor` | Checks that the plugin can run | Before the first story or when setup is unclear |
| `ei-layer-guard` | Checks file-layer rules | Before committing |
| `termination-drawing` | Knowledge of termination drawing code | When the story covers that area |

`termination-drawing` is the only domain skill. The registry lists domain skills only.

## Investigation order

Use this order for every bug. It makes a skipped step visible in the session summary.

1. **Intake.** Collect the work item or local report and its attachments.
2. **Write the understanding.** Record either the Azure DevOps source or the local source.
3. **Checkpoint.** Confirm the symptom and expected result with the reporter.
4. **Select the domain.** Use the domain catalogue. Do not guess a skill name.
5. **Read the domain.** Read the selected `SKILL.md` and `references/architecture.md` in full.
6. **Triage bounded history.** For a possible regression, take at most one Git history hop.
7. **Inspect key files.** Return to the files named by the architecture and read each relevant file.
8. **State a hypothesis.** Name the likely cause, a cheaper alternative, and evidence that separates them.
9. **Make the smallest edit.** Change only the code needed to address the supported cause.
10. **Run focused validation.** Run the smallest test command that covers the changed behavior.
11. **Run the layer guard.** Stop if it reports `blocked`.
12. **Close the session.** Run `Complete-EiSession.ps1`; do not finalize and render by hand.
13. **Check the summary.** Confirm its path, outcome, evidence, and test result before reporting completion.

### Worked example: a mounting-rail ordering regression

This is one example of the order. The workflow also supports other bugs and other domain skills.

1. Intake records the report. The expected order is `TS-1, B-1, --134, IOM-1`.
2. The understanding records the Azure DevOps or local source. The actual order starts with `--134`.
3. The checkpoint confirms that all items are on the correct rail, but their sequence is wrong.
4. Domain selection chooses `termination-drawing` from the catalogue.
5. The full skill and architecture read identify model ordering as the owning phase.
6. Bounded history triage compares the old and current `OrderSequence()` paths in one history hop.
7. Key-file inspection reads `OrderSequence()`, `ApplyPlateOrdering()`, and `GetDwgPlateCollectionOrder()`.
8. The hypothesis says plate ordering partitions plated and unplated items. The alternative is bad plate data.
9. The smallest edit changes only the rule that combines plate order with domain order.
10. Focused validation covers all-plated, all-unplated, mixed, nested, duplicate, and missing plate data.
11. The layer guard checks that the edit stayed in the approved files.
12. `Complete-EiSession.ps1` finalizes the session and writes the readable summary.
13. The summary check confirms the history evidence, changed file, test result, and final outcome.

## Folder tree

```
aveva-ei-graphics/
├── .github/plugin/plugin.json
├── README.md
├── INSTRUCTIONS.md
├── agents/
│   └── ei-graphics.agent.md
└── skills/
    ├── ei-graphics-core/
    │   ├── SKILL.md
    │   ├── schemas/          five schemas
    │   ├── references/       the registry, plus two files the agent loads on demand
    │   └── scripts/          nine scripts
    ├── ei-azure-devops-cli-intake/
    │   ├── SKILL.md
    │   └── scripts/          the intake script and its two helpers
    ├── ei-layer-guard/
    │   ├── SKILL.md
    │   └── scripts/
    ├── ei-graphics-doctor/
    │   ├── SKILL.md
    │   └── scripts/
    └── termination-drawing/
        ├── SKILL.md
        └── references/       five files, loaded only when needed
```

## Session files

Run files go in `.ei-session-logs/<story number>`. That folder is not committed.

| File | Written by | What it holds |
|---|---|---|
| `ado.json` | `Write-EiArtifact.ps1` | The fetched story |
| `story-understanding.json` | `Write-EiArtifact.ps1` | What the agent understood after approval |
| `approved-files.json` | `Write-EiArtifact.ps1` | Files approved for changes |
| `session.json` | `Write-EiSessionEntry.ps1` | The session steps |
| `session-summary.md` | `Export-EiSessionSummary.ps1` | A readable session summary |
| `attachments/` | `Convert-EiAdoIntake.ps1` | Story images |

`story-understanding.json` and `approved-files.json` carry a `hash` to detect changes. `ado.json`
uses the `adoHash` field in `story-understanding.json` instead.

## Adding a domain skill

Change two files:

1. Write `skills/<name>/SKILL.md`, with a `name` matching the folder and a `## When to Use` list.
2. Add one entry to `skills/ei-graphics-core/references/domain-skill-registry.json`.

Do not edit the manifest or tests. The registry is the full skill list.
