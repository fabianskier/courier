---
name: architecture-adr
description: Analyze a problem, compare options and record architecture decisions as ADRs with Mermaid diagrams. Use before building a feature or system, when choosing between technologies, or when asked for an analysis, architecture or decision record.
---

# Architecture analysis and decision records

Use this before any code. The output is documents the human reviews; never decide for the human.

## Process

1. **Analysis** (`docs/analysis.md`)
   - Problem and goals, in a few sentences.
   - Functional requirements, as short testable statements.
   - Non-functional requirements **with numbers or an explicit "TBD"** (throughput, latency, retention, availability).
   - Constraints (team size, budget, existing stack, no API key, etc.).
   - Non-goals: what is explicitly out of scope.
   - Risks and open questions, each with an owner or next step.
2. **Architecture** (`docs/architecture.md`)
   - Context diagram: the system, its users and external systems.
   - Container diagram: deployable parts and how they talk.
   - One sequence diagram per critical flow (the happy path and the main failure path).
   - Data model sketch for the core entities.
   - Use Mermaid code blocks so diagrams render on GitHub.
3. **Decisions** (`docs/decisions.md`): one ADR per significant choice (see format).
4. **Hand-off**: turn the accepted decisions into OpenSpec changes (proposal, design, specs, tasks).

## What deserves an ADR

A choice that is costly to reverse or that a newcomer would question: language/framework, data store, API style, real-time transport, auth, hosting, how to split services. Skip trivial choices.

## ADR format (same as the project's `docs/decisions.md`)

```markdown
## <Decision title: what we chose>

**Status:** proposed | accepted (YYYY-MM) | superseded by <title>
**Context:** the forces and constraints that make this a decision.
**Options considered:** each option with one line on its trade-offs.
**Decision:** what we chose, in one or two sentences.
**Consequences:** what gets easier, what gets harder, what we must now do.
```

## Rules

- Always compare **at least two real options** and say why the others lost. A decision with one option is not a decision.
- Prefer boring, proven choices unless the context gives a concrete reason not to.
- Tie every decision to a requirement or constraint from the analysis.
- Never delete or rewrite an accepted ADR. Mark it `superseded by …` and add a new one.
- Write `Status: proposed` and stop; the human sets `accepted`.
- Keep documents short. If a section has nothing to say, write "None" rather than padding.
- Write everything in English.
