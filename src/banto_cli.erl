-module(banto_cli).
-moduledoc """
Command-line entry point (built as an escript via `rebar3 escriptize`).

```
banto_cli index <path> <name>   # index a repo into the shared memory
banto_cli recall <query>        # semantic search across indexed repos
banto_cli ask <question>        # grounded answer across indexed repos
banto_cli review <diff-file>    # run the review swarm over a diff
banto_cli maintain <path> <name> # dependency + doc-drift maintenance report
```

Reads the same `banto` app configuration as the service (see `m:banto_config`);
provide it via `-config` or the application environment.
""".

-export([main/1, parse/1]).

-spec main([string()]) -> no_return().
main(Args) ->
    case parse(Args) of
        {ok, Cmd} ->
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
        | {maintain, string(), binary()}}
    | {error, usage}.
parse(["index", Path, Name]) -> {ok, {index, Path, list_to_binary(Name)}};
parse(["recall", Query]) -> {ok, {recall, list_to_binary(Query)}};
parse(["ask", Question]) -> {ok, {ask, list_to_binary(Question)}};
parse(["review", File]) -> {ok, {review, File}};
parse(["maintain", Path, Name]) -> {ok, {maintain, Path, list_to_binary(Name)}};
parse(_) -> {error, usage}.

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
    "  maintain <path> <name>  dependency + doc-drift maintenance report\n".
