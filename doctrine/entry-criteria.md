# Strict Entry Criteria — XAUUSD 5m execution · 15m/1H context

**This is the load-bearing file. Every signal must pass every item. One failure = NO TRADE.**

**TF architecture (5m port):** 1H = bias · 15m = intermediate structure · 5m = execution (sweep confirmation, CHoCH, POI, entry). The old 15m-execution system is retired; this file is canonical for the 5m system.

> **DOCTRINE CHANGE — 2026-07-18:** The session/killzone hard gate (old criterion #8)
> and the killzone scoring criterion are **removed by user decision**. Setups now
> qualify at any hour, 24/5. Advisor recommendation was to keep a session filter
> (journal #0017/#0020 evidence + 5m noise profile); the user chose full removal.
> The journal still logs Session on every entry — **the 30-trade review MUST
> break out win rate by session** to measure this change's impact.

## The 7-point checklist

| # | Criterion | Pass condition | Fail → NO TRADE reason |
|---|-----------|----------------|------------------------|
| 1 | **HTF bias** | 1H shows a clear BOS or CHoCH in trade direction within the last 20 candles, and 15m structure is not actively fighting it (no fresh opposing 15m CHoCH) | "No HTF BOS in trade direction" |
| 2 | **Liquidity sweep** | Price has swept an identifiable pool (prior session H/L, equal highs/lows, or visible 15m/1H swing point) within the last 2 hours | "No liquidity sweep before entry" |
| 3 | **5m confirmation** | After the sweep, 5m printed a CHoCH or BOS in trade direction | "No 5m CHoCH/BOS after sweep" |
| 4 | **POI present** | Entry is at a 5m order block, FVG, or breaker created by the confirming move | "No valid POI at entry" |
| 5 | **Discount/Premium** | For longs: entry below 50% of the confirming 5m leg. For shorts: entry above 50% of the confirming bearish leg | "Entry not in discount/premium zone" |
| 6 | **SL beyond structure** | Stop sits beyond the swept liquidity or beyond the POI's structural low/high — not a fixed pip distance | "Stop not at structural invalidation" |
| 7 | **TP ≥ 2R** | The next opposing liquidity pool (or HTF level) is at least 2R from entry | "Next liquidity < 2R from entry" |

## Killflag overrides (any one = NO TRADE regardless of checklist)

These are environmental circuit breakers, NOT session-quality filters. They stay.

- High-impact USD/Gold news within ±30 minutes
- Weekend (Saturday 2:00 AM PHT onward), Sunday open, Monday open (before 6:00 AM PHT — thin, gap-driven)
- Visible erratic / news-driven candles (long wicks, gaps) in the last 4 candles
- DXY moving sharply against the trade thesis (if visible / mentioned)
- Chart resolution too low or key levels off-screen to verify items 1–7

## 5m port notes (provisional values — backtest-tunable)

The 5m port scales time windows to bar-equivalents; it does NOT invent new
edge assumptions. Values marked *provisional* are starting points to be tuned
one-at-a-time from backtest evidence, never by feel:

| Parameter | 15m value (old) | 5m value (now) | Status |
|---|---|---|---|
| Sweep recency window | 6 h (~24 bars) | 2 h (~24 bars) | scaled, provisional |
| SL buffer beyond structure | 3–5 pips | 2–4 pips | scaled, provisional |
| Stop-width sanity band (rubric modifier) | 8–40 pips | 5–25 pips | scaled, provisional |
| Grade floor | A- (13/18) | A- (12/16) | **primary selectivity knob** |

**The grade floor is the main lever for chasing the 60% WR target.** If backtest
WR-by-grade shows A+ setups winning materially more than A-, raise the floor —
that trades frequency for hit rate. Raise it only on backtest evidence.

**5m hazard note (heightened since the session gate was removed):** the 5m
prints ~3× more sweep/CHoCH sequences than the 15m, and most of the extra ones
are noise — disproportionately in low-volume hours. With no session gate, the
ONLY filters standing between noise and a signal are checklist #1 (15m must not
fight the 1H) and the A- grade floor. Hold both without mercy. If the session-WR
breakdown at review shows off-session trades dragging the win rate, propose
re-introducing a session filter with the data in hand.

## Grading

**See `doctrine/grading-rubric.md` for the full 9-criterion, 16-point scoring system.** That file is canonical.

Quick summary of the scale:

| Grade | Score | Action |
|-------|-------|--------|
| **A+** | 15–16 | TRADE — highest conviction |
| **A** | 13–14 | TRADE — standard signal |
| **A-** | 12 | TRADE — note weakness |
| **B+ / B / B-** | 7–11 | NO TRADE — watchlist or dismiss |
| **C / D / F** | 0–6 | NO TRADE — log and forget |

Hard floor: any score < 12 (below A-) is NO TRADE. Any killflag (news ±30 min, weekend gap, news-driven candles, DXY divergence, chart resolution) forces **F**.

## Stop loss placement reference

- **Sweep + OB entry:** SL beyond the swept wick by 2–4 pips
- **Sweep + FVG entry:** SL beyond the FVG's far edge by 2–4 pips
- **Breaker entry:** SL beyond the breaker block's structural high/low by 2–4 pips

Never set SL based on pip distance alone. Structure defines the stop; the stop defines the position size (which the user calculates).

**5m spread warning:** tighter 5m stops mean spread + slippage consume a larger
fraction of 1R than on the 15m. A 6-pip stop with a 2-pip spread is paying 33%
of risk in costs before the trade starts. If the structural stop is < 5 pips,
the setup is too tight for gold — NO TRADE (see rubric stop-width modifier).
This bites hardest in low-volume hours, where spreads widen — exactly the hours
the removed session gate used to exclude.

## Take profit reference

Primary TP = next opposing liquidity pool:
- For longs: nearest buy-side liquidity above (equal highs, prior session high, obvious swing high)
- For shorts: nearest sell-side liquidity below

If primary TP < 2R, NO TRADE (criterion 7).
If primary TP > 4R, set TP at exactly 2R and note "extended target available" in the journal — the user can scale out manually.
