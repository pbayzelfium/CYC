<#
.SYNOPSIS
  Sets up a themed Windows Terminal + PowerShell 7 prompt + Claude Code status line.

.DESCRIPTION
  Installs everything it needs - you should not have to fetch anything first.
  If it is run from Windows PowerShell 5.1 it installs PowerShell 7 and
  restarts itself there.

  Brings: PowerShell 7, JetBrainsMono Nerd Font, oh-my-posh + its design
  collection, Terminal-Icons, git and Python where missing. Then writes a
  custom prompt with matched colour themes, a Claude Code status line that
  follows the terminal theme, a /terminal-theme slash command, and a
  pre-built theme catalogue.

  Python is not optional: recolouring a prompt design onto a theme runs
  pair-prompt.py at the moment you switch, so without it that feature is dead.

  Nothing is overwritten without a .bak beside it, and JSON settings are merged
  rather than replaced.

.PARAMETER DryRun
  Print what would happen and change nothing.

.PARAMETER SkipCatalogue
  Do not install the catalogue builder sources. The pre-built catalogue is
  installed either way.

.PARAMETER NoOpen
  Do not open the theme catalogue in a browser when it finishes.

.PARAMETER ResetTerminalSettings
  Only relevant if your Windows Terminal settings file is already invalid, which
  this cannot repair. Moves it aside, keeping a copy, so Windows Terminal writes
  a fresh one and the theming can be applied.

.PARAMETER Force
  Re-run over an existing install. Without this, an existing install is left
  alone: re-running replaces the prompt config with the shipped generic one,
  which loses any personal edits.

.EXAMPLE
  Works on any Windows, including one with only PowerShell 5.1:
    powershell -ExecutionPolicy Bypass -NoProfile -File install.ps1

  If you already have PowerShell 7:
    pwsh -NoProfile -File install.ps1 -DryRun
#>
# PositionalBinding=$false: a stray argument must never land in a parameter
# by position. -TestRoot silently absorbed a '-DryRun' that way.
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$DryRun,
    [switch]$SkipCatalogue,
    [switch]$Force,
    # Do not open the catalogue at the end. Set automatically in tests and CI.
    [switch]$NoOpen,
    # If Windows Terminal's settings file is already invalid, move it aside so
    # Windows Terminal writes a fresh one, instead of skipping the theming.
    [switch]$ResetTerminalSettings,
    # Where the payload comes from. Defaults to the published repo; point it at
    # a local checkout to install without network, which is what the tests do.
    [string]$Source,
    [string]$BaseUrl = 'https://raw.githubusercontent.com/pbayzelfium/CYC/main/src',
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

function Save-JsonSafely {
    <#  Write $Object to $Path as JSON without any chance of leaving a partial
        file. A truncated settings.json stops Windows Terminal from starting at
        all, so the original is only replaced once a complete, re-parsed copy
        exists on disk beside it.  #>
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path
    )

    $json = $Object | ConvertTo-Json -Depth 32
    if ([string]::IsNullOrWhiteSpace($json)) { throw "serialised to nothing" }

    # prove it before it goes anywhere near the real file
    $null = $json | ConvertFrom-Json

    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))

    # and prove what actually landed on disk, not just what we meant to write
    $null = (Get-Content $tmp -Raw) | ConvertFrom-Json

    Move-Item $tmp $Path -Force
}

function Backup {
    param([string]$Path)
    if ((Test-Path $Path) -and -not $DryRun) {
        Copy-Item $Path "$Path.bak" -Force
        Say "backed up -> $(Split-Path $Path -Leaf).bak" DarkGray
    }
}

function Get-PayloadFile {
    <#  Fetch one file from the repo, or copy it from -Source. Plain text over
        https, nothing encoded: a script carrying a large base64 blob is the
        shape packers have, and scanners flag it on sight.  #>
    param([string]$Dest)
    if ($Source) {
        $from = Join-Path $Source $Dest
        if (-not (Test-Path $from)) { throw "not in -Source: $Dest" }
        return [IO.File]::ReadAllText($from)
    }
    $url = "$BaseUrl/$($Dest -replace '\\','/')"
    (Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ 'User-Agent' = 'cyc-installer' }).Content
}

function Write-Payload {
    param([string]$Dest)
    $full = Join-Path $Root $Dest
    if ($DryRun) { Say "would write $Dest"; return }
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $text = Get-PayloadFile $Dest
    Backup $full
    [IO.File]::WriteAllText($full, $text)
    Say "wrote $Dest" DarkGray
}

