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

# Electrical and Instrumentation (EI) Graphics Doctor

Run the bundled read-only diagnostic. Do not install tools, authenticate, change configuration, or repair files.

Before a user's first story, ask once whether to run it. Save yes with `-RememberDecision`.
Save no with `-DeclineAndRemember`, which runs no checks. The decision file is under the user's
local application data folder. Later stories read that file and skip the question and doctor.

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

- `-Root` is the target repository a story is worked in (defaults to the current directory).
  It is never the plugin's own install location. The plugin's files are always resolved from
  where this script is installed, because the target repository does not contain a copy of
  the plugin.
- `-Root` does not have to be the repository's top level. The script asks git for the real
  top level and uses that instead, so a subfolder several levels deep still resolves
  correctly. Read `targetRoot` in `-Json` output to see the path actually checked.
- The doctor is diagnostic only. Never execute its suggested repair commands without the user's approval.
- Normal direct runs do not save a decision. The two remember switches are explicit.
- Do not treat skipped checks or missing evidence as a pass.
