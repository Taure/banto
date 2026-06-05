# 6. Pluggable, semantic-aware chunking

Date: 2026-05-30

## Status

Accepted (markdown strategy first). Builds on [ADR 0001](0001-architecture.md).

## Context

`banto_indexer:chunk/1` slices every file into fixed 60-line blocks regardless
of content. A 60-line boundary cuts functions and doc sections in half, so a
recall hit is an arbitrary window rather than a coherent unit, and chunks carry
no symbol/section label. We want meaning-aware boundaries without a heavy parser
or a schema change.

## Decision

- **A chunker seam.** `banto_chunk:chunk(Path, Content)` dispatches by extension
  and returns `{Text, MetaFragment}` pairs. `banto_indexer:store_chunks`
  `maps:merge`s the fragment into the base metadata
  (`repo`/`path`/`kind`/`chunk`), so a strategy can add fields (e.g. `symbol`)
  with no schema or embedding-dimension change - metadata is jsonb and additive.
- **`chunk/1` stays the line fallback.** It keeps its `binary() -> [binary()]`
  contract and unit tests; the dispatcher wraps it as `{Text, #{}}` for any kind
  without a strategy. Zero regression for non-markdown files.
- **Markdown strategy first** (`banto_chunk_markdown`): split on `#`..`######`
  headings into sections, each tagged `symbol => <heading>`; content before the
  first heading is an untagged preamble. **Fence-aware** - a `#` line inside a
  backtick or tilde code block does not start a section. A section longer than the line
  cap is sub-split by lines, all sharing the heading.
- **Erlang/Elixir form strategy is deferred** to a follow-up; the seam is built
  so it drops in as another `banto_chunk` callback module.

Heuristic, not `erl_parse`/a full Markdown AST: tolerant of non-compiling files
and cheap. The oversize line-split is the safety net.

## Consequences

- Markdown recall returns whole heading sections, labelled by `symbol`.
- Changing boundaries re-embeds, so adopting it is a **full re-index** (idempotent
  per repo). No data-model or dimension change.
- New surface is small: `banto_chunk` + one strategy module + a `store_chunks`
  merge. `chunk/1` and its callers/tests are untouched.
- Context-header prefixing (embedding `%% module:fun/arity\n` ahead of the raw
  text) is left as a future option; v1 embeds the raw chunk.
