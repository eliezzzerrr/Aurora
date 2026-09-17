# SRLevels EA — 4H-trend limits at support / resistance zones

MetaTrader 5 Expert Advisor for gold. A **separate system** from TrendEMA: its own
magic number (9101), its own kill switch (`SRLEVELS_STOP.txt`), its own heartbeat
(`SRLEVELS_HEARTBEAT.txt`). Attach to a **15M** chart on the gold symbol.

Current version: **`SRLevels_EA_v1.7.mq5`**: v1.6 plus **15M swing points as a level source**
(`UseEntryPivots`, weight 2.5 recency-scaled, 2-day lookback), so the intraday levels the coach
marks on his 15M chart appear as zones. v1.6: side from the **4H close against EMA9**
(`TrendMode = TREND_EMA_ONLY`: above = buy limits only, below = sell limits only; a flip
cancels the resting limits), **target at the first level beyond the entry, never under 2R**
(`TPMode = TP_NEXT_ZONE`, `MinRR = 2.0`, `ExtendToMinRR = true`), stop beyond the traded zone
(capped at 10.00), breakeven 1.5R. Seven versions shipped on 10 Sep: v1.0.1 (3R, cloud+MA50
gate), v1.1 (next-zone, gated), v1.2 (next-zone, no gate), v1.3 (3R, no gate), v1.4 (3R else
2R, no gate; minute-bar 2026: −1,514, PF 0.83), v1.5 (level target with a 2R floor, no gate),
v1.6 (same target, EMA9 gate). Nothing after v1.1 has a tester result of either kind. The operator's real-tick
tests on XAUUSDc gave PF 0.86 for the gated 3R build and PF 1.05 for the gated next-zone build;
the ungated modes have no real-tick result yet. See **Backtests**.

> Kill switch: drop `SRLEVELS_STOP.txt` into `MQL5\Files` and the EA cancels its
> limits and stops placing orders. Open positions keep their SL/TP at the broker.

---

## Where it comes from

Modelled on the operator's coach (19 chart samples, 26 Aug – 9 Sep 2026). The coach marks
three supports (S1–S3) below price and three resistances (R1–R3) above it, each usually a
zone, built from:

- prior 4H and 15M swing highs / lows, including old support flipped to resistance
- the Ichimoku cloud edges on 4H and 15M
- MA50 on 15M / 4H / D1, EMA9 on 4H / D1, MA200 on 4H
- Fibonacci 0.382 / 0.5 / 0.618 / 0.786 of the last big 4H swing

A zone gets stronger when sources stack (S3 on 28 Aug was fib 0.382 + MA50 15M + EMA9 D1).
Entries are **buy limits in tiers** — BL#1 aggressive at S1, BL#2 default at S2, BL#3
conservative at S3 — with take-profit at the nearest resistance (the 4,573 buy targeted
4,610 = R1).

Two deliberate departures:

| Coach | EA | Why |
|---|---|---|
| Also bought supports while the 4H was bearish (1 Sep) | The 4H picks the side. Above the cloud **and** the MA50 = buy limits only; below both = sell limits only; otherwise nothing | The operator asked for the 4H as the trend filter |
| Deeper buys added when a level broke, no visible stop | Every order carries a stop beyond the zone; a zone that stops you out is blocked for `ZoneLossBlockBars` | A cent account does not survive an Aug 29 candle without one |

---

## How it works

