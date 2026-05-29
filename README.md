# banto

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
  and stores it in bunko.
- `banto_knowledge` recalls the most relevant chunks for a question and
  synthesises a grounded answer (with source citations) via the configured LLM.
- `banto_mcp_*` exposes `recall`, `ask`, and `index_repo` over Streamable HTTP.
- `banto_review` fans out specialist reviewer agents (security, conventions,
  tests, architecture) over a diff via gakudan, each grounded by the same
  recalled context; `banto_review_eval` is a saiten benchmark that gates the
  swarm in CI.

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
it to use the tools directly. A CLI (`rebar3 escriptize` -> `banto_cli
review|ask|recall|index`) and an opt-in PR-review GitHub Action are also
included.

## Configuration

Defaults keep CI offline (a deterministic stub embedder + stub LLM). For real
use, route through a [sekisho](https://github.com/Taure/sekisho) gateway - see
`m:banto_config` and `config/dev_sys.config.src`.

## Status

P1 (indexing, recall, ask, MCP surface), P2 (PR review swarm + saiten gate + CLI
+ GitHub Action), and P3a (nightly maintenance: dependency + doc-drift report
via `banto_maintenance`, a `maintain` CLI subcommand, and a scheduled Action) are
done. P3b (a Nova + Datastar dashboard) is on the roadmap.

## License

Apache-2.0.
