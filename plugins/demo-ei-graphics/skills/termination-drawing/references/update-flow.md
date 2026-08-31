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
