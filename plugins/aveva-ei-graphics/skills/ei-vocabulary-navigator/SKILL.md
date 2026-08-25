---
name: ei-vocabulary-navigator
description: 'Resolve EI domain terms into vocabulary URIs, model classes, repositories, services, and command paths.'
license: MIT
allowed_actions:
  - run
  - help
allowedTools:
  - read
  - search
---

# EI Vocabulary Navigator

## Goal

Map EI Graphics domain terms and URI fragments to the concrete implementation path used in the codebase.

## Inputs

- `term` (required): EI domain term, URI fragment, or class-like name
- `contextText` (optional): extra text to disambiguate the term

## Output contract

Return JSON with:

- `term`
- `matchedUris`
- `domainModels`
- `repositoryInterfaces`
- `services`
- `commands`
- `ambiguities`
- `confidence`: number in range [0,1]

## Rules

1. Source mappings from vocabulary constants and `[ClassMapping]` or `[PropertyMapping]` attributes when available.
2. Keep ambiguous alternatives instead of forcing one label.
3. If confidence is below 0.7, mark the result as ambiguity-heavy for SME review.

## Lifecycle stage

`scripts/Invoke-EiDomainContextStage.ps1` runs the `domain-context` stage of the IMPLEMENT lifecycle.

The stage accepts a human-confirmed list of domain IDs selected by the agent. The agent reads the
complete ADO work item (title, description, acceptance criteria, parent feature, and any accessible
images), reasons about what the story is about, selects one or more domain IDs from
`references/domain-skill-registry.json`, presents a plain-language understanding to the user, and
obtains explicit confirmation before the stage runs.

- `-SelectedDomainIds` receives the agent-chosen domain ID(s) from the registry.
- `-HumanConfirmed` must be set; the stage blocks without it.
- For each confirmed ID the stage calls `Read-EiDomainSkillContext.ps1`, which parses the
  corresponding SKILL.md and extracts the `summary` and Key Files table.
- Writes the `domain-context` artifact (`schemas/domain-context.schema.json`, owned by
  `ei-workflow-state`). The artifact includes `humanConfirmation: { "status": "confirmed" }`.
- An empty `SelectedDomainIds` with `-HumanConfirmed` is valid: the artifact is written with an
  empty `domainSkills` array when the agent and user agree that no registered domain applies.
- A domain ID that is not present in the registry is a blocking error (`EIVN-DOMAIN-NOT-REGISTERED`).

## Implementation status

Lifecycle stage implemented in `scripts/Invoke-EiDomainContextStage.ps1` with agent-driven
selection and human-in-the-loop confirmation. Initial ontology-backed dataset for term resolution
lives in `data/vocabulary-map.json`, with deterministic lookup in
`scripts/Invoke-EiVocabularyNavigator.ps1` (used independently by the bug-reproducer skill).
