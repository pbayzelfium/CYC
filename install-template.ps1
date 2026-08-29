<#
.SYNOPSIS
  Sets up a themed Windows Terminal + PowerShell 7 prompt + Claude Code status line.

.DESCRIPTION
  Installs JetBrainsMono Nerd Font and oh-my-posh, writes a custom prompt with
  matched colour themes, a Claude Code status line that follows the terminal
  theme, and a /terminal-theme slash command for switching it all from inside
  Claude Code.

  Nothing is overwritten without a .bak beside it, and JSON settings are merged
  rather than replaced.

.PARAMETER DryRun
  Print what would happen and change nothing.

.PARAMETER SkipCatalogue
  Do not install the catalogue builder (which needs Python).

.EXAMPLE
  pwsh -NoProfile -File install.ps1
  pwsh -NoProfile -File install.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipCatalogue,
    # Testing seam: install into a throwaway directory instead of the real
    # home, and skip the network steps. See test-install.ps1.
    [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
$script:Failed = @()

$Root = if ($TestRoot) { (New-Item -ItemType Directory -Force $TestRoot).FullName } else { $HOME }
$ProfileFile = if ($TestRoot) { Join-Path $Root 'Documents\PowerShell\profile.ps1' } else { $PROFILE }
$Offline = [bool]$TestRoot

function Say  { param($m, $c = 'Gray') Write-Host "  $m" -ForegroundColor $c }
function Step { param($m) Write-Host ""; Write-Host "> $m" -ForegroundColor Cyan }
function Warn { param($m) Write-Host "  ! $m" -ForegroundColor Yellow; $script:Failed += $m }

function Backup {
    param([string]$Path)
    if ((Test-Path $Path) -and -not $DryRun) {
        Copy-Item $Path "$Path.bak" -Force
        Say "backed up -> $(Split-Path $Path -Leaf).bak" DarkGray
    }
}

function Write-Payload {
    param([string]$Dest, [string]$B64)
    $full = Join-Path $Root $Dest
    if ($DryRun) { Say "would write $Dest"; return }
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    Backup $full
    [IO.File]::WriteAllText($full, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64)))
    Say "wrote $Dest" DarkGray
}

# ---------------------------------------------------------------------------
$Payload = @{
#__PAYLOAD__
}
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Terminal setup" -ForegroundColor White
Write-Host "  ==============" -ForegroundColor DarkGray
if ($DryRun) { Say "DRY RUN - nothing will change" Yellow }

# --- 1. prerequisites -------------------------------------------------------
Step "Checking prerequisites"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "Run this with PowerShell 7 (pwsh), not Windows PowerShell 5.1."
}
Say "PowerShell $($PSVersionTable.PSVersion)" DarkGray

