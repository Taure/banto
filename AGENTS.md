# AGENTS.md

Working agreement for agents and contributors on **banto** (番頭, the head clerk
who runs the shop) - a multi-agent repo concierge for the BEAM. It indexes your
repositories into a shared semantic memory and answers questions across them,
exposed as MCP tools so a Claude Code session in any repo can use it.

banto is the **showcase consumer** of the gakudan multi-agent ecosystem: it wires
all five pillars together in one service.

## Ecosystem

All under https://github.com/Taure:

- **[gakudan](https://github.com/Taure/gakudan)** - agent orchestration runtime.
  banto uses its `gakudan_llm` backend (pointed at sekisho) and, from P2, its
  fanout router for the review swarm.
- **[bunko](https://github.com/Taure/bunko)** - agent memory + RAG. banto's
  semantic store (`bunko_store_pgvector`), embedder seam, and consolidation.
- **[sekisho](https://github.com/Taure/sekisho)** - LLM gateway / control plane.
  All of banto's LLM + embedding traffic routes here for keys, budgets, audit.
- **[madoguchi](https://github.com/Taure/madoguchi)** - MCP *server* framework.
  banto exposes `recall` / `ask` / `index_repo` as MCP tools through it.
- **[saiten](https://github.com/Taure/saiten)** - eval/scoring + CI gate. From
  P2, grades the review swarm against a planted-bug benchmark.

## How it fits together

```
banto_indexer    walk a repo -> chunk -> embed (banto_embedder/sekisho) -> bunko
banto_knowledge  recall from bunko -> synthesise via gakudan_llm (sekisho)
banto_mcp_*      madoguchi tools: recall / ask / index_repo
banto_config     all wiring from the `banto` app env (offline stub defaults)
```

All repos share one bunko namespace; each memory carries `repo`/`path`/`kind`
metadata, so recall spans every repo and a `repo` filter narrows it.

## Roadmap

- **P1 (now):** spine + cross-repo knowledge + the MCP surface.
- **P2:** PR review swarm (gakudan fanout grounded by bunko recall), saiten CI
  gate, a CLI, a GitHub Action.
- **P3:** nightly maintenance agents (dep/doc drift) + a Nova + Datastar
  dashboard (same stack as gakudan_liveboard, not Arizona).

## Commands

```bash
docker compose up -d        # pgvector Postgres for kura (port 5559)
rebar3 compile
rebar3 eunit
rebar3 ct                   # against Docker pgvector Postgres
rebar3 fmt                  # CI runs fmt --check
rebar3 xref
rebar3 dialyzer
rebar3 ex_doc
```

## Conventions

- OTP 29+. The `~"..."` sigil, never `<<"...">>`. No `lists:foldl/foldr`.
- Adjacent `~""` literals do NOT concatenate (unlike `"..."`); keep a binary on
  one literal.
- bunko metadata round-trips through jsonb, so read it with **binary** keys
  (`~"repo"`), never atoms.
- JSON via the OTP `json` module. `?LOG_*` macros with `#{...}` map reports.
- `{vsn, git}` - version derives from git tags. Default to zero comments.

## Decisions live in ADRs

Read [docs/adr/](docs/adr/) before changing the indexing, retrieval, or surface
contracts. Write a new ADR (Nygard format) for any such change.

## Git and PRs

Conventional commits. Always open a PR - never push to `main`. Every merge to
`main` tags a release.
