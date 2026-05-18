# ICT / Smart Money Framework — Quick Reference

The exact vocabulary the agent uses when reading charts. If a term is used in a signal or journal entry, it means this — no other interpretation.

## Structure

- **BOS (Break of Structure)** — price breaks a prior swing high (in uptrend) or swing low (in downtrend). Confirms continuation.
- **CHoCH (Change of Character)** — price breaks the most recent swing low (in uptrend) or swing high (in downtrend). Confirms reversal.
- **Swing high / swing low** — a candle with at least one lower-high candle on each side (swing high) or higher-low candle on each side (swing low). We use 3-candle swings minimum.
- **Internal vs external structure** — external = HTF swings; internal = LTF swings within the HTF leg. We trade internal CHoCH only when it aligns with external structure.

## Points of Interest (POI)

- **Order Block (OB)** — the last opposing candle before a strong impulsive move that broke structure.
  - *Bullish OB:* last down candle before a bullish BOS
  - *Bearish OB:* last up candle before a bearish BOS
  - Refined OB = body of the candle; aggressive entry = wick to body
- **Fair Value Gap (FVG) / Imbalance** — a 3-candle pattern where the wicks of candle 1 and candle 3 don't overlap. The gap between them is the FVG.
  - *Bullish FVG:* candle 1's high < candle 3's low
  - *Bearish FVG:* candle 1's low > candle 3's high
- **Breaker Block** — a failed order block. Bullish breaker = a bearish OB that price ran through; now acts as support. Bearish breaker = mirror.
- **Mitigation Block** — the last candle in the OPPOSITE direction of the impulse before a CHoCH. Used as an entry POI on retests.

## Liquidity

- **Buy-side liquidity (BSL)** — resting buy stops above swing highs / equal highs. Price gets "drawn" here.
- **Sell-side liquidity (SSL)** — resting sell stops below swing lows / equal lows.
- **Liquidity sweep / grab / raid** — price wicks through a liquidity pool and reverses. **Required for an A-grade entry.**
- **Equal highs / equal lows** — two or more swing points at nearly the same price. High-probability liquidity pools.
- **Session liquidity** — Asia high/low, London high/low, NY high/low. Each session's extremes become the next session's liquidity.

## Premium / Discount

Drawn from the most recent impulse leg:
- **Premium** = upper 50% — sell zone
- **Discount** = lower 50% — buy zone
- **Equilibrium** = exactly 50%

We buy in discount, sell in premium. Entries in the wrong half fail criterion #5.

## Draw on Liquidity (DOL)

The next obvious liquidity pool the market is likely targeting. Used to set the TP. Examples:
- Above a clear range high with equal highs
- Below a session low
- Above/below a daily high/low

## Time

- We only trade during **killzones** (see `killzones.md`).
- ICT macros (e.g., 09:50–10:10 NY) are noted but not required.

## What we ignore

- Indicators (RSI, MAs, MACD) — not part of this framework
- Volume — not reliable on FX/spot gold retail feeds
- Fibonacci beyond the 50% premium/discount split
- News-driven moves outside our process

## How the agent narrates a chart (internal — for journal only, not user-facing)

When logging, the agent describes structure in this exact order:
1. HTF state (trend / range)
2. Last BOS or CHoCH and at what level
3. Most recent liquidity sweep
4. POI in play
5. Confirmation event (or absence of one)
6. DOL (target)