$wtSettings = if ($TestRoot) { Join-Path $Root 'wt-settings.json' }
              else { Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json' }
if (Test-Path $wtSettings) { Say "Windows Terminal found" DarkGray }
else { Warn "Windows Terminal settings not found - its theming will be skipped." }

if (Get-Command git -EA SilentlyContinue) { Say "git found" DarkGray }
else { Warn "git not found - the prompt's git segment will stay empty." }

# --- 2. Nerd Font -----------------------------------------------------------
Step "JetBrainsMono Nerd Font"

$fontInstalled = @(
    (Join-Path $env:WINDIR 'Fonts\JetBrainsMonoNerdFont-Regular.ttf'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\JetBrainsMonoNerdFont-Regular.ttf')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Offline)      { Say "skipped (test mode)" DarkGray }
elseif ($fontInstalled) { Say "already installed" DarkGray }
elseif ($DryRun)    { Say "would install via winget (DEVCOM.JetBrainsMonoNerdFont)" }
elseif (Get-Command winget -EA SilentlyContinue) {
    Say "installing via winget - accept the elevation prompt..."
    winget install --id DEVCOM.JetBrainsMonoNerdFont --source winget `
        --accept-package-agreements --accept-source-agreements --silent | Out-Null
    Say "done" DarkGray
} else {
    Warn "winget not available - install JetBrainsMono Nerd Font by hand, or icons will show as boxes."
}

# --- 3. oh-my-posh ----------------------------------------------------------
Step "oh-my-posh"

$binDir = Join-Path $Root '.local\bin'
$omp    = Join-Path $binDir 'oh-my-posh.exe'

if ($Offline)       { Say "skipped (test mode)" DarkGray }
elseif (Test-Path $omp) { Say "already present" DarkGray }
elseif ($DryRun)    { Say "would download the portable binary to ~\.local\bin" }
else {
    # A portable binary, not the installer: on machines where UAC elevates into
    # a different account the per-user installer lands in the wrong profile.
    New-Item -ItemType Directory -Force $binDir | Out-Null
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-windows-amd64.exe' `
        -OutFile $omp
    Say "downloaded to ~\.local\bin" DarkGray
}

# PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $Offline -and $userPath -notlike "*$binDir*") {
    if ($DryRun) { Say "would add ~\.local\bin to your PATH" }
    else {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
        Say "added ~\.local\bin to PATH" DarkGray
    }
}
$env:Path = "$env:Path;$binDir"

# themes
$themeDir = Join-Path $Root '.oh-my-posh\themes'
if ($Offline) { Say "skipped (test mode)" DarkGray }
elseif ((Test-Path $themeDir) -and (Get-ChildItem $themeDir -Filter *.omp.json -EA SilentlyContinue)) {
    Say "theme collection already present" DarkGray
} elseif ($DryRun) { Say "would download the oh-my-posh theme collection" }
else {
    $zip = Join-Path $env:TEMP 'omp-themes.zip'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip' -OutFile $zip
    Expand-Archive $zip -DestinationPath $themeDir -Force
    Remove-Item $zip -Force
    Say "$((Get-ChildItem $themeDir -Filter *.omp.json).Count) designs installed" DarkGray
}
if (-not $DryRun -and -not $Offline) { [Environment]::SetEnvironmentVariable('POSH_THEMES_PATH', $themeDir, 'User') }

# --- 4. Terminal-Icons ------------------------------------------------------
Step "Terminal-Icons module"
if ($Offline) { Say "skipped (test mode)" DarkGray }
elseif (Get-Module -ListAvailable Terminal-Icons) { Say "already installed" DarkGray }
elseif ($DryRun) { Say "would install Terminal-Icons for the current user" }
else {
    try {
        Install-Module Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        Say "installed" DarkGray
    } catch { Warn "could not install Terminal-Icons: $($_.Exception.Message)" }
}

# --- 5. files ---------------------------------------------------------------
Step "Writing configuration"
foreach ($k in $Payload.Keys) {
    if ($k -eq '__profile__') { continue }
    if ($SkipCatalogue -and -not $Payload[$k].core) { Say "skipped $k (catalogue)" DarkGray; continue }
    Write-Payload $k $Payload[$k].b64
}

# --- 6. profile -------------------------------------------------------------
Step "PowerShell profile"
$block = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload['__profile__'].b64))
$marker = '# >>> terminal-theme setup >>>'
$endmk  = '# <<< terminal-theme setup <<<'

if ($DryRun) { Say "would add a marked block to $ProfileFile" }
else {
    $dir = Split-Path $ProfileFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $existing = if (Test-Path $ProfileFile) { Get-Content $ProfileFile -Raw } else { '' }
    Backup $ProfileFile
    $wrapped = "$marker`n$block`n$endmk`n"
    if ($existing -match [regex]::Escape($marker)) {
        # replace only our own block, leave everything else alone
        $pattern = "(?s)" + [regex]::Escape($marker) + ".*?" + [regex]::Escape($endmk) + "\r?\n?"
        $existing = [regex]::Replace($existing, $pattern, '')
        Say "replacing the previous block" DarkGray
    }
    [IO.File]::WriteAllText($ProfileFile, ($existing.TrimEnd() + "`n`n" + $wrapped))
    Say "profile updated" DarkGray
}

