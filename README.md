# CYC — Customize Your Claude

One command turns a bare Windows Terminal into a themed one, with a prompt, matched colour
schemes, and a Claude Code status line that follows whichever theme is active.

```powershell
pwsh -NoProfile -File install.ps1
```

## What you get

**A prompt** showing the folder, git branch with dirty / ahead / behind counts, Python venv,
and Node version — powerline segments in a Nerd Font.

**Matched themes.** Seven to start (Catppuccin Mocha, Tokyo Night, Kanagawa Wave, Nord,
Dracula, Gruvbox Dark, Rose Pine). Switching one moves the window background, the 16 ANSI
colours, the prompt and the status line together, so they never clash.

**Automatic recolouring.** oh-my-posh ships ~120 prompt designs, each with colours of its own.
Pick any of them and it is remapped onto your theme's palette — greyscale by lightness,
coloured by hue — then checked so no segment's text lands on its own background colour and
disappears. Brightness and saturation are adjustable.

**A Claude Code status line** — model, reasoning effort, folder, git state, a context-usage
bar, session cost, elapsed time, lines changed, and your rate-limit window with a countdown.
It reads the active palette on every refresh, so it always matches the window.

**A `/terminal-theme` slash command** to drive all of it from inside Claude Code, with a
numbered menu so nothing has to be typed from memory.

**A one-command theme installer** for 600+ more schemes:

```powershell
Find-TerminalTheme rose          # search
Install-TerminalTheme 'Rose Pine'
tt rose-pine                     # or: tt 7, or tts for the menu
```

## Requirements

- Windows 10/11 with **Windows Terminal** and **PowerShell 7**:

  ```powershell
  winget install --id Microsoft.PowerShell --scope machine
  ```

  Use `--scope machine`. The Microsoft Store build of PowerShell 7 installs
  **per user**, so it is invisible to every other account on the machine — which
  is easy to miss until someone else signs in and `pwsh` is not found.
- `winget` for the font, `git` for the prompt's git segment
- Python only for the optional catalogue builder — `-SkipCatalogue` leaves it out

## Options

| Flag | Effect |
|------|--------|
| `-DryRun` | Print every step and change nothing |
| `-SkipCatalogue` | Leave out the catalogue builder, the only part needing Python |
| `-TestRoot <dir>` | Install into a throwaway directory; used by the test suite |

## It tries not to break what you have

Every file it overwrites leaves a `.bak` beside it. Windows Terminal settings and
`~/.claude/settings.json` are **merged**, so your own colour schemes, terminal profiles,
keybindings and Claude settings survive. The PowerShell profile gets a **marked block**
appended, so an existing profile is kept and a re-run replaces only that block.

Those are not claims — they are what `test-install.ps1` asserts.

## Testing

```powershell
pwsh -NoProfile -File test-install.ps1
```

Runs the installer into a temp directory pre-seeded with someone else's profile, colour scheme,
terminal profile, keybinding and Claude settings, then checks all of it survived, the files
landed, a prompt variant exists per palette, and a second run does not duplicate anything.
25 assertions, a few seconds.

CI goes further on a clean `windows-latest` runner: parse, payload decode, dry run, the suite,
then a **real install from nothing** including the downloads, rendering every generated prompt
and verifying a recoloured design uses only palette colours. That runner is the closest thing
to a first-time user, and it is the check that matters most.

Not covered anywhere: the Windows Terminal step (the runner has none — it warns and skips), and
whether a font winget just installed is visible to Windows Terminal before a reboot.

## Layout

```
install.ps1            self-contained installer, generated
install-template.ps1   its source, before the payload is embedded
build-installer.py     reads the live files and emits both of the above
test-install.ps1       the assertions
src/                   the same payload as plain readable files
```

`install.ps1` embeds everything as base64, which nobody should run unread — `src/` is the
identical content in plain form, generated from the same source so the two cannot disagree.

To rebuild after changing anything:

```powershell
python build-installer.py
```

It strips personal folder shortcuts out of the prompt config, and refuses to build if a palette
names a colour scheme Windows Terminal does not have — a mismatch that would otherwise ship
themes that cannot be selected.

## The catalogue

An optional page rendering every prompt design against the same git repo, with filters, a full
terminal preview, and brightness / saturation sliders whose values are carried into the command
you copy. It needs Python:

```powershell
python -m venv ~/.oh-my-posh/catalogue/.venv
~/.oh-my-posh/catalogue/.venv/Scripts/python -m pip install fonttools brotli
pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1
```

That writes `theme-catalogue.html`, which can be opened directly or published as a Claude
artifact. Its previews embed a subsetted Nerd Font, so the glyphs render on any machine.

## Credit

Built on [oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) by Jan De Dobbeleer, the
[Nerd Fonts](https://www.nerdfonts.com/) project, and the colour schemes collected in
[mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).
