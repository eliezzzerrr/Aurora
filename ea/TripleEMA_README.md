# TripleEMA Trend — M1 scalper on a 9 / 21 / 50 EMA stack

Third MT5 Expert Advisor in this repo. Attached to an **M1** chart on `XAUUSDc`, Exness cent account, **real money**. Requested 16 Sep 2026 as the replacement for TrendEMA, which was removed on 14 Sep.

Current version: **`TripleEMA_Trend_v1.5.1.mq5`** plus the companion indicator **`TripleEMA_Lines.mq5`**. Magic **7333**. Kill switch: drop `TRIPLEEMA_STOP.txt` into `MQL5\Files`.

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
2. The last closed bar closed **above EMA9** and was **bullish** (close > open).
3. No position is open. → BUY at market on the next bar.

That is the operator's rule as stated. Since v1.4 the default is **`ENTRY_FIRST_THEN_TOUCH`**: the *first* entry in a stack uses that close rule; every entry after it is a continuation and fires the moment price **touches last bar's EMA9 from the trade side** — a wick is enough. `RequireCandleColor=false` drops the candle test on the close-rule entries.

### `EntryMode` — the pullback question

v1.0–v1.2 added a requirement I invented: a close on the far side of EMA9 before every entry. Checked against the eight example trades from 16 Sep it **fails three of the seven winners, including the two largest** — 05:31 and 07:55 were the *first* confirmation bar after the stack formed (a pullback inside a brand-new stack cannot exist yet, and clearing the arms on the flip made those entries impossible), and 06:02 was a continuation with no close below EMA9. So it is now a choice:

| Mode | Rule | Fits the examples |
|---|---|---|
| **`ENTRY_ANY_CLOSE`** (default) | any same-colour close across EMA9 while flat | 8 / 8 — also fires entries the operator skipped in extended trends |
| `ENTRY_FIRST_THEN_PULLBACK` | the stack's first confirmation bar enters; every later entry needs a pullback first | 7 / 8 — misses 06:02 |
| `ENTRY_PULLBACK_ONLY` | a pullback before every entry | ~5 / 8 |
| **`ENTRY_FIRST_THEN_TOUCH`** (default since v1.4) | first entry on the close rule; afterwards any touch of EMA9 from the trade side, intrabar | fills a point or two *earlier* than the boxes were drawn — better price, stack-width stop, nearer 1.5R, no confirmation at all on continuation entries |

**Why "from the trade side" matters.** After a stop-out, price sits beyond EMA9. If "at or past the line" counted, the EA would re-enter on the very rally that just stopped it. So price must first return to the trend side of EMA9 and then come back to touch it. **When is an entry "first"?** Measured in bars since the stack formed, not by whether this instance has traded (v1.4.1). The confirming close enters only within `FirstEntryWindowBars` (3) of the stack forming; after that, only a touch of EMA9 does. The age is walked back from history on attach, so restarting the EA inside a two-hour stack starts it in touch mode — v1.4 treated the next close as a "first" entry and sold at 4342.24 with a 383-pip stop, no touch, the exact entry the mode exists to replace. The `STACK` panel row shows the age.

The tester should pick between them, not the sample. `ResetArmOnClose` applies to the two arming modes; in `ANY_CLOSE` there is no arm to reset.

### No same-bar re-entry (`MinBarsAfterClose`, v1.3.3)

Twice on 16/17 Sep a take-profit filled on the first tick of a new bar and `ANY_CLOSE` re-entered seconds later — 51 s at 23:48, **4 s** at 00:22 — because the qualifying bar was the one the old trade had been open in. The example trades never do this; the tightest gap between a close and the next entry is about two minutes. So the bar being acted on must have **opened after the last close** (`MinBarsAfterClose = 1`; `2` demands a full bar between). It is narrower than the pullback modes: it keeps `ANY_CLOSE` and the continuation entries, and removes only the zero-gap artefact. Rebuilt from deal history on attach, so a re-attach cannot forget the last close.

**One position at a time, and the next entry only after the trade is closed.** `MaxConcurrentPositions=1` refuses any signal while a position is open. Since v1.1 a close also **wipes the arm** (`ResetArmOnClose`): a pullback seen *during* the trade no longer counts, so the full cycle — pullback → recross → entry — is required again after every exit. Without that, the first bullish close after a take-profit fired immediately with no pullback in between, which is a chase off the exit rather than the method.

## Geometry

Pips are gold pips: **1 pip = 0.01 in price = $0.01**.

