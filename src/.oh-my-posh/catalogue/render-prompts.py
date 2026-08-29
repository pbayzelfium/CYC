"""Render every oh-my-posh prompt design to HTML for the catalogue artifact.

Runs `oh-my-posh print primary` per theme against one fixed git repo so the
previews are comparable, converts the ANSI to spans, and tags each design with
the traits the catalogue filters on.
"""
import html
import json
import os
import pathlib
import re
import subprocess
import sys

def _find_omp():
    import shutil
    for c in (pathlib.Path.home() / ".local/bin/oh-my-posh.exe",
              pathlib.Path.home() / "AppData/Local/Programs/oh-my-posh/bin/oh-my-posh.exe"):
        if c.exists():
            return str(c)
    found = shutil.which("oh-my-posh")
    if not found:
        raise SystemExit("oh-my-posh not found on PATH")
    return found


OMP = _find_omp()
ROOT = pathlib.Path.home() / ".oh-my-posh"
HERE = pathlib.Path(__file__).parent
# A deliberately SHORT path: a deep one dominates every preview and pushes the
# interesting part of the prompt off the card.
PWD = str(pathlib.Path.home() / "omp-preview")


def ensure_repo():
    """Build the fixed preview repo so every design renders the same context:
    a branch called main, one modified file, one untracked file."""
    import shutil
    p = pathlib.Path(PWD)
    if p.exists():
        shutil.rmtree(p, ignore_errors=True)
    p.mkdir(parents=True, exist_ok=True)

    def git(*a):
        subprocess.run(["git", *a], cwd=PWD, capture_output=True, check=False)

    git("init", "-q", "-b", "main")
    git("config", "user.email", "preview@local")
    git("config", "user.name", "preview")
    (p / "README.md").write_text("hello\n", encoding="utf-8")
    (p / "package.json").write_text('{"name":"zaza"}\n', encoding="utf-8")
    git("add", "-A")
    git("commit", "-qm", "init")
    (p / "README.md").write_text("hello\nmore\n", encoding="utf-8")
    (p / "notes.txt").write_text("x\n", encoding="utf-8")

SGR = re.compile(r"\x1b\[([0-9;]*)m")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
# everything else: CSI sequences, the 2-byte save/restore-cursor pair, charset
# selects, and any lone ESC left over. Without this, ESC 7 / ESC 8 leak through
# and render as stray "7" and "8" in the preview.
OTHER_ESC = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][A-Za-z0-9]|\x1b[78=>MDEHc]|\x1b")

# xterm 256 palette
def xterm256():
    pal = [
        "#000000", "#800000", "#008000", "#808000", "#000080", "#800080",
        "#008080", "#c0c0c0", "#808080", "#ff0000", "#00ff00", "#ffff00",
        "#0000ff", "#ff00ff", "#00ffff", "#ffffff",
    ]
    levels = [0, 95, 135, 175, 215, 255]
    for r in levels:
        for g in levels:
            for b in levels:
                pal.append("#%02x%02x%02x" % (r, g, b))
    for i in range(24):
        v = 8 + i * 10
        pal.append("#%02x%02x%02x" % (v, v, v))
    return pal


PAL256 = xterm256()
# basic 16, tuned to sit on a dark ground
BASIC = [
    "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7",
    "#94e2d5", "#bac2de", "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
    "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
]


