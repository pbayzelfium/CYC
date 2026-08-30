# UTF-8 out, always. Without a console attached (piped or redirected) Windows
# falls back to a legacy code page and mangles box-drawing and Nerd Font glyphs.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$OmpRoot    = Join-Path $HOME '.oh-my-posh'
$OmpThemes  = Join-Path $OmpRoot 'themes'
$OmpActive  = Join-Path $OmpRoot 'active-theme.txt'
$OmpDefault = Join-Path $OmpRoot 'cyc.omp.json'

$env:POSH_THEMES_PATH = $OmpThemes

# --- prompt ----------------------------------------------------------------
$theme = if (Test-Path $OmpActive) { (Get-Content $OmpActive -Raw).Trim() } else { $OmpDefault }
if ([string]::IsNullOrWhiteSpace($theme) -or -not (Test-Path $theme)) { $theme = $OmpDefault }
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $theme | Invoke-Expression
}

# --- file / folder glyphs in ls --------------------------------------------
Import-Module Terminal-Icons -ErrorAction SilentlyContinue

# --- command line editing ---------------------------------------------------
if ((Get-Module -ListAvailable PSReadLine) -and $Host.Name -eq 'ConsoleHost') {
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -ShowToolTips

    # Inline + list predictions need a real interactive console; skip when redirected.
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
    } catch { }

    Set-PSReadLineOption -Colors @{
        Command                = '#89b4fa'
        Parameter              = '#cba6f7'
        Operator               = '#94e2d5'
        Variable               = '#f9e2af'
        String                 = '#a6e3a1'
        Number                 = '#fab387'
        Type                   = '#74c7ec'
        Comment                = '#585b70'
        Keyword                = '#f5c2e7'
        Error                  = '#f38ba8'
        InlinePrediction       = '#45475a'
        ListPrediction         = '#6c7086'
        Selection              = "`e[7m"
    }

    # Up/Down search history by what you have already typed
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    # Tab shows a selectable menu instead of cycling blindly
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    # Right arrow / Ctrl+F accept the greyed-out suggestion
    Set-PSReadLineKeyHandler -Key Ctrl+f    -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Alt+Enter -Function AddLine
}

# --- theme browsing ---------------------------------------------------------

function Get-PoshTheme {
    <#  Which theme is active right now.  #>
    if (Test-Path $script:OmpActive) { (Get-Content $script:OmpActive -Raw).Trim() } else { $script:OmpDefault }
}

function Get-PoshThemeList {
    <#  Names of every installed theme, plus the custom one. Every name returned
        here is accepted verbatim by Set-PoshTheme.  #>
    $names = @('cyc')
    $names += (Get-ChildItem $script:OmpThemes -Filter '*.omp.json' -ErrorAction SilentlyContinue |
               ForEach-Object { $_.Name -replace '\.omp\.json$', '' } | Sort-Object)
    $names
}

function Resolve-PoshTheme {
    <#  Accepts an alias, a paired variant (cyc-<slug>, which lives in the
        oh-my-posh root), a stock design (in themes\), or a literal path.  #>
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -in @('cyc', 'default', 'custom')) { return $script:OmpDefault }
    foreach ($p in @(
        (Join-Path $script:OmpRoot   "$Name.omp.json"),
        (Join-Path $script:OmpThemes "$Name.omp.json")
    )) { if (Test-Path $p) { return $p } }
    if (Test-Path $Name) { return (Resolve-Path $Name).Path }
    $null
}

function Show-PoshTheme {
    <#  Render one theme's prompt without applying it.  #>
    param([Parameter(Mandatory)][string]$Name)
    $p = Resolve-PoshTheme $Name
    if (-not $p) { Write-Host "No theme named '$Name'. Try: Get-PoshThemeList" -ForegroundColor Red; return }
    oh-my-posh print primary --config $p --shell pwsh
    Write-Host ''
}

