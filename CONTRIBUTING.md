# Contributing to AVEVA Agent Plugins

Thank you for your interest in contributing to the AVEVA Agent Plugins marketplace! This guide will help you understand what to build, how to decide on the right contribution type, and how to get your changes merged.

## Table of Contents

- [Contributing to AVEVA Agent Plugins](#contributing-to-aveva-agent-plugins)
  - [Table of Contents](#table-of-contents)
  - [Before You Start: Check for Duplicates](#before-you-start-check-for-duplicates)
  - [What Should I Build?](#what-should-i-build)
    - [Plugin](#plugin)
    - [Agent](#agent)
    - [Workflow](#workflow)
    - [Skill](#skill)
    - [Instruction](#instruction)
    - [Decision Guide](#decision-guide)
  - [Quality Guidelines](#quality-guidelines)
  - [Plugin Structure](#plugin-structure)
    - [Compliance enforcement](#compliance-enforcement)
    - [Removing a plugin from the exemptions list](#removing-a-plugin-from-the-exemptions-list)
  - [Versioning](#versioning)
  - [How to Contribute](#how-to-contribute)
    - [Adding a Plugin](#adding-a-plugin)
    - [Adding an Agent](#adding-an-agent)
    - [Adding a Skill](#adding-a-skill)
    - [Adding a Workflow](#adding-a-workflow)
    - [Adding an Instruction](#adding-an-instruction)
  - [Testing Your Changes Before Publishing](#testing-your-changes-before-publishing)
    - [Option 1: Point the marketplace at a branch (recommended)](#option-1-point-the-marketplace-at-a-branch-recommended)
    - [Option 2: Point the marketplace at a local clone](#option-2-point-the-marketplace-at-a-local-clone)
    - [Avoiding duplicate entries](#avoiding-duplicate-entries)
  - [Submitting Your Contribution](#submitting-your-contribution)
  - [Code of Conduct](#code-of-conduct)

---

## Before You Start: Check for Duplicates

**Always check the marketplace before creating something new.**

Review the existing plugins in the `plugins/` directory and the [marketplace catalog](site/) to see if the functionality you're building is already available — either fully or partially. Contributing something that duplicates existing work adds maintenance overhead and fragments user experience.

Ask yourself:
- Does any existing plugin (e.g., `aveva-rnd`, `aveva-core`, `aveva-portfolio`) already expose this functionality as a skill or agent?
- Could you extend or compose an existing skill rather than creating a new one?
- Is there a shared utility in `aveva-core` that already solves part of the problem?

If what you need is close but not quite right, consider opening an issue or discussion first to propose an enhancement to an existing plugin rather than adding a new one.

---

## What Should I Build?

Understanding the differences between contribution types helps you pick the right building block.

### Plugin

A **plugin** is a self-contained package that groups related agents, skills, and supporting assets around a specific domain or workflow theme. Plugins are the top-level units users install from the marketplace.

**Choose a plugin when:**
- You are delivering a cohesive set of capabilities for a distinct domain (e.g., portfolio management, R&D workflows, infrastructure)
- Your contribution includes multiple skills and/or agents that naturally belong together
- You want users to be able to install everything they need for a workflow in one step

> Example: `aveva-portfolio` is a plugin that packages skills and an agent for hypothesis-driven portfolio planning.

---

### Agent

An **agent** is a specialized `.agent.md` file that transforms GitHub Copilot Chat into a domain-specific assistant with a defined persona, tools, and behavior. Agents are conversational and guide users through complex, multi-step tasks interactively.

**Choose an agent when:**
- You need a persistent, persona-driven assistant that the user has an ongoing dialogue with
- The interaction is open-ended and conversational rather than command-like
- You need to combine multiple tools, context sources, and decision points in a single session

> Example: `portfolio.agent.md` acts as a portfolio strategist that guides users through the full initiative and opportunity lifecycle.

---

### Workflow

A **workflow** is a skill that orchestrates a sequence of steps, often calling other skills or external systems in a defined order to complete a multi-stage process. Workflows are typically deterministic pipelines rather than interactive conversations.

**Choose a workflow when:**
- You need to chain several steps (e.g., fetch → transform → validate → publish) in a repeatable way
- The execution path is largely fixed and not driven by open-ended user conversation
- You want to coordinate multiple existing skills or scripts into a single invocation

> Example: `portfolio-workflow` orchestrates the opportunity → initiative → MoS challenger pipeline.

---

### Skill

A **skill** is a focused, self-contained capability defined in a `SKILL.md` file. Skills are the atomic units of the marketplace — each one does one thing well. Skills can be composed into plugins and invoked by agents or workflows.

**Choose a skill when:**
- You are building a single, well-scoped capability (e.g., "create a git commit", "acquire an auth token")
- The task is repeatable and machine-friendly, not requiring back-and-forth conversation
- You want the capability to be reusable by other plugins, agents, or workflows

> Example: `get-authtoken` is a skill that acquires bearer tokens for Microsoft Entra-protected services.

---

### Instruction

An **instruction** is a lightweight markdown file (`.instructions.md`) that customizes how GitHub Copilot behaves in a specific context — such as enforcing coding conventions, style guides, or domain-specific rules. Instructions don't execute actions; they shape Copilot's default behavior.

**Choose an instruction when:**
- You want to tune Copilot's responses for a specific technology, framework, or team convention
- No tool invocation or scripted execution is needed — only behavior shaping
- The guidance applies broadly across many interactions rather than to a single task

> Example: An instruction for enforcing AVEVA C# coding standards across all Copilot responses in a repository.

---

### Decision Guide

Use this table to quickly identify what to build:

| I want to… | Build a… |
|---|---|
| Package multiple capabilities for a domain as an installable unit | **Plugin** |
| Create a conversational, persona-driven assistant | **Agent** |
| Chain multiple steps into a repeatable pipeline | **Workflow** (as a skill) |
| Deliver one focused, reusable capability | **Skill** |
| Tune Copilot's default behavior for a tech/convention | **Instruction** |
| Extend an existing domain with more capabilities | Extend the existing **Plugin** |

---

## Quality Guidelines

- **Be specific**: Generic implementations are less useful than focused, actionable ones
- **Test your contribution**: Ensure scripts are repeatable, idempotent, and work in a clean environment
- **Follow conventions**: Use consistent naming, formatting, and directory structure (see [Plugin Structure](#plugin-structure) below)
- **Keep it focused**: Each skill should address one clear use case
- **Write clearly**: Use plain language in descriptions, help docs, and comments
- **No secrets**: Never commit credentials, tokens, or environment-specific values
- **Use conventional commits**: Follow the [commit message guidelines](docs/commit-message-guidelines.md). The repository squash-merges pull requests, so a CI gate validates the **PR title** (which becomes the commit on the default branch).

---

## Plugin Structure

Every plugin MUST contain the following at its top level (additional files such as `README.md` are permitted):

```text
plugins/<plugin-name>/
  .github/                         # Required — contains plugin.json manifest
  skills/                          # Required if no agents/ folder
  agents/                          # Required if no skills/ folder
  prompts/                         # Optional — slash-command prompt delegates (*.prompt.md)
  .claude-plugin/                  # Optional — Claude Code plugin manifest
  <plugin-name>-principles.md      # Optional — principles file (file only, not a folder)
```

**At least one of `skills/` or `agents/` must be present.** A plugin that has neither fails CI. A plugin may have both.

No other folders are permitted at the plugin root beyond those listed above. This is an intentionally strict
policy: all helper scripts, rules, and supplementary assets belong inside a skill's
subdirectory (e.g., `skills/<skill-name>/scripts/`), not as separate top-level folders.

Additional files at the plugin root (such as `README.md`) are allowed and not checked by the compliance workflow.

### Compliance enforcement

The plugin structure is verified by `tools/Test-PluginStructure.ps1` as a required
step in every CI build.

All plugins are **strictly enforced by default**. The `exemptions` list in
`.github/plugin-compliance.json` exists solely to track pre-existing violations
that were present when this workflow was introduced. It is a tech debt backlog,
not an opt-out mechanism. New plugins MUST satisfy the full structure before
merging — no exemptions will be granted for newly created plugins.

### Removing a plugin from the exemptions list

Once a plugin's structure has been corrected and merged to `main`, remove it from
the `exemptions` array in `.github/plugin-compliance.json`. From that point, any
future structural violation in that plugin will fail CI. The target state is an
empty exemptions list.

---

## Versioning

Plugin versions follow [Semantic Versioning](https://semver.org/) and are **managed automatically** by the `plugin-versioning` GitHub Actions workflow on every merge to `main`.

| Change type | Version bump | Who does it |
|---|---|---|
| New skill or agent added | **minor** (e.g. `1.2.0 → 1.3.0`) | Automated |
| File modified in an existing skill/agent | **patch** (e.g. `1.2.0 → 1.2.1`) | Automated |
| Breaking change / intentional major release | **major** (e.g. `1.2.0 → 2.0.0`) | **Manual — edit `plugin.json` only** |

**Do not manually edit** the `"version"` field in `plugins/<plugin>/.github/plugin/plugin.json` or in `.github/plugin/marketplace.json` for minor or patch changes — the automation will handle those on merge. Only bump the major version manually when you are intentionally introducing a breaking change, and only edit `plugin.json`; the marketplace entry is always kept in sync by the workflow.

A `CHANGELOG.md` is generated automatically for each bumped plugin alongside an LLM-authored prose summary of the changes.

---

## How to Contribute

### Adding a Plugin

1. **Create the plugin directory structure** under `plugins/` following the `aveva-<name>` naming convention:
   ```
   plugins/aveva-<name>/
     .github/plugin/plugin.json
     skills/
     agents/
   ```

2. **Create plugin metadata** in `.github/plugin/plugin.json`:
   ```json
   {
     "name": "aveva-<name>",
     "description": "Your plugin description",
     "version": "1.0.0",
     "author": {
       "name": "AVEVA"
     },
     "skills": "skills/",
     "agents": "agents/"
   }
   ```
   Set `version` to `1.0.0`. All subsequent minor and patch bumps are automated — only increment the major version here if you are deliberately introducing a breaking change.

3. **Register in the marketplace** by adding your plugin to the `plugins` array in `.github/plugin/marketplace.json`:
   ```json
   {
     "name": "aveva-<name>",
     "source": "aveva-<name>",
     "description": "AVEVA <Name> - Hypervelocity Engineering workflows",
     "version": "1.0.0"
   }
   ```
   After the initial registration, **do not edit the `version` field** in this file directly — it is kept in sync automatically.

4. **Add skills and agents** — create `SKILL.md` files in `skills/` and `.agent.md` files in `agents/` following existing patterns.

5. **Update the README** — add your plugin to the Plugins section with descriptions of its skills.

---

### Adding an Agent

1. **Create your agent file** — add a new `.agent.md` file in the `agents/` directory of the appropriate plugin.

2. **Follow the naming convention** — use descriptive, lowercase filenames with hyphens and the `.agent.md` extension (e.g., `portfolio.agent.md`).

3. **Include frontmatter** with required metadata at the top:
   ```yaml
   ---
   description: "Brief description of the agent and its purpose"
   model: "gpt-4o"
   tools: ["execute/runInTerminal", "edit", "read", "search", "agent"]
   name: "My Agent Name"
   ---
   ```

4. **Define the persona** — establish a clear identity, domain expertise, and behavioral guidelines in the body of the file.

5. **Test your agent** — verify it provides accurate, helpful responses in its intended domain before submitting.

---

### Adding a Skill

1. **Create a new skill folder** inside the appropriate plugin's `skills/` directory:
   ```
   plugins/aveva-<name>/skills/<skill-name>/
     SKILL.md
     docs/
     scripts/     # if PowerShell helpers are needed
     templates/   # if output templates are needed
   ```

2. **Author `SKILL.md`** with a clear front matter block and well-structured instructions. Name must match the folder name (lowercase with hyphens).

3. **Add optional assets** — keep bundled scripts and templates lean; reference them from `SKILL.md`.

4. **Write tests** for any PowerShell scripts in the `tests/` directory, mirroring the plugin/skill path structure.

5. **Validate** by running existing tests to confirm no regressions:
   ```powershell
   pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
   ```

---

### Adding a Workflow

A workflow is implemented as a skill with orchestration logic. Follow the same steps as [Adding a Skill](#adding-a-skill), and additionally:

- Clearly document the sequence of steps and any skills or external systems called
- Include prerequisite validation (see `bootstrap-runner` as a reference)
- Ensure each step is idempotent where possible

---

### Adding an Instruction

1. **Create your instruction file** — add a new `.instructions.md` file in the appropriate plugin directory or at the repository root if it applies globally. These files are for repository-local or plugin-local guidance only and are **not currently surfaced in the marketplace/catalog** by the repository tooling.

2. **Follow the naming convention** — use descriptive, lowercase filenames with hyphens (e.g., `csharp-coding-standards.instructions.md`) so the purpose of the local guidance is clear.

3. **Structure your content** — start with a clear heading and organize guidance into focused sections for maintainers and local consumers:
   ```markdown
   ---
   description: "Instructions for customizing Copilot behavior for <technology/practice>"
   ---

   # Your Technology / Convention Name

   ## Guidelines

   - Provide clear, specific rules
   - Use bullet points for easy reading
   - Include examples where helpful
   ```

---

## Testing Your Changes Before Publishing

You do not need to merge to `main` to try out a plugin, skill, or agent. Because the marketplace is backed by this Git repository, you can install and use the version on your feature branch while it is still in review. This lets you validate your changes yourself and share them with teammates for feedback before opening — or merging — a pull request.

There are two ways to do this. The branch-ref approach is preferred because it needs no local clone.

### Option 1: Point the marketplace at a branch (recommended)

Marketplace sources live in the `chat.plugins.marketplaces` array in your VS Code user `settings.json`. Add a repository URL that includes a `#<branch>` ref suffix, and VS Code fetches the plugins directly from that branch — you do not have to clone the repository locally.

Your user `settings.json` is located at:

- Windows: `%APPDATA%\Code\User\settings.json`
- macOS: `~/Library/Application Support/Code/User/settings.json`
- Linux: `~/.config/Code/User/settings.json`

To open it inside VS Code, open the Command Palette (`Ctrl+Shift+P` on Windows/Linux, `Cmd+Shift+P` on macOS) and run **Preferences: Open User Settings (JSON)**. Then add or update the `chat.plugins.marketplaces` key:

```json
{
  "chat.plugins.marketplaces": [
    "https://github.com/AVEVA-Copilot-Access/aveva-agent-plugins#feature/<your-branch>"
  ]
}
```

The `#feature/<your-branch>` suffix is the only difference from the standard marketplace URL — it pins the source to your branch instead of the default branch.

Once saved, search the agent plugins marketplace for your plugin (for example `aveva-rnd`) and install it. Anyone you share the branch URL with can add the same entry to their `chat.plugins.marketplaces` and test your work immediately.

### Option 2: Point the marketplace at a local clone

If you prefer to work from a local checkout, clone the repository, switch to your feature branch, and add the local directory to your marketplace settings:

```bash
git clone https://github.com/AVEVA-Copilot-Access/aveva-agent-plugins
cd aveva-agent-plugins
git checkout feature/<your-branch>
```

Add the on-disk path of the clone to the `chat.plugins.marketplaces` array in your user `settings.json` (see Option 1 for the file location and how to open it), then switch branches locally whenever you want to test a different version. This works well when you are iterating rapidly and do not want to push every change first.

### Avoiding duplicate entries

If you keep both the plain repository URL and the `#<branch>` URL as separate entries in `chat.plugins.marketplaces`, each plugin appears twice in search results (for example, two `aveva-rnd` entries). To avoid confusion, either edit your existing entry to add the `#<branch>` suffix, or remove the plain entry so only one source is active.

---

## Submitting Your Contribution

1. **Create a feature branch** off `main`:
   ```bash
   git checkout main && git pull
   git checkout -b feat/<short-description>
   ```

2. **Make your plugin-scoped changes** — keep changes focused on the plugin or skill you're adding or modifying.

3. **Run relevant tests**:
   ```powershell
   pwsh -NoProfile -File ./tests/Invoke-PesterTests.ps1
   ```
   Or for specific skill tests:
   ```powershell
   Invoke-Pester -Path ./tests/<plugin>/skills/<skill>/scripts/
   ```

4. **Commit with a conventional commit message** (see the [commit message guidelines](docs/commit-message-guidelines.md)):
   ```
   feat(aveva-<name>): add <skill/agent/plugin> for <purpose>
   ```
   Validate your messages locally before pushing:
   ```powershell
   pwsh -File ./tools/Test-CommitMessages.ps1 -FromRef origin/main -ToRef HEAD
   ```

5. **Open a pull request** against `main` with a clear description of what you've added and why.

---

## Code of Conduct

All contributors are expected to engage respectfully and professionally. Contributions that introduce harmful content, bypass security policies, or violate AVEVA Responsible AI guidelines will not be accepted.
