# aveva-ei-graphics

The plugin itself. One agent and four skills.

## Skills

| Skill | What it is for | When it is read |
|---|---|---|
| `ei-graphics-core` | The six scripts that write and read the artifacts, plus their schemas | Whenever the agent needs to write or read an artifact |
| `ei-azure-devops-cli-intake` | Fetching a story, its images and its discussion | At the start of a run |
| `ei-layer-guard` | A pass or fail check on architecture rules | Before committing |
| `termination-drawing` | What is known about the termination drawing code | When the story is about that area |

`termination-drawing` is a domain skill. The other three are tools. Only domain skills appear in
`domain-skill-registry.json`.

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
    │   └── scripts/          six scripts
    ├── ei-azure-devops-cli-intake/
    │   ├── SKILL.md
    │   └── scripts/          the intake script and its two helpers
    ├── ei-layer-guard/
    │   ├── SKILL.md
    │   └── scripts/
    └── termination-drawing/
        ├── SKILL.md
        └── references/       five files, loaded only when needed
```

## Artifacts

Everything a run produces lands in `.ei-session-logs/<story number>/`. That folder is not
committed.

| File | Written by | What it holds |
|---|---|---|
| `ado.json` | `Write-EiArtifact.ps1` | The story as it was fetched |
| `story-understanding.json` | `Write-EiArtifact.ps1` | What the agent understood, after you agreed |
| `approved-files.json` | `Write-EiArtifact.ps1` | The files you agreed it may change |
| `session.json` | `Write-EiSessionEntry.ps1` | Every step, added one at a time |
| `session-summary.md` | `Export-EiSessionSummary.ps1` | The same session, written for a person |
| `attachments/` | `Convert-EiAdoIntake.ps1` | The images attached to the story |

`story-understanding.json` and `approved-files.json` each carry a `hash`. `ado.json` does not,
because its schema allows no such field. It is tied down instead by the `adoHash` field inside
`story-understanding.json`.

## Adding a domain skill

Two files change, and nothing else.

1. Write `skills/<name>/SKILL.md`, with a `name` matching the folder and a `## When to Use` list.
2. Add one entry to `skills/ei-graphics-core/references/domain-skill-registry.json`.

No manifest edit. No test edit. Nothing counts the skills.
