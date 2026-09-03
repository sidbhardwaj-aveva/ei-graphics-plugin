---
name: ei-graphics
description: Work an Electrical and Instrumentation (EI) Graphics story from an Azure DevOps link through to a verified fix. Uses domain skills for the code, the layer guard before committing, and a session log a maintainer can read afterwards.
---

# EI Graphics

## Intake

Run the intake script, pipe it through `Convert-EiAdoIntake.ps1`, then through
`Write-EiArtifact.ps1 -ArtifactType ado`. If either exits with a code other than 0, report the
failure and stop. Never carry on to understanding the story without an `ado.json`.

Read `ado.json` for everything after that. Never fetch the story from ADO again.

A comment can correct the description. Where the two disagree, the later comment wins.

## Choosing a domain

Run `Get-EiDomainSkillCatalog.ps1` and pick from what it returns. Never invent a domain
identifier. If nothing matches, use the block in `references/rnd-delegation.md` under
"No matching domain skill", word for word.

## Implementation priority: skill-first, explore-second

1. Check the domain skill's bug patterns. If one matches the symptom, use its documented cause and
   files, and fix it directly. Do not search the codebase.
2. If none matches, read the skill's Key Files table. Open those files first.
3. Only search more widely when the skill says nothing about the situation.
4. Every file you read that is not in the Key Files table probably means the skill has a gap.
   Note it in the session log.

## Working

- Understand the cause before you edit. Separate the symptom from what you think caused it. If no
  pattern matches and the evidence is thin, say so. Do not guess at a fix.
- Make surgical changes. Touch only what the fix needs. Leave nearby code, comments and formatting
  alone. Match the style already there.
- Small change: fix it, then verify. Large change: show the plan from
  `references/checkpoint-templates.md` and wait for a person to agree.
- Verify before you say you are done. Run a test command from the skill, or a build. "It looks
  right" is not verification.
- Surface test gaps. After reading the source, check whether a test covers the code you changed.
  If none does, ask whether to add one.
- Run the layer guard before committing. If it reports `blocked`, report the violation and do not
  commit.
- Stop when done. Once the tests pass and the guard is clear, stop. No polish, no tidying nearby
  code, no extra tests beyond what was agreed.

Log every step with `Write-EiSessionEntry.ps1`, then close the session with `-Finalize` and render
the summary with `Export-EiSessionSummary.ps1`.

When `EI_GRAPHICS_SHARE_PATH` is set, run `Export-EiSessionBundleToShare.ps1` after the summary.
It copies the completed bundle to that approved internal share. It is optional because the bundle
contains story text, comments, interactions, and evidence. If export reports a share problem, say
that the local bundle remains available and give the person the retry command.

On the first run in a repository, add `.ei-session-logs/` to `.gitignore`.

## How to write

- Short sentences. One idea each.
- Ordinary words. Write `start`, not `commence`.
- Name the file and the next action when you report a problem. "Validation failed" is not enough.
- Explain the decision before you show the diff.
- Never answer with a bare identifier, and never paste a raw error dump.
- Do not narrate your steps or your tool calls. Lead with what happened, what it means, and what is
  next.
- The person reading is often not the person who wrote the code.

## References

- `references/rnd-delegation.md` — read before review, commit or delivery.
- `references/checkpoint-templates.md` — read before showing a plan to a person.
