<#
  Keeping CYC current.

  Checks a six-byte VERSION file in the repo against the one written at install
  time. That is the whole check - no API, no token, no rate limit - so it can
  run on a session start without being felt.

  What it will not do is take anything away from you. An update replaces the
  program - the status line, the switching functions, the catalogue - and
  leaves everything you chose alone: your theme, your prompt design, the
  brightness you settled on, the themes you installed, and any edit you made to
  the prompt config. The installer does the preserving; this decides when to
  call it. The one case where your setting has to move is when the thing it
  points at is gone from the new build, and then it says so rather than quietly
  landing you somewhere else.
#>

$script:CycRoot    = Join-Path $HOME '.oh-my-posh'
$script:CycVerFile = Join-Path $script:CycRoot 'version.txt'
$script:CycStamp   = Join-Path $script:CycRoot 'last-update-check.txt'
$script:CycOptOut  = Join-Path $script:CycRoot 'no-auto-update'
$script:CycRepo    = 'https://raw.githubusercontent.com/pbayzelfium/CYC/main'

function Get-CycVersion {
    <#  .SYNOPSIS What is installed here. #>
    if (Test-Path $script:CycVerFile) {
        $v = (Get-Content $script:CycVerFile -Raw).Trim()
        if ($v) { return $v }
    }
    # Installed before versions existed, so anything published is newer.
    '0.0.0'
}

function Get-CycLatest {
    <#  .SYNOPSIS What the repo has, or $null if it cannot be reached.

        Silence is the right answer for a failed check: no network, a proxy, a
        captive portal on a hotel wifi. None of those are the user's problem to
        hear about on a session start.  #>
    try {
        $ProgressPreference = 'SilentlyContinue'
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 `
                -Uri "$script:CycRepo/VERSION" `
                -Headers @{ 'Cache-Control' = 'no-cache' }
        $v = ($r.Content -replace '[^\d\.]', '').Trim()
        if ($v -match '^\d+(\.\d+){0,3}$') { return $v }
    } catch { }
    $null
}

function Compare-CycVersion {
    <#  .SYNOPSIS  -1 / 0 / 1, comparing as versions rather than as text, so
        1.10.0 sorts after 1.9.0 instead of before it. #>
    param([string]$A, [string]$B)
    $x = $null; $y = $null
    if ([version]::TryParse($A, [ref]$x) -and [version]::TryParse($B, [ref]$y)) {
        return $x.CompareTo($y)
    }
    [string]::Compare($A, $B, $true)
}

function Test-CycUpdate {
    <#  .SYNOPSIS Is there a newer build? Returns the comparison either way.
        .PARAMETER Quiet  Do not print; just return the object. #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$Quiet)

    $current = Get-CycVersion
    $latest  = Get-CycLatest

    $result = [pscustomobject]@{
        Current   = $current
        Latest    = $latest
        Available = ($null -ne $latest) -and ((Compare-CycVersion $current $latest) -lt 0)
        Reachable = ($null -ne $latest)
    }

    if (-not $Quiet) {
        if (-not $result.Reachable) {
            Write-Host "  Could not reach the update server. You are on $current." -ForegroundColor Yellow
        } elseif ($result.Available) {
            Write-Host ""
            Write-Host "  An update is available: $current -> $latest" -ForegroundColor Cyan
            Write-Host "  Run: Update-Cyc" -ForegroundColor DarkGray
        } else {
            Write-Host "  CYC is up to date ($current)." -ForegroundColor Green
        }
    }
    $result
}

function Update-Cyc {
    <#  .SYNOPSIS Fetch the current build and install it over this one.

        .DESCRIPTION
        Everything you set up is kept: theme, prompt design, brightness and
        saturation, the themes you installed, and your own edits to the prompt
        config. Only the program files are replaced.

        .PARAMETER Force   Reinstall even when already current.
        .PARAMETER NoOpen  Do not open the catalogue when it finishes.  #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$Force, [switch]$NoOpen)

    $check = Test-CycUpdate -Quiet
    if (-not $check.Reachable) {
        Write-Host ""
        Write-Host "  Could not reach the update server - check your connection." -ForegroundColor Yellow
        Write-Host ""
        return
    }
    if (-not $check.Available -and -not $Force) {
        Write-Host ""
        Write-Host "  CYC is up to date ($($check.Current))." -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  We detected an update: $($check.Current) -> $($check.Latest)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Your theme, prompt design, colour adjustments and installed" -ForegroundColor DarkGray
    Write-Host "  themes are kept. Only the program itself is replaced." -ForegroundColor DarkGray
    Write-Host ""

    $installer = Join-Path $env:TEMP 'cyc-install.ps1'
    try {
        Write-Host "  downloading..." -ForegroundColor DarkGray
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 `
            -Uri "$script:CycRepo/install.ps1" -OutFile $installer
    } catch {
        Write-Host "  Could not download the update: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Update')
    if ($NoOpen) { $argv += '-NoOpen' }

    # A separate process, because this one is running the very profile the
    # update rewrites.
    $exe = (Get-Process -Id $PID).Path
    & $exe @argv
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        Write-Host ""
        Write-Host "  Updated to $($check.Latest)." -ForegroundColor Green
        Write-Host "  Open a new terminal to pick up the new prompt." -ForegroundColor DarkGray
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  The update did not finish cleanly (exit $code)." -ForegroundColor Yellow
        Write-Host "  Nothing you set up was changed." -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Invoke-CycUpdateCheck {
    <#  .SYNOPSIS The session-start check.

        .DESCRIPTION
        Runs at most once a day, and only in a real interactive console - never
        while something is being piped or scripted, where a surprise install
        would be indefensible. One window takes the lock, so opening six tabs
        does not start six updates.

        Turn it off by creating the file no-auto-update in ~/.oh-my-posh.  #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$Force)

    if (-not $Force) {
        if (Test-Path $script:CycOptOut) { return }
        if ($Host.Name -ne 'ConsoleHost') { return }
        if (-not [Environment]::UserInteractive) { return }

        # Once a day is often enough for a themer.
        if (Test-Path $script:CycStamp) {
            try {
                $last = [datetime]::Parse((Get-Content $script:CycStamp -Raw).Trim())
                if ((Get-Date) - $last -lt [timespan]::FromHours(24)) { return }
            } catch { }
        }
    }

    # One window only. CreateNew fails if the file exists, which is the point:
    # it is a lock, not a flag.
    $lock = Join-Path $script:CycRoot 'update.lock'
    $fs = $null
    try {
        $fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    } catch {
        # Someone else holds it - unless it is stale, left by a window that was
        # closed mid-check.
        try {
            if ((Get-Date) - (Get-Item $lock).LastWriteTime -gt [timespan]::FromMinutes(10)) {
                Remove-Item $lock -Force -EA SilentlyContinue
            }
        } catch { }
        return
    }

    try {
        Set-Content $script:CycStamp (Get-Date -Format 'o') -Encoding UTF8
        $check = Test-CycUpdate -Quiet
        if (-not $check.Available) { return }

        Write-Host ""
        Write-Host "  We detected an update: $($check.Current) -> $($check.Latest)" -ForegroundColor Cyan
        Write-Host "  Installing it now. Nothing you set up will change." -ForegroundColor DarkGray

        # The catalogue opens at the end of the install, which is the point of
        # updating: you see what is new.
        Update-Cyc
    } catch {
        # An update check must never be the reason a terminal fails to open.
    } finally {
        if ($fs) { $fs.Dispose() }
        Remove-Item $lock -Force -EA SilentlyContinue
    }
}

Set-Alias update-cyc Update-Cyc
