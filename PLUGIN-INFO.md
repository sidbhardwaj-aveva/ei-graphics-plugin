# Plugin information

| | |
|---|---|
| Name | `aveva-ei-graphics` |
| Catalogue entry | `aveva-ei-graphics-plugin` |
| Version | 1.0.0 |
| Agent | `ei-graphics` |
| Skills | 4 |
| Needs | PowerShell 7 or later, `az` with the Azure DevOps extension, git |
| Also expects | The `aveva-rnd` plugin, for review, commit and delivery |

## What it does

It takes an Azure DevOps story about Electrical and Instrumentation (EI) Graphics and works it
through to a verified fix. It asks a person to agree twice: once about what the story means, and
once about what it will change.

## What it deliberately does not do

It does not review its own code, write the commit, or open the pull request. Those belong to the
`aveva-rnd` plugin, which is read directly rather than wrapped.

It does not grade itself. Improving the skills is a person reading a session summary and editing a
skill document.

It does not decide what to do about a change that went outside the agreed list. It reports the
drift and leaves the decision to you.

## Where things live

- The agent: `plugins/aveva-ei-graphics/agents/ei-graphics.agent.md`
- The scripts: `plugins/aveva-ei-graphics/skills/ei-graphics-core/scripts/`
- The schemas: `plugins/aveva-ei-graphics/skills/ei-graphics-core/schemas/`
- What a run produces: `.ei-session-logs/<story number>/`, not committed

## Installing it

Both marketplace files are already in place, one under `.claude-plugin/` and one under
`.github/plugin/`. Point your editor at this repository and the plugin is found.

The two files use different bases, which is worth knowing if you ever move them. In the first, the
source path is relative to the repository root. In the second, the plugin root is relative to the
repository root, but the source is relative to the plugin root. Moving either file breaks its
paths.

## Shared session records

Each completed run remains in `.ei-session-logs/<story number>/` and is not committed. Set
`EI_GRAPHICS_SHARE_PATH` to send a copy of the full completed bundle to an approved internal
share. The standard location is
`\\INHYDD1510\Share\Siddanth\ei-graphics-plugin-sessions`.

The copy contains `ado.json`, `story-understanding.json`, `approved-files.json`, `session.json`,
and `session-summary.md`. It can contain story text, comments, interactions, and evidence. Only
people authorized for that material should use the share. If the share is unavailable, the local
bundle stays in place and can be exported again later.
