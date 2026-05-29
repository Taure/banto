# 2. PR review swarm via gakudan fanout

Date: 2026-05-29

## Status

Accepted (P2). Builds on [ADR 0001](0001-architecture.md).

## Context

P1's `ask` is a single LLM completion - fine for a grounded lookup, but it does
not exercise gakudan's orchestration. PR review is the case where multiple
*specialist* perspectives on one input genuinely help (a security read, a
conventions read, a tests read, an architecture read), and they are independent
within a pass - the textbook fan-out topology. This is also where banto needs to
prove the saiten pillar: an eval that grades the swarm.

## Decision

- **Swarm = `gakudan_router_fanout` over four `gakudan_agent` reviewers**
  (`security`, `conventions`, `tests`, `architecture`). `banto_review:review/2`
  recalls repository context once (via `banto:recall`, so the `repo` filter
  applies), seeds it plus the diff as the run's kickoff message, runs one
  parallel round, and collects each agent's blackboard entry
  (`role = {agent, Id}`) into `#{agent, content}`. The agents share one grounded
  context; they differ only by system prompt.
- **Grounding, not tools.** Reviewers have no tools in P1/P2; they reason over
  the recalled context in the prompt. Tool use (e.g. pulling more files on
  demand) is a later refinement.
- **saiten gate.** `banto_review_eval:suite/0` is a saiten benchmark: planted-bug
  diffs paired with the phrase the responsible reviewer should produce, scored by
  `saiten_scorer_contains` over the aggregated review. `saiten:assert_passed/1`
  gates CI. Offline it runs against whatever LLM is configured (a persona-keyed
  deterministic stub in CI, so the fanout is stable despite concurrency); with a
  real LLM behind sekisho the same suite measures the swarm for real.
- **Surfaces.** A `banto_cli` escript (`review <diff>` alongside `ask`/`recall`/
  `index`) and an opt-in GitHub Action (label `banto-review`) that runs the swarm
  on a PR diff and posts the result, wired to sekisho via repo secrets.

## Consequences

**Positive.**

- Real parallel multi-agent review; gakudan's fanout, blackboard, and supervised
  run are exercised end to end.
- The saiten gate is honest: in CI it verifies the swarm + aggregation pipeline
  produces gradeable output; with a real LLM it grades quality.
- Reviewers are independent modules - adding a "performance" or "docs" reviewer
  is one module plus a list entry.

**Negative.**

- Offline determinism needs a persona-keyed stub LLM (keys off the system
  prompt), because a shared scripted queue is racy under fanout concurrency.
- Planted-bug dataset markers (`os:cmd`, `<<"`, missing `test`) are coarse; the
  CI gate proves plumbing, not nuanced judgement. Real grading needs a real LLM
  run (manual or a secrets-gated job).
- Reviewers see only the diff + recalled chunks, not the whole file; deep
  cross-file review awaits on-demand tool use.
