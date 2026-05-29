-module(banto_dashboard).
-moduledoc """
Data for the memory dashboard: a per-repo summary of what banto has indexed,
read from the bunko store via the configured kura repo.
""".

-export([repo_summary/0]).

-doc "Indexed repos with their memory counts, most-indexed first.".
-spec repo_summary() -> {ok, [#{repo := binary(), count := integer()}]} | {error, term()}.
repo_summary() ->
    Repo = banto_config:repo(),
    SQL =
        ~"SELECT metadata->>'repo' AS repo, count(*) AS n FROM bunko_memories WHERE namespace = $1 GROUP BY metadata->>'repo' ORDER BY n DESC",
    case Repo:query(SQL, [banto_config:namespace()]) of
        {ok, Rows} ->
            {ok, [#{repo => repo_of(R), count => maps:get(n, R)} || R <- Rows]};
        {error, _} = Err ->
            Err
    end.

repo_of(#{repo := R}) when is_binary(R) -> R;
repo_of(_) -> ~"(unattributed)".
