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
""".

-export([repo/0, store/0, embedder/0, llm/0, model/0, mcp_port/0, namespace/0]).

-spec repo() -> module().
repo() -> application:get_env(banto, repo, banto_repo).

-spec store() -> bunko_store:ref().
store() -> {bunko_store_pgvector, #{repo => repo()}}.

-spec embedder() -> bunko_embedder:ref().
embedder() -> application:get_env(banto, embedder, bunko_embedder_stub).

-spec llm() -> {module(), map()}.
llm() -> application:get_env(banto, llm, {gakudan_llm_stub, #{}}).

-spec model() -> binary().
model() -> application:get_env(banto, model, ~"claude-sonnet-4-6").

-spec mcp_port() -> pos_integer().
mcp_port() -> application:get_env(banto, mcp_port, 8080).

-spec namespace() -> binary().
namespace() -> application:get_env(banto, namespace, ~"banto").
