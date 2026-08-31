# demo-ei-graphics

An agent plugin for working Electrical and Instrumentation (EI) Graphics stories.

You give it a link to an Azure DevOps story. It reads the story, agrees with you what it will
change, makes the change, checks it, and writes a summary you can read afterwards.

The agent does the thinking. The skills hold what is known about the code. Nothing in here tries
to reason on the agent's behalf.

## Before you run it

There is no automatic check for any of this. If something is missing, the error you get is the
diagnosis. That is deliberate, because checking the same five things on every run wastes time.

- [ ] `az` is signed in, and the account can read the story.
- [ ] The git working tree is clean, or your work is stashed.
- [ ] The dotnet toolkit is on the path.
- [ ] The product repository is cloned where you expect it.
- [ ] Your editor is running in agent mode.

You also need PowerShell 7 or later, and Pester 5 or later to run the tests.

## How to run it

Give the agent the story link. It will:

1. Fetch the story, its images and its discussion, and save them as `ado.json`.
2. Tell you what it understood, and wait for you to agree. This is the first checkpoint.
3. Pick a domain skill from the registry, or tell you plainly that none fits.
4. For a small change, fix it. For a large one, show you a plan and wait. That is the second
   checkpoint.
5. Run the layer guard, then the tests named by the skill.
6. Write the session log, and render the summary.

Everything it writes lands in `.ei-session-logs/<story number>/`, which is not committed.

To run the tests yourself:

```powershell
pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
```

## How to read a session summary

Open `.ei-session-logs/<story number>/session-summary.md`. It has four parts.

The header gives you the duration, the tokens, the domain skill used and the outcome. There is no
cost figure, because nothing records a price and guessing one would be worse than leaving it out.

The timeline is one row per step, with the time and what happened.

The reasoning trail is the agent explaining, in its own words, why it did each thing. This is the
part to read when the result surprised you.

The last part is written for you as the maintainer. It says which skill was used and which files
the agent had to read. It also gives the time spent waiting for a person, and how much work the
agent did. Read this one even when the run went well.

## Making the skills better

This loop is manual on purpose. There is no automatic grading.

1. Run the agent on a real story.
2. Read the maintainer section of the summary.
3. Look at the files the agent read. Any file that is not already in the skill's Key Files table
   is a gap.
4. Add the missing file, or the missing pattern, to the skill or one of its reference files.
5. Run it again on the next story.

Each pass makes the next run cheaper, because the agent searches less and reads the skill more.

## What is in here

| Folder | What it holds |
|---|---|
| `plugins/demo-ei-graphics/` | The plugin: one agent, four skills |
| `tests/` | Every test, run by `Invoke-PesterTests.ps1` |
| `tools/` | `Test-BuildProgress.ps1`, which checks the build record |
| `docs/` | The design this was built from. Kept as it was written, never edited |

`BUILD-PROGRESS.md` and `BUILD-LOG.md` record how this repository was built, task by task.
