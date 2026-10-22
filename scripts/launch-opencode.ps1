# Launcher for OpenCode: ensures the local proxy is up, then starts OpenCode.
#
# The API key is read from the environment, never hardcoded. Set it once with:
#   [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','sk-or-v1-...','User')

$ErrorActionPreference = 'Continue'
$cfgDir = Join-Path $env:USERPROFILE '.config\opencode'
$proxy  = 'http://127.0.0.1:18888'
$key    = $env:OPENROUTER_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User') }
if (-not $key) {
    Write-Host '  OPENROUTER_API_KEY is not set.' -ForegroundColor Red
    Write-Host "  Set it: [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','sk-or-v1-...','User')"
    Read-Host '  Press Enter to exit'
    exit 1
}
$work   = Join-Path $env:USERPROFILE 'OneDrive\Documents\deepseek-harness\default-workspace'

# resolve the real Documents folder (may be localised)
$docs = [Environment]::GetFolderPath('MyDocuments')
$alt  = Join-Path $docs 'deepseek-harness\default-workspace'
if (Test-Path $alt) { $work = $alt }

Write-Host ''
Write-Host '  ==========================================' -ForegroundColor DarkCyan
Write-Host '     OpenCode  -  AI agent' -ForegroundColor Cyan
Write-Host '  ==========================================' -ForegroundColor DarkCyan
Write-Host ''

function Test-ProxyPort {
    try { return [bool](Get-NetTCPConnection -State Listen -LocalPort 18888 -ErrorAction SilentlyContinue) }
    catch { return $false }
}

# ---------- 1. proxy ----------
if (-not (Test-ProxyPort)) {
    Write-Host '  [1/3] Starting proxy...' -ForegroundColor Gray
    $starter = Join-Path $cfgDir 'start-proxy.ps1'
    if (Test-Path $starter) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $starter | Out-Null
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-ProxyPort) { break }
    }
} else {
    Write-Host '  [1/3] Proxy is running.' -ForegroundColor Gray
}

# ---------- 2. connectivity (up to 3 tries) ----------
Write-Host '  [2/3] Checking connection...' -ForegroundColor Gray
$proxyOk = $false
for ($try = 1; $try -le 3; $try++) {
    try {
        $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -Proxy $proxy -TimeoutSec 25
        if ($ip) {
            Write-Host "         OK  IP $ip" -ForegroundColor Green
            $proxyOk = $true
            break
        }
    } catch {
        if ($try -lt 3) { Start-Sleep -Seconds 2 }
    }
}

if ($proxyOk) {
    $env:HTTP_PROXY  = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:ALL_PROXY   = $proxy
    $env:NO_PROXY    = 'localhost,127.0.0.1'
} else {
    Write-Host '         Proxy not responding - running without it.' -ForegroundColor Yellow
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:ALL_PROXY   -ErrorAction SilentlyContinue
}

# ---------- 3. start ----------
$env:OPENROUTER_API_KEY = $key
if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
Set-Location $work

Write-Host '  [3/3] Starting OpenCode...' -ForegroundColor Gray
Write-Host ''
Start-Sleep -Milliseconds 700

$ocCmd = Join-Path $env:APPDATA 'npm\opencode.cmd'
if (Test-Path $ocCmd) {
    & $ocCmd
} else {
    $oc = Get-Command opencode -ErrorAction SilentlyContinue
    if ($oc) { & $oc.Source } else { Write-Host 'OpenCode not found!' -ForegroundColor Red }
}

Write-Host ''
Write-Host '  OpenCode closed.' -ForegroundColor DarkGray
