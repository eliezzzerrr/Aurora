# TrendEMA EA — XAUUSD automated trader

MetaTrader 5 Expert Advisor for gold. Attached to an **M1** chart on `XAUUSDc`, Exness cent account, **real money**.

Current version: **`TrendEMA_EA_v7.26.mq5`**. Older versions are kept in this folder as history — only the newest is deployed.

> Kill switch: drop `TRENDEMA_STOP.txt` into `MQL5\Files` and the EA stops placing orders.

---

## The idea

Three timeframes, each with one job:

| TF | Role |
|---|---|
| **15M** | *Permission.* The Ichimoku cloud (9/26/52, shift 26) says which direction is allowed. Price inside the cloud = no trade. |
| **5M** | *Direction.* EMA 20 vs EMA 50 picks the side. |
| **1M** | *Timing.* Entries happen at the EMA 50. |

Counter-trend trades are permitted — a bullish 15M with a bearish 5M produces a SELL — but they get tighter geometry and must clear a structural barrier test.

---

## The five triggers

Each is tagged in the order comment so results can be attributed per mechanism.

| Tag | Mechanism |
|---|---|
| `TREND` / `CTR` | A **limit** resting at the EMA 50 (1M, falling back to 5M then 15M), re-priced each new 1M bar |
| `XING` / `XING-CTR` | A **cross** of the EMA 50, entered at market |
| `RSIX` | **Washout.** Multi-timeframe RSI extreme arms it; entry on the turn. Ignores the trend entirely |
| `TRSI` | **Trend RSI.** A 1M RSI spike *into* a confirmed 15M trend — an alternative way to time a trend entry |

### RSI-X arming levels (BUY; SELL mirrors)

| Variant | Arms when | "fast" TF |
|---|---|---|
| `3TF` | 1M < 25 **and** 5M < 40 **and** 15M < 35 | 1M |
| `1M5M` | 1M < 30 **and** 5M < 40 | 1M |
| `5M15M` | 5M < 30 **and** 15M < 35 | 5M |

Then it waits for the **turn** — the fast RSI back through 30 — and expires after 30 unfired bars. After firing, the fast RSI must exceed 50 before it can re-arm.

Note `1M5M` never reads the 15M, so it will buy a washout in a downtrend. That is the stated design, and the barrier rule below is its counterweight.

### The RSI gate on trend entries (`RSI_MODE_ARM`)

The 5M RSI crossing the mid **arms** entries on that side for `RsiArmBars` (15) bars, measured from the last moment the condition held. It is not re-tested tick by tick.

This replaced a continuous filter that cancelled resting limits on a momentary wobble — on 31 Aug a sell limit at 4438.56 was placed correctly, killed seconds later by a dip to RSI 45, and price then ran through its target.

---

## Geometry

Pips are gold pips: **1 pip = 0.01 in price = $0.01**. A 900-pip stop is 9.00.

| Trigger | SL | TP |
|---|---|---|
| Trend limit | 900 | 1500 |
| Cross | 900 | 1500 |
| Counter-trend | 500 | 1000, barrier-capped |
| RSI-X | 900 | 1500, barrier-capped |
| Trend RSI | 900 | 1500 |

Breakeven at 900/1500 is **37.5%**.

### The barrier rule

A counter-trend or washout entry is fading structure, so a fixed target can sit on the far side of the thing that will stop price. `CounterBarrier` finds the nearest level on the correct side and targets 50 pips short of it:

- 15M cloud edge
- 15M EMA 50
- **5M EMA 50** (`BarrierUse5M`)

If the remaining room does not clear the RR floor (`MinCounterRR` 1.5, `MinRsiXRR` 1.0) the trade is **refused**, and the log names the level that blocked it:

```
counter 480p to 5M EMA50 barrier, RR 0.96 < 1.50
```

Adding the 5M mostly *rejects* counters rather than shrinking them — a 500-pip stop at RR 1.5 still needs 750 pips of clear room.

---

## Risk controls

