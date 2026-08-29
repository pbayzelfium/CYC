---
name: terminal-theme
description: "Change the terminal colour scheme and/or the prompt design from inside Claude Code. No argument shows what is active and what is available."
argument-hint: "[<paired-theme> | prompt <name> | list [filter]]"
allowed-tools: Bash(pwsh:*), Read
---

# /terminal-theme — repaint the terminal without leaving the session

The analogue of `/theme` (which changes Claude Code's own colours). This one changes the
**terminal underneath**.

Argument given: `$ARGUMENTS`

## Two layers, and they are not the same thing

Peter has asked about this more than once, so lead with it whenever it is relevant.

| Layer | What it controls | How many | Command |
|-------|------------------|----------|---------|
| **Paired theme** | Window background, the 16 ANSI colours, the prompt, and this status line — moved together so nothing clashes | the keys in `palettes.json` | `/terminal-theme <slug>` |
| **Prompt design** | The prompt line only: which segments appear, powerline vs diamond vs plain, icons, layout | the files in `themes/` | `/terminal-theme prompt <name>` |

Never state either count from memory — Peter installs themes, so any number written here goes
stale. Count them when you report.

**Every design is recoloured to the active theme automatically.** Picking a design remaps its
colours onto the theme's palette and writes `~/.oh-my-posh/paired/<design>@<slug>.omp.json`;
switching themes re-pairs whatever design is in use, so the two can no longer clash. The base
design is remembered in `~/.oh-my-posh/active-design.txt`.

The honest caveat, worth stating when it matters: recolouring **collapses** a design's palette
onto the theme's smaller one — night-owl uses 57 distinct colours and comes out with 10. A
design that leans on a shade the theme has no equivalent for loses that distinction.
`Set-PoshTheme <name> -Original` keeps the author's colours instead. The catalogue previews are
recoloured to match, with a toggle back to the author's colours; when that toggle is off it
emits `/terminal-theme prompt <name> original`.

A second pass then repairs any segment whose text mapped onto its own background colour — a
per-colour mapping cannot see that, because it is a property of the pair. If a paired prompt
ever shows a segment with missing text, that pass is the thing to look at, in both
`pair-prompt.py` and the catalogue's `fixContrast`.

## Ground truth — read it, do not recall it

| What | Where |
|------|-------|
| Paired palettes (single source of truth) | `~/.oh-my-posh/palettes.json` |
| The prompt designs | `~/.oh-my-posh/themes/*.omp.json` |
| Active prompt (may be a paired file) | `~/.oh-my-posh/active-theme.txt` |
| The design it was made from | `~/.oh-my-posh/active-design.txt` |
| Recoloured prompts | `~/.oh-my-posh/paired/<design>@<slug>.omp.json` |
| Status line (reads the palette) | `~/.claude/statusline.ps1` |
| Terminal scheme | `profiles.defaults.colorScheme` in Windows Terminal's `settings.json` |

`Set-TerminalTheme` and `Set-PoshTheme` in the PowerShell 7 profile do the work. **Never
hand-edit those files to change a theme** — call the functions, so all the pieces stay in step.

## Routing the argument

**Empty** — show the numbered menu and stop. Change nothing.

```
pwsh -NoLogo -Command "Show-TerminalThemes"
```

Present it as a numbered list with the active one marked, and end by telling him he can
**just reply with a number**. Do not make him type a theme name — that was the complaint that
produced this menu. Also mention, in one line, how many prompt designs exist (count them) and
that they are searchable with `/terminal-theme list <text>`. Do not dump them all unasked.

### Never draw a swatch in chat

`Show-TerminalThemes` prints a real colour swatch per row, but **colour does not survive into a
chat reply**. Anything you draw here is monochrome.

So: **never reproduce the swatch in the reply.** Not as escape sequences, and not as block
characters (`█`, `▐`, `▌`) either — unfilled, they render as one solid grey slab that looks
broken. This was tried and it looked worse than no swatch at all. Emoji squares are no better:
the emoji palette is too coarse to separate these six, so they would all look alike, which is
misleading rather than merely useless.

Carry the colour as **information** instead — background hex plus a few words of character:

> `3. kanagawa-wave` — `#1f1f28` muted indigo ground, sand text, violet and olive accents, one hard red

The true swatch is what `tts` prints in a shell; every theme is also rendered visually on the
Terminal Control Room artifact. Point at those rather than imitating them.

When his next message is a bare number, treat it as a pick from the menu you just printed and
apply it. Do not ask him to confirm.

**A bare number as the argument** (`/terminal-theme 4`) — pass it straight through; the
function resolves numbers itself.

**`list`** or **`list <filter>`** — search the prompt designs:

```
pwsh -NoLogo -Command "Get-PoshThemeList | Where-Object { $_ -like '*<filter>*' }"
```

**Number the results** and say he can reply with a number. Hold the mapping so a bare-number
reply applies the right one via `Set-PoshTheme <name>` — the function itself only takes names,
so you do the number-to-name step. With no filter the list is long; print it in columns.

**`prompt <name>`** — switch the prompt design, leaving the window colours alone:

```
pwsh -NoLogo -Command "Set-PoshTheme <name>"
```

It is recoloured to the active theme automatically. Two suffixes the catalogue may append,
which map to parameters rather than being part of the name:

| Suffix from the catalogue | Pass instead |
|---------------------------|--------------|
| `original` | `-Original` — keep the author's colours, no recolouring |
| `--brightness N` | `-Brightness N` — shift every colour's lightness by N percent |
| `--saturation N` | `-Saturation N` — scale saturation by N percent |

```
pwsh -NoLogo -Command "Set-PoshTheme night-owl -Brightness -25 -Saturation -15"
pwsh -NoLogo -Command "Set-PoshTheme <name> -Original"
```

The tweak is remembered in `~/.oh-my-posh/active-adjust.txt` and reapplied when the theme
changes, so it does not have to be repeated. `Set-PoshTheme <name>` with no adjustment
parameters **resets it to zero** — that is deliberate, so a plain command is predictable, but
say so if he seems to expect it to stick.

The catalogue previews the same two numbers with the identical formula, so what it shows is
what the shell produces. Verified by comparison, not assumed — if the two ever disagree, one
of `adjust()` in `pair-prompt.py` or `adjustColour()` in the catalogue template was changed
without the other.

Say the window background did not change; do not offer to "pair it" — that now happens by
itself.

**Anything else** — treat it as a paired theme and pass it through:

```
pwsh -NoLogo -Command "Set-TerminalTheme <what he typed>"
```

The function resolves an exact name, a number, or a unique prefix (`kana` → `kanagawa-wave`),
and prints the menu itself if it cannot. Say which name it resolved to, then read back
`Get-TerminalTheme` to confirm.

**Name collisions** — `dracula` is both a paired slug and a stock prompt design, and
`catppuccin_mocha` (stock, underscore) is a different thing from `catppuccin-mocha` (paired,
hyphen). A bare name always means the **paired** theme; `prompt <name>` always means the
stock design. If his wording is genuinely ambiguous, ask rather than guess.

## What actually changes when

Be accurate here — this is the part that looks broken if described wrong.

- **Window background and ANSI colours** — Windows Terminal hot-reloads its settings, so the
  open window should repaint on its own. If it does not, a new tab will.
- **This session's status line** — repaints on its next update, within a few seconds. It reads
  the palette on every run, so nothing needs restarting. Only paired themes move it.
- **The prompt** — persisted immediately, but he is inside Claude Code and has no shell prompt
  on screen. He sees it on exit, or in any other terminal window.

Do not claim you have seen the window change colour. You cannot see his screen — say what was
set and let him confirm.

## Installing a new theme

**One command.** It fetches the canonical scheme, adds it to Windows Terminal, derives a
matching prompt palette from the scheme's own 16 colours, and generates the prompt variant:

```
pwsh -NoLogo -Command "Install-TerminalTheme 'Rose Pine'"
```

Find the exact name first — the collection has 606 schemes and the name must match exactly:

```
pwsh -NoLogo -Command "Find-TerminalTheme rose"
```

`Uninstall-TerminalTheme <slug>` removes a theme's palette and prompt variant again.

The installer picks segment ink by worst-case contrast across the accents and **warns** when
a scheme's own colours cap readability (Rose Pine's very dark green lands at 3.8:1). That note
is information, not a failure — do not treat it as an error or try to "fix" the scheme.

These live in `~/.oh-my-posh/theme-tools.ps1`, dot-sourced by the profile. Doing it by hand
is only for a scheme that is not in the collection: add it to `schemes[]` in Windows Terminal's
`settings.json`, add a palette under the same slug to `palettes.json` with a matching `scheme`
field, then run `~/.oh-my-posh/build-variants.ps1`.

Nothing else to touch in the shell. `Set-TerminalTheme`, its tab-completion, the menu swatch
and the status line all read `palettes.json` at call time, so the new slug works as soon as
the file has it. Its filter tags on the catalogue are computed from the palette too — nothing
to tag by hand.

To refresh the **Theme Catalogue** artifact so the new theme appears there:

```
pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1
```

That re-renders every design against a fixed preview repo it creates itself, and writes
`~/.oh-my-posh/catalogue/theme-catalogue.html`. Publish that file to the existing artifact
URL (`https://claude.ai/code/artifact/9729284e-e068-49b6-b20c-67507b082a48`) rather than a new
one, so his link keeps working. A rebuild is reproducible except for clock values inside
prompts that display the time — that difference is expected, not a defect.
