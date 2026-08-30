# Installing new terminal themes.
# Dot-sourced by the PowerShell 7 profile. Switching between installed themes
# lives in the profile itself (Set-TerminalTheme / Show-TerminalThemes).

$script:TT_Root      = Join-Path $HOME '.oh-my-posh'
$script:TT_Palettes  = Join-Path $script:TT_Root 'palettes.json'
$script:TT_Index     = Join-Path $script:TT_Root 'scheme-index.json'
$script:TT_Wt        = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$script:TT_Repo      = 'https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/windowsterminal'
$script:TT_Api       = 'https://api.github.com/repos/mbadolato/iTerm2-Color-Schemes/contents/windowsterminal'

# --- colour helpers ---------------------------------------------------------

function script:TT-Rgb { param([string]$h)
    $h = $h.TrimStart('#')
    ,@([Convert]::ToInt32($h.Substring(0,2),16),
       [Convert]::ToInt32($h.Substring(2,2),16),
       [Convert]::ToInt32($h.Substring(4,2),16))
}

function script:TT-Lum { param([string]$h)
    $c = (TT-Rgb $h) | ForEach-Object {
        $v = $_ / 255
        if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) }
    }
    0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]
}

# --- the catalogue of available schemes -------------------------------------

function Update-TerminalThemeIndex {
    <#  Refresh the cached list of installable scheme names.  #>
    # The contents API returns the whole directory in one response and ignores
    # per_page/page — asking for more pages just refetches the same list.
    $names = [System.Collections.Generic.List[string]]::new()
    try {
        $r = Invoke-RestMethod $script:TT_Api -Headers @{ 'User-Agent' = 'trinity-theme-tools' }
    } catch {
        Write-Host "Could not reach GitHub: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
    foreach ($f in $r) { if ($f.name -like '*.json') { $names.Add(($f.name -replace '\.json$', '')) } }

    $unique = @($names | Sort-Object -Unique)
    if ($unique.Count) {
        $unique | ConvertTo-Json | Set-Content $script:TT_Index -Encoding UTF8
        Write-Host "Indexed $($unique.Count) schemes." -ForegroundColor Green
    }
    $unique.Count
}

function Find-TerminalTheme {
    <#  Search installable schemes by name.  Find-TerminalTheme rose  #>
    param([string]$Query = '')
    if (-not (Test-Path $script:TT_Index)) {
        Write-Host "Building the scheme index (first run)..." -ForegroundColor DarkGray
        if ((Update-TerminalThemeIndex) -eq 0) { return }
    }
    $all = Get-Content $script:TT_Index -Raw | ConvertFrom-Json
    $hits = if ($Query) { $all | Where-Object { $_ -like "*$Query*" } } else { $all }
    if (-not $hits) { Write-Host "Nothing matches '$Query'." -ForegroundColor Yellow; return }
    Write-Host ""
    $hits | ForEach-Object { Write-Host ("  " + $_) }
    Write-Host ""
    Write-Host ("  {0} match{1}.  Install with:  Install-TerminalTheme '<name>'" -f
        @($hits).Count, $(if (@($hits).Count -eq 1) { '' } else { 'es' })) -ForegroundColor DarkGray
    Write-Host ""
}

# --- the installer ----------------------------------------------------------

function Install-TerminalTheme {
    <#  Fetch a colour scheme, add it to Windows Terminal, derive a matching
        prompt palette, and generate the prompt variant — in one step.

            Install-TerminalTheme 'Rose Pine'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Slug
    )

    if (-not $Slug) {
        $Slug = ($Name -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower()
    }

    # 1. fetch the canonical scheme
    $url = "$script:TT_Repo/$([uri]::EscapeDataString($Name)).json"
    try {
        $s = Invoke-RestMethod $url -Headers @{ 'User-Agent' = 'trinity-theme-tools' }
    } catch {
        Write-Host "No scheme called '$Name' in the collection." -ForegroundColor Red
        Write-Host "Search for the exact name with:  Find-TerminalTheme <part of the name>" -ForegroundColor Yellow
        return
    }

    $need = @('background','foreground','black','red','green','yellow','blue','purple','cyan','white',
              'brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite')
    $missing = $need | Where-Object { -not $s.$_ }
    if ($missing) {
        Write-Host "'$Name' is missing: $($missing -join ', ')" -ForegroundColor Red
        return
    }
    if (-not $s.name) { $s | Add-Member name $Name -Force }

    # 2. derive a prompt palette from the scheme's own 16 colours
    $pick = { param($bright, $plain) if ($bright) { $bright } else { $plain } }
    $accents = @{
        os       = (& $pick $s.brightPurple $s.purple)
        path     = (& $pick $s.brightBlue   $s.blue)
        gitClean = (& $pick $s.brightGreen  $s.green)
        gitDirty = (& $pick $s.brightYellow $s.yellow)
        danger   = (& $pick $s.brightRed    $s.red)
        ahead    = $s.yellow
        python   = (& $pick $s.brightCyan   $s.cyan)
        node     = $s.green
    }

    # Segment text sits on the accent colours, not on the window. Pick the ink
    # that reads worst-case best: judge each candidate by its WORST contrast
    # across the accents, because one dark accent (some schemes ship a very dark
    # "green") is what actually becomes unreadable — an average hides it.
    $worst = {
        param($ink)
        $li = TT-Lum $ink
        ($accents.Values | ForEach-Object {
            $la = TT-Lum $_
            (([Math]::Max($li, $la)) + 0.05) / (([Math]::Min($li, $la)) + 0.05)
        } | Measure-Object -Minimum).Minimum
    }
    $candidates = @($s.background, '#0b0b10', $s.brightWhite, '#ffffff') |
                  Where-Object { $_ } | Select-Object -Unique
    $segFg = ($candidates | Sort-Object { - (& $worst $_) } | Select-Object -First 1)

    $palette = [ordered]@{
        scheme = $s.name
        bg = $s.background.ToLower(); fg = $s.foreground.ToLower()
    }
    foreach ($k in 'os','path','gitClean','gitDirty','danger','ahead','python','node') {
        $palette[$k] = ([string]$accents[$k]).ToLower()
    }
    $palette['segFg'] = ([string]$segFg).ToLower()
    $palette['dim']   = ([string](& $pick $s.brightBlack $s.black)).ToLower()

    # 3. add the scheme to Windows Terminal
    if (-not (Test-Path $script:TT_Wt)) {
        Write-Host "Windows Terminal settings not found." -ForegroundColor Red
        return
    }
    Copy-Item $script:TT_Wt "$script:TT_Wt.bak" -Force
    $wt = Get-Content $script:TT_Wt -Raw | ConvertFrom-Json
    $scheme = [ordered]@{ name = $s.name }
    foreach ($k in @('background','foreground','cursorColor','selectionBackground') + $need) {
        if ($s.$k -and -not $scheme.Contains($k)) { $scheme[$k] = $s.$k }
    }
    if (-not $scheme.Contains('cursorColor'))         { $scheme['cursorColor'] = $s.foreground }
    if (-not $scheme.Contains('selectionBackground')) { $scheme['selectionBackground'] = $s.brightBlack }

    $kept = @($wt.schemes | Where-Object { $_.name -ne $s.name })
    $wt.schemes = @($kept + [pscustomobject]$scheme)
    $wt | ConvertTo-Json -Depth 32 | Set-Content $script:TT_Wt -Encoding UTF8

    # 4. add the palette
    $palettes = Get-Content $script:TT_Palettes -Raw | ConvertFrom-Json
    $palettes | Add-Member -NotePropertyName $Slug -NotePropertyValue ([pscustomobject]$palette) -Force
    $palettes | ConvertTo-Json -Depth 12 | Set-Content $script:TT_Palettes -Encoding UTF8

    # 5. generate the prompt variant
    & (Join-Path $script:TT_Root 'build-variants.ps1') | Out-Null

    # 6. refresh the catalogue so the new theme is actually in it. Only the
    # data is re-embedded, which takes about a second - a full rebuild
    # re-renders every design and is not needed, since adding a theme does not
    # change any of them.
    $builder = Join-Path $script:TT_Root 'catalogue\build-catalogue.py'
    if (Test-Path $builder) {
        $py = $null
        foreach ($c in @((Join-Path $script:TT_Root 'catalogue\.venv\Scripts\python.exe'))) {
            if (Test-Path $c) { $py = $c }
        }
        if (-not $py) {
            $cmd = Get-Command python -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -notlike '*WindowsApps*') { $py = $cmd.Source }
        }
        if ($py) {
            & $py $builder 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "  catalogue refreshed" -ForegroundColor DarkGray }
            else { Write-Host "  could not refresh the catalogue" -ForegroundColor Yellow }
        }
    }

    Write-Host ""
    Write-Host "  Installed $($s.name)" -ForegroundColor Green
    Write-Host "    slug        $Slug"
    Write-Host "    background  $($s.background)"

    # Say so when the scheme's own colours cap how readable the prompt can be.
    $lo = & $worst $segFg
    if ($lo -lt 4.5) {
        $dark = ($accents.GetEnumerator() | Sort-Object { TT-Lum $_.Value } | Select-Object -First 1)
        Write-Host ("    note        one segment reads at {0:N1}:1 — this scheme's {1} ({2}) is unusually dark" -f
            $lo, $dark.Key, $dark.Value) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Try it:  tt $Slug" -ForegroundColor DarkGray
    Write-Host "  See it:  catalogue" -ForegroundColor DarkGray
    Write-Host ""
}

function Uninstall-TerminalTheme {
    <#  Remove an installed theme's palette and prompt variant.
        The Windows Terminal scheme is left in place — harmless, and keeps any
        profile still pointing at it working.  #>
    param([Parameter(Mandatory, Position = 0)][string]$Slug)

    $palettes = Get-Content $script:TT_Palettes -Raw | ConvertFrom-Json
    if (-not ($palettes.PSObject.Properties.Name -contains $Slug)) {
        Write-Host "No theme with slug '$Slug'." -ForegroundColor Red; return
    }
    if ((Get-TerminalTheme).Prompt -eq "zelfium-$Slug.omp.json") {
        Write-Host "'$Slug' is currently active — switch away first with  tt 1" -ForegroundColor Yellow; return
    }
    $palettes.PSObject.Properties.Remove($Slug)
    $palettes | ConvertTo-Json -Depth 12 | Set-Content $script:TT_Palettes -Encoding UTF8
    Remove-Item (Join-Path $script:TT_Root "zelfium-$Slug.omp.json") -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $Slug." -ForegroundColor Green
}
