-module(banto_dep_audit).
-moduledoc """
Deterministic dependency check for a repo's `rebar.config`: flags git
dependencies pinned to a moving `branch` (non-reproducible builds). Tag-pinned,
ref-pinned, and hex-versioned deps are considered fine. Structured, not an LLM
job - deps are data.
""".

-export([scan/1, findings/1, format/1]).

-type finding() :: #{dep := atom(), issue := atom(), detail := term()}.

-export_type([finding/0]).

-doc "Scan a `rebar.config` file for dependency findings.".
-spec scan(file:filename_all()) -> {ok, [finding()]} | {error, term()}.
scan(RebarConfigPath) ->
    case file:consult(RebarConfigPath) of
        {ok, Terms} -> {ok, findings(deps(Terms))};
        {error, _} = Err -> Err
    end.

-doc "Findings for a parsed deps list (pure).".
-spec findings([term()]) -> [finding()].
findings(Deps) ->
    lists:flatten([finding(D) || D <- Deps]).

-doc "Render findings as markdown.".
-spec format([finding()]) -> binary().
format([]) ->
    ~"No dependency issues: every dependency is pinned.";
format(Findings) ->
    iolist_to_binary([
        ~"Unpinned dependencies (pin to a tag for reproducible builds):\n",
        [line(F) || F <- Findings]
    ]).

%% --- internal ---

deps(Terms) ->
    proplists:get_value(deps, Terms, []).

finding({Name, {git, _Url, {branch, Branch}}}) ->
    [#{dep => Name, issue => unpinned_branch, detail => Branch}];
finding({Name, {git, _Url, {branch, Branch}}, _Opts}) ->
    [#{dep => Name, issue => unpinned_branch, detail => Branch}];
finding(_Pinned) ->
    [].

line(#{dep := Dep, detail := Branch}) ->
    [~"- ", atom_to_binary(Dep), ~" (branch: ", to_bin(Branch), ~")\n"].

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A).