| Step | Detail |
|---|---|
| **Trend** (4H, closed bar) | `TrendMode`: cloud + MA50 agree (default), cloud only, MA50 only, or EMA9/MA50 stack |
| **Points** | Swing pivots on H1 (weight 1) and 4H (weight 2), the six MAs (1.5 each), four cloud edges (1.5), four fib levels (1.0). Older pivots are down-weighted slightly |
| **Zones** | Points within `ZoneMergeAtrMult` × ATR(14, H1) are merged, capped at two widths tall. Score = sum of weights; zones under `ZoneMinScore` are ignored |
| **Rank** | Nearest three qualifying zones below the market = S1..S3, above = R1..R3, at least `MinZoneDistancePips` away |
| **Entry** | `ENTRY_LIMIT` (default): one resting limit per enabled tier, matched to its zone by price overlap, re-priced when the zone drifts by `RepricePips`, expired after `PendingExpiryBars`. `ENTRY_REJECTION`: a 15M bar wicks into the zone and closes back out, enter at market |
| **Stop** | Beyond the far edge of the zone (`SL_ZONE`) or beyond the next zone out (`SL_NEXT_LEVEL`), plus `max(SLBufferPips, SLBufferAtrMult × ATR 15M)`. Widened to `MinSLPips`, refused above `MaxSLPips` |
| **Target** | R1 for buys / S1 for sells (`TP_R1_S1`), the first zone of any kind beyond the entry (`TP_NEXT_ZONE`), or a fixed multiple. Refused below `MinRR` |
| **Caps** | `MaxTradesPerDay` 3, `MaxConcurrentPositions` 2 (limits count), never long and short at once, 5% daily loss halt, day rolls at 17:00 ET |

Pips are gold pips: **1 pip = 0.01 = $0.01**.

Order comments carry the tier (`SRL-S1`, `SRL-R2`, `SRL-S1-RJ` for rejection entries), and the
close log line names it (`[tier 2]`), so results can be attributed per tier.

---

## Panel and chart

Rows: STATUS, 4H SIDE, 4H VALUES, NEXT CLOSE, R3 → R1, MARKET, S1 → S3 (band, score,
sources), LIMITS resting, POSITIONS, TODAY, ALL TIME. The six ranked zones are drawn as
filled rectangles (green support, red resistance) labelled with their sources.

---

## Install

