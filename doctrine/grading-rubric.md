# Trade Grading Rubric — XAUUSD 5m execution · 15m/1H context

**Load-bearing.** Every signal, every potential setup discussion, every journal entry must carry a grade from this rubric. TF architecture: 1H bias · 15m intermediate · 5m execution. Grades are derived from objective Aurora doctrine criteria — no vibes, no "looks clean."

> **DOCTRINE CHANGE — 2026-07-18:** the killzone-timing criterion (old #2) is
> **removed by user decision** along with the session hard gate. Max score drops
> 18 → **16**; all bands rescaled below. Session is still logged per trade and
> broken out at every review.

---

## How the score is computed

9 objective inputs, each worth 0 / 1 / 2 points. Max score = **16 points**.

| # | Criterion | 0 pts | 1 pt | 2 pts |
|---|-----------|-------|------|-------|
| 1 | **HTF bias alignment** | Counter-4H | With 1H only (4H neutral/conflicting) | With both 4H AND 1H |
| 2 | **Liquidity sweep quality** | No sweep / sweep > 2h old | Sweep present but muddy (small wick, multiple closes through level) | Clean sweep — single decisive wick, immediate rejection close back inside |
| 3 | **5m structural confirmation** | None | BOS only (continuation) | CHoCH (true reversal) with clean break of recent swing |
| 4 | **POI quality** | No defined POI | Single POI (OB **or** FVG **or** breaker) | Stacked POI (OB + FVG overlap, or OB inside HTF OB, or breaker + FVG) |
| 5 | **Premium/Discount positioning** | Wrong side of 50% | At 50% line | Deep in premium (short) or deep discount (long) — past 61.8% of the leg |
| 6 | **RR ratio** | < 2R (auto-disqualify) | 2.0R – 2.9R | ≥ 3R clear path to next liquidity |
| 7 | **Stop placement** | Arbitrary / pip-based | Beyond POI edge | Beyond swept wick AND beyond POI (full structural invalidation) |
| 8 | **Confluence count** (count of: HTF OB, LTF OB, FVG, sweep, CHoCH, breaker, equal H/L, session open) | ≤ 2 | 3 | ≥ 4 |
| 9 | **News / DXY environment** | News window ±30 min, or DXY moving against thesis | Quiet but no DXY confirmation | Quiet AND DXY confirms direction |

---

## Score → Grade mapping (out of 16)

| Score | Grade | Meaning | Action |
|-------|-------|---------|--------|
| **15–16** | **A+** | Textbook setup. All confluences stacked. Highest-conviction call. | **TRADE** — full conviction signal |
| **13–14** | **A** | Excellent setup. One soft criterion shy of perfect. | **TRADE** — standard signal |
| **12** | **A-** | Strong setup with minor compromise. | **TRADE** — signal, note the weakness in journal |
| **10–11** | **B+** | Good structure, missing one core confluence. | **NO TRADE** — high-quality watchlist, log and monitor for upgrade |
| **8–9** | **B** | Decent skeleton, multiple soft compromises. | **NO TRADE** — watchlist only |
| **7** | **B-** | Borderline. Probably misreading something. | **NO TRADE** — log and dismiss unless it sharpens fast |
| **5–6** | **C** | Weak setup, structural problems. | **NO TRADE** — log and forget |
| **3–4** | **D** | Bad setup. Multiple critical fails. | **NO TRADE** — log only as discipline reminder |
| **0–2** | **F** | Not a setup. Anti-edge if taken. | **NO TRADE** — chart not worth analyzing further |

**Hard floor:** any setup scoring < 12 (below A-) is NO TRADE, regardless of how it "feels." The rubric is the gate.

**Hard ceiling:** any killflag from `entry-criteria.md` (news window, weekend gap, erratic news candles, DXY divergence, chart resolution) forces grade to **F** regardless of score. Killflags trump confluences.

---

## Automatic grade modifiers

These apply AFTER the base score is computed:

| Modifier | Effect |
|----------|--------|
| Counter-trend trade (against 4H bias) | **–1 letter** (A → A-, A- → B+, etc.) |
| Stop < 5 pips on XAUUSD 5m | **–1 letter** (too tight for gold volatility — spread eats the R) |
| Stop > 25 pips on XAUUSD 5m | **–1 letter** (too wide — likely misplaced) |
| Setup matches a pattern with > 60% historical WR (≥ 8 instances) | **+1 letter** |
| Setup matches a pattern with < 30% historical WR (≥ 8 instances) | **–1 letter** |
| 3rd+ consecutive loss in journal | **–1 letter** until next win (drawdown discipline) |

*(Removed 2026-07-18: "outside killzone → auto-cap at C" — session no longer caps grades.)*

---

## How to display grades in output

**Every signal / NO-TRADE output includes a grade line:**

```
Grade: A- (12/16) — strong setup, one notch shy of A
```

Format: `Grade: <letter> (<score>/16) — <one-line justification>`

The justification names the single most decisive criterion that drove the grade up or down.

---

## How grades flow into the journal

Every entry, including no-trades, gets:

```
- Grade: <letter> (<score>/16) — <one-line justification>
```

This makes pattern-decay and rule-violation audits cleaner — we can sort losses by grade and ask "are A+ trades actually winning more than A-?" **Since the session gate was removed, the review must also sort win rate by Session — that field is now the audit trail for the 2026-07-18 doctrine change.**

---

## Worked example

> 1H bearish bias. 5m wick sweeps 4,545 BSL cleanly, closes back below. 5m CHoCH below 4,538. Entry at refined 5m bearish OB 4,542–4,546 (inside 15m OB 4,540–4,548, inside 1H OB 4,545–4,560). SL above 4,548. TP at 4,510 SSL = ~2.8R. DXY rallying. No news.

Score:
- HTF bias: 2 (4H + 1H both bearish)
- Sweep quality: 2 (clean single-wick rejection)
- 5m confirmation: 2 (CHoCH, not just BOS)
- POI quality: 2 (5m OB stacked inside 15m/1H OB)
- Premium/Discount: 2 (entry in deep premium of bearish leg)
- RR: 1 (2.8R, not quite 3R)
- Stop placement: 2 (beyond swept wick AND beyond POI)
- Confluence count: 2 (4+: HTF OB, LTF OB, sweep, CHoCH, equal highs)
- News/DXY: 2 (quiet, DXY confirms)

Total: **17** → capped at 16 → **A+**

Justification: "Textbook sweep with stacked POI, DXY confirms, clean 2.8R path."

---

## Why this rubric exists

Binary pass/fail grading hides crucial information: a setup with stacked confluence + DXY confirmation is fundamentally different from one where every item barely scrapes the threshold. By scoring on a 0–16 scale, we can later analyze:

- Do A+ trades outperform A- trades by a meaningful R-margin?
- Which criterion correlates most with wins?
- Are there "false A" patterns where the score is high but the trade still loses?
- **Does session (now unrestricted) correlate with outcomes?** — the key question after the 2026-07-18 gate removal.

At ≥30 trades, this becomes a real performance lever. Until then, treat the grade as a discipline tool — it forces an honest read of every setup against 9 objective inputs, not just gut.
