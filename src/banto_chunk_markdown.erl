-module(banto_chunk_markdown).
-moduledoc """
Chunk Markdown into heading-bounded sections, each tagged with its heading as
`symbol`. Fence-aware: a `#` line inside a ``` / ~~~ code fence does not start a
section. Content before the first heading is an untagged preamble chunk. A
section longer than `?MAX_LINES` is sub-split by lines, all sharing the heading.
See ADR 0006.
""".
-behaviour(banto_chunk).

-export([chunk/1]).

-define(MAX_LINES, 60).

-spec chunk(binary()) -> [{binary(), map()}].
chunk(Content) ->
    Lines = binary:split(Content, ~"\n", [global]),
    Sections = split_sections(Lines, false, ~"", [], []),
    lists:append([emit(Symbol, RevLines) || {Symbol, RevLines} <- Sections]).

%% Walk lines into {Symbol, ReversedLines} sections in document order.
split_sections([], _InFence, Symbol, Cur, Acc) ->
    lists:reverse(close(Symbol, Cur, Acc));
split_sections([Line | Rest], InFence, Symbol, Cur, Acc) ->
    case is_fence(Line) of
        true ->
            split_sections(Rest, not InFence, Symbol, [Line | Cur], Acc);
        false ->
            case (not InFence) andalso heading(Line) of
                {true, Text} ->
                    split_sections(Rest, InFence, Text, [Line], close(Symbol, Cur, Acc));
                _ ->
                    split_sections(Rest, InFence, Symbol, [Line | Cur], Acc)
            end
    end.

close(_Symbol, [], Acc) -> Acc;
close(Symbol, Cur, Acc) -> [{Symbol, Cur} | Acc].

emit(Symbol, RevLines) ->
    Lines = lists:reverse(RevLines),
    Meta =
        case Symbol of
            ~"" -> #{};
            _ -> #{~"symbol" => Symbol}
        end,
    [{iolist_to_binary(lists:join(~"\n", Group)), Meta} || Group <- groups(Lines, ?MAX_LINES)].

is_fence(Line) ->
    case re:run(Line, "^\\s*(```|~~~)", [{capture, none}]) of
        match -> true;
        nomatch -> false
    end.

heading(Line) ->
    case re:run(Line, "^\\s*#{1,6}\\s+(.*\\S)\\s*$", [{capture, [1], binary}]) of
        {match, [Text]} -> {true, Text};
        nomatch -> false
    end.

groups([], _N) ->
    [];
groups(Lines, N) ->
    {Head, Tail} = take(Lines, N, []),
    [Head | groups(Tail, N)].

take(Rest, 0, Acc) ->
    {lists:reverse(Acc), Rest};
take([], _N, Acc) ->
    {lists:reverse(Acc), []};
take([H | T], N, Acc) ->
    take(T, N - 1, [H | Acc]).
