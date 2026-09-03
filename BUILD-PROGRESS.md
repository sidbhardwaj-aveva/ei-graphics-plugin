# Build Progress — aveva-ei-graphics v3

**Plan:** `plan.md`
**Current task:** T023
**Last verified green:** T027 (2026-09-03T12:46:57Z)

The rows below run top to bottom. T015 sits above T010 on purpose: T010 builds its catalogue from
the real registry, whose only entry points at the skill document T015 copies. See the T010 blocks
in `BUILD-LOG.md`.

| ID | Task | Status | Commit | Acceptance verified at |
|----|------|--------|--------|------------------------|
| T001 | Repo bootstrap and source check | DONE | 7254028 | 2026-08-31T16:10:15Z |
| T002 | The progress checker | DONE | c179400 | 2026-08-31T16:34:00Z |
| T003 | The test harness | DONE | c61eb07 | 2026-08-31T16:48:00Z |
| T004 | Four schemas: three written, one copied | DONE | 3b3eb31 | 2026-08-31T17:05:00Z |
| T005 | The domain skill registry | DONE | 1ebf8c4 | 2026-08-31T17:14:00Z |
| T006 | ei-graphics-core SKILL.md and the plain-language checker | DONE | 367b3da | 2026-08-31T17:38:00Z |
| T007 | Write-EiArtifact.ps1 | DONE | 9568e0c | 2026-08-31T17:56:00Z |
| T008 | Write-EiSessionEntry.ps1 | DONE | e768ce3 | 2026-09-02T12:05:00Z |
| T009 | Export-EiSessionSummary.ps1 | DONE | bfc9d6e | 2026-09-02T09:52:00Z |
| T015 | Copy and split termination-drawing | DONE | 7552aa4 | 2026-08-31T19:02:00Z |
| T010 | Get-EiDomainSkillCatalog.ps1 | DONE | 556cfe1 | 2026-08-31T19:14:00Z |
| T011 | Test-EiScopeDrift.ps1 | DONE | 5907ded | 2026-08-31T19:24:00Z |
| T012 | Convert-EiAdoIntake.ps1 | DONE | 7329c09 | 2026-08-31T19:42:00Z |
| T013 | Copy ei-azure-devops-cli-intake | DONE | a85ce8b | 2026-08-31T20:02:00Z |
| T014 | Copy ei-layer-guard | DONE | 60b59ac | 2026-08-31T20:12:00Z |
| T016 | agents/ei-graphics.agent.md | DONE | 65a506d | 2026-08-31T20:30:00Z |
| T017 | The manifests | DONE | b95a93d | 2026-08-31T20:40:00Z |
| T018 | The documents | DONE | 7247517 | 2026-08-31T20:52:00Z |
| T019 | The no-orphan check | DONE | ee21c44 | 2026-09-02T09:36:00Z |
| T020 | The script contract check | DONE | 4e68ec1 | 2026-08-31T21:20:00Z |
| T021 | Everything green, before the live run | DONE | 2abf97f | 2026-08-31T21:32:00Z |
| T024 | Evidence behind the reasoning | DONE | dfc5fa1 | 2026-09-03T05:59:24Z |
| T025 | Comment deviations in the summary | DONE | 02eb879 | 2026-09-03T06:52:00Z |
| T026 | Publish team plugin and collect sessions | DONE | 2a9d016 | 2026-09-03T12:33:47Z |
| T027 | Document the installed-plugin migration | DONE | pending | 2026-09-03T12:46:57Z |
| T022 | Dry run against story 3408091 | BLOCKED | — | — |
| T023 | Read the summary, improve the skill | TODO | — | — |
