<#
  Keeping CYC current.

  Checks a six-byte VERSION file against the one written at install time. The
  check goes to api.github.com rather than raw.githubusercontent, because raw is
  served through a CDN that holds each file for minutes - and that window falls
  exactly when someone presses "check for updates", just after a release. Raw
  stays as the fallback for when the API is rate limited.

  What it will not do is take anything away. An update replaces the program -
  the status line, the switching functions, the catalogue - and leaves
  everything you chose alone: your theme, your prompt design, the brightness you
  settled on, the themes you installed, and any edit you made to the prompt
  config. The installer does the preserving; this decides when to call it. The
  one case where your setting has to move is when the thing it points at is gone
  from the new build, and then it says so rather than quietly landing you
  somewhere else.

  It checks when the catalogue is opened, and when the button is pressed. It
  does not check when a terminal starts: opening a shell is not launching this
  program, and a prompt should not cost a network call or begin an install.

  It says all of that on one line. Progress is shown as a bar that fills while
  the work actually runs, and the line is erased when it finishes, leaving a
  single sentence behind.
#>

$script:CycRoot    = Join-Path $HOME '.oh-my-posh'
$script:CycVerFile = Join-Path $script:CycRoot 'version.txt'
$script:CycOptOut  = Join-Path $script:CycRoot 'no-auto-update'
$script:CycRepo    = 'https://raw.githubusercontent.com/pbayzelfium/CYC/main'
$script:CycApi     = 'https://api.github.com/repos/pbayzelfium/CYC/contents/VERSION?ref=main'

# --- one line, pastel olive -------------------------------------------------

$script:CycInk  = "$([char]27)[38;2;163;177;138m"  # pastel olive, the filled bar
$script:CycDim  = "$([char]27)[38;2;104;114;88m"   # the same hue, dimmed
$script:CycOff  = "$([char]27)[0m"

function Test-CycCanAnimate {
    <#  Redirected output has no cursor to move, and a line redrawn with \r
        into a file or a pipe just concatenates into nonsense.  #>
    -not [Console]::IsOutputRedirected -and $Host.Name -eq 'ConsoleHost'
}

function Get-CycWidth {
    <#  [Console]::WindowWidth throws "the handle is invalid" wherever there is
        no console buffer behind the process. Never let a cosmetic detail be the
        thing that raises an error in someone's terminal.  #>
    try { $w = [Console]::WindowWidth; if ($w -gt 20) { return $w } } catch { }
    80
}

function Write-CycBar {
    <#  .SYNOPSIS Draw the whole thing on one line, in place. #>
    param([string]$Label, [double]$Percent, [int]$Width = 24)

    if (-not (Test-CycCanAnimate)) { return }
    $p    = [Math]::Max(0, [Math]::Min(100, $Percent))
    $fill = [int][Math]::Round($Width * $p / 100)
    $bar  = ([string][char]0x2588) * $fill + ([string][char]0x2591) * ($Width - $fill)
    $line = "  {0}{1,-21}{2}{3}{4}{5} {6,3}%{7}" -f `
        $script:CycDim, $Label, $script:CycOff,
        $script:CycInk, $bar, $script:CycOff, [int]$p, $script:CycOff
    try { [Console]::Write("`r$line") } catch { }
}

function Clear-CycLine {
    if (-not (Test-CycCanAnimate)) { return }
    try { [Console]::Write("`r" + (' ' * ((Get-CycWidth) - 1)) + "`r") } catch { }
}

function Write-CycLine {
    <#  The one sentence left behind when the bar is gone. #>
    param([string]$Text, [switch]$Dim)
    Clear-CycLine
    $c = if ($Dim) { $script:CycDim } else { $script:CycInk }
    if (Test-CycCanAnimate) { Write-Host "  $c$Text$($script:CycOff)" }
    else { Write-Host "  $Text" }
}

function Wait-CycBar {
    <#  .SYNOPSIS Fill toward $To while $IsDone is false, and only reach it when
        the work is actually finished.

        .DESCRIPTION
        The bar approaches its target asymptotically, so it never claims to be
        further along than it is: a slow download sits at 80-something rather
        than hitting 100 and waiting there, which is the thing that makes a
        progress bar feel like a lie.  #>
    param(
        [string]$Label,
        [scriptblock]$IsDone,
        [double]$From = 0,
        [double]$To = 100,
        [double]$Expect = 1.5
    )
    $t0 = Get-Date
    Write-CycBar $Label $From
    while (-not (& $IsDone)) {
        $elapsed = ((Get-Date) - $t0).TotalSeconds
        $frac = 1 - [Math]::Exp(-$elapsed / [Math]::Max(0.2, $Expect))
        Write-CycBar $Label ($From + ($To - $From) * $frac)
        Start-Sleep -Milliseconds 55
    }
    Write-CycBar $Label $To
}

