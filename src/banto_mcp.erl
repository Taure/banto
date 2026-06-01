-module(banto_mcp).
-moduledoc """
The MCP server surface: exposes banto's capabilities as MCP tools (`recall`,
`ask`, `index_repo`) and the indexed repositories as MCP resources, so a Claude
Code session in any repo can use them. Two transports share one server spec: the
Streamable HTTP server (started at app boot on `{banto, mcp_port}`) and a stdio
transport (`start_stdio/0`) for running banto as a local MCP server launched by a
desktop client.
""".

-export([start/0, start_stdio/0, server/0]).

-doc "Start the madoguchi MCP HTTP server on the configured port at `/mcp`.".
-spec start() -> {ok, pid()} | {error, term()}.
start() ->
    madoguchi:start_http(server(), #{port => banto_config:mcp_port(), path => "/mcp"}).

-doc """
Serve the MCP protocol over stdin/stdout until EOF. The entry point for running
banto as a local MCP server a desktop client launches; all protocol traffic is on
stdout, so logs must go to stderr.
""".
-spec start_stdio() -> ok.
start_stdio() ->
    madoguchi_stdio:start(server()).

-doc "The MCP server spec (name, version, tools, resources).".
-spec server() -> map().
server() ->
    #{
        name => ~"banto",
        version => ~"0.1.0",
        tools => [banto_mcp_recall, banto_mcp_ask, banto_mcp_index],
        resources => [banto_mcp_resources]
    }.
