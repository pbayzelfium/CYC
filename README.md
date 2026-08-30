# CYC - Customize Your Claude

Turns a bare Windows Terminal into a themed one, with a prompt, matched colour schemes, and a
Claude Code status line that follows whichever theme is active.

## Install

**Download it, then run it.** Two steps on purpose - see the note below.

```powershell
irm https://raw.githubusercontent.com/pbayzelfium/CYC/main/install.ps1 -OutFile "$env:TEMP\cyc-install.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "$env:TEMP\cyc-install.ps1"
```

To see what it would do without changing anything, add `-DryRun` to the second line.
If it is already installed and you are upgrading, add `-Force`.

When it finishes, the theme catalogue opens in your browser by itself.

<details>
<summary>Why not a one-line <code>irm | iex</code>?</summary>

Because `irm <url> | iex` is the shape of a real attack technique - the one security guidance
tells people never to run, and which Microsoft Defender flags by pattern. An installer that
trips someone's antivirus reads as a virus regardless of what it actually does.

So: no piping into `iex`, and **no encoded payload**. `install.ps1` is about 27 KB of readable
PowerShell that fetches its files as plain text from `src/` in this repo. It previously carried
them as 531 KB of base64 - the other shape scanners flag, because that is what packed malware
looks like.

Every line of what gets installed is readable before you run it: `install.ps1` itself, and the
files it fetches under [src/](https://github.com/pbayzelfium/CYC/tree/main/src).

`powershell`, not `pwsh` - `powershell` is on every Windows, while `pwsh` is one of the things
this installs. Once running, it installs PowerShell 7 and restarts itself there.
`-ExecutionPolicy Bypass` is needed because Windows blocks downloaded scripts by default.

**Installing without internet access**, or from a checkout: pass `-Source <dir>` pointing at a
copy of `src/`.

</details>

## What you get

**A prompt** showing the folder, git branch with dirty / ahead / behind counts, Python venv,
and Node version - powerline segments in a Nerd Font.

**Matched themes.** Seven to start (Catppuccin Mocha, Tokyo Night, Kanagawa Wave, Nord,
Dracula, Gruvbox Dark, Rose Pine). Switching one moves the window background, the 16 ANSI
colours, the prompt and the status line together, so they never clash.

**A catalogue you click.** Every prompt design rendered against the same repository, with
filters, a full-size terminal preview, and brightness / saturation sliders. Pick what you want
and press **Apply** - your terminal changes, with nothing to copy or paste. It opens itself when
you install, and `catalogue` reopens it.

**Automatic recolouring.** oh-my-posh ships ~120 prompt designs, each with colours of its own.
Pick any of them and it is remapped onto your theme's palette - greyscale by lightness, coloured
by hue - then checked so no segment's text lands on its own background colour and disappears.

**A Claude Code status line** - model, reasoning effort, folder, git state, a context-usage
bar, session cost, elapsed time, lines changed, and your rate-limit window with a countdown.
It reads the active palette on every refresh, so it always matches the window.

**A `/terminal-theme` slash command** to drive all of it from inside Claude Code, with a
numbered menu so nothing has to be typed from memory.

**A one-command theme installer** for 600+ more schemes. Adding one refreshes the catalogue
by itself:

```powershell
Find-TerminalTheme rose          # search
Install-TerminalTheme 'Rose Pine'
tt rose-pine                     # or: tt 7, or tts for the menu
```

## Requirements

**Windows 10 or 11. That is the whole list.**

The installer brings everything else itself - you should not have to fetch anything first:

| It installs | Why |
|-------------|-----|
| PowerShell 7 | If you start it from Windows PowerShell 5.1 it installs 7 and **restarts itself there** |
| Windows Terminal | Nothing to theme without it |
| JetBrainsMono Nerd Font | The prompt's icons. Falls back to a per-user font install if winget is unavailable, which needs no admin |
| oh-my-posh + ~120 designs | The prompt itself |
| Terminal-Icons | File and folder glyphs in `ls` |
| git | The prompt's git segment stays empty without it |
| Python + fonttools | **Not optional.** Recolouring a design onto a theme runs `pair-prompt.py` at the moment you switch, so without Python that feature is dead, not degraded |

It also registers a `cyc://` link handler under `HKCU`, which is what lets the catalogue's
**Apply** button reach your terminal. No admin needed, and uninstall removes it.

It prefers `winget` and falls back to direct downloads where it can. Anything it genuinely
cannot install is reported at the end as a warning naming what is missing and what that costs
you - it never fails silently or leaves you guessing.

## Removing it

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File ~/.oh-my-posh/uninstall.ps1 -DryRun
pwsh -NoProfile -File ~/.oh-my-posh/uninstall.ps1
```

Takes out only what it put in: its block from your profile, its colour schemes and appearance
keys from Windows Terminal, its `statusLine` entry from Claude, the `cyc://` registration, and
its own files. Your schemes, terminal profiles, keybindings and settings stay. `-RestoreBackup`
rolls those three files back to the `.bak` copies instead, and `-KeepDownloads` keeps the
prompt designs.

It leaves PowerShell 7, Windows Terminal, git, Python, the font and Terminal-Icons alone -
they are general tools and something else may now depend on them.

## Updating

It checks once a day, on a new terminal, against a six-byte `VERSION` file in this
repository. When there is a newer build it says so and installs it:

```
We detected an update: 1.1.0 -> 1.2.0
Installing it now. Nothing you set up will change.
```

Opening the catalogue checks too, and installs first, so what opens is the current
one. If the check fails the catalogue still opens - an unreachable server is never a
reason not to show you the page.

You can also ask at any time - from a terminal, or with **Check for updates** in the
catalogue's header, which opens a console window so you can watch it:

```powershell
Test-CycUpdate   # is there one?
Update-Cyc       # install it
```

**An update takes nothing away.** Your theme, your prompt design, the brightness and
saturation you settled on, the themes you installed, and your own edits to the prompt
config are all kept - only the program is replaced. If you edited `cyc.omp.json`, yours
stays and the new one is written beside it as `cyc.omp.json.new`, yours to take or ignore.

The single exception is a prompt design that no longer exists in the new build. Then it
falls back to the default **and says so** - it will not quietly land you somewhere else.

Every one of those is asserted by the test suite, and each assertion has been checked to
fail when the preserving is removed.

To turn the daily check off:

```powershell
New-Item ~/.oh-my-posh/no-auto-update -ItemType File
```

## Options

| Flag | Effect |
|------|--------|
| `-DryRun` | Print every step and change nothing |
| `-Force` | Re-run over an existing install. Without it, an existing install is left alone, because re-running replaces the prompt config and would lose edits to it |
| `-NoOpen` | Do not open the catalogue when it finishes |
| `-SkipCatalogue` | Leave out the catalogue's build scripts. The catalogue itself is installed either way |
| `-Source <dir>` | Install from a local copy of `src/` instead of fetching from GitHub |
| `-Update` | Install a newer build over this one, keeping everything you set up. What `Update-Cyc` uses |
| `-TestRoot <dir>` | Install into a throwaway directory; used by the test suite |

## It tries not to break what you have

Every file it overwrites leaves a `.bak` beside it. Windows Terminal settings and
`~/.claude/settings.json` are **merged**, so your own colour schemes, terminal profiles,
keybindings and Claude settings survive. The PowerShell profile gets a **marked block**
appended, so an existing profile is kept and a re-run replaces only that block.

Those are not claims - they are what `test-install.ps1` asserts.

## Testing

```powershell
pwsh -NoProfile -File test-install.ps1
```

Installs into a temp directory pre-seeded with someone else's profile, colour scheme, terminal
profile, keybinding and Claude settings; checks all of it survived; then re-installs and
uninstalls, asserting both that CYC's traces are gone and that their work is still there.
**37 assertions, a few seconds.**

CI runs on a clean `windows-latest` runner on every push: parses every script, refuses anything
base64-encoded or piped into `iex`, checks each manifest entry exists, runs the suite, then does
a **real install from nothing** including the downloads - rendering every generated prompt,
verifying a recoloured design uses only palette colours, and confirming the `cyc://` handler
refuses path traversal, injected commands, out-of-range numbers, unknown themes and foreign
URL schemes.

What CI cannot reach - Windows Terminal, the browser, a person clicking - was covered by hand on
a clean Windows profile. See [test/README.md](test/README.md) for what was run, what it found,
and what is still unproven.

## Layout

```
install.ps1            the installer: fetches src/ and configures everything
install-template.ps1   its source, before the file manifest is substituted
build-installer.py     reads the live files and emits install.ps1 + src/
uninstall.ps1          removes what the installer added
test-install.ps1       the assertions
src/                   everything the installer writes, as plain files
test/                  clean-machine testing: Sandbox, a second user account
```

`install.ps1` fetches `src/` as plain text at install time, so what it will write is readable
here first. Both are generated from the live files by one script, so they cannot disagree.

To rebuild after changing anything:

```powershell
python build-installer.py
```

It strips personal folder shortcuts out of the prompt config, refuses to build if a palette
names a colour scheme Windows Terminal does not have, and refuses if the catalogue still
contains a username, computer name or home path - the previews are rendered from a live machine,
so that guard is the thing standing between a rebuild and publishing someone's details.

## The catalogue

Ships pre-built and opens when you install. `catalogue` reopens it.

Rebuilding is only needed if you edit the page itself; installing a theme refreshes it
automatically. The toolchain is set up by the installer, so:

```powershell
pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1
```

The previews embed a subsetted Nerd Font, so the glyphs render on any machine, including one
that has never installed the font.

## Credit

Built on [oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) by Jan De Dobbeleer, the
[Nerd Fonts](https://www.nerdfonts.com/) project, and the colour schemes collected in
[mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).
JetBrains Mono is under the SIL Open Font License 1.1; the Nerd Fonts patcher is MIT.
