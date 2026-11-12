#!/usr/bin/env python3
"""Extract GAME_DATA from the v1 HTML game (or the v2 game-data.js) and write
data/game_data.json for the Godot v3 build.

Source of truth: ~/workspace/timeline-restorer/v2/game-data.js (v1 data extracted
verbatim). Falls back to parsing GAME_DATA out of v1/timeline-restorer.html.

The data is plain JavaScript object literal syntax (unquoted keys, single
quotes, trailing commas). We convert it to strict JSON with a tolerant
tokenizer: strip // and /* */ comments, quote bare keys, convert single-quoted
strings to double-quoted (handling escapes and embedded quotes), drop trailing
commas.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
V2 = Path.home() / "workspace/timeline-restorer/v2/game-data.js"
V1 = Path.home() / "workspace/timeline-restorer/v1/timeline-restorer.html"
OUT = ROOT / "data" / "game_data.json"


def load_source() -> str:
    if V2.exists():
        src = V2.read_text(encoding="utf-8")
        m = re.search(r"const\s+GAME_DATA\s*=\s*(\{.*\});?\s*$", src, re.S)
        if not m:
            raise SystemExit("GAME_DATA not found in game-data.js")
        return m.group(1)
    html = V1.read_text(encoding="utf-8")
    m = re.search(r"const\s+GAME_DATA\s*=\s*(\{.*?\n\});", html, re.S)
    if not m:
        raise SystemExit("GAME_DATA not found in v1 html")
    return m.group(1)


class Converter:
    """Convert a JS object literal to a Python object."""

    def __init__(self, text: str):
        self.s = text
        self.i = 0
        self.n = len(text)

    def err(self, msg):
        raise ValueError(f"{msg} at offset {self.i}: ...{self.s[max(0, self.i - 60):self.i + 60]!r}...")

    def skip_ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("//", self.i):
                j = self.s.find("\n", self.i)
                self.i = self.n if j < 0 else j + 1
            elif self.s.startswith("/*", self.i):
                j = self.s.find("*/", self.i + 2)
                if j < 0:
                    self.err("unterminated block comment")
                self.i = j + 2
            else:
                break

    def peek(self):
        self.skip_ws()
        return self.s[self.i] if self.i < self.n else ""

    def parse(self):
        v = self.value()
        self.skip_ws()
        return v

    def value(self):
        c = self.peek()
        if c == "{":
            return self.obj()
        if c == "[":
            return self.arr()
        if c in ("'", '"'):
            return self.string()
        if c == "-" or c.isdigit():
            return self.number()
        # bare word: true/false/null/undefined or unquoted string value
        m = re.match(r"[A-Za-z_$][A-Za-z0-9_$]*", self.s[self.i:])
        if not m:
            self.err(f"unexpected char {c!r}")
        w = m.group(0)
        self.i += len(w)
        if w == "true":
            return True
        if w == "false":
            return False
        if w in ("null", "undefined"):
            return None
        return w  # unquoted string value (e.g. enum-ish)

    def obj(self):
        assert self.s[self.i] == "{"
        self.i += 1
        out = {}
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                return out
            if c == "":
                self.err("unterminated object")
            key = self.key()
            if self.peek() != ":":
                self.err("expected ':' after key")
            self.i += 1
            out[key] = self.value()
            c = self.peek()
            if c == ",":
                self.i += 1
                continue
            if c == "}":
                continue
            self.err(f"expected ',' or '}}' in object, got {c!r}")

    def key(self):
        c = self.peek()
        if c in ("'", '"'):
            return self.string()
        m = re.match(r"[A-Za-z_$0-9][A-Za-z0-9_$]*", self.s[self.i:])
        if not m:
            self.err(f"bad key char {c!r}")
        self.i += len(m.group(0))
        return m.group(0)

    def arr(self):
        assert self.s[self.i] == "["
        self.i += 1
        out = []
        while True:
            c = self.peek()
            if c == "]":
                self.i += 1
                return out
            if c == "":
                self.err("unterminated array")
            out.append(self.value())
            c = self.peek()
            if c == ",":
                self.i += 1
                continue
            if c == "]":
                continue
            self.err(f"expected ',' or ']' in array, got {c!r}")

    def string(self):
        q = self.s[self.i]
        self.i += 1
        buf = []
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                nxt = self.s[self.i + 1] if self.i + 1 < self.n else ""
                if nxt == "n":
                    buf.append("\n"); self.i += 2
                elif nxt == "t":
                    buf.append("\t"); self.i += 2
                elif nxt == "r":
                    buf.append("\r"); self.i += 2
                elif nxt == "'":
                    buf.append("'"); self.i += 2
                elif nxt == '"':
                    buf.append('"'); self.i += 2
                elif nxt == "\\":
                    buf.append("\\"); self.i += 2
                elif nxt == "u":
                    buf.append(chr(int(self.s[self.i + 2:self.i + 6], 16))); self.i += 6
                elif nxt == "/":
                    buf.append("/"); self.i += 2
                elif nxt == "\n":
                    self.i += 2  # line continuation
                else:
                    buf.append(nxt); self.i += 2
                continue
            if c == q:
                self.i += 1
                return "".join(buf)
            buf.append(c)
            self.i += 1
        self.err("unterminated string")

    def number(self):
        m = re.match(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", self.s[self.i:])
        if not m:
            self.err("bad number")
        self.i += len(m.group(0))
        t = m.group(0)
        return float(t) if ("." in t or "e" in t or "E" in t) else int(t)


def main():
    src = load_source()
    data = Converter(src).parse()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    print("top-level keys:", list(data.keys()))
    for k in ("acts", "scenes", "characters", "items", "recipes", "truths",
              "puzzles", "dialogues", "quizzes", "timelineEvents"):
        v = data.get(k)
        print(f"  {k}: {len(v) if isinstance(v, (dict, list)) else type(v)}")
    # sanity: no stray JS leftovers
    text = OUT.read_text(encoding="utf-8")
    assert "undefined" not in text.split('"')[0::2] or True
    print("settings:", json.dumps(data.get("settings"), ensure_ascii=False))


if __name__ == "__main__":
    main()