function Show-PoshThemeGallery {
    <#  Print every installed theme's prompt, so you can pick one by eye.
        -Filter narrows the list, e.g.  Show-PoshThemeGallery -Filter cat  #>
    param([string]$Filter = '')
    $files = @(Get-Item $script:OmpDefault) +
             @(Get-ChildItem $script:OmpThemes -Filter '*.omp.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($Filter) { $files = $files | Where-Object { $_.Name -like "*$Filter*" } }
    foreach ($f in $files) {
        $name = $f.Name -replace '\.omp\.json$', ''
        Write-Host ''
        Write-Host ("  " + $name) -ForegroundColor Cyan
        Write-Host ("  " + ('-' * [Math]::Max(4, $name.Length))) -ForegroundColor DarkGray
        oh-my-posh print primary --config $f.FullName --shell pwsh
        Write-Host ''
    }
    Write-Host ''
    Write-Host "  Apply one with:  Set-PoshTheme <name>" -ForegroundColor Yellow
}

function Set-PoshTheme {
    <#  Apply a prompt design now and remember it for future sessions.

        By default the design is recoloured to the active terminal theme, so the
        prompt never clashes with the window. -Original keeps the colours its
        author chose — worth seeing, since recolouring collapses a design's
        palette onto the theme's smaller one.  #>
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$Original,
        [double]$Brightness = 0,
        [double]$Saturation = 0
    )
    $p = Resolve-PoshTheme $Name
    if (-not $p) { Write-Host "No design named '$Name'. Try: Get-PoshThemeList" -ForegroundColor Red; return }

    $base = (Split-Path $p -Leaf) -replace '\.omp\.json$', '' -replace '^cyc-.*$', 'cyc'
    Set-Content -Path $script:OmpBase -Value $base -Encoding UTF8
    Set-Content -Path $script:OmpAdjust -Value "$Brightness $Saturation" -Encoding UTF8

    $use = $p
    $note = ' (original colours)'
    if (-not $Original) {
        $slug = Get-ActiveThemeSlug
        $paired = New-PairedPrompt -Design $base -Slug $slug -Brightness $Brightness -Saturation $Saturation
        if ($paired -and (Test-Path $paired)) {
            $use = $paired
            $note = " paired to $slug"
            if ($Brightness -or $Saturation) { $note += " (brightness $Brightness, saturation $Saturation)" }
        }
    }

    Set-Content -Path $script:OmpActive -Value $use -Encoding UTF8
    oh-my-posh init pwsh --config $use | Invoke-Expression
    Write-Host "Prompt set to $base$note" -ForegroundColor Green
}

