-module(banto_knowledge).
-moduledoc """
Grounded question answering over the indexed memory. Recalls the most relevant
chunks for a question, formats them (with source paths) as context, and asks the
configured `gakudan_llm` backend to answer using only that context. A single
completion - the multi-agent orchestration (gakudan fanout) is reserved for the
review swarm, not needed for a grounded lookup.
""".

-export([ask/3, ask/4, recall/4, recall_opts/2, build_request/3]).
-export_type([step/0]).

-type step() :: #{
    step := recall | prompt | llm | answer | error,
    phase := start | done,
    question_len => non_neg_integer(),
    repo_filter => binary() | undefined,
    count => non_neg_integer(),
    sources => [map()],
    model => binary(),
    prompt_len => non_neg_integer(),
    backend => binary(),
    answer_len => non_neg_integer(),
    answer => binary(),
    step_failed => atom(),
    reason => binary()
}.

-doc "Recall context for `Question` and synthesise a grounded answer.".
-spec ask(bunko:context(), binary(), map()) -> {ok, binary()} | {error, term()}.
ask(Ctx, Question, Opts) ->
    ask(Ctx, Question, Opts, fun(_) -> ok end).

-doc "As `ask/3`, invoking `Flow` with a `t:step/0` map at each stage.".
-spec ask(bunko:context(), binary(), map(), fun((step()) -> ok)) ->
    {ok, binary()} | {error, term()}.
ask(Ctx, Question, Opts, Flow) ->
    case recall(Ctx, Question, Opts, Flow) of
        {ok, Hits} ->
            Model = banto_config:model(),
            {Mod, LlmOpts} = banto_config:resilient_llm(),
            Req = build_request(Model, Question, Hits),
            Flow(#{
                step => prompt,
                phase => done,
                model => Model,
                prompt_len => prompt_len(Req),
                count => length(Hits)
            }),
            Flow(#{step => llm, phase => start, backend => ref_name(Mod), model => Model}),
            case Mod:complete(Req, LlmOpts) of
                {ok, Resp} ->
                    Answer = answer_text(Resp),
                    Flow(#{step => llm, phase => done, answer_len => byte_size(Answer)}),
                    Flow(#{step => answer, phase => done, answer => Answer}),
                    {ok, Answer};
                {error, R} = Err ->
                    Flow(#{step => error, phase => done, step_failed => llm, reason => err(R)}),
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

-doc "Recall the top-k hits for `Query`, invoking `Flow` with `recall` steps.".
-spec recall(bunko:context(), binary(), map(), fun((step()) -> ok)) ->
    {ok, [bunko_store:hit()]} | {error, term()}.
recall(Ctx, Query, Opts, Flow) ->
    Repo = maps:get(repo, Opts, undefined),
    Flow(#{step => recall, phase => start, question_len => byte_size(Query), repo_filter => Repo}),
    case bunko:recall(Ctx, Query, recall_opts(Opts, Repo)) of
        {ok, Hits} ->
            Flow(#{step => recall, phase => done, count => length(Hits), sources => sources(Hits)}),
            {ok, Hits};
        {error, R} = Err ->
            Flow(#{step => error, phase => done, step_failed => recall, reason => err(R)}),
            Err
    end.

-doc """
Translate banto recall `Opts` plus a `Repo` filter into bunko recall options:
push the repo filter and distance threshold into bunko so the DB does the work,
and enable hybrid (keyword + vector) recall when configured - exact identifiers
and error codes matter for code retrieval.
""".
-spec recall_opts(map(), binary() | undefined) -> map().
recall_opts(Opts, Repo) ->
    Base = maps:without([repo], Opts),
    WithFilter =
        case Repo of
            undefined -> Base;
            _ -> Base#{filter => #{~"repo" => Repo}}
        end,
    WithThreshold =
        case banto_config:max_distance() of
            undefined -> WithFilter;
            Max -> WithFilter#{max_distance => Max}
        end,
    case banto_config:hybrid() of
        true -> WithThreshold#{hybrid => true};
        false -> WithThreshold
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

sources(Hits) ->
    [
        #{
            repo => meta(~"repo", H),
            path => meta(~"path", H),
            kind => meta(~"kind", H),
            distance => maps:get(distance, H, 0.0)
        }
     || H <- Hits
    ].

meta(Key, Hit) ->
    maps:get(Key, maps:get(metadata, Hit, #{}), ~"?").

prompt_len(#{messages := [#{content := Content} | _]}) -> byte_size(Content);
prompt_len(_) -> 0.

ref_name(Mod) when is_atom(Mod) -> atom_to_binary(Mod).

err(Reason) -> iolist_to_binary(io_lib:format("~p", [Reason])).
