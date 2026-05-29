#!/bin/sh
set -e

# Clever Cloud routes external traffic to the single port $PORT (default 8080).
# BANTO_ROLE picks which listener binds it; the other binds an unreachable
# internal port. Both Clever apps run this same image, sharing the DB + sekisho.
: "${PORT:=8080}"
: "${BANTO_ROLE:=dashboard}"
: "${EMBEDDING_DIM:=1536}"
: "${BANTO_NAMESPACE:=banto}"
: "${BANTO_MODEL:=claude-sonnet-4-6}"
: "${EMBED_MODEL:=text-embedding-3-small}"

if [ "$BANTO_ROLE" = "mcp" ]; then
    MCP_PORT="$PORT"
    NOVA_PORT=8079
else
    NOVA_PORT="$PORT"
    MCP_PORT=8079
fi

export PORT BANTO_ROLE EMBEDDING_DIM BANTO_NAMESPACE BANTO_MODEL EMBED_MODEL NOVA_PORT MCP_PORT

exec /app/bin/banto foreground