| Control | Setting |
|---|---|
| Risk per trade | 1.0% of equity, 1.25% hard ceiling, 2.0 lot cap |
| Concurrent positions | 3 |
| Per-trigger slots | One open position each for EMA1 / EMA5 / EMA15 / RSIX / TRSI |
| Opposing entries | Never long and short at once |
| Daily halt | 6% realised loss; day rolls at 12:00 ET |
| **Cooldown** | 60 min after a loss — **losing side only** |
| **Same-direction brake** | 3 losses in a row on one side blocks that side until the 15M permission flips |
| Spread | Skip above 50 pips |
| News | MT5 calendar high-impact USD ±15 min, plus manual GMT windows |
| Free margin | Pause below 30% |

The last two rows of that table exist because of one night. On 31 Aug → 1 Sep the EA sold a 22-point rally **five consecutive times** for −141.00: three tagged `TREND` (the 15M cloud said down while price rose) and two `CROSS-CTR` (it said up and the EA sold anyway). Nothing could notice it was repeatedly wrong on one side — the position cap, the slots and the opposing-entry rule were all satisfied throughout.

The cooldown is deliberately **one-sided**: two failed BUYs should not block the SELL those failures argue for. Repetition in one direction is the brake's job.

### Stop management

On every fill the EA re-anchors SL **and** TP to the price actually received, using the pip distances recorded for that ticket at send time (`RememberGeometry`). It keeps checking for `SyncStopsSeconds` (60) and attaches a stop to any position found without one.

The record is **in-memory** — a re-attach loses it for positions already open, and those fall back to the old cautious behaviour of leaving the TP alone.

---

## The panel

Rows worth knowing:

| Row | Meaning |
|---|---|
| `EA ALIVE` | Uptime, and how long since the panel was redrawn |
| `NEXT CLOSE` | Countdown to the next 1M / 5M / 15M close |
| `LIVE 5M` | Forming-bar values, marked `(not traded)` — the EA acts on closed bars |
| `BARS USED` | Timestamps of the bars actually driving decisions |
| `RSI 5M` | In ARM mode: remaining window per side, e.g. `arm BUY 4:12 / SELL cold` |
| `COOLDOWN` | Which side is held and which is still allowed |
| `BRAKE` | Appears only when a direction is blocked on a loss streak |
| `WIN RATE` | `today` from broker history; `overall` from the config epoch |

`today` and the daily trade count legitimately disagree: one counts positions **closed** since the rollover, the other counts positions **opened**.

---

## Diagnostics in the log

```
RSI EXTREME armed: BUY 1M5M  1M=26.8 5M=35.7 15M=50.1
TREND-RSI expired unfired after 6 bars.  turn=yes  last state: blocked: 1M EMAs oppose (4451.57/4453.32)
NEWS PROBE   HIGH 2026.09.01 22:00  ISM Manufacturing PMI  (blocks 21:45 - 22:15)
```

`turn=NEVER` means the RSI never came back through the level — the setup died on its own. `turn=yes` means something downstream stopped it, and `last state` names which gate. The two call for opposite fixes.

The EA also writes `TRENDEMA_HEARTBEAT.txt` to `MQL5\Files` as `time|tickAge|marketOpen|phase` for an external watchdog. `scripts/mt5-watchdog.ps1` can consume it; it is **not currently scheduled**, deliberately.

---

## Install

1. Copy the newest `.mq5` and `.ex5` into
   `…\MQL5\Experts\Advisors\`
2. Attach to an **M1 XAUUSDc** chart, allow algo trading
3. Confirm the startup banner in the Experts log names the version you expect

Because the filename changes every version, MT5 will not pick up a new build on its own — re-attach explicitly.

---

## Open items

- **The six-month backtest has never been run.** Every trade is already tagged per trigger, so one run would attribute edge properly. Live results so far are tens of trades across a dozen versions — not a clean sample of anything.
- The geometry memo does not survive a restart; persisting it to GlobalVariables would fix the gap.
- `RsiXArmExpiryBars`, `BarrierUse5M`, `RiskPercent`, the cooldown and the brake are absent from the config signature, so changing them does not reset the win-rate epoch.
- MT5's calendar grades importance differently from ForexFactory. The EA blocks on MT5's view, which is the more conservative of the two.
