# Proxy control for OpenCode: start / stop / restart / status.
# Usage:  proxy.ps1 stop     proxy.ps1 start     proxy.ps1 status

param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'on', 'off')]
    [string]$Action = 'status',
    [string]$WorkDir = $PSScriptRoot,
    [int]$Port = 18888
)

$ErrorActionPreference = 'Continue'
$cfgDir  = $WorkDir
$core    = (Get-Content (Join-Path $cfgDir 'sing-box.path') -Raw -ErrorAction SilentlyContinue)
if ($core) { $core = $core.Trim() }
$cfg     = Join-Path $cfgDir 'proxy-config.json'
$starter = Join-Path $PSScriptRoot 'start-proxy.ps1'

# alias
if ($Action -eq 'on')  { $Action = 'start' }
if ($Action -eq 'off') { $Action = 'stop' }

function Get-ProxyProc {
    Get-Process sing-box -ErrorAction SilentlyContinue
}

function Test-ProxyListen {
    try { return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) }
    catch { return $false }
}

function Show-Status {
    $proc = Get-ProxyProc
    $listen = Test-ProxyListen
    Write-Host ''
    if ($proc -and $listen) {
        $ram = [math]::Round(($proc | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)
        Write-Host '  Proxy:  RUNNING' -ForegroundColor Green
        Write-Host "  pid:    $($proc.Id -join ', ')"
        Write-Host "  listen: 127.0.0.1:$Port"
        Write-Host "  RAM:    $ram MB"
        try {
            $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -Proxy "http://127.0.0.1:$Port" -TimeoutSec 15
            Write-Host "  IP:     $ip" -ForegroundColor Green
        } catch {
            Write-Host '  IP:     not responding' -ForegroundColor Yellow
        }
    } elseif ($proc) {
        Write-Host '  Proxy:  PARTIAL (process alive, port closed)' -ForegroundColor Yellow
    } else {
        Write-Host '  Proxy:  STOPPED' -ForegroundColor Red
        Write-Host '  OpenCode will not reach the models until it is started.'
        Write-Host '  Start it with:  proxy.ps1 start'
    }
    Write-Host ''
}

function Stop-Proxy {
    $proc = Get-ProxyProc
    if (-not $proc) {
        Write-Host '  Proxy is already stopped.' -ForegroundColor Gray
        return
    }
    foreach ($p in $proc) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Host "  Stopped pid $($p.Id)." -ForegroundColor Green }
        catch { Write-Host "  Could not stop pid $($p.Id): $($_.Exception.Message)" -ForegroundColor Red }
    }
    Start-Sleep -Milliseconds 700
    if (Test-ProxyListen) { Write-Host '  Port  is still open.' -ForegroundColor Yellow }
    else { Write-Host '  Port  closed.' -ForegroundColor Gray }
}

function Start-Proxy {
    if (Test-ProxyListen) { Write-Host '  Proxy is already running.' -ForegroundColor Gray; return }
    if (-not (Test-Path $starter)) { Write-Host "  Missing $starter" -ForegroundColor Red; return }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $starter
}

switch ($Action) {
    'start'   { Start-Proxy;  Show-Status }
    'stop'    { Stop-Proxy;   Show-Status }
    'restart' { Stop-Proxy; Start-Sleep -Seconds 1; Start-Proxy; Show-Status }
    'status'  { Show-Status }
}
