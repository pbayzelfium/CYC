# Third-party notices

CYC itself is MIT - see [`../LICENSE`](../LICENSE). This file covers what it
**redistributes** or installs, which is a shorter list than it looks, because most of what
CYC uses it fetches for you rather than carrying.

## Redistributed in this repository

**JetBrains Mono, subset** &mdash; SIL Open Font License 1.1
Copyright 2020 The JetBrains Mono Project Authors.
Full text: [`JetBrainsMono-OFL.txt`](JetBrainsMono-OFL.txt).

The catalogue embeds a 285-codepoint WOFF2 subset as a data URI, so the prompt glyphs render
for a reader who has never installed the font. The glyphs come from the Nerd Fonts patched
build of JetBrains Mono; the patcher is by Ryan L McIntyre and its own sources carry a mix of
licences, but the outlines here are JetBrains Mono's and OFL 1.1 is the licence that governs
them. The CSS calls the family `CatalogueMono` because it is a subset, not the whole face.

*What the OFL asks, and what is done about it:* the licence travels with the font (this
directory), the font is not sold on its own, and the subset is not passed off as the complete
JetBrains Mono.

**Colour scheme definitions** &mdash; MIT
Copyright (c) 2011 to Present Mark Badolato, from
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).
Full text: [`iTerm2-Color-Schemes-MIT.txt`](iTerm2-Color-Schemes-MIT.txt).

`schemes.json` ships seven scheme definitions taken from that collection, and
`Install-TerminalTheme` fetches any of the other 600 on request.

## Installed, not redistributed

Nothing below is in this repository. The installer fetches each from its own publisher, so
their licences apply where they land and not here.

| | |
|---|---|
| [oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh) | MIT, Jan De Dobbeleer. The prompt engine and its ~120 designs |
| [Nerd Fonts](https://www.nerdfonts.com/) | The patched JetBrainsMono NF installed onto the machine |
| PowerShell 7, Windows Terminal | Microsoft, MIT |
| [Terminal-Icons](https://github.com/devblackops/Terminal-Icons) | MIT |
| git, Python | their own licences |

## If you fork this

The MIT licence on CYC covers the code in this repository. Keep this directory with it: the
OFL requires its text to accompany the font wherever the font goes, and the catalogue carries
the font inside itself.
