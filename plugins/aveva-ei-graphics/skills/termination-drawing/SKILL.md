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
| `codebasePath` | optional | Local clone root of `dabacon-products`. Defaults to `d:\Git\dabacon-products\Engineering\Modules\EI\Source` |
| `isUpdateScenario` | optional | `true` if the bug occurs only during drawing UPDATE (re-generation), not first creation |

At least one of `adoWorkItemId`, `diagLogPath`, or `symptomText` is required.

---

## Output Contract

Return a JSON object:

```json
{
  "status": "diagnosed | needs-log | blocked | fixed",
  "issueClass": "model | insert | update-cleanup | connector-routing | metadata | layout",
  "rootCause": "<one sentence>",
  "affectedFiles": ["relative path", "..."],
  "logEvidence": ["line or pattern that proves the root cause"],
  "proposedFix": "<description of the code change>",
  "criticalRulesApplied": ["rule 1", "..."],
  "testCommand": "dotnet test ... --filter ...",
  "confidence": 0.0
}
```

- `status: needs-log` → symptom alone is insufficient; request log.
- `status: blocked` → contradictory evidence; explain what is missing.
- `confidence` in `[0, 1]`; anything below `0.7` must accompany a `blocked` or `needs-log` status.

---

## Invocation Workflow

### Step 1 — Understand the Problem
- Determine whether the bug is a **CREATION** issue (first generation) or an **UPDATE** issue (re-generation).
- If only a symptom is supplied and confidence < 0.7, request the diagnostic log before proceeding.
- Check `MODEL-DONE` to understand what's in the model.
- Check `INSERT-START` to confirm insertion order.

### Step 2 — Analyse the Log

Run these PowerShell patterns against the supplied log path:

```powershell
# Model + insertion summary
Select-String -Path $logPath -Pattern "MODEL-DONE|INSERT-START"

# Key shape actions
Select-String -Path $logPath -Pattern "BOX-ACTION|TERM-ACTION|WIRE-INS|CORE-INSERT"

# Validation failures
Select-String -Path $logPath -Pattern "fromValid=False|NO-START-POINT|FAIL"

# Duplicate-insert suppression hits
Select-String -Path $logPath -Pattern "BOX-ACTION action=SKIP-DUPLICATE|TERM-ACTION action=SKIP-DUPLICATE"

# Full numbered output for context
Select-String -Path $logPath -Pattern "MODEL-DONE|BOX-ACTION|TERM-ACTION|WIRE-INS|CORE-INSERT" |
    ForEach-Object { $_.LineNumber.ToString().PadLeft(5) + "  " + $_.Line }
```

### Step 3 — Read Source Before Touching It

Before modifying any file, call `read_file` on the full relevant source file.  
Identify the exact method and line where the bug lives using `grep_search`.

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

---

## Architecture Overview

### Pipeline
```
User Action → Execute() → TryBuildModel() → InsertModel() → FinalizeGeneratedDrawing()
                              ↓                    ↓                    ↓
                    TerminationDrawingModelBuilder  TerminationDrawingInserter  UpdateDrawing() [if isUpdate]
```

### Key Files

