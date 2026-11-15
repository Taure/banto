-module(banto_test_stream_handler).
-moduledoc false.
-behaviour(cowboy_handler).

-export([init/2]).

-spec init(cowboy_req:req(), term()) -> no_return().
init(Req, _State) ->
    Stream = banto_dashboard_page:index_stream(Req),
    banto_stream:handle(Stream, undefined, Req).
