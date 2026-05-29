-module(banto_test_llm).
-moduledoc false.
-behaviour(gakudan_llm).

-export([complete/2]).

%% Echoes the last user message back as the answer, so a test can assert that
%% the recalled context and question actually reached the model.
complete(#{messages := Msgs}, _Opts) ->
    Text = last_user(Msgs),
    {ok, #{stop_reason => end_turn, content => [#{type => text, text => Text}]}}.

last_user(Msgs) ->
    case [C || #{role := user, content := C} <- Msgs] of
        [] -> ~"";
        Contents -> lists:last(Contents)
    end.
