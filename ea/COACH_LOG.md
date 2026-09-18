# Coach log — Jem Francisco posts vs SRLevels EA

A running record of the coach's published calls and what the EA did with the same market.
The operator asked on 14 Sep 2026 for every post shared in session to be kept here and mined
for changes that raise the win rate. Newest first.

Levels are price, not pips. 1 pip = 0.01.

---

## 2026-09-18 06:32 — He flips long, and publishes an actual trade plan

Three images: a Google Sheet headed **FOLLOW MY TRADING**, a 15M OANDA chart, and the Discord
post carrying them.

> Sharing the 15 minutes chart below as of 6:29 am, Gold retraces exactly w/in EMA9 in the
> Daily chart or S1- 4,343 in the 15M chart that I posted last night. It needs to breakout from
> MA50 (Blue line). 4,349 to regain its momentum to trade back w/in 4,350- 4,370 to max
> potential short term target at 4,400. We expect gold to move w/in the range (Support and
> Resistance) identified below.

**The bearish case is over.** He has been short since 11 Sep. Yesterday's rally closed the
Daily candle at 4,346.40, above the Daily EMA9, and this post has him buying the retrace into
that same EMA9. The EA flipped with him, independently, at 08:00 this morning:
`Side changed: SELL -> BUY [D1 close 4346.40 vs EMA9 4333.09]`. First time since this log
started that the EA and the coach turned on the same candle.

### The sheet — new, and the most explicit thing he has ever posted

Tab "Scalping" (there is a second tab, "Swing/Trend Follow Trading"). Header says
*"Initial Phase - Sharing 60% of my Actual Trading Execution"* and
*"Overall Strategy: Will depend on Bias for the Day (Green Candle - Bullish Overall Buy,
[Red] Candle - Overall Short)"*.

| # | Side | Entry | Targets | Invalidation | Session | Type | Tranche |
|---|---|---|---|---|---|---|---|
| 1 | Short | 4,400.00 | 4,350 / 4,370 / 4,390 | 4,410.00 | Asian–NY | Default (Med-High) | 1 of 2 |
| 2 | Short | 4,376–4,380 | 4,325 / 4,335 / 4,350 | 4,410.00 | Asian–NY | Aggressive (HIGH) | 2 of 2 |
| 1 | Buy | 4,340–4,343 | 4,360 / 4,380 / 4,400 | 4,278.00 | London–NY | Aggressive (HIGH) | 1 of 3 |
| 2 | Buy | 4,325–4,335 | 4,350 / 4,370 / 4,400 | 4,278.00 | London–NY | Default (Med-High) | 2 of 3 |
| 3 | Buy | 4,306–4,310 | 4,330 / 4,350 / 4,370 | 4,278.00 | London–NY | Conservative (Low) | 3 of 3 |

Reminders on the sheet: lot by risk appetite, 0.01 low / 0.05 medium / 0.10 high; **maximum 3
tranches per direction, to limit market exposure**.

15M chart levels: R3 4,380–4,400 · R2 4,365–4,372 (printed "4,465", a typo) · R1 4,356 ·
S1 4,340–4,343 · S1 4,323–4,325 · S1 4,306–4,312 · a red "Invalidation level zone" at 4,281.68.

### Against the EA, 08:00–09:30 today

| His level | EA zone | |
|---|---|---|
| Buy 1, 4,340–4,343 (aggressive) | 4,338.68–4,343.68, **score 18.9**, the session's best; buy limit rested at 4,343.68 from 08:30 | match |
| Buy 2, 4,325–4,335 (default) | 4,330.99–4,335.38, score 13.7 [fib 0.382, EMA9 D1, kumo M15, EMA9 H4, piv M15, MA50 D1, piv H1]; limit at 4,335.38 | match at the top of his band |
| Buy 3, 4,306–4,310 (conservative) | not ranked this morning | 35.00 below the market |
| Short 1 and 2, 4,376–4,400 | not tradeable | the EA is one-sided on a BUY day |

