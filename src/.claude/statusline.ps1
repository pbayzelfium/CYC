# ---------------------------------------------------------------------------
#  Claude Code status line
#  Receives session JSON on stdin, prints two coloured rows.
#  Uses only widely-supported Unicode (no Nerd Font glyphs) so it renders the
#  same in Windows Terminal, VS Code and Cursor.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $d = $raw | ConvertFrom-Json } catch { exit 0 }

# --- palette -----------------------------------------------------------------
# Follows whichever terminal theme is active, read from the same palettes.json
# that generates the prompt variants. Falls back to Catppuccin Mocha.
function Hex { param([string]$h)
    $h = $h.TrimStart('#')
    "$([char]27)[38;2;$([Convert]::ToInt32($h.Substring(0,2),16));$([Convert]::ToInt32($h.Substring(2,2),16));$([Convert]::ToInt32($h.Substring(4,2),16))m"
}

$pal = [pscustomobject]@{
    os='#cba6f7'; path='#89b4fa'; gitClean='#a6e3a1'; gitDirty='#f9e2af'
    danger='#f38ba8'; ahead='#fab387'; python='#74c7ec'; node='#94e2d5'; dim='#585b70'
}
try {
    $all = Get-Content (Join-Path $HOME '.oh-my-posh\palettes.json') -Raw | ConvertFrom-Json
    $hit = $null

    # 1. a paired prompt variant is active -> use its palette
    $active = Join-Path $HOME '.oh-my-posh\active-theme.txt'
    if (Test-Path $active) {
        $leaf = Split-Path ((Get-Content $active -Raw).Trim()) -Leaf
        if ($leaf -match '^cyc-(.+)\.omp\.json$' -and
            $all.PSObject.Properties.Name -contains $Matches[1]) { $hit = $all.($Matches[1]) }
    }

    # 2. otherwise (a stock prompt design is active) follow the window's scheme,
    #    so the bar still matches the background it is drawn on
    if (-not $hit) {
        $wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if (Test-Path $wt) {
            $scheme = (Get-Content $wt -Raw | ConvertFrom-Json).profiles.defaults.colorScheme
            foreach ($p in $all.PSObject.Properties) {
                if ($p.Name -notlike '_*' -and $p.Value.scheme -eq $scheme) { $hit = $p.Value; break }
            }
        }
    }

    if ($hit) { $pal = $hit }
} catch { }

$R      = "$([char]27)[0m"
$Dim    = Hex $pal.dim        # separators
$Mauve  = Hex $pal.os         # model
$Blue   = Hex $pal.path       # directory
$Green  = Hex $pal.gitClean   # clean / healthy
$Yellow = Hex $pal.gitDirty   # dirty / warming
$Peach  = Hex $pal.ahead      # cost
$Red    = Hex $pal.danger     # danger
$Teal   = Hex $pal.node       # rate limit
$Sky    = Hex $pal.python     # misc

$sep = "$Dim  ·  $R"

# ---------------------------------------------------------------------------
#  Row 1 : model  ·  directory  ·  git  ·  PR
# ---------------------------------------------------------------------------
$one = [System.Collections.Generic.List[string]]::new()

# model (+ effort, + fast mode)
$model = $d.model.display_name
if ($model) {
    $m = "$Mauve$model$R"
    if ($d.effort.level -and $d.effort.level -ne 'medium') { $m += "$Dim/$($d.effort.level)$R" }
    if ($d.fast_mode) { $m += "$Yellow ⚡$R" }
    $one.Add($m)
}

# directory
$cwd = if ($d.workspace.current_dir) { $d.workspace.current_dir } else { $d.cwd }
if ($cwd) {
    $leaf = Split-Path $cwd -Leaf
    if (-not $leaf) { $leaf = $cwd }
    $one.Add("$Blue$leaf$R")
}