| File | Purpose |
|------|---------|
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Controller/TerminationDrawingGenerationWorkflow.cs` | Orchestrates generation/update. Contains `UpdateDrawing()` cleanup logic. |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Model Builder/TerminationDrawingModelBuilder.cs` | Builds LOC-aware model: placement, grouping, wire adjustment, connected equipment traversal |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Inserter/TerminationDrawingInserter.cs` | Sorts model (LOC-0 first), calls InsertAllCanvasEquipmentData |
| `Presentation/Aveva.EI.CanvasDrawings/EquipmentInserter.cs` | Inserts/updates equipment+terminal shapes. Manages `insertedTags` composite keys. Contains `IsShapeFoundOnDrawing` metadata-aware lookup. |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Model/CanvasEquipmentData.cs` | Equipment data model: terminal creation, cable/core processing, strip layout, sheet transitions |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Model/CanvasTerminalData.cs` | Terminal data: position, connectivity side, parent reference |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Model/CanvasCoreData.cs` | Core data: ModelPoints, ConnCanvasTerminalData, OnSideOfEquipTerminal |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Manager/CoreConnectorManager.cs` | Core connector insertion/update. Composite key system for core shapes. |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Manager/CableShapeManager.cs` | Cable shape insertion, neighbor lookup for invisible cables |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Inserter/WireConnectorInserter.cs` | Wire insertion: terminal validation via `IsTerminalInserted`, extreme-side skip |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Inserter/LinkConnectorInserter.cs` | Link connector insertion with terminal validation |
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Inserter/LoopWireConnectorInserter.cs` | Loop wire insertion with terminal validation |
| `Presentation/Aveva.EI.CanvasDrawings/Helper/MetaDataHelper.cs` | Metadata constants: `ShapeConnectivitySide`, `ConnectivitySideDriving` |
| `Presentation/Aveva.EI.CanvasDrawings/Helper/TsDiag.cs` | Diagnostic logging to `D:\HVE\ts-diag.log` |

---

## Core Concepts

### LOC (Level of Connectivity)
- **LOC-0**: Driving object (equipment selected by user). `IsConnectedObject = false`, `LocLevel = 0`.
- **LOC-1+**: Connected objects placed at increasing hops from the driver. `IsConnectedObject = true`, `LocLevel = 1,2,3...`
- Each internal wire hop = 1 LOC level. Cable connection between enclosures = 1 LOC level.
- Same domain object ID can appear at multiple LOC levels (as both driving content and connected object).

### Connectivity Sides
- `ConnectivitySide = ""` → LOC-0 driving placement (no side)
- `ConnectivitySide = "Right"` → Connected on the right side of the source
- `ConnectivitySide = "Left"` → Connected on the left side of the source

### BackLayerShape
- `true` means the shape is INVISIBLE (suppressed duplicate). The visible instance is rendered elsewhere.
- Connected enclosure's sub-equipment are `BackLayerShape = true` (the sub-equipment gets its own independent connected placement).

---

## Shape Metadata & Composite Key System

### Purpose
During drawing UPDATE, `UpdateDrawing()` must delete shapes that are no longer in the model while keeping shapes that ARE in the model. When the same domain ID appears at multiple LOC levels/sides, plain IDs can't distinguish which shape to keep vs delete.

### Metadata Values (stored on each shape via `AddMetadata`)
Key: `MetaDataHelper.ShapeConnectivitySide`

| Shape Type | LOC-0 metadata | LOC-1+ metadata |
|------------|----------------|-----------------|
| Equipment/Terminal | `"Driving"` | `"{locLevel}-{side}"` e.g., `"1-Right"`, `"2-Left"` |
| Core connector | `"{cableSide}-Driving"` e.g., `"Right-Driving"` | `"{cableSide}-{locLevel}-{side}"` e.g., `"Left-1-Right"` |

### Composite Key in `insertedTags`
| Shape Type | LOC-0 key | LOC-1+ key |
|------------|-----------|------------|
| Equipment/Terminal | `"domainId"` (plain) | `"domainId|{locLevel}-{side}"` e.g., `"=604003932/187898|2-Right"` |
| Core connector | `"coreId|{cableSide}-Driving"` | `"coreId|{cableSide}-{locLevel}-{side}"` e.g., `"=604003932/187543|Left-1-Right"` |
| Cable | `"cableId"` (plain, single shared shape) | N/A |

### UpdateDrawing Logic
```csharp
var shapeSide = shape.GetMetadata(MetaDataHelper.ShapeConnectivitySide);
string compositeKey;
if (string.IsNullOrEmpty(shapeSide) || shapeSide == "Driving")
    compositeKey = shape.LinkedId.ToString();          // LOC-0 or legacy
else
    compositeKey = shape.LinkedId + "|" + shapeSide;   // LOC-1+ or core

