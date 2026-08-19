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

`scripts/Invoke-EiDomainContextStage.ps1` runs the `domain-context` stage of the IMPLEMENT lifecycle. Every
lookup is delegated to `Invoke-EiVocabularyNavigator.ps1`; the stage only decides which candidate terms
survive.

- The caller proposes candidate terms; `references/domain-pack-policy.json` disposes of them. A term
  survives only if the story text mentions it, the navigator matched at least one URI, and its
  confidence clears the floor.
- The navigator is called with the term alone, never with the story text. Passing the story as context
  makes every candidate match the union of everything the story mentions, which would hand the scope
  resolver a far wider domain than the terms it was given.
- Terms that do not survive are recorded in `unresolvedTerms`, and ambiguous terms in `ambiguities`, so
  the narrowing stays auditable rather than silent.
- Writes the `domain-context` artifact (`schemas/domain-context.schema.json`, owned by `ei-workflow-state`)
  and blocks the stage when too little resolves, rather than emitting a thin context.

## Implementation status

Initial ontology-backed dataset lives in `data/vocabulary-map.json`, with deterministic lookup implemented in `scripts/Invoke-EiVocabularyNavigator.ps1` and the lifecycle stage in `scripts/Invoke-EiDomainContextStage.ps1`.
