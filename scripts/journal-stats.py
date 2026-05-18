"""
journal-stats.py — Parses trades/journal.md into structured metrics.

Reads the markdown journal Aurora maintains, extracts each numbered entry,
and emits a JSON blob with stats Aurora uses for /aurora-review.

Usage:
    python scripts/journal-stats.py            # prints JSON to stdout
    python scripts/journal-stats.py --pretty   # human-readable summary
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from collections import Counter, defaultdict

ROOT = Path(__file__).resolve().parent.parent
JOURNAL = ROOT / "trades" / "journal.md"

# Regex for a journal entry block.
# Header: "## #NNNN · YYYY-MM-DD HH:MM PHT · BUY|SELL|NO-TRADE"
# Also accepts legacy UTC for backward compatibility on old entries.
ENTRY_HEADER_RE = re.compile(
    r"^##\s+#(?P<id>\d{4})\s+·\s+(?P<date>\d{4}-\d{2}-\d{2})\s+(?P<time>\d{2}:\d{2})\s+(?:PHT|UTC)\s+·\s+(?P<dir>BUY|SELL|NO-TRADE)\s*$",
    re.MULTILINE,
)


def parse_entries(text: str) -> list[dict]:
    """Split journal text into per-entry dicts."""
    matches = list(ENTRY_HEADER_RE.finditer(text))
    entries: list[dict] = []
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        entry = {
            "id": m.group("id"),
            "date": m.group("date"),
            "time": m.group("time"),
            "direction": m.group("dir"),
            "raw": block,
        }
        entry.update(_parse_fields(block))
        entries.append(entry)
    return entries


def _parse_fields(block: str) -> dict:
    """Pull structured fields from the bullet body of an entry."""
    fields = {
        "session": None,
        "grade": None,
        "pattern": None,
        "outcome": None,
        "r": None,
        "htf_bias": None,
        "liquidity_swept": None,
        "notes_excerpt": None,
    }
    for line in block.splitlines():
        ls = line.strip().lstrip("-").strip()
        if ls.lower().startswith("session:"):
            fields["session"] = _clean(ls.split(":", 1)[1])
        elif ls.lower().startswith("grade:"):
            fields["grade"] = _clean(ls.split(":", 1)[1])
        elif ls.lower().startswith("pattern match:"):
            fields["pattern"] = _clean(ls.split(":", 1)[1])
        elif ls.lower().startswith("outcome:"):
            fields["outcome"] = _clean(ls.split(":", 1)[1]).upper()
        elif ls.lower().startswith("r:"):
            fields["r"] = _parse_r(ls.split(":", 1)[1])
        elif ls.lower().startswith("htf bias:"):
            fields["htf_bias"] = _clean(ls.split(":", 1)[1])
        elif ls.lower().startswith("liquidity swept:"):
            fields["liquidity_swept"] = _clean(ls.split(":", 1)[1])
        elif ls.lower().startswith("notes:"):
            fields["notes_excerpt"] = _clean(ls.split(":", 1)[1])[:240]
    return fields


def _clean(s: str) -> str:
    return s.strip().rstrip(".")


def _parse_r(s: str) -> float | None:
    s = s.strip().lstrip("+").replace("R", "").strip()
    if s in ("", "—", "-"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def classify_session(session_text: str | None) -> str:
    if not session_text:
        return "unknown"
    s = session_text.lower()
    if "london" in s and "ny" in s:
        return "london_ny_overlap"
    if "london" in s:
        return "london"
    if "ny" in s:
        return "ny"
    if "asia" in s or "off" in s:
        return "off_killzone"
    return "other"


def compute_stats(entries: list[dict]) -> dict:
    signaled = [e for e in entries if e["direction"] in ("BUY", "SELL")]
    no_trades = [e for e in entries if e["direction"] == "NO-TRADE"]

    resolved = [
        e for e in signaled
        if e["outcome"] in ("WON", "LOST", "BE")
    ]
    pending = [
        e for e in signaled
        if (e["outcome"] or "PENDING") not in ("WON", "LOST", "BE")
    ]

    wins = [e for e in resolved if e["outcome"] == "WON"]
    losses = [e for e in resolved if e["outcome"] == "LOST"]
    bes = [e for e in resolved if e["outcome"] == "BE"]

    total_r = sum(e["r"] for e in resolved if e["r"] is not None)
    avg_r = total_r / len(resolved) if resolved else None
    win_rate = (len(wins) / len(resolved)) * 100 if resolved else None

    # Streaks
    outcomes = [e["outcome"] for e in resolved]
    max_w = max_l = cur_w = cur_l = 0
    for o in outcomes:
        if o == "WON":
            cur_w += 1
            cur_l = 0
            max_w = max(max_w, cur_w)
        elif o == "LOST":
            cur_l += 1
            cur_w = 0
            max_l = max(max_l, cur_l)
        else:
            cur_w = cur_l = 0

    # Selectivity: % of all analyses that became a trade
    selectivity = (
        (len(signaled) / len(entries)) * 100 if entries else None
    )

    # Session breakdown (resolved trades only)
    sessions: dict[str, dict] = defaultdict(lambda: {"trades": 0, "wins": 0, "r_total": 0.0})
    for e in resolved:
        sess = classify_session(e["session"])
        sessions[sess]["trades"] += 1
        if e["outcome"] == "WON":
            sessions[sess]["wins"] += 1
        if e["r"] is not None:
            sessions[sess]["r_total"] += e["r"]
    for v in sessions.values():
        v["win_rate"] = (v["wins"] / v["trades"] * 100) if v["trades"] else None
        v["avg_r"] = (v["r_total"] / v["trades"]) if v["trades"] else None

    # Pattern breakdown (resolved trades only)
    patterns: dict[str, dict] = defaultdict(lambda: {"trades": 0, "wins": 0, "r_total": 0.0})
    for e in resolved:
        key = e["pattern"] or "unmatched"
        patterns[key]["trades"] += 1
        if e["outcome"] == "WON":
            patterns[key]["wins"] += 1
        if e["r"] is not None:
            patterns[key]["r_total"] += e["r"]
    for v in patterns.values():
        v["win_rate"] = (v["wins"] / v["trades"] * 100) if v["trades"] else None
        v["avg_r"] = (v["r_total"] / v["trades"]) if v["trades"] else None

    # Last-20 win rate for drawdown alert
    last_20_resolved = resolved[-20:]
    last_20_wr = None
    if last_20_resolved:
        last_20_wr = (
            sum(1 for e in last_20_resolved if e["outcome"] == "WON")
            / len(last_20_resolved) * 100
        )

    return {
        "total_analyses": len(entries),
        "signaled_trades": len(signaled),
        "no_trades": len(no_trades),
        "pending": len(pending),
        "resolved": len(resolved),
        "wins": len(wins),
        "losses": len(losses),
        "be": len(bes),
        "win_rate_pct": round(win_rate, 1) if win_rate is not None else None,
        "total_r": round(total_r, 2),
        "avg_r": round(avg_r, 3) if avg_r is not None else None,
        "max_win_streak": max_w,
        "max_loss_streak": max_l,
        "selectivity_pct": round(selectivity, 1) if selectivity is not None else None,
        "last_20_win_rate_pct": round(last_20_wr, 1) if last_20_wr is not None else None,
        "sessions": dict(sessions),
        "patterns": dict(patterns),
        "review_triggers": _eval_triggers(
            resolved_count=len(resolved),
            last_20_wr=last_20_wr,
            patterns=patterns,
        ),
    }


def _eval_triggers(*, resolved_count: int, last_20_wr: float | None, patterns: dict) -> list[str]:
    flags: list[str] = []
    if resolved_count in (30, 50) or (resolved_count >= 100 and resolved_count % 50 == 0):
        flags.append(f"MILESTONE: {resolved_count} resolved trades — run /aurora-review")
    if last_20_wr is not None and last_20_wr <= 35.0:
        flags.append(f"DRAWDOWN: last-20 win rate {last_20_wr:.1f}% — audit rule compliance")
    for name, p in patterns.items():
        if p["trades"] >= 8 and p["win_rate"] is not None and p["win_rate"] < 30.0:
            flags.append(f"PATTERN-DECAY: {name} at {p['win_rate']:.1f}% over {p['trades']} — retirement candidate")
    return flags


def render_pretty(stats: dict) -> str:
    lines = []
    lines.append("=" * 56)
    lines.append("Aurora Journal Stats")
    lines.append("=" * 56)
    lines.append(f"Total analyses:    {stats['total_analyses']}")
    lines.append(f"Signaled trades:   {stats['signaled_trades']}")
    lines.append(f"  · Resolved:      {stats['resolved']}  (W {stats['wins']} / L {stats['losses']} / BE {stats['be']})")
    lines.append(f"  · Pending:       {stats['pending']}")
    lines.append(f"NO-TRADE:          {stats['no_trades']}")
    lines.append(f"Selectivity:       {stats['selectivity_pct']}% of analyses → trade" if stats['selectivity_pct'] is not None else "Selectivity: —")
    lines.append("")
    lines.append(f"Win rate:          {stats['win_rate_pct']}%" if stats['win_rate_pct'] is not None else "Win rate: — (no resolved trades)")
    lines.append(f"Total R:           {stats['total_r']:+.2f}")
    lines.append(f"Avg R / trade:     {stats['avg_r']:+.3f}" if stats['avg_r'] is not None else "Avg R / trade: —")
    lines.append(f"Max win streak:    {stats['max_win_streak']}")
    lines.append(f"Max loss streak:   {stats['max_loss_streak']}")
    lines.append(f"Last-20 win rate:  {stats['last_20_win_rate_pct']}%" if stats['last_20_win_rate_pct'] is not None else "Last-20 win rate: —")
    if stats["sessions"]:
        lines.append("")
        lines.append("By session:")
        for sess, v in stats["sessions"].items():
            wr = f"{v['win_rate']:.1f}%" if v["win_rate"] is not None else "—"
            ar = f"{v['avg_r']:+.2f}" if v["avg_r"] is not None else "—"
            lines.append(f"  · {sess:20s} {v['trades']:3d} trades · WR {wr} · avg R {ar}")
    if stats["patterns"]:
        lines.append("")
        lines.append("By pattern:")
        for name, v in stats["patterns"].items():
            wr = f"{v['win_rate']:.1f}%" if v["win_rate"] is not None else "—"
            ar = f"{v['avg_r']:+.2f}" if v["avg_r"] is not None else "—"
            lines.append(f"  · {name[:40]:40s} {v['trades']:3d} · WR {wr} · avg R {ar}")
    if stats["review_triggers"]:
        lines.append("")
        lines.append("Review triggers active:")
        for t in stats["review_triggers"]:
            lines.append(f"  ⚠️  {t}")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    # Windows: force UTF-8 stdout so unicode arrows/emojis don't crash on cp1252
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except (AttributeError, ValueError):
        pass
    if not JOURNAL.exists():
        print(json.dumps({"error": f"Journal not found at {JOURNAL}"}))
        return 1
    text = JOURNAL.read_text(encoding="utf-8")
    entries = parse_entries(text)
    stats = compute_stats(entries)
    if "--pretty" in argv:
        print(render_pretty(stats))
    else:
        print(json.dumps(stats, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
