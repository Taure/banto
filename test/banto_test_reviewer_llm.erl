-module(banto_test_reviewer_llm).
-moduledoc false.
-behaviour(gakudan_llm).

%% Deterministic reviewer stub for offline swarm tests. Keys off the agent's
%% system prompt (not a shared script queue), so it is stable under fanout
%% concurrency, and reacts to planted markers in the diff so the saiten gate can
%% assert that the right reviewer caught the right issue.

-export([complete/2]).

complete(#{system := Sys, messages := Msgs}, _Opts) ->
    Diff = last_user(Msgs),
    Text = respond(persona(Sys), Diff),
    {ok, #{stop_reason => end_turn, content => [#{type => text, text => Text}]}}.

persona(Sys) ->
    case
        {
            has(Sys, ~"SECURITY"),
            has(Sys, ~"CONVENTIONS"),
            has(Sys, ~"TESTS"),
            has(Sys, ~"ARCHITECTURE"),
            has(Sys, ~"DOCS")
        }
    of
        {true, _, _, _, _} -> security;
        {_, true, _, _, _} -> conventions;
        {_, _, true, _, _} -> tests;
        {_, _, _, true, _} -> architecture;
        {_, _, _, _, true} -> docs;
        _ -> unknown
    end.

respond(security, Diff) ->
    case has(Diff, ~"os:cmd") of
        true -> ~"FINDING (high): command injection - os:cmd/1 on external input.";
        false -> ~"No security issues found."
    end;
respond(conventions, Diff) ->
    case has(Diff, ~"<<\"") of
        true -> ~"FINDING: use the ~\"\" sigil, not <<\"\">> binary string literals.";
        false -> ~"Conventions OK."
    end;
respond(tests, Diff) ->
    case has(Diff, ~"test") of
        true -> ~"Tests present.";
        false -> ~"FINDING: no test added for this change."
    end;
respond(architecture, _Diff) ->
    ~"No architectural concerns.";
respond(docs, _Ctx) ->
    ~"FINDING: README references a removed function; status section is stale.";
respond(unknown, _Diff) ->
    ~"".

has(Bin, Needle) ->
    binary:match(Bin, Needle) =/= nomatch.

last_user(Msgs) ->
    case [C || #{role := user, content := C} <- Msgs] of
        [] -> ~"";
        Contents -> lists:last(Contents)
    end.
