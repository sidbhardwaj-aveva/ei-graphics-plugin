---
name: termination-drawing
description: >
  Diagnose, implement, and verify AVEVA EI Termination Drawing features.
  Covers the full drawing generation/update pipeline, LOC model, shape
  metadata and composite-key system, connector routing, and multi-sheet
  layout. Accepts a diagnostic log, ADO work item, or plain-text symptom
  and returns a structured diagnosis with optional code changes.
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - run_in_terminal
  - read_file
  - grep_search
  - file_search
  - semantic_search
  - replace_string_in_file
  - multi_replace_string_in_file
  - create_file
  - get_errors
---

# Termination Drawing Skill

## When to Use
Use this skill when working on AVEVA EI Termination Drawing features including:
- Drawing generation/update workflow issues
- LOC (Levels of Connectivity) model and traversal bugs
- Shape placement, translate, delete logic during update
- Wire/core/cable connector routing and visibility
- Multi-sheet layout, group overlap, and vertical stacking
- Equipment/terminal metadata and `insertedTags` composite key system
- Connected object deduplication and merge logic

---

## Goal
Given a symptom, diagnostic log, or ADO work item, produce a structured diagnosis that identifies
the root cause within the Termination Drawing pipeline, proposes a code fix, and verifies it.

---

## Inputs
| Parameter | Required | Description |
|-----------|----------|-------------|
| `adoWorkItemId` | one-of | ADO work item ID (`ADO#<id>`) |
| `diagLogPath` | one-of | Path to `ts-diag.log` on the user's machine |
| `symptomText` | one-of | Free-text symptom or pasted log fragment |
| `codebasePath` | optional | Root of the local `dabacon-products` clone. Defaults to the current working directory, since the agent is invoked from `Engineering/Modules/EI/Source`. |
| `isUpdateScenario` | optional | `true` if the bug occurs only during drawing UPDATE (re-generation), not first creation |

At least one of `adoWorkItemId`, `diagLogPath`, or `symptomText` is required.

---

## Output Contract
Return a JSON object:

```json
{
  "status": "diagnosed | fixed | needs-log | blocked | setup-failed | verification-unconfirmed",
  "issueClass": "model | insert | update-cleanup | connector-routing | metadata | layout",
  "rootCause": "<one sentence>",
  "affectedFiles": ["relative path", "..."],
  "evidenceUsed": ["log line, commit, or file and line that supports the root cause"],
  "logEvidence": ["line or pattern that proves the root cause"],
  "alternativeHypotheses": ["the cheaper explanation, and what would tell it apart"],
  "proposedFix": "<description of the code change>",
  "criticalRulesApplied": ["rule 1", "..."],
  "testCommand": "dotnet test ... --filter ...",
  "confidence": 0.0,
  "runtimeVerificationStatus": "verified | unavailable | unconfirmed"
}
```

- `status: needs-log` → the symptom alone is insufficient **and** the Step 1b triage found no
  commit that controls the reported behaviour. Request the log, and say what triage ruled out.
- `status: blocked` → contradictory evidence; explain what is missing.
- `status: setup-failed` → a required script or path could not be resolved, so no work was done.
- `status: verification-unconfirmed` → the fix is in place, but no executed test or regenerated
  drawing confirms it.
- `confidence` in `[0, 1]`. It measures the **root cause only**. Anything below `0.7` must
  accompany a `blocked` or `needs-log` status.
- `runtimeVerificationStatus` is separate from `confidence`. `unavailable` means no log and no
  regeneration were possible. `unconfirmed` means the targeted test emitted no result.

### Never collapse these two pairs

A build is not a test result. Historical evidence is not runtime verification. Report the three
facts separately, in these words:

```text
root-cause confidence: high
runtime reproduction: unavailable
fix verification: build passed, targeted test execution unconfirmed
```

Never say the drawing is fixed without a regenerated drawing or an executed targeted test.

### The historical-regression evidence path

A runtime log stops being mandatory only when **all five** of these hold:

1. the symptom is clear;
2. Step 1b found a relevant historical commit;
3. the changed code directly controls the reported behaviour;
4. the old and new behaviour can be compared from source;
5. the proposed fix is narrow and testable.

Miss any one of them and the answer is `needs-log`, not a diagnosis. When all five hold, return
`diagnosed` with `runtimeVerificationStatus: unavailable`, never `fixed`.

---

## Invocation Workflow
### Step 1 — Understand the Problem
- Determine whether the bug is a **CREATION** issue (first generation) or an **UPDATE** issue (re-generation).
- If only a symptom is supplied, run Step 1b before you ask for the diagnostic log.
- Check `MODEL-DONE` to understand what's in the model.
- Check `INSERT-START` to confirm insertion order.

### Step 1b — Regression Triage

Run this fixed sequence whenever the symptom is an order, a position, a layout, a grouping, a
rendering sequence, or any output that used to be right and has changed. Run it before you return
`needs-log`. Run the steps in order.

a. Classify the symptom as creation, update, or both.
b. Name the owning pipeline phase from `references/architecture.md`.
c. Search local history for the symbols and key files that phase owns:

```powershell
git log --all --oneline -S "<symbol>" -- <key file> <key file>
git log --all --oneline -- <key file> <key file>
```

d. Read each candidate commit: `git show <commit> -- <key file>`.
e. Compare the current implementation with the last known-good one. Name the method that changed
   and what the change did to the reported behaviour.
f. Only now decide whether a runtime log is needed.

This is a fixed list, not an invitation to explore. Take at most one history hop, then return to
the Key Files the architecture reference selected. If the sequence finds no commit that touches
the reported behaviour, say so and ask for the log.

