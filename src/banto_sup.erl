-module(banto_sup).
-moduledoc false.
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    Children = [
        #{id => banto_index_hub, start => {banto_index_hub, start_link, []}, type => worker},
        #{id => banto_flow_hub, start => {banto_flow_hub, start_link, []}, type => worker},
        #{id => banto_index_sup, start => {banto_index_sup, start_link, []}, type => supervisor}
    ],
    {ok, {SupFlags, Children}}.
