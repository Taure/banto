-module(banto_app).
-moduledoc false.
-behaviour(application).

-include_lib("kernel/include/logger.hrl").

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = banto_sup:start_link(),
    ok = install_schema(),
    _ = nova_handlers:register_handler(stream, fun banto_stream:handle/3),
    ok = maybe_start_mcp(),
    {ok, Sup}.

stop(_State) ->
    ok.

%% Provision the bunko schema on boot (idempotent). Best-effort: if the DB is
%% not yet reachable, log and continue so the node still starts.
install_schema() ->
    case banto:ensure_schema() of
        ok ->
            ok;
        {error, Reason} ->
            ?LOG_WARNING(#{event => schema_install_failed, reason => Reason}),
            ok
    end.

%% In the `dashboard` role Nova serves the public surface and the MCP listener is
%% not needed. In the `mcp` role (or locally, when BANTO_ROLE is unset) start the
%% madoguchi MCP server. Nova's own listener always starts from its app config.
maybe_start_mcp() ->
    case os:getenv("BANTO_ROLE") of
        "dashboard" ->
            ok;
        _ ->
            _ = banto_mcp:start(),
            ok
    end.
