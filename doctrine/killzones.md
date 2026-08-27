# Killzones & Session Rules

> **STATUS: INFORMATIONAL ONLY since 2026-07-18.** The killzone hard gate and
> killzone scoring were removed from doctrine by user decision — sessions no
> longer block or grade a setup. This file remains as session-character
> reference (when sweeps tend to be clean vs muddy, spread behavior, session
> liquidity mapping) and for the journal's `Session:` field. The weekend /
> Monday-open / news windows listed below are still enforced as killflags in
> `entry-criteria.md` — those are gap/spread protection, not session filters.

**All times PHT (Philippine Time). UTC IS NEVER USED ANYWHERE IN OUTPUT.** User is in the Philippines — every time, every reference, every label uses PHT only.

Broker MT5 server runs on UTC. **Add 8 hours to broker clock to get PHT.** Example: broker shows `02:48 PM` → PHT is `10:48 PM`. The agent NEVER displays the intermediate broker/UTC time — always convert internally and output PHT only.

The agent always asks the user to confirm chart timezone if a screenshot's timestamp is ambiguous.

## Tradeable killzones

| Killzone | PHT | What we do | Why |
|----------|-----|------------|-----|
| **London open** | **3:00 PM – 6:00 PM** | Primary trading window | Gold's most consistent directional moves; Asia liquidity often swept here |
| **NY AM** | **8:30 PM – 11:30 PM** | Secondary window — best volatility of the day | USD-driven moves; runs on London highs/lows; London/NY overlap |

## Build-up / observation only

| Period | PHT | What we do |
|--------|-----|------------|
| Asia session | 6:00 AM – 2:00 PM | Mark Asia high & Asia low — these are liquidity for London |
| London close → NY open | 6:00 PM – 8:30 PM | Watch for consolidation; mark London H/L |
| NY PM | 11:30 PM – 4:00 AM | Lower probability, only A+ setups with very strong HTF context |

## NO TRADE windows

- **Saturday 2:00 AM PHT onward** — weekend gap risk
- **Monday 5:00 AM PHT** open — thin liquidity, gap-driven
- **±30 min** around high-impact USD/Gold news (NFP, FOMC, CPI, PPI, retail sales, ISM)
- **Asia session entries** — Asia is for liquidity *building*, not trading

## Common patterns by killzone

### London open (3:00 PM – 6:00 PM PHT)
The bread-and-butter session.
- Asia range usually exists. London either sweeps Asia high → reverses down, or sweeps Asia low → reverses up. ("Asia sweep + London reversal")
- Most A-grade setups come from London sweep + 5m CHoCH + retest of the 5m OB/FVG, targeting opposite Asia/London extremes.

### NY AM (8:30 PM – 11:30 PM PHT)
- Typical move: NY sweeps London's high or low, then runs in the opposite direction toward the prior day's level.
- Watch for the **9:30 PM PHT** news candle (US economic data release window) — if no major news, the candle's wick often forms the day's POI.

## Session-aware checklist additions

- If current candle time is **outside** the killzones (PHT), criterion #8 fails → NO TRADE.
- If the chart shows price entering a killzone within the next 1–2 candles but the killzone hasn't started, hold off and watch — log as B-grade watchlist.
- If the chart has no timestamp visible, the agent must ask the user for the current session before signaling.

## DST notes (for the agent's awareness)

- The Philippines does **not** observe DST — PHT is always UTC+8.
- London / NY do observe DST. The PHT killzone hours above assume **DST is in effect** in London/NY (March–October). During winter (November–March):
  - London open in PHT shifts to **4:00 PM – 7:00 PM PHT**
  - NY AM in PHT shifts to **9:30 PM – 12:30 AM PHT**
- The agent should check the current month and adjust PHT killzone references accordingly.
