# Instructions

How to use this plugin and what it will ask you.

## Starting a run

Give the agent a story link or pasted title. It finds the story number for you.

## The two checks

**It explains what it understood.** Check this for mistakes. Later comments override the story
description, and the agent will say so.

**It shows a plan for a large change.** The plan lists the files, changes, reason, test command,
and anything not tested.

You can approve, change, or refuse the plan. Your decision is recorded and checked again at the end.

For a small change with a documented domain pattern, it skips plan approval and fixes it.

## What it will not do without asking

- Change a file you did not approve. Any such change is reported.
- Add a test you did not ask for.
- Clean up unrelated code.
- Commit when the layer check reports a problem.

## When it cannot help

If no domain skill covers the area, the agent stops and asks which files and rules matter. That
answer can later be added to a skill.

## When reasoning is stuck

The agent stops when information is missing, conflicts, or does not support a conclusion. It says
what is unclear and asks one focused question. Give it the relevant file, expected behavior, rule,
error, or decision.

## After the run

Read `.ei-session-logs/<story number>/session-summary.md`. Its last section is for you.

If it had to read files not listed in the skill, add them to the skill for the next run.

## If something goes wrong

The agent stops if the story was not fully fetched. If intake fails, there is no `ado.json`.

Every message names the file and the next action. Report any message that does not.
