# Testing

Four ways to check this, from cheapest to most thorough. They cover different
things — the last two are the ones that reach Windows Terminal.

## 1. The suite — seconds, no VM

```powershell
pwsh -NoProfile -File test-install.ps1
```

Installs into a temp directory pre-seeded with someone else's profile, colour scheme, terminal
profile, keybinding and Claude settings, then asserts all of it survived and everything landed.
25 assertions. Run this after any change.

**Does not cover:** the downloads, the font, Windows Terminal, or a first-time machine.

## 2. CI — a clean `windows-latest` runner, free

`.github/workflows/test.yml` runs the suite plus a **real install from nothing**, including the
downloads, then renders every generated prompt and checks a recoloured design uses only palette
colours.

**Does not cover:** Windows Terminal or the font — the runner has neither Windows Terminal nor
winget, so those steps warn and skip.

## 3. Windows Sandbox — a clean Windows in ~30 seconds

Enable it once, elevated, then reboot:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
```

Then double-click `sandbox.wsb`. It maps this folder in read-only, installs PowerShell 7 from
nothing, runs the dry run, the suite and a real install, verifies the prompt renders and that a
new shell picks up the profile, and copies the log to `test/results/sandbox-log.txt` so it
survives the sandbox closing.

**Does not cover:** Windows Terminal or the font. Sandbox has neither Windows Terminal nor
winget — the same blind spot as CI, for the same reason. It is a genuinely clean machine, so it
catches anything that assumes PowerShell 7, a profile, or a pre-existing folder.

## 4. A second local user account — the only one that reaches Windows Terminal

The gap the first three share is that **the Windows Terminal settings merge is never executed**.
That is the step most likely to damage something, because it edits a file someone already has.

A new local user on this machine has Windows Terminal (provisioned for every user on Windows 11)
and winget, but a completely fresh profile, PATH, fonts and settings — which is exactly a
first-time user.

Two scripts do it. **Elevated, as yourself:**

```powershell
pwsh -File test\new-user-setup.ps1
```

It creates the account (with a password — some policies refuse to let a passwordless local
account sign in, which turns into a confusing dead end at the lock screen), stages the installer
in `C:\Users\Public\CYC` where the other account can read it, and prints the remaining steps.

Then sign in as the test user, open Windows Terminal once so it writes its default settings,
run the installer, reopen the terminal, and:

```powershell
pwsh -NoProfile -File C:\Users\Public\CYC\verify-clean-user.ps1
```

That checks the Windows Terminal side specifically: the settings still parse, the font applied,
all schemes are present and none duplicated, a `.bak` was left, the profile loads in a new shell,
and switching themes actually works. It refuses to run as your own account, since that would
prove nothing.

Two things it cannot check, and asks you to look at instead: whether the prompt shows **icons
rather than boxes** (boxes mean the font is not visible yet — usually a reboot, and worth knowing
before telling anyone else to install this), and whether the **window background repaints live**
or only in a new tab. The README claims live; that claim has never been verified on a fresh
machine.

Tear down afterwards, elevated, once signed back in as yourself:

```powershell
pwsh -File test\new-user-setup.ps1 -Remove
```

**This is the one worth doing before sharing the link widely.** The rest run automatically; this
one needs ten minutes and a sign-out.

## Results so far

Four rounds on a clean Windows 11 Pro (Spanish) profile, plus CI on every push.

**Round 4** - the parts only a person on a real install can exercise: the installer registering
the `cyc://` handler, the catalogue opening by itself when the install finishes, and pressing
**Apply** in the browser to change the terminal with no copying. All confirmed working.

**Rounds 1-3** below.

The clean-user test (4) has been run once on Windows 11 Pro, Spanish: **20 checks, 0 failures**,
plus both eyeball checks. The font rendered immediately — **no reboot needed** — and `tt` repainted
the open window rather than requiring a new tab.

Three real bugs surfaced only because it was run on a fresh profile, all fixed:

- `Add-LocalGroupMember -Group 'Users'` fails on non-English Windows; the group is `Usuarios`
  there. Now addressed by SID.
- PowerShell 7 from the Microsoft Store installs **per user**, so it is invisible to a new
  account. The README now says `--scope machine`.
- The verifier checked for the profile's commands in a shell it had itself started with
  `-NoProfile`, reporting three failures against a working install.

## What is still untested anywhere

- Windows 10. Everything here assumes Windows 11 conventions.
- A machine with no winget at all — the installer warns and continues, but nobody has watched it.
- Whether the font needs a reboot on a machine where it was *not* already installed system-wide.
  On the test machine it was, so that path is still unproven.
