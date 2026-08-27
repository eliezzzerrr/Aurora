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
    [int]    $StallMinutes     = 2,    # heartbeat file this old = EA is dead
    [int]    $TickStallMinutes = 5,    # no ticks this long, market open = feed is dead
    [int]    $CooldownMinutes  = 10,
    [int]    $MaxConsecutive   = 3,    # give up after this many failed restarts
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'

$TerminalDir  = 'C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$HeartbeatFile= Join-Path $TerminalDir 'MQL5\Files\TRENDEMA_HEARTBEAT.txt'
$Mt5Exe       = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$LogFile      = Join-Path $PSScriptRoot 'watchdog.log'
$StampFile    = Join-Path $PSScriptRoot '.last-restart'
$FailFile     = Join-Path $PSScriptRoot '.consecutive-restarts'

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

# --- Heartbeat format (EA v7.9+):  <local time>|<tick age s>|<market open 0/1>
#     A fresh heartbeat only proves the EA is ALIVE, not that it is receiving
#     data - it is written from OnTimer, which runs on the terminal clock.
#     On 27 Aug the EA sat for nine hours with a perfectly current heartbeat
#     and no ticks at all, so the tick age is the field that matters.
$tickAge    = $null
$marketOpen = $null
try {
    $parts = (Get-Content $HeartbeatFile -Raw).Trim() -split '\|'
    if ($parts.Count -ge 3) {
        $tickAge    = [int]$parts[1]
        $marketOpen = [int]$parts[2]
    }
} catch { }

$reason = $null

if ($age -ge $StallMinutes) {
    $reason = "heartbeat {0:N1} min old (threshold {1}) - EA not executing" -f $age, $StallMinutes
}
elseif ($null -ne $tickAge -and $marketOpen -eq 1 -and $tickAge -ge ($TickStallMinutes * 60)) {
    $reason = "no ticks for {0:N1} min while the market is open - quote feed dead" -f ($tickAge / 60)
}

if (-not $reason) {
    # healthy - clear the consecutive-failure counter and stay quiet
    if (Test-Path $FailFile) { Remove-Item $FailFile -Force -ErrorAction SilentlyContinue }
    exit 0
}

# --- do not thrash: one restart per cooldown window
if (Test-Path $StampFile) {
    $since = (New-TimeSpan -Start (Get-Item $StampFile).LastWriteTime -End (Get-Date)).TotalMinutes
    if ($since -lt $CooldownMinutes) {
        Write-Log ("STALL ({0}), but last restart was {1:N1} min ago - waiting out the cooldown." -f $reason, $since)
        exit 0
    }
}

# --- Give up rather than loop. On 27 Aug this restarted MT5 38 times over
#     seven hours: the attached EA version had been deleted from the Advisors
#     folder, so no EA ever loaded, the heartbeat never refreshed, and every
#     cycle looked like a fresh stall. Restarting cannot fix a problem that
#     restarting does not fix.
$fails = 0
if (Test-Path $FailFile) { $fails = [int](Get-Content $FailFile -Raw).Trim() }

if ($fails -ge $MaxConsecutive) {
    Write-Log ("GIVING UP: {0} restarts in a row did not restore the heartbeat. " -f $fails +
               "Restarting is not fixing this - check that the EA attached to the chart " +
               "still exists in MQL5\Experts\Advisors, and that Algo Trading is on. " +
               "Delete .consecutive-restarts to re-arm the watchdog.")
    exit 0
}

Write-Log ("STALL DETECTED: {0}." -f $reason)

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
    Set-Content -Path $FailFile  -Value ([string]($fails + 1))
    Write-Log 'Restart issued. MT5 will reload the chart and the EA with its saved inputs.'
}
catch {
    Write-Log ("RESTART FAILED: {0}" -f $_.Exception.Message)
    exit 1
}
