-module(banto_reviewer_tests).
-moduledoc "Review-swarm agent: test coverage.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> tests.

system_prompt() ->
    ~"You are the TESTS reviewer on a code-review swarm. Assess whether the diff is adequately tested: new functions/branches with no test, edge cases left uncovered, tests that assert nothing meaningful, missing regression tests for a bug fix. Reference the repo's testing conventions from the provided context. Suggest the specific test that is missing. Be terse.".

tools() -> [].

model() -> banto_config:model().
