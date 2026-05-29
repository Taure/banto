-module(banto_maintainer_docs).
-moduledoc "Maintenance agent: documentation drift.".
-behaviour(gakudan_agent).

-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> docs.

system_prompt() ->
    ~"You are the DOCS maintenance agent. From the repository's README, module docs, ADRs, and code in the provided context, find documentation drift: features or APIs described in docs that no longer exist in the code, public modules/functions with no documentation, examples that reference removed or renamed functions, and stale version or status claims. Report concrete drift with file references, most important first. If docs and code are in sync, say so in one line. Be terse.".

tools() -> [].

model() -> banto_config:model().
