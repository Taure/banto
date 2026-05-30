-module(banto_index_hub).
-moduledoc """
Central registry and pub/sub for background index jobs. Jobs `report/1` their
progress here; dashboard SSE connections `subscribe/0` to receive a snapshot plus
every subsequent update as a `{banto_index_progress, Jobs}` message. Subscribers
are monitored and dropped when they disconnect.
""".
-behaviour(gen_server).

-export([start_link/0, report/1, subscribe/0, snapshot/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-type jobs() :: #{binary() => banto_indexer:progress()}.
-export_type([jobs/0]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-doc "Report a job's progress. Called from the indexer's progress callback.".
-spec report(banto_indexer:progress()) -> ok.
report(Progress) ->
    gen_server:cast(?MODULE, {report, Progress}).

-doc "Subscribe the caller to progress updates; returns the current snapshot.".
-spec subscribe() -> jobs().
subscribe() ->
    gen_server:call(?MODULE, {subscribe, self()}).

-doc "Current per-repo job state.".
-spec snapshot() -> jobs().
snapshot() ->
    gen_server:call(?MODULE, snapshot).

init([]) ->
    {ok, #{jobs => #{}, subs => #{}}}.

handle_call({subscribe, Pid}, _From, #{subs := Subs, jobs := Jobs} = State) ->
    Ref = erlang:monitor(process, Pid),
    {reply, Jobs, State#{subs => Subs#{Pid => Ref}}};
handle_call(snapshot, _From, #{jobs := Jobs} = State) ->
    {reply, Jobs, State};
handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({report, #{repo := Repo} = Progress}, #{jobs := Jobs, subs := Subs} = State) ->
    Jobs1 = Jobs#{Repo => Progress},
    broadcast(Subs, Jobs1),
    {noreply, State#{jobs => Jobs1}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #{subs := Subs} = State) ->
    {noreply, State#{subs => maps:remove(Pid, Subs)}};
handle_info(_Msg, State) ->
    {noreply, State}.

broadcast(Subs, Jobs) ->
    maps:foreach(fun(Pid, _Ref) -> Pid ! {banto_index_progress, Jobs} end, Subs).