// Shape survives if its compositeKey is in insertedTagSet
```

### IsShapeFoundOnDrawing (Equipment/Terminal)
```csharp
// Finds shape by LinkedId + metadata match
// Priority: exact metadata match > fallback to untagged legacy shape
IsShapeFoundOnDrawing(tagId, connectivitySide)
// connectivitySide="" → looks for "Driving" metadata
// connectivitySide="1-Right" → looks for "1-Right" metadata
```

### Wire/Link/LoopWire Terminal Validation
All three connector inserters use `IsTerminalInserted()`:
```csharp
private static bool IsTerminalInserted(CanvasTerminalData terminal, List<string> insertedTags)
{
    var id = terminal.DomainObject.Id;
    var side = terminal.ConnectivitySide ?? "";
    if (string.IsNullOrEmpty(side))
        return insertedTags.Contains(id);                    // LOC-0: plain ID
    var locLevel = terminal.ParentCanvasEquipmentData?.LocLevel ?? 0;
    return insertedTags.Contains(id + "|" + locLevel + "-" + side);  // LOC-1+: composite
}
```

---

## Drawing Update Flow (isUpdate = true)

1. **TryBuildModel**: Rebuilds the canvas model from current DB state (equipment may have been added/removed)
2. **InsertModel**: Inserts/translates/deletes shapes based on model vs existing drawing
   - LOC-0 shapes: DELETE-OLD + INSERT (fresh placement)
   - LOC-1+ shapes: TRANSLATE if found on same sheet, else DELETE-OLD + INSERT
   - Each processed shape's composite key added to `insertedTags`
3. **UpdateDrawing**: Deletes all shapes whose composite key is NOT in `insertedTags`
   - Shapes from removed equipment get deleted
   - Legacy untagged shapes (pre-metadata) use plain LinkedId

### Key Rules
- LOC-0 items are ALWAYS re-inserted (delete old, insert new) — they don't translate
- LOC-1+ items try to TRANSLATE existing shapes to new position (avoids flicker)
- `insertedTags.Contains(key)` guards prevent double-processing when same ID appears multiple times
- Equipment sorted by LocLevel (LOC-0 first) ensures driving shapes claim untagged legacy shapes before connected shapes

---

## Model Builder Key Concepts

### Grouping
- **Cable nodes**: Grouped by source sub-equipment (`GroupCableNodesBySourceEquipment`)
- **Internal wire nodes**: Grouped by source sub-equipment (`GroupInternalWireNodesBySourceEquipment`)
- Each group processes independently with own `processedIds` and `lastPlacedBottom`

### Connected Equipment Placement
```
TryGetStartPoint → determines X,Y for connected item
  Cable connection: source cable's ModelStartPoint.Y
  Internal wire: source terminal's ModelLocation.Y + far-end X
```

### Wire Direction
- Each wire has TWO entries on driving object: outgoing (Side.Right) + incoming (Side.Left)
- `BackLayerShape = true` = wire is invisible (rendered on opposite equipment)
- Wire ModelPoints[4]: `[terminal, bend1, bend2, far-end]` (Right) or `[far-end, bend1, bend2, terminal]` (Left)

### Deduplication
- Connected objects deduplicate within same `ConnectivityGroupKey`
- NEVER remove ConnectivityGroupKey check — cross-group dedup causes cascading corruption
- `MergeDedupChildTerminals` and `MergeDedupCableCores` handle merge of terminal/cable data

---

## Diagnostic Logging

### Enable
Logging writes to `D:\HVE\ts-diag.log`. Ensure `TsDiag.cs` has correct guard:
```csharp
if (string.IsNullOrEmpty(message)) return;  // Only skip empty messages
```

### Key Log Patterns
| Pattern | Meaning |
|---------|---------|
| `MODEL-DONE count=N items=[...]` | Model built with N equipment items. Shows ID@locLevel/side. |
| `INSERT-START count=N items=[...]` | Insert phase starting (sorted by LocLevel). |
| `BOX-ACTION action=INSERT/TRANSLATE/DELETE-OLD/SKIP-BACKLAYER` | Equipment shape action during insert. |
| `TERM-ACTION action=TRANSLATE/DELETE-OLD` | Terminal shape action during insert. |
| `WIRE-INS ... fromValid=T/F toValid=T/F show=T/F` | Wire placement decision. False fromValid/toValid = terminal not found in insertedTags. |
| `CORE-INSERT core=X term=Y side=Z termConnSide=W` | Core connector placed. `side` = cable side, `termConnSide` = terminal's connectivity. |
| `CABLE-INS ... -> ALREADY-INSERTED/INSERT/NOT-VISIBLE` | Cable shape processing. |
| `STRIP-Y` | Strip terminal Y calculation (overflow, sheetChanged, srcY). |
| `CORE-Y` | TryResolveConnectedCoreY resolution for devices. |

### Log Analysis Commands (PowerShell)
```powershell
# Extract key actions
Select-String -Path "D:\HVE\ts-diag.log" -Pattern "MODEL-DONE|INSERT-START|BOX-ACTION|TERM-ACTION|WIRE-INS|CORE-INSERT" | ForEach-Object { $_.LineNumber.ToString().PadLeft(4) + " " + $_.Line }

# Find creation vs update (separate by timestamp gap)
Select-String -Path "D:\HVE\ts-diag.log" -Pattern "MODEL-DONE" | Select-Object LineNumber, Line

