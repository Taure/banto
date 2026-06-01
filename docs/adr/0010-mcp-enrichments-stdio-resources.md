# 10. MCP tool annotations, stdio transport, and repo resources

Date: 2026-06-01

## Status

Accepted. Extends the MCP surface from [ADR 0001](0001-architecture.md).

## Context

banto's MCP surface (`recall`, `ask`, `index_repo`) was tool-only, HTTP-only, and
gave clients no behavioural hints. madoguchi v0.1.6 adds three things banto can
adopt:

- Optional `annotations/0` / `output_schema/0` tool callbacks. Annotations let a
  client know which tools are safe to call without confirmation (read-only,
  open-world) and which mutate state (index_repo replaces a repo's memories).
- A stdio transport (`madoguchi_stdio`). Desktop MCP clients commonly launch a
  local server as a subprocess and speak JSON-RPC over stdin/stdout; banto could
  only be reached over HTTP.
- A `madoguchi_resource` behaviour. The indexed repositories are natural MCP
  *resources* a client can browse, distinct from the action tools.

## Decision

- **Annotations.** `recall` and `ask` declare `readOnlyHint => true` and
  `openWorldHint => true`; `index_repo` declares `readOnlyHint => false`,
  `destructiveHint => true`, `idempotentHint => true` (re-indexing replaces).
- **Structured recall output.** `recall` declares an `output_schema/0` and returns
  `structuredContent` (`hits` as `{repo, path, content}`) alongside its text, so a
  client can consume results structurally.
- **Stdio transport.** `banto_mcp:start_stdio/0` serves the same server spec over
  stdin/stdout; the `mcp-stdio` CLI subcommand is the entry point. In that role
  the HTTP listener is not started (`BANTO_ROLE=stdio`) so nothing but MCP traffic
  reaches stdout.
- **Repo resources.** `banto_mcp_resources` (a `madoguchi_resource` provider)
  lists each indexed repo as `banto://repo/<name>` and reads it as the repo's
  indexed file paths. It is listed under the server's `resources`.

## Consequences

- A client can present banto's tools correctly and gate the mutating one; the
  read-only tools can run without a confirmation prompt.
- banto runs as a local MCP server a desktop client launches, not only as an HTTP
  service.
- Indexed repos are browsable as resources without issuing a recall.
- The HTTP transport and the existing tool contracts are unchanged; everything
  here is additive (the extra tool callbacks are optional, the stdio role and
  resources are opt-in).
