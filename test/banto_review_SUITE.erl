-module(banto_review_SUITE).

-export([all/0, init_per_suite/1]).
-export([swarm_returns_all_reviews/1, security_reviewer_catches_injection/1, saiten_gate_passes/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [swarm_returns_all_reviews, security_reviewer_catches_injection, saiten_gate_passes].

init_per_suite(Config) ->
    application:set_env(bunko, embedding_dim, 8),
    application:set_env(banto, repo, banto_test_repo),
    application:set_env(banto, embedder, bunko_embedder_stub),
    application:set_env(banto, llm, {banto_test_reviewer_llm, #{}}),
    application:set_env(banto, namespace, ~"banto-review-test"),
    {ok, _} = application:ensure_all_started(kura),
    {ok, _} = application:ensure_all_started(kura_postgres),
    {ok, _} = application:ensure_all_started(gakudan),
    ok = banto_test_repo:start(),
    try
        ok = bunko_store_pgvector:uninstall(#{repo => banto_test_repo}),
        ok = banto:ensure_schema(),
        Config
    catch
        Class:Reason -> {skip, {banto_db_setup, Class, Reason}}
    end.

swarm_returns_all_reviews(_Config) ->
    Diff = ~"--- a/x.erl\n+++ b/x.erl\n@@\n+f() -> ok.\n",
    {ok, Reviews} = banto_review:review(Diff, #{}),
    Agents = lists:sort([maps:get(agent, R) || R <- Reviews]),
    ?assertEqual([architecture, conventions, security, tests], Agents).

security_reviewer_catches_injection(_Config) ->
    Diff = ~"--- a/runner.erl\n+++ b/runner.erl\n@@\n+run(In) -> os:cmd(\"build \" ++ In).\n",
    {ok, Reviews} = banto_review:review(Diff, #{}),
    [#{content := Content}] = [R || #{agent := security} = R <- Reviews],
    ?assertNotEqual(nomatch, binary:match(Content, ~"command injection")).

saiten_gate_passes(_Config) ->
    %% Runs the swarm over the planted-bug dataset and gates on the scorecard.
    ?assertEqual(ok, saiten:assert_passed(saiten:run(banto_review_eval:suite()))).
