# Checkpoint templates

Two moments in a run need a person. Use these shapes, so the person is reading the same thing
every time.

## Checkpoint 1: the understanding

Show what you took from the story before you touch any code.

- What you think the problem is, in two or three sentences.
- What the story says should happen afterwards.
- Which domain skill you picked, and why.
- Anything a comment changed, and which comment it was.
- Anything you could not work out.

Then ask whether that is right, and wait.

## Checkpoint 2: the plan

Show this before a large change. A small change with a documented pattern does not need it.

### Implementation Plan

**Files I'll change:**

1. `File.cs` — change `MethodX`, because ...
2. `File2.cs` — handle the case where ...

**Tests I'll verify:**

- The test command from the domain skill, named in full.

**New tests needed?**

- Either "the existing tests cover this", or
- "Nothing covers X. Should I add a test for it?"

**Risks:**

- What could break that the tests would not catch.

Then wait. The person can agree, narrow it, widen it, refuse it, or ask for tests.

Once they agree, write the list with `Write-EiArtifact.ps1 -ArtifactType approved-files`, and
check it later with `Test-EiScopeDrift.ps1`.
