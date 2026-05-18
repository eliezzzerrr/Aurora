---
description: Full Aurora performance review — stats, breakdowns, loss themes, and proposed doctrine changes from the trade journal.
---

Run a complete performance review of Aurora's signals using the trade journal.

**Procedure:**

1. Run the stats parser to compute metrics from the journal:
   ```
   python scripts/journal-stats.py
   ```
   This outputs a JSON blob with: resolved trade count, wins/losses/BE, win rate, total R, avg R, max streaks, session breakdown, pattern breakdown, NO-TRADE counts.

2. Read the full journal (`trades/journal.md`) for context on individual trades — especially the notes field of any losing trades for rule-compliance audit.

3. Read the pattern library (`patterns/README.md`) for per-pattern context.

4. Use the **review output format** defined in the Aurora agent doctrine (`.claude/agents/aurora.md`, "Review protocol" section). Sections in order:
   - Headline (one sentence)
   - Stats table
   - Breakdown by session
   - Breakdown by pattern
   - Loss themes
   - Rule-compliance audit
   - Proposed doctrine changes (each requires user approval)
   - What's working
   - What to watch

5. **Critical:** propose doctrine changes only if the sample size supports it (≥30 resolved trades for full conclusions; below that, label findings as "directional, not conclusive"). Never modify doctrine files in this command — only propose. Wait for explicit user approval before editing.

6. If the journal has fewer than 5 resolved trades, output a short "insufficient data" message instead of the full review template — list what we have, but don't pretend to draw conclusions.

Always route this through the `aurora` subagent so the review is generated with the full doctrine in context.
