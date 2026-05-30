-module(banto_flow_stream).
-moduledoc """
Nova `stream` handler for the dashboard's live ask/recall flow, modelled on
`gakudan_liveboard_sse`: it `stream_reply`s, subscribes to `m:banto_flow_hub`,
pushes `datastar:patch_elements` frames for `#flow` and `#answer` as steps
arrive, and **holds the connection** (never returns, so Nova's buffered reply
never fires). Opened from the dashboard with `data-init` on page load. The flow
itself is produced wherever `banto:ask/2`/`recall/2` runs (console, MCP), not
here. See ADR 0007.
""".

-export([handle/3]).
-hank([{unnecessary_function_arguments, [{handle, 3, 2}]}]).

-spec handle(tuple(), term(), cowboy_req:req()) -> no_return().
handle({stream, Code, Headers, _Spec}, _Callback, Req0) ->
    Req = cowboy_req:stream_reply(Code, Headers, Req0),
    {Steps, Answer} = banto_flow_hub:subscribe(),
    send(Req, flow_frame(Steps)),
    send(Req, answer_frame(Answer)),
    loop(Req).

loop(Req) ->
    receive
        {banto_flow_update, Steps, Answer} ->
            send(Req, flow_frame(Steps)),
            send(Req, answer_frame(Answer)),
            loop(Req)
    end.

send(Req, Frame) ->
    ok = cowboy_req:stream_body(Frame, nofin, Req).

flow_frame(Steps) ->
    datastar:patch_elements(
        banto_dashboard_page:flow_html(Steps), #{selector => ~"#flow", mode => inner}
    ).

answer_frame(undefined) ->
    datastar:patch_elements(
        ~"<p class=\"empty\">the answer will appear here.</p>",
        #{selector => ~"#answer", mode => inner}
    );
answer_frame({ok, Answer}) ->
    datastar:patch_elements(
        banto_dashboard_page:answer_html({ok, Answer}), #{selector => ~"#answer", mode => inner}
    );
answer_frame({error, Reason}) ->
    datastar:patch_elements(
        banto_dashboard_page:answer_html({error, Reason}), #{selector => ~"#answer", mode => inner}
    ).
