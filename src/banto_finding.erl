-module(banto_finding).
-moduledoc """
Schema-constrained findings for the review swarm. Each reviewer requests
structured output against `schema/0`; gakudan validates the model's reply with
`gakudan_validator_json` before it reaches the blackboard, so findings parse
robustly instead of by scraping prose.

`render/1` turns a reviewer's collected content back into markdown: it parses the
structured JSON when present, and falls back to the raw text otherwise (a model
or stub that did not produce structured output still renders).
""".

-export([request_options/0, schema/0, render/1]).

-doc "The `request_options/0` reviewers return to request validated findings.".
-spec request_options() -> map().
request_options() ->
    #{
        response_format => schema(),
        validator => {gakudan_validator_json, schema()}
    }.

-doc "JSON schema constraining a reviewer's findings.".
-spec schema() -> map().
schema() ->
    #{
        ~"type" => ~"object",
        ~"required" => [~"findings"],
        ~"properties" => #{
            ~"findings" => #{
                ~"type" => ~"array",
                ~"items" => #{
                    ~"type" => ~"object",
                    ~"required" => [~"severity", ~"title"],
                    ~"properties" => #{
                        ~"severity" => #{
                            ~"type" => ~"string",
                            ~"enum" => [~"info", ~"low", ~"medium", ~"high", ~"critical"]
                        },
                        ~"title" => #{~"type" => ~"string"},
                        ~"detail" => #{~"type" => ~"string"},
                        ~"location" => #{~"type" => ~"string"}
                    }
                }
            }
        }
    }.

-doc "Render a reviewer's content (structured JSON or plain text) as markdown.".
-spec render(binary()) -> binary().
render(Content) ->
    case parse(Content) of
        {ok, #{~"findings" := Findings}} when is_list(Findings) ->
            render_findings(Findings);
        _ ->
            Content
    end.

parse(Content) ->
    try json:decode(Content) of
        Value -> {ok, Value}
    catch
        _:_ -> error
    end.

render_findings([]) ->
    ~"No issues found.";
render_findings(Findings) ->
    iolist_to_binary(lists:join(~"\n", [render_one(F) || F <- Findings])).

render_one(F) ->
    Severity = maps:get(~"severity", F, ~"info"),
    Title = maps:get(~"title", F, ~"(untitled)"),
    Location = maps:get(~"location", F, ~""),
    Detail = maps:get(~"detail", F, ~""),
    [
        ~"- **(",
        Severity,
        ~")** ",
        Title,
        loc(Location),
        det(Detail)
    ].

loc(~"") -> ~"";
loc(Location) -> [~" [", Location, ~"]"].

det(~"") -> ~"";
det(Detail) -> [~"\n  ", Detail].
