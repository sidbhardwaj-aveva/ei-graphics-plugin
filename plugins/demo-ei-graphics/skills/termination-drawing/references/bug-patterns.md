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
