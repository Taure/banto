-module(banto_cli).
-moduledoc """
Command-line entry point (built as an escript via `rebar3 escriptize`).

```
banto_cli index <path> <name>   # index a repo into the shared memory
banto_cli recall <query>        # semantic search across indexed repos
banto_cli ask <question>        # grounded answer across indexed repos
banto_cli review <diff-file>    # run the review swarm over a diff
banto_cli maintain <path> <name> # dependency + doc-drift maintenance report
banto_cli mcp-stdio             # run banto as a local MCP server over stdio
```

Reads the same `banto` app configuration as the service (see `m:banto_config`);
provide it via `-config` or the application environment.
""".

-export([main/1, parse/1]).

-spec main([string()]) -> no_return().
main(Args) ->
    case parse(Args) of
        {ok, Cmd} ->
            _ = maybe_stdio_role(Cmd),
            {ok, _} = application:ensure_all_started(banto),
            halt(run(Cmd));
        {error, usage} ->
            io:format(standard_error, usage(), []),
            halt(2)
    end.

-doc "Parse argv into a command. Pure; exported for testing.".
-spec parse([string()]) ->
    {ok,
        {index, string(), binary()}
        | {recall, binary()}
        | {ask, binary()}
        | {review, string()}
        | {maintain, string(), binary()}
        | mcp_stdio}
    | {error, usage}.
parse(["index", Path, Name]) -> {ok, {index, Path, list_to_binary(Name)}};
parse(["recall", Query]) -> {ok, {recall, list_to_binary(Query)}};
parse(["ask", Question]) -> {ok, {ask, list_to_binary(Question)}};
parse(["review", File]) -> {ok, {review, File}};
parse(["maintain", Path, Name]) -> {ok, {maintain, Path, list_to_binary(Name)}};
parse(["mcp-stdio"]) -> {ok, mcp_stdio};
parse(_) -> {error, usage}.

%% In stdio mode stdout carries MCP protocol traffic, so the HTTP listener (and
%% nothing else) must not be started by app boot: mark the role so
%% banto_app:maybe_start_mcp/0 skips the HTTP transport.
maybe_stdio_role(mcp_stdio) -> os:putenv("BANTO_ROLE", "stdio");
maybe_stdio_role(_) -> ok.

%% --- dispatch ---

run({index, Path, Name}) ->
    ok = banto:ensure_schema(),
    case banto:index(Path, #{name => Name}) of
        {ok, #{files := F, chunks := C}} ->
            io:format("indexed ~s: ~p files, ~p chunks~n", [Name, F, C]),
            0;
        {error, Reason} ->
            fail(Reason)
    end;
run({recall, Query}) ->
    case banto:recall(Query, #{}) of
        {ok, Hits} ->
            io:format("~s~n", [banto_mcp_util:format_hits(Hits)]),
            0;
        {error, Reason} ->
            fail(Reason)
    end;
run({ask, Question}) ->
    case banto:ask(Question, #{}) of
        {ok, Answer} ->
            io:format("~s~n", [Answer]),
            0;
        {error, Reason} ->
            fail(Reason)
    end;
run({review, File}) ->
    case file:read_file(File) of
        {ok, Diff} ->
            case banto_review:review(Diff, #{}) of
                {ok, Reviews} ->
                    io:format("~s~n", [banto_review:format(Reviews)]),
                    0;
                {error, Reason} ->
                    fail(Reason)
            end;
        {error, Reason} ->
            fail(Reason)
    end;
run({maintain, Path, Name}) ->
    {ok, Report} = banto_maintenance:run(Path, #{repo => Name}),
    io:format("~s~n", [Report]),
    0;
run(mcp_stdio) ->
    ok = banto_mcp:start_stdio(),
    0.

fail(Reason) ->
    io:format(standard_error, "banto: error: ~p~n", [Reason]),
    1.

usage() ->
    "usage: banto_cli <command>\n"
    "  index <path> <name>   index a repo into the shared memory\n"
    "  recall <query>        semantic search across indexed repos\n"
    "  ask <question>        grounded answer across indexed repos\n"
    "  review <diff-file>    run the review swarm over a diff\n"
    "  maintain <path> <name>  dependency + doc-drift maintenance report\n"
    "  mcp-stdio             run banto as a local MCP server over stdio\n".
