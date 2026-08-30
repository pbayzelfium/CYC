"""Package this whole terminal setup into one self-contained install.ps1.

Reads the live files rather than a copy, so the installer cannot drift from
what is actually running here. Re-run it after changing any of them.

    python build-installer.py
"""
import base64
import json
import pathlib
import re

HOME = pathlib.Path.home()
ROOT = HOME / ".oh-my-posh"
CLAUDE = HOME / ".claude"
OUT = ROOT / "share" / "install.ps1"

# (source, destination relative to $HOME, needed?)
FILES = [
    (ROOT / "palettes.json",        ".oh-my-posh/palettes.json",        True),
    (ROOT / "build-variants.ps1",   ".oh-my-posh/build-variants.ps1",   True),
    (ROOT / "pair-prompt.py",       ".oh-my-posh/pair-prompt.py",       True),
    (ROOT / "theme-tools.ps1",      ".oh-my-posh/theme-tools.ps1",      True),
    (CLAUDE / "statusline.ps1",     ".claude/statusline.ps1",           True),
    (CLAUDE / "commands/terminal-theme.md", ".claude/commands/terminal-theme.md", True),
    (ROOT / "share/uninstall.ps1", ".oh-my-posh/uninstall.ps1", True),
    (ROOT / "cyc-protocol.ps1", ".oh-my-posh/cyc-protocol.ps1", True),
    (ROOT / "catalogue/render-prompts.py",     ".oh-my-posh/catalogue/render-prompts.py",     False),
    (ROOT / "catalogue/subset-font.py",        ".oh-my-posh/catalogue/subset-font.py",        False),
    (ROOT / "catalogue/build-catalogue.py",    ".oh-my-posh/catalogue/build-catalogue.py",    False),
    (ROOT / "catalogue/catalogue-template.html", ".oh-my-posh/catalogue/catalogue-template.html", False),
    (ROOT / "catalogue/rebuild.ps1",           ".oh-my-posh/catalogue/rebuild.ps1",           False),
]


def cyc_generic():
    """The custom prompt, minus this machine's personal folder shortcuts."""
    cfg = json.loads((ROOT / "cyc.omp.json").read_text(encoding="utf-8"))
    for block in cfg.get("blocks", []):
        for seg in block.get("segments", []):
            seg.get("options", {}).pop("mapped_locations", None)
    return json.dumps(cfg, indent=2)


def profile_block():
    """Everything after the UTF-8 header, so it can be appended to a profile
    that already exists rather than replacing someone's work."""
    p = HOME / "OneDrive/Documentos/PowerShell/Microsoft.PowerShell_profile.ps1"
    if not p.exists():
        p = HOME / "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
    t = p.read_text(encoding="utf-8")
    start = t.index("# UTF-8 out, always.")
    end = t.index("#  Your own additions below this line")
    return t[start:end].rstrip() + "\n"


def b64(text):
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def chunks(s, n=110):
    return "\n".join(s[i:i + n] for i in range(0, len(s), n))


payload = {}
for src, dest, required in FILES:
    if not src.exists():
        if required:
            raise SystemExit(f"missing required file: {src}")
        print(f"  skipped (absent): {dest}")
        continue
    payload[dest] = (b64(src.read_text(encoding="utf-8")), required)

payload[".oh-my-posh/cyc.omp.json"] = (b64(cyc_generic()), True)
payload["__profile__"] = (b64(profile_block()), True)


def scheme_defs():
    """The Windows Terminal colour scheme objects for every palette, lifted from
    this machine's settings. Without these a fresh install has palettes naming
    schemes that do not exist, and switching themes fails."""
    import os
    wt = (pathlib.Path(os.environ["LOCALAPPDATA"]) /
          "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json")
    have = json.loads(wt.read_text(encoding="utf-8")).get("schemes", [])
    wanted = {v["scheme"] for k, v in
              json.loads((ROOT / "palettes.json").read_text(encoding="utf-8")).items()
              if not k.startswith("_")}
    out = [s for s in have if s.get("name") in wanted]
    missing = wanted - {s["name"] for s in out}
    if missing:
        raise SystemExit(f"scheme definitions missing from Windows Terminal: {sorted(missing)}")
    print(f"  packaged {len(out)} colour schemes")
    return json.dumps(out, indent=2)


payload[".oh-my-posh/schemes.json"] = (b64(scheme_defs()), True)


def catalogue_page():
    """The built catalogue. Shipped rather than built on the user's machine:
    building needs Python, a virtualenv and fonttools, so requiring it meant
    nobody got a catalogue at all. Strips the link to this instance's private
    Control Room artifact, which nobody else can open."""
    f = ROOT / "catalogue/theme-catalogue.html"
    if not f.exists():
        raise SystemExit("catalogue not built - run catalogue/rebuild.ps1 first")
    html = f.read_text(encoding="utf-8")
    html = re.sub(r" The settings behind them live in the <a [^>]*>[^<]*</a>\.", "", html)
    if "claude.ai/code/artifact" in html:
        raise SystemExit("a private artifact link is still in the catalogue")

    # This page is published. oh-my-posh renders the real user, host, hardware
    # and whatever Spotify is playing, so refuse to build rather than leak it.
    import getpass
    import socket
    leaks = {
        getpass.getuser(): "your username",
        socket.gethostname(): "your computer name",
        str(pathlib.Path.home()): "your home path",
    }
    found = [why for token, why in leaks.items() if token and token in html]
    if found:
        raise SystemExit(
            "catalogue still contains " + ", ".join(found) +
            "\n  Close Spotify, then rebuild:"
            "\n  pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1")
    return html


payload[".oh-my-posh/catalogue/theme-catalogue.html"] = (b64(catalogue_page()), True)

# A manifest, not a payload: the installer fetches these as plain files.
blob = "\n".join(
    f"  '{dest}' = ${'true' if req else 'false'}"
    for dest, (_data, req) in payload.items() if dest != "__profile__")

TEMPLATE = (ROOT / "share" / "install-template.ps1").read_text(encoding="utf-8")
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(TEMPLATE.replace("#__MANIFEST__", blob), encoding="utf-8")

kb = OUT.stat().st_size / 1024
print(f"wrote {OUT}  ({kb:.0f} KB, {len(payload)} files)")
body = OUT.read_text(encoding="utf-8")
assert "#__MANIFEST__" not in body
assert len(body) < 60_000, "installer got big again - is something embedded?"
print("manifest substituted")

# Also emit the payload as plain files. install.ps1 is a base64 blob nobody
# should run unread; src/ is the same content, reviewable, and generated from
# the same source so the two cannot disagree.
src = OUT.parent / "src"
if src.exists():
    import shutil
    shutil.rmtree(src)
for dest, (data, _req) in payload.items():
    name = "profile-block.ps1" if dest == "__profile__" else dest
    f = src / name
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(base64.b64decode(data).decode("utf-8"), encoding="utf-8")

# the generator and its template belong in the repo too
import shutil
shutil.copy2(__file__, OUT.parent / "build-installer.py")
print(f"wrote {src}  ({len(payload)} readable copies)")
