# Rebuild the Theme Catalogue after installing or editing themes.
#   pwsh -NoProfile -File ~\.oh-my-posh\catalogue\rebuild.ps1
# Then hand theme-catalogue.html to Claude to republish to the same artifact URL.

$here = $PSScriptRoot
$venv = Join-Path $here '.venv\Scripts\python.exe'
$py   = if (Test-Path $venv) { $venv }
        elseif (Get-Command python -EA SilentlyContinue) { 'python' }
        elseif (Get-Command py -EA SilentlyContinue) { 'py' }
        else { throw 'Python not found - install it, or create the venv in this folder.' }

Write-Host "1/3  rendering every prompt design..." -ForegroundColor DarkGray
& $py (Join-Path $here 'render-prompts.py')

Write-Host "2/3  subsetting the Nerd Font to the glyphs used..." -ForegroundColor DarkGray
& $py (Join-Path $here 'subset-font.py')

Write-Host "3/3  building the page..." -ForegroundColor DarkGray
& $py (Join-Path $here 'build-catalogue.py')

Write-Host ""
Write-Host "  Output: $(Join-Path $here 'theme-catalogue.html')" -ForegroundColor Green
Write-Host "  Ask Claude to publish it to the existing catalogue URL." -ForegroundColor DarkGray
Write-Host ""
