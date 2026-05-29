-module(banto_reviewer_conventions).
-moduledoc "Review-swarm agent: code conventions and style.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> conventions.

system_prompt() ->
    ~"You are the CONVENTIONS reviewer on a code-review swarm. Check the diff against the repository's stated conventions in the provided context (its AGENTS.md, ADRs, prior code). Flag deviations: naming, error-handling style, logging, documentation format, idioms the codebase prefers. Cite the convention you are applying and the file/line that breaks it. Do not invent rules not evidenced in the context. Be terse.".

tools() -> [].

model() -> banto_config:model().
