# 9. Resilient LLM backends (retry + optional fallback)

Date: 2026-06-01

## Status

Accepted. Refines the LLM wiring from [ADR 0001](0001-architecture.md).

## Context

Every LLM call - a grounded `ask` and each reviewer in the swarm - went straight
to the single configured `gakudan_llm` backend. A transient upstream failure (an
HTTP 5xx, a timeout, a dropped connection) therefore failed the whole operation,
even though a retry moments later would have succeeded.

gakudan v0.1.41 ships two composable backends that are themselves `gakudan_llm`
implementations: `gakudan_llm_retry` (retries transient errors with exponential
backoff) and `gakudan_llm_fallback` (tries a list of backends in order). They
warp nothing in core - a wrapped backend slots into any `{Module, Opts}` site.

## Decision

Add `banto_config:resilient_llm/0`, which wraps the configured backend
(`banto_config:llm/0`, whose `{Mod, Opts}` shape is unchanged) for resilience:

- optional fallback backends first (`banto` env `llm_fallback`, default `[]`),
- then a retry/backoff wrapper (`banto` env `llm_retry`, default
  `#{max_attempts => 3}`; set `false` to disable).

`banto_knowledge:ask` and `banto_run` (the swarm and maintenance agents) call
`resilient_llm/0` instead of `llm/0`. `llm/0` still returns the raw configured
backend for callers that want it.

## Consequences

- A transient upstream blip no longer fails an ask or a review; the retry
  absorbs it.
- The existing `{Mod, Opts}` `llm` config keeps working untouched - resilience
  is layered on top, off by setting `llm_retry => false`.
- Adding standby providers is config-only via `llm_fallback`, no code change.
- Retries add latency on the failing path (bounded by `max_attempts` and the
  backoff cap); the happy path is unaffected.
