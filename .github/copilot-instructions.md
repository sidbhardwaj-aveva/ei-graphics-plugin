# EI Graphics Plugin — repository conventions

This repository is the **primary development repo** for the `aveva-ei-graphics` plugin.
All changes are made here. See "Relationship to `aveva-agent-plugins`" below.

## Before implementing anything

Read these first — the working tree is often ahead of the request:

1. `specs/002-ei-graphics-plugin-foundation/current-status.md` — phase snapshot and completed work.
2. `specs/002-ei-graphics-plugin-foundation/progress-log.md` (tail) — the execution journal.
3. `specs/002-ei-graphics-plugin-foundation/todo-list.md` — the task tracker.

`plugins/aveva-ei-graphics/README.md` (skills table, structure tree, phase status, known
limitations) is the file that most often drifts behind implemented work — check it in every tranche.

## Governing rule: AI vs deterministic tooling

LLMs are non-deterministic. The same prompt can produce different output and can interpret the same
rule inconsistently across runs.

- Use AI where **reasoning and interpretation** add value (diagnosis, drafting, triage, summarising,
  choosing an approach).
- Use **deterministic tooling** (PowerShell + Pester) wherever a rule must be enforced the same way
  every single time (gates, validation, scope checks, schema checks).
- A quality gate must never depend on model judgement. If it can pass or fail, it is a script with
  an exit code and a test.

## Workflow rules

- Fail closed: absence of evidence is never a pass. Unimplemented stages BLOCK.
- Max 3 correction attempts.
- No `runSubagent`.
- Reuse `/aveva-rnd:*` and `/aveva-core:*` skills; never reimplement them.
- Validation contract: `{ Status: 'Valid'|'Invalid', Errors, Warnings, Details }`;
  exit `0` = Valid, `1` = Invalid; `-Json` emits JSON.
- Run state lives in `.copilottracking/ei-graphics/<story-id>/` (git-ignored).
- Never hand-edit `workflow-state.json`. Use `Set-EiWorkflowStage.ps1 -Action start|complete|block`.
  Failed validation must never mutate state — validate a temp candidate, then commit.

## Spec sync gate

Any change under `plugins/aveva-ei-graphics/**` needs a matching change under
`specs/002-ei-graphics-plugin-foundation/**`, or the gate fails:

```powershell
./tools/Test-EiGraphicsSpecSync.ps1 -FromRef origin/main -ToRef HEAD
```

Never invoke a gate script via `pwsh -File script.ps1 -ChangedPaths $array`: `-File` passes args as
flat strings, so array elements bind to the *following* parameters and the gate silently PASSes on
one path. Use in-process invocation: `& ./tools/Test-EiGraphicsSpecSync.ps1 -ChangedPaths $paths`.
Sanity-check the echoed "Plugin prefix" / "Changed files" header before trusting a PASS.

## Tests

```powershell
pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
```

- Pester 5+ required (`New-PesterConfiguration`).
- `Should -Throw -ExpectedMessage` uses `-like`, so substrings need `*wildcards*`.

## PowerShell conventions

- Scripts use `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, and
  `$PSScriptRoot`-relative paths.
- Never write an array-normalising helper with `ValueFromPipeline` + `, @($Value)`: the pipeline
  re-wraps each element, so multi-element JSON arrays arrive as `Object[]` items and property access
  silently returns nothing. Use a plain positional parameter returning `@($Value)`.
- `Get-EiPathSegment`-style helpers: always wrap results in `@()` at the call site, or a
  single-segment result is a string and `$x[0]` yields a char.

## Environment gotchas

- The repo is OneDrive-backed: `git rm -r` prompts to retry directory deletion — answer `n`, then
  `Remove-Item -Recurse -Force`. Use `git -c gc.auto=0 commit`.

## Relationship to `aveva-agent-plugins`

The plugin also exists in the `AVEVA-Copilot-Access/aveva-agent-plugins` monorepo. **This repo is
now where development happens**; the monorepo copy is downstream. When a tranche lands here, mirror
`plugins/aveva-ei-graphics/**` and `tests/aveva-ei-graphics/**` back to the monorepo.

The monorepo keeps `specs/002-ei-graphics-plugin-foundation/**` too; this repo additionally carries
the design docs under `specs/002-ei-graphics-plugin-foundation/design/`, which are deliberately not
shipped inside `plugins/` so the plugin package stays clean.

Check drift with:

```powershell
git diff --no-index --name-status ..\aveva-agent-plugins\plugins\aveva-ei-graphics .\plugins\aveva-ei-graphics
```
