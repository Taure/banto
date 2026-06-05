-module(banto_tests).
-include_lib("eunit/include/eunit.hrl").

%% --- banto_config defaults ---

config_defaults_test() ->
    ?assertEqual(banto_repo, banto_config:repo()),
    ?assertEqual(~"banto", banto_config:namespace()),
    ?assertEqual({bunko_embedder_stub, #{cache => true}}, banto_config:embedder()),
    ?assertEqual({gakudan_llm_stub, #{}}, banto_config:llm()),
    ?assertEqual({bunko_store_pgvector, #{repo => banto_repo}}, banto_config:store()),
    ?assertEqual(undefined, banto_config:max_distance()),
    ?assertEqual(true, banto_config:hybrid()),
    ?assertEqual(#{max_attempts => 3}, banto_config:llm_retry()),
    ?assertEqual([], banto_config:llm_fallback()).

config_resilient_llm_default_test() ->
    ?assertEqual(
        {gakudan_llm_retry, #{max_attempts => 3, backend => {gakudan_llm_stub, #{}}}},
        banto_config:resilient_llm()
    ).

config_resilient_llm_no_retry_test() ->
    application:set_env(banto, llm_retry, false),
    try
        ?assertEqual({gakudan_llm_stub, #{}}, banto_config:resilient_llm())
    after
        application:unset_env(banto, llm_retry)
    end.

config_resilient_llm_fallback_test() ->
    application:set_env(banto, llm_retry, false),
    application:set_env(banto, llm_fallback, [{other_llm, #{}}]),
    try
        ?assertEqual(
            {gakudan_llm_fallback, #{
                backends => [{gakudan_llm_stub, #{}}, {other_llm, #{}}]
            }},
            banto_config:resilient_llm()
        )
    after
        application:unset_env(banto, llm_retry),
        application:unset_env(banto, llm_fallback)
    end.

config_embed_cache_off_test() ->
    application:set_env(banto, embed_cache, false),
    try
        ?assertEqual(bunko_embedder_stub, banto_config:embedder())
    after
        application:unset_env(banto, embed_cache)
    end.

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

%% --- banto_knowledge:recall_opts ---

recall_opts_no_repo_hybrid_test() ->
    Opts = banto_knowledge:recall_opts(#{limit => 5}, undefined),
    ?assertEqual(5, maps:get(limit, Opts)),
    ?assertEqual(true, maps:get(hybrid, Opts)),
    ?assertEqual(error, maps:find(filter, Opts)).

recall_opts_repo_filter_test() ->
    Opts = banto_knowledge:recall_opts(#{limit => 3, repo => ~"kura"}, ~"kura"),
    ?assertEqual(#{~"repo" => ~"kura"}, maps:get(filter, Opts)),
    ?assertEqual(error, maps:find(repo, Opts)).

recall_opts_max_distance_test() ->
    application:set_env(banto, max_distance, 0.4),
    try
        Opts = banto_knowledge:recall_opts(#{}, undefined),
        ?assertEqual(0.4, maps:get(max_distance, Opts))
    after
        application:unset_env(banto, max_distance)
    end.

recall_opts_hybrid_off_test() ->
    application:set_env(banto, hybrid, false),
    try
        Opts = banto_knowledge:recall_opts(#{}, undefined),
        ?assertEqual(error, maps:find(hybrid, Opts))
    after
        application:unset_env(banto, hybrid)
    end.

%% --- banto_indexer:items batches per-chunk metadata ---

indexer_items_skips_blank_and_tags_test() ->
    Parts = [{~"alpha", #{~"symbol" => ~"S"}}, {~"   ", #{}}, {~"beta", #{}}],
    Items = banto_indexer:items(~"kura", ~"a.erl", ~"code", Parts, 0, []),
    ?assertEqual(2, length(Items)),
    [{C0, M0}, {C1, _M1}] = Items,
    ?assertEqual(~"alpha", C0),
    ?assertEqual(~"kura", maps:get(~"repo", M0)),
    ?assertEqual(0, maps:get(~"chunk", M0)),
    ?assertEqual(~"S", maps:get(~"symbol", M0)),
    ?assertEqual(~"beta", C1).

%% --- banto_review_eval suite shape ---

eval_suite_scorers_test() ->
    Suite = banto_review_eval:suite(),
    Scorers = maps:get(scorers, Suite),
    ?assert(lists:member(saiten_scorer_contains, Scorers)),
    ?assertMatch(
        [_],
        [
            J
         || {saiten_scorer_judge, #{epochs := E, reducer := majority}} = J <- Scorers, E > 1
        ]
    ).

eval_suite_threshold_and_sinks_test() ->
    Suite = banto_review_eval:suite(),
    Threshold = maps:get(threshold, Suite),
    ByScorer = maps:get(by_scorer, Threshold),
    ?assertEqual(#{min_pass_rate => 1.0}, maps:get(saiten_scorer_contains, ByScorer)),
    ?assertEqual(#{min_mean_score => 0.5}, maps:get(saiten_scorer_judge, ByScorer)),
    Sinks = maps:get(sinks, Suite),
    ?assertMatch([{saiten_sink_junit, #{path := _}}], Sinks).

eval_assert_no_regression_no_baseline_test() ->
    application:set_env(banto, eval_baseline_path, "/tmp/banto-no-such-baseline.json"),
    try
        ?assertEqual(ok, banto_review_eval:assert_no_regression())
    after
        application:unset_env(banto, eval_baseline_path)
    end.

%% --- banto_finding (structured review findings) ---

finding_request_options_test() ->
    Opts = banto_reviewer_security:request_options(),
    ?assertEqual(banto_finding:schema(), maps:get(response_format, Opts)),
    ?assertEqual({gakudan_validator_json, banto_finding:schema()}, maps:get(validator, Opts)).

finding_render_structured_test() ->
    Content = iolist_to_binary(
        json:encode(#{
            ~"findings" => [
                #{
                    ~"severity" => ~"high",
                    ~"title" => ~"command injection",
                    ~"location" => ~"runner.erl",
                    ~"detail" => ~"os:cmd on input"
                }
            ]
        })
    ),
    Out = banto_finding:render(Content),
    ?assertNotEqual(nomatch, binary:match(Out, ~"(high)")),
    ?assertNotEqual(nomatch, binary:match(Out, ~"command injection")),
    ?assertNotEqual(nomatch, binary:match(Out, ~"runner.erl")),
    ?assertNotEqual(nomatch, binary:match(Out, ~"os:cmd on input")).

finding_render_empty_test() ->
    Out = banto_finding:render(iolist_to_binary(json:encode(#{~"findings" => []}))),
    ?assertNotEqual(nomatch, binary:match(Out, ~"No issues found.")).

finding_render_plain_text_fallback_test() ->
    ?assertEqual(~"just prose, not json", banto_finding:render(~"just prose, not json")).

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

cli_parse_mcp_stdio_test() ->
    ?assertEqual({ok, mcp_stdio}, banto_cli:parse(["mcp-stdio"])).

%% --- MCP tool annotations / output schema (ADR 0010) ---

mcp_recall_annotations_read_only_test() ->
    Ann = banto_mcp_recall:annotations(),
    ?assertEqual(true, maps:get(readOnlyHint, Ann)),
    ?assertEqual(true, maps:get(openWorldHint, Ann)).

mcp_ask_annotations_read_only_test() ->
    ?assertEqual(true, maps:get(readOnlyHint, banto_mcp_ask:annotations())).

mcp_index_annotations_not_read_only_test() ->
    Ann = banto_mcp_index:annotations(),
    ?assertEqual(false, maps:get(readOnlyHint, Ann)),
    ?assertEqual(true, maps:get(destructiveHint, Ann)).

mcp_recall_output_schema_test() ->
    Schema = banto_mcp_recall:output_schema(),
    ?assertEqual([~"hits"], maps:get(~"required", Schema)).

mcp_util_hits_json_test() ->
    Hits = [#{content => ~"code", metadata => #{~"repo" => ~"kura", ~"path" => ~"x.erl"}}],
    ?assertEqual(
        [#{~"repo" => ~"kura", ~"path" => ~"x.erl", ~"content" => ~"code"}],
        banto_mcp_util:hits_json(Hits)
    ).

mcp_server_has_resources_test() ->
    Server = banto_mcp:server(),
    ?assertEqual([banto_mcp_resources], maps:get(resources, Server)),
    ?assert(lists:member(banto_mcp_recall, maps:get(tools, Server))).

mcp_resources_unknown_uri_test() ->
    ?assertEqual({error, not_found}, banto_mcp_resources:read(~"banto://bogus/x")).

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

%% --- banto_indexer:collect_files polyglot extensions + engine build dirs ---

collect_files_polyglot_test() ->
    Dir = filename:join("/tmp", "banto_idx_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(filename:join(Dir, "Library")),
    Wanted = [
        "main.lua", "client.dart", "sdk.ts", "Player.cs", "core.cpp", "node.gd", "hud.gui_script"
    ],
    Unwanted = ["asset.png", "data.json", filename:join("Library", "gen.cs")],
    [ok = file:write_file(filename:join(Dir, F), ~"content") || F <- Wanted ++ Unwanted],
    try
        Found = [filename:basename(P) || P <- banto_indexer:collect_files(Dir)],
        ?assertEqual(lists:sort(Wanted), lists:sort(Found))
    after
        [file:delete(filename:join(Dir, F)) || F <- Wanted ++ Unwanted],
        _ = file:del_dir(filename:join(Dir, "Library")),
        _ = file:del_dir(Dir)
    end.

%% --- banto_index_hub pub/sub ---

index_hub_subscribe_and_report_test() ->
    {ok, Pid} = banto_index_hub:start_link(),
    try
        ?assertEqual(#{}, banto_index_hub:subscribe()),
        banto_index_hub:report(#{repo => ~"r1", phase => file, done => 2, total => 5, chunks => 9}),
        receive
            {banto_index_progress, Jobs} ->
                ?assertMatch(#{~"r1" := #{done := 2, chunks := 9}}, Jobs)
        after 1000 ->
            ?assert(false)
        end,
        ?assertMatch(#{~"r1" := _}, banto_index_hub:snapshot())
    after
        gen_server:stop(Pid)
    end.

%% --- banto_dashboard_page:jobs_html ---

jobs_html_test() ->
    Empty = iolist_to_binary(banto_dashboard_page:jobs_html(#{})),
    ?assertNotEqual(nomatch, binary:match(Empty, ~"no index jobs")),
    H = iolist_to_binary(
        banto_dashboard_page:jobs_html(#{
            ~"kura" => #{repo => ~"kura", phase => file, done => 3, total => 6, chunks => 12}
        })
    ),
    ?assertNotEqual(nomatch, binary:match(H, ~"kura")),
    ?assertNotEqual(nomatch, binary:match(H, ~"3/6")),
    ?assertNotEqual(nomatch, binary:match(H, ~"50%")).

%% --- banto_chunk_markdown (ADR 0006) ---

symbols(Chunks) ->
    [maps:get(~"symbol", M, undefined) || {_T, M} <- Chunks].

chunk_markdown_sections_test() ->
    Chunks = banto_chunk_markdown:chunk(~"intro\n## First\na\nb\n## Second\nc"),
    Syms = symbols(Chunks),
    ?assert(lists:member(~"First", Syms)),
    ?assert(lists:member(~"Second", Syms)),
    %% preamble before the first heading is untagged
    ?assert(lists:member(undefined, Syms)).

chunk_markdown_fence_not_heading_test() ->
    %% a '#' line inside a code fence must not start a section
    Chunks = banto_chunk_markdown:chunk(~"## Real\ntext\n```\n# not a heading\n```\nmore"),
    ?assertEqual([~"Real"], [S || S <- symbols(Chunks), S =/= undefined]).

%% --- banto_chunk dispatch ---

chunk_dispatch_non_md_matches_line_slicer_test() ->
    Content = iolist_to_binary(lists:join(~"\n", [integer_to_binary(N) || N <- lists:seq(1, 5)])),
    Tuples = banto_chunk:chunk("foo.erl", Content),
    ?assertEqual(banto_indexer:chunk(Content), [T || {T, _M} <- Tuples]),
    ?assert(lists:all(fun({_T, M}) -> M =:= #{} end, Tuples)).

chunk_dispatch_md_uses_markdown_test() ->
    Tuples = banto_chunk:chunk("readme.md", ~"## H\nbody"),
    ?assertEqual([~"H"], [S || S <- symbols(Tuples), S =/= undefined]).