# git — cached for 5s, untracked files skipped (they make status slow)
if ($cwd -and (Test-Path $cwd)) {
    $key   = [BitConverter]::ToString([System.Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes($cwd))).Replace('-','')
    $cache = Join-Path $env:TEMP "cc-sl-git-$key.txt"
    $git   = $null

    if ((Test-Path $cache) -and ((Get-Date) - (Get-Item $cache).LastWriteTime).TotalSeconds -lt 5) {
        $git = Get-Content $cache -Raw
    } else {
        Push-Location $cwd
        $branch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $branch) {
            $porcelain = & git status --porcelain --untracked-files=no 2>$null
            $changed   = if ($porcelain) { @($porcelain).Count } else { 0 }
            $ab        = & git rev-list --left-right --count '@{upstream}...HEAD' 2>$null
            $behind = 0; $ahead = 0
            if ($ab -match '^\s*(\d+)\s+(\d+)') { $behind = [int]$Matches[1]; $ahead = [int]$Matches[2] }
            $git = "$branch`t$changed`t$ahead`t$behind"
        } else { $git = '' }
        Pop-Location
        Set-Content -Path $cache -Value $git -NoNewline
    }

    if ($git) {
        $p = $git -split "`t"
        $branch = $p[0]; $changed = [int]$p[1]; $ahead = [int]$p[2]; $behind = [int]$p[3]
        $col = if ($changed -gt 0) { $Yellow } else { $Green }
        $g = "$col⎇ $branch$R"
        if ($changed -gt 0) { $g += "$Yellow ●$changed$R" }
        if ($ahead  -gt 0) { $g += "$Sky ↑$ahead$R" }
        if ($behind -gt 0) { $g += "$Peach ↓$behind$R" }
        $one.Add($g)
    }
}

# open pull request
if ($d.pr.number) {
    $prCol = switch ($d.pr.review_state) {
        'approved'          { $Green }
        'changes_requested' { $Red }
        'draft'             { $Dim }
        default             { $Sky }
    }
    $one.Add("$prCol#$($d.pr.number)$R")
}

# non-default output style
if ($d.output_style.name -and $d.output_style.name -ne 'default') {
    $one.Add("$Dim$($d.output_style.name)$R")
}

# ---------------------------------------------------------------------------
#  Row 2 : context bar  ·  cost  ·  elapsed  ·  rate limit  ·  diff
# ---------------------------------------------------------------------------
$two = [System.Collections.Generic.List[string]]::new()

# context window bar
$pct = $d.context_window.used_percentage
if ($null -ne $pct) {
    $pct   = [double]$pct
    $width = 12
    $fill  = [Math]::Min($width, [Math]::Max(0, [int][Math]::Round($pct / 100 * $width)))
    $barCol = if ($pct -ge 85) { $Red } elseif ($pct -ge 60) { $Yellow } else { $Green }
    $bar = "$barCol$('█' * $fill)$Dim$('░' * ($width - $fill))$R"

    $used = $d.context_window.total_input_tokens
    $size = $d.context_window.context_window_size
    $tok  = ''
    if ($used -and $size) {
        $tok = "$Dim $([Math]::Round($used / 1000))k/$([Math]::Round($size / 1000))k$R"
    }
    $two.Add("$bar $barCol$([int]$pct)%$R$tok")
}

# session cost
if ($null -ne $d.cost.total_cost_usd) {
    $two.Add("$Peach`$$('{0:N2}' -f $d.cost.total_cost_usd)$R")
}

# elapsed wall-clock
if ($d.cost.total_duration_ms) {
    $ms = [double]$d.cost.total_duration_ms
    $t  = [TimeSpan]::FromMilliseconds($ms)
    $el = if ($t.TotalHours -ge 1) { '{0}h{1:00}m' -f [int]$t.TotalHours, $t.Minutes }
          elseif ($t.TotalMinutes -ge 1) { '{0}m' -f [int]$t.TotalMinutes }
          else { '{0}s' -f [int]$t.TotalSeconds }
    $two.Add("$Dim$el$R")
}

# lines changed this session
$add = [int]$d.cost.total_lines_added
$del = [int]$d.cost.total_lines_removed
if ($add -gt 0 -or $del -gt 0) {
    $two.Add("$Green+$add$R$Dim/$R$Red-$del$R")
}

# 5-hour rate limit window
$rl = $d.rate_limits.five_hour.used_percentage
if ($null -ne $rl) {
    $rlCol = if ($rl -ge 80) { $Red } elseif ($rl -ge 50) { $Yellow } else { $Teal }
    $s = "$Dim 5h $R$rlCol$([int]$rl)%$R"
    if ($d.rate_limits.five_hour.resets_at) {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$d.rate_limits.five_hour.resets_at).ToLocalTime()
        $left  = $reset - (Get-Date)
        if ($left.TotalMinutes -gt 0) {
            $lt = if ($left.TotalHours -ge 1) { '{0}h{1:00}m' -f [int]$left.TotalHours, $left.Minutes }
                  else { '{0}m' -f [int]$left.TotalMinutes }
            $s += "$Dim ($lt)$R"
        }
    }
    $two.Add($s)
}

# ---------------------------------------------------------------------------
if ($one.Count) { [Console]::Out.WriteLine(($one -join $sep)) }
if ($two.Count) { [Console]::Out.WriteLine(($two -join $sep)) }
