-module(banto_review_eval).
-moduledoc """
A [saiten](https://github.com/Taure/saiten) benchmark for the review swarm: each
case is a diff with a planted issue and the phrase the responsible reviewer
should produce. The target runs `banto_review:review/2` and the
`saiten_scorer_contains` scorer checks the aggregated review names the issue.

Run it with `saiten:run(banto_review_eval:suite())`; gate CI with
`saiten:assert_passed/1`. Offline it uses whatever LLM is configured (a
deterministic stub in CI); with a real LLM behind sekisho it measures the swarm
for real.
""".

-export([suite/0, dataset/0]).

-doc "The planted-bug dataset: `#{input := Diff, expected := phrase}` cases.".
-spec dataset() -> [saiten:eval_case()].
dataset() ->
    [
        #{
            id => command_injection,
            input =>
                ~"--- a/src/runner.erl\n+++ b/src/runner.erl\n@@\n-run(_) -> ok.\n+run(Input) -> os:cmd(\"build \" ++ Input).\n",
            expected => ~"command injection"
        },
        #{
            id => old_binary_literal,
            input =>
                ~"--- a/src/greet.erl\n+++ b/src/greet.erl\n@@\n-hello() -> ok.\n+hello() -> <<\"hi\">>.\n",
            expected => ~"sigil"
        },
        #{
            id => missing_test,
            input =>
                ~"--- a/src/calc.erl\n+++ b/src/calc.erl\n@@\n-add(A, B) -> A + B.\n+add(A, B) -> A + B.\n+sub(A, B) -> A - B.\n",
            expected => ~"no test"
        }
    ].

-doc "The saiten suite that runs the swarm and scores each planted case.".
-spec suite() -> saiten:suite().
suite() ->
    #{
        name => banto_review,
        dataset => dataset(),
        target => fun run_case/1,
        scorers => [saiten_scorer_contains],
        threshold => #{min_pass_rate => 1.0}
    }.

run_case(#{input := Diff}) ->
    case banto_review:review(Diff, #{}) of
        {ok, Reviews} -> banto_review:format(Reviews);
        {error, Reason} -> iolist_to_binary(io_lib:format("review error: ~p", [Reason]))
    end.
