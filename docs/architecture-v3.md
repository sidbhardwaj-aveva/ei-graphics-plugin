# EI Graphics Plugin — Revised Target Architecture (v3)

## References used
- agentskills.io/specification — progressive disclosure, <500 lines / <5000 tokens per SKILL.md
- agentskills.io/skill-creation/best-practices — coherent units, gotchas, validation loops
- agentskills.io/skill-creation/using-scripts — structured output, --help, exit codes, idempotent
- agentskills.io/skill-creation/evaluating-skills — evals framework for testing skill quality

## TL;DR

Strip the plugin to: ADO intake, story understanding (new), domain skills, layer guard, and a session logger. The agent handles all reasoning. aveva-rnd handles code review, commit, and PR. Domain skills (like termination-drawing) ARE the scope knowledge — no resolver pipeline needed. Human approves scope in conversation; the approval is persisted for drift checking.

---

## Target Architecture Diagram

```
ADO story URL/ID
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ ADO INTAKE (deterministic script)                               │
│ • Retrieve title, description, acceptance criteria, comments    │
│ • Download embedded images                                      │
│ • Persist ado.json                                              │
│ • Append to session log                                         │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ AGENT: READ + UNDERSTAND (semantic reasoning)                   │
│ • Read complete ado.json + downloaded attachments                │
│ • Examine domain skill catalogue (script lists available skills)│
│ • Read full SKILL.md of shortlisted domains                     │
│ • Draft understanding + propose domains + assess complexity     │
│ • Log reasoning to session                                      │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ HUMAN CHECKPOINT 1: Understanding + Domain                      │
│                                                                 │
│ Agent presents:                                                 │
│   • What I understood                                           │
│   • Expected outcome                                            │
│   • Important requirements                                      │
│   • Image understanding (visible/inferred/undetermined)         │
│   • Comment understanding (superseding info flagged)            │
│   • Proposed domain skill(s) + reasoning                        │
│   • Complexity assessment (small bug / large change)            │
│   • Uncertainty / ambiguities                                   │
│                                                                 │
│ Human can: confirm, correct, add/remove domain, provide context │
│                                                                 │
│ If no domain skill matches → agent tells the developer:         │
│   "No domain skill covers this area. I can still proceed        │
│    but will be less precise. You can give me context or stop."  │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ PERSIST: story-understanding.json (deterministic write)          │
│ • Confirmed understanding, domains, corrections, complexity     │
│ • Hash of ado.json it was derived from                          │
│ • Human reviewer identity + timestamp                           │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌──── BRANCH: complexity assessment ────────────────────────────────┐
│                                                                    │
│  SMALL BUG (1-3 files, single method, clear fix from skill):      │
│    Agent says: "This looks like a small fix in <file>.<method>.   │
│    I can implement directly. Want me to proceed?"                  │
│    → Human confirms → agent implements → layer guard → commit     │
│                                                                    │
│  LARGE CHANGE (multi-file, architecture, unclear scope):          │
│    ▼                                                               │
└────────────────────────────────────────────────────────────────────┘
  │ (large change path)
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ AGENT: SCOPE PROPOSAL (semantic reasoning)                      │
│ • Read domain skill Key Files                                   │
│ • Read actual source files to confirm relevance                 │
│ • Propose: files to change, why, what changes in each           │
│ • Present as human-readable plan                                │
│ • Log reasoning to session                                      │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ HUMAN CHECKPOINT 2: Scope / Plan approval                       │
│                                                                 │
│ Agent presents:                                                 │
│   ### Implementation Plan                                       │
│   **Files I'll change:**                                        │
│   1. `File.cs` → modify `MethodX` because ...                  │
│   2. `File2.cs` → add handling for ...                          │
│   **Tests I'll verify:**                                        │
│   - `dotnet test --filter "ClassName"`                          │
│   **New tests needed?**                                         │
│   - "Existing tests cover this" OR                              │
│   - "No coverage for X — should I add a test for ...?"         │
│   **Risks:**                                                    │
│   - ...                                                         │
│                                                                 │
│ Human can: approve, narrow, expand, reject, request tests       │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ PERSIST: approved-files.json (deterministic write)               │
│ • Approved file list + change intent per file                   │
│ • Hash for later drift detection                                │
│ • Human approver + timestamp                                    │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ AGENT: IMPLEMENT (semantic reasoning + tool use)                 │
│ • Check skill's Bug Patterns — if one matches, use its fix      │
│ • Read skill's Key Files first — they are the entry points      │
│ • Only search beyond Key Files when skill doesn't cover it      │
│ • Make changes guided by domain skill critical rules             │
│ • Run tests (from skill's test commands)                        │
│ • Log all actions to session                                    │
│ • Log any file read NOT in Key Files (skill coverage gap)       │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ PRE-COMMIT VALIDATION (deterministic)                            │
│ • Layer guard: run on changed files                             │
│ • Drift check: compare actual changes vs approved-files.json    │
│ • If drift detected → inform developer, ask to approve addition │
│ • If layer violation → block, explain                           │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ DELEGATE TO aveva-rnd                                            │
│ • code-review → agent reviews its own changes                   │
│ • git-commit → conventional commit                              │
│ • create-pr → with title, description, linked work item         │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│ SESSION SUMMARY (deterministic script)                           │
│ • Render .ei-session-logs/<storyId>/session-summary.md          │
│ • From the progressive JSON log                                 │
│ • Timing, cost, decisions, human interactions, outcomes         │
└─────────────────────────────────────────────────────────────────┘
```

