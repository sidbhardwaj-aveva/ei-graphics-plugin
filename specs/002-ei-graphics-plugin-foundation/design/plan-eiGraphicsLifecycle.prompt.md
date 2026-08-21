Final Architecture Review — Revise Phase 1 Before Implementation

Review the current Phase 1 architecture proposal for "ei-graphics" and revise it based on the following requirements.

The current Phase 1 report is the source of truth for the repository-specific findings. Do not discard those findings. Preserve anything that remains valid and only change the parts identified below.

The goal is to produce a final architecture proposal, not implementation.

---

1. Do NOT Start Implementation

This is still a design/review phase.

Do NOT:

- modify "ei-graphics"
- modify R&D agents
- create new agents
- create new skills
- modify "extensions.yml"
- modify SpecKit configuration
- modify scripts
- modify vocabulary files

First produce the revised architecture.

Stop after the revised architecture and wait for explicit approval.

---

2. Re-evaluate Agent Specialization

The current report correctly identified that the R&D SpecKit agents expose extension mechanisms through ".specify/extensions.yml".

Do not interpret this as:

«"We must never modify R&D agents."»

Instead, use this decision hierarchy:

Existing R&D capability
        ↓
SpecKit extension hook
        ↓
2D constitution
        ↓
ei-graphics wrapper / skill
        ↓
Specialized R&D agent
        ↓
Fork/replace only if absolutely necessary

For every R&D agent, determine the lowest layer that can correctly implement the required 2D behavior.

The principle is:

«Reuse proven R&D infrastructure, but do not treat R&D agents as immutable black boxes.»

For example:

Generic implementation behavior
        +
2D constitution
        +
2D scope
        +
2D domain context
        +
post-implementation safety validation

may be sufficient without modifying "speckit.implement".

But if the required behavior cannot be safely expressed through hooks/context/wrappers, explicitly identify why an R&D agent must be modified.

Produce an updated matrix:

Agent| Reuse| Extend via Hook| Extend via Context| Wrap| Modify/Fork| Reason
speckit.workflow| | | | | | 
speckit.ado-ingest| | | | | | 
speckit.specify| | | | | | 
speckit.clarify| | | | | | 
speckit.plan| | | | | | 
speckit.tasks| | | | | | 
speckit.analyze| | | | | | 
speckit.implement| | | | | | 
speckit.bugdiagnosis| | | | | | 
speckit.constitution| | | | | | 
git agents| | | | | | 
code-review| | | | | | 

Do not create unnecessary copies of R&D agents.

---

3. CRITICAL — Verify Agent Orchestration

The previous report concluded that:

«"Agent programmatically invokes another agent as a function" is unsupported.»

Do NOT simply accept that conclusion.

Verify this against the actual GitHub Copilot environment used by this repository.

Investigate the actual supported mechanisms for:

- custom agents
- subagents
- agent delegation
- handoffs
- skills
- agent-to-agent execution
- Copilot coding agent
- Copilot CLI if relevant
- VS Code Copilot agent mode if relevant

The important question is:

«Can "ei-graphics" invoke the R&D SpecKit agents in a way that allows the workflow to continue automatically after the scope approval?»

Specifically determine whether this is technically possible:

ei-graphics
    ↓
scope analysis
    ↓
human approves scope
    ↓
speckit.specify
    ↓
speckit.plan
    ↓
speckit.tasks
    ↓
speckit.implement
    ↓
validation
    ↓
git commit
    ↓
PR

without requiring three separate manual handoff clicks.

---

4. Test the Orchestration Mechanism

Do not answer this only from documentation.

Inspect the actual repository configuration and available Copilot agent mechanisms.

If possible, perform a non-destructive proof of concept using temporary/test agents or existing agents.

The proof should answer:

Can Agent A delegate to Agent B?
Can Agent B return useful structured state?
Can Agent A continue after Agent B?
Can multiple agents execute sequentially?
Can the parent preserve context/state?
Can deterministic skills be invoked between agent stages?

Do not modify production files while testing this.

If the environment genuinely does not support autonomous agent-to-agent execution, clearly state:

Not supported because:
...

If it is supported, demonstrate the supported mechanism and revise the architecture accordingly.

Do not assume either answer.

---

5. Reconsider the IMPLEMENT Workflow

The desired behavior is:

User enters ADO story URL
        ↓
ei-graphics
        ↓
Story analysis
        ↓
2D domain analysis
        ↓
Scope / blast-radius analysis
        ↓
Human scope approval
        ↓
AUTOMATED ENGINEERING WORKFLOW
        ↓
SpecKit
        ↓
Implementation
        ↓
Build
        ↓
Tests
        ↓
Bug fixing
        ↓
Validation
        ↓
Commit
        ↓
