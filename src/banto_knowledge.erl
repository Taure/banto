-module(banto_knowledge).
-moduledoc """
Grounded question answering over the indexed memory. Recalls the most relevant
chunks for a question, formats them (with source paths) as context, and asks the
configured `gakudan_llm` backend to answer using only that context. A single
completion - the multi-agent orchestration (gakudan fanout) is reserved for the
review swarm, not needed for a grounded lookup.
""".

-export([ask/3, build_request/3]).

-doc "Recall context for `Question` and synthesise a grounded answer.".
-spec ask(bunko:context(), binary(), map()) -> {ok, binary()} | {error, term()}.
ask(Ctx, Question, Opts) ->
    case bunko:recall(Ctx, Question, Opts) of
        {ok, Hits0} ->
            Hits = filter_repo(Hits0, maps:get(repo, Opts, undefined)),
            {Mod, LlmOpts} = banto_config:llm(),
            Req = build_request(banto_config:model(), Question, Hits),
            case Mod:complete(Req, LlmOpts) of
                {ok, Resp} -> {ok, answer_text(Resp)};
                {error, _} = Err -> Err
            end;
        {error, _} = Err ->
            Err
    end.

-doc "Build the `gakudan_llm` request: system rules + recalled context + question.".
-spec build_request(binary(), binary(), [bunko_store:hit()]) -> map().
build_request(Model, Question, Hits) ->
    System =
        ~"You are a precise engineering assistant for the user's code repositories. Answer the question using ONLY the provided context. Cite the source paths you used. If the context is insufficient to answer, say so plainly.",
    Prompt = iolist_to_binary([
        ~"Context from the repositories:\n\n",
        format_context(Hits),
        ~"\n\nQuestion: ",
        Question
    ]),
    #{
        model => Model,
        system => System,
        tools => [],
        messages => [#{role => user, content => Prompt}]
    }.

format_context([]) ->
    ~"(no relevant context found)";
format_context(Hits) ->
    lists:join(~"\n\n---\n\n", [format_hit(H) || H <- Hits]).

format_hit(#{content := Content} = Hit) ->
    Meta = maps:get(metadata, Hit, #{}),
    Path = maps:get(~"path", Meta, ~"unknown"),
    Repo = maps:get(~"repo", Meta, ~"unknown"),
    iolist_to_binary([~"[", Repo, ~"/", Path, ~"]\n", Content]).

answer_text(#{content := Blocks}) ->
    iolist_to_binary([T || #{type := text, text := T} <- Blocks]);
answer_text(_) ->
    ~"".

filter_repo(Hits, undefined) ->
    Hits;
filter_repo(Hits, Repo) ->
    [H || H <- Hits, maps:get(~"repo", maps:get(metadata, H, #{}), undefined) =:= Repo].
