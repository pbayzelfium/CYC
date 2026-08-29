"""Recolour a prompt design to a terminal theme's palette.

    python pair-prompt.py <design> <theme-slug> [brightness] [saturation]

brightness and saturation are percentages, default 0. Brightness shifts every
colour's lightness; saturation scales it. The catalogue previews the same two
numbers with the identical formula, so what is copied from there is what the
shell produces.

Reads the design's oh-my-posh config, maps every colour it uses onto the
closest colour in the target palette, and writes ~/.oh-my-posh/paired/
<design>@<slug>.omp.json.

This is a translation, not a repaint by the design's author: a design that
leans on a colour the target palette has no equivalent for will lose that
distinction. The original is never modified and stays selectable.
"""
import json
import pathlib
import re
import sys

# its own folder, not the home directory: the script sits beside the palettes
# and designs it reads, so it works wherever the setup is installed
ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "paired"
HEX = re.compile(r"#([0-9a-fA-F]{6})\b")

# palette roles, split by how they get used
NEUTRALS = ("bg", "segFg", "dim", "fg")
ACCENTS = ("os", "path", "gitClean", "gitDirty", "danger", "ahead", "python", "node")


def hsl(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    mx, mn = max(r, g, b), min(r, g, b)
    light = (mx + mn) / 2
    if mx == mn:
        return 0.0, 0.0, light
    d = mx - mn
    sat = d / (2 - mx - mn) if light > 0.5 else d / (mx + mn)
    if mx == r:
        hue = ((g - b) / d) % 6
    elif mx == g:
        hue = (b - r) / d + 2
    else:
        hue = (r - g) / d + 4
    return hue * 60, sat, light


def hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def build_map(colours, pal):
    neutrals = [(k, hsl(pal[k])) for k in NEUTRALS if k in pal]
    accents = [(k, hsl(pal[k])) for k in ACCENTS if k in pal]
    out = {}
    for c in colours:
        h, s, l = hsl(c)
        if s < 0.18 or not accents:
            # greyscale-ish: keep its place on the light/dark axis
            key = min(neutrals, key=lambda kv: abs(kv[1][2] - l))[0]
        else:
            # coloured: keep its hue, take the palette's version of it
            key = min(accents, key=lambda kv: (hue_gap(kv[1][0], h), abs(kv[1][1] - s)))[0]
        out[c.lower()] = pal[key].lower()
    return out


def hsl_to_hex(h, s, l):
    def f(n):
        k = (n + h / 30) % 12
        a = s * min(l, 1 - l)
        return l - a * max(-1, min(k - 3, 9 - k, 1))
    return "#" + "".join("%02x" % round(max(0.0, min(1.0, f(n))) * 255) for n in (0, 8, 4))


def adjust(hexcol, brightness, saturation):
    """Shift lightness, scale saturation. Identical to the catalogue's version —
    if one changes the other must, or the preview stops predicting the result."""
    if not brightness and not saturation:
        return hexcol
    h, s, l = hsl(hexcol)
    l = max(0.0, min(1.0, l + brightness / 100.0))
    s = max(0.0, min(1.0, s * (1 + saturation / 100.0)))
    return hsl_to_hex(h, s, l)


def luminance(h):
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(int(h[i:i + 2], 16) / 255) for i in (1, 3, 5))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def fix_contrast(node, pal):
    """Mapping each colour on its own can put a segment's text on the same
    palette colour as its own background, and the text vanishes. No per-colour
    mapping can see that — it is a property of the pair — so repair it after."""
    inks = [pal[k] for k in ("segFg", "fg", "bg") if k in pal]
    if isinstance(node, dict):
        fg, bg = node.get("foreground"), node.get("background")
        if (isinstance(fg, str) and isinstance(bg, str)
                and fg.startswith("#") and bg.startswith("#")
                and contrast(fg, bg) < 3):
            node["foreground"] = max(inks, key=lambda i: contrast(bg, i))
        for v in node.values():
            fix_contrast(v, pal)
    elif isinstance(node, list):
        for v in node:
            fix_contrast(v, pal)


def resolve(design):
    for p in (ROOT / f"{design}.omp.json", ROOT / "themes" / f"{design}.omp.json"):
        if p.exists():
            return p
    sys.exit(f"no design called {design!r}")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: pair-prompt.py <design> <theme-slug> [brightness] [saturation]")
    design, slug = sys.argv[1], sys.argv[2]
    brightness = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    saturation = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0

    palettes = json.loads((ROOT / "palettes.json").read_text(encoding="utf-8"))
    if slug not in palettes:
        sys.exit(f"no theme called {slug!r}")
    pal = palettes[slug]

    src = resolve(design)
    text = src.read_text(encoding="utf-8")
    colours = sorted({("#" + m.group(1)).lower() for m in HEX.finditer(text)})
    if not colours:
        # nothing to remap (a design using only named/palette colours)
        OUT.mkdir(exist_ok=True)
        dest = OUT / f"{design}@{slug}.omp.json"
        dest.write_text(text, encoding="utf-8")
        print(dest)
        return

    mapping = {k: adjust(v, brightness, saturation)
               for k, v in build_map(colours, pal).items()}
    # single pass through placeholders so a substituted colour is never re-mapped
    for i, c in enumerate(colours):
        text = re.sub(re.escape(c), f"@@{i}@@", text, flags=re.IGNORECASE)
    for i, c in enumerate(colours):
        text = text.replace(f"@@{i}@@", mapping[c])

    cfg = json.loads(text)
    fix_contrast(cfg, pal)

    OUT.mkdir(exist_ok=True)
    dest = OUT / f"{design}@{slug}.omp.json"
    dest.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    print(dest)


main()
