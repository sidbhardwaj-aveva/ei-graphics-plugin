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
| `Presentation/Aveva.EI.CanvasDrawings/Helper/TsDiag.cs` | Diagnostic logging. Output path is defined at the top of this file, so it varies per environment. |

### Settings & Configuration Surface

The files above generate the drawing. The files below define what the drawing is allowed to look
like. A story that asks whether a specific termination-diagram setting exists, or where a control
on the settings dialog lives, is almost always about this surface, not the pipeline. Search only
the generator tree and these files are missed. Story 3774939 read all ten of them and none were
listed above.

| File | Purpose |
|------|---------|
| `Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/TerminationDrawingSettings.cs` | Runtime settings model the pipeline consumes: cable, core, wire and link lengths, spacing, connector labels, endpoint formulas, orientation. |
| `Presentation/Aveva.EI.Ui/TerminationDrawingSettings/ViewModels/TerminationDrawingSettingsViewModel.cs` | View model for the per-drawing termination settings dialog. Binds the runtime model to the WPF view. |
| `Presentation/Aveva.EI.Ui/TerminationDrawingSettings/Views/TerminationDrawingSettings.xaml` | Per-drawing settings view. First place to check when the user sees a control on screen and the pipeline files do not mention it. |
| `Presentation/Aveva.EI.Ui/AdvancedDrawingsSettings/Views/TerminationDrawingType/TerminationDrawingTypeSettings.xaml` | Template-level termination drawing settings: labels, symbol variants, minimum connector spacing. |
| `Presentation/Aveva.EI.Ui/AdvancedDrawingsSettings/Views/TerminationDrawingType/TerminationgDrawingCableSettings.xaml` | Template-level cable settings. The `Terminationg` typo is in the shipping file name and is not a mistake in this table. |
| `Presentation/Aveva.EI.Ui/AdvancedDrawingsSettings/Views/TerminationDrawingType/TerminationDrawingWireSettings.xaml` | Template-level wire settings. |
| `Presentation/Aveva.EI.Ui/AdvancedDrawingsSettings/Views/TerminationDrawingType/TerminationDrawingCoreSettings.xaml` | Template-level core settings. |
| `Presentation/Aveva.EI.Ui/AdvancedDrawingsSettings/Views/TerminationDrawingType/TerminationDrawingLinkSettings.xaml` | Template-level link settings. |
| `Domain/Aveva.EI.DomainServices/AdvancedSettingsService.cs` | Domain service that owns the setting definitions the template views bind against, including vertical spacing and connector length. Read this before answering "does this setting exist?". |
| `Tests/Aveva.EI.CanvasDrawings.Test/TerminationDrawing/TerminationDrawingSettingsTest.cs` | Focused tests for the settings model. A useful template when adding a new setting. |

Some settings named in stories are not in any of these files. Text height on a tstrip header, a
terminal width or an IO module width is controlled by the symbol the drawing uses, not by a
setting field. If a control cannot be found on this surface and does not have a formula in the
runtime model, the answer is usually "symbol-controlled".

---

## Phase Ownership

Three different phases can produce a wrong-looking drawing, and each has its own owner. Decide the
phase before you decide the file. Editing a later phase to correct an earlier one leaves the bug
in place and adds a second one.

| Phase | What it decides | Owning code |
|-------|-----------------|-------------|
| Model ordering | The sequence equipment appears in, per mounting rail | `TerminationDrawingModelBuilder.OrderSequence()`, `ApplyPlateOrdering()`, `GetDwgPlateCollectionOrder()` |
| Group resolution | Which equipment is gathered into a group, and what counts as a child | `ConnectedEquipmentGroupResolver.GetGroupableContainedEquipment()`, `ConnectedEquipmentGroupResolver.GetAllChildren()` |
| Placement | Where a resolved group lands on the sheet | `PlaceLoc0Groups()`, `CanvasEquipmentData` |
| Post-placement adjustment | Nudging what is already placed so it does not overlap | `LayoutAdjustmentService.AdjustConnectedDeviceVerticalOverlaps()` |
| Insertion | Turning the model into shapes on the drawing | `TerminationDrawingInserter`, `EquipmentInserter` |

### The ordering methods

- `OrderSequence()` decides the domain order for a rail: strip, barrier, instrument, module. It is
  the only place the domain sequence is expressed. A change here changes every drawing.
- `ApplyPlateOrdering()` applies the mounting-plate order on top of that. The trap is partitioning:
  concatenating plate-ordered items ahead of unplated ones re-sorts the whole rail, because the
  unplated items are pushed to the end regardless of their domain order.
- `GetDwgPlateCollectionOrder()` supplies the plate order those two consume. An empty or partial
  plate list here is not an error; it means the rail is ordered by domain sequence alone.

### The resolver methods

- `GetGroupableContainedEquipment()` answers what can be gathered into one group.
- `GetAllChildren()` walks the containment tree beneath an item. It is the broader abstraction, and
  it is shared. A change here affects grouping, placement and insertion at once, so it is almost
  never the right place to fix a symptom seen on one rail.

### ContainedEquipment and CanHavePartEquipment

`ContainedEquipment` is what an enclosure actually holds right now. `CanHavePartEquipment` is
whether a thing is allowed to hold parts at all. The first is data, the second is a capability
flag. A rail, a compartment and a plate can each be true for `CanHavePartEquipment` while holding
different `ContainedEquipment`, so nesting is normal. Any ordering rule that only reads the direct
`ContainedEquipment` of the enclosure silently ignores nested rail and compartment contents.

### Which owner to inspect first

| Symptom | First owner to inspect |
|---------|------------------------|
| Wrong `MODEL-DONE` order | Model builder ordering |
| Correct `MODEL-DONE`, wrong position | `LayoutAdjustmentService` / `CanvasEquipmentData` |
| Correct model, missing shape | Inserter / `EquipmentInserter` |
| Update-only stale shape | `UpdateDrawing` / metadata |
| Wrong connector visibility | Wire, core and link inserters |
| Duplicate connected equipment | Resolver and deduplication |

### The one-phase-later rule

When the log shows `MODEL-DONE` and `INSERT-START` already carrying the expected order, the model
ordering code is correct and is not the place to edit. Move one phase later and inspect placement
and post-placement adjustment instead.

When there is no log, but Step 1b history triage identifies an ordering change, a model-builder fix
may be proposed. Label runtime confirmation as missing when you do.

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

## Codebase Location

The agent runs from the root of the local `dabacon-products` clone at
`Engineering/Modules/EI/Source`. Every path below is relative to that root, so no absolute
path or remote URL is needed to open or edit the code.

Source tree:
```
Presentation\Aveva.EI.CanvasDrawings\
├── EquipmentInserter.cs                               # Shape insert/update/delete + insertedTags
├── Helper\MetaDataHelper.cs                           # Metadata key constants
├── Helper\TsDiag.cs                                   # Diagnostic logging (output path set in this file, varies per environment)
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
