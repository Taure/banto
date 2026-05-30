-module(banto_chunk).
-moduledoc """
Dispatches file content to a chunking strategy by extension, returning
`{Text, MetaFragment}` pairs. The fragment is merged into each chunk's bunko
metadata by `banto_indexer` (e.g. a `symbol`). Markdown splits on heading
sections; everything else falls back to `banto_indexer`'s line slicer with an
empty fragment. See ADR 0006.
""".

-callback chunk(binary()) -> [{binary(), map()}].

-export([chunk/2]).

-spec chunk(file:filename_all(), binary()) -> [{binary(), map()}].
chunk(Path, Content) ->
    case strategy(Path) of
        undefined -> [{Text, #{}} || Text <- banto_indexer:chunk(Content)];
        Mod -> Mod:chunk(Content)
    end.

-spec strategy(file:filename_all()) -> module() | undefined.
strategy(Path) ->
    case unicode:characters_to_binary(filename:extension(Path)) of
        ~".md" -> banto_chunk_markdown;
        ~".markdown" -> banto_chunk_markdown;
        _ -> undefined
    end.