| | |
|---|---|
| **SL** | EMA50 (shift 1) ± `SLBufferPips` (5) — essentially on the slow EMA, as the example stops were drawn |
| **TP** | `RewardRatio` (1.5) × the SL distance |
| Refused if SL < `MinSLPips` (**250**, v1.5.1) | a flat stack puts EMA50 next to price and the stop inside one M1 bar. First full live day, 17 Sep: the nine entries with stops of 210 pips or less went 2/9 for −300.70, four of them stopped inside 30 s, one slipped 87 pips on the fill and risked 0.48%; the other 25 went 11/25 for +179.10. The floor also refuses the two ~100-pip example trades and one 97-pip winner; the operator accepted that. As-logged, not re-run |
| Refused if SL > `MaxSLPips` (**1000**, v1.4.2) | price has run far from EMA50; the entry is late. Cut the other way once on 17 Sep: it refused 43 touches during a 500-pip squeeze, one of which would have paid, then allowed the 994-pip buy at the end of the run |

A refused entry logs once per bar per reason (v1.5.1); the `STATUS` and `NEXT LOT` rows carry the live reason.

On a slipped fill the **stop stays on the EMA50** — it is structural, not a pip count — and only the **target** is recomputed from the actual fill so the trade still pays `RewardRatio` on the distance really being risked. Risk moves slightly with the slip and the log prints the real figure. (v1.3 preserved pip distance instead, which walked the stop off the line by the slippage; the first live fill on 16 Sep landed 15 pips above the EMA50 it was meant to sit under.)

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
| Time stop | `MaxHoldMinutes = 60` (v1.5): a position still open after an hour is closed at market, whatever its P/L. Neutral on its first day: four closes, net −40.30 |
| No same-bar re-entry | `MinBarsAfterClose = 1` — the trigger bar must have opened after the last close |
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
| `NEXT LOT` | what an entry from here would size to, and the SL distance — or why nothing would fire (under the floor, over the cap) |
| `WIN TARGET` | breakeven vs the running win rate, in points |
| `AVG TIME` | average time in trade — all, wins, losses, today. Paired IN→OUT by position id. With the stop nearer than the target, losers should die fast and winners run; a drift in either says something about the tape. The `OPEN` row shows the current position's age |
| `BAR USED` | open time of the **closed** bar the values came from (server time) |
| `EMA LINES` | whether the 9/21/50 lines are drawn on the chart, and why not if they are hidden |

## EMA lines on the chart

`DrawEmas` (default on) adds the companion indicator `TripleEMA_Lines` to the chart — EMA 9 **yellow**, 21 **red**, 50 **blue**, the colours from the operator's TradingView setup. A built-in `iMA` handle cannot be recoloured from an EA, which is why the companion exists.

They draw **only while the chart timeframe equals `EntryTF`**. M1 lines on an H1 chart would be meaningless, and H1 lines would show a trend the EA does not trade. Change the chart timeframe and the EA adds or removes them on its own; the `EMA LINES` panel row says which state you are in. If a copy of the indicator is already on the chart — left behind by an earlier instance, or added by hand — the EA adopts it rather than adding a second, because MT5 refuses two indicators with the same short name in one window (error 4114). It waits for the indicator to finish its first calculation before adding, retries every 5 s, logs once a minute while it fails, and recreates its handle after twelve straight failures. The EA trades identically on any chart timeframe — it never reads the chart period, only `EntryTF`.

## Known gaps

- **No config-signature epoch.** The `overall` win rate covers every trade under magic 7333 and does not reset when inputs change. Change geometry and the statistics pool.
- **No backtest yet.** Every default above is from the operator's spec and example chart, not a sweep. The first tester run is the next step, before anything is tuned.
- No Friday cutoff, no news gate. Positions are short-lived by design, but a 1-minute scalp through a release will slip.
- First full live day, 17 Sep 2026: 34 trades, 13 wins, −121.60 net. The morning trended and paid (+260.80 at the 19:58 peak); the New York evening gave it all back on a flat stack (1/9, −382.40). The 250-pip floor is the response; whether New York needs a session window is one day of data and undecided.

## Install

1. Copy the EA `.mq5` and `.ex5` to `…\MQL5\Experts\Advisors\`, and `TripleEMA_Lines.mq5` / `.ex5` to `…\MQL5\Indicators\`
2. Attach to an **M1 XAUUSDc** chart, allow algo trading
3. Confirm the `[T3EMA] Initialised.` banner in the Experts log

Runs alongside SRLevels (magic 9101) without conflict — every piece of state is keyed on symbol + magic. Risk stacks across EAs though: two EAs each at their own cap means double the account exposure.
