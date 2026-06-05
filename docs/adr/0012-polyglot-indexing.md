# 12. Polyglot indexing

Date: 2026-06-05

## Status

Accepted. Extends [ADR 0001](0001-architecture.md); chunking seam from
[ADR 0006](0006-semantic-chunking.md) is unchanged.

## Context

The indexer only accepted BEAM-flavoured extensions (`.erl .hrl .ex .exs .md
.config .src .app`), so a workspace with game-client SDKs (Lua, Dart,
TypeScript, C#, C++, GDScript, Go, Defold scripts) indexed nothing but their
markdown. Recall over a mixed workspace answered doc questions and went blind
on source. Engine build output (Unity `Library`, Unreal
`Intermediate`/`Saved`/`Binaries`/`DerivedDataCache`, Godot `.godot`, Dart
`.dart_tool`, generic `build`/`dist`/`vendor`) also contains generated files
with wanted extensions, which would pollute the index.

## Decision

- Extend `?EXTS` with the common source extensions for the SDK languages we
  index: `.lua .dart .ts .js .mjs .cs .cpp .cc .h .hpp .gd .go .script
  .gui_script .render_script`.
- Extend `?SKIP_DIRS` with the engine and toolchain output dirs above so
  generated code never reaches the embedder.
- No new chunking strategies: every new extension falls through
  `banto_chunk:strategy/1` to the line slicer, with `kind => ~"code"`. Semantic
  strategies per language remain future ADR material.

## Consequences

- Non-BEAM repos get full source coverage; chunk counts (and embedding spend)
  grow accordingly. The content-hash cache still dedupes re-indexing.
- Line-sliced chunks for the new languages lack `symbol` metadata until a
  per-language strategy lands behind the ADR 0006 seam.
- A repo whose `vendor`/`build`/`dist` holds first-party source is skipped;
  acceptable for the workspaces we target.