# ---------------------------------------------------------------------------
# What to install, and whether it is core (installed even with -SkipCatalogue).
$Manifest = [ordered]@{
#__MANIFEST__
}
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Terminal setup" -ForegroundColor White
Write-Host "  ==============" -ForegroundColor DarkGray
if ($DryRun) { Say "DRY RUN - nothing will change" Yellow }

# --- do not quietly overwrite an existing install ---------------------------
# Re-running replaces the prompt config with the shipped generic one, so a
# personalised cyc.omp.json loses its edits. A .bak is left, but silence
# is the wrong default when the cost is someone's own configuration.
$existing = @(
    (Join-Path $Root '.oh-my-posh\palettes.json'),
    (Join-Path $Root '.oh-my-posh\cyc.omp.json')
) | Where-Object { Test-Path $_ }

if ($existing -and -not $Force -and -not $DryRun) {
    $custom = $false
    $z = Join-Path $Root '.oh-my-posh\cyc.omp.json'
    if (Test-Path $z) { $custom = (Get-Content $z -Raw) -match 'mapped_locations' }

    Write-Host ""
    Write-Host "  CYC is already installed here." -ForegroundColor Yellow
    Say "found: $($existing[0])" DarkGray
    if ($custom) {
        Write-Host "  Your prompt config has personal edits (folder shortcuts)." -ForegroundColor Yellow
        Write-Host "  Re-running would replace it with the generic one." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  To see what would change, without changing anything:" -ForegroundColor DarkGray
    Write-Host "    -DryRun"
    Write-Host "  To upgrade anyway (a .bak is kept beside every file it replaces):" -ForegroundColor DarkGray
    Write-Host "    -Force"
    Write-Host ""
    exit 0
}

# --- 1. dependencies --------------------------------------------------------
Step "Dependencies"

function Get-Latest {
    param([string]$Pattern)
    $r = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
        -Headers @{ 'User-Agent' = 'cyc-installer' }
    ($r.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1).browser_download_url
}

function Install-Winget {
    param([string]$Id, [string]$Label)
    if (-not (Get-Command winget -EA SilentlyContinue)) { return $false }
    Say "installing $Label via winget..."
    winget install --id $Id --source winget --accept-package-agreements `
        --accept-source-agreements --silent 2>&1 | Out-Null
    $true
}

# --- PowerShell 7: the one that has to happen before anything else ----------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Say "running under Windows PowerShell $($PSVersionTable.PSVersion) - PowerShell 7 is required" Yellow
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path $pwsh)) {
        if ($DryRun) { Say "would install PowerShell 7, then restart in it"; exit 0 }
        Say "installing PowerShell 7 - accept the elevation prompt..."
        try {
            $msi = Join-Path $env:TEMP 'cyc-pwsh.msi'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -Uri (Get-Latest '*win-x64.msi') -OutFile $msi
            $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qb /norestart" -Wait -PassThru
            Remove-Item $msi -Force -EA SilentlyContinue
            if ($proc.ExitCode -ne 0) { throw "msiexec exited $($proc.ExitCode)" }
        } catch {
            Write-Host ""
            Write-Host "  Could not install PowerShell 7: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Install it and run this again:" -ForegroundColor Yellow
            Write-Host "    winget install --id Microsoft.PowerShell --scope machine" -ForegroundColor Yellow
            exit 1
        }
    }
    if (-not (Test-Path $pwsh)) { Write-Host "  PowerShell 7 still not found." -ForegroundColor Red; exit 1 }

    if (-not $PSCommandPath) {
        # Piped in rather than run from a file, so there is no path to restart.
        Write-Host ""
        Write-Host "  This script cannot restart itself when it is piped in." -ForegroundColor Red
        Write-Host "  Save it to a file first, then run that file:" -ForegroundColor Yellow
        Write-Host '    irm https://raw.githubusercontent.com/pbayzelfium/CYC/main/install.ps1 -OutFile "$env:TEMP\cyc-install.ps1"' -ForegroundColor Yellow
        Write-Host '    powershell -ExecutionPolicy Bypass -NoProfile -File "$env:TEMP\cyc-install.ps1"' -ForegroundColor Yellow
        exit 1
    }
    Say "restarting in PowerShell 7..." Green
    # Pass on whatever was actually given. Naming the parameters here by hand is
    # how -Force came to be lost: it was added to the parameter block later and
    # never added to this list, so it vanished at the handover and the second run
    # behaved as though it had never been typed.
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $argv += "-$($kv.Key)" }
        } elseif ($null -ne $kv.Value -and "$($kv.Value)" -ne '') {
            $argv += @("-$($kv.Key)", "$($kv.Value)")
        }
    }
    if ($PSBoundParameters.Count) {
        Say "carrying over: $((@($PSBoundParameters.Keys) | Sort-Object) -join ', ')" DarkGray
    }
    & $pwsh @argv
    exit $LASTEXITCODE
}
Say "PowerShell $($PSVersionTable.PSVersion)" DarkGray

$wtSettings = if ($TestRoot) { Join-Path $Root 'wt-settings.json' }
              else { Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json' }
if (Test-Path $wtSettings) { Say "Windows Terminal found" DarkGray }
elseif ($Offline) { Say "Windows Terminal skipped (test mode)" DarkGray }
elseif ($DryRun)  { Say "would install Windows Terminal" }
else {
    # Without it there is no window to theme, so install it rather than warn.
    if (Install-Winget 'Microsoft.WindowsTerminal' 'Windows Terminal') {
        Say "installed - open it once so it writes its settings, then re-run this" Yellow
    } else {
        Warn "Windows Terminal not found and could not be installed. Get it from the Microsoft Store, open it once, then re-run this."
    }
}

$hasWinget = [bool](Get-Command winget -EA SilentlyContinue)
if ($hasWinget) { Say "winget available" DarkGray }
else { Warn "winget not found - falling back to direct downloads." }

# --- git ---------------------------------------------------------------------
if (Get-Command git -EA SilentlyContinue) { Say "git found" DarkGray }
elseif ($Offline) { Say "git skipped (test mode)" DarkGray }
elseif ($DryRun)  { Say "would install git" }
else {
    if (Install-Winget 'Git.Git' 'git') {
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path','User')
        if (Get-Command git -EA SilentlyContinue) { Say "git installed" DarkGray }
        else { Warn "git installed but not on PATH yet - reopen your terminal." }
    } else {
        Warn "could not install git. Get it from https://git-scm.com - the prompt's git segment stays empty without it."
    }
}

# --- Python: a RUNTIME dependency, not an optional extra --------------------
# Set-PoshTheme shells out to pair-prompt.py every time you pick a design, so
# without Python the recolouring feature is dead rather than degraded.
function Get-AnyPython {
    foreach ($n in 'python', 'python3') {
        $c = Get-Command $n -EA SilentlyContinue
        # the Store stub in WindowsApps is not a real interpreter
        if ($c -and $c.Source -notlike '*WindowsApps*') { return $c.Source }
    }
    foreach ($g in 'C:\Python3*\python.exe', "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe") {
        $f = Get-ChildItem $g -EA SilentlyContinue | Select-Object -Last 1
        if ($f) { return $f.FullName }
    }
    $null
}

$python = Get-AnyPython
if ($python)      { Say "python found: $python" DarkGray }
elseif ($Offline) { Say "python skipped (test mode)" DarkGray }
elseif ($DryRun)  { Say "would install Python (needed to recolour prompts)" }
else {
    if (Install-Winget 'Python.Python.3.12' 'Python') {
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path','User')
        $python = Get-AnyPython
    }
    if (-not $python) {
        try {
            Say "downloading Python installer..."
            $exe = Join-Path $env:TEMP 'cyc-python.exe'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -OutFile $exe `
                -Uri 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe'
            Start-Process $exe -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1' -Wait
            Remove-Item $exe -Force -EA SilentlyContinue
            $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path','User')
            $python = Get-AnyPython
        } catch { }
    }
    if ($python) { Say "python installed: $python" DarkGray }
    else { Warn "could not install Python. Recolouring a prompt design onto a theme will not work until you install it from python.org." }
}

