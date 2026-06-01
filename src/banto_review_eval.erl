-module(banto_review_eval).
-moduledoc """
A [saiten](https://github.com/Taure/saiten) benchmark for the review swarm: each
case is a diff with a planted issue and the phrase the responsible reviewer
should produce. The target runs `banto_review:review/2`; `saiten_scorer_contains`
checks the aggregated review names the issue, and a self-consistency
`saiten_scorer_judge` (multiple epochs reduced for stability) grades whether the
review actually addresses the planted bug.

Run it with `saiten:run(banto_review_eval:suite())`; gate CI with
`saiten:assert_passed/1`. The suite emits a JUnit XML report (CI-native) and, if
a baseline scorecard exists, `assert_no_regression/0` gates against it. Offline it
uses a deterministic LLM stub and a deterministic judge stub; with a real LLM
behind sekisho and a real judge it measures the swarm for real.
""".

-export([suite/0, dataset/0, junit_path/0, baseline_path/0, assert_no_regression/0]).

-define(JUDGE_EPOCHS, 3).

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
        scorers => [saiten_scorer_contains, judge_scorer()],
        threshold => threshold(),
        sinks => [{saiten_sink_junit, #{path => junit_path()}}]
    }.

-doc "Gate against the baseline scorecard if one exists; `ok` when there is none.".
-spec assert_no_regression() -> ok | no_return().
assert_no_regression() ->
    case saiten_sink_json:read(baseline_path()) of
        {ok, Baseline} ->
            {ok, Current} = saiten:run(suite()),
            saiten:assert_no_regression(saiten:compare(Baseline, Current, #{}));
        {error, _} ->
            ok
    end.

-doc "Path of the JUnit XML report the suite writes.".
-spec junit_path() -> file:name_all().
junit_path() ->
    application:get_env(banto, eval_junit_path, "review-eval-junit.xml").

-doc "Path of the optional baseline scorecard for regression gating.".
-spec baseline_path() -> file:name_all().
baseline_path() ->
    application:get_env(banto, eval_baseline_path, "review-eval-baseline.json").

%% --- internal ---

%% A self-consistency judge: run the judge several times and reduce by majority,
%% so a variable judge gives a stable verdict. Defaults to the deterministic
%% saiten stub judge (a perfect pass offline); point `eval_judge` at a real judge
%% behind sekisho to grade for real.
judge_scorer() ->
    Judge = application:get_env(banto, eval_judge, saiten_judge_stub),
    {saiten_scorer_judge, #{
        judge => Judge,
        criteria =>
            ~"Does the review concretely identify and address the planted bug in the diff?",
        epochs => ?JUDGE_EPOCHS,
        reducer => majority
    }}.

%% The keyword scorer must catch every planted bug (the hard gate); the judge is
%% held to a softer mean-score bar so judge variance never flakes the build.
threshold() ->
    #{
        min_pass_rate => 1.0,
        by_scorer => #{
            saiten_scorer_contains => #{min_pass_rate => 1.0},
            saiten_scorer_judge => #{min_mean_score => 0.5}
        }
    }.

run_case(#{input := Diff}) ->
    case banto_review:review(Diff, #{}) of
        {ok, Reviews} -> banto_review:format(Reviews);
        {error, Reason} -> iolist_to_binary(io_lib:format("review error: ~p", [Reason]))
    end.
