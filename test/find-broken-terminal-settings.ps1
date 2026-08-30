<#
.SYNOPSIS
  Finds which Windows Terminal settings file is broken, and offers to reset it.

.DESCRIPTION
  Windows Terminal keeps its settings in different places depending on how it
  was installed - Store, Preview, or unpackaged - and the installer only knew
  about the Store one. This looks in all of them, reports which files parse and
  which do not, and shows the offending lines.

  -Fix moves the broken one aside, keeping a copy, so Windows Terminal writes a
  fresh one on next start.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -NoProfile -File find-broken-terminal-settings.ps1
  powershell -ExecutionPolicy Bypass -NoProfile -File find-broken-terminal-settings.ps1 -Fix
#>
[CmdletBinding(PositionalBinding = $false)]
param([switch]$Fix)

$ErrorActionPreference = 'Continue'
$la = $env:LOCALAPPDATA

$candidates = @(
    @{ n = 'Store (stable)';  p = "$la\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" }
    @{ n = 'Store (preview)'; p = "$la\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json" }
    @{ n = 'Store (canary)';  p = "$la\Packages\Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\LocalState\settings.json" }
    @{ n = 'Unpackaged';      p = "$la\Microsoft\Windows Terminal\settings.json" }
)

Write-Host ""
Write-Host "  Windows Terminal settings files" -ForegroundColor White
Write-Host ""

$broken = @()
foreach ($c in $candidates) {
    if (-not (Test-Path $c.p)) {
        Write-Host ("  {0,-16} not present" -f $c.n) -ForegroundColor DarkGray
        continue
    }
    $size = (Get-Item $c.p).Length
    try {
        $null = (Get-Content $c.p -Raw) | ConvertFrom-Json
        Write-Host ("  {0,-16} OK       {1,8:N0} bytes" -f $c.n, $size) -ForegroundColor Green
        Write-Host ("                   $($c.p)") -ForegroundColor DarkGray
    } catch {
        Write-Host ("  {0,-16} BROKEN   {1,8:N0} bytes" -f $c.n, $size) -ForegroundColor Red
        Write-Host ("                   $($c.p)") -ForegroundColor DarkGray
        Write-Host ("                   $($_.Exception.Message)") -ForegroundColor Yellow
        $broken += $c.p

        $lines = Get-Content $c.p
        Write-Host ""
        Write-Host "  last lines of the file:" -ForegroundColor DarkGray
        $start = [Math]::Max(0, $lines.Count - 8)
        for ($i = $start; $i -lt $lines.Count; $i++) {
            Write-Host ("    {0,4}  {1}" -f ($i + 1), $lines[$i]) -ForegroundColor DarkGray
        }
        Write-Host ("    total lines: {0}" -f $lines.Count) -ForegroundColor DarkGray
        Write-Host ""
    }
}

Write-Host ""
if (-not $broken) {
    Write-Host "  Every settings file present is valid JSON." -ForegroundColor Green
    Write-Host "  If Windows Terminal still complains, it is reading one this does not" -ForegroundColor Yellow
    Write-Host "  know about. In Windows Terminal press Ctrl+, then 'Open JSON file'" -ForegroundColor Yellow
    Write-Host "  and note the path it opens." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

if (-not $Fix) {
    Write-Host "  Re-run with -Fix to move the broken file aside, keeping a copy," -ForegroundColor Yellow
    Write-Host "  so Windows Terminal writes a fresh one." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

foreach ($p in $broken) {
    $aside = "$p.broken-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Move-Item $p $aside -Force
    Write-Host "  moved to $(Split-Path $aside -Leaf)" -ForegroundColor Green
}
Write-Host ""
Write-Host "  Close every Windows Terminal window and open a new one." -ForegroundColor White
Write-Host "  The error should be gone. Then re-run the CYC installer with -Force" -ForegroundColor DarkGray
Write-Host "  to apply the colours." -ForegroundColor DarkGray
Write-Host ""
