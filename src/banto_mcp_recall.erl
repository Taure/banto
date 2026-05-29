-module(banto_mcp_recall).
-moduledoc "MCP tool: semantic search across the indexed repositories.".
-behaviour(madoguchi_tool).

-export([name/0, description/0, input_schema/0, call/1]).

name() -> ~"recall".

description() ->
    ~"Semantic search across the user's indexed repositories. Returns the most relevant code and documentation chunks with their source paths. Use this to find where something is implemented or how a pattern is used across repos.".

input_schema() ->
    #{
        ~"type" => ~"object",
        ~"properties" => #{
            ~"query" => #{~"type" => ~"string", ~"description" => ~"What to search for."},
            ~"limit" => #{~"type" => ~"integer", ~"description" => ~"Max hits (default 5)."},
            ~"repo" => #{
                ~"type" => ~"string", ~"description" => ~"Optional: restrict to one repo by name."
            }
        },
        ~"required" => [~"query"]
    }.

call(Args) ->
    Query = maps:get(~"query", Args),
    Opts = banto_mcp_util:opts(Args),
    case banto:recall(Query, Opts) of
        {ok, Hits} -> {ok, banto_mcp_util:format_hits(Hits)};
        {error, Reason} -> {error, banto_mcp_util:reason(Reason)}
    end.
