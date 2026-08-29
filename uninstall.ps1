<#
.SYNOPSIS
  Removes CYC and puts back what it changed.

.DESCRIPTION
  Removes only what the installer added:

    - the marked block from your PowerShell profile, leaving the rest alone
    - the colour schemes it added to Windows Terminal, and the appearance keys
      it set, leaving your own schemes and profiles alone
    - the statusLine entry from ~/.claude/settings.json, leaving the rest
    - ~/.oh-my-posh (prompt, palettes, designs, catalogue)
    - ~/.claude/statusline.ps1 and the /terminal-theme command
    - oh-my-posh.exe, and the POSH_THEMES_PATH variable

  It does NOT remove PowerShell 7, Windows Terminal, git, Python, the Nerd Font
  or the Terminal-Icons module. Those are general tools you may want, and
  removing them could break something else you installed since.

.PARAMETER DryRun
  List what would be removed and change nothing.

.PARAMETER RestoreBackup
  Restore Windows Terminal settings, the profile and the Claude settings from
  the .bak files the installer left, instead of editing them surgically. Use
  this if you have not changed those files since installing; it is exact, but
  it also discards anything you changed after.

.PARAMETER KeepDownloads
  Leave ~/.oh-my-posh in place (prompt designs, catalogue) and only undo the
  configuration.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -NoProfile -File uninstall.ps1 -DryRun
  pwsh -NoProfile -File uninstall.ps1
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$DryRun,
    [switch]$RestoreBackup,
    [switch]$KeepDownloads,
    [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
$Root = if ($TestRoot) { $TestRoot } else { $HOME }
$ProfileFile = if ($TestRoot) { Join-Path $Root 'Documents\PowerShell\profile.ps1' } else { $PROFILE }
$removed = 0

function Say  { param($m, $c = 'Gray') Write-Host "  $m" -ForegroundColor $c }
function Step { param($m) Write-Host ""; Write-Host "> $m" -ForegroundColor Cyan }
function Did  { param($m) Say $m DarkGray; $script:removed++ }

Write-Host ""
Write-Host "  Removing CYC" -ForegroundColor White
Write-Host "  ============" -ForegroundColor DarkGray
if ($DryRun) { Say "DRY RUN - nothing will change" Yellow }

# --- 1. the PowerShell profile ---------------------------------------------
Step "PowerShell profile"
$marker = '# >>> terminal-theme setup >>>'
$endmk  = '# <<< terminal-theme setup <<<'

if (-not (Test-Path $ProfileFile)) { Say "no profile found" DarkGray }
else {
    $t = Get-Content $ProfileFile -Raw
    if ($t -notmatch [regex]::Escape($marker)) { Say "no CYC block in it" DarkGray }
    elseif ($DryRun) { Say "would remove the CYC block, keeping the rest" }
    elseif ($RestoreBackup -and (Test-Path "$ProfileFile.bak")) {
        Copy-Item "$ProfileFile.bak" $ProfileFile -Force
        Did "restored from .bak"
    } else {
        # Only between the markers: whatever else is in there is not ours.
        $pattern = "(?s)" + [regex]::Escape($marker) + ".*?" + [regex]::Escape($endmk) + "\r?\n?"
        [IO.File]::WriteAllText($ProfileFile, ([regex]::Replace($t, $pattern, '')).TrimEnd() + "`n")
        Did "removed the CYC block, kept everything else"
    }
}

# --- 2. Windows Terminal ----------------------------------------------------
Step "Windows Terminal"
$wt = if ($TestRoot) { Join-Path $Root 'wt-settings.json' }
      else { Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json' }

if (-not (Test-Path $wt)) { Say "not installed" DarkGray }
elseif ($DryRun) { Say "would remove the added schemes and reset the appearance" }
elseif ($RestoreBackup -and (Test-Path "$wt.bak")) {
    Copy-Item "$wt.bak" $wt -Force
    Did "restored from .bak"
} else {
    try {
        $mine = @()
        $sf = Join-Path $Root '.oh-my-posh\schemes.json'
        if (Test-Path $sf) { $mine = @((Get-Content $sf -Raw | ConvertFrom-Json).name) }

        $j = Get-Content $wt -Raw | ConvertFrom-Json
        if ($mine.Count) {
            $before = @($j.schemes).Count
            $j.schemes = @($j.schemes | Where-Object { $mine -notcontains $_.name })
            Did "removed $($before - @($j.schemes).Count) colour schemes"
        }
        # only the appearance keys the installer set
        foreach ($k in 'font','colorScheme','useAcrylic','opacity','padding',
                       'scrollbarState','historySize','cursorShape','antialiasingMode') {
            if ($j.profiles.defaults.PSObject.Properties.Name -contains $k) {
                $j.profiles.defaults.PSObject.Properties.Remove($k)
            }
        }
        Did "reset the appearance defaults"
        $j | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding UTF8
        Say "your own schemes, profiles and keybindings were left alone" DarkGray
    } catch { Say "could not edit Windows Terminal settings: $($_.Exception.Message)" Yellow }
}

# --- 3. Claude Code ---------------------------------------------------------
Step "Claude Code"
$cs = Join-Path $Root '.claude\settings.json'
if (-not (Test-Path $cs)) { Say "no settings.json" DarkGray }
elseif ($DryRun) { Say "would remove the statusLine entry" }
else {
    try {
        $j = Get-Content $cs -Raw | ConvertFrom-Json
        if ($j.PSObject.Properties.Name -contains 'statusLine') {
            $j.PSObject.Properties.Remove('statusLine')
            $j | ConvertTo-Json -Depth 32 | Set-Content $cs -Encoding UTF8
            Did "removed the statusLine entry, kept the rest"
        } else { Say "no statusLine entry" DarkGray }
    } catch { Say "could not edit Claude settings: $($_.Exception.Message)" Yellow }
}

foreach ($f in '.claude\statusline.ps1', '.claude\commands\terminal-theme.md') {
    $p = Join-Path $Root $f
    if (-not (Test-Path $p)) { continue }
    if ($DryRun) { Say "would delete $f" } else { Remove-Item $p -Force; Did "deleted $f" }
}

# --- 4. the files -----------------------------------------------------------
Step "Files"
$omp = Join-Path $Root '.oh-my-posh'
if ($KeepDownloads) { Say "keeping $omp (-KeepDownloads)" DarkGray }
elseif (-not (Test-Path $omp)) { Say "nothing at $omp" DarkGray }
elseif ($DryRun) {
    $n = @(Get-ChildItem $omp -Recurse -File -EA SilentlyContinue).Count
    Say "would delete $omp ($n files)"
} else {
    Remove-Item $omp -Recurse -Force
    Did "deleted $omp"
}

$exe = Join-Path $Root '.local\bin\oh-my-posh.exe'
if (Test-Path $exe) {
    if ($DryRun) { Say "would delete oh-my-posh.exe" }
    else { Remove-Item $exe -Force; Did "deleted oh-my-posh.exe" }
}
Say "~\.local\bin itself was left on PATH - other tools may live there" DarkGray

if (-not $DryRun -and -not $TestRoot) {
    [Environment]::SetEnvironmentVariable('POSH_THEMES_PATH', $null, 'User')
    Did "cleared POSH_THEMES_PATH"
}

# --- done -------------------------------------------------------------------
Write-Host ""
if ($DryRun) { Write-Host "  Dry run - nothing was changed." -ForegroundColor Yellow }
else { Write-Host "  Removed $removed things." -ForegroundColor Green }
Write-Host ""
Write-Host "  Left in place on purpose: PowerShell 7, Windows Terminal, git," -ForegroundColor DarkGray
Write-Host "  Python, the Nerd Font and Terminal-Icons. They are general tools," -ForegroundColor DarkGray
Write-Host "  and something else may now depend on them." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Close and reopen your terminal." -ForegroundColor White
Write-Host ""
