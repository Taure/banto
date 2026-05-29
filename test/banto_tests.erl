-module(banto_tests).
-include_lib("eunit/include/eunit.hrl").

%% --- banto_config defaults ---

config_defaults_test() ->
    ?assertEqual(banto_repo, banto_config:repo()),
    ?assertEqual(~"banto", banto_config:namespace()),
    ?assertEqual(bunko_embedder_stub, banto_config:embedder()),
    ?assertEqual({gakudan_llm_stub, #{}}, banto_config:llm()),
    ?assertEqual({bunko_store_pgvector, #{repo => banto_repo}}, banto_config:store()).

%% --- banto_indexer:chunk ---

chunk_single_test() ->
    ?assertEqual([~"a\nb\nc"], banto_indexer:chunk(~"a\nb\nc")).

chunk_splits_long_content_test() ->
    Content = iolist_to_binary(lists:join(~"\n", [integer_to_binary(N) || N <- lists:seq(1, 130)])),
    Chunks = banto_indexer:chunk(Content),
    %% 130 lines / 60 per chunk = 3 chunks
    ?assertEqual(3, length(Chunks)),
    %% round-trips: rejoining the chunks reproduces the content
    ?assertEqual(Content, iolist_to_binary(lists:join(~"\n", Chunks))).

%% --- banto_embedder pure helpers ---

embedder_build_body_test() ->
    ?assertEqual(
        #{model => ~"m", input => ~"hello"},
        banto_embedder:build_body(~"m", ~"hello")
    ).

embedder_parse_embedding_test() ->
    Body = iolist_to_binary(
        json:encode(#{
            ~"object" => ~"list",
            ~"data" => [#{~"embedding" => [0.1, 0.2, 3]}],
            ~"usage" => #{~"prompt_tokens" => 4}
        })
    ),
    ?assertEqual({ok, [0.1, 0.2, 3.0]}, banto_embedder:parse_embedding(Body)).

embedder_parse_embedding_bad_test() ->
    ?assertEqual({error, no_embedding}, banto_embedder:parse_embedding(~"{}")).

%% --- banto_knowledge:build_request ---

build_request_includes_context_and_question_test() ->
    Hits = [
        #{content => ~"defmodule Foo", metadata => #{~"repo" => ~"kura", ~"path" => ~"a.ex"}},
        #{content => ~"-module(bar).", metadata => #{~"repo" => ~"nova", ~"path" => ~"b.erl"}}
    ],
    Req = banto_knowledge:build_request(~"claude", ~"where is Foo?", Hits),
    ?assertEqual(~"claude", maps:get(model, Req)),
    ?assertEqual([], maps:get(tools, Req)),
    [#{role := user, content := Prompt}] = maps:get(messages, Req),
    ?assertNotEqual(nomatch, binary:match(Prompt, ~"defmodule Foo")),
    ?assertNotEqual(nomatch, binary:match(Prompt, ~"kura/a.ex")),
    ?assertNotEqual(nomatch, binary:match(Prompt, ~"where is Foo?")).

build_request_no_hits_test() ->
    Req = banto_knowledge:build_request(~"claude", ~"q", []),
    [#{content := Prompt}] = maps:get(messages, Req),
    ?assertNotEqual(nomatch, binary:match(Prompt, ~"no relevant context")).

%% --- banto_mcp_util ---

mcp_opts_default_test() ->
    ?assertEqual(#{limit => 5}, banto_mcp_util:opts(#{})).

mcp_opts_with_repo_and_limit_test() ->
    ?assertEqual(
        #{limit => 3, repo => ~"kura"},
        banto_mcp_util:opts(#{~"limit" => 3, ~"repo" => ~"kura"})
    ).

mcp_format_hits_empty_test() ->
    ?assertEqual(~"No matches found.", banto_mcp_util:format_hits([])).

mcp_format_hits_test() ->
    Hits = [#{content => ~"code here", metadata => #{~"repo" => ~"kura", ~"path" => ~"x.erl"}}],
    Out = banto_mcp_util:format_hits(Hits),
    ?assertNotEqual(nomatch, binary:match(Out, ~"[kura/x.erl]")),
    ?assertNotEqual(nomatch, binary:match(Out, ~"code here")).

%% --- MCP tool specs ---

tool_specs_test() ->
    ?assertEqual(~"recall", banto_mcp_recall:name()),
    ?assertEqual(~"ask", banto_mcp_ask:name()),
    ?assertEqual(~"index_repo", banto_mcp_index:name()),
    ?assertEqual([~"query"], maps:get(~"required", banto_mcp_recall:input_schema())),
    ?assertEqual([~"question"], maps:get(~"required", banto_mcp_ask:input_schema())),
    ?assertEqual([~"path", ~"name"], maps:get(~"required", banto_mcp_index:input_schema())).
