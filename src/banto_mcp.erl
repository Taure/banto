-module(banto_mcp).
-moduledoc """
The MCP server surface: exposes banto's capabilities as MCP tools over
Streamable HTTP (via madoguchi), so a Claude Code session in any repo can
`recall`, `ask`, or `index`. Started at app boot on `{banto, mcp_port}`.
""".

-export([start/0, server/0]).

-doc "Start the madoguchi MCP HTTP server on the configured port at `/mcp`.".
-spec start() -> {ok, pid()} | {error, term()}.
start() ->
    madoguchi:start_http(server(), #{port => banto_config:mcp_port(), path => "/mcp"}).

-doc "The MCP server spec (name, version, tools).".
-spec server() -> map().
server() ->
    #{
        name => ~"banto",
        version => ~"0.1.0",
        tools => [banto_mcp_recall, banto_mcp_ask, banto_mcp_index]
    }.
