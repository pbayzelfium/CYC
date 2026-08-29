"""Inline the rendered designs and palettes into the catalogue page."""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
ROOT = pathlib.Path.home() / ".oh-my-posh"

designs = json.loads((HERE / "prompt-designs.json").read_text(encoding="utf-8"))
palettes = json.loads((ROOT / "palettes.json").read_text(encoding="utf-8"))

ACCENTS = ("os", "path", "gitClean", "gitDirty", "danger", "python")


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def hue_sat_light(h):
    r, g, b = rgb(h)
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


def luminance(h):
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def theme_traits(v):
    """Derived from the palette itself, so a theme added later is tagged
    automatically — no hand-maintained list to fall out of date."""
    t = []
    hue, sat, light = hue_sat_light(v["bg"])
    if sat < 0.06:
        t.append("neutral")
    elif hue < 70 or hue >= 330:
        t.append("warm")
    elif 180 <= hue < 330:
        t.append("cool")
    else:
        t.append("neutral")

    t.append("deep" if light < 0.13 else "raised")

    mean_sat = sum(hue_sat_light(v[k])[1] for k in ACCENTS) / len(ACCENTS)
    t.append("vivid" if mean_sat >= 0.6 else "muted")

    lb, lf = luminance(v["bg"]), luminance(v["fg"])
    ratio = (max(lb, lf) + 0.05) / (min(lb, lf) + 0.05)
    t.append("high contrast" if ratio >= 11 else "soft")
    return t


themes = []
for slug, v in palettes.items():
    if slug.startswith("_"):
        continue
    # the whole palette travels: the page recolours designs onto it in the
    # browser, using the same mapping the shell uses
    themes.append({
        "slug": slug,
        "traits": theme_traits(v),
        **{k: v[k] for k in
           ("scheme", "bg", "fg", "segFg", "dim", "ahead", "node") + ACCENTS
           if k in v},
    })


def embed(obj):
    # '<' escaped so no payload can close the host <script> element
    return json.dumps(obj, ensure_ascii=False).replace("<", "\\u003c")


font = (HERE / "catalogue-font.b64").read_text(encoding="utf-8").strip()

html = (HERE / "catalogue-template.html").read_text(encoding="utf-8")
html = (html.replace("__THEMES__", embed(themes))
            .replace("__DESIGNS__", embed(designs))
            .replace("__FONT__", font))

out = HERE / "theme-catalogue.html"
out.write_text(html, encoding="utf-8")
print("wrote %s  (%.0f KB, %d themes, %d designs)"
      % (out, out.stat().st_size / 1024, len(themes), len(designs)))
for token in ("__THEMES__", "__DESIGNS__", "__FONT__"):
    assert token not in html, "placeholder left in output: %s" % token
assert "</script>" not in embed(designs), "script breakout risk"
print("placeholders substituted, no breakout")
