# Deploying banto

banto ships **one image** (`Dockerfile`) run in **two roles** that share a
PostgreSQL (pgvector) database and a [sekisho](https://github.com/Taure/sekisho)
gateway. `BANTO_ROLE` selects which listener is public on the platform's routed
port (`$PORT`):

| Role | `BANTO_ROLE` | Public surface |
| --- | --- | --- |
| dashboard | `dashboard` | Nova + Datastar memory console |
| mcp | `mcp` | madoguchi MCP server (Streamable HTTP) |

It runs on any container platform; platform-specific wiring (linking a managed
database, mapping its env, setting secrets) lives outside this repo.

## Prerequisites

1. A **pgvector** PostgreSQL (the `vector` extension).
2. A reachable **sekisho** gateway with two virtual keys (one for the Anthropic
   lane, one for the OpenAI embeddings lane). banto routes all LLM and embedding
   traffic through it.

## Run

```bash
docker build -t banto .
docker run -p 8080:8080 -e BANTO_ROLE=dashboard \
  -e BANTO_DB=banto -e BANTO_DB_HOST=... -e BANTO_DB_PORT=5432 \
  -e BANTO_DB_USER=... -e BANTO_DB_PASSWORD=... \
  -e SEKISHO_BASE_URL=https://your-sekisho -e SEKISHO_LLM_KEY=... -e SEKISHO_EMBED_KEY=... \
  banto
```

| Variable | Required | Notes |
| --- | --- | --- |
| `BANTO_ROLE` | yes | `dashboard` or `mcp` |
| `BANTO_DB`, `BANTO_DB_HOST`, `BANTO_DB_PORT`, `BANTO_DB_USER`, `BANTO_DB_PASSWORD` | yes | pgvector Postgres connection |
| `SEKISHO_BASE_URL` | yes | gateway origin |
| `SEKISHO_LLM_KEY` | yes | virtual key for the Anthropic lane |
| `SEKISHO_EMBED_KEY` | yes | virtual key for the embeddings lane |
| `BANTO_NAMESPACE` | no | default `banto` |
| `BANTO_MODEL` | no | default `claude-sonnet-4-6` |
| `EMBED_MODEL` | no | default `text-embedding-3-small` |
| `EMBEDDING_DIM` | no | default `1536` (must match the embed model) |

The schema is created on boot (`banto:ensure_schema/0`, idempotent).

## Notes

- One public port. The platform routes `$PORT`; `entrypoint.sh` maps `BANTO_ROLE`
  to the public listener on `$PORT` (the other binds an unreachable internal
  port).
- The cold dependency-graph compile is RAM-heavy; if a source build OOMs, give
  the builder more memory (or build in CI and pull the image).
- Build the image locally first (`docker build .`) to catch any missing `COPY`.
