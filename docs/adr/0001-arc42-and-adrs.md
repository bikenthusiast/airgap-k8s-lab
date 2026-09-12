# ADR-0001: Architecture documentation with arc42 and ADRs

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

The project should not only work, it should be understandable to others: what
was built, and why this way rather than another? At the same time it is a
one-person project, so the documentation must not cost more than it returns.

## Decision

- The overall architecture is documented in **one** file following arc42
  (`docs/architecture.md`). Sections that are still open are marked *open*
  rather than omitted.
- Every significant decision gets its own short **ADR** in `docs/adr/`.
- A **work journal** (`docs/journal.md`) records what was done when and why,
  including dead ends and corrected misdiagnoses.
- Everything is written in English, since the project is meant to be readable
  internationally.

## Consequences

- Readers have a clear path: README → architecture → ADRs.
- ADRs are not rewritten after the fact. If a decision changes, a new ADR
  supersedes the old one.

## Alternatives considered

- **README only:** too shallow for rationale; decisions get lost.
- **arc42 split across twelve files:** too scattered for a project this size.