# --- what is installed, and what is published -------------------------------

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

        .PARAMETER ShowProgress
        Draw the bar while the request is in flight. The request runs as a real
        task and the bar is driven by it, so what fills the line is the work and
        not a timer pretending to be one.

        Silence is the right answer for a failed check: no network, a proxy, a
        captive portal in a hotel. None of those are the user's problem to hear
        about when a terminal opens.  #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$ShowProgress)

    $client = $null
    try {
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [timespan]::FromSeconds(8)
        $client.DefaultRequestHeaders.Add('User-Agent', 'cyc-update-check')
        $client.DefaultRequestHeaders.Add('Cache-Control', 'no-cache')

        # The API first: it is not cached, so a release is visible the moment it
        # lands rather than several minutes later.
        $task = $client.GetStringAsync($script:CycApi)
        if ($ShowProgress) { Wait-CycBar 'checking for updates' { $task.IsCompleted } 0 100 0.7 }
        else { $null = $task.Wait(8000) }

        if (-not $task.IsFaulted -and $task.IsCompletedSuccessfully) {
            $json = $task.Result | ConvertFrom-Json
            $v = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($json.content)) -replace '[^\d\.]', '').Trim()
            if ($v -match '^\d+(\.\d+){0,3}$') { return $v }
        }

        # Rate limited or blocked: raw still answers, just a few minutes late.
        $task2 = $client.GetStringAsync("$script:CycRepo/VERSION")
        if ($ShowProgress) { Wait-CycBar 'checking for updates' { $task2.IsCompleted } 0 100 0.7 }
        else { $null = $task2.Wait(8000) }
        if (-not $task2.IsFaulted -and $task2.IsCompletedSuccessfully) {
            $v = ($task2.Result -replace '[^\d\.]', '').Trim()
            if ($v -match '^\d+(\.\d+){0,3}$') { return $v }
        }
    } catch {
    } finally {
        if ($client) { $client.Dispose() }
    }
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
        .PARAMETER Quiet         Do not print; just return the object.
        .PARAMETER ShowProgress  Draw the bar while checking.  #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$Quiet, [switch]$ShowProgress)

    $current = Get-CycVersion
    $latest  = Get-CycLatest -ShowProgress:$ShowProgress

    $result = [pscustomobject]@{
        Current   = $current
        Latest    = $latest
        Available = ($null -ne $latest) -and ((Compare-CycVersion $current $latest) -lt 0)
        Reachable = ($null -ne $latest)
    }

    if (-not $Quiet) {
        if (-not $result.Reachable)    { Write-CycLine "CYC $current - could not reach the update server" -Dim }
        elseif ($result.Available)     { Write-CycLine "CYC $current - update available: $($result.Latest). Run Update-Cyc" }
        else                           { Write-CycLine "CYC $current - up to date" -Dim }
    }
    $result
}

function Update-Cyc {
    <#  .SYNOPSIS Fetch the current build and install it over this one.

        .DESCRIPTION
        Everything you set up is kept: theme, prompt design, brightness and
        saturation, the themes you installed, and your own edits to the prompt
        config. Only the program files are replaced.

        The installer's own output is kept out of the way and written to a log,
        so a routine update is one line. A failure says where the log is - quiet
        on success, loud on failure, never quiet on failure.

        .PARAMETER Force   Reinstall even when already current.
        .PARAMETER NoOpen  Do not open the catalogue when it finishes.
        .PARAMETER Known   A result from Test-CycUpdate, when the caller has
                           already asked. Saves a second request and a second
                           bar for the same question.  #>
    [CmdletBinding(PositionalBinding = $false)]
    param([switch]$Force, [switch]$NoOpen, $Known)

    $check = if ($Known) { $Known } else { Test-CycUpdate -Quiet -ShowProgress }
    if (-not $check.Reachable) {
        Write-CycLine "CYC $($check.Current) - could not reach the update server" -Dim
        return
    }
    if (-not $check.Available -and -not $Force) {
        Write-CycLine "CYC $($check.Current) - up to date" -Dim
        return
    }

    $installer = Join-Path $env:TEMP 'cyc-install.ps1'
    $log       = Join-Path $env:TEMP 'cyc-update.log'
    $errLog    = Join-Path $env:TEMP 'cyc-update.err.log'

    try {
        $client = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [timespan]::FromSeconds(90)
        $client.DefaultRequestHeaders.Add('User-Agent', 'cyc-update-check')
        $client.DefaultRequestHeaders.Add('Cache-Control', 'no-cache')
        $task = $client.GetStringAsync("$script:CycRepo/install.ps1")
        Wait-CycBar "downloading $($check.Latest)" { $task.IsCompleted } 0 100 2.5
        if ($task.IsFaulted) { throw $task.Exception.GetBaseException().Message }
        [IO.File]::WriteAllText($installer, $task.Result)
        $client.Dispose()
    } catch {
        Write-CycLine "CYC - could not download the update: $($_.Exception.Message)" -Dim
        return
    }

    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Update')
    if ($NoOpen) { $argv += '-NoOpen' }

    # A separate process, because this one is running the profile being replaced.
    $exe = (Get-Process -Id $PID).Path
    $proc = Start-Process $exe -ArgumentList $argv -PassThru -NoNewWindow `
                -RedirectStandardOutput $log -RedirectStandardError $errLog
    Wait-CycBar "installing $($check.Latest)" { $proc.HasExited } 0 100 9

    if ($proc.ExitCode -eq 0) {
        Write-CycLine "CYC updated $($check.Current) -> $($check.Latest). Open a new terminal to pick it up."
    } else {
        Write-CycLine "CYC - the update did not finish (exit $($proc.ExitCode)). Nothing you set up was changed." -Dim
        Write-CycLine "      the installer's output is in $log" -Dim
    }
}

# No alias here. 'update-cyc' and 'Update-Cyc' are the same name to PowerShell,
# and an alias outranks a function, so aliasing one to the other makes the name
# resolve to itself and stop working entirely.
