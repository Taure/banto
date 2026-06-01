# 11. Review-eval upgrades: self-consistency judge, JUnit, regression gate

Date: 2026-06-01

## Status

Accepted. Refines the eval/CI gate from [ADR 0002](0002-review-swarm.md).

## Context

The review-swarm benchmark (`banto_review_eval`) scored each planted-bug case
only with `saiten_scorer_contains` against a `min_pass_rate => 1.0` threshold,
and emitted nothing CI-native. saiten v0.1.7 adds the pieces to make the gate
both stricter and more stable:

- `saiten_scorer_judge` with `epochs` + `reducer` - run an LLM-as-judge several
  times and reduce, so a variable judge yields a stable verdict.
- Per-scorer thresholds (`by_scorer`) - hold different scorers to different bars.
- A JUnit XML sink (`saiten_sink_junit`) - CI-native test output.
- `saiten:compare/3` + `assert_no_regression/1` against a baseline scorecard
  (read with `saiten_sink_json:read/1`).

## Decision

`banto_review_eval:suite/0` now:

- Adds a self-consistency `saiten_scorer_judge` (3 epochs, `majority` reducer)
  beside the keyword scorer. The judge defaults to the deterministic
  `saiten_judge_stub` so CI stays offline and stable; point the `eval_judge` env
  at a real judge behind sekisho to grade for real.
- Uses `by_scorer` thresholds: the keyword scorer must catch every planted bug
  (`min_pass_rate => 1.0`, the hard gate); the judge is held to a softer
  `min_mean_score => 0.5` so judge variance never flakes the build.
- Writes a JUnit XML report (`eval_junit_path`, default `review-eval-junit.xml`).

A new `banto_review_eval:assert_no_regression/0` gates against a baseline
scorecard at `eval_baseline_path` when one exists, and is a no-op pass otherwise,
so adopting it requires no baseline to be committed first.

## Consequences

- The gate is harder to game (a review must both name the issue and satisfy the
  judge) yet stable offline (deterministic stubs, majority reduction).
- CI emits JUnit XML, so the eval surfaces as native test results.
- A committed baseline turns on regression detection with confidence-interval
  noise tolerance; with no baseline the build is unaffected.
- All knobs are env-configurable; the dataset and `suite/0`'s shape stay
  backward compatible.