def ansi_to_html(text):
    text = OSC.sub("", text)
    # protect the SGR codes, drop every other escape, then restore
    text = SGR.sub(lambda m: "\x00%s\x01" % m.group(1), text)
    text = OTHER_ESC.sub("", text)
    text = re.sub(r"\x00([0-9;]*)\x01", lambda m: "\x1b[%sm" % m.group(1), text)
    fg = bg = None
    bold = reverse = False
    out = []
    pos = 0

    def open_tag():
        f, b = (bg, fg) if reverse else (fg, bg)
        st = []
        if f:
            st.append("color:%s" % f)
        if b:
            st.append("background:%s" % b)
        if bold:
            st.append("font-weight:700")
        return '<span style="%s">' % ";".join(st) if st else "<span>"

    out.append(open_tag())
    for m in SGR.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        pos = m.end()
        ps = [p for p in m.group(1).split(";") if p != ""] or ["0"]
        i = 0
        while i < len(ps):
            p = int(ps[i])
            if p == 0:
                fg = bg = None
                bold = reverse = False
            elif p == 1:
                bold = True
            elif p == 22:
                bold = False
            elif p == 7:
                reverse = True
            elif p == 27:
                reverse = False
            elif p in (38, 48):
                if i + 1 < len(ps) and ps[i + 1] == "2" and i + 4 < len(ps):
                    c = "#%02x%02x%02x" % tuple(int(ps[i + j]) for j in (2, 3, 4))
                    i += 4
                elif i + 1 < len(ps) and ps[i + 1] == "5" and i + 2 < len(ps):
                    c = PAL256[int(ps[i + 2]) % 256]
                    i += 2
                else:
                    i += 1
                    continue
                if p == 38:
                    fg = c
                else:
                    bg = c
            elif p == 39:
                fg = None
            elif p == 49:
                bg = None
            elif 30 <= p <= 37:
                fg = BASIC[p - 30]
            elif 90 <= p <= 97:
                fg = BASIC[p - 90 + 8]
            elif 40 <= p <= 47:
                bg = BASIC[p - 40]
            elif 100 <= p <= 107:
                bg = BASIC[p - 100 + 8]
            i += 1
        out.append("</span>")
        out.append(open_tag())
    out.append(html.escape(text[pos:]))
    out.append("</span>")
    return "".join(out)


def render(cfg):
    r = subprocess.run(
        [OMP, "print", "primary", "--config", str(cfg), "--shell", "pwsh",
         "--pwd", PWD, "--terminal-width", "70", "--status", "0",
         "--execution-time", "1400"],
        capture_output=True, timeout=25,
    )
    return r.stdout.decode("utf-8", "replace")


def traits(raw):
    t = []
    plain = OSC.sub("", SGR.sub("", raw))
    if "\ue0b0" in plain or "\ue0b2" in plain:
        t.append("powerline")
    if "\ue0b6" in plain or "\ue0b4" in plain or "\ue0b7" in plain or "\ue0b5" in plain:
        t.append("diamond")
    if not t:
        t.append("plain")
    if plain.count("\n") >= 1:
        t.append("multiline")
    else:
        t.append("oneline")
    if "main" in plain:
        t.append("git")
    # any 48; sequence means filled segment backgrounds
    if re.search(r"\x1b\[[0-9;]*4[08];", raw) or re.search(r"48;2;", raw):
        t.append("filled")
    else:
        t.append("outline")
    return t


def main():
    ensure_repo()
    items = []
    files = [(ROOT / "zelfium.omp.json", "zelfium", "custom")]
    for slug in json.loads((ROOT / "palettes.json").read_text(encoding="utf-8")):
        if slug.startswith("_"):
            continue
        files.append((ROOT / ("zelfium-%s.omp.json" % slug), "zelfium-%s" % slug, "paired"))
    for f in sorted((ROOT / "themes").glob("*.omp.json")):
        files.append((f, f.name[: -len(".omp.json")], "stock"))

    for cfg, name, kind in files:
        if not cfg.exists():
            continue
        try:
            raw = render(cfg)
        except Exception as e:
            print("skip %s: %s" % (name, e), file=sys.stderr)
            continue
        raw = raw.rstrip()
        # collapse the long run of padding before a right prompt
        raw = re.sub(r" {6,}", "   ", raw)
        items.append({
            "name": name,
            "kind": kind,
            "traits": traits(raw),
            "html": ansi_to_html(raw),
        })
        print(".", end="", flush=True)

    out = HERE / "prompt-designs.json"
    out.write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
    print("\nwrote %s  (%d designs, %.0f KB)" % (out, len(items), out.stat().st_size / 1024))


main()
