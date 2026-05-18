# Aurora EAs — MetaTrader 5 Expert Advisors

Two EAs in this folder:

| File | Style | Timeframes | Sessions | Concurrent positions |
|---|---|---|---|---|
| **`Aurora.mq5`** | Day-trader | 1H bias / 15m execution | London + NY only | 1 |
| **`Aurora Scalper.mq5`** | Scalper | 15m bias / 5m sweep / 1m entry | 24/5 (no session lock) | up to 3 |

Both implement the ICT/SMC sweep + CHoCH + OB retest structure, 2:1 RR minimum, 1% balance risk per trade, and daily safety circuit breakers. Different magic numbers — they can run side-by-side on the same chart without conflict.

**Status: v1.0 — Demo-only. Do not run on live capital until validated with 30+ closed trades per EA.**

---

## Aurora.mq5 — what it does

On every new M15 bar, the EA runs a 4-stage state machine:

```
STAGE_IDLE     →  Scan for HTF bias + liquidity sweep
                  Wick beyond BSL/SSL + close back inside = sweep confirmed

STAGE_SWEPT    →  Wait for 15m close past most recent swing low/high
                  = CHoCH confirmed

STAGE_CHOCH    →  Identify the 15m bearish/bullish OB
                  Calc entry/SL/TP, verify RR ≥ 2:1
                  Place limit order at OB

STAGE_PENDING  →  Monitor for fill or invalidation
                  Fill → tradesToday++, reset to IDLE
                  Sweep wick breached → cancel + reset
                  Bars > expiry → cancel + reset
```

Positions on tick: monitor +1R achievement → move SL to breakeven (if enabled).

---

## Aurora Scalper.mq5 — what it does

Same 5-stage logic, but compressed:
- HTF bias on **M15** instead of H1
- Sweep detection on **M5** instead of M15
- CHoCH + OB + entry on **M1** instead of M15
- After placing limit order, immediately resets to IDLE so the next M1 bar can hunt new setups
- Up to **3 concurrent positions** (open + pending counted together)
- **No session filter** — runs 24/5
- Tighter pip tolerances and shorter timeouts

### Scalper-specific inputs (defaults shown)

| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 0.5 | Lower per-trade risk since 3 can be open at once |
| `InpRRMin` | 2.0 | Minimum reward-to-risk (1.5 was tested and destroyed edge) |
| `InpMaxPositions` | 3 | Hard cap on concurrent open + pending orders |
| `InpUseKillzones` | false | Off by default. Set true to restrict to London/NY |
| `InpBiasTF` | M15 | HTF bias |
| `InpSweepTF` | M5 | Liquidity sweep detection |
| `InpEntryTF` | M1 | CHoCH, OB, entry |
| `InpSwingLookback` | 2 | Tighter (1m needs less context) |
| `InpRequireEqualHighs` | **true** | true = strict clustered equal-highs (recommended — preserves edge). false = sweep any swing (kills win rate per backtest) |
| `InpEqualHighTolPips` | 2.0 | Pip tolerance when InpRequireEqualHighs = true |
| `InpStructureBars` | 120 | M5 bars for pool scan (~10 hours) |
| `InpSweepTimeoutBars` | 15 | M1 bars after sweep before resetting if no CHoCH |
| `InpSLBufferPips` | 2.0 | Tighter SL buffer |
| `InpLimitExpireBars` | 20 | M1 bars before pending limit auto-cancels |
| `InpMaxTradesDay` | 15 | Higher daily cap for scalper |
| `InpMaxConsecLoss` | 3 | Halt after 3 in a row |
| `InpMagic` | 87742 | Distinct from day-trader (87741) — both can run on same chart |

---

## Installation (same procedure for both EAs)

### 1. Copy the EA file

Copy `Aurora.mq5` and/or `Aurora Scalper.mq5` to your MetaTrader 5 `Experts` folder:

**Windows path:**
```
C:\Users\<YOU>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_HASH>\MQL5\Experts\Aurora.mq5
```

Or in MT5: **File → Open Data Folder → MQL5 → Experts → paste here**.

### 2. Compile

In MetaEditor (F4 from MT5 or open MetaEditor directly):
- Open `Experts/Aurora.mq5`
- Press **F7** to compile
- You should see `0 errors, 0 warnings` in the log

### 3. Attach to XAUUSD chart

