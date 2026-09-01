# CLAUDE.md

Guidance for Claude Code working in this repository.

## What lives here

Two independent systems that share a repo and a symbol (XAUUSD) and nothing else:

| | What it is | Where |
|---|---|---|
| **Aurora** | An ICT/SMC *advisory* subagent. Reads chart screenshots, runs an 8-point checklist, emits a signal or NO-TRADE, logs to a journal. Places no orders. | `.claude/agents/aurora.md`, `doctrine/`, `patterns/`, `trades/`, `playbook.md` |
| **TrendEMA EA** | A MetaTrader 5 Expert Advisor that trades **real money, automatically**, on `XAUUSDc`. | `ea/` |

Do not blend their doctrine. Aurora's killzones, grading rubric and 8-point checklist have no bearing on the EA, and the EA's triggers are not Aurora patterns.

---

## The EA runs on a live real-money account

`ea/` is not a sandbox. The current version is attached to a chart and placing orders on a funded Exness cent account at 1% risk per trade, up to 3 positions.

- Never edit a file in the MT5 `Advisors\` folder directly. Edit in `ea/`, compile, copy.
- Never delete the version that is currently attached (see **Deploy** below).
- A logic change ships to a live trader. Compile clean, and say plainly what behaviour changed.

There is a kill switch: dropping `TRENDEMA_STOP.txt` into `MQL5\Files` halts it.

---

## Versioning

Filenames carry the version: `ea/TrendEMA_EA_v7.26.mq5`. Keep `#property version` and the `// file is ...` note in sync.

| Bump | When |
|---|---|
| `v7` → `v8` | A new strategy or a restructure of how components relate |
| `v7.25` → `v7.26` | A new input, gate, filter, or behavioural refinement |
| `v7.26` → `v7.26.1` | A bug fix, a default flip, log wording, cosmetics |

Decide the size yourself; the user will say if they disagree.

### `STRATEGY_REV` is a separate decision

```c
#define STRATEGY_REV "7.26"
```

This constant feeds a config-signature hash that keys the **win-rate epoch**. Bumping it wipes the running win/loss count. It has nothing to do with the filename — a `v8` release with an unchanged `STRATEGY_REV` keeps its statistics.

Bump it only when **entry behaviour** changes. Do not bump for logging, panel, or diagnostic work.

Known gap: the signature covers ~45 strategy inputs but omits `CooldownMinutesAfterLoss`, `MaxSameDirLosses`, `RsiArmBars`, `BarrierUse5M` and `RiskPercent`. Changing those in the MT5 dialog silently pools results across configurations.

---

## Build and deploy

```bash
"/c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"<ABSOLUTE .mq5 path>" /log:"<ABSOLUTE log path>"
```

**MetaEditor exits non-zero even on success.** Ignore the exit code; read the log's `Result: N errors, N warnings` line. Append `; true` in Bash so the step doesn't abort.

**The compile log is UTF-16LE.** `grep` finds nothing in it. Read it with PowerShell `Get-Content`.

Deploy destination:

```
C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Advisors\
```

Copy both `.mq5` and `.ex5`.

### Never delete the attached version

MT5 reloads an EA **by filename** from the chart profile. Deleting the attached one means no EA loads at all. On 27 Aug this silently caused 38 MT5 restarts over seven hours with nothing trading.

The sequence is always:

1. Deploy the new version alongside the old one
2. Tell the user to re-attach (the filename changed, so MT5 will not pick it up on its own)
3. Wait for the user to confirm
4. **Verify from the log** that the new version's startup banner appeared
5. Only then delete the old files

Step 4 matters because MT5 buffers log writes — the banner can lag several minutes behind a genuine attach. Poll for it rather than assuming, and rather than deleting on faith.

---

## Reading MT5 logs — use PowerShell, not grep

**All MT5 logs are UTF-16LE.** `grep` silently returns zero matches on them, which reads as "this never happened."

This has already produced one wrong conclusion reported to the user as fact: a `grep` for error `10025` returned nothing, was reported as "never observed on this account", and the loop was in fact running live at that moment — 100 occurrences across two days.

```powershell
Get-Content $log | Select-String -SimpleMatch "TREMA"
```

A zero result from a log search is a claim that something never happened. Verify the search itself before reporting it.

### Where the logs are

| Path | Contains |
|---|---|
| `...\MQL5\Logs\YYYYMMDD.log` | EA `Print()` output — arms, fills, gates, expiries |
| `...\Logs\YYYYMMDD.log` | Terminal/broker messages — **every deal**, including closes |

### Reconstructing P/L

The EA log records fills, not results. Round trips come from the terminal deal log:

```
deal #… buy 0.06 XAUUSDc at 4436.362 done (based on order #0)
```

Match each closing deal to its entry by price: a stop-out lands exactly `SLPips × 0.01` from the open. This is how the −141.00 overnight session was attributed per trigger, and it reconciled to the panel exactly.

---

## Gold specifics

- **1 pip = 0.01 in price = $0.01.** A 900-pip stop is 9.00 in price. Inputs are named `*Pips` throughout and always mean this.
- `XAUUSDc` reports **3 digits**; pip size is still 0.01. Snap prices to `SYMBOL_TRADE_TICK_SIZE`, not just `NormalizeDouble` to digits.
- Cent account: at 0.03 lots, a 900-pip stop is −27.00 USC. P/L = price difference × lots × 100.

## Indicator reads

Trend and direction are read at **shift 1** (the last closed bar) so they cannot repaint. Entries fire intra-bar on tick. The panel additionally shows live forming-bar values labelled `(not traded)` — do not confuse those with what the EA acted on.

---

## Editing the `.mq5`

It is ~3,900 lines. Prefer a Python patch script with exact-match assertions over hand editing:

```python
def rep(a, b):
    assert s.count(a) == 1, (a[:70], s.count(a))
    s = s.replace(a, b, 1)
```

Assert the count. A `str.replace` defaulting to replace-all has already injected a block into the wrong `switch` statement, and a careless regex once rewrote a function's call to itself into infinite recursion — that one killed the EA on every washout for two days.

**Do not write the `.mq5` via a Bash heredoc.** Apostrophes in comments break it. Use the Write tool or a patch script.

---

## Comments

The source carries the reasoning for non-obvious decisions, usually with the date and the incident that motivated them:

```c
//--- v7.23.1: this override has to happen BEFORE the drift test, not
//    after it. Sitting after, the test compared a barrier TP against
//    the fixed-pip TP it was deliberately shortened from...
```

Match that. When fixing something subtle, record *why* the obvious-looking alternative is wrong, so it does not get "simplified" back into a bug.

---

## Working style the user expects

- **Verify before asserting.** Read the log, the deal history, the input values. Several wrong answers here came from reasoning about the code instead of checking what actually ran.
- **Correct errors plainly** and move on. The user acts on these conclusions with real money.
- **Say what a change will not do.** A fix that applies only to future fills does not repair an open position; say so before they go looking.
- **Name the tradeoff.** Every risk gate added so far also blocks trades that would have won. Give the honest cost, including when a change would not have helped the incident that prompted it.
- Explanations should be short and concrete. The user has asked for simpler explanations more than once.

## Git

Commit messages explain the incident, not just the change — what broke, the evidence, why this fix and not the obvious one. See `git log` for the established shape. Push only when asked.