# Check what's NOT placed
Select-String -Path "D:\HVE\ts-diag.log" -Pattern "fromValid=False|toValid=False|NO-START-POINT"
```

---

## Common Bug Patterns & Fixes

### 1. Wire not placed after update (fromValid=False)
**Symptom**: `WIRE-INS ... fromValid=False toValid=False show=False`
**Root cause**: Terminal only exists at LOC-1+ (parent equipment removed from model). Wire inserter checks plain ID but insertedTags only has composite key.
**Fix**: Wire/Link/LoopWire inserters must use `IsTerminalInserted()` which checks composite key based on terminal's `ConnectivitySide` and parent's `LocLevel`.

### 2. Ghost shapes persist after update
**Symptom**: Shapes at old positions remain after equipment removed from model.
**Root cause**: Same LinkedId exists at multiple LOC levels/sides. Plain ID in insertedTags keeps ALL shapes alive.
**Fix**: Use per-shape metadata (`"LocLevel-Side"`) + composite keys in insertedTags. UpdateDrawing constructs composite key from metadata to decide keep/delete.

### 3. Wrong shape targeted during translate
**Symptom**: Shape at LOC-1 translated instead of LOC-2 (or vice versa). Ghost shape remains.
**Root cause**: `IsShapeFoundOnDrawing` returns first match for same LinkedId without distinguishing LOC levels.
**Fix**: Include LocLevel in metadata (e.g., `"1-Right"` vs `"2-Right"`). `IsShapeFoundOnDrawing` matches by exact metadata value.

### 4. Core shapes from removed equipment persist
**Symptom**: Core connector lines remain at old Y positions after JB removed.
**Root cause**: Same core ID placed at multiple equipment contexts. Plain core ID in insertedTags protects all shapes.
**Fix**: Core composite key = `"coreId|cableSide-connContext"`. Each core shape tagged with `"{cableSide}-{connContext}"` metadata. Different contexts get unique keys.

### 5. Cross-group wire contamination
**Symptom**: Wires from Group1 appear connected to Group2's equipment.
**Root cause**: `SourceInternalWireTerminalIds` not filtering correctly.
**Fix**: Ensure each connected object has properly scoped `SourceInternalWireTerminalIds` from its specific group.

### 6. Connected object at wrong Y
**Symptom**: Equipment placed at incorrect vertical position.
**Root cause**: `TryGetStartPoint` finding wrong cable/wire endpoint.
**Fix**: Check that cable is matched by ID (not enclosure), and that source terminal Y (not target) is used.

### 7. Duplicate terminal shapes (both-content scenario)
**Symptom**: Same terminal has multiple shapes, cable attaches to wrong one.
**Root cause**: Terminal rendered at LOC-0 (neutral) AND as connected variant at LOC-1+.
**Fix**: `crossGroupLoc0Driver` guard skips connected placement when target is content-driver at different group. Or: mark connected-variant terminals as `IsTerminalAsConnectionPoint` to suppress symbol.

---

## Testing

### Running Tests
```powershell
cd d:\Git\dabacon-products\Engineering\Modules\EI\Source
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

## Drawing Update Trigger (IsDrawingUpdateRequired)

### LOC Change Detection
When user changes Left/Right LOC values via the Drawing Content Assigner UI, the drawing must be regenerated on next open/activate.

**Mechanism**: Snapshot comparison in `CanvasEventManager.IsDrawingUpdateRequired` → `TerminationTemplateDrawing` case:
- `LeftLevelOfConnectivity` / `RightLevelOfConnectivity` = current user-set values (in `drawing.Metadata.ShortStrings`)
- `GeneratedLeftLevelOfConnectivity` / `GeneratedRightLevelOfConnectivity` = snapshot stored at last generation

**Helper**: `IsLevelOfConnectivityChanged(drawingMetaData)` — static method in CanvasEventManager.cs

**Files**:
- `Helper/MetaDataHelper.cs`: Constants `GeneratedLeftLevelOfConnectivity`, `GeneratedRightLevelOfConnectivity`
- `TerminationDrawing/Controller/TerminationDrawingController.cs`: `AddMetaDataToDrawing` stores snapshot using `UpdateMetadata`
- `SGCClient/CanvasEventManager.cs`: `IsLevelOfConnectivityChanged` + insertion in TerminationTemplateDrawing case

**Backward compat**: If no snapshot exists (pre-feature drawings), check returns false. Snapshot stored on next generation.

---

## MetaDataHelper API Rules

