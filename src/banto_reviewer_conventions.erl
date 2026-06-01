-module(banto_reviewer_conventions).
-moduledoc "Review-swarm agent: code conventions and style.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0, request_options/0]).

id() -> conventions.

system_prompt() ->
    ~"You are the CONVENTIONS reviewer on a code-review swarm. Check the diff against the repository's stated conventions in the provided context (its AGENTS.md, ADRs, prior code). Flag deviations: naming, error-handling style, logging, documentation format, idioms the codebase prefers. Do not invent rules not evidenced in the context. Return your findings as the structured object: one entry per deviation with severity, a short title, the file/line in `location`, and the convention being applied in `detail`. An empty `findings` list means no issues.".

tools() -> [].

model() -> banto_config:model().

request_options() -> banto_finding:request_options().
