-module(banto_index_stream).
-moduledoc """
Nova `stream` handler for the dashboard's live index view. Registered in
`banto_app`. Subscribes the request process to `m:banto_index_hub`, holds the SSE
connection open, and patches `#jobs` with a fresh render on every progress
update. The process exits (and the hub drops the subscription via its monitor)
when the client disconnects.
""".

-export([handle/3]).

-define(KEEPALIVE_MS, 25000).

-spec handle(tuple(), term(), cowboy_req:req()) -> no_return().
handle({stream, Code, Headers, _Spec}, _Callback, Req0) ->
    Jobs = banto_index_hub:subscribe(),
    Req = cowboy_req:stream_reply(Code, Headers, Req0),
    send(Req, frame(Jobs)),
    loop(Req).

loop(Req) ->
    receive
        {banto_index_progress, Jobs} ->
            send(Req, frame(Jobs)),
            loop(Req)
    after ?KEEPALIVE_MS ->
        send(Req, ~": keepalive\n\n"),
        loop(Req)
    end.

send(Req, Data) ->
    try
        cowboy_req:stream_body(Data, nofin, Req)
    catch
        _:_ -> exit(normal)
    end.

frame(Jobs) ->
    datastar:patch_elements(
        banto_dashboard_page:jobs_html(Jobs), #{selector => ~"#jobs", mode => inner}
    ).
