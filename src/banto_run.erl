-module(banto_run).
-moduledoc """
Runs a set of `gakudan_agent`s once over a kickoff message via
`gakudan_router_fanout` and collects each agent's blackboard entry. Shared by
the review swarm and the maintenance agents - the start/send/await/stop dance and
the per-agent extraction live here.
""".

-export([run/3]).

-define(TIMEOUT, 120_000).

-doc """
Run `Agents` (modules implementing `gakudan_agent`) once over `Kickoff`. Returns
one entry per agent: `#{agent := atom(), content := binary()}`. `Opts`: `timeout`
(ms), `llm` (a `gakudan_llm` ref; defaults to `banto_config:llm/0`).
""".
-spec run([module()], binary(), map()) -> {ok, [map()]} | {error, term()}.
run(Agents, Kickoff, Opts) ->
    case
        gakudan:start_run(#{
            agents => Agents,
            router => {gakudan_router_fanout, #{rounds => 1}},
            llm => maps:get(llm, Opts, banto_config:llm()),
            max_turns => length(Agents) + 2
        })
    of
        {ok, _Pid, RunId} ->
            ok = gakudan:send(RunId, Kickoff),
            Result =
                case gakudan:await(RunId, maps:get(timeout, Opts, ?TIMEOUT)) of
                    {ok, Entries} -> {ok, collect(Entries)};
                    {error, _} = Err -> Err
                end,
            _ = gakudan:stop(RunId),
            Result;
        {error, _} = Err ->
            Err
    end.

collect(Entries) ->
    [#{agent => A, content => content_text(C)} || #{role := {agent, A}, content := C} <- Entries].

content_text(C) when is_binary(C) ->
    C;
content_text(Blocks) when is_list(Blocks) ->
    iolist_to_binary([T || #{type := text, text := T} <- Blocks]).