Neither buy limit had filled by 09:40; price went the other way, 4,343 to 4,362.

### Four things this post settles

**1. The tier ladder is his ladder.** Three tranches per direction, nearest = aggressive, furthest
= conservative, one limit each. That is exactly `TradeTier1/2/3`, arrived at independently on
10 Sep. It also says plainly that his **nearest** tranche is the high-risk one — the EA's tier 1,
which went 0-for-3 live and was switched off on 15 Sep. He rates it the same way and still takes
it, at a third of the size of his high-risk lot.

**2. His invalidation is two layers, and this log had only noticed one.** The Daily EMA9 decides
the *bias* (14 Sep: "needs to trade back above EMA9 in the Daily chart"), and that is what
v1.13.1 now uses to pick and pause the side. The *trade* invalidation is separate and structural:
4,278 for every buy tranche, 4,410 for every short, so one stop for the whole ladder, 65.00 below
the top entry. The EA puts a 6.50–7.50 stop beyond each zone edge. Unchanged gap, now with his
own numbers on it: his per-trade risk is roughly ten times the EA's, and his targets are 2 to 6
times further out.

**3. Sessions.** Buys are tagged London–NY, shorts Asian–NY. The EA's NY blackout (08:00–18:00 ET,
shipped 17 Sep at the operator's request) covers the whole New York half of his buy window.
The EA can only take his buy tranches between London and 20:00 Manila.

**4. Three targets per trade, scaled out.** The EA takes one, at the next zone with a 2R floor.
Partials were built and removed on the operator's instruction on 10 Sep ("no remove the
partials"). His first target on Buy 1 is 4,360, about 1.7R against his own invalidation; the
third is 4,400. Worth re-reading if the 2R floor ever comes back up.

**Nothing shipped off this post.** The alignment it shows is on the side rule and the tier
ladder, both already in. The two real divergences — his structural stop with scaled targets, and
both-sides trading — are the same two the operator has already decided against, on 10 and 14 Sep.

## 2026-09-17 06:58 — Daily map after the reversal: resistance 4,280–4,317, supports to 4,019

Chart only, no text. OANDA Daily. The 16 Sep candle that spiked to 4,380 closed back down with a
long upper wick, and price at post time is 4,269, under the Daily MA50 at 4,282 and under the
daily cloud (4,328–4,403). The bearish case he has held since 11 Sep survived its own
invalidation test by the daily close.

Chart annotations: R3 4,317 · R2 4,295–4,300 · R1 4,280–4,287 · S1 4,200–4,235 · S2 4,150 ·
S3 4,019–4,065. Red arrow at the MA50/cloud rejection, green arrow at the 3,942 swing low that
anchors his fib.

| His level | EA zone at 08:15 | |
|---|---|---|
| R3 4,317 | not ranked | above the top three |
| R2 4,295–4,300 | R3 4,295.42–4,296.05 (3.6), sell limit resting at 4,295.42 | match |
| — | R2 4,291.46–4,292.08 (2.8), sell limit resting at 4,291.46 | EA extra, between his R1 and R2 |
| R1 4,280–4,287, holds the Daily MA50 | S1 4,282.17–4,283.03 (6.4) and R1 4,285.88–4,286.87 (3.5) | match; price sat inside his band at rebuild, so the EA splits it into a support below and a resistance above |
| S1 4,200–4,235 | not ranked | 50.00–85.00 below the market, outside `MaxZoneDistancePips` |
| S2 4,150 / S3 4,019–4,065 | invisible | 120.00–265.00 away |

Side agrees: EA reads Daily close 4,271.57 against Daily EMA9 4,329.76, SELL. His chart says the
same with price under the MA50 and the cloud.

**Alignment on this post is the closest since 10 Sep.** Both of his tradeable resistances are EA
zones with limits resting in them. What still does not carry over is unchanged: his supports are
Daily-chart structure 50.00 to 265.00 below, the EA works a 45.00 window and takes 2R at a time.
He is short for a ride to 4,200 and below; the EA is short for 10.80.

