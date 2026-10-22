# Starts a local sing-box proxy on 127.0.0.1:18888.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File start-proxy.ps1
#
# Expects, next to this script:
#   proxy-config.json  - sing-box config (produced by check-configs.py + verify-live.py)
#   sing-box.path      - one line: full path to sing-box.exe
#
# Override the working directory with -WorkDir if the files live elsewhere.

param(
    [string]$WorkDir = $PSScriptRoot,
    [int]$Port = 18888
)

$ErrorActionPreference = 'Stop'

$cfg      = Join-Path $WorkDir 'proxy-config.json'
$coreFile = Join-Path $WorkDir 'sing-box.path'

if (-not (Test-Path $cfg)) {
    Write-Error "config not found: $cfg  (run check-configs.py and verify-live.py first)"
    exit 1
}

# resolve sing-box: explicit file, else PATH
$core = $null
if (Test-Path $coreFile) {
    $candidate = (Get-Content $coreFile -Raw).Trim()
    if (Test-Path $candidate) { $core = $candidate }
}
if (-not $core) {
    $cmd = Get-Command sing-box -ErrorAction SilentlyContinue
    if ($cmd) { $core = $cmd.Source }
}
if (-not $core) {
    Write-Error "sing-box not found. Put its path in $coreFile or add it to PATH."
    exit 1
}

# already running?
$running = Get-Process sing-box -ErrorAction SilentlyContinue
if ($running) {
    $listen = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($listen) { Write-Host "proxy already running on 127.0.0.1:$Port"; exit 0 }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

Start-Process -FilePath $core -ArgumentList @('run', '-c', $cfg) -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $WorkDir 'proxy.out.log') `
    -RedirectStandardError (Join-Path $WorkDir 'proxy.err.log')

for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
        Write-Host "proxy up on 127.0.0.1:$Port"
        exit 0
    }
}

Write-Error "proxy did not start within 20s; see proxy.err.log in $WorkDir"
exit 1