# --- 2. Nerd Font -----------------------------------------------------------
Step "JetBrainsMono Nerd Font"

$fontInstalled = @(
    (Join-Path $env:WINDIR 'Fonts\JetBrainsMonoNerdFont-Regular.ttf'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\JetBrainsMonoNerdFont-Regular.ttf')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Offline)           { Say "skipped (test mode)" DarkGray }
elseif ($fontInstalled) { Say "already installed" DarkGray }
elseif ($DryRun)        { Say "would install the Nerd Font" }
else {
    $done = Install-Winget 'DEVCOM.JetBrainsMonoNerdFont' 'the Nerd Font'
    if (-not $done -or -not (Test-Path (Join-Path $env:WINDIR 'Fonts\JetBrainsMonoNerdFont-Regular.ttf'))) {
        # No winget, or it did not land: install per-user, which needs no admin.
        try {
            Say "installing the font for this user..."
            $zip = Join-Path $env:TEMP 'cyc-font.zip'
            $dir = Join-Path $env:TEMP 'cyc-font'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -OutFile $zip `
                -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
            Expand-Archive $zip -DestinationPath $dir -Force
            $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
            New-Item -ItemType Directory -Force $userFonts | Out-Null
            $key = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
            foreach ($f in Get-ChildItem $dir -Filter 'JetBrainsMonoNerdFont-*.ttf') {
                Copy-Item $f.FullName $userFonts -Force
                New-ItemProperty -Path $key -Name "$($f.BaseName) (TrueType)" `
                    -Value (Join-Path $userFonts $f.Name) -PropertyType String -Force | Out-Null
            }
            Remove-Item $zip, $dir -Recurse -Force -EA SilentlyContinue
            Say "font installed for this user" DarkGray
        } catch {
            Warn "could not install the Nerd Font: $($_.Exception.Message). Icons will show as boxes."
        }
    } else { Say "installed" DarkGray }
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
    # An x64 binary will not run on a Surface Pro X and friends.
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'ARM64' { 'arm64' }
        'x86'   { '386' }
        default { 'amd64' }
    }
    Say "architecture: $arch" DarkGray
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-windows-$arch.exe" `
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
foreach ($k in $Manifest.Keys) {
    if ($k -eq '__profile__') { continue }
    if ($SkipCatalogue -and -not $Manifest[$k]) { Say "skipped $k (catalogue builder)" DarkGray; continue }
    try { Write-Payload $k }
    catch { Warn "could not fetch $k : $($_.Exception.Message)" }
}

# --- 6. profile -------------------------------------------------------------
Step "PowerShell profile"
$block = Get-PayloadFile 'profile-block.ps1'
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
        $wtRaw = Get-Content $wtSettings -Raw

        # Is it valid before we touch it? A broken settings.json is why Windows
        # Terminal shows "Error al cargar configuracion" / "Failed to load
        # settings" and runs on defaults - and it is not something this wrote.
        $wtValid = $true
        try { $null = $wtRaw | ConvertFrom-Json } catch { $wtValid = $false }

        if (-not $wtValid) {
            if ($ResetTerminalSettings) {
                $aside = "$wtSettings.broken-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
                Move-Item $wtSettings $aside -Force
                Say "your settings file was invalid - moved to $(Split-Path $aside -Leaf)" Yellow
                Say "Windows Terminal will write a fresh one" DarkGray
                $wtRaw = '{}'
            } else {
                Write-Host ""
                Write-Host "  Your Windows Terminal settings file is not valid JSON." -ForegroundColor Yellow
                Write-Host "  It was already broken before this ran - nothing here caused it." -ForegroundColor Yellow
                Write-Host "  Windows Terminal is ignoring it and using defaults, which is why" -ForegroundColor Yellow
                Write-Host "  it shows a 'failed to load settings' box when it starts." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  The prompt will still be installed. The colours cannot be," -ForegroundColor Yellow
                Write-Host "  because there is no readable file to merge them into." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Either fix the file yourself, or re-run with:" -ForegroundColor Yellow
                Write-Host "    -ResetTerminalSettings" -ForegroundColor Cyan
                Write-Host "  which moves it aside, keeping a copy, and lets Windows Terminal" -ForegroundColor Yellow
                Write-Host "  write a fresh one." -ForegroundColor Yellow
                Write-Host ""
                Warn "Windows Terminal theming skipped: its settings file is invalid (see above)"
                throw 'skip'
            }
        }

        Backup $wtSettings
        # PowerShell parses comments but cannot write them back, so a commented
        # settings file comes out stripped. Say so rather than quietly doing it.
        if ($wtRaw -match '(?m)^\s*//') {
            Warn "your Windows Terminal settings contain comments; they cannot be preserved and will be dropped (the .bak keeps them)"
        }
        $wt = $wtRaw | ConvertFrom-Json
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

        Save-JsonSafely -Object $wt -Path $wtSettings
        Say "appearance applied" DarkGray
    } catch {
        if ($_.Exception.Message -ne 'skip') {
            Warn "could not update Windows Terminal settings: $($_.Exception.Message)"
        }
    }
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
        Save-JsonSafely -Object $s -Path $claudeSettings
        Say "status line configured" DarkGray
    } catch { Warn "could not update Claude settings: $($_.Exception.Message)" }
}

