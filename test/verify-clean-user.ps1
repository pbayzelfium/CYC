<#
.SYNOPSIS
  Step 2 of the clean-user test. Run this AS THE TEST USER, after the installer,
  in a freshly opened Windows Terminal.

.DESCRIPTION
  Checks the things only a real account with Windows Terminal can check — the
  parts CI and Windows Sandbox cannot reach because neither has Windows
  Terminal or winget.

  The last two checks are yours to make by eye: a script cannot see whether the
  glyphs render or the background actually changed.
#>
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $warn = 0

function Check {
    param([string]$What, [scriptblock]$Test, [switch]$Warning)
    $ok = $false
    try { $ok = [bool](& $Test) } catch { }
    if ($ok)          { Write-Host "  PASS  $What" -ForegroundColor Green; $script:pass++ }
    elseif ($Warning) { Write-Host "  WARN  $What" -ForegroundColor Yellow; $script:warn++ }
    else              { Write-Host "  FAIL  $What" -ForegroundColor Red;   $script:fail++ }
}

Write-Host ""
Write-Host "  Clean-user verification  (running as $env:USERNAME)" -ForegroundColor White
Write-Host ""

if ($env:USERNAME -eq 'pc') {
    Write-Host "  You are signed in as yourself, not the test account." -ForegroundColor Red
    Write-Host "  This must run as the test user, or it proves nothing." -ForegroundColor Red
    Write-Host ""
    exit 1
}

# --- the install itself -----------------------------------------------------
Write-Host "  Files" -ForegroundColor DarkGray
Check "oh-my-posh downloaded"   { Test-Path "$HOME\.local\bin\oh-my-posh.exe" }
Check "design collection"       { @(Get-ChildItem "$HOME\.oh-my-posh\themes" -Filter *.omp.json -EA SilentlyContinue).Count -gt 50 }
Check "prompt variants"         { @(Get-ChildItem "$HOME\.oh-my-posh" -Filter 'zelfium-*.omp.json' -EA SilentlyContinue).Count -ge 7 }
Check "Claude status line"      { Test-Path "$HOME\.claude\statusline.ps1" }
Check "slash command"           { Test-Path "$HOME\.claude\commands\terminal-theme.md" }
Check "profile written"         { Test-Path $PROFILE }

# --- Windows Terminal: the part nothing else tests --------------------------
Write-Host ""
Write-Host "  Windows Terminal  (only this test reaches it)" -ForegroundColor DarkGray
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
Check "settings file exists"    { Test-Path $wt }

if (Test-Path $wt) {
    $j = $null
    Check "settings still parse as JSON" { $script:j = Get-Content $wt -Raw | ConvertFrom-Json; $true }
    if ($j) {
        Check "font set to JetBrainsMono NF" { $j.profiles.defaults.font.face -eq 'JetBrainsMono NF' }
        Check "colour schemes added"         { $j.schemes.name -contains 'Catppuccin Mocha' }
        Check "all 7 schemes present" {
            $want = (Get-Content "$HOME\.oh-my-posh\palettes.json" -Raw | ConvertFrom-Json).PSObject.Properties |
                    Where-Object { $_.Name -notlike '_*' } | ForEach-Object { $_.Value.scheme }
            @($want | Where-Object { $j.schemes.name -notcontains $_ }).Count -eq 0 }
        Check "no duplicated schemes" {
            ($j.schemes.name | Group-Object | Where-Object Count -gt 1).Count -eq 0 }
        Check "default profile is PowerShell 7" {
            $p = $j.profiles.list | Where-Object { $_.guid -eq $j.defaultProfile }
            $p.source -eq 'Windows.Terminal.PowershellCore' } -Warning
        Check "a backup was left"            { Test-Path "$wt.bak" }
    }
}

# --- the font ---------------------------------------------------------------
Write-Host ""
Write-Host "  Font" -ForegroundColor DarkGray
Check "Nerd Font installed" {
    (Test-Path (Join-Path $env:WINDIR 'Fonts\JetBrainsMonoNerdFont-Regular.ttf')) -or
    (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\JetBrainsMonoNerdFont-Regular.ttf')) } -Warning

# --- does the thing actually work -------------------------------------------
Write-Host ""
Write-Host "  Behaviour" -ForegroundColor DarkGray

# This script is meant to be run with -NoProfile, so the profile's commands are
# deliberately absent HERE. Ask a child shell that does load the profile, which
# is what a real terminal window will be.
$probe = & pwsh -NoLogo -Command @'
$r = [ordered]@{
  profile = [bool](Get-Command Set-TerminalTheme -EA SilentlyContinue)
  menu    = [bool](Get-Command Show-TerminalThemes -EA SilentlyContinue)
  install = [bool](Get-Command Install-TerminalTheme -EA SilentlyContinue)
  switch  = $false
}
if ($r.profile) {
  try {
    Set-TerminalTheme gruvbox-dark | Out-Null
    $was = (Get-TerminalTheme).Scheme
    Set-TerminalTheme catppuccin-mocha | Out-Null
    $r.switch = ($was -eq 'Gruvbox Dark')
  } catch { }
}
[pscustomobject]$r | ConvertTo-Json -Compress
'@ 2>$null

$p = $null
try { $p = ($probe | Select-Object -Last 1) | ConvertFrom-Json } catch { }

if (-not $p) {
    Write-Host "  FAIL  could not start a profile-loading shell" -ForegroundColor Red
    $fail++
} else {
    Check "profile loads in a new shell" { $p.profile }.GetNewClosure()
    Check "theme menu available"         { $p.menu }.GetNewClosure()
    Check "installer command available"  { $p.install }.GetNewClosure()
    Check "switching theme works"        { $p.switch }.GetNewClosure()
}

$omp = "$HOME\.local\bin\oh-my-posh.exe"
if (Test-Path $omp) {
    Check "every generated prompt renders" {
        $bad = 0
        foreach ($c in Get-ChildItem "$HOME\.oh-my-posh" -Filter 'zelfium-*.omp.json') {
            if (-not (& $omp print primary --config $c.FullName --shell pwsh --plain)) { $bad++ }
        }
        $bad -eq 0 }
}

# --- summary ----------------------------------------------------------------
Write-Host ""
Write-Host "  $pass passed, $fail failed, $warn warnings" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
Write-Host ""
Write-Host "  Two things a script cannot check - look at the screen:" -ForegroundColor White
Write-Host "    1. Does the prompt show ICONS, not boxes?"
Write-Host "       Boxes mean the font is not applied yet. A reboot usually fixes it,"
Write-Host "       and that is worth knowing before telling anyone else to install this."
Write-Host "    2. Run  tts  then  tt 5  - does the WINDOW BACKGROUND change colour?"
Write-Host "       If it only changes in a new tab, say so; the README claims it repaints live."
Write-Host ""
if ($fail) { exit 1 }
