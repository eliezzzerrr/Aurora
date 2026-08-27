<#
    mt5-watchdog.ps1

    Restarts MetaTrader 5 when TrendEMA_EA stops executing.

    HOW IT KNOWS
    ------------
    TrendEMA_EA v7.4+ writes MQL5\Files\TRENDEMA_HEARTBEAT.txt from OnTimer,
    which fires on the terminal's own clock rather than on incoming quotes.
    So a stale heartbeat means the EA has genuinely stopped running - it does
    NOT merely mean the market is quiet. That distinction is what lets this
    script act without any market-hours logic.

    WHAT IT DOES
    ------------
    Heartbeat older than $StallMinutes  ->  kill terminal64.exe, wait, relaunch.
    MT5 restores the chart and the EA's saved inputs on startup, and open
    positions are unaffected: their SL/TP live at the broker, not in the EA.

    SAFETY
    ------
    - Will not restart more than once per $CooldownMinutes (no restart loops).
    - Does nothing if MT5 is not running - it never launches MT5 unprompted.
    - Does nothing if the heartbeat file has never existed (EA not attached).
    - Every action is appended to watchdog.log next to this script.

    RUN IT
    ------
    Test once, safely:      powershell -File mt5-watchdog.ps1 -WhatIf
    Run once for real:      powershell -File mt5-watchdog.ps1
    Schedule it every 2 min: see the schtasks command in the project notes.
#>

param(
    [int]    $StallMinutes    = 2,
    [int]    $CooldownMinutes = 10,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'

$TerminalDir  = 'C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$HeartbeatFile= Join-Path $TerminalDir 'MQL5\Files\TRENDEMA_HEARTBEAT.txt'
$Mt5Exe       = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$LogFile      = Join-Path $PSScriptRoot 'watchdog.log'
$StampFile    = Join-Path $PSScriptRoot '.last-restart'

function Write-Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogFile -Value $line
    Write-Output $line
}

# --- MT5 must already be running. This script never starts it from cold: if
#     the user closed MT5 deliberately, relaunching it would be wrong.
$proc = Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Log 'MT5 not running - nothing to do.'
    exit 0
}

if (-not (Test-Path $HeartbeatFile)) {
    Write-Log 'No heartbeat file yet - EA not attached, or older than v7.4. Skipping.'
    exit 0
}

$age = (New-TimeSpan -Start (Get-Item $HeartbeatFile).LastWriteTime -End (Get-Date)).TotalMinutes
if ($age -lt $StallMinutes) {
    exit 0    # healthy; stay quiet so the log only records real events
}

# --- do not thrash: one restart per cooldown window
if (Test-Path $StampFile) {
    $since = (New-TimeSpan -Start (Get-Item $StampFile).LastWriteTime -End (Get-Date)).TotalMinutes
    if ($since -lt $CooldownMinutes) {
        Write-Log ("Heartbeat stale {0:N1} min, but last restart was {1:N1} min ago - waiting out the cooldown." -f $age, $since)
        exit 0
    }
}

Write-Log ("STALL DETECTED: heartbeat {0:N1} min old (threshold {1})." -f $age, $StallMinutes)

if ($WhatIf) {
    Write-Log 'WhatIf: would restart MT5 now. No action taken.'
    exit 0
}

try {
    Write-Log 'Stopping terminal64.exe ...'
    Stop-Process -Name 'terminal64' -Force
    Start-Sleep -Seconds 8

    Write-Log 'Starting MT5 ...'
    Start-Process -FilePath $Mt5Exe
    Set-Content -Path $StampFile -Value (Get-Date -Format 'o')
    Write-Log 'Restart issued. MT5 will reload the chart and the EA with its saved inputs.'
}
catch {
    Write-Log ("RESTART FAILED: {0}" -f $_.Exception.Message)
    exit 1
}
