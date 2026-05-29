-module(banto_app).
-moduledoc false.
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = banto_sup:start_link(),
    _ = banto_mcp:start(),
    {ok, Sup}.

stop(_State) ->
    ok.
