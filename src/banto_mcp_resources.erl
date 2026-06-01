-module(banto_mcp_resources).
-moduledoc """
MCP resource provider: exposes each indexed repository as a readable resource
under `banto://repo/<name>`. `list/0` advertises one resource per repo (with its
indexed-memory count); `read/1` returns the repo's indexed file paths so a client
can see what banto knows about a repo without issuing a recall.
""".
-behaviour(madoguchi_resource).

-export([list/0, read/1]).

-define(SCHEME, ~"banto://repo/").

-doc "One resource descriptor per indexed repository.".
-spec list() -> [madoguchi_resource:resource()].
list() ->
    case banto_dashboard:repo_summary() of
        {ok, Summary} -> [descriptor(S) || S <- Summary];
        {error, _} -> []
    end.

-doc "Read a `banto://repo/<name>` URI: the repo's indexed file paths.".
-spec read(binary()) ->
    {ok, [madoguchi_resource:contents()]} | {error, not_found} | {error, binary()}.
read(Uri) ->
    case repo_of_uri(Uri) of
        {ok, Repo} ->
            case paths(Repo) of
                {ok, []} -> {error, not_found};
                {ok, Paths} -> {ok, [madoguchi_resource:text(Uri, render(Repo, Paths))]};
                {error, R} -> {error, banto_mcp_util:reason(R)}
            end;
        error ->
            {error, not_found}
    end.

%% --- internal ---

descriptor(#{repo := Repo, count := Count}) ->
    #{
        uri => <<?SCHEME/binary, Repo/binary>>,
        name => Repo,
        title => Repo,
        mimeType => ~"text/plain",
        description => iolist_to_binary([
            ~"Indexed repository ", Repo, ~" (", integer_to_binary(Count), ~" memories)."
        ])
    }.

repo_of_uri(Uri) ->
    case string:prefix(Uri, ?SCHEME) of
        nomatch -> error;
        ~"" -> error;
        Repo -> {ok, Repo}
    end.

paths(Repo) ->
    RepoMod = banto_config:repo(),
    SQL =
        ~"SELECT DISTINCT metadata->>'path' AS path FROM bunko_memories WHERE namespace = $1 AND metadata->>'repo' = $2 ORDER BY path",
    case RepoMod:query(SQL, [banto_config:namespace(), Repo]) of
        {ok, Rows} -> {ok, [P || #{path := P} <- Rows, is_binary(P)]};
        {error, _} = Err -> Err
    end.

render(Repo, Paths) ->
    iolist_to_binary([
        ~"# ",
        Repo,
        ~"\n\nIndexed files:\n",
        [[~"- ", P, ~"\n"] || P <- Paths]
    ]).