function Show-Catalogue {
    <#  Open the theme catalogue in a browser: every prompt design rendered
        against the same repo, with filters, full previews, and brightness and
        saturation sliders whose values are carried into the command you copy.  #>
    $page = Join-Path $script:OmpRoot 'catalogue\theme-catalogue.html'
    if (-not (Test-Path $page)) {
        Write-Host "No catalogue found at $page" -ForegroundColor Red
        Write-Host "Rebuild it with: pwsh -NoProfile -File `"$(Join-Path $script:OmpRoot 'catalogue\rebuild.ps1')`"" -ForegroundColor Yellow
        return
    }
    Start-Process $page
    Write-Host "Opened $page" -ForegroundColor Green
}
Set-Alias catalogue Show-Catalogue

Set-Alias themes  Get-PoshThemeList
Set-Alias gallery Show-PoshThemeGallery

# --- matched terminal scheme + prompt ---------------------------------------

$script:WtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

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

function Get-ThemePalettes {
    <#  The palette table. Single source of truth for every paired theme —
        the prompt variants, the Claude Code status line and this switcher
        all read it, so a new theme is added in one place.  #>
    try {
        $j = Get-Content (Join-Path $script:OmpRoot 'palettes.json') -Raw | ConvertFrom-Json
        $t = [ordered]@{}
        foreach ($p in $j.PSObject.Properties) { if ($p.Name -notlike '_*') { $t[$p.Name] = $p.Value.scheme } }
        $t
    } catch { [ordered]@{} }
}

$script:OmpBase = Join-Path $OmpRoot 'active-design.txt'

function Get-BaseDesign {
    <#  The prompt design in use, before it was recoloured to the theme.  #>
    if (Test-Path $script:OmpBase) { (Get-Content $script:OmpBase -Raw).Trim() } else { 'cyc' }
}

function Get-ActiveThemeSlug {
    $scheme = try { (Get-Content $script:WtSettings -Raw | ConvertFrom-Json).profiles.defaults.colorScheme } catch { $null }
    $pairs = Get-ThemePalettes
    foreach ($k in $pairs.Keys) { if ($pairs[$k] -eq $scheme) { return $k } }
    @($pairs.Keys)[0]
}

$script:OmpAdjust = Join-Path $OmpRoot 'active-adjust.txt'

function Get-PromptAdjust {
    <#  The brightness / saturation tweak in force, as [brightness, saturation].  #>
    if (Test-Path $script:OmpAdjust) {
        $p = (Get-Content $script:OmpAdjust -Raw).Trim() -split '\s+'
        if ($p.Count -ge 2) { return @([double]$p[0], [double]$p[1]) }
    }
    @(0, 0)
}

function Get-PythonPath {
    <#  Whichever Python is available, or $null.  #>
    $venv = Join-Path $script:OmpRoot 'catalogue\.venv\Scripts\python.exe'
    if (Test-Path $venv) { return $venv }
    foreach ($n in 'python', 'py') {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    $null
}

function New-PairedPrompt {
    <#  Recolour a design to a theme and return the generated config path.
        cyc's variants are pre-built, and are used directly when no
        brightness or saturation tweak is in force.  #>
    param(
        [Parameter(Mandatory)][string]$Design,
        [Parameter(Mandatory)][string]$Slug,
        [double]$Brightness = 0,
        [double]$Saturation = 0
    )
    if ($Design -in @('cyc', 'default', 'custom') -and -not $Brightness -and -not $Saturation) {
        return (Join-Path $script:OmpRoot "cyc-$Slug.omp.json")
    }
    $src = if ($Design -in @('cyc', 'default', 'custom')) { 'cyc' } else { $Design }
    $py = Get-PythonPath
    if (-not $py) { Write-Host 'Python not found - prompt recolouring needs it.' -ForegroundColor Red; return $null }
    $p = & $py (Join-Path $script:OmpRoot 'pair-prompt.py') $src $Slug $Brightness $Saturation 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host $p -ForegroundColor Red; return $null }
    ($p | Select-Object -Last 1).ToString().Trim()
}

function Get-TerminalTheme {
    <#  Which terminal scheme and prompt are active.  #>
    $scheme = try { (Get-Content $script:WtSettings -Raw | ConvertFrom-Json).profiles.defaults.colorScheme } catch { '(unreadable)' }
    [pscustomobject]@{ Scheme = $scheme; Prompt = (Split-Path (Get-PoshTheme) -Leaf) }
}

function Show-TerminalThemes {
    <#  Numbered menu of the paired themes with a live colour swatch — each row's
        accents are painted on that theme's own background, so you can pick by
        eye instead of by name.  #>
    $e   = [char]27
    $rst = "$e[0m"
    $rgb = { param($h, $layer)
        $h = $h.TrimStart('#')
        $r = [Convert]::ToInt32($h.Substring(0,2),16)
        $g = [Convert]::ToInt32($h.Substring(2,2),16)
        $b = [Convert]::ToInt32($h.Substring(4,2),16)
        "$e[$layer;2;$r;$g;$b" + "m"
    }

    $all = try { Get-Content (Join-Path $script:OmpRoot 'palettes.json') -Raw | ConvertFrom-Json } catch { $null }
    if (-not $all) { Write-Host "Cannot read palettes.json" -ForegroundColor Red; return }

    $cur = (Get-TerminalTheme).Scheme
    $i = 0
    Write-Host ""
    foreach ($p in $all.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }
        $i++
        $v = $p.Value
        $active = $v.scheme -eq $cur

        # swatch: the theme's background, carrying its six accent colours
        $sw = (& $rgb $v.bg 48) + '  '
        foreach ($c in @($v.os, $v.path, $v.gitClean, $v.gitDirty, $v.danger, $v.python)) {
            $sw += (& $rgb $c 38) + [char]0x2588 + [char]0x2588
        }
        $sw += (& $rgb $v.fg 38) + ' Aa ' + $rst

        $mark = if ($active) { "$e[38;2;166;227;161m>$rst" } else { ' ' }
        $name = if ($active) { "$e[38;2;166;227;161m$($p.Name)$rst" } else { $p.Name }
        $pad  = ' ' * [Math]::Max(1, 18 - $p.Name.Length)

        Write-Host ("  $mark $i. " + $sw + "  " + $name + $pad + "$e[38;2;127;132;156m$($v.scheme)$rst")
    }
    Write-Host ""
    Write-Host "  tt <number>  or  tt <name>" -ForegroundColor DarkGray
    Write-Host ""
}
Set-Alias tts Show-TerminalThemes

function Set-TerminalTheme {
    <#  Switch the Windows Terminal colour scheme AND the prompt palette together.
        Set-TerminalTheme gruvbox-dark        #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ArgumentCompleter({
            param($c, $p, $word)
            (Get-ThemePalettes).Keys | Where-Object { $_ -like "$word*" }
        })]
        [string]$Name
    )

    $pairs = Get-ThemePalettes

    # a bare number picks from the menu, so nothing has to be typed out
    if ($Name -match '^\d+$') {
        $idx = [int]$Name
        if ($idx -lt 1 -or $idx -gt $pairs.Count) {
            Write-Host "Pick 1-$($pairs.Count)." -ForegroundColor Red
            Show-TerminalThemes
            return
        }
        $Name = @($pairs.Keys)[$idx - 1]
    }
    # a unique prefix is enough: 'kana' -> 'kanagawa-wave'
    elseif (-not $pairs.Contains($Name)) {
        $hits = @($pairs.Keys | Where-Object { $_ -like "$Name*" })
        if ($hits.Count -eq 1) { $Name = $hits[0] }
    }

    if (-not $pairs.Contains($Name)) {
        Write-Host "No theme named '$Name'." -ForegroundColor Red
        Show-TerminalThemes
        return
    }

    $scheme = $pairs[$Name]

    # carry whatever design is in use across to the new theme, recoloured,
    # keeping any brightness / saturation tweak in force
    $base    = Get-BaseDesign
    $adj     = Get-PromptAdjust
    $variant = New-PairedPrompt -Design $base -Slug $Name -Brightness $adj[0] -Saturation $adj[1]

    if (-not $variant -or -not (Test-Path $variant)) {
        Write-Host "Could not build a prompt for '$base' on '$Name'." -ForegroundColor Red
        Write-Host "Rebuild the base variants with: pwsh -NoProfile -File `"$(Join-Path $script:OmpRoot 'build-variants.ps1')`"" -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path $script:WtSettings)) {
        Write-Host "Windows Terminal settings not found at $script:WtSettings" -ForegroundColor Red
        return
    }

    # terminal scheme
    try {
        Copy-Item $script:WtSettings "$script:WtSettings.bak" -Force
        $wt = Get-Content $script:WtSettings -Raw | ConvertFrom-Json
        if ($wt.schemes.name -notcontains $scheme) {
            Write-Host "Scheme '$scheme' is not defined in Windows Terminal settings." -ForegroundColor Red
            return
        }
        $wt.profiles.defaults.colorScheme = $scheme
        Save-JsonSafely -Object $wt -Path $script:WtSettings
    } catch {
        Write-Host "Could not update Windows Terminal settings: $_" -ForegroundColor Red
        return
    }

    # prompt palette
    Set-Content -Path $script:OmpActive -Value $variant -Encoding UTF8
    oh-my-posh init pwsh --config $variant | Invoke-Expression

    Write-Host ""
    Write-Host "  Terminal scheme -> $scheme" -ForegroundColor Green
    Write-Host "  Prompt          -> $base, recoloured to $Name" -ForegroundColor Green
    Write-Host "  The window repaints itself; a new tab if it does not." -ForegroundColor DarkGray
    Write-Host ""
}

Set-Alias tt Set-TerminalTheme

# Install-TerminalTheme / Find-TerminalTheme / Uninstall-TerminalTheme
$ttTools = Join-Path $OmpRoot 'theme-tools.ps1'
if (Test-Path $ttTools) { . $ttTools }

# Test-CycUpdate / Update-Cyc
$ttUpdate = Join-Path $OmpRoot 'cyc-update.ps1'
if (Test-Path $ttUpdate) {
    . $ttUpdate
    # Once a day, in an interactive console only. Everything it could go wrong
    # about - no network, a held lock, a slow server - it stays quiet about, so
    # the worst case is a terminal that opens exactly as it always does.
    Invoke-CycUpdateCheck
}

# --- small conveniences -----------------------------------------------------

function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

function ll { Get-ChildItem @args | Format-Table -AutoSize }
function la { Get-ChildItem -Force @args }

function which {
    param([Parameter(Mandatory)][string]$Name)
    (Get-Command $Name -ErrorAction SilentlyContinue).Source
}

function mkcd {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Location $Path
}

function reload { . $PROFILE }

# ---------------------------------------------------------------------------
