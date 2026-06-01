-module(banto_mcp_index).
-moduledoc "MCP tool: index (or re-index) a repository into the shared memory.".
-behaviour(madoguchi_tool).

-export([name/0, description/0, input_schema/0, annotations/0, call/1]).

name() -> ~"index_repo".

%% Not read-only: it writes to (and replaces) the shared memory for a repo.
annotations() ->
    #{
        title => ~"Index a repository",
        readOnlyHint => false,
        destructiveHint => true,
        idempotentHint => true
    }.

description() ->
    ~"Index a repository directory into banto's shared memory so it becomes searchable via recall/ask. Re-indexing replaces the repo's previous memories. Returns the number of files and chunks stored.".

input_schema() ->
    #{
        ~"type" => ~"object",
        ~"properties" => #{
            ~"path" => #{
                ~"type" => ~"string", ~"description" => ~"Absolute path to the repository."
            },
            ~"name" => #{
                ~"type" => ~"string", ~"description" => ~"Short repo name (recorded as metadata)."
            }
        },
        ~"required" => [~"path", ~"name"]
    }.

call(Args) ->
    Path = binary_to_list(maps:get(~"path", Args)),
    Name = maps:get(~"name", Args),
    case banto:index(Path, #{name => Name}) of
        {ok, #{files := Files, chunks := Chunks}} ->
            {ok,
                iolist_to_binary([
                    ~"Indexed ",
                    Name,
                    ~": ",
                    integer_to_binary(Files),
                    ~" files, ",
                    integer_to_binary(Chunks),
                    ~" chunks."
                ])};
        {error, Reason} ->
            {error, banto_mcp_util:reason(Reason)}
    end.
