-module(banto_dashboard_page).
-moduledoc """
Nova controllers for the memory dashboard. `index/1` server-renders the shell:
the indexed-repo summary and a Datastar-bound recall search box. `search/1`
reads the `query` signal Datastar posts, runs `banto:recall`, and returns a
single Datastar patch of `#results` (one-shot SSE, no held connection).
""".

%% index/1 takes Req by the Nova controller contract even though it is unused.
-hank([{unnecessary_function_arguments, [{index, 1, 1}]}]).

-export([index/1, search/1]).
-export([page/2, repo_summary_html/1, results_html/1, query_signal/1]).

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

%% --- rendering ---

body(Summary) ->
    [
        ~"<h2>indexed repositories</h2>",
        repo_summary_html(Summary),
        ~"<h2>recall</h2>",
        ~"<div data-signals-query=\"''\"><div class=\"search\">",
        ~"<input type=\"text\" placeholder=\"search across your repos...\" data-bind-query>",
        ~"<button data-on-click=\"@post('/dashboard/search')\">recall</button></div>",
        ~"<div id=\"results\" class=\"results\"><p class=\"empty\">enter a query above.</p></div></div>"
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
