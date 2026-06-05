-module(banto_index_job).
-moduledoc """
A supervised, fire-and-forget index run for one repo. Runs `banto_indexer:index/4`
with a progress callback that reports to `m:banto_index_hub`, then stops. Started
under `m:banto_index_sup`, so it survives the dashboard page that triggered it.
""".
-behaviour(gen_server).

-export([start/2, start_link/2]).
-export([init/1, handle_continue/2, handle_call/3, handle_cast/2]).

-doc "Start a background index of `Path` under repo short-name `Name`.".
-spec start(binary(), file:filename_all()) -> {ok, pid()} | {error, term()}.
start(Name, Path) ->
    banto_index_sup:start_job(Name, Path).

-spec start_link(binary(), file:filename_all()) -> {ok, pid()}.
start_link(Name, Path) ->
    gen_server:start_link(?MODULE, [Name, Path], []).

init([Name, Path]) ->
    {ok, #{repo => Name, path => Path}, {continue, run}}.

handle_continue(run, #{repo := Name, path := Path} = State) ->
    Progress = fun banto_index_hub:report/1,
    case banto_indexer:index(banto:ctx(), Path, Name, Progress) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            banto_index_hub:report(#{
                repo => Name,
                phase => done,
                done => 0,
                total => 0,
                chunks => 0,
                error => iolist_to_binary(io_lib:format("~p", [Reason]))
            })
    end,
    {stop, normal, State}.

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.
