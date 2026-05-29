-module(banto_maintenance).
-moduledoc """
Nightly maintenance report for a repository: a deterministic dependency check
(`banto_dep_audit`) plus an LLM doc-drift pass (`banto_maintainer_docs` grounded
by bunko-recalled docs + code). Intended to run on a schedule and open an issue
with the report.
""".

-export([run/2, format/2]).

-doc """
Produce a maintenance report for the repo at `RepoPath`. `Opts`: `repo` (the
indexed repo name, used to scope the doc-drift recall) and any `banto_run` opts.
""".
-spec run(file:filename_all(), map()) -> {ok, binary()}.
run(RepoPath, Opts) ->
    DepFindings = dep_findings(RepoPath),
    DocDrift = doc_drift(Opts),
    {ok, format(DepFindings, DocDrift)}.

-doc "Render a maintenance report from dep findings and the doc-drift text (pure).".
-spec format([banto_dep_audit:finding()], binary()) -> binary().
format(DepFindings, DocDrift) ->
    iolist_to_binary([
        ~"# banto maintenance report\n\n## Dependencies\n\n",
        banto_dep_audit:format(DepFindings),
        ~"\n\n## Documentation drift\n\n",
        DocDrift,
        ~"\n"
    ]).

%% --- internal ---

dep_findings(RepoPath) ->
    case banto_dep_audit:scan(filename:join(RepoPath, "rebar.config")) of
        {ok, Findings} -> Findings;
        {error, _} -> []
    end.

doc_drift(Opts) ->
    Limit = 8,
    RecallOpts =
        case maps:get(repo, Opts, undefined) of
            undefined -> #{limit => Limit};
            Repo -> #{limit => Limit, repo => Repo}
        end,
    Hits =
        case banto:recall(~"README module documentation public API examples status", RecallOpts) of
            {ok, H} -> H;
            {error, _} -> []
        end,
    Kickoff = iolist_to_binary([
        ~"Check this repository for documentation drift. Context follows.\n\n",
        banto_mcp_util:format_hits(Hits)
    ]),
    case banto_run:run([banto_maintainer_docs], Kickoff, Opts) of
        {ok, [#{content := Content} | _]} -> Content;
        {ok, []} -> ~"(no doc-drift output)";
        {error, _} -> ~"(doc-drift agent unavailable)"
    end.