PR

There should be one primary human checkpoint:

Scope approval

The user approves:

- relevant modules
- files
- symbols
- dependencies
- expected changes
- risks
- protected areas
- 2D/3D boundary
- blast radius

After that, automate as much as the actual Copilot environment supports.

Do not add unnecessary checkpoints.

---

6. Preserve ITERATE as a First-Class Workflow

This is one of the most important requirements.

If:

Story
 ↓
Implementation
 ↓
PR
 ↓
Reviewer rejects PR
 ↓
Screenshot attached
 ↓
Test fails

the agent must NOT restart from:

Story → scope → plan → implementation

Instead:

Existing PR
 ↓
Recover implementation state
 ↓
Recover original scope
 ↓
Recover domain context
 ↓
Retrieve review feedback
 ↓
Retrieve CI/test results
 ↓
Retrieve screenshots/attachments if available
 ↓
Diagnose
 ↓
Minimal fix
 ↓
Targeted tests
 ↓
Regression tests
 ↓
Safety validation
 ↓
Commit
 ↓
Push to SAME branch
 ↓
Update SAME PR

This should remain a separate "ITERATE" workflow.

---

7. Separate Analysis State from Implementation State

Formalize these as two concepts.

Analysis State

ADO story
Domain concepts
Vocabulary mappings
Relevant modules
Relevant files
Relevant symbols
Dependencies
Risk
Blast radius
Protected areas
Historical context
Approved scope

Implementation State

Branch
Commits
Current diff
Build results
Test results
PR
Review comments
CI results
Attachments
Screenshots

The transition should be:

IMPLEMENT
    ↓
Analysis State
    ↓
persisted in appropriate artifacts
    ↓
Implementation State
    ↓
PR

Then:

ITERATE
    ↓
Recover Analysis State
    +
Recover current Implementation State
    ↓
Diagnose only the delta

Prefer the existing "prEvidencePackage" and ".specify" artifacts before introducing a new database.

---

8. Strengthen the MVP

The current Phase 1 report defers several capabilities from MVP.

Reconsider that.

The purpose of this project is not merely:

«"Automate generic software development."»

The R&D team already has generic engineering agents.

The differentiator is:

«Safe, domain-aware modification of the AVEVA 2D legacy codebase.»

Therefore MVP must demonstrate at least:

2D domain context
+
2D vocabulary
+
scope resolution
+
human scope approval
+
2D/3D boundary protection
+
scope allowlist
+
minimal-change rules
+
implementation
+
targeted tests
+
regression validation
+
ITERATE workflow

Do not build an enormous domain knowledge system for MVP.

But do not remove the minimum domain/safety layer that makes this project meaningfully different from the generic R&D agents.

---

9. Domain Knowledge Strategy

Keep the existing automated vocabulary bootstrap idea.

Use:

Codebase
 ↓
Automated mining
 ↓
Candidate vocabulary
 ↓
2D SME validation
 ↓
Canonical vocabulary

Mine more than just:

Service
Repository
Command

Also consider:

- Managers
- Handlers
- Resolvers
- Factories
- Interfaces
- namespaces
- enums
- attributes
- tests
- domain classes
- method names
- comments
- documentation

Do not automatically assume every discovered term is domain truth.

The 2D team owns validation and enrichment.

---

10. Do Not Build RAG Prematurely

Use deterministic repository intelligence first where available:

- grep/search
- semantic search
- symbol search
- ".csproj" dependencies
- test discovery
- Git history

Only introduce more complex retrieval architecture if the actual repository demonstrates a need for it.

The objective is:

Story
 ↓
Relevant domain context
 ↓
Relevant code

not:

Story
 ↓
Entire repository
 ↓
LLM

---

11. Strengthen Deterministic Safety

Prioritize constraints that can be enforced by scripts/tools rather than prompts.

At minimum:

Scope guard

Approved files
      ↓
Actual git diff
      ↓
Compare
      ↓
Outside scope → BLOCK

2D/3D guard

Changed files
      ↓
Project/namespace/path classification
      ↓
3D detected
      ↓
BLOCK / explicit escalation

Final validation

Check:

Build passes
Targeted tests pass
Regression tests pass
No unexpected files
No 3D modifications
No obvious unrelated refactoring
Expected 2D components changed
Protected-area checks passed

These should not depend solely on LLM compliance.

---

12. Do Not Assume Runtime Call Graphs

The current report correctly notes that runtime call-graph analysis is unavailable.

Maintain that distinction.

Use:

Symbol references
+
.csproj dependencies
+
test relationships
+
Git history

for approximate blast-radius analysis.

Clearly label it as:

«Static approximation, not runtime certainty.»

Do not represent it as a complete dependency graph.

---

13. Historical Git Knowledge

