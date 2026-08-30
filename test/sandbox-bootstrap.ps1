<#
  Runs inside Windows Sandbox, launched by sandbox.wsb.

  The sandbox starts with Windows PowerShell 5.1 and nothing else, which is the
  point: this exercises the install-from-nothing path that cannot be checked on
  a machine that already has everything.

  Everything it prints also goes to C:\Results\sandbox-log.txt, which is mapped
  back to the host so the output survives the sandbox closing.
#>
$ErrorActionPreference = 'Continue'
$log = 'C:\Results\sandbox-log.txt'
New-Item -ItemType Directory -Force 'C:\Results' | Out-Null
Start-Transcript -Path $log -Force | Out-Null

function Head { param($m) Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Cyan }

Head "Sandbox baseline"
Write-Host "Windows PowerShell : $($PSVersionTable.PSVersion)"
Write-Host "pwsh present       : $([bool](Get-Command pwsh -EA SilentlyContinue))"
Write-Host "winget present     : $([bool](Get-Command winget -EA SilentlyContinue))"
Write-Host "Windows Terminal   : $([bool](Get-Command wt -EA SilentlyContinue))"
Write-Host "git present        : $([bool](Get-Command git -EA SilentlyContinue))"

# --- PowerShell 7 -----------------------------------------------------------
Head "Installing PowerShell 7"
$msi = "$env:TEMP\pwsh.msi"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
        -Headers @{ 'User-Agent' = 'cyc-sandbox' }
    $url = ($rel.assets | Where-Object { $_.name -like '*win-x64.msi' } | Select-Object -First 1).browser_download_url
    Write-Host "downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $msi
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
    Write-Host "installed"
} catch {
    Write-Host "FAILED to install PowerShell 7: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript | Out-Null
    Read-Host "press Enter to close"
    exit 1
}

$pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
if (-not (Test-Path $pwsh)) {
    Write-Host "pwsh.exe not found after install" -ForegroundColor Red
    Stop-Transcript | Out-Null; Read-Host "press Enter to close"; exit 1
}

# --- copy out of the read-only mount ----------------------------------------
Head "Staging the installer"
Copy-Item C:\CYC C:\CYC-run -Recurse -Force
Write-Host "staged to C:\CYC-run"

# --- the actual test --------------------------------------------------------
Head "install.ps1 -DryRun"
& $pwsh -NoProfile -File C:\CYC-run\install.ps1 -DryRun

Head "test-install.ps1"
& $pwsh -NoProfile -File C:\CYC-run\test-install.ps1
$suite = $LASTEXITCODE

Head "install.ps1 (for real, from nothing)"
& $pwsh -NoProfile -File C:\CYC-run\install.ps1 -SkipCatalogue
$install = $LASTEXITCODE

# --- did it actually work? --------------------------------------------------
Head "Verifying the result"
$checks = [ordered]@{
    'oh-my-posh downloaded' = Test-Path "$HOME\.local\bin\oh-my-posh.exe"
    'designs downloaded'    = (@(Get-ChildItem "$HOME\.oh-my-posh\themes" -Filter *.omp.json -EA SilentlyContinue).Count -gt 50)
    'palettes written'      = Test-Path "$HOME\.oh-my-posh\palettes.json"
    'status line written'   = Test-Path "$HOME\.claude\statusline.ps1"
    'slash command written' = Test-Path "$HOME\.claude\commands\terminal-theme.md"
    'variants generated'    = (@(Get-ChildItem "$HOME\.oh-my-posh" -Filter 'cyc-*.omp.json' -EA SilentlyContinue).Count -ge 7)
    'profile written'       = Test-Path "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
}
$bad = 0
foreach ($k in $checks.Keys) {
    if ($checks[$k]) { Write-Host ("  PASS  " + $k) -ForegroundColor Green }
    else             { Write-Host ("  FAIL  " + $k) -ForegroundColor Red; $bad++ }
}

Head "Does the prompt render?"
$omp = "$HOME\.local\bin\oh-my-posh.exe"
if (Test-Path $omp) {
    foreach ($cfg in Get-ChildItem "$HOME\.oh-my-posh" -Filter 'cyc-*.omp.json' -EA SilentlyContinue) {
        $out = & $omp print primary --config $cfg.FullName --shell pwsh --plain
        if ($out) { Write-Host ("  PASS  " + $cfg.Name + "  ->  " + ($out -split "`n")[0].Trim()) -ForegroundColor Green }
        else      { Write-Host ("  FAIL  " + $cfg.Name + " rendered nothing") -ForegroundColor Red; $bad++ }
    }
}

Head "Does a new shell get the prompt?"
$probe = & $pwsh -NoLogo -Command "if (Get-Command Set-TerminalTheme -EA SilentlyContinue) { 'profile loaded, commands available' } else { 'PROFILE DID NOT LOAD' }"
Write-Host "  $probe"
if ($probe -notmatch 'available') { $bad++ }

Head "Result"
Write-Host "  suite exit    : $suite"
Write-Host "  install exit  : $install"
Write-Host "  failed checks : $bad"
if ($bad -eq 0 -and $suite -eq 0) { Write-Host "  CLEAN INSTALL WORKS" -ForegroundColor Green }
else { Write-Host "  SOMETHING IS BROKEN - see above" -ForegroundColor Red }

Write-Host ""
Write-Host "  Not covered here: Windows Terminal theming and the font install." -ForegroundColor Yellow
Write-Host "  Sandbox has neither Windows Terminal nor winget." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Full log copied to the host at test\results\sandbox-log.txt" -ForegroundColor DarkGray

Stop-Transcript | Out-Null
Read-Host "press Enter to close the sandbox"
