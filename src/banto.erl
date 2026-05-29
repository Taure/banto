-module(banto).
-moduledoc """
Multi-agent repo concierge: index your repositories into a shared semantic
memory, then recall or ask questions across them.

All repositories share one bunko namespace; each memory carries `repo`, `path`,
and `kind` metadata, so recall spans every repo and an optional `repo` filter
narrows it. LLM traffic routes through the configured `gakudan_llm` backend
(point it at a [sekisho](https://github.com/Taure/sekisho) gateway for central
keys, budgets, and audit); embeddings through the configured `bunko_embedder`.

See `m:banto_config` for the application-environment knobs.
""".

-export([ensure_schema/0, index/2, recall/2, ask/2, ctx/0]).

-doc "Create the bunko schema in the configured repo. Idempotent; call at setup.".
-spec ensure_schema() -> ok | {error, term()}.
ensure_schema() ->
    bunko_store_pgvector:install(#{repo => banto_config:repo()}).

-doc "The bunko context (store + embedder + namespace + summarizer) from config.".
-spec ctx() -> bunko:context().
ctx() ->
    #{
        store => banto_config:store(),
        embedder => banto_config:embedder(),
        namespace => banto_config:namespace(),
        summarizer => bunko_summarizer_stub
    }.

-doc """
Index a repository directory into the shared memory. `Opts` must carry
`name => binary()` (the repo's short name, recorded as `repo` metadata). Re-runs
replace the repo's previous memories. Returns counts of files and chunks stored.
""".
-spec index(file:filename_all(), map()) -> {ok, map()} | {error, term()}.
index(RepoPath, #{name := Name}) ->
    banto_indexer:index(ctx(), RepoPath, Name).

-doc """
Recall the most relevant memories for `Query`. `Opts`: `limit` (default 5) and an
optional `repo => binary()` filter (post-filters hits by `repo` metadata).
""".
-spec recall(binary(), map()) -> {ok, [bunko_store:hit()]} | {error, term()}.
recall(Query, Opts) ->
    case bunko:recall(ctx(), Query, Opts) of
        {ok, Hits} -> {ok, filter_repo(Hits, maps:get(repo, Opts, undefined))};
        {error, _} = Err -> Err
    end.

-doc """
Answer `Question` grounded in recalled memories: recall the top-k, feed them as
context, and synthesise an answer via the configured LLM. `Opts` as `recall/2`.
""".
-spec ask(binary(), map()) -> {ok, binary()} | {error, term()}.
ask(Question, Opts) ->
    banto_knowledge:ask(ctx(), Question, Opts).

filter_repo(Hits, undefined) ->
    Hits;
filter_repo(Hits, Repo) ->
    [H || H <- Hits, maps:get(~"repo", maps:get(metadata, H, #{}), undefined) =:= Repo].
