-module(banto_index_stream_tests).
-include_lib("eunit/include/eunit.hrl").

-define(LISTENER, banto_index_stream_tests).
-define(PATH, "/dashboard/index/stream").
-define(NO_EVENT, #{type => ~"message", data => [], other => []}).

line_breaks_test_() ->
    {setup, fun start/0, fun stop/1, fun(Port) ->
        {"a repo name with CR, CRLF and LF is data of one event and keeps its line breaks", fun() ->
            ok = banto_index_hub:report(#{
                repo => ~"a\rb\r\nc\nd", phase => start, done => 0, total => 3, chunks => 0
            }),
            ?assertEqual(1, map_size(banto_index_hub:snapshot())),
            [#{type := Type, data := Data, other := Other}] = events(stream(Port)),
            ?assertEqual({~"datastar-patch-elements", []}, {Type, Other}),
            ?assertEqual(
                [~"elements", ~"mode", ~"selector"],
                lists:usort([hd(binary:split(Line, ~" ")) || Line <- Data])
            ),
            ?assertEqual([~"#jobs"], values(~"selector", Data)),
            ?assertEqual([~"inner"], values(~"mode", Data)),
            Elements = <<<<Line/binary, $\n>> || Line <- values(~"elements", Data)>>,
            ?assertMatch(
                {_, _}, binary:match(Elements, ~"<span class=\"repo\">a\nb\nc\nd</span>")
            )
        end}
    end}.

start() ->
    {ok, _} = application:ensure_all_started(cowboy),
    {ok, Hub} = banto_index_hub:start_link(),
    true = unlink(Hub),
    Dispatch = cowboy_router:compile([{'_', [{?PATH, banto_test_stream_handler, []}]}]),
    {ok, _} = cowboy:start_clear(?LISTENER, [{port, 0}], #{env => #{dispatch => Dispatch}}),
    ranch:get_port(?LISTENER).

stop(_Port) ->
    ok = cowboy:stop_listener(?LISTENER),
    ok = gen_server:stop(banto_index_hub).

%% Over HTTP/1.0 the body is not chunked: what is read after the head is the
%% event stream as sent.
stream(Port) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}]),
    ok = gen_tcp:send(Socket, [~"GET ", ?PATH, ~" HTTP/1.0\r\n\r\n"]),
    Bytes = received(Socket, <<>>, 5000),
    ok = gen_tcp:close(Socket),
    [_Head, Body] = binary:split(Bytes, ~"\r\n\r\n"),
    Body.

%% Waits for the first bytes, then for as long as more keep arriving.
-spec received(gen_tcp:socket(), binary(), timeout()) -> binary().
received(Socket, Read, Wait) ->
    case gen_tcp:recv(Socket, 0, Wait) of
        {ok, Bytes} when is_binary(Bytes) -> received(Socket, <<Read/binary, Bytes/binary>>, 300);
        {error, timeout} -> Read
    end.

%% Reads a stream the way an SSE client does: a line ends at CRLF, CR or LF,
%% and an empty line ends an event. A field that is neither `event` nor `data`
%% is kept under `other`.
events(Stream) ->
    events(binary:split(Stream, [~"\r\n", ~"\r", ~"\n"], [global]), ?NO_EVENT, []).

events([], _Unfinished, Events) ->
    lists:reverse(Events);
events([~"" | Lines], Event, Events) when Event =:= ?NO_EVENT ->
    events(Lines, ?NO_EVENT, Events);
events([~"" | Lines], Event = #{data := Data, other := Other}, Events) ->
    Read = Event#{data := lists:reverse(Data), other := lists:reverse(Other)},
    events(Lines, ?NO_EVENT, [Read | Events]);
events([<<$:, _Comment/binary>> | Lines], Event, Events) ->
    events(Lines, Event, Events);
events([Line | Lines], Event = #{data := Data, other := Other}, Events) ->
    Next =
        case binary:split(Line, [~": ", ~":"]) of
            [~"event", Type] -> Event#{type := Type};
            [~"data", Value] -> Event#{data := [Value | Data]};
            [Name | _Value] -> Event#{other := [Name | Other]}
        end,
    events(Lines, Next, Events).

%% What follows `Word` on the data lines of a Datastar event that start with it.
-spec values(binary(), [binary()]) -> [binary()].
values(Word, Data) ->
    Size = byte_size(Word),
    [Value || <<Start:Size/binary, $\s, Value/binary>> <- Data, Start =:= Word].
