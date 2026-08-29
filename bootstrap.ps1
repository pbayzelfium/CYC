<#
  CYC bootstrap - the one-liner entry point.

    powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/pbayzelfium/CYC/main/bootstrap.ps1 | iex"

  This is deliberately tiny and safe to pipe into iex. install.ps1 is not:
  it restarts itself in PowerShell 7 using $PSCommandPath, which is empty when
  a script is piped rather than run from a file. So this downloads install.ps1
  to a real file first, then runs it.

  Requires the repo to be public, or GITHUB_TOKEN set to a token that can read
  it. See README.
#>
[CmdletBinding()]
param(
    [string]$Repo   = 'pbayzelfium/CYC',
    [string]$Branch = 'main',
    [switch]$DryRun,
    [switch]$SkipCatalogue,
    [switch]$Force
)

# Piping into iex discards parameters, so honour environment variables too.
# Both of these work:
#   $env:CYC_DRYRUN=1; irm .../bootstrap.ps1 | iex
#   & ([scriptblock]::Create((irm .../bootstrap.ps1))) -DryRun
if ($env:CYC_DRYRUN)   { $DryRun = $true }
if ($env:CYC_FORCE)    { $Force = $true }
if ($env:CYC_NOCATALOGUE) { $SkipCatalogue = $true }

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

Write-Host ""
Write-Host "  CYC - Customize Your Claude" -ForegroundColor White
Write-Host "  fetching the installer..." -ForegroundColor DarkGray

$dest = Join-Path $env:TEMP 'cyc-install.ps1'
$url  = "https://raw.githubusercontent.com/$Repo/$Branch/install.ps1"

$headers = @{ 'User-Agent' = 'cyc-bootstrap' }
if ($env:GITHUB_TOKEN) {
    # a private repo needs a token that can read it
    $headers['Authorization'] = "token $env:GITHUB_TOKEN"
    $url = "https://api.github.com/repos/$Repo/contents/install.ps1?ref=$Branch"
    $headers['Accept'] = 'application/vnd.github.raw'
}

try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $dest
} catch {
    Write-Host ""
    Write-Host "  Could not download the installer." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  If $Repo is private, either:" -ForegroundColor Yellow
    Write-Host "    - set a token first:  `$env:GITHUB_TOKEN = 'ghp_...'" -ForegroundColor Yellow
    Write-Host "    - or ask for install.ps1 directly and run it with:" -ForegroundColor Yellow
    Write-Host "        powershell -ExecutionPolicy Bypass -NoProfile -File install.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$kb = [math]::Round((Get-Item $dest).Length / 1KB)
if ($kb -lt 100) {
    Write-Host "  That download is only ${kb} KB - probably an error page, not the installer." -ForegroundColor Red
    Write-Host "  Check the repo is public, or set GITHUB_TOKEN." -ForegroundColor Yellow
    exit 1
}
Write-Host "  got it (${kb} KB) - running" -ForegroundColor DarkGray

# Unblock: a file fetched from the internet carries Mark of the Web, which
# stops it running even under Bypass in some configurations.
Unblock-File $dest -ErrorAction SilentlyContinue

# A HASHTABLE splat, not an array: array splatting passes arguments
# positionally, so '-DryRun' was being bound as a value to the first positional
# parameter instead of as a switch.
$opts = @{}
if ($DryRun)        { $opts['DryRun'] = $true }
if ($SkipCatalogue) { $opts['SkipCatalogue'] = $true }
if ($Force)         { $opts['Force'] = $true }
if ($DryRun) { Write-Host "  dry run - nothing will be changed" -ForegroundColor Yellow }
& $dest @opts
exit $LASTEXITCODE