Retain Git-history analysis as a useful contextual signal.

For relevant stories:

Current story
 ↓
Relevant component
 ↓
Historical changes
 ↓
Similar bug fixes
 ↓
Previous tests
 ↓
Implementation patterns

The agent should use historical changes as evidence, not blindly copy old code.

---

14. PR Evidence Package

Retain the existing idea of embedding structured context in the PR.

It should contain enough information to reconstruct the original reasoning:

{
  "adoLinkage": {},
  "domainContext": {},
  "scope": {},
  "affectedModules": [],
  "affectedFiles": [],
  "affectedSymbols": [],
  "risk": {},
  "blastRadius": {},
  "tests": {},
  "constitutionVersion": "",
  "scopeApproval": {},
  "implementationSummary": {}
}

Do not invent the exact schema until the existing implementation has been inspected.

The important requirement is:

«ITERATE should not need to rediscover the original analysis unnecessarily.»

---

15. Reviewer Feedback Must Be Evidence

Do not blindly obey comments such as:

"Change CableManager."

Instead:

Reviewer feedback
 ↓
Understand expected behavior
 ↓
Inspect current implementation
 ↓
Reproduce/validate
 ↓
Determine root cause
 ↓
Minimal correction

If the reviewer is correct, make the change.

If the reviewer identifies a symptom but not the root cause, fix the root cause.

If uncertain, stop and report the evidence.

---

16. Screenshot / Attachment Handling

Verify what the actual tooling supports.

Determine whether the agent can access:

- PR attachments
- inline screenshots
- ADO attachments
- CI logs
- test artifacts

Do not claim multimodal screenshot analysis is available unless the actual environment supports it.

If accessible:

Screenshot
 ↓
Extract observable evidence
 ↓
Correlate with test/code behavior
 ↓
Diagnose

If not accessible, explicitly identify the limitation.

---

17. Revised Architecture

Produce a final architecture diagram similar to:

                         GitHub Copilot
                              │
                              ▼
                     ┌─────────────────┐
                     │   ei-graphics   │
                     │    Router       │
                     └────────┬────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
             IMPLEMENT                    ITERATE
                │                           │
                ▼                           ▼
        2D Story Analysis             PR State Recovery
                │                           │
        2D Scope Resolution          Feedback Analysis
                │                           │
        Domain Context               Root Cause Analysis
                │                           │
                ▼                           ▼
        Human Scope Approval         Minimal Correction
                │                           │
                ▼                           │
        SpecKit/R&D Pipeline               │
                │                           │
        ┌───────┼────────┐                  │
        ▼       ▼        ▼                  │
      Specify  Plan     Tasks                │
                │                           │
                ▼                           │
          Implementation                    │
                │                           │
                ▼                           │
        Build / Test / Fix                 │
                │                           │
                ▼                           │
        2D Safety Validation ◄──────────────┘
                │
                ▼
          Git / Commit
                │
                ▼
             Create PR

Then explain which components are:

- existing R&D
- extended
- wrapped
- new
- deterministic
- LLM-driven

---

18. Required Final Decision Matrix

End the architecture report with:

Question| Decision| Evidence
Can R&D agents be reused?| | 
Can R&D agents be extended through hooks?| | 
Can agents delegate to other agents?| | 
Can IMPLEMENT be automated after scope approval?| | 
Can ITERATE run in one turn?| | 
Is SpecKit auto-initialization feasible?| | 
Where is human approval required?| | 
Which R&D agents need specialization?| | 
Which new EI agents are required?| | 
Which safety checks are deterministic?| | 
What must be deferred from MVP?| | 

Every decision must be based on the actual repository/environment where possible.

---

19. Final Deliverable

Produce the revised Phase 1 Architecture Proposal containing:

1. Current architecture
2. R&D agent inventory
3. Agent specialization matrix
4. Verified orchestration capabilities
5. Final architecture
6. IMPLEMENT workflow
7. ITERATE workflow
8. SpecKit initialization
9. Scope checkpoint
10. Domain knowledge strategy
11. Vocabulary strategy
12. Repository intelligence
13. Safety model
14. State model
15. PR feedback handling
16. Screenshot/attachment capabilities
17. MVP scope
18. Risks
19. Open questions
20. Final decision matrix

HARD STOP

After producing this revised architecture:

DO NOT IMPLEMENT ANYTHING.

Do not modify any repository files.

Do not create agents.

Do not create skills.

Do not modify R&D agents.

Do not modify "ei-graphics".

Do not modify SpecKit.

Wait for explicit approval of the revised architecture before proceeding to Phase 2 implementation.

The objective of this phase is to establish the correct architecture based on the actual capabilities of the repository and Copilot environment, not to begin coding prematurely.
