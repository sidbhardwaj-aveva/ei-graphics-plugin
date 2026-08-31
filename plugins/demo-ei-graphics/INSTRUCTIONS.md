# Instructions

How to drive this plugin, and what it will ask of you.

## Starting a run

Give the agent a link to the story. A pasted title works too. You do not need to pull the number
out yourself; the intake skill does that, and it does it the same way every time.

## The two moments it will stop

**It will tell you what it understood.** Read it properly. This is the cheapest place to catch a
misunderstanding. If the description and a later comment disagree, the agent follows the comment,
and it will say so.

**It will show you a plan, if the change is large.** The plan names each file, what changes in it,
and why. It also names the test command it will run, and says whether anything is untested.

You can agree, narrow it, widen it, or refuse it. What you agree to is written down, and checked
again at the end.

For a small change with a documented cause, it skips the second stop and fixes it.

## What it will not do without asking

- Change a file you did not agree to. If one changes anyway, it is reported as drift.
- Add a test you did not ask for.
- Tidy code near the fix.
- Commit when the layer guard reports a problem.

## When it cannot help

If no domain skill covers the area, the agent says so plainly rather than guessing. It will ask
you which files matter and whether there are rules it should follow. Answering well is worth the
minute it takes, because the answer can then be written into a skill.

## After the run

Read `.ei-session-logs/<story number>/session-summary.md`. The last section is written for you.

If the agent had to read files that are not listed in the skill, that is a gap. Add them to the
skill, and the next run will be quicker and more accurate.

## If something goes wrong

The agent stops rather than carrying on with a half-fetched story. If the intake fails, it reports
the failure and stops, and there will be no `ado.json`.

Every message names the file it is talking about and says what to do next. If you ever get one
that does not, that is a defect worth reporting.