- Open a XAUUSD chart in MT5 (chart timeframe doesn't matter — each EA reads its own internal TFs)
- Drag `Navigator → Expert Advisors → Aurora` (or `Aurora Scalper`) onto the chart
- In the popup:
  - **Common tab:** check `Allow Algo Trading` (required for auto-trade)
  - **Inputs tab:** review settings (see below)
- Click OK
- Smiley face in top-right of chart = EA running ✅

### 4. Enable algo trading globally

The toolbar `Algo Trading` button must be **green** for auto-trade to work.

---

## Key inputs (defaults shown)

| Input | Default | Notes |
|---|---|---|
| `InpRiskPercent` | 1.0 | % of balance risked per trade |
| `InpRRMin` | 2.0 | Min RR — refuses trades below this |
| `InpMoveBE_at1R` | true | Move SL to entry at +1R |
| `InpUseKillzones` | true | Restrict to London + NY AM |
| `InpBrokerToUTC` | -4 | Broker timezone offset from UTC (US brokers usually -4 or -5 DST) |
| `InpLondonOpenH..CloseH` | 7..10 | UTC hours for London window |
| `InpNYOpenH..CloseH` | 12:30..15:30 | UTC for NY AM |
| `InpSwingLookback` | 3 | Bars left/right for pivot (3 = strict, 5 = stricter) |
| `InpEqualHighTolPips` | 5.0 | Tolerance for "equal" highs/lows |
| `InpStructureBars` | 50 | M15 lookback for liquidity pools |
| `InpHTFBiasBars` | 30 | H1 lookback for bias |
| `InpSLBufferPips` | 3.0 | Extra pips beyond sweep wick for SL |
| `InpLimitExpireBars` | 12 | M15 bars before pending order auto-cancels |
| `InpMaxTradesDay` | 3 | Hard daily entry limit |
| `InpMaxConsecLoss` | 2 | Halt after N losses in a row |
| `InpMagic` | 87741 | Position identifier (don't change unless running multiple instances) |
| `InpLogToFile` | true | Write decisions to `MQL5/Files/Aurora_Journal.txt` |

### Adjusting `InpBrokerToUTC`

Check your broker's server time vs UTC:
- "GMT" broker → 0
- "GMT+2/+3" broker (most ECN) → +2 or +3
- US broker (NY time) → -4 (EDT summer) or -5 (EST winter)

Your broker (per chart screenshots showing UTC-4) → `-4` works during DST. Change to `-5` between Nov–Mar.

---

## Where the EA logs

Two places:

1. **MT5 Experts log** — `Toolbox → Experts` tab. Real-time decision stream.
2. **File** — `MQL5/Files/Aurora_Journal.txt`. Persistent across restarts.

Sample log lines:
```
2026-05-19 15:00:00 [INFO] --- New trading day: 2026.05.19 ---
2026-05-19 15:15:32 [SIGNAL] [SWEEP] Short — BSL @ 4545.000 wicked to 4553.500, closed at 4541.200
2026-05-19 15:30:14 [SIGNAL] [CHoCH] Short confirmed — close 4528.500 < swing low 4530.000
2026-05-19 15:30:14 [SIGNAL] [LIMIT PLACED] SELL 0.05 lots @ 4548.000 · SL 4557.000 · TP 4481.000 · RR 7.44
2026-05-19 15:48:11 [SIGNAL] [FILLED] Position opened from ticket 12345678
```

---

## Backtesting before going live

Strongly recommended. In MT5:

1. **View → Strategy Tester** (Ctrl+R)
2. **Expert:** `Aurora`
3. **Symbol:** `XAUUSD` (or whatever your broker calls gold)
4. **Period:** start with last 30 days, then expand to 90/180/365
5. **Modeling:** `Every tick based on real ticks` (gold needs accurate ticks)
6. **Forward:** 1/4 or 1/2 (out-of-sample validation)
7. Click **Start**

Watch the results tab for:
- Total trades (target: 1–3/day average)
- Win rate (target: ≥45%)
- Profit factor (target: ≥1.5)
- Max drawdown (target: <10% of balance)

If backtests look good → run on demo for ~30 trades → review → consider live.

---

## What this EA can't do (limitations)

- **No visual pattern recognition.** It detects structure algorithmically. Some setups discretionary-Aurora would catch will be missed, and vice versa.
- **No news filter.** It will happily trade through NFP unless you disable Algo Trading manually 30 min before.
- **No multi-symbol.** Built for XAUUSD only. Could be adapted but parameters would need re-tuning.
- **Equal-highs detection is fuzzy.** Uses `InpEqualHighTolPips` as tolerance. Tune this if you see it missing obvious pools or detecting noise.
- **Bias is mechanical.** Compares last 30 H1 bars' HH/LL positions. Works for trending markets, less reliable in ranges.
- **One position at a time.** No stacking. Pending order also blocks new signals until filled or cancelled.

---

## Roadmap (post-v1)

If forward-testing produces real edge:

- [ ] News calendar integration (auto-pause around high-impact USD/Gold events)
- [ ] Multi-TF confirmation (require H4 alignment for A+ grade)
- [ ] Partial close at 1R (take half off, runner to 2R)
- [ ] Visual on-chart drawing (mark detected BSL/SSL/OB/CHoCH for verification)
- [ ] Adaptive equal-high tolerance based on ATR
- [ ] Alert mode (signals + sounds, no auto-execution)

---

## Disclaimer

This is a personal trading system, distributed as-is for educational and research purposes. Trading carries risk of capital loss. The author accepts no responsibility for any losses incurred. Always test on demo first. Past performance, including backtest results, does not guarantee future results.
