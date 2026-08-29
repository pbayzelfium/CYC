"""Subset JetBrainsMono Nerd Font to only the characters the catalogue uses,
and emit it as a base64 WOFF2 for embedding.

The catalogue previously relied on the font being installed on the reader's
machine. It is installed on this machine, but the artifact viewer does not let
a page reach local fonts, so every Nerd Font glyph rendered as a box. Embedding
a subset removes the dependency entirely and survives sharing the link.
"""
import base64
import html
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
def _find_font():
    import os
    names = ("JetBrainsMonoNerdFont-Regular.ttf", "JetBrainsMonoNLNerdFont-Regular.ttf")
    roots = (pathlib.Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts",
             pathlib.Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/Windows/Fonts")
    for r in roots:
        for n in names:
            if (r / n).exists():
                return r / n
    return pathlib.Path("JetBrainsMonoNerdFont-Regular.ttf")


SRC = _find_font()
TAG = re.compile(r"<[^>]+>")


def used_codepoints():
    data = json.loads((HERE / "prompt-designs.json").read_text(encoding="utf-8"))
    chars = set()
    for d in data:
        chars.update(html.unescape(TAG.sub("", d["html"])))
    # everything the page itself draws in the mono face: box drawing, the
    # status-line marks, and the sample session output in the previews.
    # Anything added to the page in these fonts MUST be listed here or it
    # ships as a box.
    chars.update(chr(c) for c in range(0x20, 0x7F))
    chars.update("─│┌┐└┘·▸▹❯⎇●↑↓█░▐▌…—’")
    chars.update("✓✗⚠→←›‹×•√≈±§¶")
    chars.update("✻⏺⎿⧉◆◇▪▫")   # Claude Code's thinking / tool-call marks
    chars.discard("\n")
    chars.discard("\r")
    return sorted(chars)


def main():
    if not SRC.exists():
        sys.exit("font not found: %s" % SRC)

    cps = used_codepoints()
    out = HERE / "catalogue-font.woff2"
    unicodes = ",".join("U+%04X" % ord(c) for c in cps)

    subprocess.run([
        sys.executable, "-m", "fontTools.subset", str(SRC),
        "--unicodes=%s" % unicodes,
        "--flavor=woff2",
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
        "--output-file=%s" % out,
    ], check=True)

    b64 = base64.b64encode(out.read_bytes()).decode("ascii")
    (HERE / "catalogue-font.b64").write_text(b64, encoding="utf-8")
    print("%d codepoints -> %.1f KB woff2 (%.1f KB base64)"
          % (len(cps), out.stat().st_size / 1024, len(b64) / 1024))


main()
