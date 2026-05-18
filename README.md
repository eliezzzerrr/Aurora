# Aurora — XAUUSD ICT/SMC Day-Trading Agent

A disciplined, strict-checklist trading system for gold (XAUUSD) on 15m–1H timeframes, built on ICT / Smart Money Concepts. Operates via a custom Claude Code subagent that reads chart screenshots, runs an 8-point entry checklist, and emits signal-only trade calls or NO-TRADE with the failing criterion named.

**Mission:** target 50% win rate at 2:1 RR. Edge comes from process discipline — rejecting B-grade setups — not from prediction.

**Phase:** DEMO 🧪 — forward-testing only, not live capital.

## How it works

1. User uploads a XAUUSD chart screenshot (15m/1H/4H or multi-pane).
2. The `aurora` subagent reads the chart, applies the strict 8-point checklist, and outputs:
   - **A signal** (BUY / SELL with entry / SL / TP at minimum 2:1 RR), or
   - **NO TRADE** with the single failing criterion.
3. Every analysis appends a structured entry to `trades/journal.md`.
4. When the user reports an outcome (`won` / `lost` / `+2R`), Aurora updates the journal and recomputes running stats.

## The strategy in one sentence

> Short XAUUSD into sweep-and-reverse moves at obvious liquidity pools, aligned with higher-timeframe bias, only during London or NY killzones, with a 2:1 reward-to-risk minimum. (Symmetric for longs.)

## Repository structure

```
.
├── playbook.md                  Master reference — read first on every analysis
├── doctrine/
│   ├── entry-criteria.md        The strict 8-point checklist (load-bearing)
│   ├── ict-framework.md         ICT / SMC vocabulary used by the agent
│   └── killzones.md             Session timing rules (PHT-primary)
├── patterns/
│   ├── README.md                Pattern library (grows with usage)
│   └── diagrams/                Matplotlib-generated schematic teaching diagrams
├── trades/
│   └── journal.md               Every analysis logged here
├── scripts/
│   └── journal-stats.py         Parses the journal into JSON / pretty stats
├── charts/                      Optional drop folder for chart screenshots
└── .claude/
    ├── agents/aurora.md         The Aurora subagent definition
    └── commands/aurora-review.md  /aurora-review slash command
```

## Key principles

- **Strict over loose:** one criterion fails → NO TRADE. No exceptions.
- **Killzone only:** London 3:00–6:00 PM PHT, NY AM 8:30–11:30 PM PHT.
- **Wait for closes, not wicks.** Signals require 15m candle closes, never mid-candle prints.
- **Doctrine never auto-changes.** Performance reviews surface proposed changes; user approves explicitly.
- **Journal is sacred.** Pattern recognition improves only as fast as outcomes are honestly logged.

## Graduation criteria (demo → live)

All four must be true:

| Criterion | Threshold |
|---|---|
| Resolved trades | ≥ 30 |
| Win rate at honest 2:1 RR | ≥ 45% |
| Total R | ≥ +5R |
| Rule-compliance audit | Clean |

## License

Personal trading system. Not financial advice. The author accepts no responsibility for trading outcomes.
