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
  banto uses its `gakudan_llm` backend (pointed at sekisho, wrapped in
  `gakudan_llm_retry`/`gakudan_llm_fallback`), its fanout router for the review
  swarm, and structured output (`response_format` + `gakudan_validator_json`).
- **[bunko](https://github.com/Taure/bunko)** - agent memory + RAG. banto's
  semantic store (`bunko_store_pgvector`), batched cached embedding
  (`remember_many`), hybrid recall, metadata filters, and consolidation.
- **[sekisho](https://github.com/Taure/sekisho)** - LLM gateway / control plane.
  All of banto's LLM + embedding traffic routes here for keys, budgets, audit
  (reached via gateway config, not a dep).
- **[madoguchi](https://github.com/Taure/madoguchi)** - MCP *server* framework.
  banto exposes `recall` / `ask` / `index_repo` as annotated MCP tools and its
  indexed repos as MCP resources, over HTTP and stdio.
- **[saiten](https://github.com/Taure/saiten)** - eval/scoring + CI gate. Grades
  the review swarm against a planted-bug benchmark (`banto_review_eval`) with a
  self-consistency judge, JUnit output, and an optional regression gate.

## How it fits together

```
banto_indexer    walk a repo -> chunk -> batch-embed (cached) -> bunko remember_many
banto_knowledge  hybrid recall from bunko (DB repo filter + distance threshold)
                 -> synthesise via a resilient gakudan_llm (retry/fallback, sekisho)
banto_mcp_*      madoguchi tools (recall/ask/index_repo, annotated) + repo
                 resources, over HTTP or stdio (banto_cli mcp-stdio)
banto_review     fanout swarm; reviewers emit schema-constrained structured findings
banto_review_eval saiten gate: self-consistency judge + JUnit + optional regression
banto_config     all wiring from the `banto` app env (offline stub defaults)
```

All repos share one bunko namespace; each memory carries `repo`/`path`/`kind`
metadata, so recall spans every repo and a `repo` filter (pushed into the DB as a
metadata filter) narrows it.

## Roadmap

- **P1 (done):** spine + cross-repo knowledge + the MCP surface.
- **P2 (done):** PR review swarm (gakudan fanout grounded by bunko recall),
  saiten CI gate (`banto_review_eval`), the `banto_cli` escript, an opt-in
  GitHub Action.
- **P3a (done):** nightly maintenance - `banto_dep_audit` (deterministic) +
  `banto_maintainer_docs` (gakudan doc-drift agent), combined by
  `banto_maintenance`, surfaced via the `maintain` CLI subcommand and a scheduled
  GitHub Action that opens an issue.
- **P3b (done):** a Nova + Datastar memory console (`banto_router` +
  `banto_dashboard_page`) on a second cowboy listener (:8081; MCP stays on :8080):
  indexed-repo summary + live recall search via Datastar `@post`. Same stack as
  gakudan_liveboard, not Arizona.
- **P4 (done):** adopt the pillars' new capabilities - DB-side filtered +
  thresholded + hybrid recall (ADR 0008), resilient LLM backends (ADR 0009), MCP
  annotations + stdio transport + repo resources (ADR 0010), review-eval
  self-consistency judge + JUnit + regression gate (ADR 0011), structured review
  findings, and batched cached indexing.

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
