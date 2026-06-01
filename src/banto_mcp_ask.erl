-module(banto_mcp_ask).
-moduledoc "MCP tool: ask a question answered from the indexed repositories.".
-behaviour(madoguchi_tool).

-export([name/0, description/0, input_schema/0, annotations/0, call/1]).

name() -> ~"ask".

annotations() ->
    #{
        title => ~"Ask across repositories",
        readOnlyHint => true,
        openWorldHint => true
    }.

description() ->
    ~"Ask a question about the user's repositories. Recalls relevant context and answers from it, citing source paths. Use this for 'how/why/where do we...' questions grounded in the actual codebase rather than guessing.".

input_schema() ->
    #{
        ~"type" => ~"object",
        ~"properties" => #{
            ~"question" => #{~"type" => ~"string", ~"description" => ~"The question to answer."},
            ~"limit" => #{
                ~"type" => ~"integer", ~"description" => ~"Context chunks to recall (default 5)."
            },
            ~"repo" => #{
                ~"type" => ~"string", ~"description" => ~"Optional: restrict to one repo by name."
            }
        },
        ~"required" => [~"question"]
    }.

call(Args) ->
    Question = maps:get(~"question", Args),
    Opts = banto_mcp_util:opts(Args),
    case banto:ask(Question, Opts) of
        {ok, Answer} -> {ok, Answer};
        {error, Reason} -> {error, banto_mcp_util:reason(Reason)}
    end.
