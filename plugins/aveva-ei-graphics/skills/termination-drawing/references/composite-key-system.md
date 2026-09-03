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
