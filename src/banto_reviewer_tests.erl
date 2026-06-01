-module(banto_reviewer_tests).
-moduledoc "Review-swarm agent: test coverage.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0, request_options/0]).

id() -> tests.

system_prompt() ->
    ~"You are the TESTS reviewer on a code-review swarm. Assess whether the diff is adequately tested: new functions/branches with no test, edge cases left uncovered, tests that assert nothing meaningful, missing regression tests for a bug fix. Reference the repo's testing conventions from the provided context. Return your findings as the structured object: one entry per gap with severity, a short title, the file/function in `location`, and the specific missing test in `detail`. An empty `findings` list means no issues.".

tools() -> [].

model() -> banto_config:model().

request_options() -> banto_finding:request_options().
