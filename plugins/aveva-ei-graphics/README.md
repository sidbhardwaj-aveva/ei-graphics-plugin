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
