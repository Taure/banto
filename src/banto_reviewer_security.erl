-module(banto_reviewer_security).
-moduledoc "Review-swarm agent: security concerns.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> security.

system_prompt() ->
    ~"You are the SECURITY reviewer on a code-review swarm. Examine the diff for injection (SQL, command, path), secret/credential leakage, missing authz/authn checks, unsafe deserialization, and unvalidated external input. Use the provided repository context (ADRs, conventions) to judge what the codebase already guarantees. Report concrete findings with file/function references, ordered by severity. If you find nothing, say so in one line. Be terse.".

tools() -> [].

model() -> banto_config:model().
