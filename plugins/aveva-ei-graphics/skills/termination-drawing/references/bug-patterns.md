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

### 8. Equipment in the wrong mounting-rail order
**Symptom**: Every item is on the drawing, at the right rail, in the wrong sequence. A reported
case expected `TS-1, B-1, --134, IOM-1` and produced `--134, TS-1, B-1, IOM-1`, so one item moved
to the front of the rail and the rest kept their relative order.
**Check**: This is a regression until proven otherwise. Run the Step 1b history triage over
`OrderSequence` and compare the previous implementation with the current one. The old code read a
horizontal sequence and then a vertical sequence; the current code calls `ApplyPlateOrdering()`.
Read both before forming a hypothesis.
**Typical cause**: A new ordering policy partitions the rail, putting the items that appear in the
plate order ahead of the items that do not, instead of applying the domain sequence across all of
them. A single unplated item then jumps the queue, or falls to the end, depending on which side of
the concatenation it lands.
**Caution**: Do not simply delete the plate ordering. It may be intended for the direct children
of an enclosure, with the domain sequence governing nested rail and compartment contents. Removing
it fixes the reported rail and breaks every drawing that relies on a configured plate order. Find
out which collection each rule is meant to govern before changing either.
**A fix must hold for all seven cases**:
1. every item unplated;
2. every item plated;
3. a mix of plated and unplated items on one rail;
4. items nested inside a rail or a compartment rather than directly in the enclosure;
5. the strip, barrier, instrument and module sequence, in that order;
6. the same plate named twice in the plate order;
7. plate data that is missing or empty.

---
