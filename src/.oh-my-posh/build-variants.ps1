# Generates one cyc-<slug>.omp.json per palette in palettes.json, by
# remapping the colour tokens used in cyc.omp.json.
# Re-run after editing cyc.omp.json or palettes.json.

# its own folder, not $HOME: the script lives beside the files it reads, so it
# works wherever the setup is installed
$root     = $PSScriptRoot
$base     = Get-Content (Join-Path $root 'cyc.omp.json') -Raw
$palettes = Get-Content (Join-Path $root 'palettes.json') -Raw | ConvertFrom-Json

# the literal hexes as written in cyc.omp.json (the catppuccin-mocha values)
$src = [ordered]@{
    os='#cba6f7'; path='#89b4fa'; gitClean='#a6e3a1'; gitDirty='#f9e2af'
    danger='#f38ba8'; ahead='#fab387'; python='#74c7ec'; node='#94e2d5'
    segFg='#11111b'; dim='#585b70'
}

foreach ($p in $palettes.PSObject.Properties) {
    if ($p.Name -like '_*') { continue }
    $slug = $p.Name
    $pal  = $p.Value
    $out  = $base

    # two-pass swap through placeholders, so a target colour that also appears
    # as a source colour cannot be rewritten twice
    foreach ($k in $src.Keys) { $out = $out -replace [regex]::Escape($src[$k]), "@@$k@@" }
    foreach ($k in $src.Keys) { $out = $out -replace "@@$k@@", $pal.$k }

    $path = Join-Path $root "cyc-$slug.omp.json"
    Set-Content -Path $path -Value $out -Encoding UTF8
    Write-Host "wrote $path"
}