---

## What the EI plugin owns (final list)

| Component | Type | Purpose |
|-----------|------|---------|
| `ei-azure-devops-cli-intake` | Skill + scripts | ADO retrieval with comments, images, tri-state |
| `ei-graphics.agent.md` | Agent | Conversational orchestrator |
| `termination-drawing` | Domain skill (SKILL.md only) | Domain knowledge pack |
| *(future domain skills)* | Domain skill (SKILL.md only) | One per EI area as needed |
| `Invoke-EiLayerGuard.ps1` | Validation script | Architecture rule enforcement |
| `Get-EiDomainSkillCatalog.ps1` | Discovery script | Lists available skills for the agent |
| `Write-EiArtifact.ps1` | Persistence script | Schema-validated JSON write |
| `Test-EiScopeDrift.ps1` | Validation script | Compares actual changes vs approved list |
| `Write-EiSessionEntry.ps1` | Logging script | Appends to progressive session JSON |
| `Export-EiSessionSummary.ps1` | Reporting script | Renders markdown from session JSON |

**Total: ~6 scripts + domain SKILL.md files + agent definition.**
Compare to current: ~35 scripts across 8 skills.

---

## Spec compliance (agentskills.io)

### Size targets
- Agent.md: ~60 lines, ~1500 tokens (currently 170 → cut by 65%)
- termination-drawing/SKILL.md: ~120 lines, ~2500 tokens (currently ~490 → split to references/)
- ei-azure-devops-cli-intake/SKILL.md: ~80 lines (usage reference for scripts)
- No other skills needed

### Progressive disclosure (spec §Progressive disclosure)
1. **Metadata (~100 tokens):** name + description in frontmatter — loaded at startup for all skills
2. **Instructions (<5000 tokens):** SKILL.md body — loaded when skill is activated
3. **Resources (as needed):** references/, scripts/ — loaded only when required

### Script design (spec: using-scripts)
- Structured JSON output (stdout), diagnostics to stderr
- --help with flags and examples
- Meaningful exit codes (0=success, 1=failure with reason)
- Idempotent where possible
- No interactive prompts

### Skill evaluation (manual, documented in README)
No automated eval framework. The feedback loop is:
1. Run agent on a real story
2. Read session-summary.md (reasoning trail, maintainer section)
3. Identify gaps (wrong pattern matched, missing files, wasted steps)
4. Fix SKILL.md or references/
5. Repeat

### Preflight (manual, documented in README)
No automated prerequisite validation. The README lists what must be true before invoking the agent:
- az CLI logged in with ADO access
- git working tree clean (or stashed)
- dotnet SDK available
- dabacon-products repo cloned at expected path
- VS Code with Copilot agent mode

Agent assumes environment is ready. If something fails, the error message is the diagnostic.
This avoids burning tokens on repeated setup checks every run.

---

## Lean agent.md (~60 lines, ~1500 tokens)

