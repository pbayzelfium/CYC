<#
.SYNOPSIS
  Exercises install.ps1 against a throwaway home directory.

.DESCRIPTION
  The install-from-nothing path is the part that cannot be checked on a machine
  that already has everything. This runs the installer into a temp directory
  with a pre-seeded Windows Terminal config, PowerShell profile and Claude
  settings that all contain someone else's work, then asserts that:

    - every file lands where it should
    - the user's existing profile content survives
    - the user's existing colour scheme and terminal profile survive
    - the user's existing Claude settings survive
    - prompt variants are generated, one per palette
    - a second run is idempotent rather than duplicating its own block

  Network steps (winget, downloads) are skipped; those are covered by a real
  run on a clean machine, which this does not replace.

.EXAMPLE
  pwsh -NoProfile -File test-install.ps1
#>
[CmdletBinding()]
param([string]$Installer = (Join-Path $PSScriptRoot 'install.ps1'))

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

# The version the build was stamped with. Read from VERSION rather than typed,
# so bumping the release does not silently turn this assertion into a lie.
$ExpectVersion = (Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()

function Check {
    param([string]$What, [scriptblock]$Test)
    try {
        if (& $Test) { Write-Host "  PASS  $What" -ForegroundColor Green; $script:pass++ }
        else         { Write-Host "  FAIL  $What" -ForegroundColor Red;   $script:fail++ }
    } catch {
        Write-Host "  FAIL  $What  ($($_.Exception.Message))" -ForegroundColor Red
        $script:fail++
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("cyc-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $root | Out-Null
Write-Host ""
Write-Host "  Test root: $root" -ForegroundColor DarkGray

try {
    # --- seed the root with things a real person would already have ---------
    $profileDir = Join-Path $root 'Documents\PowerShell'
    New-Item -ItemType Directory -Force $profileDir | Out-Null
    $profileFile = Join-Path $profileDir 'profile.ps1'
    Set-Content $profileFile "function Get-MyOwnThing { 'do not delete me' }" -Encoding UTF8

    $wt = Join-Path $root 'wt-settings.json'
    @{
        profiles = @{
            defaults = @{ font = @{ face = 'Consolas' } }
            list     = @(@{ guid = '{aaaa}'; name = 'Their Shell' })
        }
        schemes  = @(@{ name = 'Their Scheme'; background = '#123456' })
        keybindings = @(@{ id = 'Their.Binding'; keys = 'ctrl+j' })
    } | ConvertTo-Json -Depth 10 | Set-Content $wt -Encoding UTF8

    $claudeDir = Join-Path $root '.claude'
    New-Item -ItemType Directory -Force $claudeDir | Out-Null
    Set-Content (Join-Path $claudeDir 'settings.json') '{"model":"opus","theirKey":"keep me"}' -Encoding UTF8

    # --- run it -------------------------------------------------------------
    Write-Host ""
    & pwsh -NoProfile -File $Installer -TestRoot $root -SkipCatalogue -NoOpen -Source (Join-Path $PSScriptRoot 'src') *>&1 |
        Where-Object { $_ -match 'warning|WARN|!' } | ForEach-Object { Write-Host "  installer: $_" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  Assertions" -ForegroundColor White

    # --- files landed -------------------------------------------------------
    foreach ($f in '.oh-my-posh\palettes.json', '.oh-my-posh\cyc.omp.json',
                   '.oh-my-posh\pair-prompt.py', '.oh-my-posh\theme-tools.ps1',
                   '.oh-my-posh\build-variants.ps1', '.oh-my-posh\schemes.json',
                   '.claude\statusline.ps1', '.claude\commands\terminal-theme.md') {
        Check "wrote $f" { Test-Path (Join-Path $root $f) }.GetNewClosure()
    }

    Check "catalogue skipped with -SkipCatalogue" {
        -not (Test-Path (Join-Path $root '.oh-my-posh\catalogue\build-catalogue.py')) }

    # --- nothing of theirs was destroyed ------------------------------------
    Check "their profile content survived" {
        (Get-Content $profileFile -Raw) -match 'do not delete me' }
    Check "our profile block was added" {
        (Get-Content $profileFile -Raw) -match 'terminal-theme setup' }
    Check "their profile was backed up" { Test-Path "$profileFile.bak" }

    $wtj = Get-Content $wt -Raw | ConvertFrom-Json
    Check "their colour scheme survived"   { $wtj.schemes.name -contains 'Their Scheme' }
    Check "their terminal profile survived" { $wtj.profiles.list.name -contains 'Their Shell' }
    Check "their keybinding survived"      { $wtj.keybindings.id -contains 'Their.Binding' }
    Check "our schemes were added"         { $wtj.schemes.name -contains 'Catppuccin Mocha' }
    Check "the font was set"               { $wtj.profiles.defaults.font.face -eq 'JetBrainsMono NF' }

    $cj = Get-Content (Join-Path $claudeDir 'settings.json') -Raw | ConvertFrom-Json
    Check "their Claude settings survived" { $cj.theirKey -eq 'keep me' -and $cj.model -eq 'opus' }
    Check "status line was configured"     { $cj.statusLine.command -match 'statusline\.ps1' }

    # --- the generated output is usable -------------------------------------
    $palettes = Get-Content (Join-Path $root '.oh-my-posh\palettes.json') -Raw | ConvertFrom-Json
    $slugs = @($palettes.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' })
    Check "one prompt variant per palette ($($slugs.Count))" {
        $made = @(Get-ChildItem (Join-Path $root '.oh-my-posh') -Filter 'cyc-*.omp.json')
        $made.Count -eq $slugs.Count }.GetNewClosure()
    Check "every palette names a scheme that exists" {
        $defs = (Get-Content (Join-Path $root '.oh-my-posh\schemes.json') -Raw | ConvertFrom-Json).name
        @($slugs | Where-Object { $defs -notcontains $palettes.$_.scheme }).Count -eq 0 }.GetNewClosure()
    Check "no personal folder shortcuts shipped" {
        (Get-Content (Join-Path $root '.oh-my-posh\cyc.omp.json') -Raw) -notmatch 'mapped_locations' }

    # --- running twice must not duplicate ------------------------------------
    # -Force: an existing install is left alone otherwise, which is the point
    & pwsh -NoProfile -File $Installer -TestRoot $root -SkipCatalogue -Force -NoOpen -Source (Join-Path $PSScriptRoot 'src') *>&1 | Out-Null
    Check "second run does not duplicate the profile block" {
        ([regex]::Matches((Get-Content $profileFile -Raw), 'terminal-theme setup >>>').Count) -eq 1 }
    Check "second run does not duplicate schemes" {
        $j = Get-Content $wt -Raw | ConvertFrom-Json
        ($j.schemes.name | Group-Object | Where-Object Count -gt 1).Count -eq 0 }
    Check "their content still survives a second run" {
        (Get-Content $profileFile -Raw) -match 'do not delete me' }

    # --- updating must take nothing away -------------------------------------
    # An update replaces the program. Everything below is the person's own: the
    # theme they installed, the prompt they edited, the colours they chose.
    Write-Host ""
    Write-Host "  Update" -ForegroundColor White

    $omp  = Join-Path $root '.oh-my-posh'
    $palF = Join-Path $omp 'palettes.json'
    $cfgF = Join-Path $omp 'cyc.omp.json'

    # they installed a theme of their own
    $pal = Get-Content $palF -Raw | ConvertFrom-Json
    $pal | Add-Member 'their-theme' ([pscustomobject]@{
        scheme = 'Their Scheme'; bg = '#101010'; fg = '#eeeeee'
    }) -Force
    $pal | ConvertTo-Json -Depth 12 | Set-Content $palF -Encoding UTF8

    # they edited the prompt config
    $cfg = Get-Content $cfgF -Raw
    Set-Content $cfgF ($cfg -replace '"final_space"', '"their_edit": true, "final_space"') -Encoding UTF8

    # they picked a colour scheme, which is the whole point of the program
    $wtj = Get-Content $wt -Raw | ConvertFrom-Json
    $wtj.profiles.defaults | Add-Member colorScheme 'Their Scheme' -Force
    $wtj.profiles.defaults | Add-Member opacity 70 -Force
    $wtj | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding UTF8

    # and they are on an older build
    Set-Content (Join-Path $omp 'version.txt') '1.0.0' -Encoding UTF8
    Set-Content (Join-Path $omp 'active-design.txt') 'cyc' -Encoding UTF8

    & pwsh -NoProfile -File $Installer -TestRoot $root -SkipCatalogue -Update -NoOpen -Source (Join-Path $PSScriptRoot 'src') *>&1 | Out-Null

    $pal2 = Get-Content $palF -Raw | ConvertFrom-Json
    Check "KEPT the theme they installed" { $null -ne $pal2.PSObject.Properties['their-theme'] }
    Check "KEPT its scheme name"          { $pal2.'their-theme'.scheme -eq 'Their Scheme' }
    Check "KEPT the shipped themes too"   { $null -ne $pal2.PSObject.Properties['nord'] }
    Check "KEPT their prompt edit"        { (Get-Content $cfgF -Raw) -match 'their_edit' }
    Check "offered the new prompt beside it" { Test-Path "$cfgF.new" }

    $wtj2 = Get-Content $wt -Raw | ConvertFrom-Json
    Check "KEPT their colour scheme"      { $wtj2.profiles.defaults.colorScheme -eq 'Their Scheme' }
    Check "KEPT their opacity"            { $wtj2.profiles.defaults.opacity -eq 70 }
    Check "KEPT their own scheme entry"   { $wtj2.schemes.name -contains 'Their Scheme' }

    Check "replaced the program"          { (Get-Content (Join-Path $root '.claude\statusline.ps1') -Raw).Length -gt 100 }
    Check "recorded the new version"      { (Get-Content (Join-Path $omp 'version.txt') -Raw).Trim() -eq $ExpectVersion }.GetNewClosure()
    Check "left their design alone"       { (Get-Content (Join-Path $omp 'active-design.txt') -Raw).Trim() -eq 'cyc' }

    # The one case where a setting has to move: what it points at is gone.
    Set-Content (Join-Path $omp 'active-design.txt') 'design-that-was-removed' -Encoding UTF8
    & pwsh -NoProfile -File $Installer -TestRoot $root -SkipCatalogue -Update -NoOpen -Source (Join-Path $PSScriptRoot 'src') *>&1 | Out-Null
    Check "fell back when their design was removed from the build" {
        (Get-Content (Join-Path $omp 'active-design.txt') -Raw).Trim() -eq 'cyc' }
    Check "and still kept their theme"    {
        $j = Get-Content $palF -Raw | ConvertFrom-Json
        $null -ne $j.PSObject.Properties['their-theme'] }

    # --- uninstall: an uninstaller that never runs is just a promise --------
    Write-Host ""
    Write-Host "  Uninstall" -ForegroundColor White
    $uninstaller = Join-Path $PSScriptRoot 'uninstall.ps1'
    & pwsh -NoProfile -File $uninstaller -TestRoot $root *>&1 | Out-Null

    Check "removed its own files"        { -not (Test-Path (Join-Path $root '.oh-my-posh')) }
    Check "removed the status line"      { -not (Test-Path (Join-Path $root '.claude\statusline.ps1')) }
    Check "removed the slash command"    { -not (Test-Path (Join-Path $root '.claude\commands	erminal-theme.md')) }
    Check "removed its profile block"    {
        (Get-Content $profileFile -Raw) -notmatch 'terminal-theme setup' }
    Check "KEPT their profile content"   {
        (Get-Content $profileFile -Raw) -match 'do not delete me' }

    $wtj = Get-Content $wt -Raw | ConvertFrom-Json
    Check "removed its colour schemes"   { $wtj.schemes.name -notcontains 'Catppuccin Mocha' }
    Check "KEPT their colour scheme"     { $wtj.schemes.name -contains 'Their Scheme' }
    Check "KEPT their terminal profile"  { $wtj.profiles.list.name -contains 'Their Shell' }
    Check "KEPT their keybinding"        { $wtj.keybindings.id -contains 'Their.Binding' }
    Check "reset the font"               { -not $wtj.profiles.defaults.font }

    $cj = Get-Content (Join-Path $claudeDir 'settings.json') -Raw | ConvertFrom-Json
    Check "removed the statusLine entry" { -not $cj.statusLine }
    Check "KEPT their Claude settings"   { $cj.theirKey -eq 'keep me' -and $cj.model -eq 'opus' }
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($fail) {
    Write-Host "  $pass passed, $fail FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  $pass passed" -ForegroundColor Green
exit 0
