-module(banto_flow_stream).
-moduledoc """
Nova `stream` handler for the dashboard's live ask/recall flow. Reads the
`question` and `mode` (`ask` | `recall`) signals from the held GET's `datastar`
query param, runs the instrumented `banto:ask/3` or `banto:recall/3` in a
monitored worker, patches `#flow` live as each step arrives, patches `#answer`
with the result, then closes (`fin`). The flow is private to this request - no
hub. A client disconnect kills the worker, so an in-flight LLM call is not leaked.
See ADR 0007.
""".

-export([handle/3]).
-hank([{unnecessary_function_arguments, [{handle, 3, 2}]}]).

-define(KEEPALIVE_MS, 25000).

-spec handle(tuple(), term(), cowboy_req:req()) -> no_return().
handle({stream, Code, Headers, _Spec}, _Callback, Req0) ->
    {Mode, Question} = banto_dashboard_page:flow_params(Req0),
    Req = cowboy_req:stream_reply(Code, Headers, Req0),
    run(Req, Mode, Question),
    _ = send(Req, ~"", fin),
    exit(normal).

run(Req, _Mode, ~"") ->
    _ = send(Req, flow_frame([]));
run(Req, Mode, Question) ->
    Self = self(),
    Flow = fun(Step) -> Self ! {flow_step, Step} end,
    {Pid, Ref} = spawn_monitor(fun() -> Self ! {flow_result, Mode, op(Mode, Question, Flow)} end),
    collect(Req, Pid, Ref, []).

op(recall, Question, Flow) -> banto:recall(Question, #{limit => 8}, Flow);
op(_Ask, Question, Flow) -> banto:ask(Question, #{limit => 8}, Flow).

collect(Req, Pid, Ref, Steps) ->
    receive
        {flow_step, Step} ->
            Steps1 = Steps ++ [Step],
            guard(Req, Pid, flow_frame(Steps1), fun() -> collect(Req, Pid, Ref, Steps1) end);
        {flow_result, Mode, Result} ->
            guard(Req, Pid, answer_frame(Mode, Result), fun() -> collect(Req, Pid, Ref, Steps) end);
        {'DOWN', Ref, process, Pid, _Reason} ->
            ok
    after ?KEEPALIVE_MS ->
        guard(Req, Pid, ~": keepalive\n\n", fun() -> collect(Req, Pid, Ref, Steps) end)
    end.

%% Send a frame; on a dead client, kill the worker (do not leak the LLM call).
guard(Req, Pid, Data, Continue) ->
    case send(Req, Data) of
        ok -> Continue();
        closed -> exit(Pid, kill)
    end.

send(Req, Data) ->
    send(Req, Data, nofin).

send(Req, Data, Fin) ->
    try
        cowboy_req:stream_body(Data, Fin, Req),
        ok
    catch
        _:_ -> closed
    end.

flow_frame(Steps) ->
    datastar:patch_elements(
        banto_dashboard_page:flow_html(Steps), #{selector => ~"#flow", mode => inner}
    ).

answer_frame(recall, {ok, Hits}) ->
    answer_patch(banto_dashboard_page:answer_html({hits, Hits}));
answer_frame(_Ask, {ok, Answer}) ->
    answer_patch(banto_dashboard_page:answer_html({ok, Answer}));
answer_frame(_Mode, {error, Reason}) ->
    answer_patch(banto_dashboard_page:answer_html({error, Reason})).

answer_patch(Html) ->
    datastar:patch_elements(Html, #{selector => ~"#answer", mode => inner}).
