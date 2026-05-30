-module(banto_dashboard_page).
-moduledoc """
Nova controllers for the memory dashboard. `index/1` server-renders the shell:
the indexed-repo summary and a Datastar-bound recall search box. `search/1`
reads the `query` signal Datastar posts, runs `banto:recall`, and returns a
single Datastar patch of `#results` (one-shot SSE, no held connection).
""".

%% index/1, index_stream/1 and flow_stream/1 take Req by the Nova controller
%% contract even though it is unused.
-hank([{unnecessary_function_arguments, [{index, 1, 1}, {index_stream, 1, 1}, {flow_stream, 1, 1}]}]).

-export([index/1, search/1, start_index/1, index_stream/1, flow_stream/1]).
-export([page/2, repo_summary_html/1, results_html/1, query_signal/1, jobs_html/1]).
-export([flow_question/1, flow_mode/1, flow_html/1, answer_html/1]).

%% GET /
index(_Req) ->
    Summary =
        case banto_dashboard:repo_summary() of
            {ok, S} -> S;
            {error, _} -> []
        end,
    html(page(~"banto", body(Summary))).

%% POST /dashboard/search - Datastar sends {query: "..."} as signals.
search(Req) ->
    {ok, Body, _Req1} = cowboy_req:read_body(Req),
    Query = query_signal(Body),
    Hits = recall(Query),
    Frame = datastar:patch_elements(results_html(Hits), #{selector => ~"#results", mode => inner}),
    {status, 200, maps:from_list(datastar:sse_headers()), iolist_to_binary(Frame)}.

%% POST /dashboard/index - Datastar sends {path, name}; starts a background job.
start_index(Req) ->
    {ok, Body, _Req1} = cowboy_req:read_body(Req),
    Msg =
        case index_signals(Body) of
            {ok, Name, Path} ->
                _ = banto_index_job:start(Name, Path),
                [~"indexing ", html_escape(Name), ~"..."];
            {error, _} ->
                ~"enter both a path and a name."
        end,
    Frame = datastar:patch_elements(
        [~"<span>", Msg, ~"</span>"], #{selector => ~"#index-status", mode => inner}
    ),
    {status, 200, maps:from_list(datastar:sse_headers()), iolist_to_binary(Frame)}.

%% GET /dashboard/index/stream - held SSE; banto_index_stream takes over.
index_stream(_Req) ->
    {stream, 200, maps:from_list(datastar:sse_headers()), #{}}.

%% GET /dashboard/flow/stream - held SSE; banto_flow_stream runs the ask/recall.
flow_stream(_Req) ->
    {stream, 200, maps:from_list(datastar:sse_headers()), #{}}.

-doc "The `question` signal from a Datastar `@post` body (same idiom as search/1).".
-spec flow_question(binary()) -> binary().
flow_question(Body) ->
    case datastar:read_signals(Body) of
        {ok, #{~"question" := Q}} when is_binary(Q) -> string:trim(Q);
        _ -> ~""
    end.

-doc "Map the flow stream's request path to its mode.".
-spec flow_mode(binary()) -> ask | recall.
flow_mode(~"/dashboard/flow/recall") -> recall;
flow_mode(_Path) -> ask.

%% --- rendering ---

body(Summary) ->
    [
        ~"<h2>indexed repositories</h2>",
        repo_summary_html(Summary),
        ~"<h2>index a repo</h2>",
        ~"<div data-signals-path=\"''\" data-signals-name=\"''\" data-on-load=\"@get('/dashboard/index/stream')\">",
        ~"<div class=\"search\">",
        ~"<input type=\"text\" placeholder=\"/repos/personal/gakudan\" data-bind-path>",
        ~"<input type=\"text\" placeholder=\"name\" data-bind-name>",
        ~"<button data-on-click=\"@post('/dashboard/index')\">index</button></div>",
        ~"<div id=\"index-status\" class=\"empty\"></div>",
        ~"<div id=\"jobs\" class=\"jobs\"><p class=\"empty\">no index jobs yet.</p></div></div>",
        ~"<h2>ask &amp; recall</h2>",
        ~"<div data-signals-question=\"''\"><div class=\"search\">",
        ~"<input type=\"text\" placeholder=\"ask across your repos...\" data-bind-question>",
        ~"<button data-on-click=\"@post('/dashboard/flow/recall')\">recall</button>",
        ~"<button data-on-click=\"@post('/dashboard/flow/ask')\">ask</button></div>",
        ~"<div id=\"flow\" class=\"flow\"><p class=\"empty\">the agent's flow will appear here.</p></div>",
        ~"<div id=\"answer\" class=\"results\"><p class=\"empty\">the answer will appear here.</p></div></div>"
    ].

-doc "Render the indexed-repo summary (pure).".
-spec repo_summary_html([map()]) -> iodata().
repo_summary_html([]) ->
    ~"<p class=\"empty\">nothing indexed yet - run banto:index/2.</p>";
repo_summary_html(Summary) ->
    [
        ~"<ul class=\"repos\">",
        [
            [
                ~"<li>",
                html_escape(maps:get(repo, R)),
                ~" <span class=\"count\">",
                integer_to_binary(maps:get(count, R)),
                ~"</span></li>"
            ]
         || R <- Summary
        ],
        ~"</ul>"
    ].

-doc "Render recall hits (pure).".
-spec results_html([bunko_store:hit()]) -> iodata().
results_html([]) ->
    ~"<p class=\"empty\">no matches.</p>";
results_html(Hits) ->
    [hit_html(H) || H <- Hits].

hit_html(#{content := Content} = Hit) ->
    Meta = maps:get(metadata, Hit, #{}),
    Repo = maps:get(~"repo", Meta, ~"?"),
    Path = maps:get(~"path", Meta, ~"?"),
    [
        ~"<div class=\"hit\"><div class=\"src\">",
        html_escape(Repo),
        ~"/",
        html_escape(Path),
        ~"</div><pre>",
        html_escape(snippet(Content)),
        ~"</pre></div>"
    ].

-doc "The HTML page shell (pure).".
-spec page(binary(), iodata()) -> iodata().
page(Title, Content) ->
    [
        ~"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\">",
        ~"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
        ~"<title>",
        html_escape(Title),
        ~"</title><link rel=\"stylesheet\" href=\"/assets/css/app.css\">",
        ~"<script type=\"module\" src=\"/assets/js/datastar.js\"></script></head>",
        ~"<body><header class=\"site-header\"><h1><a href=\"/\">\x{756A}\x{982D} banto</a></h1>",
        ~"<span class=\"tagline\">memory console</span></header>",
        ~"<div class=\"container\">",
        Content,
        ~"</div></body></html>"
    ].

%% --- helpers ---

recall(~"") ->
    [];
recall(Query) ->
    case banto:recall(Query, #{limit => 8}) of
        {ok, Hits} -> Hits;
        {error, _} -> []
    end.

query_signal(Body) ->
    case datastar:read_signals(Body) of
        {ok, #{~"query" := Q}} when is_binary(Q) -> string:trim(Q);
        _ -> ~""
    end.

index_signals(Body) ->
    case datastar:read_signals(Body) of
        {ok, #{~"path" := P, ~"name" := N}} when is_binary(P), is_binary(N) ->
            case {string:trim(P), string:trim(N)} of
                {<<>>, _} -> {error, empty};
                {_, <<>>} -> {error, empty};
                {Path, Name} -> {ok, Name, Path}
            end;
        _ ->
            {error, bad}
    end.

-doc "Render the live index-job panel (pure).".
-spec jobs_html(banto_index_hub:jobs()) -> iodata().
jobs_html(Jobs) when map_size(Jobs) =:= 0 ->
    ~"<p class=\"empty\">no index jobs yet.</p>";
jobs_html(Jobs) ->
    [~"<ul class=\"jobs\">", [job_row(R, P) || {R, P} <- lists:sort(maps:to_list(Jobs))], ~"</ul>"].

job_row(Repo, #{done := Done, total := Total, chunks := Chunks} = P) ->
    Pct =
        case Total of
            0 -> 0;
            _ -> Done * 100 div Total
        end,
    Status =
        case maps:get(error, P, undefined) of
            undefined -> phase_label(maps:get(phase, P), Done, Total, Chunks);
            Err -> [~"error: ", html_escape(Err)]
        end,
    [
        ~"<li><div class=\"job-head\"><span class=\"repo\">",
        html_escape(Repo),
        ~"</span><span class=\"status\">",
        Status,
        ~"</span></div><div class=\"bar\"><div class=\"bar-fill\" style=\"width:",
        integer_to_binary(Pct),
        ~"%\"></div></div></li>"
    ].

phase_label(done, _Done, _Total, Chunks) ->
    [~"done - ", integer_to_binary(Chunks), ~" chunks"];
phase_label(start, _Done, Total, _Chunks) ->
    [~"starting - ", integer_to_binary(Total), ~" files"];
phase_label(_File, Done, Total, Chunks) ->
    [
        integer_to_binary(Done),
        ~"/",
        integer_to_binary(Total),
        ~" files, ",
        integer_to_binary(Chunks),
        ~" chunks"
    ].

-doc "Render an ask/recall flow as an ordered step list (pure).".
-spec flow_html([banto_knowledge:step()]) -> iodata().
flow_html([]) ->
    ~"<p class=\"empty\">the agent's flow will appear here.</p>";
flow_html(Steps) ->
    [~"<ol class=\"flow\">", [step_row(S) || S <- Steps], ~"</ol>"].

step_row(#{step := recall, phase := start} = S) ->
    flow_li(~"recall", [
        ~"searching for ", integer_to_binary(maps:get(question_len, S, 0)), ~" bytes"
    ]);
step_row(#{step := recall, phase := done} = S) ->
    flow_li(~"recall", [
        integer_to_binary(maps:get(count, S, 0)),
        ~" chunks<ul class=\"sources\">",
        [source_li(H) || H <- maps:get(sources, S, [])],
        ~"</ul>"
    ]);
step_row(#{step := prompt} = S) ->
    flow_li(~"prompt", [
        ~"built ",
        integer_to_binary(maps:get(prompt_len, S, 0)),
        ~" bytes for ",
        html_escape(maps:get(model, S, ~"?"))
    ]);
step_row(#{step := llm, phase := start} = S) ->
    flow_li(~"synthesise", [~"calling ", html_escape(maps:get(backend, S, ~"?"))]);
step_row(#{step := llm, phase := done} = S) ->
    flow_li(~"synthesise", [~"answer ", integer_to_binary(maps:get(answer_len, S, 0)), ~" bytes"]);
step_row(#{step := answer}) ->
    flow_li(~"answer", ~"done");
step_row(#{step := error} = S) ->
    flow_li(~"error", [
        ~"failed at ",
        atom_to_binary(maps:get(step_failed, S, unknown)),
        ~": ",
        html_escape(maps:get(reason, S, ~""))
    ]);
step_row(_Step) ->
    [].

source_li(#{repo := R, path := P} = H) ->
    [
        ~"<li>",
        html_escape(R),
        ~"/",
        html_escape(P),
        ~" <span class=\"kind\">",
        html_escape(maps:get(kind, H, ~"")),
        ~"</span></li>"
    ].

flow_li(Label, Body) ->
    [
        ~"<li class=\"flow-step\"><span class=\"label\">",
        Label,
        ~"</span><span class=\"detail\">",
        Body,
        ~"</span></li>"
    ].

-doc "Render the final answer (ask) or hit list (recall) for the #answer area (pure).".
-spec answer_html({ok, binary()} | {hits, [bunko_store:hit()]} | {error, term()}) -> iodata().
answer_html({ok, Answer}) ->
    [~"<div class=\"answer\"><pre>", html_escape(Answer), ~"</pre></div>"];
answer_html({hits, Hits}) ->
    results_html(Hits);
answer_html({error, Reason}) ->
    [~"<p class=\"empty\">error: ", html_escape(to_bin(Reason)), ~"</p>"].

to_bin(B) when is_binary(B) -> B;
to_bin(R) -> iolist_to_binary(io_lib:format("~p", [R])).

snippet(C) when is_binary(C) ->
    case byte_size(C) =< 500 of
        true -> C;
        false -> iolist_to_binary([binary:part(C, 0, 500), ~"..."])
    end;
snippet(_) ->
    ~"[non-text]".

html(Body) ->
    Headers = #{
        ~"content-type" => ~"text/html; charset=utf-8",
        ~"content-security-policy" =>
            ~"default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"
    },
    {status, 200, Headers, iolist_to_binary(Body)}.

html_escape(B) ->
    B1 = binary:replace(B, ~"&", ~"&amp;", [global]),
    B2 = binary:replace(B1, ~"<", ~"&lt;", [global]),
    B3 = binary:replace(B2, ~">", ~"&gt;", [global]),
    binary:replace(B3, ~"\"", ~"&quot;", [global]).
