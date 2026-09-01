# Aurora — XAUUSD trading systems

Two independent systems for gold (XAUUSD), sharing a repo and nothing else.

| | What it is | Capital | Docs |
|---|---|---|---|
| **Aurora** | ICT/SMC **advisory** subagent. Reads chart screenshots, runs an 8-point checklist, emits a signal or NO-TRADE. Places no orders. | Demo 🧪 | this file |
| **TrendEMA EA** | MetaTrader 5 Expert Advisor. Trades **automatically**, on a funded account. | **Real money ⚠️** | [`ea/README.md`](ea/README.md) |

Their doctrines are separate. Aurora's killzones and grading rubric do not apply to the EA, and the EA's triggers are not Aurora patterns.

---

# Part 1 — Aurora (advisory agent)

A disciplined, strict-checklist system on 15m–1H timeframes, built on ICT / Smart Money Concepts. A custom Claude Code subagent reads chart screenshots, runs an 8-point entry checklist, and emits signal-only trade calls or NO-TRADE with the failing criterion named.

**Mission:** target 50% win rate at 2:1 RR. Edge comes from process discipline — rejecting B-grade setups — not from prediction.

**Phase:** DEMO 🧪 — forward-testing only, not live capital.

---

## The strategy in one sentence

> Short XAUUSD into sweep-and-reverse moves at obvious liquidity pools, aligned with higher-timeframe bias, only during London or NY killzones, with a 2:1 reward-to-risk minimum. (Symmetric for longs.)

## The 5-stage setup

Every A-grade trade follows this skeleton:

1. **Bias** — 1H + 4H clearly trending
2. **Sweep** — 15m wicks through a liquidity pool and closes back inside
3. **CHoCH** — 15m closes past the most recent swing low/high in trade direction
4. **Retest** — price pulls back into the 15m OB / FVG that caused the CHoCH
5. **Entry** — at the refined POI, SL beyond structural invalidation, TP at next opposing liquidity ≥ 2R away

One stage missing → NO TRADE.

## The 8-point strict checklist

| # | Filter | Pass condition |
|---|---|---|
| 1 | HTF bias | 1H BOS/CHoCH in trade direction |
| 2 | Liquidity sweep | A pool taken within last 6 h |
| 3 | 15m confirmation | CHoCH or BOS after the sweep |
| 4 | POI present | OB / FVG / breaker at entry |
| 5 | Discount / Premium | Entry on the correct half of the leg |
| 6 | SL at structure | Beyond swept liquidity / POI invalidation — not pip distance |
| 7 | TP ≥ 2R | Next opposing pool ≥ 2R away |
| 8 | Session | Inside London (3:00–6:00 PM PHT) or NY AM (8:30–11:30 PM PHT) |

One fail → NO TRADE. Non-negotiable.

---

## How it works

```
You upload a XAUUSD chart  →  Aurora runs the 8-point checklist
                           →  emits SIGNAL (entry/SL/TP at ≥ 2:1 RR)
                              or NO-TRADE with the failing criterion
                           →  logs structured entry to trades/journal.md

You report the outcome     →  Aurora updates the entry, recomputes
                              running stats, updates pattern library
```

### "Should I upload?" — user-side filter (30-second check)

Before sending any chart, run this in your head:

```
Q1: Did a 15m candle JUST CLOSE?       NO → don't upload
                                       YES ↓
Q2: Are we in a killzone?               NO → don't upload
                                       YES ↓
Q3: Did a TRIGGER EVENT print?          NO → don't upload
                                       YES → ✅ upload
```

**The only 4 trigger events that warrant an upload:**

1. **Sweep confirmed** — 15m closes clearly past a marked BSL/SSL with rejection
2. **CHoCH confirmed** — 15m closes past the most recent swing low/high
3. **Retest filling** — after sweep + CHoCH, price pulls back into the OB / FVG
4. **Thesis broken** — 15m closes clearly above structural invalidation; re-bias needed

Mid-candle wicks, marginal closes, chop continuation, or "just checking" → not triggers, don't upload.

---

## Journal protocol

Every analysis = one numbered entry in [`trades/journal.md`](trades/journal.md). Hard rules:

- **Never skip an entry.** Every Aurora invocation gets logged.
- **Pattern tag discipline.** Must be `#NN` (from `patterns/README.md`) or `novel — [short description]`. Never bare `novel`.
- **Outcome lifecycle.** Signal entries start `OPEN`; updated to `WON / LOST / BE` only when user reports. No-trade entries are `N/A`.
- **NO-TRADE reason taxonomy** — pick one:
  - **Gate fail** — a specific checklist criterion failed (e.g., `#2 no sweep`, `#8 off-killzone`)
  - **Circuit breaker** — a hard environmental override (high-impact news ±30 min, weekend gap, suspicious price action, chart unreadable)
  - **Checklist fail** — overall grade too weak even though no single criterion is a clean fail (B-grade watchlist)
- **Stats recomputed on every append.** The running stats block at the top of the journal is updated whenever an entry is added or an outcome filled in.

---

## Killzones (PHT)

User is in the Philippines (UTC+8). All times in PHT.

| Window | Local time | Status |
|---|---|---|
| Asia (user daytime) | 6:00 AM – 2:00 PM | Mark levels only — no trading |
| **London open** | **3:00 – 6:00 PM** | **Prime — most consistent gold moves** |
| Dead zone | 6:00 – 8:30 PM | Step away, dinner |
| **NY AM** | **8:30 – 11:30 PM** | **Prime — best volatility** |
| NY PM / after | 11:30 PM – 4:00 AM | Only A+ setups, otherwise sleep |

