# Recording the README demo

Goal: a short (~25-40s) `assets/demo.gif` for the top of the README and a Show HN.
Show the two things that land: a cited cross-repo answer, then the review swarm.

## What to capture
1. `rebar3 shell` booting banto (one or two lines, then the prompt).
2. `banto:index/2` indexing a repo (the progress line).
3. `banto:ask/2` returning an answer with `[repo/path]` citations.
4. `banto_review:review/2` + `format/1` printing a couple of structured findings.

Keep models real for the recording (route through sekisho) so the answer reads
well - the stub LLM is for the no-key first run, not the demo.

## Suggested terminal session

```erlang
ok = banto:ensure_schema().
{ok, _} = banto:index("../kura", #{name => ~"kura"}).
{ok, A} = banto:ask(~"how does kura configure its connection pool?", #{repo => ~"kura"}).
io:format("~ts~n", [A]).
%% then a small diff for the swarm:
{ok, R} = banto_review:review(Diff, #{repo => ~"kura"}).
io:format("~ts~n", [banto_review:format(R)]).
```

## Recording

asciinema -> animated gif (crisp, small, no video host):

```bash
# record
asciinema rec banto.cast --idle-time-limit 1.5
# ... run the session above, then exit the shell ...
# convert (agg ships with asciinema, or use the older asciicast2gif)
agg banto.cast assets/demo.gif
```

Trim to ~30s, keep the terminal ~100 cols. Then uncomment the
`![...](assets/demo.gif)` line near the top of ../README.md and commit the gif.

Tips: clear scrollback first, use a legible font/size, and pause ~1s on the
answer and on the findings so they're readable in the loop.
</content>
