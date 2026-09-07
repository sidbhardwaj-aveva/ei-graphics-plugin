---
name: ei-graphics-doctor
description: "Diagnose EI Graphics plugin readiness when setup, commands, Azure DevOps authentication, artifacts, or Git configuration may be broken. Use before the first story in a repository or when plugin setup is uncertain."
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - read
  - powershell
---

# EI Graphics Doctor

Run the bundled read-only diagnostic. Do not install tools, authenticate, change configuration, or repair files.

## Diagnostic Workflow

1. From the repository root, run:

   ```powershell
   pwsh -NoProfile -File ./plugins/aveva-ei-graphics/skills/ei-graphics-doctor/scripts/Invoke-EiGraphicsDoctor.ps1
   ```

2. Let all six checks finish:
   - Check 1: PowerShell Runtime (EIGD001)
   - Check 2: Azure DevOps CLI and Authentication (EIGD002)
   - Check 3: Plugin File Structure (EIGD003)
   - Check 4: Skill Registry and Schemas (EIGD004)
   - Check 5: Session Artifacts (EIGD005)
   - Check 6: Git Configuration (EIGD006)

3. Report the overall status, each failed or flagged check, and the exact required actions emitted by the script. Do not diagnose beyond the returned evidence.

## Status

- `Ready`: all critical checks passed.
- `ManualReview`: the plugin can run, but the reported warning needs review.
- `Blocked`: stop plugin work until every required action is resolved.

Exit code `0` means `pass`. Exit code `1` means `blocked` or `needs-manual-review`.

## JSON Output

Use JSON only when structured output is needed:

```powershell
pwsh -NoProfile -File ./plugins/aveva-ei-graphics/skills/ei-graphics-doctor/scripts/Invoke-EiGraphicsDoctor.ps1 -Json
```

Read `status`, `violations`, `reviewFlags`, `requiredActions`, and `checkDetails`. Preserve error codes and messages when reporting findings.

## Gotchas

- Run from the repository root unless `-Root` is supplied explicitly.
- The doctor is diagnostic only. Never execute its suggested repair commands without the user's approval.
- Do not treat skipped checks or missing evidence as a pass.
