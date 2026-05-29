-module(banto_review).
-moduledoc """
PR review swarm. Fans out specialist reviewer agents (security, conventions,
tests, architecture) over a diff with `gakudan_router_fanout` - they run
concurrently, each grounded by the same bunko-recalled repository context
(ADRs, conventions, prior code). Collects each agent's finding from the run
blackboard and renders one review.

This is where gakudan's orchestration earns its keep: parallel specialist
perspectives on one diff, not a single prompt.
""".

-export([review/2, agents/0, build_kickoff/2, format/1, reviews/1]).

-define(AGENTS, [
    banto_reviewer_security,
    banto_reviewer_conventions,
    banto_reviewer_tests,
    banto_reviewer_architecture
]).
-define(TIMEOUT, 120_000).

-doc "The reviewer agents in the swarm.".
-spec agents() -> [module()].
agents() -> ?AGENTS.

-doc """
Run the review swarm over `Diff`. `Opts`: `context_limit` (recalled chunks,
default 6), `repo` (restrict recall to one repo), `timeout` (ms). Returns one
entry per reviewer: `#{agent := atom(), content := binary()}`.
""".
-spec review(binary(), map()) -> {ok, [map()]} | {error, term()}.
review(Diff, Opts) ->
    Hits = recall_context(Diff, Opts),
    Kickoff = build_kickoff(Diff, Hits),
    case
        gakudan:start_run(#{
            agents => ?AGENTS,
            router => {gakudan_router_fanout, #{rounds => 1}},
            llm => banto_config:llm(),
            max_turns => length(?AGENTS) + 2
        })
    of
        {ok, _Pid, RunId} ->
            ok = gakudan:send(RunId, Kickoff),
            Result =
                case gakudan:await(RunId, maps:get(timeout, Opts, ?TIMEOUT)) of
                    {ok, Entries} -> {ok, reviews(Entries)};
                    {error, _} = Err -> Err
                end,
            _ = gakudan:stop(RunId),
            Result;
        {error, _} = Err ->
            Err
    end.

-doc "Extract per-agent review entries from a run's blackboard transcript.".
-spec reviews([map()]) -> [map()].
reviews(Entries) ->
    [#{agent => A, content => content_text(C)} || #{role := {agent, A}, content := C} <- Entries].

-doc "Build the swarm kickoff message: recalled context + the diff.".
-spec build_kickoff(binary(), [bunko_store:hit()]) -> binary().
build_kickoff(Diff, Hits) ->
    iolist_to_binary([
        ~"Review the following diff. Repository context is provided first - use it to ground your review.\n\n## Repository context\n\n",
        banto_mcp_util:format_hits(Hits),
        ~"\n\n## Diff\n\n",
        Diff
    ]).

-doc "Render the swarm's reviews as a single markdown document.".
-spec format([map()]) -> binary().
format(Reviews) ->
    iolist_to_binary([
        ~"# banto review\n",
        [section(R) || R <- Reviews]
    ]).

%% --- internal ---

section(#{agent := Agent, content := Content}) ->
    [~"\n## ", atom_to_binary(Agent), ~"\n\n", Content, ~"\n"].

recall_context(Diff, Opts) ->
    Limit = maps:get(context_limit, Opts, 6),
    RecallOpts =
        case maps:get(repo, Opts, undefined) of
            undefined -> #{limit => Limit};
            Repo -> #{limit => Limit, repo => Repo}
        end,
    case banto:recall(recall_query(Diff), RecallOpts) of
        {ok, Hits} -> Hits;
        {error, _} -> []
    end.

%% The head of the diff (changed paths + first hunks) is the recall query.
recall_query(Diff) ->
    binary:part(Diff, 0, min(byte_size(Diff), 2000)).

content_text(C) when is_binary(C) ->
    C;
content_text(Blocks) when is_list(Blocks) ->
    iolist_to_binary([T || #{type := text, text := T} <- Blocks]).
