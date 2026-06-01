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
| [0004](0004-dashboard.md) | Nova + Datastar memory dashboard |
| [0005](0005-streamed-background-indexing.md) | Streamed background indexing |
| [0006](0006-semantic-chunking.md) | Semantic chunking |
| [0007](0007-streamed-ask-flow.md) | Streamed ask/recall flow (observe a hub) |
| [0008](0008-db-filtered-hybrid-recall.md) | DB-side filtered, thresholded, hybrid recall |
| [0009](0009-resilient-llm-backends.md) | Resilient LLM backends (retry + fallback) |
| [0010](0010-mcp-enrichments-stdio-resources.md) | MCP annotations, stdio transport, repo resources |
| [0011](0011-review-eval-upgrades.md) | Review-eval: self-consistency judge, JUnit, regression gate |
