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
