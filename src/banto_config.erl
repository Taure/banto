-module(banto_config).
-moduledoc """
Reads banto's runtime configuration from the `banto` application environment,
with defaults that keep CI offline and deterministic (stub embedder + stub LLM).

| Key | Default | Meaning |
| --- | --- | --- |
| `repo` | `banto_repo` | the kura repo module backing the store |
| `namespace` | `~"banto"` | the single bunko namespace; repos are told apart by metadata |
| `embedder` | `bunko_embedder_stub` | a `bunko_embedder` ref; set `{banto_embedder, #{...}}` for real |
| `llm` | `{gakudan_llm_stub, #{}}` | a `gakudan_llm` ref; point at sekisho for real |
| `model` | `~"claude-sonnet-4-6"` | the model name sent in completions |
| `mcp_port` | `8080` | the madoguchi MCP server port |
| `max_distance` | `undefined` | drop recall hits whose cosine distance exceeds this |
| `hybrid` | `true` | fuse keyword (BM25/tsvector) + vector lanes for recall |
| `embed_cache` | `true` | content-hash embedding cache on the embedder ref |
| `llm_retry` | `#{max_attempts => 3}` | wrap the LLM backend in a retry backend; `false` to disable |
| `llm_fallback` | `[]` | extra `{Mod, Opts}` backends to fall through to after the primary |
""".

-export([repo/0, store/0, embedder/0, llm/0, resilient_llm/0, model/0, mcp_port/0, namespace/0]).
-export([max_distance/0, hybrid/0, llm_retry/0, llm_fallback/0]).

-spec repo() -> module().
repo() -> application:get_env(banto, repo, banto_repo).

-spec store() -> bunko_store:ref().
store() -> {bunko_store_pgvector, #{repo => repo()}}.

-spec embedder() -> bunko_embedder:ref().
embedder() ->
    Ref = application:get_env(banto, embedder, bunko_embedder_stub),
    case embed_cache() of
        true -> with_cache(Ref);
        false -> Ref
    end.

embed_cache() -> application:get_env(banto, embed_cache, true).

with_cache(Mod) when is_atom(Mod) -> {Mod, #{cache => true}};
with_cache({Mod, Opts}) -> {Mod, Opts#{cache => true}}.

-spec llm() -> {module(), map()}.
llm() -> application:get_env(banto, llm, {gakudan_llm_stub, #{}}).

-doc """
The configured LLM backend wrapped for resilience: optional fallback backends
first, then a retry/backoff wrapper, so transient upstream errors do not fail an
ask or review. Set `llm_retry` to `false` and `llm_fallback` to `[]` to get the
raw backend back.
""".
-spec resilient_llm() -> {module(), map()}.
resilient_llm() ->
    with_retry(with_fallback(llm(), llm_fallback())).

with_fallback(Primary, []) ->
    Primary;
with_fallback(Primary, Backends) when is_list(Backends) ->
    {gakudan_llm_fallback, #{backends => [Primary | Backends]}}.

with_retry(Backend) ->
    case llm_retry() of
        false -> Backend;
        Opts when is_map(Opts) -> {gakudan_llm_retry, Opts#{backend => Backend}}
    end.

-spec model() -> binary().
model() -> application:get_env(banto, model, ~"claude-sonnet-4-6").

-spec mcp_port() -> pos_integer().
mcp_port() -> application:get_env(banto, mcp_port, 8080).

-spec namespace() -> binary().
namespace() -> application:get_env(banto, namespace, ~"banto").

-spec max_distance() -> number() | undefined.
max_distance() -> application:get_env(banto, max_distance, undefined).

-spec hybrid() -> boolean().
hybrid() -> application:get_env(banto, hybrid, true).

-spec llm_retry() -> map() | false.
llm_retry() -> application:get_env(banto, llm_retry, #{max_attempts => 3}).

-spec llm_fallback() -> [{module(), map()}].
llm_fallback() -> application:get_env(banto, llm_fallback, []).
