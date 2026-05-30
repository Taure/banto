# 7. Streamed ask/recall flow (observe a hub, like the liveboard)

Date: 2026-05-30

## Status

Accepted. Builds on [ADR 0004](0004-dashboard.md) and
[ADR 0005](0005-streamed-background-indexing.md). Supersedes this ADR's own
first cut (a per-request, click-triggered, finite SSE), which did not work in the
browser - see Consequences.

## Context

The dashboard showed only end results; the retrieval that grounds an answer
(which chunks, from where, then the prompt and the LLM call) was invisible. We
want to watch a flow happen live.

The first design ran the ask *inline* in a held SSE opened by a button
(`data-on-click="@post(...)"`). It worked under `curl` but never in the browser:
**Datastar v1 has no `data-on-load`** (banto used it, so the index SSE never
opened), and - separately - the dashboard's HTML was served with **no
`Cache-Control`**, so the browser kept a stale page and no fix ever reached it.
gakudan_liveboard, the working reference, does none of this: it **observes** a
shared hub over an SSE opened on load with **`data-init`**.

## Decision

Adopt the gakudan_liveboard model.

- **A flow hub.** `banto_flow_hub` (one gen_server) holds the most recent flow's
  steps + answer and pub/subs to subscribers; a `recall`/`start` step begins a
  fresh flow. Subscribers are monitored and dropped on disconnect.
- **`ask`/`recall` report to the hub by default.** `banto:ask/2` and `recall/2`
  pass `fun banto_flow_hub:report/1` as the flow callback (the `index/3 ->
  index/4` precedent), so a call from **anywhere on the node** - a console, the
  MCP tools, the CLI - streams its flow. `report/1` is a no-op when the hub is
  not running.
- **The dashboard observes; it does not trigger.** `banto_flow_stream` is a
  registered Nova `stream` handler that `stream_reply`s, `subscribe`s to the hub,
  patches `#flow` and `#answer`, and **holds the connection (never returns)** -
  exactly `gakudan_liveboard_sse`. Opened on page load with
  `data-init="@get('/dashboard/flow/stream')"` (GET, no body, no click). The
  index panel uses the same `data-init` mechanism for its `#jobs` SSE; both
  panels are observe-only (trigger work from a console / MCP).
- **`Cache-Control: no-store`** on the dashboard HTML and assets, so a fresh
  build always loads.

## Consequences

- Run `banto:ask`/`recall` (console or MCP) on the dashboard node and the flow
  streams into the page live, no refresh, no button.
- No reliance on Datastar `data-on-click`/`data-bind`, which did not bind in the
  target browser; `data-init` + SSE is the proven path.
- `banto:ask/3`, `recall/3` and the MCP surface are behaviourally unchanged (they
  just also emit flow steps).
- Node-scoped: the hub is per-node, so the dashboard shows flows from *its* node.
  Cross-node aggregation (distributed `pg`) is deferred.
