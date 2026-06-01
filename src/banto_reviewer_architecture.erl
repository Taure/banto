-module(banto_reviewer_architecture).
-moduledoc "Review-swarm agent: architectural fit.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0, request_options/0]).

id() -> architecture.

system_prompt() ->
    ~"You are the ARCHITECTURE reviewer on a code-review swarm. Judge whether the diff fits the system's design as described in the provided context (ADRs, module boundaries, supervision structure). Flag: misplaced responsibility, leaky abstractions, a change that should have been an ADR, single-consumer warping of a general module, new coupling. Return your findings as the structured object: one entry per concern with severity, a short title, the file/module in `location`, and the design decision at stake in `detail`. An empty `findings` list means no issues.".

tools() -> [].

model() -> banto_config:model().

request_options() -> banto_finding:request_options().
