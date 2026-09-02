# EI Graphics plugin — how it works, in six diagrams

A visual walkthrough of the plugin as it works today. Read top to bottom: the first two diagrams
say **what** it is and **how** a story flows through it; the rest zoom into the mechanics.

Every diagram is also saved as a standalone `.mmd` file in this folder so you can drop it straight
into Excalidraw (Insert → Mermaid). The mermaid here avoids `<br>` and `\n`, which Excalidraw does
not render, and uses short labels so the boxes stay legible.

---

## 1. System context — what talks to what

The plugin is a conversational agent that turns one Azure DevOps story into a verified fix. It
reads ADO but never writes back to it, edits the product code, asks a human to agree twice, and
hands review, commit and PR to `aveva-rnd`. Every step is appended to a session log.

```mermaid
flowchart LR
    Dev["Developer"]

    subgraph Plugin["demo-ei-graphics plugin"]
        Agent["EI Graphics agent"]
        Skills["Core and domain skills"]
    end

    ADO["Azure DevOps story"]
    Repo["Product code repo"]
    Rnd["aveva-rnd plugin"]
    Logs[("Session logs")]

    Dev -->|"story link"| Agent
    Agent -->|"two approvals"| Dev
    Agent -->|"read only"| ADO
    Agent -->|"read and edit"| Repo
    Agent -->|"review, commit, PR"| Rnd
    Agent -->|"append every step"| Logs
    Skills -->|"code knowledge"| Agent
```

**Key idea:** the agent does the reasoning; the skills hold the code knowledge; delivery is
delegated. Nothing in the plugin tries to reason on the agent's behalf.

---

## 2. End-to-end workflow — how a story becomes a fix

Two human checkpoints gate the run. A deterministic script fetches the story; the agent proposes;
the human confirms understanding, then approves scope. Small bugs skip straight to implementation;
large changes get a plan first.

```mermaid
flowchart TD
    A["ADO intake script writes ado.json"] --> B["Agent reads and understands story"]
    B --> C{"Checkpoint 1: understanding and domain"}
    C -->|"human agrees"| D["Persist story-understanding.json"]
    D --> E{"Complexity?"}
    E -->|"small bug"| I["Implement surgical fix"]
    E -->|"large change"| F["Agent proposes scope and plan"]
    F --> G{"Checkpoint 2: plan approval"}
    G -->|"human approves"| H["Persist approved-files.json"]
    H --> I
    I --> J{"Layer guard and drift check"}
    J -->|"clear"| K["Delegate to aveva-rnd"]
    J -->|"violation or drift"| X["Report and stop"]
    K --> L["Render session summary"]
```

**Key idea:** the split between deterministic scripts (intake, persistence, guards) and semantic
reasoning (understanding, scope, implementation) is deliberate. Only scripts decide pass or fail.

---

## 3. Run sequence — the same flow over time

The temporal view. Notice the agent reads `ado.json` once and never re-fetches from ADO, and that
core scripts are the only thing writing artifacts.

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant Ag as EI Graphics agent
    participant In as ADO intake
    participant Sk as Domain skill
    participant Sc as Core scripts
    participant Rn as aveva-rnd

    Dev->>Ag: story link
    Ag->>In: fetch story, images, comments
    In->>Sc: write ado.json
    Ag->>Ag: read ado.json, draft understanding
    Ag->>Dev: Checkpoint 1
    Dev-->>Ag: agree
    Ag->>Sc: write story-understanding.json
    Ag->>Sk: match bug pattern, read key files
    Ag->>Dev: Checkpoint 2 when large
    Dev-->>Ag: approve
    Ag->>Sc: write approved-files.json
    Ag->>Ag: apply surgical fix, run tests
    Ag->>Sc: layer guard and drift check
    Ag->>Rn: review, commit, PR
    Ag->>Sc: render session summary
    Ag->>Dev: summary link
```

---

## 4. Components and ownership — what the plugin owns vs delegates

The plugin ships one agent and four skills. Review, commit and PR are read directly from
`aveva-rnd` rather than wrapped, which keeps the surface small.

```mermaid
flowchart TB
    Agent["ei-graphics agent"]

    subgraph Owns["EI plugin owns"]
        subgraph SkillSet["Skills"]
            Intake["ei-azure-devops-cli-intake"]
            Core["ei-graphics-core: six scripts"]
            Guard["ei-layer-guard"]
            Domain["termination-drawing domain"]
        end
    end

    subgraph Delegates["Delegated to aveva-rnd"]
        Review["code-review"]
        Commit["git-commit"]
        PR["create-pr"]
    end

    Agent --> SkillSet
    Agent --> Delegates
    Core --> Artifacts[("JSON artifacts and summary")]
```

**Key idea:** a domain skill like `termination-drawing` *is* the scope knowledge — no resolver
pipeline. New EI areas are added as new domain skills, one file each.

---

## 5. Progressive disclosure — how skills stay cheap to load

Skills load in three tiers so the agent only pays for what it needs. Names and descriptions are
always in context; the body loads when a skill is activated; references and scripts load only when
the task reaches for them.

```mermaid
flowchart LR
    subgraph T1["Tier 1: always loaded"]
        M["Skill name and description"]
    end

    subgraph T2["Tier 2: on activation"]
        B["SKILL.md body"]
    end

    subgraph T3["Tier 3: on demand"]
        R["references and scripts"]
    end

    M -->|"skill looks relevant"| B
    B -->|"need deeper detail"| R
```

**Key idea:** this is why the agent is told to work skill-first — match a documented bug pattern,
then read the skill's Key Files, and only search the wider codebase when the skill is silent.

---

## 6. Artifacts and drift — how the run stays honest

Each stage writes a schema-checked JSON artifact. Hashes chain them together: the understanding
records the hash of the ADO data it came from, and the approved file list is compared against the
real git changes before anything is committed.

```mermaid
flowchart TB
    Intake["ADO intake"] --> Ado[("ado.json")]
    Ado -->|"adoHash"| SU[("story-understanding.json")]
    SU --> AF[("approved-files.json")]
    AF -->|"approved list and hash"| Drift{"Drift check vs git changes"}
    Changes["Actual file changes"] --> Drift
    Drift -->|"pass"| Commit["Delegate commit"]
    Drift -->|"drift"| Report["Report unapproved files"]
    Steps["Every agent step"] --> Session[("session.json")]
    Session --> Summary["session-summary.md"]
```

**Key idea:** drift is reported, not auto-resolved. If the agent touched a file nobody approved,
the run stops and asks a human. The session log then feeds the manual skill-improvement loop.

---

## Using these in a slide or on a whiteboard

- **Excalidraw:** open a `.mmd` file, copy its contents, then in Excalidraw use *Insert → Mermaid*
  and paste. The diagrams deliberately avoid `<br>` and `\n`, which that importer drops.
- **GitHub / VS Code:** this `README.md` renders every diagram inline, no tooling needed.
- Keep each diagram on its own slide. They are sized to stay readable when projected.

| File | Diagram |
|---|---|
| `01-system-context.mmd` | What talks to what |
| `02-workflow.mmd` | Story to fix, with the two checkpoints |
| `03-run-sequence.mmd` | The same flow over time |
| `04-components.mmd` | Owned vs delegated |
| `05-progressive-disclosure.mmd` | Three-tier skill loading |
| `06-artifacts-and-drift.mmd` | Artifacts, hashing and drift |
