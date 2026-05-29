# 4. Nova + Datastar memory dashboard

Date: 2026-05-29

## Status

Accepted (P3b). Builds on [ADR 0001](0001-architecture.md).

## Context

banto knows things (its bunko memory) and a web console makes that legible:
which repos are indexed, how much, and a live recall search. The ecosystem's
dashboard stack is Nova + Datastar (the `gakudan_liveboard` set), not Arizona.
banto has been a plain OTP service (madoguchi MCP on cowboy at :8080); the
dashboard adds a web tier without disturbing that.

## Decision

- **Nova + Datastar, second listener.** Add `nova` + `datastar` (pre-release,
  SHA-pinned to the known-good liveboard set) and run Nova's cowboy listener on
  **:8081**, separate from the madoguchi MCP listener on :8080. Routes live in
  `banto_router` (Nova's `<bootstrap_application>_router` convention).
- **Scope = memory console.** The dashboard shows what banto actually persists:
  an indexed-repo summary (`banto_dashboard:repo_summary/0`, a `GROUP BY` over the
  bunko table) and a recall search. gakudan runs and sekisho budgets are
  ephemeral / another service's data, so they are out of scope here.
- **One-shot search, not a held stream.** `banto_dashboard_page:search/1` reads
  the `query` signal Datastar `@post`s, runs `banto:recall`, and returns a single
  `datastar:patch_elements` SSE frame for `#results`. liveboard's long-lived SSE
  fits a live transcript; an on-demand memory query does not need a held
  connection.
- **Assets via a whitelisted controller, not `cowboy_static`.** The documented
  `{"/assets/[...]", "static/assets"}` catch-all route crashes
  `nova_router:execute/2` with `{badmap, undefined}` under the cowboy version
  banto resolves (2.15.0, forced by madoguchi). Exact-path routes work, so
  `banto_dashboard_assets:serve/1` serves the two known assets (app.css,
  datastar.js) from `priv` by whitelist - no path traversal, no cowboy-version
  dependence. Filed upstream against nova.
- **Strict CSP, self-hosted.** `script-src 'self' 'unsafe-eval'` (Datastar needs
  eval for `data-*` expressions); everything else `'self'`. datastar.js is
  vendored, not a CDN.

## Consequences

**Positive.**

- A real Datastar dashboard proving the Nova + Datastar stack on top of banto's
  memory; verified at the HTTP level (page, assets, the search patch frame).
- The asset controller is version-robust and secure (whitelist).

**Negative.**

- Two cowboy listeners (MCP + web) in one release; fine, but two ports to run.
- The live browser interactivity (Datastar applying patches, `data-bind`) is not
  covered by CI - only the server-rendered HTML and the patch frames are tested.
  Verifying the UX needs a browser.
- Pinning nova/datastar to SHAs (pre-release) means manual bumps until they tag.
