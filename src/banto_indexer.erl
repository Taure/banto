-module(banto_indexer).
-moduledoc """
Walk a repository, chunk its source and docs, and store each chunk as a bunko
memory tagged with `repo`, `path`, and `kind` metadata. Re-indexing a repo first
deletes its previous memories, so the operation is idempotent per repo.
""".

-export([index/3, index/4, collect_files/1, chunk/1]).

-type progress() :: #{
    repo := binary(),
    phase := start | file | done,
    done := non_neg_integer(),
    total := non_neg_integer(),
    chunks := non_neg_integer(),
    file => binary(),
    error => binary()
}.
-export_type([progress/0]).

%% File types worth indexing for code/doc retrieval.
-define(EXTS, [~".erl", ~".hrl", ~".ex", ~".exs", ~".md", ~".config", ~".src", ~".app"]).
-define(SKIP_DIRS, [~"_build", ~".git", ~"deps", ~"_checkouts", ~"node_modules", ~"doc"]).
-define(MAX_BYTES, 262144).
-define(CHUNK_LINES, 60).

-doc "Index `RepoPath` under repo short-name `Name`. Returns `{files, chunks}` counts.".
-spec index(bunko:context(), file:filename_all(), binary()) -> {ok, map()} | {error, term()}.
index(Ctx, RepoPath, Name) ->
    index(Ctx, RepoPath, Name, fun(_) -> ok end).

-doc "Index `RepoPath`, invoking `Progress` with a `t:progress/0` map per file.".
-spec index(bunko:context(), file:filename_all(), binary(), fun((progress()) -> ok)) ->
    {ok, map()} | {error, term()}.
index(Ctx, RepoPath, Name, Progress) ->
    Root = to_path_list(RepoPath),
    case delete_existing(Ctx, Name) of
        ok ->
            Files = collect_files(Root),
            Total = length(Files),
            Progress(#{repo => Name, phase => start, done => 0, total => Total, chunks => 0}),
            {Stored, Chunks} = store_files(Ctx, Root, Name, Files, 0, 0, 0, Total, Progress),
            Progress(#{
                repo => Name, phase => done, done => Stored, total => Total, chunks => Chunks
            }),
            {ok, #{files => Stored, chunks => Chunks}};
        {error, _} = Err ->
            Err
    end.

%% --- file walking ---

-doc "Recursively collect indexable file paths under `Root`.".
-spec collect_files(file:filename_all()) -> [file:filename_all()].
collect_files(Root) ->
    lists:reverse(walk(to_path_list(Root), [])).

%% Normalise a filename_all() to a charlist so the walk and metadata paths
%% (which compare and concatenate with strings) work for binary inputs too -
%% MCP/JSON paths arrive as binaries.
to_path_list(P) when is_binary(P) -> unicode:characters_to_list(P);
to_path_list(P) -> P.

walk(Path, Acc) ->
    case filelib:is_dir(Path) of
        true ->
            case lists:member(list_to_binary(filename:basename(Path)), ?SKIP_DIRS) of
                true ->
                    Acc;
                false ->
                    {ok, Entries} = file:list_dir(Path),
                    walk_entries([filename:join(Path, E) || E <- lists:sort(Entries)], Acc)
            end;
        false ->
            case wanted(Path) of
                true -> [Path | Acc];
                false -> Acc
            end
    end.

walk_entries([], Acc) ->
    Acc;
walk_entries([P | Rest], Acc) ->
    walk_entries(Rest, walk(P, Acc)).

wanted(Path) ->
    lists:member(list_to_binary(filename:extension(Path)), ?EXTS) andalso
        filelib:file_size(Path) =< ?MAX_BYTES.

%% --- storing ---

store_files(_Ctx, _Root, _Name, [], Files, Chunks, _Pos, _Total, _Progress) ->
    {Files, Chunks};
store_files(Ctx, Root, Name, [Path | Rest], Files, Chunks, Pos, Total, Progress) ->
    {Inc, Stored, Rel} =
        case file:read_file(Path) of
            {ok, Content} ->
                R = relative(Root, Path),
                S = store_chunks(Ctx, Name, R, kind(Path), chunk(Content)),
                {
                    case S of
                        0 -> 0;
                        _ -> 1
                    end,
                    S,
                    R
                };
            {error, _} ->
                {0, 0, relative(Root, Path)}
        end,
    Pos1 = Pos + 1,
    Files1 = Files + Inc,
    Chunks1 = Chunks + Stored,
    Progress(#{
        repo => Name, phase => file, file => Rel, done => Pos1, total => Total, chunks => Chunks1
    }),
    store_files(Ctx, Root, Name, Rest, Files1, Chunks1, Pos1, Total, Progress).

store_chunks(Ctx, Name, Rel, Kind, Parts) ->
    store_chunks(Ctx, Name, Rel, Kind, Parts, 0, 0).

store_chunks(_Ctx, _Name, _Rel, _Kind, [], _Idx, Stored) ->
    Stored;
store_chunks(Ctx, Name, Rel, Kind, [Part | Rest], Idx, Stored) ->
    Meta = #{~"repo" => Name, ~"path" => Rel, ~"kind" => Kind, ~"chunk" => Idx},
    Inc =
        case string:trim(Part) of
            <<>> ->
                0;
            _ ->
                case bunko:remember(Ctx, Part, Meta) of
                    {ok, _} -> 1;
                    {error, _} -> 0
                end
        end,
    store_chunks(Ctx, Name, Rel, Kind, Rest, Idx + 1, Stored + Inc).

%% --- chunking ---

-doc "Split file content into line-bounded chunks of at most ?CHUNK_LINES lines.".
-spec chunk(binary()) -> [binary()].
chunk(Content) ->
    Lines = binary:split(Content, ~"\n", [global]),
    [iolist_to_binary(lists:join(~"\n", Group)) || Group <- group(Lines, ?CHUNK_LINES)].

group([], _N) ->
    [];
group(Lines, N) ->
    {Head, Tail} = split(Lines, N, []),
    [Head | group(Tail, N)].

split(Rest, 0, Acc) ->
    {lists:reverse(Acc), Rest};
split([], _N, Acc) ->
    {lists:reverse(Acc), []};
split([H | T], N, Acc) ->
    split(T, N - 1, [H | Acc]).

%% --- helpers ---

delete_existing(Ctx, Name) ->
    Store = maps:get(store, Ctx),
    NS = maps:get(namespace, Ctx),
    case bunko_store:all(Store, NS) of
        {ok, Memories} ->
            Ids = [
                maps:get(id, M)
             || M <- Memories,
                maps:get(~"repo", maps:get(metadata, M, #{}), undefined) =:= Name
            ],
            delete_ids(Store, Ids);
        {error, _} = Err ->
            Err
    end.

delete_ids(_Store, []) -> ok;
delete_ids(Store, Ids) -> bunko_store:delete(Store, Ids).

relative(Root, Path) ->
    R = string:trim(filename:flatten(Root), trailing, "/"),
    case string:prefix(Path, R ++ "/") of
        nomatch -> list_to_binary(Path);
        Rel -> list_to_binary(Rel)
    end.

kind(Path) ->
    case list_to_binary(filename:extension(Path)) of
        ~".md" -> ~"doc";
        ~".config" -> ~"config";
        ~".src" -> ~"config";
        ~".app" -> ~"config";
        _ -> ~"code"
    end.
