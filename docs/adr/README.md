# Architecture Decision Records

The decision log for banto. Each ADR captures the *why* behind the indexing,
retrieval, or surface contracts.

## When to write one

Write a new ADR for any change to the indexing model, the retrieval/answer
contract, the MCP surface, or how the pillars are wired. Small fixes that
preserve contracts do not need one.

Use the [Nygard format](https://github.com/joelparkerhenderson/architecture-decision-record):
**Context**, **Decision**, **Consequences**. Number sequentially; never rewrite
a merged ADR - supersede it.

## Index

| ADR | Title |
| --- | --- |
| [0001](0001-architecture.md) | Architecture and pillar wiring |
| [0002](0002-review-swarm.md) | PR review swarm via gakudan fanout |
| [0003](0003-maintenance.md) | Nightly maintenance: deterministic deps + LLM doc-drift |