# --- 7. Windows Terminal ----------------------------------------------------
Step "Windows Terminal"
if (-not (Test-Path $wtSettings)) { Say "skipped - not installed" DarkGray }
elseif ($DryRun) { Say "would add 7 colour schemes and set the font, then merge in the appearance" }
else {
    try {
        Backup $wtSettings
        $wt = Get-Content $wtSettings -Raw | ConvertFrom-Json
        $pal = Get-Content (Join-Path $Root '.oh-my-posh\palettes.json') -Raw | ConvertFrom-Json

        # colour schemes: replace ours by name, leave any others alone
        $defs = Get-Content (Join-Path $Root '.oh-my-posh\schemes.json') -Raw | ConvertFrom-Json
        $names = @($defs | ForEach-Object { $_.name })
        $kept  = @($wt.schemes | Where-Object { $names -notcontains $_.name })
        $wt.schemes = @($kept + $defs)
        Say "$($names.Count) colour schemes added" DarkGray

        if (-not $wt.profiles.defaults) {
            $wt.profiles | Add-Member defaults ([pscustomobject]@{}) -Force
        }
        $d = $wt.profiles.defaults
        foreach ($kv in @{
            font           = [pscustomobject]@{ face = 'JetBrainsMono NF'; size = 11 }
            colorScheme    = 'Catppuccin Mocha'
            useAcrylic     = $true
            opacity        = 95
            padding        = '14, 12, 14, 12'
            scrollbarState = 'hidden'
            historySize    = 20000
            cursorShape    = 'filledBox'
            antialiasingMode = 'grayscale'
        }.GetEnumerator()) {
            $d | Add-Member $kv.Key $kv.Value -Force
        }

        # prefer PowerShell 7 as the default profile
        $pwshProfile = $wt.profiles.list | Where-Object { $_.source -eq 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
        if ($pwshProfile) { $wt | Add-Member defaultProfile $pwshProfile.guid -Force }

        $wt | ConvertTo-Json -Depth 32 | Set-Content $wtSettings -Encoding UTF8
        Say "appearance applied" DarkGray
    } catch { Warn "could not update Windows Terminal settings: $($_.Exception.Message)" }
}

# --- 8. Claude Code status line --------------------------------------------
Step "Claude Code status line"
$claudeSettings = Join-Path $Root '.claude\settings.json'
if ($DryRun) { Say "would add a statusLine entry to ~\.claude\settings.json" }
else {
    try {
        $s = if (Test-Path $claudeSettings) {
            Backup $claudeSettings
            Get-Content $claudeSettings -Raw | ConvertFrom-Json
        } else {
            New-Item -ItemType Directory -Force (Split-Path $claudeSettings -Parent) | Out-Null
            [pscustomobject]@{}
        }
        $s | Add-Member statusLine ([pscustomobject]@{
            type            = 'command'
            command         = "pwsh -NoProfile -File $($Root -replace '\\','/')/.claude/statusline.ps1"
            padding         = 0
            refreshInterval = 30
        }) -Force
        $s | ConvertTo-Json -Depth 32 | Set-Content $claudeSettings -Encoding UTF8
        Say "status line configured" DarkGray
    } catch { Warn "could not update Claude settings: $($_.Exception.Message)" }
}

# --- 9. generate the prompt variants ---------------------------------------
Step "Building prompt variants"
if ($DryRun) { Say "would run build-variants.ps1" }
else {
    try {
        & (Join-Path $Root '.oh-my-posh\build-variants.ps1') | Out-Null
        Say "one prompt palette per theme generated" DarkGray
    } catch { Warn "build-variants failed: $($_.Exception.Message)" }
}

# --- done -------------------------------------------------------------------
Write-Host ""
if ($script:Failed.Count) {
    Write-Host "  Finished with $($script:Failed.Count) warning(s):" -ForegroundColor Yellow
    $script:Failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
} else {
    Write-Host "  Done." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Close every Windows Terminal window and open a new one." -ForegroundColor White
Write-Host "  Then try:" -ForegroundColor DarkGray
Write-Host "    tts                      the theme menu, with colour swatches"
Write-Host "    tt 3                     switch theme and prompt together"
Write-Host "    Install-TerminalTheme    add any of 600+ schemes"
Write-Host "    /terminal-theme          the same, from inside Claude Code"
Write-Host ""
if (-not $SkipCatalogue) {
    Write-Host "  The catalogue builder needs Python. To set it up:" -ForegroundColor DarkGray
    Write-Host "    python -m venv ~/.oh-my-posh/catalogue/.venv"
    Write-Host "    ~/.oh-my-posh/catalogue/.venv/Scripts/python -m pip install fonttools brotli"
    Write-Host "    pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1"
    Write-Host ""
}
