<#
.SYNOPSIS
  Step 1 of the clean-user test. Creates a throwaway local account and stages
  the installer where it can reach it. Run this ELEVATED, as yourself.

.DESCRIPTION
  A new local user on this machine has Windows Terminal and winget, but a
  completely fresh profile, PATH, fonts and settings. That is the only setup
  which exercises the Windows Terminal settings merge — the step most likely to
  damage something a real person already has, and the one neither CI nor
  Windows Sandbox can reach.

  This only creates the account and copies files. Nothing is installed here.

.PARAMETER User
  Account name. Default Testing.

.PARAMETER Remove
  Delete the account and its profile instead. Run this when you are finished.

.EXAMPLE
  # elevated
  pwsh -File new-user-setup.ps1
  pwsh -File new-user-setup.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$User = 'Testing',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$stage = "C:\Users\Public\CYC"

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this elevated: right-click Windows Terminal > Run as administrator."
    }
}
Assert-Admin

# --- teardown ---------------------------------------------------------------
if ($Remove) {
    Write-Host ""
    if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $User
        Write-Host "  removed account $User" -ForegroundColor Green
    } else { Write-Host "  no account called $User" -ForegroundColor DarkGray }

    $prof = "C:\Users\$User"
    if (Test-Path $prof) {
        try {
            Remove-Item $prof -Recurse -Force -ErrorAction Stop
            Write-Host "  removed profile $prof" -ForegroundColor Green
        } catch {
            Write-Host "  could not delete $prof - sign that account out first, then re-run." -ForegroundColor Yellow
        }
    }
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force; Write-Host "  removed $stage" -ForegroundColor Green }
    Write-Host ""
    return
}

# --- create -----------------------------------------------------------------
Write-Host ""
Write-Host "  Clean-user test - setup" -ForegroundColor White
Write-Host ""

