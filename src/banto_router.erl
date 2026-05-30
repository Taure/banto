-module(banto_router).
-behaviour(nova_router).

-export([routes/1]).

routes(_Environment) ->
    [
        #{
            prefix => "",
            security => false,
            routes => [
                {"/", fun banto_dashboard_page:index/1, #{methods => [get]}},
                {"/dashboard/search", fun banto_dashboard_page:search/1, #{methods => [post]}},
                {"/dashboard/index", fun banto_dashboard_page:start_index/1, #{methods => [post]}},
                {"/dashboard/index/stream", fun banto_dashboard_page:index_stream/1, #{
                    methods => [get]
                }},
                {"/dashboard/flow/stream", fun banto_dashboard_page:flow_stream/1, #{
                    methods => [get]
                }},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/css/app.css", fun banto_dashboard_assets:serve/1, #{methods => [get]}},
                {"/assets/js/datastar.js", fun banto_dashboard_assets:serve/1, #{methods => [get]}}
            ]
        }
    ].
