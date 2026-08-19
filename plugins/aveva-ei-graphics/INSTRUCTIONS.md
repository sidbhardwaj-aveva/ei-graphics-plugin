# EI Graphics Plugin — Usage and Development Instructions

## Running the Workflow

The lifecycle is owned by the `ei-graphics-workflow` skill. Users enter through the thin
`EI Graphics` agent and never call a script directly.

```text
user -> ei-graphics.agent.md -> ei-graphics-workflow -> skills -> gates
     -> .copilottracking/ei-graphics/<story-id>/ -> Git / PR
```

### Prerequisites

- PowerShell 7+ (`pwsh`)
- `git` on `PATH`, with the workspace inside a git work tree
- Azure CLI (`az`) installed and authenticated (`az login`) for ADO intake
- The `aveva-rnd` and `aveva-core` plugins installed — the workflow reuses their skills and
  fails closed if either is missing

### Preflight

Run before starting a story to confirm the environment and every declared dependency resolve.

```powershell
& './plugins/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/Validate-EiWorkflowPrerequisites.ps1' `
    -RepositoryRoot (Get-Location) `
    -Phase A `
    -Json
```

| Parameter | Purpose |
|-----------|---------|
| `RepositoryRoot` | Repository to validate; git work-tree checks run against it |
| `Phase` | `A`–`E`. Later phases require more capabilities and enforce more checks |
| `PluginSearchRoot` | Extra plugin install roots for non-standard host layouts |
| `NoDefaultSearchRoots` | Restrict discovery to the roots you pass |
| `Json` | Emit the structured validation result |

Default search roots are the dev checkout `plugins/`, `~/.copilot/installed-plugins/*`, and
`~/.vscode/agent-plugins/*/*/*/plugins`. A missing required plugin returns
`EIWF-DEPENDENCY-MISSING` with a marketplace install instruction.

### Workflow state

State lives in `.copilottracking/ei-graphics/<story-id>/`, which is git-ignored and never reaches
a commit or PR. `ei-workflow-state` owns it.

```powershell
$stateScripts = './plugins/aveva-ei-graphics/skills/ei-workflow-state/scripts'

# Start or resume a run
& "$stateScripts/Initialize-EiWorkflowState.ps1" -StoryId '468178' -WorkflowPath IMPLEMENT -Json

# Confirm the run is usable before continuing
& "$stateScripts/Validate-EiWorkflowState.ps1" -StateDir '.copilottracking/ei-graphics/468178' -Json
```

Re-running `Initialize-EiWorkflowState.ps1` resumes rather than overwrites. Use `-Force` only to
archive unusable state; it writes a timestamped `.bak.json` first.

### Result contract

Every run returns a schema-validated contract, persisted as `workflow-result.json`.

```powershell
& './plugins/aveva-ei-graphics/skills/ei-graphics-workflow/scripts/New-EiWorkflowResult.ps1' `
    -StateDir '.copilottracking/ei-graphics/468178' `
    -Summary 'Phase A skeleton initialised.' `
    -NextAction 'Wait for Phase B.' `
    -Status blocked `
    -Json
```

| Status | Meaning |
|--------|---------|
| `completed` | The requested path finished and every gate passed |
| `awaiting-approval` | A human decision is required before the run continues |
| `blocked` | A gate returned BLOCK; `blocks[]` carries the code and remediation |
| `failed` | The run could not proceed and is not resumable as-is |

The script refuses to return a contract while the run is still `in-progress` unless `-Status` is
supplied explicitly, so an unfinished run can never be reported as a success.

### Fail-closed behaviour

- Missing evidence is never treated as a pass. A stage completes only on a `pass` gate.
- Unimplemented lifecycle stages BLOCK when reached; they are not skipped.
- Artifacts reserved for a later phase cannot be written (`EIWF-SCHEMA-PENDING`).
- Correction attempts are capped at 3.
- Story ids are validated as safe directory names, so state paths cannot escape the tracking root.

## Running Tests

```powershell
# Full EI suite (Pester 5+ required)
Invoke-Pester -Path './tests/aveva-ei-graphics' -Tag 'Unit'

# Single agent/skill
Invoke-Pester -Path './tests/aveva-ei-graphics/agents/ei-ado-ingest'
Invoke-Pester -Path './tests/aveva-ei-graphics/skills/ei-workflow-state'
```

## Commit Convention

All commits follow the two-part split:

1. `feat(aveva-ei-graphics): <description>` — code and tests
2. `docs(aveva-ei-graphics): <description>` — spec/planning updates

Use `fix(aveva-ei-graphics): ...` for bugfixes. Use `git -c gc.auto=0 commit` to avoid gc prompts on OneDrive workspaces.

## Change Log

### 2026-08-18

- refactor(aveva-ei-graphics)!: remove superseded ei-graphics-workflow agent, script, and tests
- test(aveva-ei-graphics): migrate EI suites to Pester 5 assertion syntax
- docs(aveva-ei-graphics): rewrite instructions for the workflow-first architecture
- feat(aveva-ei-graphics): add thin ei-graphics agent and ei-graphics-workflow lifecycle skill
- feat(aveva-ei-graphics): add ei-workflow-state store, schemas, and workflow result contract

### 2026-08-11

- fix(aveva-ei-graphics): resolve git-diff paths to absolute using repo toplevel
- feat(aveva-ei-graphics): add usage and development instructions file
- fix(aveva-ei-graphics): guard against non-absolute URIs in ado cli intake
- docs(aveva-ei-graphics): record git-diff auto-discovery for orchestrator
- feat(aveva-ei-graphics): add git-diff auto-discovery for changed files in orchestrator
- docs(aveva-ei-graphics): record adapted agent runtimes and orchestrator wiring
- feat(aveva-ei-graphics): add adapted agent runtimes and wire orchestrator

### 2026-08-10

- docs(aveva-ei-graphics): record cli intake skill adoption
- feat(aveva-ei-graphics): add ei azure devops cli intake skill
- docs(aveva-ei-graphics): record url-driven ado intake adaptation
- feat(aveva-ei-graphics): add url-driven ado intake for bug reproducer
- docs(aveva-ei-graphics): mark live ado calibration complete
- docs(aveva-ei-graphics): record rnd-style ado adaptation
- feat(aveva-ei-graphics): adopt rnd-style ado request handling
- docs(aveva-ei-graphics): record ado auth redirect calibration
- feat(aveva-ei-graphics): handle ado auth redirect fallback
- docs(aveva-ei-graphics): record live calibration prerequisites
- docs(aveva-ei-graphics): capture ado fallback calibration pass
- feat(aveva-ei-graphics): calibrate ado fallback confidence and transient tagging
- docs(aveva-ei-graphics): record ado hardening progress
- feat(aveva-ei-graphics): harden ado retrieval fallback behavior
- docs(aveva-ei-graphics): lock hardening-before-adaptation sequence
- docs(aveva-ei-graphics): update plan for workflow runtime slice
- feat(aveva-ei-graphics): add deterministic workflow orchestrator runtime
- docs(aveva-ei-graphics): define rnd-reference reuse policy
- docs(aveva-ei-graphics): record workflow wiring progress
- feat(aveva-ei-graphics): wire workflow agent evidence packaging
- docs(aveva-ei-graphics): update plan for ado and reviewer slices
- feat(aveva-ei-graphics): add ado retrieval and deterministic pr reviewer slice
- docs(aveva-ei-graphics): update phase 1 status for test scaffolder
- feat(aveva-ei-graphics): add deterministic ei-test-scaffolder slice
- feat(tools): add EI graphics spec sync gate and refresh planning docs
- feat(aveva-ei-graphics): implement deterministic phase-1 script slices
- docs(aveva-ei-graphics): align plan with phase 1 capability map
- docs(aveva-ei-graphics): add workflow analysis and support docs
- feat(aveva-ei-graphics): replace placeholder contracts with workflow capabilities
- docs(aveva-ei-graphics): add planning and reconcile status
- feat(aveva-ei-graphics): scaffold plugin and register marketplace