# --- 9. catalogue toolchain -------------------------------------------------
Step "Catalogue builder"
if ($Offline -or $SkipCatalogue) { Say "skipped" DarkGray }
elseif (-not $python) { Warn "no Python, so the catalogue cannot be rebuilt. The pre-built one still opens with 'catalogue'." }
elseif ($DryRun) { Say "would create a virtualenv and install fonttools" }
else {
    try {
        $venv = Join-Path $Root '.oh-my-posh\catalogue\.venv'
        if (-not (Test-Path (Join-Path $venv 'Scripts\python.exe'))) {
            & $python -m venv $venv 2>&1 | Out-Null
        }
        $vpy = Join-Path $venv 'Scripts\python.exe'
        if (Test-Path $vpy) {
            & $vpy -m pip install --quiet --disable-pip-version-check fonttools brotli 2>&1 | Out-Null
            Say "virtualenv ready - 'rebuild.ps1' will work" DarkGray
        } else { Warn "could not create the catalogue virtualenv" }
    } catch { Warn "catalogue toolchain: $($_.Exception.Message)" }
}

# --- 10. generate the prompt variants --------------------------------------
Step "Building prompt variants"
if ($DryRun) { Say "would run build-variants.ps1" }
else {
    try {
        & (Join-Path $Root '.oh-my-posh\build-variants.ps1') | Out-Null
        Say "one prompt palette per theme generated" DarkGray
    } catch { Warn "build-variants failed: $($_.Exception.Message)" }
}

