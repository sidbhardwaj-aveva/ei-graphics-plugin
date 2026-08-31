# Working in this repository

Read `plan.md` first. It is the build script, and it wins over anything here.

## Only machines decide pass or fail

If a rule can pass or fail, it is a PowerShell script with an exit code and a Pester test. Never
judge by eye. A skipped test is a blocked task, not a green one. No evidence means no pass.

## The loop for every task

One task at a time. Never start the next until the current one says `DONE`.

1. Set the row to `IN-PROGRESS` in `BUILD-PROGRESS.md` and update the `Current task` header.
   Append the `BUILD-LOG.md` block, with its `**Assumptions:**` line, before doing any work.
   Commit: `build(T0NN): start <title>`
2. Do the work.
3. Run the task's check command. It must exit 0. Three failed attempts is the limit: after that,
   set the row to `BLOCKED`, write the diagnosis, commit, and ask a person.
4. Run `pwsh -NoProfile -File ./tools/Test-BuildProgress.ps1`. It must exit 0.
5. Run `pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1`. It must exit 0.
6. Finish the `BUILD-LOG.md` block: attempts, decisions, result.
7. Set the row to `DONE`, add the timestamp, and put the word `pending` in the Commit column.
8. Commit: `build(T0NN): <title>`
9. Write the resulting short SHA into the Commit column, replacing `pending`.
   Commit: `chore(T0NN): record commit sha`

Three commits per task. Never use `git commit --amend`. The `pending` marker exists so that
amending is never needed.

`BUILD-LOG.md` is append only. Never edit an old entry. If an earlier entry turns out to be wrong,
correct it in the current task's entry and say so.

If a task can be read two ways, stop. Write the options and your recommendation, set the row to
`BLOCKED`, commit, and ask.

## PowerShell conventions

Every script we write starts with `#Requires -Version 7.0`, then `Set-StrictMode -Version Latest`
and `$ErrorActionPreference = 'Stop'`. Paths resolve from `$PSScriptRoot`. JSON goes to stdout and
messages go to stderr. Exit 0 on success and 1 on failure. Running twice is safe. Nothing prompts.
Every one of them has a `-Help` switch.

Copied scripts are exempt. They keep their own shape and must not be edited to match ours.

Every error message names the file and says what to do next. "Validation failed" is a defect.

## Traps already paid for

- **Never** run a gate as `pwsh -File script.ps1 -ChangedFiles $array`. The `-File` switch
  flattens the array and the gate passes silently. Call it in process with `&`.
- A function returning a one-item array gives back a bare object. Return `, $items` instead.
- An ordered dictionary has `Contains` but no `ContainsKey`, and no `Clone`. A hashtable has both.
- `ConvertFrom-Json` turns a timestamp string into a date object. Writing it out again changes its
  format. Convert it back, or assert against the raw file text.
- Sort keys with `[StringComparer]::Ordinal`, never `Sort-Object`, which compares by culture.
- `Should -Throw -ExpectedMessage` matches with `-like`, so a substring needs `*wildcards*`.
- Pester needs `-ForEach` data at discovery time, so build it at the top of the file, not in
  `BeforeAll`.

## Git and OneDrive

Both repositories live in OneDrive. Commit with `git -c gc.auto=0 commit`, or garbage collection
will fight the sync client.

If `git rm -r` asks you to retry a deletion, that is OneDrive. Answer `n`, then use
`Remove-Item -Recurse -Force`, then commit.

Git will warn that LF will be replaced by CRLF. That is expected and harmless here.