Note for the record: the 16 Sep entry logged at 21:48 said the EA would flip to BUY if the daily
candle finished above 4,344. It finished at 4,271.57. No flip.

**What the day did, logged at 23:55.** Gold rallied about 90.00 from the 4,271.57 close to
4,363, through every level on his map. The EA, short all day by that same close, sold six
rallies and kept one: 1W 5L, -306.00, -1.45% of capital. Worst day since it went live.

| Time | Entry | Result |
|---|---|---|
| 08:42 | sell 4,291.46 [R2] | **+205.20** |
| 09:00 | sell 4,285.88 [R2] | -107.50 |
| 11:42 | sell 4,295.42 [R2] | -102.50 |
| 15:14 | sell 4,322.67 [R2] | -97.60 |
| 19:09 | sell 4,333.84 [R2] | -105.70 |
| 19:53 | sell 4,338.68 [R3] | -97.90 |

42 limits placed, 18 cancelled on re-rank, 1 on the blackout. Unlike 16 Sep, where a straight-line
rally let the re-rank pull the orders out of the path for one loss total, this one climbed in
steps and paused at each zone long enough to fill the limit resting in it.

**The post is what fixed it.** His map that morning topped out at R3 4,317 and he took nothing
above it, because his own invalidation - the Daily EMA9, the level this log named on 14 Sep -
sat at 4,329.76. The EA had been using that line to pick a side at the daily close and then
ignoring it for the rest of the day. The last two fills, 19:09 and 19:53, were sells above it:
-203.60, two thirds of the loss. Shipped the same night as v1.13.1, `UseInvalidationLine`:
no sell limit or rejection entry above the line on a SELL day, none below it on a BUY day, and
no intraday flip - the flip stays at the daily close where he keeps it. Re-scored over every
fill on the Daily rule, 14-17 Sep, it removes exactly those two trades and blocks no winner.
Tester, both years: 2026 -1,341 -> -1,140, 2025 -758 -> -221, drawdown and losing streaks down
in both, win rate flat. See `SRLevels_README.md`.

## 2026-09-16 22:51 — 4H bearish map: resistance 4,400 / MA50 4,360, targets restated

Chart only, no text. OANDA 4H, posted after the FED-day rally had already carried price from
4,283 to a 4,360 high. Same thesis as the 08:52 post, now with the ceiling named.

Chart annotations: Psychological resistance 4,400 · MA50 (4H, blue) 4,360 · red arrows on the
three prior rejections at the cloud/MA50 (~4 Sep 4,520, ~10 Sep 4,420, ~12 Sep 4,410) and two
more pointing at 4,400 and 4,360 as the next · "Bearish Scenario" · confirmation of further
downtrend on a break below 4,250–4,262 · short target 1 4,150–4,200 · short target 2
4,100–4,050. Ichimoku span readout 4,319.5 / 4,372.3; the forward cloud is bearish from about
4,320 to 4,400. Price 4,343.6 at post time, 16.00 under the MA50.

Read plainly: the bearish case survives the rally, and its line in the sand has moved up from
the Daily EMA9 (~4,344, his 11 Sep invalidation, which price is sitting on) to the 4H MA50 at
4,360 with 4,400 as the last word. Targets unchanged.

| His level | EA at 22:51 | |
|---|---|---|
| Psychological resistance 4,400 | no source for round numbers | third post to name it — open gap 2 |
| MA50 4H 4,360 | not in the last logged set; MA50 4H is an enabled source, so it enters on the next rebuild | zones last rebuilt 07:42 from price 4,283 and topped out at R3 4,301 — 60.00 below the market by post time |
| Break level 4,250–4,262 | S2 4,260.82–4,261.44 · S3 4,253.09–4,253.72 (07:42 set) | still matches, as at 08:52 |
| Targets 4,150–4,200 / 4,100–4,050 | invisible | 150.00–290.00 away against `MaxZoneDistancePips` 4,500 |

