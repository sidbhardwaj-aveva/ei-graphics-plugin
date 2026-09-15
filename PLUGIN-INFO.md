# Plugin information

| | |
|---|---|
| Name | `aveva-ei-graphics` |
| Catalogue entry | `aveva-ei-graphics-plugin` |
| Version | 1.0.0 |
| Agent | `ei-graphics` |
| Skills | 4 tools and 1 domain skill |
| Needs | PowerShell 7 or later, `az` with the Azure DevOps extension, git |
| Also expects | The `aveva-rnd` plugin, for review, commit and delivery |

## What it does

It takes an Azure DevOps story about Electrical and Instrumentation (EI) Graphics through to a
verified fix. It asks for approval of the story meaning and the planned changes.

## What it deliberately does not do

It does not review code, create commits, or open pull requests. The `aveva-rnd` plugin does that.

It does not assess itself. A person improves skills by reading a session summary and editing the
skill document.

It reports changes outside the approved list and leaves the decision to you.

## Where things live

- The agent: `plugins/aveva-ei-graphics/agents/ei-graphics.agent.md`
- The scripts: `plugins/aveva-ei-graphics/skills/ei-graphics-core/scripts/`
- The schemas: `plugins/aveva-ei-graphics/skills/ei-graphics-core/schemas/`
- Run files: `.ei-session-logs/<story number>/`, not committed

## Installing it

Both marketplace files are already in place: one under `.claude-plugin/` and one under
`.github/plugin/`. Point your editor at this repository to load the plugin.

The files use different path bases. In the first, the source path starts at the repository root.
In the second, the plugin root starts at the repository root and the source starts there. Moving
either file can break its paths.

## Shared session records

Each completed run stays in `.ei-session-logs/<story number>/` and is not committed. Set
`EI_GRAPHICS_SHARE_PATH` to copy the completed bundle to an approved internal share. The standard
location is
`\\INHYDD1510\Share\ei-graphics-plugin-sessions`.

The copy contains `ado.json`, `story-understanding.json`, `approved-files.json`, `session.json`,
and `session-summary.md`. It may contain story text, comments, interactions, and evidence. Only
authorized people should use the share. If the share is unavailable, the local bundle stays in
place and can be exported later.
