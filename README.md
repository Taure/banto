# banto

[![CI](https://github.com/Taure/banto/actions/workflows/ci.yml/badge.svg)](https://github.com/Taure/banto/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Taure/banto)](LICENSE.md)
[![Erlang](https://img.shields.io/badge/erlang-29%2B-blue)](.tool-versions)

**banto** (番頭, the head clerk who runs the shop) is a multi-agent repo
concierge for the BEAM. Point it at your repositories; it indexes them into a
shared semantic memory and answers questions across them - exposed as MCP tools,
so a Claude Code session in any repo can `recall`, `ask`, or `index_repo`.

banto is the showcase consumer of the [gakudan](https://github.com/Taure/gakudan)
multi-agent ecosystem - it wires five pillars into one service:

| Pillar | Role in banto |
| --- | --- |
| [gakudan](https://github.com/Taure/gakudan) | LLM backend (via sekisho); fanout review swarm (P2) |
| [bunko](https://github.com/Taure/bunko) | the pgvector semantic store + embedder seam |
| [sekisho](https://github.com/Taure/sekisho) | gateway for LLM + embedding keys, budgets, audit |
| [madoguchi](https://github.com/Taure/madoguchi) | exposes recall / ask / index_repo as MCP tools |
| [saiten](https://github.com/Taure/saiten) | grades the review swarm in CI (P2) |

## How it works

All repos share one bunko namespace; each memory carries `repo`, `path`, and
`kind` metadata, so recall spans every repo and an optional `repo` filter narrows
it.

- `banto_indexer` walks a repo, chunks its source and docs, embeds each chunk,
  and stores it in bunko in one batched, content-hash-cached embedding call per
  file, so re-indexing is fast.
- `banto_knowledge` recalls the most relevant chunks for a question - hybrid
  (keyword + vector) search, narrowed at the database by a `repo` metadata filter
  and a distance threshold - and synthesises a grounded answer (with source
  citations) via the configured LLM, wrapped in a retry/fallback backend so
  transient upstream errors do not fail the call.
- `banto_mcp_*` exposes `recall`, `ask`, and `index_repo` as MCP tools (with
  read-only / destructive annotations) and the indexed repos as MCP resources,
  over Streamable HTTP or a stdio transport (`banto_cli mcp-stdio`).
- `banto_review` fans out specialist reviewer agents (security, conventions,
  tests, architecture) over a diff via gakudan, each grounded by the same
  recalled context and returning schema-constrained structured findings;
  `banto_review_eval` is a saiten benchmark (self-consistency judge, JUnit output,
  optional regression gate) that gates the swarm in CI.
- `banto_router` + `banto_dashboard_page` serve a Nova + Datastar memory console
  on `:8081`: the indexed-repo summary and a live recall search.

## Quick start

```bash
docker compose up -d            # pgvector Postgres on :5559
rebar3 shell                    # starts banto with config/dev_sys.config.src
```

```erlang
ok = banto:ensure_schema().
{ok, _} = banto:index("/path/to/kura", #{name => ~"kura"}).
{ok, Hits} = banto:recall(~"how is the connection pool configured?", #{limit => 5}).
{ok, Answer} = banto:ask(~"what does kura_query:where/2 expect?", #{repo => ~"kura"}).
{ok, Reviews} = banto_review:review(Diff, #{repo => ~"kura"}), banto_review:format(Reviews).
```

The MCP server starts on `:8080` at `/mcp`; point your Claude Code MCP config at
it to use the tools directly, or run `banto_cli mcp-stdio` to serve the same tools
and repo resources over stdio for a desktop client that launches a local server. A
CLI (`rebar3 escriptize` -> `banto_cli review|ask|recall|index|maintain|mcp-stdio`)
and an opt-in PR-review GitHub Action are also included.

## Configuration

Defaults keep CI offline (a deterministic stub embedder + stub LLM). For real
use, route through a [sekisho](https://github.com/Taure/sekisho) gateway - see
`m:banto_config` and `config/dev_sys.config.src`.

## Status

All phases are in: P1 (indexing, recall, ask, MCP surface), P2 (PR review swarm +
saiten gate + CLI + GitHub Action), P3a (nightly maintenance: dependency +
doc-drift report via `banto_maintenance`, a `maintain` CLI subcommand, a
scheduled Action), and P3b (a Nova + Datastar memory console on `:8081` -
indexed-repo summary + live recall search).

## License

Apache-2.0.
