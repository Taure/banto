# 5. Streamed background indexing

Date: 2026-05-30

## Status

Accepted. Builds on [ADR 0004](0004-dashboard.md).

## Context

Indexing a repo is slow and unbounded: a large repo (gakudan, ~285 chunks) is
hundreds of embed calls. Driven synchronously through the `index_repo` MCP tool
or a blocking HTTP request, it overruns response timeouts and shows the caller
nothing until it either finishes or dies. The dashboard could only display a
static `GROUP BY` summary; you could not watch an index happen.

ADR 0004 deferred held SSE ("an on-demand memory query does not need a held
connection") but flagged that a live process is exactly where it fits. Indexing
is that live process.

## Decision

- **Indexing is a supervised background job.** `banto_index_sup` is a
  `simple_one_for_one` supervisor of `banto_index_job` workers (`temporary`, so a
  failed index does not restart-loop). A job runs `banto_indexer:index/4` and
  exits; it survives the page that started it.
- **Progress is a callback, not a new return shape.** `banto_indexer:index/4`
  takes a `fun((progress()) -> ok)` invoked per file (`index/3` passes a no-op,
  so existing callers and the MCP tool are unchanged). The job's callback reports
  to a hub.
- **A hub fans progress out.** `banto_index_hub` (one gen_server) holds the
  latest `progress()` per repo and a monitored set of subscribers. Jobs
  `report/1`; SSE connections `subscribe/0` (getting a snapshot) and receive each
  update. Monitors drop subscribers on disconnect, so no manual cleanup.
- **Held SSE for the live view.** `banto_dashboard_page:index_stream/1` returns
  `{stream, ...}`; a registered Nova `stream` handler (`banto_index_stream`, the
  same mechanism sekisho uses) holds the connection, subscribes to the hub, and
  patches `#jobs` via Datastar on every update. `POST /dashboard/index` starts a
  job; `data-on-load` opens the stream.

## Consequences

- Large repos no longer time out: the request returns immediately, the job runs
  in the background, and progress streams live.
- The MCP `index_repo` surface is untouched (still synchronous via `index/3`).
- The held SSE is the first long-lived connection in banto; the hub's monitors
  bound its bookkeeping to live subscribers.
- A job's progress is in-memory only (the hub). A restart loses in-flight job
  state; the indexed data itself is durable in bunko. Persisting job history is
  out of scope.