# --- done -------------------------------------------------------------------
# --- 10b. the cyc:// link handler -------------------------------------------
# So the catalogue's buttons can apply a theme directly instead of handing you
# a command to paste. Per-user registry, no admin needed.
Step "Catalogue buttons"
$handler = Join-Path $Root '.oh-my-posh\cyc-protocol.ps1'
if ($Offline -or $TestRoot) { Say "skipped (test mode)" DarkGray }
elseif ($DryRun) { Say "would register the cyc:// link handler" }
elseif (-not (Test-Path $handler)) { Warn "handler missing, buttons will fall back to copying" }
else {
    try {
        $pwshExe = (Get-Process -Id $PID).Path
        $key = 'HKCU:\Software\Classes\cyc'
        New-Item -Path $key -Force | Out-Null
        Set-ItemProperty -Path $key -Name '(Default)' -Value 'URL:CYC theme'
        Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
        New-Item -Path "$key\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "$key\shell\open\command" -Name '(Default)' `
            -Value ('"{0}" -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" "%1"' -f $pwshExe, $handler)
        Say "registered - the catalogue can now apply themes directly" DarkGray
    } catch { Warn "could not register the link handler: $($_.Exception.Message)" }
}

# --- 11. show them what they just installed --------------------------------
# The point of the catalogue is being seen. Waiting for someone to think to
# type 'catalogue' means most people never find it.
$page = Join-Path $Root '.oh-my-posh\catalogue\theme-catalogue.html'
if ($DryRun) { Step "Catalogue"; Say "would open $page in your browser" }
elseif ($NoOpen -or $Offline -or $env:CI) { }
elseif (Test-Path $page) {
    Step "Opening the catalogue"
    try {
        Start-Process $page
        Say "opened in your browser - every prompt design, with previews" DarkGray
    } catch {
        Say "could not open a browser. Open it yourself:" Yellow
        Say "  $page" DarkGray
    }
}

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
Write-Host "    catalogue                reopen the theme catalogue later"
Write-Host ""
Write-Host "  The catalogue just opened in your browser; 'catalogue' reopens it." -ForegroundColor DarkGray
Write-Host "  Rebuild it only after adding a theme:" -ForegroundColor DarkGray
Write-Host "    pwsh -NoProfile -File ~/.oh-my-posh/catalogue/rebuild.ps1"
Write-Host ""
