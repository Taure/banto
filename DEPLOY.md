# Deploying banto to Clever Cloud

banto ships **one image** (`Dockerfile`) run as **two Clever apps** that share a
PostgreSQL add-on and a sekisho gateway. `BANTO_ROLE` selects which listener is
public on Clever's routed port (`$PORT`):

| App | `BANTO_ROLE` | Public surface |
| --- | --- | --- |
| banto-dashboard | `dashboard` | Nova + Datastar memory console |
| banto-mcp | `mcp` | madoguchi MCP server (Streamable HTTP) |

## Prerequisites

1. **A pgvector Postgres.** Verify Clever's PostgreSQL add-on provides the
   `vector` extension; if not, use an external pgvector Postgres and set the
   `POSTGRESQL_ADDON_*` vars by hand.
2. **A deployed sekisho** with an upstream + two virtual keys (one for the
   Anthropic lane, one for the OpenAI embeddings lane). banto routes all LLM and
   embedding traffic through it.

## Set up (per app)

1. Create a Docker app on Clever from this repo (it builds the `Dockerfile`).
2. Link the **PostgreSQL add-on** to both apps (injects `POSTGRESQL_ADDON_HOST`,
   `_PORT`, `_DB`, `_USER`, `_PASSWORD`).
3. Set environment variables:

   | Variable | Required | Notes |
   | --- | --- | --- |
   | `BANTO_ROLE` | yes | `dashboard` or `mcp` |
   | `SEKISHO_BASE_URL` | yes | gateway origin, e.g. `https://sekisho.example.com` |
   | `SEKISHO_LLM_KEY` | yes | virtual key for the Anthropic lane |
   | `SEKISHO_EMBED_KEY` | yes | virtual key for the embeddings lane |
   | `BANTO_NAMESPACE` | no | default `banto` |
   | `BANTO_MODEL` | no | default `claude-sonnet-4-6` |
   | `EMBED_MODEL` | no | default `text-embedding-3-small` |
   | `EMBEDDING_DIM` | no | default `1536` (must match the embed model) |

The schema is created on boot (`banto:ensure_schema/0`, idempotent), so the
first app to start provisions the `bunko_memories` table.

## Notes

- **One public port.** Clever routes only `$PORT`; `entrypoint.sh` maps
  `BANTO_ROLE` -> the public listener on `$PORT` (the other binds an unreachable
  internal port).
- **Build memory.** The cold dependency-graph compile is RAM-heavy; if the Clever
  build OOMs, bump the build instance one tier (or build in CI and pull the
  image).
- **No auto-deploy.** Clever redeploys on a manual trigger or a registry webhook,
  so prod can go stale - verify after each deploy.
- Build the image locally first (`docker build .` then run with the env vars) to
  catch any missing `COPY`.
