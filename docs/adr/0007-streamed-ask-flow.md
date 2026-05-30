# 7. Streamed ask/recall flow

Date: 2026-05-30

## Status

Accepted. Builds on [ADR 0004](0004-dashboard.md) and
[ADR 0005](0005-streamed-background-indexing.md).

## Context

The dashboard returned only end results: recall as a one-shot hit list, ask as a
single answer after a multi-second blocking LLM call, with nothing in between.
The retrieval that grounds an answer - which chunks were recalled, from which
repo/path, then the prompt build and the LLM call - was invisible. For a RAG
concierge that opacity is the opposite of trust, and `/workflows` (which can show
agent progress) is unavailable while a session is busy.

ADR 0005 established the held-SSE + Datastar-patch pattern for a *shared,
long-lived* background process (indexing, via a hub). An ask/recall is different:
it is *per-request, private to the asker, and finite*.

## Decision

- **Instrument with a callback, not a new return shape.** `banto_knowledge:ask/4`
  and `recall/4` take a `fun((step()) -> ok)` invoked at each stage (recall,
  prompt, llm, answer, error). `ask/3` / `recall` keep their behaviour with a
  no-op callback, so `banto:ask/2`, `recall/2` and the MCP tools are unchanged -
  the same precedent as `banto_indexer:index/3 -> index/4`.
- **No re-decomposition of `bunko:recall`.** The flow calls `bunko:recall`
  whole (preserving its `limit` validation and semantics) and emits one `recall`
  step with the hit sources, rather than re-implementing embed+search. Coarser,
  but correct and dependency-faithful.
- **No hub.** The flow is private to one requester and produced inside the held
  request process; there is no shared state to fan out. One flow per connection,
  so no cross-viewer leakage - achieved precisely *because* there is no hub.
- **Held but finite SSE.** `GET /dashboard/flow/stream` returns `{stream,...}`;
  the handler patches `#flow` live per step, patches `#answer` with the result,
  then closes the body with `fin` and exits. Unlike the index stream (infinite),
  this connection ends when the answer lands.
- **A monitored worker, killed on disconnect.** The ask/recall runs in a
  `spawn_monitor` worker that messages steps back; the request process patches
  frames and keepalives. On client disconnect a frame send fails and the handler
  `exit(Worker, kill)`s it - a linked `exit(normal)` would NOT stop the worker,
  leaking the in-flight LLM call.
- **The question/mode ride the datastar query param.** Datastar `@get` serialises
  the signal store as one `datastar=<json>` param; the handler decodes it with
  `datastar:read_signals/1` (it does NOT support arbitrary `?q=` keys). `mode`
  (`ask` | `recall`) selects synthesis vs retrieval-only.
- **One registered Nova `stream` handler, dispatched on path** (`banto_stream`):
  `/dashboard/flow/stream` -> `banto_flow_stream`, else -> `banto_index_stream`.

## Consequences

- The user watches recall (with cited repo/path per chunk) and synthesis happen,
  then the answer (ask) or hit list (recall) lands - both surfaces show their flow.
- `ask/3`, `recall/2` and the MCP surface are behaviourally untouched.
- The flow is ephemeral and single-client: no persistence, no replay.
- This is banto's first *finite* held SSE; the `fin` + `exit(normal)` is the
  termination contract. Requires the dashboard-role node to have the LLM/embedder
  config (it shares the same `banto` app env).
