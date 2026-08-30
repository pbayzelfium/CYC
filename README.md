# CYC - Customize Your Claude

Turns a bare Windows Terminal into a themed one: a prompt, matched colour schemes, and a
Claude Code status line that follows whichever theme is active. One command, and it installs
everything it needs.

## Install

```powershell
irm https://raw.githubusercontent.com/pbayzelfium/CYC/main/install.ps1 -OutFile "$env:TEMP\cyc-install.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "$env:TEMP\cyc-install.ps1"
```

Add `-DryRun` to the second line to see every step without changing anything. When it
finishes, the theme catalogue opens in your browser by itself.

Already installed? Don't re-run this - use `Update-Cyc`, or **Check for updates** in the
catalogue. See [Updating](#updating).

<details>
<summary>Why two steps, and not <code>irm | iex</code>?</summary>

Because `irm <url> | iex` is the shape of a real attack technique - the one security guidance
tells people never to run, and which Microsoft Defender flags by pattern. An installer that
trips someone's antivirus reads as a virus regardless of what it does.

So: no piping into `iex`, and **no encoded payload**. `install.ps1` is <!--SIZE-->37<!--/SIZE--> KB
of readable PowerShell that fetches its files as plain text from
[src/](https://github.com/pbayzelfium/CYC/tree/main/src). It once carried them as 531 KB of
base64 - the other shape scanners flag, because that is what packed malware looks like.

`powershell`, not `pwsh`: `powershell` is on every Windows, while `pwsh` is one of the things
this installs. Once running it installs PowerShell 7 and restarts itself there.
`-ExecutionPolicy Bypass` is needed because Windows blocks downloaded scripts by default.

Installing without internet, or from a checkout: pass `-Source <dir>` pointing at a copy of
`src/`.

</details>

## What you get

- **A prompt** - folder, git branch with dirty / ahead / behind counts, Python venv, Node
  version, as powerline segments in a Nerd Font.
- **Matched themes** - seven to start. Switching one moves the window background, the 16 ANSI
  colours, the prompt and the status line together, so they never clash.
- **A catalogue you click** - every prompt design rendered against the same repository, with
  filters, a full-size preview, and brightness / saturation sliders. Press **Apply** and your
  terminal changes, with nothing to copy or paste.
- **Automatic recolouring** - oh-my-posh ships ~120 designs, each with colours of its own.
  Pick any and it is remapped onto your palette, then checked so no segment's text lands on
  its own background and vanishes.
- **A Claude Code status line** - model, folder, git state, context-usage bar, session cost,
  elapsed time, lines changed, and your rate-limit window. It reads the active palette on
  every refresh.
- **600+ more schemes**, one command each, and the catalogue refreshes itself when you add one.

## Using it

| | |
|---|---|
| `tts` | The theme menu, with a colour swatch per row |
| `tt <name>` \| `tt 3` | Switch theme and prompt together. Takes a name, number, or unique prefix |
| `catalogue` | Open the catalogue |
| `Find-TerminalTheme rose` | Search the 600+ installable schemes |
| `Install-TerminalTheme 'Rose Pine'` | Fetch one, wire it in, build its prompt palette |
| `Set-PoshTheme <name>` | Change only the prompt design |
| `/terminal-theme` | All of it from inside Claude Code, with a numbered menu |
| `Update-Cyc` | Install a newer build, keeping everything you set up |

## Updating

It keeps itself current, three ways:

- **A new terminal** checks once a day, in an interactive console only, one window at a time.
- **Opening the catalogue** checks first and installs before opening, so what opens is current.
- **Check for updates** in the catalogue's header asks on demand, in a console window.

Each is one line: a bar that fills while the request is in flight, erased when it answers,
leaving a single sentence - your version when current, what it installed when not, or why it
could not ask.

**An update takes nothing away.** Your theme, prompt design, colour adjustments, the themes
you installed and your own edits to the prompt config are kept - only the program is replaced.
If you edited `cyc.omp.json`, yours stays and the new one lands beside it as `.new`. The one
exception is a prompt design the new build no longer has: it falls back to the default **and
says so**. All of that is asserted by the test suite, and each assertion was checked to fail
when the preserving is removed.

Versions are odometer digits, not semver: each component runs 0-9 and carries into the one
above, so 1.3.9 becomes 1.4.0.

To stop the daily check: `New-Item ~/.oh-my-posh/no-auto-update -ItemType File`. The button
and `Update-Cyc` still work.

<details>
<summary>Installed before 1.1.0? One manual run, once</summary>

Updating arrived in 1.1.0, so an older install has nothing on it that knows to look - it
cannot pull a feature it does not have. Re-run the installer once with `-Update` and it is on
the train for good:

```powershell
irm https://raw.githubusercontent.com/pbayzelfium/CYC/main/install.ps1 -OutFile "$env:TEMP\cyc-install.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "$env:TEMP\cyc-install.ps1" -Update
```

`-Update`, not `-Force`: it keeps your theme, prompt design and installed themes. Then close
every terminal window and open a new one.

</details>

## Requirements

**Windows 10 or 11. That is the whole list.** The installer brings the rest itself - you
should not have to fetch anything first.

<details>
<summary>What it installs, and why</summary>

| It installs | Why |
|-------------|-----|
| PowerShell 7 | Start it from Windows PowerShell 5.1 and it installs 7 and **restarts itself there** |
| Windows Terminal | Nothing to theme without it |
| JetBrainsMono Nerd Font | The prompt's icons. Falls back to a per-user install if winget is unavailable, needing no admin |
| oh-my-posh + ~120 designs | The prompt itself |
| Terminal-Icons | File and folder glyphs in `ls` |
| git | The prompt's git segment stays empty without it |
| Python + fonttools | **Not optional.** Recolouring runs `pair-prompt.py` at the moment you switch, so without Python that feature is dead, not degraded |

It also registers a `cyc://` link handler under `HKCU`, which is what lets the catalogue's
**Apply** button reach your terminal. No admin needed, and uninstall removes it.

It prefers `winget` and falls back to direct downloads. Anything it genuinely cannot install
is reported at the end, naming what is missing and what that costs you.

</details>

## It tries not to break what you have

Every file it overwrites leaves a `.bak` beside it. Windows Terminal settings and
`~/.claude/settings.json` are **merged**, so your own colour schemes, terminal profiles,
keybindings and Claude settings survive. Your PowerShell profile gets a **marked block**
appended, so an existing profile is kept and a re-run replaces only that block.

Those are not claims - they are what `test-install.ps1` asserts.

## Removing it

```powershell
pwsh -NoProfile -File ~/.oh-my-posh/uninstall.ps1 -DryRun   # see what would go
pwsh -NoProfile -File ~/.oh-my-posh/uninstall.ps1
```

Takes out only what it put in: its profile block, its colour schemes and appearance keys, its
`statusLine` entry, the `cyc://` registration, and its own files. Your schemes, terminal
profiles, keybindings and settings stay. `-RestoreBackup` rolls those files back to their
`.bak` copies instead; `-KeepDownloads` keeps the prompt designs.

It leaves PowerShell 7, Windows Terminal, git, Python, the font and Terminal-Icons alone -
they are general tools, and something else may now depend on them.

## Options

| Flag | Effect |
|------|--------|
| `-DryRun` | Print every step and change nothing |
| `-Update` | Install a newer build over this one, keeping everything you set up. What `Update-Cyc` uses |
| `-Force` | Re-run over an existing install. Replaces the prompt config, so prefer `-Update` |
| `-NoOpen` | Do not open the catalogue when it finishes |
| `-SkipCatalogue` | Leave out the catalogue's build scripts. The catalogue itself installs either way |
| `-ResetTerminalSettings` | Only if your Windows Terminal settings file is already invalid: moves it aside, keeping a copy |
| `-Source <dir>` | Install from a local copy of `src/` instead of fetching from GitHub |
| `-TestRoot <dir>` | Install into a throwaway directory; used by the test suite |

<details>
<summary>Working on CYC itself</summary>

```
install.ps1            the installer: fetches src/ and configures everything
install-template.ps1   its source, before the file manifest is substituted
build-installer.py     reads the live files and emits install.ps1 + src/
VERSION                the published version, and what the update check compares against
bump-version.py        bumps it, carrying at 9: 1.3.9 becomes 1.4.0
uninstall.ps1          removes what the installer added
test-install.ps1       the assertions
src/                   everything the installer writes, as plain files
test/                  clean-machine testing: Sandbox, a second user account
```

`install.ps1` and `src/` are generated from the live files by one script, so they cannot
disagree. After changing anything:

```powershell
python build-installer.py
```

It strips personal folder shortcuts out of the prompt config, refuses to build if a palette
names a colour scheme Windows Terminal does not have, and refuses if the catalogue still
contains a username, computer name or home path - the previews are rendered from a live
machine, so that guard stands between a rebuild and publishing someone's details.

**Testing.** `pwsh -NoProfile -File test-install.ps1` installs into a temp directory
pre-seeded with someone else's profile, colour scheme, terminal profile, keybinding and
Claude settings; checks all of it survived; then re-installs, updates and uninstalls,
asserting both that CYC's traces are gone and that their work is still there.

CI runs on a clean `windows-latest` runner on every push: parses every script, refuses
anything base64-encoded or piped into `iex`, checks each manifest entry exists, runs the
suite, then does a **real install from nothing** including the downloads - rendering every
generated prompt, verifying a recoloured design uses only palette colours, and confirming the
`cyc://` handler refuses path traversal, injected commands, out-of-range numbers, unknown
themes and foreign URL schemes.

What CI cannot reach - Windows Terminal, a browser, a person clicking - was covered by hand
on a clean Windows profile. See [test/README.md](test/README.md) for what was run, what it
found, and what is still unproven.

**The catalogue** ships pre-built. Rebuilding is only needed if you edit the page itself;
installing a theme refreshes it automatically:
`pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1`. The previews embed a subsetted
Nerd Font, so glyphs render on a machine that has never installed it.

</details>

## Credit

Built on [oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) by Jan De Dobbeleer, the
[Nerd Fonts](https://www.nerdfonts.com/) project, and the colour schemes collected in
[mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).
JetBrains Mono is under the SIL Open Font License 1.1; the Nerd Fonts patcher is MIT.
