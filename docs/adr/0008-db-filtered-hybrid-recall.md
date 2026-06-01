# 8. DB-side filtered, thresholded, hybrid recall

Date: 2026-06-01

## Status

Accepted. Refines the retrieval contract from [ADR 0001](0001-architecture.md).

## Context

`banto_knowledge:recall/4` recalled the top-k chunks from bunko, then filtered
them by `repo` **in Erlang** (`filter_repo`). That has three problems:

- A `repo` filter applied after the top-k means the k slots are spent on other
  repos first, so a narrow query can return fewer (or zero) of the wanted repo's
  chunks even when they exist.
- Nothing dropped low-relevance hits, so an unrelated chunk could still be
  injected into the answer prompt as "context".
- Pure vector search misses exact identifiers and error codes, which matter a
  great deal for code retrieval (a function name, a `{error, Reason}` tag).

bunko v0.1.7 adds query-time options that solve all three at the database:
`filter` (a metadata map matched with the jsonb `@>` operator), `max_distance`
(a cosine-distance threshold), and `hybrid => true` (Reciprocal Rank Fusion of a
tsvector keyword lane with the vector lane; the GIN full-text index is created by
`bunko_store_pgvector:install/1`).

## Decision

Translate banto's recall options into bunko's query options in
`banto_knowledge:recall_opts/2`:

- The `repo` filter becomes `filter => #{~"repo" => Repo}` so the database
  narrows before ranking. `filter_repo` is removed.
- A configurable `max_distance` (`banto` env `max_distance`, default `undefined`
  = no threshold) drops irrelevant chunks.
- `hybrid` (`banto` env `hybrid`, default `true`) fuses keyword + vector lanes;
  the GIN index hybrid needs is provisioned by the existing `ensure_schema/0`.

The `Flow` step events and the no-repo behaviour are unchanged.

## Consequences

- A `repo`-scoped recall spends all k slots on that repo, so it returns the
  relevant chunks instead of being crowded out.
- Irrelevant chunks below the distance threshold are no longer injected as
  context, improving answer grounding.
- Hybrid recall surfaces exact-token matches (identifiers, error codes) that pure
  vector search ranked away. Defaulting it on costs one extra keyword lane per
  query; set `hybrid => false` to opt out.
- No new setup step: `install/1` already creates the full-text index.
