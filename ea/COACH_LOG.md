# Coach log — Jem Francisco posts vs SRLevels EA

A running record of the coach's published calls and what the EA did with the same market.
The operator asked on 14 Sep 2026 for every post shared in session to be kept here and mined
for changes that raise the win rate. Newest first.

Levels are price, not pips. 1 pip = 0.01.

---

## 2026-09-14 07:25 — gap down, H&S still pending

> Gold gap down today as a result of continuous escalation of US and Iran War (Oil still
> trading at $100+ per barrel Bearish for Gold due to Inflationary Risk). The head and
> shoulders bearish reversal pattern may still materialize if Gold will eventually breakdown
> from 4,300. Gold needs to trade back above EMA9 in the Daily chart (currently value 4,380)
> first and Psychological resistance at 4,400 (2nd) to initially invalidate.

| His level | EA zone at 09:01 | |
|---|---|---|
| 4,400 psychological resistance | not ranked | beyond `MaxZoneDistancePips` |
| 4,377 immediate resistance | not ranked | 4th up; EA ranks 3 |
| 4,342–4,350 immediate resistance | R1 4,346.89–4,351.84 (10.1) | match |
| S1 4,328–4,330 | S1 4,328.40–4,331.17 (5.9) | near exact |
| S2 4,300–4,312 | S3 4,310.83–4,313.62 (11.0) | top of his band |
| S3 4,292 | not ranked | below the EA's three |

EA side: SELL, agreeing with him. **Drove v1.8**: `TrendEMATF = PERIOD_D1`, because the EA's
EMA9 was on H4 at 4,346.89, 33.00 below his Daily 4,380, and would have flipped to BUY on a
bounce he was still calling a downtrend.

## 2026-09-11 11:36 — Daily chart, retracement map

Daily values from his chart: MA50 **4,268.24**, EMA9 **4,382.57**, daily cloud
**4,430.13 / 4,328.45**. Fib drawn 4,697.00 → 3,942.93:

| Ratio | Price |
|---|---|
| 0.236 | 4,519.04 |
| 0.382 | 4,408.94 |
| 0.5 | 4,319.96 |
| 0.618 | 4,230.98 |
| 0.786 | 4,104.30 |

He is watching 0.618 and 0.786 as technical-bounce buys in a downtrend.

## 2026-09-11 10:22 — Head and Shoulders, short bias

> Neckline – Major support level 4,311. Psychological support 4,300. Our strategy after the
> breakdown will focus on 80% short selling and only 20% for technical bounce. CPI to be
> released tonight expected higher than previous 3.4% as a result of the PPI data last night,
> hence we expect Gold to continue going down further prior to FED meeting on Sept 15–16.

| | |
|---|---|
| Aggressive entry | 4,340–4,350 |
| Default entry | 4,375–4,391 |
| Invalidation | 4,438 |
| Initial targets | 4,282 · 4,230 · 4,200 |
| Scalp bounce levels | 4,282 · 4,311–4,315 |
| D1 MA50 + Kumo confluence | 4,268 |

> Heads up, buying in anticipation for a technical bounce during a strong downtrend is a
> countertrending strategy, hence conservative approach in taking profits and cutting your
> losses is necessary.

## 2026-09-10 09:46 — 15M levels

R3 4,442 · R2 4,430 · R1 4,420 · S1 4,400–4,405 · S2 4,391 · S3 4,375–4,386.

His R1 4,420 and S2 4,391 were 15M swing points the EA could not see, since it collected
pivots from H1 and H4 only. **Drove v1.7** (`UseEntryPivots`, 15M swings as a source).

---

## What the posts have changed so far

| Observation | Shipped |
|---|---|
| His intraday levels are 15M swings | v1.7, 15M pivot source |
| His bands are lines and ~5.00 zones whatever the ATR | v1.7.2, fixed 250-pip merge |
| His invalidation is the **Daily** EMA9 | v1.8, `TrendEMATF = PERIOD_D1` |
| He rests limits at every tier; the EA's nearest tier kept getting sliced | v1.9, rejection on tier 1 only (operator's idea, best of four tested) |

## Open gaps — candidates, none tested yet

1. **Fib is computed on the H4, his is on the Daily.** `CollectFib` scans `FibSwingBars` bars
   of `TrendTF`. His 0.618 at 4,230.98 and 0.786 at 4,104.30 are Daily and invisible to the EA.
   A `FibTF` input defaulting to D1, or a second Daily fib source, would put them in the set.
2. **Round numbers are levels for him, and the EA has no source for them.** 4,300 and 4,400
   are named in two consecutive posts. A "psychological level" source at each 50.00 or 100.00,
   low weight so it only counts as confluence, is a few lines.
3. **`MaxZoneDistancePips` 4,500 (45.00) hides his structural targets.** 4,268, 4,230 and
   4,200 are all out of view from 4,338. This caps the EA to a 45.00 window and is the
   mechanical reason it cannot hold for the moves he is playing for.
4. **Geometry is the real divergence, not levels.** His stop is the 4,438 invalidation, about
   90.00 from the aggressive entry; the EA's are 4.00 to 10.00. His targets are 0.7R to 1.6R
   against that stop; the EA's floor is 2R. Same levels, twenty times the timeframe. At 0.5%
   risk on a 90.00 stop this account sizes to the broker minimum, so copying him directly is
   not available — but a middle setting has never been tested.
