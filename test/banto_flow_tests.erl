-module(banto_flow_tests).
-include_lib("eunit/include/eunit.hrl").

%% --- banto_dashboard_page:flow_html (ADR 0007) ---

flow_html_empty_test() ->
    ?assertNotEqual(
        nomatch,
        binary:match(iolist_to_binary(banto_dashboard_page:flow_html([])), ~"flow will appear")
    ).

flow_html_steps_test() ->
    Steps = [
        #{step => recall, phase => start, question_len => 12, repo_filter => undefined},
        #{
            step => recall,
            phase => done,
            count => 2,
            sources => [
                #{repo => ~"kura", path => ~"src/kura.erl", kind => ~"code", distance => 0.2}
            ]
        },
        #{
            step => prompt,
            phase => done,
            model => ~"claude-sonnet-4-6",
            prompt_len => 800,
            count => 2
        },
        #{
            step => llm,
            phase => start,
            backend => ~"gakudan_llm_anthropic",
            model => ~"claude-sonnet-4-6"
        },
        #{step => llm, phase => done, answer_len => 300},
        #{step => answer, phase => done}
    ],
    H = iolist_to_binary(banto_dashboard_page:flow_html(Steps)),
    ?assertNotEqual(nomatch, binary:match(H, ~"<ol")),
    ?assertNotEqual(nomatch, binary:match(H, ~"kura/src/kura.erl")),
    ?assertNotEqual(nomatch, binary:match(H, ~"synthesise")),
    ?assertNotEqual(nomatch, binary:match(H, ~"claude-sonnet-4-6")).

flow_html_error_step_test() ->
    H = iolist_to_binary(
        banto_dashboard_page:flow_html([
            #{step => error, phase => done, step_failed => llm, reason => ~"upstream error"}
        ])
    ),
    ?assertNotEqual(nomatch, binary:match(H, ~"failed at llm")),
    ?assertNotEqual(nomatch, binary:match(H, ~"upstream error")).

%% --- banto_dashboard_page:answer_html ---

answer_html_ok_test() ->
    H = iolist_to_binary(banto_dashboard_page:answer_html({ok, ~"the grounded answer"})),
    ?assertNotEqual(nomatch, binary:match(H, ~"the grounded answer")),
    ?assertNotEqual(nomatch, binary:match(H, ~"<pre>")).

answer_html_hits_test() ->
    Hits = [#{content => ~"code", metadata => #{~"repo" => ~"kura", ~"path" => ~"x.erl"}}],
    H = iolist_to_binary(banto_dashboard_page:answer_html({hits, Hits})),
    ?assertNotEqual(nomatch, binary:match(H, ~"kura/x.erl")).

answer_html_error_test() ->
    H = iolist_to_binary(banto_dashboard_page:answer_html({error, timeout})),
    ?assertNotEqual(nomatch, binary:match(H, ~"error:")),
    ?assertNotEqual(nomatch, binary:match(H, ~"timeout")).