### Step 2 — Analyse the Log

Run the PowerShell patterns in `references/log-analysis.md` against the supplied log path.

When the conclusion depends on earlier code, inspect local Git history separately from the ADO
story. In chat and the session log, show the exact commands and source lines: `git log --all
--oneline -S "<symbol>" -- <file> <file>`; `git blame -L <start>,<end> <file>`; `git show
<commit> -- <file> <file>`. Record the commit, title, related work item, file, line, symbol and
quote in `reasoning` and `evidence` through `Write-EiSessionEntry.ps1`. Use an informational entry
for history. It shows provenance, not proof that the story or every scenario is verified.
### Step 3 — Read Source Before Touching It

Before modifying any file, call `read_file` on the full relevant source file.  
Identify the exact method and line where the bug lives using `grep_search`.

### Step 3b — Record the Hypothesis Before You Edit

Write these six lines before the first edit, and put them in the session log:

1. the symptom, in the words the reporter used;
2. the expected phase, from the phase table in `references/architecture.md`;
3. the owning method you selected;
4. one falsifiable hypothesis;
5. one cheaper alternative hypothesis;
6. the discriminating evidence that would tell the two apart.

If you cannot name the discriminating evidence, you are not ready to edit.

Apply the one-phase-later rule in `references/architecture.md`. When the log shows `MODEL-DONE`
and `INSERT-START` already holding the expected order, do not change model ordering code; move one
phase later and inspect placement and post-placement adjustment. When there is no log but Step 1b
identifies an ordering change, a model-builder fix may be proposed with runtime confirmation
labelled as missing.

### Step 4 — Implement the Fix

- Apply only the change that fixes the root cause. Do not refactor surrounding code.
- Follow the composite-key patterns documented in **Shape Metadata & Composite Key System** below.
- Ensure backward compatibility with legacy untagged shapes.
- Add a `TsDiag.Log` call for any new code path that affects shape state.

### Step 5 — Verify

```powershell
# Compile check (run from codebase root)
dotnet build Presentation\Aveva.EI.CanvasDrawings\Aveva.EI.CanvasDrawings.csproj --no-incremental

# Run targeted tests
dotnet test Tests\Aveva.EI.CanvasDrawings.Test --filter "FullyQualifiedName~<ClassName>" --no-restore
```

Ask the user to rebuild and regenerate the drawing, then provide the new log.  
Compare `MODEL-DONE` and `BOX-ACTION` patterns between old and new log to confirm the fix.

Keep compile and targeted-test results in a separate validation entry, not in Git-history evidence.

---

## Testing

### Running Tests

Run from the codebase root (`Engineering/Modules/EI/Source`), which is the working directory
the agent is invoked from.

```powershell
dotnet test Tests\Aveva.EI.CanvasDrawings.Test --filter "FullyQualifiedName~CoreConnectorManager" --no-restore
dotnet test Tests\Aveva.EI.CanvasDrawings.Test --filter "FullyQualifiedName~LoopWireConnector" --no-restore
```

### Test Structure
- Tests use NSubstitute for mocking SchematicCanvas API (`Shape`, `Drawing`, `Sheet`, `Connector`)
- `InvokeXxx` helpers use reflection to call private methods
- `insertedTags` assertions must account for composite keys (not plain IDs) for LOC-1+ scenarios

### Key Test Scenarios for LOC Update
1. **5-terminal strip, remove terminal 2**: LOC-0 terminals DELETE-OLD + re-INSERT, positions recalculated
2. **2 JBs, remove one JB**: Connected LOC-1+ shapes deleted, cores from removed JB cleaned up
3. **Same equipment at multiple LOC levels**: Each gets unique metadata, correct one survives update
4. **Legacy drawing update**: Untagged shapes found via fallback, first LOC-0 processing claims them

---

## Critical Rules (Do NOT Violate)

1. **NEVER remove ConnectivityGroupKey from dedup predicate** — causes cascading group-key pollution
2. **NEVER use plain terminal ID for wire validation** — use `IsTerminalInserted()` with composite key
3. **LOC-0 metadata is always "Driving"** — never store LOC level in LOC-0 metadata
4. **Core metadata format**: `"{cableSide}-{connContext}"` — includes cable side to distinguish same-core placed on both sides
5. **Process LOC-0 first** — sorting by LocLevel ensures driving shapes claim untagged legacy shapes
6. **UpdateDrawing checks metadata AS-IS** — don't strip or transform metadata values
7. **Cable shapes use plain IDs** — cables are shared across contexts (single physical shape)
8. **`TsDiag.Log` guard** — only `return` for empty messages, never for non-empty (reversed check silences all logging)
9. **Use `UpdateMetadata` for mutable snapshot values** — `AddMetadata` is write-once (no-op if key exists)
10. **existsInBoth must check shape existence** — only skip if shape found with matching LOC metadata; otherwise fall through to fresh insertion

## References

Load a reference file only when the problem calls for it. Each one is a slice of the original
skill document, moved here so this file stays short.

- `references/architecture.md` — read this first on any new area. It has the pipeline, the key
  files table, the connectivity model and where the code lives.
- `references/composite-key-system.md` — read this when a shape is matched, skipped or duplicated
  wrongly, or when metadata and inserted tags are involved.
- `references/update-flow.md` — read this when the problem only shows up on an update run, or
  when it involves grouping, placement, wire direction or the core connector path.
- `references/log-analysis.md` — read this at Step 2, and whenever you have a diagnostic log to
  work through.
- `references/bug-patterns.md` — read this once you can describe the symptom. Check it before
  writing any new fix, because the fix may already be written down.
