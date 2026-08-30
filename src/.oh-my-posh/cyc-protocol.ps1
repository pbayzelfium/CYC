<#
  Handles cyc:// links, so the catalogue's buttons can apply a theme directly
  instead of handing you a command to paste.

  Windows launches this with the whole URL as the first argument:

      cyc://apply?theme=nord&design=atomic&b=-20&s=-34
      cyc://update

  SECURITY. A protocol handler is a way for any web page to run something on
  this machine, so nothing here is passed to a shell. Every value is matched
  against what is actually installed - the keys in palettes.json and the files
  in themes/ - and anything that does not match exactly is refused. There is no
  path, no expression and no command in the URL, only names to look up.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)][string]$Url,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $HOME '.oh-my-posh'
$log  = Join-Path $root 'protocol.log'

function Note {
    param($m)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    try { Add-Content -Path $log -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

function Fail { param($m) Note "REFUSED: $m"; exit 1 }

if (-not $Url) { Fail 'no url' }
Note "url: $Url"

# --- what is being asked for ------------------------------------------------
if ($Url -notmatch '^cyc://([a-z]{1,12})') { Fail 'not a cyc:// url' }
$action = $Matches[1]
if ($action -notin @('apply', 'update')) { Fail "unknown action: $action" }

if ($action -eq 'update') {
    # This handler is registered windowless, because applying a theme has
    # nothing to show. An update does: it takes a minute and it says what it
    # kept. So hand it to a window someone can actually read.
    $updater = Join-Path $root 'cyc-update.ps1'
    if (-not (Test-Path $updater)) { Fail 'the updater is not installed' }

    $script = @"
. '$updater'
Write-Host ''
Write-Host '  Checking for updates...' -ForegroundColor Cyan
`$c = Test-CycUpdate -Quiet
if (-not `$c.Reachable) {
    Write-Host ''
    Write-Host '  Could not reach the update server.' -ForegroundColor Yellow
    Write-Host '  Check your connection and try again.' -ForegroundColor DarkGray
} elseif (-not `$c.Available) {
    Write-Host ''
    Write-Host "  You are on the latest version (`$(`$c.Current))." -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host "  Update found: `$(`$c.Current) -> `$(`$c.Latest)" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Close your other terminal windows now.' -ForegroundColor Yellow
    Write-Host '  They are running the old profile, and it is replaced by this.' -ForegroundColor DarkGray
    Write-Host ''
    Start-Sleep -Seconds 4
    Update-Cyc -NoOpen
    Write-Host '  Opening a fresh terminal...' -ForegroundColor DarkGray
    `$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (`$wt) { Start-Process wt.exe } else { Start-Process (Get-Process -Id `$PID).Path }
    `$page = Join-Path '$root' 'catalogue\theme-catalogue.html'
    if (Test-Path `$page) { Start-Process `$page }
}
Write-Host ''
Write-Host '  Press any key to close.' -ForegroundColor DarkGray
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    $tmp = Join-Path $env:TEMP "cyc-update-run.ps1"
    Set-Content -Path $tmp -Value $script -Encoding UTF8
    Note 'update requested - opening a window'
    Start-Process (Get-Process -Id $PID).Path `
        -ArgumentList '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmp`""
    exit 0
}

# --- parse, without trusting anything --------------------------------------
$query = ($Url -replace '^cyc://[^?]*\??', '').TrimEnd('/')
$args  = @{}
foreach ($pair in ($query -split '&')) {
    if (-not $pair) { continue }
    $kv = $pair -split '=', 2
    if ($kv.Count -ne 2) { continue }
    $k = [uri]::UnescapeDataString($kv[0])
    $v = [uri]::UnescapeDataString($kv[1])
    # names only: no paths, no separators, no expressions
    if ($k -notmatch '^[a-z]{1,12}$') { Fail "bad key: $k" }
    if ($v -notmatch '^[A-Za-z0-9._@-]{0,64}$') { Fail "bad value for ${k}: $v" }
    $args[$k] = $v
}

# --- resolve against what is really installed -------------------------------
$theme = $null
if ($args.ContainsKey('theme')) {
    $palettes = Get-Content (Join-Path $root 'palettes.json') -Raw | ConvertFrom-Json
    $known = @($palettes.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' })
    if ($known -notcontains $args['theme']) { Fail "unknown theme: $($args['theme'])" }
    $theme = $args['theme']
}

$design = $null
if ($args.ContainsKey('design') -and $args['design']) {
    $d = $args['design']
    $ok = ($d -eq 'cyc') -or
          (Test-Path (Join-Path $root "themes\$d.omp.json")) -or
          (Test-Path (Join-Path $root "$d.omp.json"))
    if (-not $ok) { Fail "unknown design: $d" }
    $design = $d
}

[double]$b = 0; [double]$s = 0
foreach ($n in 'b', 's') {
    if (-not $args.ContainsKey($n)) { continue }
    $parsed = 0.0
    if (-not [double]::TryParse($args[$n], [ref]$parsed)) { Fail "bad number for ${n}" }
    if ($parsed -lt -100 -or $parsed -gt 100) { Fail "out of range for ${n}" }
    if ($n -eq 'b') { $b = $parsed } else { $s = $parsed }
}
$original = ($args['mode'] -eq 'original')

if ($WhatIfOnly) {
    Note "would apply theme=$theme design=$design b=$b s=$s original=$original"
    exit 0
}

# --- apply ------------------------------------------------------------------
# The switching functions come from the PowerShell profile, which loads because
# this runs without -NoProfile.
if (-not (Get-Command Set-TerminalTheme -ErrorAction SilentlyContinue)) {
    Fail 'the profile did not load, so Set-TerminalTheme is unavailable'
}

if ($theme)  { Set-TerminalTheme $theme | Out-Null; Note "theme -> $theme" }

if (-not $design -and ($b -or $s)) {
    # Sliders moved without picking a design: adjust the prompt already in use.
    $design = Get-BaseDesign
    Note "no design given, adjusting the current one: $design"
}

if ($design) {
    if ($original) { Set-PoshTheme $design -Original | Out-Null }
    else           { Set-PoshTheme $design -Brightness $b -Saturation $s | Out-Null }
    Note "design -> $design (b=$b s=$s original=$original)"
}

Note 'applied'
exit 0
