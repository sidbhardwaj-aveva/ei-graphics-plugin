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
Run these against the log path supplied with the problem report:

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

---