**SRLevels was in the NY blackout (20:00–05:00 local) when this was posted** — no limits, no
zone rebuild logged since 07:42, no trades after the single 4,321.90 stop-out earlier in the
day. Its zone set was built from 4,283 and price ended the day at 4,344, so the map it would
trade at 05:00 is not the one it is holding. Nothing to compare at the moment of the post
except that both read the side the same way: Daily close vs Daily EMA9, with the two now
touching — the EA flips to BUY if the daily candle finishes above 4,344 and he says the same
about 4,360/4,400 one timeframe up.

**The M1 scalper was working his ceiling from the other side.** TripleEMA (v1.3.2 → v1.4.1
over the evening) shorted 4,342–4,349 five times between 22:57 and 01:12, 3 wins and 2
stops, +131.70 — the same 4,340–4,360 band his arrows point at, reached by a 9/21/50 EMA stack
on M1 with 300–700-pip stops rather than by his levels. Coincidence of place, not of method;
no change follows from it.

**What it exposes, again:** the geometry, not the levels. His stop is 4,400, about 56.00 above
the market; his first target is 150.00 below it. That is a 2.7R trade the EA cannot express
inside a 45.00 window with a 2R floor, and open gaps 3 and 4 already say so. The only new item
is the third naming of 4,400 — the round-number source in gap 2 is now the most-repeated
unbuilt thing in this log.

## 2026-09-16 08:52 — breakdown levels named, target 4,100–4,050

> Team, sharing the 15 minutes chart below, take note of the further breakdown levels w/in
> 4,250–4,262 to confirm further downtrend to target 4,100–4,050 in favor of short sellers.
> Link to Head and Shoulders bearish reversal pattern last Sept. 11 trade guidance.

Chart annotations: R3 4,330 with EMA9 D1 at 4,342 · R2 4,310–4,317 · R1 4,300 · immediate
support 4,250–4,262, labelled "confirmation for further downtrend, breakdown from these
levels" · potential next retracement 4,050–4,100 in favour of short sellers.

| His level | EA zone at 10:43 | |
|---|---|---|
| R3 4,330 / EMA9 D1 4,342 | not ranked | 4th–5th up, outside the top three |
| R2 4,310–4,317 | not ranked at 10:43; became R1 4,310.61 and R2 4,316.06 by 10:45 | match once price rose |
| R1 4,300 | R2 tops at 4,300.52, R3 4,300.61–4,301.76 | match |
| — | R1 4,287.79–4,291.77 (5.9) | EA extra |
| — | S1 4,271.26–4,273.67 (4.7) | EA extra |
| Immediate support 4,250–4,262 | S2 4,260.82–4,261.44 (3.2) and S3 4,253.09–4,253.72 (4.8) | both inside his band |
| Target 4,100–4,050 | invisible | 180.00 away, four times `MaxZoneDistancePips` |

Side agrees: EA reads Daily close 4,288.29 against Daily EMA9 4,359.56, he quotes EMA9 D1 at
4,342 live on OANDA. Same conclusion, different feed and shift.

**The divergence is the trade, not the level.** He is positioning for a 180.00 ride to
4,100–4,050. The EA sells rallies for 2R a time inside a 45.00 window and will keep doing that
through the same move.

**What the day did, logged at 21:48.** The opposite of the call. Gold rallied about 100.00,
from 4,283 to 4,380, on the day of the FED decision. Price closed the session roughly 36.00
above the Daily EMA9 at 4,344, which is his own stated invalidation for the bearish case; if
the daily candle finishes there the EA flips to BUY at the close.

The EA sold into that rally exactly once: 0.12 lots at 4,321.90, stopped at 4,330.26 for
−100.30. It placed 29 limits and cancelled 12 of them on re-rank as price climbed through them.
Without the re-rank those orders would have filled in sequence, two slots at a time, for
something like six or seven consecutive stops. The re-rank behaviour the operator chose to keep
on 16 Sep earned its keep the same day. The NY blackout took over at 08:00 ET and cancelled the
last two resting limits.

