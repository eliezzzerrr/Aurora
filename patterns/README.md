# XAUUSD Pattern Library

This file grows over time. The agent reads the tail of this file on every invocation and references existing patterns when a new chart matches.

A pattern is only saved when:
1. The user says `save pattern` after an analysis, OR
2. The same setup has been observed at least twice across journaled trades (the agent will propose saving on the second observation)

## Entry template

```
### #NN · [short pattern name]
- Setup: [2–3 lines describing the structural sequence]
- Bias requirement: [HTF BOS bullish / bearish / either]
- Trigger: [the confirming event]
- Entry refinement: [OB / FVG / breaker]
- Invalidation: [what kills the setup]
- Observed instances: [trade #s]
- Win rate: [updated as outcomes come in]
- Avg R: [updated]
- First observed: [date]
- Last observed: [date]
```

---

## Patterns

*(empty — patterns will appear here as they are observed and saved)*