Trading outside these windows fails criterion #8 by doctrine.

---

## Phase: DEMO 🧪

Currently forward-testing on a demo account. Discipline is identical to live — every signal logged, every outcome tracked. Graduation criteria below.

### Graduation criteria (demo → live)

All four must be true before any live capital:

| Criterion | Threshold |
|---|---|
| Resolved trades in journal | ≥ 30 |
| Win rate at honest 2:1 RR | ≥ 45% |
| Total R | ≥ +5R |
| Rule-compliance audit | Clean |

If any fails at the 30-trade review, stay on demo. Live capital is earned, not assumed.

---

## Repository structure

```
.
├── README.md                    This file
├── CLAUDE.md                    Working notes for Claude Code (build, deploy, gotchas)
├── playbook.md                  Master reference — Aurora reads first on every analysis
├── ea/
│   ├── README.md                TrendEMA EA reference — strategy, triggers, risk
│   └── TrendEMA_EA_v*.mq5/.ex5  Every version, newest is the deployed one
├── doctrine/
│   ├── entry-criteria.md        The strict 8-point checklist (load-bearing)
│   ├── grading-rubric.md        A/B/C setup grading
│   ├── ict-framework.md         ICT / SMC vocabulary
│   └── killzones.md             Session timing rules (PHT-primary)
├── patterns/
│   ├── README.md                Pattern library (grows with usage)
│   └── diagrams/                Matplotlib-generated schematic teaching diagrams
├── trades/
│   └── journal.md               Every analysis logged here
├── scripts/
│   ├── journal-stats.py         Parses journal → JSON / pretty stats
│   └── mt5-watchdog.ps1         Restarts MT5 on a stale EA heartbeat (not scheduled)
├── charts/                      Optional drop folder for chart screenshots
└── .claude/
    ├── agents/aurora.md         The Aurora subagent definition (model: opus)
    └── commands/aurora-review.md  /aurora-review slash command
```

---

## Tooling

### `/aurora-review` slash command

Full performance audit: stats / session breakdown / pattern breakdown / loss themes / proposed doctrine changes. Doctrine changes are only proposed — never auto-applied — and require explicit user approval.

### `scripts/journal-stats.py`

Pure-stdlib Python parser for `trades/journal.md`. Emits JSON or human-readable summary. Used by `/aurora-review` and by Aurora's auto-flag triggers (drawdown alerts, pattern decay, milestone reviews).

```bash
python scripts/journal-stats.py --pretty   # human-readable
python scripts/journal-stats.py            # JSON
```

### Auto-flag triggers

Aurora silently checks the journal on every invocation and surfaces banners above the signal when:

- **Milestone**: 30 / 50 / 100+ resolved trades reached → `/aurora-review` due
- **Drawdown**: ≤ 35% WR over last 20 resolved trades → audit rule compliance
- **Pattern decay**: < 30% WR after 8+ instances → retirement candidate
- **Pattern emergence**: same novel setup 5+ times → propose adding to library
- **Rule violation streak**: 3+ consecutive losses with relaxed criteria

---

---

# Part 2 — TrendEMA EA (automated trader)

Full reference: **[`ea/README.md`](ea/README.md)**.

A MetaTrader 5 Expert Advisor on an M1 `XAUUSDc` chart, trading a **funded Exness cent account** at 1% risk per trade, up to 3 concurrent positions. Unlike Aurora it places, modifies and closes orders on its own.

**Kill switch:** drop `TRENDEMA_STOP.txt` into `MQL5\Files`.

### Strategy in one sentence

> The 15M Ichimoku cloud grants permission, the 5M EMA 20/50 picks direction, and entries are taken at the 1M EMA 50 — with two RSI triggers that time entries differently and one that ignores the trend altogether.

### Five triggers, each separately tagged

| Tag | Mechanism |
|---|---|
| `TREND` / `CTR` | Limit resting at the EMA 50, re-priced every 1M bar |
| `XING` / `XING-CTR` | Cross of the EMA 50, at market |
| `RSIX` | Multi-timeframe RSI washout, entered on the turn — trend-blind by design |
| `TRSI` | 1M RSI exhaustion *into* a confirmed 15M trend |

Every order is tagged so results can be attributed per mechanism.

### Risk

1% per trade (1.25% ceiling), 3 positions, one per trigger slot, no opposing entries, 6% daily halt, 60-minute cooldown on the losing side after a loss, and a brake that blocks a direction after 3 losses in a row on it until the 15M flips.

### Status

Live and iterating. Results so far span tens of trades across a dozen versions, which is **not a clean sample** — the six-month backtest remains the outstanding item, and every trade is already tagged for it.

---

## Key principles

- **Strict over loose.** One criterion fails → NO TRADE. No exceptions.
- **Wait for closes, not wicks.** Signals require a CLOSED 15m candle.
- **Killzone only.** The system doesn't trade outside London / NY AM.
- **TF-specificity.** Every structural reference is tagged with the timeframe it was observed on.
- **Doctrine never auto-changes.** Performance reviews propose; user approves.
- **The journal is sacred.** Pattern recognition improves only as fast as outcomes are honestly logged.
- **NO TRADE is the most profitable signal in the system.** Most of trading is not trading.

---

## License

Personal trading system. Not financial advice. The author accepts no responsibility for trading outcomes.