$Password = "CycTest!2024"
if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
    Write-Host "  account $User already exists - reusing it" -ForegroundColor DarkGray
    Write-Host "  (for a truly clean run: -Remove first, then re-run this)" -ForegroundColor DarkGray
    # Reset it, and always print it. A half-finished earlier run can leave an
    # account whose password was set but never shown, which looks from the
    # lock screen like no password was ever set.
    Set-LocalUser -Name $User -Password (ConvertTo-SecureString $Password -AsPlainText -Force)
    Write-Host "  password reset to:     $Password" -ForegroundColor Green
} else {
    # A password, not -NoPassword: some policies refuse to let a passwordless
    # local account sign in, which turns into a confusing dead end at the
    # lock screen.
    $pw = ConvertTo-SecureString 'CycTest!2024' -AsPlainText -Force
    New-LocalUser -Name $User -Password $pw -AccountNeverExpires -PasswordNeverExpires `
        -FullName 'CYC clean test' -Description 'Throwaway account for testing CYC' | Out-Null
    Write-Host "  created local account: $User" -ForegroundColor Green
    Write-Host "  password:              CycTest!2024" -ForegroundColor Green
}

# Group membership, every run - New-LocalUser joins no group, and a user in no
# group cannot sign in properly. By SID, not name: the built-in group is
# "Usuarios" on Spanish Windows, "Benutzer" on German, and so on.
$usersGroup = Get-LocalGroup -SID 'S-1-5-32-545'
$already = Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like "*\$User" }
if ($already) {
    Write-Host "  already in $($usersGroup.Name)" -ForegroundColor DarkGray
} else {
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $User
    Write-Host "  added to group:        $($usersGroup.Name)" -ForegroundColor Green
}

# --- stage the installer somewhere the other account can read ---------------
$repo = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($f in 'install.ps1', 'test-install.ps1') {
    Copy-Item (Join-Path $repo $f) $stage -Force
}
Copy-Item (Join-Path $PSScriptRoot 'verify-clean-user.ps1') $stage -Force
# The walkthrough has to live where the TEST account can read it: once you have
# switched users you can no longer see the window you launched this from.
$howto = @"
CYC - clean user test
=====================
You are signed in as $User. This is a throwaway account; nothing here matters.

The point of this test: a brand new Windows profile is the only place where the
installer's Windows Terminal step actually runs. Neither CI nor Windows Sandbox
has Windows Terminal, so the settings merge - the step most likely to damage
something a real person already has - is untested anywhere else.

STEP 0  Check PowerShell 7 is here. In any terminal, run:

            pwsh -v

        If that says it is not recognised, this account has no PowerShell 7 and
        nothing below will run. The Microsoft Store build is installed PER USER,
        so it does not carry over from another account. Install the machine-wide
        build once, from an ADMIN window in the OWNING account:

            winget install --id Microsoft.PowerShell --scope machine

        Then sign out of this account and back in, and try 'pwsh -v' again.

STEP 1  Open Windows Terminal from the Start menu, then CLOSE it again.
        This is not busywork. Windows Terminal only writes its settings.json the
        first time it runs. Skipping this would test "create a config from
        nothing" instead of "merge into a config that already exists", which is
        the case that can destroy someone's setup.

STEP 2  Open Windows Terminal again and run:

            pwsh -NoProfile -File C:\Users\Public\CYC\install.ps1

        Expect it to install a font (accept the elevation prompt), download
        oh-my-posh and ~120 prompt designs, and finish in a minute or two.
        Warnings are printed at the end - note any of them.

STEP 3  Close EVERY Windows Terminal window. Open a new one.
        The font and the new default profile only apply to a fresh window.

STEP 4  Run:

            pwsh -NoProfile -File C:\Users\Public\CYC\verify-clean-user.ps1

        It checks the Windows Terminal side: settings still parse, the font
        applied, all schemes present and none duplicated, a .bak was left, the
        profile loads, and switching themes works.

STEP 5  Look at the screen. Two things no script can check:

        a) Does the prompt show ICONS, or BOXES?
           Boxes mean the font is not visible to Windows Terminal yet. That
           usually needs a reboot - and if so, everyone else installing this
           will hit the same thing, which is worth knowing before sharing it.

        b) Run  tts  then  tt 5 .
           Does the WINDOW BACKGROUND change straight away, or only in a new
           tab? The docs claim it repaints live. That has never been verified
           on a fresh machine, so whatever you see is the answer.

STEP 6  Note anything that failed or looked wrong, then sign OUT of $User
        (Start > avatar > Sign out). Signing out of this throwaway account is
        fine and is required before its folder can be deleted.

        Back in your own session, run elevated:

            pwsh -File "$PSCommandPath" -Remove

Things worth reporting either way: any FAIL or WARN lines, whether icons
rendered, and whether the background repainted live or needed a new tab.
"@
Set-Content (Join-Path $stage 'INSTRUCTIONS.txt') $howto -Encoding UTF8

# readable by everyone, since C:\Users\Public inherits oddly on some machines.
# *SID form, again because the group name is localised.
icacls $stage /grant "*S-1-5-32-545:(OI)(CI)RX" /T | Out-Null
Write-Host "  staged installer at:   $stage" -ForegroundColor Green
Write-Host "  walkthrough for the test account: $stage\INSTRUCTIONS.txt" -ForegroundColor Green

Write-Host ""
Write-Host "  Next, in order:" -ForegroundColor White
Write-Host "    1. SWITCH USER - do not sign out." -ForegroundColor Yellow
Write-Host "       Start > your avatar > $User,  or  Ctrl+Alt+Del > Switch user."
Write-Host "       Switching keeps your own session running in the background, so"
Write-Host "       anything you have open - editors, terminals, a Claude Code session -"
Write-Host "       is still there when you switch back. Signing out closes all of it."
Write-Host "    2. Sign in as  $User  with  CycTest!2024"
Write-Host "       First sign-in takes a minute or two while Windows sets the profile up."
Write-Host "    3. Open Windows Terminal once from Start, then close it."
Write-Host "       This makes it write its default settings.json - the file the installer merges into."
Write-Host "    4. Open Windows Terminal again and run:"
Write-Host ""
Write-Host "         pwsh -NoProfile -File C:\Users\Public\CYC\install.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "    5. Close every Windows Terminal window, open a new one, and run:"
Write-Host ""
Write-Host "         pwsh -NoProfile -File C:\Users\Public\CYC\verify-clean-user.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "    6. Look at the terminal with your own eyes: coloured prompt, icons not boxes."
Write-Host "       Try  tts  and  tt 3  and confirm the window background changes."
Write-Host "    7. Sign OUT of $User (that one is safe - it is the throwaway account),"
Write-Host "       switch back to yourself, then run this elevated:"
Write-Host ""
Write-Host "         pwsh -File `"$PSCommandPath`" -Remove" -ForegroundColor Cyan
Write-Host ""


