# Strict Entry Criteria — XAUUSD 15m–1H

**This is the load-bearing file. Every signal must pass every item. One failure = NO TRADE.**

## The 8-point checklist

| # | Criterion | Pass condition | Fail → NO TRADE reason |
|---|-----------|----------------|------------------------|
| 1 | **HTF bias** | 1H shows a clear BOS or CHoCH in trade direction within the last 20 candles | "No HTF BOS in trade direction" |
| 2 | **Liquidity sweep** | Price has swept an identifiable pool (prior session H/L, equal highs/lows, or visible swing point) within the last 6 hours | "No liquidity sweep before entry" |
| 3 | **15m confirmation** | After the sweep, 15m printed a CHoCH or BOS in trade direction | "No 15m CHoCH/BOS after sweep" |
| 4 | **POI present** | Entry is at a 15m order block, FVG, or breaker created by the confirming move | "No valid POI at entry" |
| 5 | **Discount/Premium** | For longs: entry below 50% of the last 15m bullish leg. For shorts: entry above 50% of the last bearish leg | "Entry not in discount/premium zone" |
| 6 | **SL beyond structure** | Stop sits beyond the swept liquidity or beyond the POI's structural low/high — not a fixed pip distance | "Stop not at structural invalidation" |
| 7 | **TP ≥ 2R** | The next opposing liquidity pool (or HTF level) is at least 2R from entry | "Next liquidity < 2R from entry" |
| 8 | **Session** | Current time is inside London (**3:00 PM – 6:00 PM PHT**) or NY AM (**8:30 PM – 11:30 PM PHT**) killzone | "Off-killzone setup" |

## Killflag overrides (any one = NO TRADE regardless of checklist)

- High-impact USD/Gold news within ±30 minutes
- Weekend (Saturday 2:00 AM PHT onward), Sunday open
- Visible erratic / news-driven candles (long wicks, gaps) in the last 4 candles
- DXY moving sharply against the trade thesis (if visible / mentioned)
- Chart resolution too low or key levels off-screen to verify items 1–7

## Grading

| Grade | Meaning | Action |
|-------|---------|--------|
| **A** | All 8 criteria pass, no killflags | **TRADE** — emit signal |
| **B** | 6–7 pass, no killflags | NO TRADE — log as watchlist |
| **C** | ≤5 pass, or any killflag | NO TRADE — log and forget |

Only A-grade setups produce a buy/sell signal.

## Stop loss placement reference

- **Sweep + OB entry:** SL beyond the swept wick by 3–5 pips
- **Sweep + FVG entry:** SL beyond the FVG's far edge by 3–5 pips
- **Breaker entry:** SL beyond the breaker block's structural high/low by 3–5 pips

Never set SL based on pip distance alone. Structure defines the stop; the stop defines the position size (which the user calculates).

## Take profit reference

Primary TP = next opposing liquidity pool:
- For longs: nearest buy-side liquidity above (equal highs, prior session high, obvious swing high)
- For shorts: nearest sell-side liquidity below

If primary TP < 2R, NO TRADE (criterion 7).
If primary TP > 4R, set TP at exactly 2R and note "extended target available" in the journal — the user can scale out manually.