What stays (agent would get it wrong without):
- Don't re-fetch ADO data (agents waste calls)
- Don't narrate steps (agents do this by default)
- Direct output style (caveman-lite): no filler/pleasantries/hedging, lead with the answer not the process, no tool-call narration. Pattern: `[what happened] [what it means] [what's next]`. Normal prose for commits, PR descriptions, and docs — other humans read those. Drop terse mode for security warnings, irreversible actions, or when compression creates ambiguity.
- Don't invent domain IDs (agent must check registry)
- Comments supersede description (non-obvious)
- Session log every step (not natural agent behavior)
- Layer guard before commit (agent wouldn't know to do this)
- Complexity branching rules (when to show plan vs proceed)
- Skill-first file resolution (see below — agent would explore randomly without this)
- Surgical changes only: touch only what the fix requires. Don't improve adjacent code, comments, or formatting. Match existing style. Remove only imports/variables YOUR changes made unused.
- Verify before declaring done: every fix needs a test command run (from the skill) or a build check. "It looks correct" is not verification.
- Surface test gaps: after reading the source for the fix, check if the test project has tests for the affected method/class. If no test covers the changed code path, ask the human: "No existing test covers X — should I add one?"
- Do not edit until cause is understood: separate symptom from inferred cause. If no bug pattern matches and evidence is insufficient, say so — don't guess at a fix.
- Stop when done: once tests pass and layer guard clears, stop. No polish, no adjacent cleanup, no extra tests beyond what was agreed.

What's cut (agent already knows / obsolete):
- How to flatten PowerShell commands
- Lifecycle stages, gates, block codes
- Format-EiWorkflowSummary usage
- Exact domain-context script invocation
- Understanding template (specify content, not formatting)
- Implementation status section
- References to ei-graphics-workflow skill

---

## Skill-first file resolution (new agent.md rule)

The single biggest token waste is the agent running 10+ exploratory searches across a massive codebase when the domain skill already points to the exact file and method. The new agent.md must include:

```
## Implementation priority: skill-first, explore-second

1. Check the domain skill's **Bug Patterns** section. If a pattern matches the symptom,
   use its documented root cause, affected files, and fix directly. Do NOT search the codebase.
2. If no pattern matches, read the skill's **Key Files** table. Open those files first —
   they are the documented entry points for this domain.
3. Only use grep_search / semantic_search / file_search beyond the skill's documented files
   when the skill explicitly doesn't cover the scenario.
4. Every file you read that is NOT in the skill's Key Files table costs tokens and likely
   means the skill has a coverage gap — note it in the session log for skill improvement.
```

This rule closes the loop: session logs expose coverage gaps → maintainer reads session-summary.md → adds missing files/patterns to SKILL.md → next run stays inside the skill.

---

## termination-drawing — progressive disclosure split

### SKILL.md (~120 lines, ~2500 tokens)
- Frontmatter (name, description)
- When to Use (bullet list)
- Workflow (5 steps)
- Key Files table (abbreviated — top 9 files)
- References section (tells agent WHEN to load each file)
- Gotchas (6 critical rules the agent would violate without)
- Test commands
- Codebase location

### references/ (loaded on demand)
| File | ~Lines | Loaded when |
|------|--------|-------------|
| `bug-patterns.md` | 150 | Diagnosing a symptom |
| `composite-key-system.md` | 100 | insertedTags / LOC metadata issue |
| `log-analysis.md` | 60 | ts-diag.log provided |
| `architecture.md` | 120 | Full pipeline understanding needed |
| `update-flow.md` | 80 | Update trigger / IsDrawingUpdateRequired |

### evals/ — NOT included
Skill evaluation is manual. See README for the run→read→fix loop.
No evals.json, no fixtures, no automated grading.

---

## Artifacts persisted per run

Location: `.ei-session-logs/<storyId>/`

| File | Written by | Purpose |
|------|-----------|---------|
| `ado.json` | `Invoke-EiAdoIntakeStage.ps1` | Raw story data |
| `story-understanding.json` | `Write-EiArtifact.ps1` | Confirmed understanding + domains |
| `approved-files.json` | `Write-EiArtifact.ps1` | Human-approved scope with hash |
| `session.json` | `Write-EiSessionEntry.ps1` | Progressive execution log (agent appends) |
| `session-summary.md` | `Export-EiSessionSummary.ps1` | Human-readable summary |

---

## Session log design

### Progressive JSON (`session.json`)

Array of entries, appended by the agent after each significant step:

```jsonc
{
  "schemaVersion": "1.0.0",
  "storyId": "4965976",
  "startedAt": "2026-08-26T09:00:00Z",
  "agent": "ei-graphics",
  "entries": [
    {
      "timestamp": "2026-08-26T09:00:01Z",
      "phase": "ado-intake",
      "action": "retrieve-story",
      "reasoning": "Story URL provided, calling ADO CLI intake...",
      "outcome": "Retrieved: title, description, 3 comments, 2 images",
      "durationMs": 4200,
      "tokensUsed": null
    },
    {
      "timestamp": "2026-08-26T09:00:06Z",
      "phase": "understanding",
      "action": "read-story",
      "reasoning": "Reading ado.json. Title mentions 'core connector not inserted after update'. This matches bug pattern #5 in termination-drawing skill: 'Core shapes from removed equipment persist'. Comment 2 from dev clarifies this is specifically about the existsInBoth check.",
      "outcome": "Matched to termination-drawing domain, bug pattern #5 (existsInBoth)",
      "durationMs": 2100,
      "tokensUsed": 1847
    },
    {
      "timestamp": "2026-08-26T09:00:08Z",
      "phase": "understanding",
      "action": "select-domain",
      "reasoning": "Story mentions 'core connector', 'update scenario', 'insertedTags'. Termination-drawing skill documents CoreConnectorManager.cs and the existsInBoth flow. High confidence match.",
      "outcome": "Proposed domain: termination-drawing (confidence: high)",
      "durationMs": 800,
      "tokensUsed": 523
    },
    {
      "timestamp": "2026-08-26T09:00:09Z",
      "phase": "human-checkpoint",
      "action": "present-understanding",
      "reasoning": null,
      "outcome": "Presented understanding to human. Awaiting response.",
      "durationMs": 0,
      "tokensUsed": 0
    },
    {
      "timestamp": "2026-08-26T09:02:30Z",
      "phase": "human-checkpoint",
      "action": "human-response",
      "reasoning": null,
      "outcome": "Human confirmed understanding and domain. No corrections.",
      "humanInput": "yes, that's correct",
      "durationMs": 0,
      "tokensUsed": 0
    },
    {
      "timestamp": "2026-08-26T09:02:31Z",
      "phase": "complexity",
      "action": "assess",
      "reasoning": "Single file affected (CoreConnectorManager.cs), single method (InsertCanvasCoreConnector), bug pattern already documented with fix. This is a small bug.",
      "outcome": "Complexity: small. Proposing direct implementation.",
      "durationMs": 400,
      "tokensUsed": 312
    },
    {
      "timestamp": "2026-08-26T09:02:45Z",
      "phase": "implementation",
      "action": "read-source",
      "reasoning": "Reading CoreConnectorManager.cs to find the existsInBoth check...",
      "outcome": "Found existsInBoth block at line 187. Current code returns unconditionally when existsInBoth=true.",
      "durationMs": 1200,
      "tokensUsed": 3400,
      "filesRead": ["Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Manager/CoreConnectorManager.cs"]
    },
    {
      "timestamp": "2026-08-26T09:03:00Z",
      "phase": "implementation",
      "action": "apply-fix",
      "reasoning": "Per bug pattern #5 in the skill: only return when shape is actually found. Fall through to normal insertion when metadata doesn't match.",
      "outcome": "Modified InsertCanvasCoreConnector: added null check after metadata search",
      "durationMs": 2000,
      "tokensUsed": 1200,
      "filesModified": ["Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Manager/CoreConnectorManager.cs"]
    },
    {
      "timestamp": "2026-08-26T09:03:10Z",
      "phase": "validation",
      "action": "layer-guard",
      "reasoning": null,
      "outcome": "PASS. No architecture violations.",
      "durationMs": 300,
      "tokensUsed": 0,
      "scriptOutput": { "status": "pass", "violations": [] }
    },
    {
      "timestamp": "2026-08-26T09:03:15Z",
      "phase": "validation",
      "action": "run-tests",
      "reasoning": "Running targeted tests from skill: dotnet test --filter CoreConnectorManager",
      "outcome": "12/12 tests passing",
      "durationMs": 18000,
      "tokensUsed": 0
    },
    {
      "timestamp": "2026-08-26T09:03:35Z",
      "phase": "commit",
      "action": "delegate-rnd-commit",
      "reasoning": "Fix verified. Delegating to aveva-rnd:git-commit.",
      "outcome": "Committed: fix(termination-drawing): only skip core insertion when shape found with matching metadata",
      "durationMs": 1500,
      "tokensUsed": 400
    }
  ],
  "summary": {
    "completedAt": "2026-08-26T09:03:37Z",
    "totalDurationMs": 216000,
    "totalTokens": 7682,
    "filesModified": ["CoreConnectorManager.cs"],
    "testsRun": 12,
    "testsPassed": 12,
    "humanInteractions": 2,
    "outcome": "fixed",
    "domainSkillUsed": "termination-drawing",
    "bugPatternMatched": "Core Connector Update (existsInBoth)"
  }
}
```

### Rendered summary (`session-summary.md`)

Generated by `Export-EiSessionSummary.ps1` from the JSON:

```markdown
# Session: Story 4965976 — Core connector not inserted after update

**Duration:** 3m 36s | **Tokens:** 7,682 | **Cost:** ~$0.08
**Domain:** Termination Drawing | **Pattern:** existsInBoth guard
**Outcome:** Fixed in 1 commit

## Timeline

| Time | Phase | What happened |
|------|-------|---------------|
| 09:00:01 | Intake | Retrieved story (3 comments, 2 images) |
| 09:00:06 | Understanding | Matched to bug pattern #5 in termination-drawing |
| 09:00:09 | Checkpoint | Presented understanding → human confirmed |
| 09:02:31 | Complexity | Assessed as small bug (1 file, 1 method) |
| 09:03:00 | Implementation | Modified CoreConnectorManager.cs |
| 09:03:10 | Validation | Layer guard: PASS |
| 09:03:15 | Tests | 12/12 passing |
| 09:03:35 | Commit | fix(termination-drawing): only skip core insertion when shape found |

## Agent Reasoning Trail

### Why termination-drawing?
> Story mentions 'core connector', 'update scenario', 'insertedTags'.
> Skill documents CoreConnectorManager.cs and the existsInBoth flow.

### Why small bug?
> Single file, single method, bug pattern already documented with fix.

### What I changed and why:
> Per bug pattern #5: only `return` when shape is actually found with matching metadata.
> When shape NOT found, fall through to normal insertion path.

## For the maintainer

- **Skill coverage:** Bug pattern #5 was a direct hit. No codebase searching needed.
- **Improvement opportunity:** None identified — the skill documented this exact scenario.
- **Human wait time:** 2m 21s (between presenting understanding and getting confirmation)
- **Agent efficiency:** 3 file reads, 1 file write, 1 test run. Target was <10 commands. ✓
```

---

## Domain skill catalogue script

`Get-EiDomainSkillCatalog.ps1` — the agent calls this once to know what's available.

**Input:** none (reads from registry file)
**Output:** JSON array of available skills with enough info for the agent to shortlist

```jsonc
{
  "skills": [
    {
      "domainId": "termination-drawing",
      "displayName": "Termination Drawing",
      "skillPath": "skills/termination-drawing/SKILL.md",
      "description": "Diagnose, implement, and verify AVEVA EI Termination Drawing features...",
      "whenToUse": [
        "Drawing generation/update workflow issues",
        "LOC model and traversal bugs",
        "Shape placement, translate, delete logic",
        "Wire/core/cable connector routing",
        "Multi-sheet layout, group overlap"
      ]
    }
  ]
}
```

The agent reads description + whenToUse. If a shortlist matches, it reads the full SKILL.md. Progressive disclosure — cheap first pass, expensive only for matches.

---

## `domain-skill-registry.json` — simplified role

Remains as a **machine-readable index only**. No detection terms, no synonyms. Schema enforced:

```jsonc
{
  "schemaVersion": "1.0.0",
  "domains": [
    { "id": "termination-drawing", "displayName": "Termination Drawing", "skillPath": "skills/termination-drawing/SKILL.md" }
  ]
}
```

Agent uses this to know what IDs are valid. `Get-EiDomainSkillCatalog.ps1` enriches it with content from SKILL.md frontmatter + When to Use section.

---

## story-understanding.json schema

```jsonc
{
  "schemaVersion": "1.0.0",
  "storyId": "4965976",
  "adoHash": "sha256:...",           // binds to exact ado.json version
  "status": "confirmed",             // draft | confirmed

  "understanding": {
    "subject": "Core connectors not inserted after wire re-addition in update scenario",
    "expectedOutcome": "After update 2 (wires added back), core connectors should be inserted at restored LOC levels",
    "requirements": [
      { "text": "existsInBoth check must not suppress insertion when shape was deleted", "source": "description" },
      { "text": "Composite key metadata must match before skipping", "source": "comment:12" }
    ],
    "technicalConcepts": ["existsInBoth", "composite key", "insertedTags", "LOC level"],
    "acceptanceCriteria": ["Core shapes appear at restored LOC levels after update 2"]
  },

  "attachmentUnderstanding": [
    { "fileName": "before-update.png", "observations": [
      { "text": "Shows 8 items with cores connecting JB1 and JB2", "certainty": "visible" }
    ]}
  ],

  "commentUnderstanding": {
    "commentsRead": 3,
    "supersedingInfo": [
      { "commentId": "12", "effect": "Clarifies the bug is specifically in the existsInBoth path" }
    ]
  },

  "proposedDomains": [
    { "domainId": "termination-drawing", "reason": "Story involves core connector insertion during drawing update", "confidence": "high" }
  ],
  "confirmedDomains": ["termination-drawing"],

  "complexity": {
    "assessment": "small",       // small | large
    "reasoning": "Single file, single method, documented bug pattern",
    "filesLikely": 1,
    "methodsLikely": 1
  },

  "ambiguities": [],

  "humanReview": {
    "reviewedBy": "siddhant.bhardwaj",
    "reviewedAt": "2026-08-26T09:02:30Z",
    "decision": "confirmed",
    "corrections": []
  }
}
```

---

## approved-files.json schema

```jsonc
{
  "schemaVersion": "1.0.0",
  "storyId": "4965976",
  "understandingHash": "sha256:...",  // binds to the understanding it was derived from
  "approvedAt": "2026-08-26T09:02:45Z",
  "approvedBy": "siddhant.bhardwaj",
  "approvalType": "direct",           // direct (small bug) | plan-reviewed (large change)
  "files": [
    { "path": "Presentation/Aveva.EI.CanvasDrawings/TerminationDrawing/Manager/CoreConnectorManager.cs",
      "intent": "modify", "reason": "Fix existsInBoth early return" }
  ],
  "hash": "sha256:..."               // for drift detection
}
```

---

## Drift detection

`Test-EiScopeDrift.ps1` simplified to:
1. Read `approved-files.json`
2. Get actual changed files (git diff)
3. Compare: any file changed that's not in the approved list?
4. If yes → warn the developer, ask if they want to approve the addition
5. If all match → pass

No seal, no canonical hashing ceremony, no scope-change-request artifacts. Just: "you said you'd change X, you actually changed X+Y, is Y intentional?"

---

## Layer guard integration

Runs as a self-check before commit. The agent calls:

```powershell
& ./skills/ei-layer-guard/scripts/Invoke-EiLayerGuard.ps1 `
    -ChangedFiles @('path/to/changed/file.cs') `
    -ChangedProjects @('path/to/changed.csproj') `
    -Json
```

If `status: blocked` → agent reports the violation and does NOT commit.
If `status: needs-manual-review` → agent informs developer.
If `status: pass` → proceed to commit.

---

## aveva-rnd delegation

| Step | RND Skill | How |
|------|-----------|-----|
| Code review | `code-review` | Agent runs Get-ReviewDiff + reviews changed lines |
| Commit | `git-commit` | Conventional commit with type/scope from story |
| PR | `create-pr` | Title from story, description from understanding |
| Rebase | `git-rebase` | If needed before PR |

The agent reads these skills directly (they're installed). No EI wrappers needed.

**Used:**
- `code-review` — self-check before commit
- `git-commit` — conventional commit
- `create-pr` — PR with linked work item
- `git-rebase` — if needed before PR
- `csharp-conventions` — loaded when writing/reviewing C# code (Allman braces, `_camelCase` fields, XML doc patterns, test naming)
- `refactor` — when fix involves restructuring existing code (extract method, break up god class). Golden rules: small steps, test after each, don't mix refactor with feature changes
- `nuget-manager` — when implementation needs to add/update NuGet packages. Enforces `dotnet add package` over hand-editing `.csproj`, plus restore verification
- `test-value-analysis` — when deciding which tests to write. Framework: "if the test can't fail in production, don't write it." Prevents test bloat
- `pr-security-compliance` — 11 OWASP security controls checked post-PR as self-audit (Named Pipes, injection, hardcoded creds, unsafe deserialization)
- `get-reviewresults` — on ITERATE path, checks if prior code review is stale before re-running. Avoids redundant full reviews
- `mermaid-diagrams` — enforces Mermaid-only diagrams (no ASCII art) when agent touches documentation

**Not used:** `bug-diagnosis` (domain skills replace it), `speckit-bootstrap` (no spec phase), `create-audit` (session log replaces it), `performance-profiling` (out of scope), `ai-ready-*` (repo scaffolding), `backlog-*` / `item-classifier` / `transcript-parser` (planning tooling), `create-epic` / `create-feature` / `create-user-story` / `create-bug-report` / `create-issue-report` (work item creation — agent consumes, doesn't create), `sprint-review` (ceremony tooling), `har-analysis` (browser traffic), `prerequisite-validator` (Decision #11), `azure-devops-cli` (already wrapped by ei-azure-devops-cli-intake).

---

## No domain skill scenario

When the catalogue returns no match, the agent says:

```
### No matching domain skill

I checked the available domain skills and none cover this area.

**What this means:**
- I don't have documented key files, bug patterns, or architecture rules
- I can still read the codebase and reason, but less precisely
- My scope proposals may miss important files

**What would help me:**
- Which source files are relevant to this story?
- Are there architecture rules I should follow?
- Any patterns or conventions for this area?

**Your options:**
1. Give me context → I'll proceed with your guidance
2. Stop here → this area needs a domain skill written first
3. Point me to files → I'll read them and propose a plan
```

The developer stays in control. Agent doesn't refuse, doesn't pretend.

---

## What gets deleted (eventually)

### Phase 1 deletions (dead today, safe)
- `plugins/.../ei-vocabulary-navigator/references/domain-pack-policy.json` (zero callers)
- `plugins/.../ei-vocabulary-navigator/data/vocabulary-map.json` (only called by navigator being deleted)
- `plugins/.../ei-graphics-workflow/references/lifecycle-iterate.json` (zero callers)
- `plugins/.../ei-graphics-workflow/scripts/New-EiWorkflowResult.ps1` (zero runtime callers)
- `plugins/.../ei-workflow-state/schemas/workflow-result.schema.json` (only used by above)
- `tests/.../ei-graphics-workflow/scripts/New-EiWorkflowResult.Tests.ps1` (tests deleted script)
- `outputs_of_prompts_for_improving/` entire directory (scratch output, gitignored but present)
- Clean up references in `INSTRUCTIONS.md` and `README.md` that mention deleted files

### Phase 2 deletions (after new architecture lands)
- `ei-vocabulary-navigator/` entire skill directory
- `ei-bug-reproducer/` entire skill directory
- `ei-scope-resolver/` entire skill directory (includes New-EiScopeCandidate.ps1)
- `ei-scope-validator/` entire skill directory
- `ei-workflow-state/` entire skill directory
- `ei-graphics-workflow/` entire skill directory (SKILL.md + all scripts)
- `ei-test-scaffolder/` entire skill directory
- `plugins/.../ei-graphics-workflow/scripts/Validate-EiWorkflowPrerequisites.ps1`
- All corresponding test directories under `tests/aveva-ei-graphics/skills/`
- `INSTRUCTIONS.md` rewritten to reference new architecture only

### Auto-gitignore in target project
When the agent runs in a developer's project (e.g., dabacon-products), it creates:
- `.ei-session-logs/` — session logs
- `.copilottracking/` — code review artifacts

The agent.md must instruct: **before first write**, check the target project's `.gitignore` for these entries. If missing, append them. This is a one-time action per project — idempotent, non-destructive.

```
## First-run setup
Before writing any artifacts, check if `.gitignore` contains `.ei-session-logs/` and `.copilottracking/`.
If either is missing, append them. This prevents session logs from being committed to the target project.
```

### .gitignore additions needed (plugin repo)
Current .gitignore is correct — already ignores:
```
.copilottracking/
.ei-session-logs/
testResults.xml
coverage.xml
.specify/feature.json
.vscode/
azdo-settings.json
specs/
outputs_of_prompts_for_improving/
```
No changes needed.

### Docs to rewrite (Phase 3 — no stale docs on git)
- `PLUGIN-INFO.md` — rewrite to describe new architecture (currently references old lifecycle)
- `plugins/aveva-ei-graphics/README.md` — rewrite skills table, structure tree
- `plugins/aveva-ei-graphics/INSTRUCTIONS.md` — rewrite (references New-EiWorkflowResult, old workflow)
- `.claude-plugin/marketplace.json` — update description (remove "ITERATE routing", "scope control")
- `.github/plugin/marketplace.json` — same description update
- `.github/copilot-instructions.md` — update to reference new architecture, remove old workflow rules
- `README.md` (root) — update description paragraph only; installation section stays

### No-orphan guard test (Phase 3)
After all deletions, add a Pester test that greps for references to deleted names:
- `New-EiWorkflowResult`, `New-EiScopeCandidate`, `vocabulary-map`, `domain-pack-policy`
- `lifecycle-iterate`, `Invoke-EiVocabularyNavigator`, `Invoke-EiBugReproducer`
- `ei-scope-resolver`, `ei-scope-validator`, `ei-workflow-state`, `ei-test-scaffolder`
Any match in non-spec, non-test files = test failure.

---

## Migration plan

### Phase 1: Foundation (no breaking changes)

1. Create `Write-EiArtifact.ps1` — simple schema-validated JSON writer
2. Create `Write-EiSessionEntry.ps1` — append to session.json
3. Create `Export-EiSessionSummary.ps1` — render markdown from JSON
4. Create `Get-EiDomainSkillCatalog.ps1` — enumerate registry + parse SKILL.md headers
5. Create `Test-EiScopeDrift.ps1` (simplified) — compare git diff vs approved-files.json
6. Define schemas: `story-understanding.schema.json`, `approved-files.schema.json`, `session.schema.json`
7. Tests for all new scripts

**Gate:** All new scripts pass Pester. Old tests still pass.

### Phase 2: Agent rewrite

8. Rewrite `ei-graphics.agent.md`:
   - Simple flow: intake → understand → checkpoint → implement → validate → commit
   - Progressive session logging at every step
   - Complexity branching (small/large)
   - No-domain-skill conversational fallback
   - Delegate to aveva-rnd for review/commit/PR
9. Wire layer guard as pre-commit self-check

**Gate:** Manual run on story 4965976. Target: <10 terminal commands, full session log produced.

### Phase 3: Cleanup

10. Delete dead files (Phase 1 list)
11. Delete replaced machinery (Phase 2 list)
12. Update README, INSTRUCTIONS, PLUGIN-INFO
13. Add guard test: no references to deleted mechanisms

**Gate:** Full Pester suite green. Session log from a real run reviewed by maintainer.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Session logging adds overhead | Append-only, no blocking. Summary generated only at end. |
| Agent forgets to log | Agent.md instructions make it non-optional. Absence in log = visible gap. |
| Drift detection too strict for exploratory fixes | Agent can ask human to approve additions mid-flow |
| No skill = bad scope | Agent explicitly tells human, doesn't pretend. Human provides context. |
| Token cost of reading full SKILL.md | Progressive disclosure: catalogue first, full read only for matches |

---

## Decisions made

1. **No scope resolver/validator pipeline.** Agent proposes, human approves, drift detects violations.
2. **No bug-diagnosis from RND.** Domain skills ARE the diagnosis capability.
3. **Layer guard kept.** Binary deterministic check, run before commit by the agent.
4. **Session logging captures everything.** JSON progressive + markdown summary. Lives in `.ei-session-logs/`.
5. **Small/large branching.** Agent assesses complexity; small bugs skip the plan presentation.
6. **No domain skill = conversational fallback.** Developer provides context or stops.
7. **aveva-rnd for code-review, git-commit, create-pr.** No EI wrappers.
8. **Simple artifact persistence.** Write-EiArtifact.ps1 with schema check. No workflow-state machinery.
9. **Registry stays.** Machine-readable index only. No semantic fields.
10. **Session log verbosity: verbose first, concise later.** During skill improvement phase, agent writes full chain-of-thought reasoning (e.g., "I matched this to bug pattern #5 because the story mentions 'existsInBoth' and the skill documents that exact scenario"). Once skills are mature and evals pass consistently, switch to concise mode (e.g., "Matched: termination-drawing, pattern #5"). The verbose output feeds back into skill improvement — it shows where skills have gaps, where the agent struggles, and where instructions are ambiguous. Controlled via a `verbosity` field in session schema (`"verbose"` | `"concise"`).
11. **No automated preflight.** Prerequisites documented in README. Agent assumes environment is ready. Errors are the diagnostic.
12. **No automated eval framework.** Skill improvement is manual: run agent → read session-summary.md → fix SKILL.md → repeat. No evals.json, no fixtures, no benchmark.json.
13. **Validate-EiWorkflowPrerequisites.ps1 deleted.** Replaced by README documentation.