1. Copy `SRLevels_EA_v1.0.mq5` and `.ex5` into `…\MQL5\Experts\Advisors\`
2. Attach to a **15M XAUUSDc** chart, allow algo trading
3. Confirm the `[SRL] Initialised.` banner in the Experts log

It can run on the same account as TrendEMA — different magic, different files — but two
EAs buying the same dip is twice the risk on one idea.

---

## Backtests (10 Sep 2026)

40 headless runs, XAUUSD on the Exness demo server, 15M, 1-minute OHLC modelling, 10,000
deposit, 0.5% risk. The 2026 run (1 Jan – 8 Sep) chose the defaults; 2025 is the
out-of-sample check and is the number to trust. Percentages are real here: the 2.0-lot cap
never binds on a standard-lot symbol at this risk, unlike the TrendEMA runs.

| Configuration | 2026 Jan–Sep | 2025 |
|---|---|---|
| As first written: SL beyond the zone, TP at R1, RR floor 1.0 | −846, PF 0.91, 308 trades | +1,540, PF 1.08, 525 trades |
| SL beyond the **next** zone + TP at the **next** zone | +530, PF 1.08 | +1,053, PF 1.14 |
| … + RR floor 0.6 | +1,205, PF 1.15 | +1,460, PF 1.16 |
| … + breakeven at 1.5R (best tested, one field away from the shipped build) | +1,619, PF 1.22, 291 trades, 1.6/day, 47.8% win vs 42.6% breakeven, DD 10.0%, 9 losses in a row | +1,416, PF 1.16, 327 trades, 1.3/day, 50.8% vs 46.4%, DD 18.3%, 8 in a row |
| **Shipped: fixed 3R target, zone stop capped at $10, breakeven 1.5R** | **+458, PF 1.07, 228 trades, 1.3/day, DD 8.1%** | **+1,904, PF 1.11, 519 trades, 2.0/day, DD 17.2%** |
| Rejection entries instead of limits, same geometry | +945, PF 1.36, 107 trades, 0.6/day, DD 3.9% | +715, PF 1.19, 147 trades, 0.6/day, DD 4.4% |

Rejected because it did not survive 2025:

- Excluding the US session (trade 22:00–13:00 GMT only): 2026 +1,263 PF 1.28, 2025 +236 PF 1.04.
- Breakeven at 0.7R: 2026 +2,207 PF 1.38, 2025 +929 PF 1.13.
- The limit in the middle of the zone: −2,043 in 2026. Deeper fills are the ones where the level breaks.
- No 4H filter (the coach's both-sides habit): −1,222 with the shipped geometry, −3,052 as first written.

Tier 2 lost on its own in both years (−109 and −151) but removing it changes slot
interactions more than it saves, so it stays on.

**Fixed 3R targets (requested 10 Sep, 16 runs).** A 3R target does not raise profit per
trade; the win rate falls in step with the payout and the expectancy ends up *lower*
than the shipped defaults.

| 3R variant | 2026 Jan–Sep | 2025 |
|---|---|---|
| 3R, next-zone stop (shipped stop) | −487, PF 0.96, DD 19% | +3,009, PF 1.17, DD 26% |
| 3R, zone stop, no breakeven (the pure version) | +716, PF 1.06, win 25.4% vs 24.3% breakeven | +468, PF 1.02, DD 29% |
| 3R, zone stop, breakeven 1.5R | +210, PF 1.02 | +2,102, PF 1.12 |
| 3R, zone stop capped at $10, breakeven 1.5R (best of the set) | +458, PF 1.07, 1.3/day, DD 8% | +1,904, PF 1.11, 2.0/day, DD 17% |
| 3R, rejection entries | −174, PF 0.96 | +3,927, PF 1.31, DD 9% |
| Only levels at least 3R away | +57, 0.4/day | −151 |
| 2R for comparison | −747, PF 0.93 | +992, PF 1.06 |

Per trade, the best 3R variant made 0.02% (2026) and 0.037% (2025) of equity against
0.056% and 0.043% for the next-zone target. 2025 was a trend year and flatters every
long-target setting; 2026 takes it back.

**The operator chose 3R anyway (v1.0.1, 10 Sep 2026), then ran it on the live terminal
with 100% real ticks on XAUUSDc, 1 Jan – 9 Sep 2026:** 220 trades, −296.58, PF 0.86; 41
targets, 139 full stops, 40 breakeven scratches. A quarter of the trades were over inside six
minutes (limit fills on a spike, the tight zone stop goes in the same move), and fills between
22:00 and 02:00 server time ran 12 won / 47 lost. The 2.0 lot cap bound on every trade because
the tester deposits USD against a symbol that pays in cents; set `MaxLotSizeCap = 0` for tester
runs on XAUUSDc.

**v1.1 therefore ships the next-zone geometry**: `TPMode = TP_NEXT_ZONE`, `MinRR = 0.6`,
`SLMode = SL_NEXT_LEVEL`, `MaxSLPips = 2500`, breakeven 1.5R. It has not yet been run on real
ticks. The 3R build is four fields away: `TPMode = TP_FIXED_RR`, `FixedRR = 3.0`,
`SLMode = SL_ZONE`, `MaxSLPips = 1000`.

The honest summary: the edge is thin. Profit factor 1.16 out of sample, a win rate about
four points above its own breakeven. Fifty live trades will not tell you whether it is real.
`ENTRY_REJECTION` trades a third as often with a quarter of the drawdown and a higher PF in
both years; it is the safer choice if 0.6 trades a day is acceptable.

Not yet tested: real-tick modelling, XAUUSDc on the live server, spread widening at the
daily break. The runner is `runbt.py` in the portable tester folder (see memory notes).

## 17 Sep 2026: the invalidation line (v1.13, tested, not deployed)

The side comes from the daily close against the Daily EMA9, and the EA never looked at that
line again during the day. On 17 Sep the close put the side at SELL under 4,329.76, gold
rallied 90.00 through the line, and the EA sold twice above it (19:09 at 4,333.84, 19:53 at
4,338.68), both stopped: −203.60 of a −306.00 day. The coach's map that morning had no
resistance above 4,317. He does not sell above his own invalidation.

`UseInvalidationLine` (v1.13): on a SELL day no sell limit or rejection entry may sit above
the line, on a BUY day none below it. While price is beyond the line every zone on the trade
side is beyond it too, so the side is paused with no extra state and resumes when price comes
back under. It does **not** flip the side: 16 Sep fired the same signal at 4,344, ran to 4,380
and the daily candle closed at 4,271.57. An intraday flip buys the top of that day. The panel
gets an `INVALIDATION` row with the line, where price is against it, and since when.

Live fills on the Daily rule, 14–17 Sep, re-scored against the line in force at the time:

| | Trades | W | L | Win % | P/L |
|---|---|---|---|---|---|
| As traded | 14 | 5 | 9 | 36% | +49.20 |
| With the line | 12 | 5 | 7 | 42% | +252.80 |

Both removed trades are the 17 Sep sells above the line. Nothing else on those four days was
beyond it. The 10–11 Sep trades ran on the 4H side rule and cannot be re-scored.

Tester, minute bars, XAUUSD on the demo, 10,000 USD, `MaxLotSizeCap=0`, otherwise the live
v1.12 defaults (tier 1 off, unlimited fills, cap 2, 500–1,000 stop, NY blackout, noon-ET
rollover):

| | 2026 Jan–Sep, line off | line on | 2025, line off | line on |
|---|---|---|---|---|
| Net | −1,341 | −1,140 | −758 | −221 |
| PF | 0.88 | 0.89 | 0.90 | 0.97 |
| Trades | 429 | 374 | 274 | 233 |
| W / L | 169 / 260 | 147 / 227 | 105 / 169 | 91 / 142 |
| Win % (needs) | 39.4 (42.0) | 39.3 (41.8) | 38.3 (40.4) | 39.1 (39.5) |
| Max DD | 18.5% | 14.7% | 11.2% | 6.9% |
| Losses in a row | 12 | 10 | 11 | 6 |

What it says. The line removes 13–15% of the trades and they are worse than average (22W 33L
in 2026, 14W 27L in 2025), so net, drawdown and the losing streaks improve in both years. The
win rate does not move. And the configuration it is bolted onto loses in the tester in both
years with or without it: the tier-1-off build that has been live since 15 Sep has no edge on
minute bars, which the 15 Sep tier-1-off runs already said. Tier 1, the bucket the tester
likes (+680 in 2026, +1,370 in 2025 in the v1.11.1 runs), is the one that lost 3 of 3 live and
was switched off.

Status: compiled clean, run in the portable tester, committed. **Not in the live Advisors
folder.** Before a live deploy, throttle the crossing log: it prints on every cross of the
line, 1,512 lines in the 2026 run, about eight a day.

**Replay of the live window, 10–16 Sep, real ticks, deposit 21,200, v1.13 defaults.** 8 trades,
4W 4L, +427.60, identical with the line on or off: no entry on those days sat beyond the
line, which is what the log re-score said. 17 Sep cannot be replayed until the server day has
closed; the tester only runs closed days.

| Day | Tester, line off | Tester, line on | Live, as traded |
|---|---|---|---|
| Thu 10 Sep | 2, 1W 1L, +109.53 | same | 3, 1W 2L, +20.10 (old side rule, buys) |
| Fri 11 Sep | 1, 0W 1L, −101.20 | same | 2, 0W 2L, −246.30 |
| Mon 14 Sep | 2, 2W 0L, +432.95 | same | 3, 2W 1L, +333.20 |
| Tue 15 Sep | 2, 1W 1L, +102.76 | same | 4, 2W 2L, +122.30 |
| Wed 16 Sep | 1, 0W 1L, −109.11 | same | 1, 0W 1L, −100.30 |

Where the configurations coincide the replay matches the live fills to the minute and within
15 pips (14 Sep 09:58, 15 Sep 10:01 and 18:54, 16 Sep 10:56). The differences are config: tier
1 was on live until 15 Sep and is off in v1.13, the NY blackout only went live on 16 Sep, and
the live terminal was off on the morning of 14 Sep.

**Consecutive-loss halt, measured post hoc on the same four runs** (every entry after the Nth
straight loss in the EA day is dropped; positions already open keep running). Nets here exclude
swap, so the baselines sit a little above the report figures.

| Halt after | 2026 line off | 2026 line on | 2025 line off | 2025 line on |
|---|---|---|---|---|
| none | −1,175 | −995 | −629 | −115 |
| 2 losses | −1,477 | −1,681 | −647 | −83 |
| 3 losses | −1,420 | −1,349 | −1,034 | −287 |
| 4 losses | −1,052 | −1,041 | −797 | −115 |

A halt after three straight losses costs 170 to 400 a year in every configuration: the trades
after a third loss win at least as often as the average trade. 17 Sep, where it would have
saved 203.60, is the day that prompted the idea and the exception. Rejected, 17 Sep 2026.
