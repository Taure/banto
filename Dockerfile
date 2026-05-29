# Build the prod release. Clever Cloud builds this Dockerfile from source.
FROM erlang:29 AS build
WORKDIR /src
# Deps first for layer caching.
COPY rebar.config rebar.lock ./
RUN rebar3 as prod compile
# Then the app sources. priv/ MUST be copied - the dashboard's datastar.js and
# app.css are served from there.
COPY src ./src
COPY config ./config
COPY priv ./priv
RUN rebar3 as prod release

# Self-contained runtime (the release bundles ERTS). Match the build image's
# Debian release so the bundled ERTS finds a compatible glibc - erlang:29 is
# trixie-based, so the runtime must be trixie too.
FROM debian:trixie-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl libncurses6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/_build/prod/rel/banto ./
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
# Default role; override per Clever app (BANTO_ROLE=mcp for the MCP app).
ENV BANTO_ROLE=dashboard
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
