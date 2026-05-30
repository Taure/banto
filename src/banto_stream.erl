-module(banto_stream).
-moduledoc """
Dispatches Nova `stream` returns to the right held-SSE handler by request path.
`nova_handlers:register_handler(stream, _)` is global (one fun per return type),
so this routes `/dashboard/flow/stream` to `m:banto_flow_stream` and the indexing
panel's `/dashboard/index/stream` to `m:banto_index_stream`.
""".

-export([handle/3]).

-spec handle(tuple(), term(), cowboy_req:req()) -> no_return().
handle({stream, _Code, _Headers, _Spec} = Stream, Callback, Req) ->
    case cowboy_req:path(Req) of
        ~"/dashboard/flow/stream" -> banto_flow_stream:handle(Stream, Callback, Req);
        _ -> banto_index_stream:handle(Stream, Callback, Req)
    end.
