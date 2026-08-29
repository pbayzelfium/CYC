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

```powershell
# elevated
New-LocalUser -Name cyctest -NoPassword -AccountNeverExpires
Add-LocalGroupMember -Group Users -Member cyctest
```

Sign in as `cyctest`, open Windows Terminal once so it writes its default settings, then run the
installer. Check: the font applies, the schemes appear in the dropdown, `tts` shows swatches,
and `tt 3` switches both window and prompt. Afterwards:

```powershell
Remove-LocalUser -Name cyctest
Remove-Item "C:\Users\cyctest" -Recurse -Force   # elevated
```

**This is the one worth doing before sharing the link widely.** The rest can run automatically;
this one needs ten minutes and a sign-out.

## What is still untested anywhere

- Whether a font winget has just installed is visible to Windows Terminal before a reboot.
  It usually is not, which is why the installer says so at the end.
- Windows 10. Everything here assumes Windows 11 conventions.
