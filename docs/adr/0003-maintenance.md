# 3. Nightly maintenance: deterministic deps + LLM doc-drift

Date: 2026-05-29

## Status

Accepted (P3a). Builds on [ADR 0002](0002-review-swarm.md).

## Context

Beyond reviewing incoming diffs, a concierge should watch a repo over time. Two
maintenance concerns recur: dependencies drifting to unpinned/stale versions, and
documentation drifting out of sync with code. These have opposite shapes - deps
are structured data; doc drift is a judgement call - so one mechanism does not
fit both.

## Decision

- **Deps are data, not an LLM job.** `banto_dep_audit:scan/1` parses a repo's
  `rebar.config` with `file:consult/1` and flags git deps pinned to a moving
  `branch` (non-reproducible). Tag-, ref-, and hex-pinned deps pass. Deterministic
  and unit-tested - no model in the loop.
- **Doc drift is a judgement call, so it is an agent.** `banto_maintainer_docs` is
  a `gakudan_agent` run (via the shared `banto_run`) over bunko-recalled README +
  module docs + code; the model reports features documented-but-removed,
  public-but-undocumented, stale examples, and stale status claims.
- **`banto_maintenance:run/2` combines both** into one markdown report. Surfaced
  via the `banto_cli maintain` subcommand and a **scheduled GitHub Action** that
  indexes the repo, runs the report, and opens an issue (wired to sekisho via
  secrets; cron + manual, so no cost on normal pushes).
- **`banto_run` extracted.** The gakudan start/send/await/stop + per-agent
  collection that the review swarm used is now shared by review and maintenance.

## Consequences

**Positive.**

- The dep check is reproducible and needs no LLM/network; the CI gate on it is
  deterministic.
- Doc drift reuses the indexed memory (bunko) and the agent machinery (gakudan),
  so it costs almost no new code.
- Self-maintenance: the nightly Action points banto at its own repo, dogfooding
  the whole stack on a schedule.

**Negative.**

- The dep check only flags `branch` pins; "a newer tag exists" needs a registry
  query and is left to a future Action step, not the core module.
- Doc-drift quality depends on the LLM and on what was indexed; offline it uses
  the persona-keyed stub (a canned finding), so CI proves plumbing, not judgement.
