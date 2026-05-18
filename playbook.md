# XAUUSD Playbook — Master Reference

This is the agent's master file. Every analysis starts here.

## Mission

Day-trade XAUUSD on 15m–1H using ICT/Smart Money Concepts. Target **50% win rate at 2:1 RR**. The edge is process discipline, not prediction.

## Current phase: **DEMO** 🧪

We are forward-testing the system on a demo account. Every signal, every trade, every outcome is logged the same way it would be on live capital — same discipline, same checklist, same NO-TRADE bias. The only difference is the money isn't real yet.

**Why demo first:** A brand-new strategy has zero validated history. Burning real capital to discover edge is how 90% of retail blows up. Demo gives us 30+ trades of evidence at zero financial cost.

**Demo-trap awareness:**
- Don't take B-grade trades "because it's free" — that corrupts the journal and tells us nothing about whether the real system works
- Don't over-position size in demo just to see big numbers — that doesn't translate to live emotional management
- Don't skip the journal because "it's just demo" — the journal IS the entire point of the demo phase
- **Trade demo like every pip is real.** That's the only useful kind of demo trading.

## Graduation criteria (demo → live)

All four must be true before going live:

| Criterion | Threshold | Why |
|---|---|---|
| Resolved trades | ≥ 30 | Below this, win rate is statistical noise |
| Win rate | ≥ 45% at honest 2:1 RR | Small undershoot of 50% target is acceptable; <45% means edge unproven |
| Total R | ≥ +5R | Positive expectancy, not just neutral |
| Rule-compliance | Clean | No journal entries with relaxed criteria in the last 10 trades |

If any of those fail at the 30-trade review, stay on demo. Build to 50 trades, then 100. Live capital is earned, not assumed.

## Bias

- **HTF trend** (1H or 4H, last 5 swing points): bullish / bearish / ranging
- A valid trade aligns with HTF bias. Counter-trend trades require an explicit 1H CHoCH and are graded one notch lower.

## Day-trading sequence (the only pattern family we trade)

Every A-grade setup follows this skeleton:

1. **HTF context** — clear BOS or CHoCH on 1H establishing direction
2. **Liquidity grab** — price sweeps a meaningful pool (prior session high/low, equal highs/lows, swing high/low)
3. **Reversal confirmation** — 15m CHoCH or BOS *against* the sweep direction
4. **POI retest** — price returns to the OB, FVG, or breaker that caused the CHoCH
5. **Entry** at the refined POI; SL beyond structural invalidation; TP at the next opposing liquidity pool ≥ 2R away

If any of those five elements is missing → NO TRADE.

## Killzones (PHT)

User is in Philippines (PHT, UTC+8). **All times shown in PHT — that's your local clock.**

- **London open:** 3:00 PM – 6:00 PM PHT — primary session for gold
- **NY AM:** 8:30 PM – 11:30 PM PHT — secondary, often best volatility
- **Asia (your daytime, 6 AM – 2 PM PHT):** rangebound, used for liquidity building only — do not trade
- **Off-killzone setups** are NO TRADE by default

(UTC reference: London 07:00–10:00 UTC, NY AM 12:30–15:30 UTC. Broker server is UTC−4 (NY); add 12h to broker clock for PHT.)

## Definitions of "fail"

A trade is invalidated (SL hit) when:
- Price closes 15m beyond the entry-defining POI on the wrong side
- A CHoCH occurs against the trade direction on 15m

A trade is closed early (manual) when:
- Pre-2R, price prints structure that explicitly invalidates the thesis (e.g., new HTF BOS against position). This is logged as the realized R, not as a full loss.

## What we don't trade

- Monday open (Sunday 21:00 UTC) and Saturday onwards (Friday 18:00 UTC) — weekend gap risk
- 30 minutes before or after high-impact USD news (NFP, FOMC, CPI)
- Asia session entries (6:00 AM – 2:00 PM PHT — your daytime)
- Ranges with no swept liquidity
- Setups where the next liquidity pool is < 2R from entry

## Output discipline

User-facing output is signal only. All reasoning is captured in `trades/journal.md`.

## "Should I upload?" decision tree (user-side filter)

The user runs this 30-second check BEFORE uploading any chart. The whole point: filter at the user's end so Aurora is only invoked on real trigger events, not on chop / impatience / mid-candle wicks.

```
Q1: Did a 15m candle JUST CLOSE (within ~60s)?
    NO  → don't upload, wait
    YES → continue

Q2: Are we inside a killzone (London 3–6 PM PHT or NY 8:30–11:30 PM PHT)?
    NO  → don't upload (except for pre-session briefing at 2:45 / 8:15 PM PHT)
    YES → continue

Q3: Did one of the 4 TRIGGER EVENTS print on the closed candle?
    NO  → don't upload, watch next candle
    YES → ✅ upload
```

### The only 4 events that warrant an upload

| # | Trigger | What it looks like |
|---|---------|--------------------|
| 1 | **Sweep confirmed** | 15m closes clearly past a marked BSL/SSL with rejection wick (e.g., wick above 4,545, body closes < 4,544) |
| 2 | **CHoCH confirmed** | 15m closes past the most recent 15m swing low (short) or swing high (long) |
| 3 | **Retest filling** | After sweep + CHoCH, price pulls back into the 15m OB / FVG — entry zone tagged |
| 4 | **Thesis broken** | 15m closes clearly above structural invalidation (e.g., above the 1H OB top); re-bias needed |

### What is NOT a trigger (do not upload)

- Mid-candle wicks or spikes — always wait for the close
- Marginal closes right on a level (close exactly at 4,545 = wait)
- Same chop state as last upload (no structural change)
- "Just checking in" or impatience
- Compression candles inside a range

## Review & adaptation

The system does **not** auto-learn. Doctrine never changes silently. But Aurora monitors performance and surfaces review triggers:

- **Auto-flag triggers** (run on every chart upload): milestone reviews at 30/50/100+ trades, drawdown alerts (<35% WR over last 20), pattern decay (<30% WR after 8+ instances), pattern emergence (5+ observations of a novel setup).
- **Manual review** via `/aurora-review` — full performance breakdown anytime. Parses `trades/journal.md` via `scripts/journal-stats.py`, emits stats / session breakdown / pattern breakdown / loss themes / proposed doctrine changes.
- **Approval required.** Any proposed doctrine change waits for your explicit OK before files are touched.

Below 30 resolved trades, treat all findings as directional, not conclusive.

## File map

- `playbook.md` — this file
- `doctrine/entry-criteria.md` — the strict checklist (load-bearing)
- `doctrine/ict-framework.md` — ICT terms the agent uses
- `doctrine/killzones.md` — session timing rules (PHT-primary)
- `patterns/README.md` — learned pattern library (grows over time)
- `patterns/diagrams/` — schematic teaching diagrams (matplotlib-generated PNGs)
- `trades/journal.md` — every signal + outcome (grows over time)
- `scripts/journal-stats.py` — journal parser, emits JSON or pretty stats
- `charts/` — drop chart screenshots here (optional; you can also paste them inline)
- `.claude/agents/aurora.md` — the agent definition (named **Aurora**)
- `.claude/commands/aurora-review.md` — `/aurora-review` slash command
