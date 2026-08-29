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

if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
    Write-Host "  account $User already exists - reusing it" -ForegroundColor DarkGray
    Write-Host "  (for a truly clean run: -Remove first, then re-run this)" -ForegroundColor DarkGray
} else {
    # A password, not -NoPassword: some policies refuse to let a passwordless
    # local account sign in, which turns into a confusing dead end at the
    # lock screen.
    $pw = ConvertTo-SecureString 'CycTest!2024' -AsPlainText -Force
    New-LocalUser -Name $User -Password $pw -AccountNeverExpires -PasswordNeverExpires `
        -FullName 'CYC clean test' -Description 'Throwaway account for testing CYC' | Out-Null
    Add-LocalGroupMember -Group 'Users' -Member $User
    Write-Host "  created local account: $User" -ForegroundColor Green
    Write-Host "  password:              CycTest!2024" -ForegroundColor Green
}

# --- stage the installer somewhere the other account can read ---------------
$repo = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($f in 'install.ps1', 'test-install.ps1') {
    Copy-Item (Join-Path $repo $f) $stage -Force
}
Copy-Item (Join-Path $PSScriptRoot 'verify-clean-user.ps1') $stage -Force
# readable by everyone, since C:\Users\Public inherits oddly on some machines
icacls $stage /grant "Users:(OI)(CI)RX" /T | Out-Null
Write-Host "  staged installer at:   $stage" -ForegroundColor Green

Write-Host ""
Write-Host "  Next, in order:" -ForegroundColor White
Write-Host "    1. Sign out (or Win+L, then switch user). Do NOT delete your session."
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
Write-Host "    7. Sign out of $User, sign back in as yourself, then run this elevated:"
Write-Host ""
Write-Host "         pwsh -File `"$PSCommandPath`" -Remove" -ForegroundColor Cyan
Write-Host ""

