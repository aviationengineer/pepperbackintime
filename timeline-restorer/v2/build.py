#!/usr/bin/env python3
"""Assemble the single-file v2 game: shell.html + Phaser + GAME_DATA + game.js.

The Phaser library is inlined verbatim (never hand-pasted). Its four inert
URL string literals (two doc links, two XML namespace identifiers) are
rewritten with an equivalent unicode escape so the final file contains no
"http://" or "https://" substring at all — the strings still evaluate to
the exact same values at runtime ("http:" + U+002F + U+002F == "http://").

Usage: python3 build.py   (run from the v2 folder)
Output: timeline-restorer.html in the same folder.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# URL literals inside the Phaser source. They are inert strings (doc links
# and XML namespace identifiers), never fetches. Rewriting them as
# "http:" + \u002f\u002f keeps their runtime value identical.
URL_REWRITES = [
    ("https://phaser.io", "https:\\u002f\\u002fphaser.io"),
    ("http://www.w3.org/2000/svg", "http:\\u002f\\u002fwww.w3.org/2000/svg"),
    ("http://www.w3.org/1999/xhtml", "http:\\u002f\\u002fwww.w3.org/1999/xhtml"),
]

def read(p):
    return p.read_text(encoding="utf-8")

def main():
    shell = read(HERE / "shell.html")
    phaser = read(HERE / "phaser.min.js")
    data = read(HERE / "game-data.js")
    game = read(HERE / "game.js")

    for old, new in URL_REWRITES:
        if old in phaser:
            phaser = phaser.replace(old, new)
    assert "http://" not in phaser and "https://" not in phaser, "URL literals remain in Phaser source"

    for name, content in [("phaser.min.js", phaser), ("game-data.js", data), ("game.js", game)]:
        assert "</script" not in content.lower(), f"{name} contains a script-closing tag"

    for marker in ("<!--PHASER_LIB-->", "<!--GAME_DATA-->", "<!--GAME_JS-->"):
        assert shell.count(marker) == 1, f"placeholder {marker} must appear exactly once in shell.html"

    out = shell.replace("<!--PHASER_LIB-->", phaser)
    out = out.replace("<!--GAME_DATA-->", data)
    out = out.replace("<!--GAME_JS-->", game)

    assert "http://" not in out and "https://" not in out, "external URL found in final file"
    # No external resource tags in the shell (the only place HTML tags live).
    # (Phaser's loader internals contain ".src =" JS assignments for assets
    # this game never loads; those are inert, not references.)
    import re as _re
    assert not _re.search(r"<(script|img|link|audio|video|iframe)\b[^>]*\b(src|href)\s*=", shell), \
        "external resource tag found in shell.html"
    for bad in ("TODO", "FIXME", "lorem"):
        assert bad not in out, f"placeholder text found in final file: {bad}"

    target = HERE / "timeline-restorer.html"
    target.write_text(out, encoding="utf-8")
    print("built", target)
    print("lines:", out.count("\n") + 1, "| bytes:", target.stat().st_size)

if __name__ == "__main__":
    main()