| Method | Behavior | Use When |
|--------|----------|----------|
| `AddMetadata(key, value, drawing)` | Write-once: NO-OP if key already exists | First-time static metadata (template ID, tag ID, class URIs) |
| `UpdateMetadata(key, value, drawing)` | Remove + Add: always overwrites | Mutable metadata that changes across generations (LOC snapshot, timestamps) |

**CRITICAL RULE**: Any metadata that must be refreshed on subsequent generations MUST use `UpdateMetadata`. Using `AddMetadata` for mutable state causes:
- Stale snapshot → infinite update loop (trigger fires every activate)
- Or missed changes (snapshot never updates to reflect new value)

---

## Core Connector Update (existsInBoth)

### Problem: Cores Not Inserted After Wire Re-Addition (Update 2)
**Scenario**: Create drawing (8 items) → Remove wires (update 1, 4 items) → Add wires back (update 2, 8 items restored). Terminals at restored LOC levels are inserted correctly, but cores are NOT.

**Root Cause**: In `CoreConnectorManager.InsertCanvasCoreConnector`, the `existsInBoth` check uses `(coreId, terminalId)` matching WITHOUT LOC-level context. When the same core connects to the same terminal at multiple LOC levels (e.g., LOC-1 and LOC-2), the check incorrectly triggers for the LOC level whose shape was deleted during update 1.

The old code:
1. `existsInBoth = true` → adds composite key to `insertedTags`
2. Searches for shape with matching metadata → NOT FOUND (shape was deleted in update 1)
3. Returns unconditionally → core gets no shape, never inserted

**Fix**: Only `return` (skip) when shape is actually found with matching metadata. When shape NOT found, fall through to normal `IsShapeFoundOnDrawing` → `InsertNewCoreConnector` path:
```csharp
if (existsInBoth)
{
    var (coreKey, coreMeta) = GetCoreInsertKeyAndMeta(coreData);
    // search for shape with matching metadata...
    if (coreData.Shape != null)
    {
        insertedTags.Add(coreKey);
        return;  // Shape found at correct LOC — preserve
    }
    // Shape NOT found: fall through to normal insertion
    // (same core+terminal at different LOC matched incorrectly)
}
```

**Key Insight**: `existsInBoth` only means the (coreId, terminalId) pair exists in both the existing drawing map AND the actual model map. It does NOT mean the specific LOC-level shape exists. The metadata filter narrows to the exact LOC context.

---

## Codebase Location

```
https://dev.azure.com/AVEVA-VSTS/Dabacon%20Products/_git/dabacon-products?path=/Engineering/Modules/EI/Source
```

Default local clone path (override with `codebasePath` input):
```
d:\Git\dabacon-products\Engineering\Modules\EI\Source
```

Source tree within that root:
```
Presentation\Aveva.EI.CanvasDrawings\
├── EquipmentInserter.cs                               # Shape insert/update/delete + insertedTags
├── Helper\MetaDataHelper.cs                           # Metadata key constants
├── Helper\TsDiag.cs                                   # Diagnostic logging → D:\HVE\ts-diag.log
├── SGCClient\CanvasEventManager.cs                    # IsDrawingUpdateRequired + LOC change detection
└── TerminationDrawing\
    ├── Controller\TerminationDrawingGenerationWorkflow.cs   # Pipeline orchestration, UpdateDrawing()
    ├── Controller\TerminationDrawingController.cs           # AddMetaDataToDrawing (LOC snapshot)
    ├── Model Builder\TerminationDrawingModelBuilder.cs      # LOC model: grouping, placement, dedup
    ├── Model\CanvasEquipmentData.cs                         # Equipment model: terminals, cables, strips
    ├── Model\CanvasTerminalData.cs                          # Terminal model: position, connectivity side
    ├── Model\CanvasCoreData.cs                              # Core model: ModelPoints, ConnCanvasTerminalData
    ├── Inserter\TerminationDrawingInserter.cs               # Sorts by LocLevel, calls InsertAllCanvasEquipmentData
    ├── Inserter\WireConnectorInserter.cs                    # Wire placement + IsTerminalInserted validation
    ├── Inserter\LinkConnectorInserter.cs                    # Link connector + terminal validation
    ├── Inserter\LoopWireConnectorInserter.cs                # Loop wire + terminal validation
    ├── Manager\CoreConnectorManager.cs                      # Core connector insert/update, existsInBoth logic
    └── Manager\CableShapeManager.cs                         # Cable shape insert, neighbor lookup
```

Test project:
```
Tests\Aveva.EI.CanvasDrawings.Test\
```

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
