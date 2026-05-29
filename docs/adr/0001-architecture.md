# 1. Architecture and pillar wiring

Date: 2026-05-29

## Status

Accepted (P1).

## Context

banto is the showcase consumer of the gakudan multi-agent ecosystem. Its job is
twofold: be genuinely useful (a concierge over the user's many repositories) and
prove that the five pillars - gakudan, bunko, sekisho, madoguchi, saiten -
compose into one coherent service rather than five separate demos. Where banto
hits a gap in a pillar, the gap is fixed *in the pillar* as a general feature
(e.g. gakudan's `base_url` opt, sekisho's embeddings lane, bunko's `install/1`),
not worked around here.

## Decision

A plain OTP service (not Nova in P1; the dashboard in P3 will add Nova +
Datastar) with these seams:

- **Memory: bunko.** One shared namespace holds every repo's chunks; each memory
  carries `repo`/`path`/`kind` metadata. Cross-repo recall is therefore a single
  similarity search, and a `repo` filter is a metadata post-filter. The schema is
  provisioned with `bunko_store_pgvector:install/1` at setup. Re-indexing a repo
  deletes its prior memories first, so indexing is idempotent per repo.
- **LLM + embeddings: sekisho.** All model traffic routes through the gateway via
  configuration only - the `gakudan_llm_anthropic` backend with a `base_url`
  pointing at sekisho's Anthropic lane, and `banto_embedder` posting to sekisho's
  OpenAI embeddings lane. This gives central keys, budgets, and audit for free.
  Offline stub defaults (`bunko_embedder_stub`, `gakudan_llm_stub`) keep CI
  deterministic and network-free.
- **Surface: madoguchi.** `recall`, `ask`, and `index_repo` are MCP tools served
  over Streamable HTTP, so a Claude Code session in any repo consumes banto
  directly. This is what makes it "help me in my repos" rather than a standalone
  bot.
- **Answering: a single completion, not orchestration.** P1 `ask` recalls
  context and asks the LLM once. gakudan's multi-agent fanout is reserved for the
  P2 review swarm, where parallel specialist agents earn their keep.

Everything is read from the `banto` application environment via `banto_config`,
so the same code runs offline (stubs) or against a live sekisho + pgvector.

## Consequences

**Positive.**

- One shared namespace makes cross-repo retrieval trivial and the `repo` filter
  cheap.
- Routing LLM/embeddings through sekisho is config-only, thanks to the upstream
  `base_url` and embeddings-lane work - no bespoke client code in banto.
- Stub defaults mean CI needs only a pgvector Postgres, no API keys.

**Negative.**

- A single namespace means re-indexing scans the namespace to delete a repo's old
  memories; fine at repo scale, not at millions of chunks (revisit with a
  metadata-indexed delete if needed).
- Chunking is line-bounded and naive (fixed line count); good enough for
  retrieval, not semantically aware. A smarter chunker is a later refinement.
- Recall quality depends on the configured embedder; the offline stub is for
  tests only and is not semantically meaningful.
