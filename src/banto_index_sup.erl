-module(banto_index_sup).
-moduledoc "Dynamic supervisor for background index jobs (`m:banto_index_job`).".
-behaviour(supervisor).

-export([start_link/0, start_job/2]).
-export([init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_job(binary(), file:filename_all()) -> {ok, pid()} | {error, term()}.
start_job(Name, Path) ->
    supervisor:start_child(?MODULE, [Name, Path]).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one, intensity => 10, period => 10},
    ChildSpec = #{
        id => banto_index_job,
        start => {banto_index_job, start_link, []},
        restart => temporary,
        type => worker
    },
    {ok, {SupFlags, [ChildSpec]}}.
