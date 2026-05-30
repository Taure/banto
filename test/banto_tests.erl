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

%% --- banto_cli:parse ---

cli_parse_index_test() ->
    ?assertEqual({ok, {index, "/p", ~"kura"}}, banto_cli:parse(["index", "/p", "kura"])).

cli_parse_recall_test() ->
    ?assertEqual({ok, {recall, ~"q"}}, banto_cli:parse(["recall", "q"])).

cli_parse_ask_test() ->
    ?assertEqual({ok, {ask, ~"why"}}, banto_cli:parse(["ask", "why"])).

cli_parse_review_test() ->
    ?assertEqual({ok, {review, "d.diff"}}, banto_cli:parse(["review", "d.diff"])).

cli_parse_maintain_test() ->
    ?assertEqual({ok, {maintain, "/p", ~"kura"}}, banto_cli:parse(["maintain", "/p", "kura"])).

%% --- banto_dep_audit ---

dep_audit_flags_branch_test() ->
    Deps = [
        {a, {git, "u", {tag, "v1"}}},
        {b, {git, "u", {branch, "main"}}},
        {c, "1.0.0"}
    ],
    ?assertEqual(
        [#{dep => b, issue => unpinned_branch, detail => "main"}],
        banto_dep_audit:findings(Deps)
    ).

dep_audit_clean_format_test() ->
    ?assertEqual(
        ~"No dependency issues: every dependency is pinned.",
        banto_dep_audit:format([])
    ).

dep_audit_finding_format_test() ->
    Out = banto_dep_audit:format([#{dep => b, issue => unpinned_branch, detail => ~"main"}]),
    ?assertNotEqual(nomatch, binary:match(Out, ~"b (branch: main)")).

maintenance_format_test() ->
    Report = banto_maintenance:format(
        [#{dep => b, issue => unpinned_branch, detail => ~"main"}],
        ~"docs look fine"
    ),
    ?assertNotEqual(nomatch, binary:match(Report, ~"maintenance report")),
    ?assertNotEqual(nomatch, binary:match(Report, ~"branch: main")),
    ?assertNotEqual(nomatch, binary:match(Report, ~"docs look fine")).

cli_parse_usage_test() ->
    ?assertEqual({error, usage}, banto_cli:parse(["bogus"])),
    ?assertEqual({error, usage}, banto_cli:parse([])).

%% --- banto_dashboard_page rendering ---

dashboard_page_shell_test() ->
    Html = iolist_to_binary(banto_dashboard_page:page(~"banto", ~"<p>x</p>")),
    ?assertNotEqual(nomatch, binary:match(Html, ~"<!DOCTYPE html")),
    ?assertNotEqual(nomatch, binary:match(Html, ~"/assets/js/datastar.js")),
    ?assertNotEqual(nomatch, binary:match(Html, ~"<p>x</p>")).

dashboard_repo_summary_html_test() ->
    Out = iolist_to_binary(
        banto_dashboard_page:repo_summary_html([#{repo => ~"kura", count => 3}])
    ),
    ?assertNotEqual(nomatch, binary:match(Out, ~"kura")),
    ?assertNotEqual(nomatch, binary:match(Out, ~">3<")),
    Empty = iolist_to_binary(banto_dashboard_page:repo_summary_html([])),
    ?assertNotEqual(nomatch, binary:match(Empty, ~"nothing indexed")).

dashboard_results_html_test() ->
    Hit = #{content => ~"some code", metadata => #{~"repo" => ~"kura", ~"path" => ~"x.erl"}},
    Out = iolist_to_binary(banto_dashboard_page:results_html([Hit])),
    ?assertNotEqual(nomatch, binary:match(Out, ~"kura/x.erl")),
    ?assertNotEqual(nomatch, binary:match(Out, ~"some code")),
    ?assertNotEqual(nomatch, binary:match(banto_dashboard_page:results_html([]), ~"no matches")).

dashboard_query_signal_test() ->
    ?assertEqual(~"find this", banto_dashboard_page:query_signal(~"{\"query\":\"find this\"}")),
    ?assertEqual(~"", banto_dashboard_page:query_signal(~"{}")),
    ?assertEqual(~"", banto_dashboard_page:query_signal(~"not json")).

tool_specs_test() ->
    ?assertEqual(~"recall", banto_mcp_recall:name()),
    ?assertEqual(~"ask", banto_mcp_ask:name()),
    ?assertEqual(~"index_repo", banto_mcp_index:name()),
    ?assertEqual([~"query"], maps:get(~"required", banto_mcp_recall:input_schema())),
    ?assertEqual([~"question"], maps:get(~"required", banto_mcp_ask:input_schema())),
    ?assertEqual([~"path", ~"name"], maps:get(~"required", banto_mcp_index:input_schema())).

%% --- banto_indexer:collect_files accepts binary paths (MCP/JSON inputs) ---

collect_files_binary_path_test() ->
    Dir = filename:join("/tmp", "banto_idx_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Dir),
    File = filename:join(Dir, "readme.md"),
    ok = file:write_file(File, ~"# hello\nworld"),
    try
        FromList = banto_indexer:collect_files(Dir),
        FromBinary = banto_indexer:collect_files(unicode:characters_to_binary(Dir)),
        ?assertEqual(FromList, FromBinary),
        ?assertEqual(1, length(FromList))
    after
        _ = file:delete(File),
        _ = file:del_dir(Dir)
    end.
