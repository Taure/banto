-module(banto_embedder).
-moduledoc """
A `bunko_embedder` that embeds text through a [sekisho](https://github.com/Taure/sekisho)
gateway's OpenAI embeddings lane, so embedding traffic gets the same virtual
key, budget, and audit as chat. `bunko_embedder_stub` is the offline default
(see `m:banto_config`); configure this for real embeddings:

```erlang
{banto, [{embedder, {banto_embedder, #{
    base_url => ~"http://sekisho.internal/openai",
    api_key  => ~"sk-sekisho-...",
    model    => ~"text-embedding-3-small"
}}}]}
```

The backend appends `/v1/embeddings`, so point `base_url` at the origin + the
gateway's OpenAI prefix.
""".

-behaviour(bunko_embedder).

-export([embed/2]).
-export([build_body/2, parse_embedding/1]).

-define(DEFAULT_MODEL, ~"text-embedding-3-small").
-define(TIMEOUT, 30_000).

-spec embed(binary(), map()) -> {ok, [float()]} | {error, term()}.
embed(Text, #{base_url := BaseUrl, api_key := ApiKey} = Opts) ->
    ensure_started(),
    Model = maps:get(model, Opts, ?DEFAULT_MODEL),
    Url = binary_to_list(BaseUrl) ++ "/v1/embeddings",
    Headers = [{"x-api-key", binary_to_list(ApiKey)}],
    Request =
        {Url, Headers, "application/json", iolist_to_binary(json:encode(build_body(Model, Text)))},
    case httpc:request(post, Request, [{timeout, ?TIMEOUT}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _Hdrs, RespBody}} -> parse_embedding(RespBody);
        {ok, {{_, Code, _}, _Hdrs, _Body}} -> {error, {http_error, Code}};
        {error, Reason} -> {error, Reason}
    end;
embed(_Text, _Opts) ->
    {error, {bad_config, missing_base_url_or_api_key}}.

-doc "Build the OpenAI embeddings request body (pure).".
-spec build_body(binary(), binary()) -> map().
build_body(Model, Text) ->
    #{model => Model, input => Text}.

-doc "Extract the first embedding vector from an OpenAI embeddings response (pure).".
-spec parse_embedding(binary()) -> {ok, [float()]} | {error, term()}.
parse_embedding(Body) ->
    case json:decode(Body) of
        #{~"data" := [#{~"embedding" := Vec} | _]} when is_list(Vec) ->
            {ok, [float(N) || N <- Vec]};
        _ ->
            {error, no_embedding}
    end.

ensure_started() ->
    _ = inets:start(),
    _ = ssl:start(),
    ok.
