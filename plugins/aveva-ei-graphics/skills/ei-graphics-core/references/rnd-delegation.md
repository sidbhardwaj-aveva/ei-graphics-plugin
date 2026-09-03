# Delegating to `aveva-rnd`

The `aveva-rnd` plugin is installed alongside this one. Read its skills directly. This plugin
wraps none of them.

## When to use which skill

| Step | Skill | How |
|---|---|---|
| Self-check before committing | `code-review` | Review the changed lines, not the whole file |
| Commit | `git-commit` | A conventional commit, with the type and scope from the story |
| Pull request | `create-pr` | Title from the story, description from the understanding |
| Rebase | `git-rebase` | Only if the branch needs it before the PR |
| Writing C# | `csharp-conventions` | Load before writing or reviewing any C# |
| Restructuring code | `refactor` | Small steps, test after each, never mixed with a fix |
| Adding a package | `nuget-manager` | Use the command, never hand-edit the project file |
| Deciding what to test | `test-value-analysis` | If it cannot fail in production, do not write it |
| After the PR | `pr-security-compliance` | A self-audit against the security controls |
| Repeat review | `get-reviewresults` | Checks whether an earlier review is stale first |
| Any diagram | `mermaid-diagrams` | Diagrams only, never drawings made of text characters |

That is 11 skills. Use nothing else from `aveva-rnd`.

## What this plugin deliberately does not use

Bug diagnosis is replaced by the domain skills. The session log replaces the audit skill. There is
no specification phase. Work item creation is out of scope, because this agent reads stories and
does not write them. Anything to do with planning, ceremonies, browser traffic or repository
scaffolding is out of scope too.

## No matching domain skill

When the catalogue returns nothing that fits, say this:

### No matching domain skill

I checked the available domain skills and none cover this area.

**What this means:**

- I have no documented key files, bug patterns or architecture rules for it.
- I can still read the code and reason about it, but less precisely.
- The files I propose to change may miss something important.

**What would help me:**

- Which source files matter for this story?
- Are there architecture rules I should follow?
- Any patterns or conventions for this area?
