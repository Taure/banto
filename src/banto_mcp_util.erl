-module(banto_mcp_util).
-moduledoc false.

-include_lib("kernel/include/logger.hrl").

-export([opts/1, format_hits/1, reason/1]).

-doc "Build recall/ask Opts from MCP tool arguments (limit + optional repo).".
-spec opts(map()) -> map().
opts(Args) ->
    Base = #{limit => maps:get(~"limit", Args, 5)},
    case maps:get(~"repo", Args, undefined) of
        undefined -> Base;
        Repo -> Base#{repo => Repo}
    end.

-doc "Render recall hits as readable text for an MCP client.".
-spec format_hits([bunko_store:hit()]) -> binary().
format_hits([]) ->
    ~"No matches found.";
format_hits(Hits) ->
    iolist_to_binary(lists:join(~"\n\n", [format_hit(H) || H <- Hits])).

format_hit(#{content := Content} = Hit) ->
    Meta = maps:get(metadata, Hit, #{}),
    Repo = maps:get(~"repo", Meta, ~"?"),
    Path = maps:get(~"path", Meta, ~"?"),
    [~"[", Repo, ~"/", Path, ~"]\n", Content].

-doc "Log an internal error reason server-side; return a generic client-safe message.".
-spec reason(term()) -> binary().
reason(Reason) ->
    ?LOG_WARNING(#{event => mcp_tool_error, reason => Reason}),
    ~"banto: internal error".
