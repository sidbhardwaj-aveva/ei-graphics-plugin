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