## 2026-09-15 07:23 — bounce off the Daily MA50, and a stand-down order

> Gold did bounce from MA50 4,275 in the Daily chart yesterday after breaking down from 4,300
> due to the market expectation that FED will raise interest rate by 25 basis pts on Sept 16.
> Market expect 86% that FED will Raise interest rate (Bearish for Gold) based on FED CME
> Watch tool. Pres. Trump intervention may confuse the market and the entire narrative for
> Head and Shoulders Bearish reversal pattern maybe invalidated once the FED decided to Hold
> interest rate (Bullish for Gold) instead of raising it on Sept. 16. Gold really needs to
> trade back above EMA9 in the Daily chart (Current value 4,356) to totally invalidate any
> potential bearish reversal. A further breakdown below MA50 in the Daily chart will further
> confirm a trend reversal w/in the previous breakout level 4,200-4,220 (first) and
> 4,100-4,050 (2nd).

And, in a second post eleven minutes later:

> It would be prudent to resume the follow my trading template **after Sept. 16 meeting** to
> ensure a more clearer market direction after the most important event this week.

| His level | EA zone at 09:03 | |
|---|---|---|
| R3 4,322–4,338 | not ranked | above the EA window |
| R2 4,313–4,317 | not ranked | above the EA window |
| R1 4,306 | not ranked | EA tops out at 4,301.76 |
| — | R1 4,291.46–4,292.08 (4.8) | EA extra |
| — | R2 4,294.98–4,297.98 (6.2) | EA extra |
| — | R3 4,300.52–4,301.76 (3.4) | EA extra |
| S1 4,282 | S1 4,282.23–4,283.67 (4.0) | near exact |
| MA50 D1 4,275 | nothing | EA has the MA50 D1 as a source but it did not cluster |
| S2 4,264–4,272 | S3 4,263.46–4,264.09 (2.4) | bottom of his band |
| S3 4,253 | not ranked | below the EA window |

Both sides agree on SELL. His Daily EMA9 reads 4,356 live; the EA reads 4,377.38 because it
takes the closed-bar value at shift 1.

**The stand-down is the part the EA cannot act on.** It has no news awareness and will trade
through the FOMC decision at 02:00 Manila on 16 Sep. Sitting it out means dropping
`SRLEVELS_STOP.txt` into `MQL5\Files` by hand, which cancels resting limits and blocks new
ones but does not close an open position.

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
| He never trades **beyond** his invalidation, not just on the wrong side of it at the close | v1.13.1, `UseInvalidationLine` - the side pauses while price is past the Daily EMA9 |

## Tested and rejected — 14 Sep 2026

All four level-source gaps below were built (v1.10) and tested the same afternoon. **Every
one lost money in both years**, so all four ship defaulted off. Minute bars, per-tier
entries, cap 3, lot cap lifted:

| | 2026 Jan–Sep | 2025 |
|---|---|---|
| Baseline (v1.9.1 sources) | −517, PF 0.96, DD 12.0% | +3,463, PF 1.14, DD 9.7% |
| All four added | −1,524, PF 0.88, DD 18.9% | +2,222, PF 1.10 |
| Daily pivots only | −1,212 | +2,316 |
| Round numbers only | −1,134 | +2,903 |
| Daily fib only | −693 | +3,226 |
| Daily cloud only | −517 (no change) | +3,140 |

The trade count barely moved, 482 to 486 in 2026, so these did not add trades. They shifted
the boundaries and the ranking of zones already being traded, and shifted them worse. Nearly
all the damage landed in tier 2: −1,169 to −1,914 in 2026.

**This settles a standing question.** The gap between the EA and the coach is not the level
list. He uses more sources, the EA can now use the same ones, and copying them makes results
worse. Whatever he does that works lives in the judgment and the geometry, not in what he
draws on the chart.

## Appendix — the original 19 screenshots (10 Sep 2026)

Shared in one batch when the EA was first specified. Dates are read off each chart axis and
are approximate. Recorded for the level-construction patterns rather than the calls.

