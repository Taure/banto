-module(banto_flow_hub).
-moduledoc """
Live pub/sub for the most recent ask/recall flow, so the dashboard can observe
flows triggered from anywhere on this node (console, MCP, CLI) - the
gakudan_liveboard model. `banto_knowledge` reports each `t:banto_knowledge:step/0`
here; dashboard SSE connections `subscribe/0` for a snapshot plus every update as
a `{banto_flow_update, Steps, Answer}` message. A `recall`/`start` step begins a
fresh flow. Subscribers are monitored and dropped on disconnect.
""".
-behaviour(gen_server).

-export([start_link/0, report/1, subscribe/0, snapshot/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-type answer() :: undefined | {ok, binary()} | {error, binary()}.
-export_type([answer/0]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-doc "Report a flow step. Safe to call when the hub is not running (no-op).".
-spec report(banto_knowledge:step()) -> ok.
report(Step) ->
    case erlang:whereis(?MODULE) of
        undefined -> ok;
        _ -> gen_server:cast(?MODULE, {report, Step})
    end.

-doc "Subscribe the caller; returns the current `{Steps, Answer}` snapshot.".
-spec subscribe() -> {[banto_knowledge:step()], answer()}.
subscribe() ->
    gen_server:call(?MODULE, {subscribe, self()}).

-spec snapshot() -> {[banto_knowledge:step()], answer()}.
snapshot() ->
    gen_server:call(?MODULE, snapshot).

init([]) ->
    {ok, #{steps => [], answer => undefined, subs => #{}}}.

handle_call({subscribe, Pid}, _From, #{subs := Subs} = State) ->
    Ref = erlang:monitor(process, Pid),
    {reply, snap(State), State#{subs => Subs#{Pid => Ref}}};
handle_call(snapshot, _From, State) ->
    {reply, snap(State), State};
handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({report, Step}, State0) ->
    State = apply_step(Step, State0),
    broadcast(State),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #{subs := Subs} = State) ->
    {noreply, State#{subs => maps:remove(Pid, Subs)}};
handle_info(_Msg, State) ->
    {noreply, State}.

%% A recall/start step begins a fresh flow; answer/error steps capture the result.
apply_step(#{step := recall, phase := start} = Step, State) ->
    State#{steps => [Step], answer => undefined};
apply_step(#{step := answer, answer := Answer} = Step, #{steps := Steps} = State) ->
    State#{steps => Steps ++ [Step], answer => {ok, Answer}};
apply_step(#{step := error, reason := Reason} = Step, #{steps := Steps} = State) ->
    State#{steps => Steps ++ [Step], answer => {error, Reason}};
apply_step(Step, #{steps := Steps} = State) ->
    State#{steps => Steps ++ [Step]}.

snap(#{steps := Steps, answer := Answer}) ->
    {Steps, Answer}.

broadcast(#{steps := Steps, answer := Answer, subs := Subs}) ->
    maps:foreach(fun(Pid, _Ref) -> Pid ! {banto_flow_update, Steps, Answer} end, Subs).
