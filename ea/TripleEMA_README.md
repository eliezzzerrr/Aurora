# TripleEMA Trend — M1 scalper on a 9 / 21 / 50 EMA stack

Third MT5 Expert Advisor in this repo. Attached to an **M1** chart on `XAUUSDc`, Exness cent account, **real money**. Requested 16 Sep 2026 as the replacement for TrendEMA, which was removed on 14 Sep.

Current version: **`TripleEMA_Trend_v1.0.1.mq5`**. Magic **7333**. Kill switch: drop `TRIPLEEMA_STOP.txt` into `MQL5\Files`.

> Removing the EA does **not** close an open position — it keeps its SL/TP on the broker.

---

## The idea

One timeframe, no bias. The EMA stack on M1 *is* the trend, and the EA follows it both ways.

| Stack | Meaning |
|---|---|
| EMA9 > EMA21 > EMA50 | **BULL** — buys only |
| EMA9 < EMA21 < EMA50 | **BEAR** — sells only |
| EMA9 in the middle | **NONE** — no trades, any pending arm is cleared |

All indicator reads are at **shift 1** (the last closed bar), so nothing repaints. Entries are market orders placed on the open of the next bar.

## The entry (BUY; SELL mirrors)

1. Stack is BULL.
2. **A bar has closed below EMA9 since the last entry** — the pullback. This arms the setup.
3. The last closed bar closed **above EMA9** and was **bullish** (close > open). → BUY at market.

Step 2 is what makes it a scalp rather than an always-in system. Without it, every bar of a trend that closes above EMA9 qualifies. `RequirePullback=false` removes it; `RequireCandleColor=false` removes the candle test.

A stack change clears the arm — a pullback inside the old trend is not a setup in the new one.

## Geometry

Pips are gold pips: **1 pip = 0.01 in price = $0.01**.

| | |
|---|---|
| **SL** | EMA50 (shift 1) ± `SLBufferPips` (5) — essentially on the slow EMA, as the example stops were drawn |
| **TP** | `RewardRatio` (1.5) × the SL distance |
| Refused if SL < `MinSLPips` (50) | a flat stack puts EMA50 on top of price; the lot would balloon. Two of the eight example trades had ~90–100 pip stops, so the floor is deliberately low |
| Refused if SL > `MaxSLPips` (1500) | price has run far from EMA50; the entry is late |

Both are **re-anchored to the actual fill** once the market order returns, so a slipped fill keeps its intended distances.

### The number that has to be beaten

```
breakeven = 1 / (1 + RewardRatio) = 40.0% at 1.5R
```

Spread is ~26 pips on a typical ~550-pip stop, so realistically **41–42%** to stand still. Compare TrendEMA at 1000/3000: 25%. A nearer target buys a higher win rate and raises the bar at the same time; this design accepts that trade.

The panel's `WIN TARGET` row derives the real figure from realised average win / average loss once there is one of each, and falls back to the geometry number until then.

## Risk

| Control | Default |
|---|---|
| Risk per trade | **0.25%** of equity, 0.50% hard ceiling, 2.0 lot cap |
| Concurrent positions | **1** |
| Daily loss halt | 3% realised; day rolls at 12:00 ET |
| Spread cap | 40 pips |
| Cooldown after loss | off (`CooldownMinutesAfterLoss`) |
| Session windows | all hours (`SessionWindowsET`, e.g. `"02:00-11:00"`) |
| Daily trade cap | off |

Lot sizing is TrendEMA's `CalcLot` verbatim: size from the SL distance, round **down**, reject rather than clamp above the ceiling, margin-checked.

## Panel

| Row | Meaning |
|---|---|
| `EMA 9/21/50` | shift-1 values |
| `STACK` | BULL / BEAR / NONE |
| `LAST BAR` | close vs EMA9, candle colour — the two trigger conditions |
| `ARM` | whether a pullback has been seen and what it is waiting for |
| `STATUS` | WAIT / ARMED / BLOCKED (and why) / FILLED / HALTED |
| `NEXT LOT` | what an entry from here would size to, and the SL distance |
| `WIN TARGET` | breakeven vs the running win rate, in points |
| `BAR USED` | open time of the **closed** bar the values came from (server time) |

## Known gaps in v1.0

- **No config-signature epoch.** The `overall` win rate covers every trade under magic 7333 and does not reset when inputs change. Change geometry and the statistics pool.
- **No backtest yet.** Every default above is from the operator's spec and example chart, not a sweep. The first tester run is the next step, before anything is tuned.
- No Friday cutoff, no news gate. Positions are short-lived by design, but a 1-minute scalp through a release will slip.
- Untested on the live account as of this writing.

## Install

1. Copy `.mq5` and `.ex5` to `…\MQL5\Experts\Advisors\`
2. Attach to an **M1 XAUUSDc** chart, allow algo trading
3. Confirm the `[T3EMA] Initialised.` banner in the Experts log

Runs alongside SRLevels (magic 9101) without conflict — every piece of state is keyed on symbol + magic. Risk stacks across EAs though: two EAs each at their own cap means double the account exposure.