| Chart | Levels marked |
|---|---|
| 4H, ~5 Sep | R3 4,510 · R2 4,490 · R1 4,479 · S1 4,405–4,411 · S2 4,376–4,391 · S3 4,365–4,370 |
| 15M, ~4 Sep 10:58 | R3 4,500 · R2 4,493 · R1 4,487 · S1 4,467 · S2 4,456–4,458 · S3 4,420–4,430 |
| 4H, ~4 Sep 08:17 | Retracement 0.236 4,457.05 · 0.382 4,423.72 · 0.5 4,396.78 · 0.618 4,369.84 · 0.786 4,331.48 |
| 4H, ~4 Sep | R3 4,500–4,510 · R2 4,464–4,486 · R1 4,440–4,450 · S1 4,400–4,419 · S2 4,382–4,387 · S3 4,352–4,364 |
| 15M, ~3 Sep 13:30 | R3 4,500–4,510 · R1 4,440–4,450 · S1 4,395–4,397 · S2 4,364–4,382 · S3 4,344–4,352 |
| 15M, ~2 Sep 22:28 | Previous support turned resistance 4,396 · R3 4,396–4,420 · R2 4,374–4,387 · R1 4,344–4,355 · S1 4,323 · S2 4,315 · S3 4,282–4,308 · Kumo support D1 4,269 · MA50 D1 4,223 |
| 4H, ~2 Sep 13:51 | R3 EMA9 4H 4,355 · R2 4,335 · R1 4,326 · MA200 4H 4,289 |
| 4H, ~2 Sep 09:46 | R3 4,335–4,340 · R2 4,330 · R1 4,326 · MA50 D1 4,222 · downside R1 4,230 · R2 4,150–4,200 · R3 4,065–4,103 |
| 15M, ~1 Sep 18:28 | R3 4,415–4,423 · R2 4,396–4,400 · R1 4,389 · S4 4,350–4,362 (default) · S4 4,311–4,327 (conservative) |
| 5M, ~1 Sep 10:32 | BL#1 4,430–4,440 · BL#2 4,426 · BL#2 4,417 · BL#3 4,387–4,405 |
| 15M, ~1 Sep 07:59 | R3 4,486–4,500 · R2 4,464–4,472 · R1 4,450–4,455 · S1 4,430–4,440 · S2 4,417–4,426 · S3 4,387–4,405 |
| 15M, ~31 Aug 00:37 | R3 4,546 · R2 4,529 · R1 4,486–4,503 · S1 4,445–4,450 · S2 4,424 · S3 4,400 · MA50 current 4,539 |
| 1M, ~28 Aug 15:22 | TP 4,610 · lower end of aggressive BL 4,573 |
| 4H, ~28 Aug 08:14 | R3 4,643 · R2 4,621 · R1 4,618 · S1 4,593 · S2 4,585 · S3 4,550–4,563 · MA50 M15 4,546 · EMA9 D1 4,557 |
| 4H, ~27 Aug 21:53 | MA50 4H 4,540 · EMA9 D1 4,542 · historical support D1 4,529 |
| 15M, ~27 Aug 21:44 | R3 4,605 · R2 4,600 · R1 4,593 · S1 4,583 · S2 4,563 |
| 15M, ~27 Aug | R2 4,637–4,640 · R2 4,627–4,633 · R1 4,623–4,625 · S1 4,600 · S2 4,583–4,590 · S3 4,563 · EMA9 D1 4,549 |
| 1M, ~26 Aug 20:16 | R3 4,050 · R2 4,040 · R1 4,030 · MA50 15M 4,636 · BL#2 4,013–4,015 |
| 1M, ~26 Aug 18:49 | Same levels, later snapshot |

Patterns that came out of this batch and shaped v1.0: three tiers each side, bands rather than
lines, buy limits labelled BL#1 aggressive / BL#2 default / BL#3 conservative, and levels drawn
from swings, cloud edges, MA50 and EMA9 across 15M/4H/D1 plus fib retracements.

## Open gaps — still untested

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
