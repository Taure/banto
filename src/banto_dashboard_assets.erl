-module(banto_dashboard_assets).
-moduledoc """
Serves the dashboard's two static assets from `priv/static/assets` via a
whitelist (no path traversal). A controller rather than cowboy_static, so asset
serving does not depend on the cowboy version Nova happens to resolve.
""".

-export([serve/1]).

serve(Req) ->
    case asset(cowboy_req:path(Req)) of
        {ok, Rel, ContentType} ->
            File = filename:join([code:priv_dir(banto), "static", "assets", Rel]),
            case file:read_file(File) of
                {ok, Bin} ->
                    {status, 200,
                        #{~"content-type" => ContentType, ~"cache-control" => ~"no-store"}, Bin};
                {error, _} ->
                    {status, 404, #{}, ~"not found"}
            end;
        error ->
            {status, 404, #{}, ~"not found"}
    end.

asset(~"/assets/css/app.css") -> {ok, "css/app.css", ~"text/css; charset=utf-8"};
asset(~"/assets/js/datastar.js") -> {ok, "js/datastar.js", ~"text/javascript; charset=utf-8"};
asset(_) -> error.
