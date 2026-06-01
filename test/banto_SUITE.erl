-module(banto_SUITE).

-export([all/0, init_per_suite/1]).
-export([
    index_and_recall/1,
    ask_grounds_in_context/1,
    reindex_is_idempotent/1,
    recall_repo_filter/1,
    mcp_resources_list_and_read/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [
        index_and_recall,
        ask_grounds_in_context,
        reindex_is_idempotent,
        recall_repo_filter,
        mcp_resources_list_and_read
    ].

init_per_suite(Config) ->
    application:set_env(bunko, embedding_dim, 8),
    application:set_env(banto, repo, banto_test_repo),
    application:set_env(banto, embedder, bunko_embedder_stub),
    application:set_env(banto, llm, {banto_test_llm, #{}}),
    application:set_env(banto, namespace, ~"banto-test"),
    {ok, _} = application:ensure_all_started(kura),
    {ok, _} = application:ensure_all_started(kura_postgres),
    ok = banto_test_repo:start(),
    try
        ok = bunko_store_pgvector:uninstall(#{repo => banto_test_repo}),
        ok = banto:ensure_schema(),
        Config
    catch
        Class:Reason -> {skip, {banto_db_setup, Class, Reason}}
    end.

index_and_recall(Config) ->
    {Root, Greeting} = make_fixture(Config, ~"fixture"),
    {ok, Stats} = banto:index(Root, #{name => ~"fixture"}),
    ?assertEqual(2, maps:get(files, Stats)),
    %% query with text identical to a stored chunk -> deterministic top hit
    {ok, Hits} = banto:recall(Greeting, #{limit => 5}),
    ?assert(length(Hits) >= 1),
    [Top | _] = Hits,
    ?assertEqual(~"lib/greeting.erl", maps:get(~"path", maps:get(metadata, Top))),
    ?assertEqual(~"fixture", maps:get(~"repo", maps:get(metadata, Top))).

ask_grounds_in_context(Config) ->
    {Root, Greeting} = make_fixture(Config, ~"asked"),
    {ok, _} = banto:index(Root, #{name => ~"asked"}),
    %% banto_test_llm echoes the prompt; it must carry recalled context + paths
    {ok, Answer} = banto:ask(Greeting, #{limit => 5, repo => ~"asked"}),
    ?assertNotEqual(nomatch, binary:match(Answer, ~"asked_marker")),
    ?assertNotEqual(nomatch, binary:match(Answer, ~"lib/greeting.erl")).

reindex_is_idempotent(Config) ->
    {Root, _Greeting} = make_fixture(Config, ~"dup"),
    {ok, _} = banto:index(Root, #{name => ~"dup"}),
    {ok, _} = banto:index(Root, #{name => ~"dup"}),
    %% 2 files -> 2 chunks, not doubled by the second index
    ?assertEqual(2, count_for_repo(~"dup")).

recall_repo_filter(Config) ->
    {RootA, GreetA} = make_fixture(Config, ~"alpha"),
    {RootB, _GreetB} = make_fixture(Config, ~"beta"),
    {ok, _} = banto:index(RootA, #{name => ~"alpha"}),
    {ok, _} = banto:index(RootB, #{name => ~"beta"}),
    {ok, Hits} = banto:recall(GreetA, #{limit => 50, repo => ~"alpha"}),
    ?assert(length(Hits) >= 1),
    Repos = lists:usort([maps:get(~"repo", maps:get(metadata, H)) || H <- Hits]),
    ?assertEqual([~"alpha"], Repos).

mcp_resources_list_and_read(Config) ->
    {Root, _} = make_fixture(Config, ~"resrepo"),
    {ok, _} = banto:index(Root, #{name => ~"resrepo"}),
    Resources = banto_mcp_resources:list(),
    Uris = [maps:get(uri, R) || R <- Resources],
    ?assert(lists:member(~"banto://repo/resrepo", Uris)),
    {ok, [Contents]} = banto_mcp_resources:read(~"banto://repo/resrepo"),
    Text = maps:get(text, Contents),
    ?assertNotEqual(nomatch, binary:match(Text, ~"lib/greeting.erl")),
    ?assertEqual({error, not_found}, banto_mcp_resources:read(~"banto://repo/nope")).

%% --- helpers ---

%% Builds a fixture repo whose content embeds the repo name, so every repo has
%% distinct file content (and thus distinct stub embeddings). Returns the repo
%% root and the exact greeting-file content (for use as a recall query).
make_fixture(Config, Name) ->
    Priv = ?config(priv_dir, Config),
    Root = filename:join(Priv, "fixture_" ++ binary_to_list(Name)),
    Greeting = iolist_to_binary([~"-module(greeting).\nhello() -> ", Name, ~"_marker."]),
    ok = filelib:ensure_dir(filename:join([Root, "lib", "x"])),
    ok = file:write_file(filename:join([Root, "lib", "greeting.erl"]), Greeting),
    ok = file:write_file(
        filename:join(Root, "README.md"),
        iolist_to_binary([~"# ", Name, ~"\nCats are mammals in ", Name, ~"."])
    ),
    {Root, Greeting}.

count_for_repo(Repo) ->
    {ok, Memories} = bunko_store:all(banto_config:store(), banto_config:namespace()),
    length([M || M <- Memories, maps:get(~"repo", maps:get(metadata, M, #{}), undefined) =:= Repo]).
