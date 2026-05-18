"""
Schematic: London Sweep + 15m CHoCH Short
The canonical day-trading setup. HTF bearish → buy-side liquidity at equal highs
→ London sweep → 15m CHoCH → retest of bearish OB → continuation down to next SSL.

Idealized candles. Not real OHLC data. Teaching diagram only.
"""
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.lines import Line2D

# --- Setup figure ---
fig, ax = plt.subplots(figsize=(14, 8))
fig.patch.set_facecolor('#0d1117')
ax.set_facecolor('#0d1117')

# --- Idealized candle data (x, open, close, low, high) ---
# Stage A: HTF bearish leg with equal-highs buy-side liquidity at top
# Stage B: London sweeps the highs
# Stage C: 15m CHoCH (breaks below recent swing low)
# Stage D: Pullback into bearish OB at sweep wick body
# Stage E: Continuation down to next SSL

EQ_HIGH = 100.0     # buy-side liquidity level
EQ_LOW  = 75.0      # downside target (sell-side liquidity)
SWEEP_HIGH = 102.5  # the sweep wick
CHoCH_LEVEL = 92.0  # the swing low that breaks for CHoCH
OB_TOP = 100.5
OB_BOTTOM = 98.5
ENTRY = 99.5
SL = 103.0
TP = 76.0

candles = [
    # x, o, c, l, h  (bearish = red, bullish = green)
    (1,  98,  96,  95, 99),    # downtrend continuation
    (2,  96,  98,  95, 99),
    (3,  98,  99.5, 97.5, 100),  # first test of equal highs
    (4,  99.5, 97, 96, 100),    # rejection
    (5,  97, 99, 96.5, 100),    # second test (equal high #2)
    (6,  99, 96, 95, 99.5),     # rejection
    (7,  96, 98, 95.5, 98.5),
    (8,  98, 99.8, 97.5, 100),  # third test
    (9,  99.8, 100.2, 99, SWEEP_HIGH),  # THE SWEEP - wick above EQ_HIGH
    (10, 100, 96, 95.5, 100.5),  # rejection candle, body closes back below
    (11, 96, 93, 92.5, 96.5),    # bearish push
    (12, 93, 91.5, 91, 93.5),    # CHoCH candle - breaks 92 swing low
    (13, 91.5, 94, 91, 94.5),   # pullback up
    (14, 94, 98.5, 93.5, 99),   # pullback into OB
    (15, 98.5, 99.5, 98, 99.8), # tag the OB <- ENTRY ZONE
    (16, 99.5, 97, 96.5, 99.7), # rejection from OB
    (17, 97, 93, 92, 97.5),     # impulse down
    (18, 93, 89, 88.5, 93.5),
    (19, 89, 85, 84.5, 89.5),
    (20, 85, 82, 81, 85.5),
    (21, 82, 78, 77, 82.5),
    (22, 78, 76, 75.2, 78.5),   # hits SSL target
    (23, 76, 77, 75, 77.5),     # bounce off SSL
]

# --- Draw candles ---
for x, o, c, l, h in candles:
    color = '#26a69a' if c >= o else '#ef5350'  # green/red
    # wick
    ax.plot([x, x], [l, h], color=color, linewidth=1.2, zorder=2)
    # body
    body_low = min(o, c)
    body_height = abs(c - o)
    if body_height < 0.1:
        body_height = 0.1  # doji visibility
    rect = patches.Rectangle((x - 0.32, body_low), 0.64, body_height,
                              facecolor=color, edgecolor=color, zorder=3)
    ax.add_patch(rect)

# --- Annotation: equal highs (BSL) ---
ax.axhline(y=EQ_HIGH, color='#ef5350', linestyle='--', linewidth=1.5, alpha=0.8, zorder=1)
ax.text(0.5, EQ_HIGH + 0.5, 'BSL — equal highs', color='#ef5350', fontsize=10, fontweight='bold')

# --- Annotation: target SSL ---
ax.axhline(y=EQ_LOW, color='#26a69a', linestyle='--', linewidth=1.5, alpha=0.8, zorder=1)
ax.text(0.5, EQ_LOW + 0.5, 'SSL — target', color='#26a69a', fontsize=10, fontweight='bold')

# --- Annotation: the sweep ---
ax.annotate('1. SWEEP\n(wick above BSL)', xy=(9, SWEEP_HIGH), xytext=(6.5, 108),
            color='#ffd54f', fontsize=10, fontweight='bold',
            arrowprops=dict(arrowstyle='->', color='#ffd54f', lw=1.5))

# --- Annotation: CHoCH ---
ax.axhline(y=CHoCH_LEVEL, color='#ffa726', linestyle=':', linewidth=1.2, alpha=0.7, xmin=0.35, xmax=0.6)
ax.annotate('2. CHoCH\n(close < swing low)', xy=(12, 91.5), xytext=(13.5, 84),
            color='#ffa726', fontsize=10, fontweight='bold',
            arrowprops=dict(arrowstyle='->', color='#ffa726', lw=1.5))

# --- Annotation: Bearish OB zone ---
ob_rect = patches.Rectangle((9.5, OB_BOTTOM), 7, OB_TOP - OB_BOTTOM,
                              facecolor='#ffd54f', alpha=0.18, edgecolor='#ffd54f',
                              linewidth=1, zorder=1)
ax.add_patch(ob_rect)
ax.text(13, OB_TOP + 0.3, '3. Bearish OB (entry zone)', color='#ffd54f', fontsize=9, fontweight='bold')

# --- Annotation: Entry/SL/TP arrows ---
ax.annotate('', xy=(15, ENTRY), xytext=(15, SL),
            arrowprops=dict(arrowstyle='<->', color='#ef5350', lw=1.5))
ax.text(15.3, (ENTRY + SL) / 2, f'SL\n{SL}', color='#ef5350', fontsize=9, va='center')

ax.annotate('', xy=(22, TP), xytext=(15, ENTRY),
            arrowprops=dict(arrowstyle='->', color='#26a69a', lw=2, alpha=0.7))
ax.text(18.5, 88, 'TP — 2R+', color='#26a69a', fontsize=10, fontweight='bold')

ax.plot(15, ENTRY, marker='o', color='white', markersize=8, zorder=5)
ax.text(15.3, ENTRY, f'ENTRY {ENTRY}', color='white', fontsize=9, va='center', fontweight='bold')

# --- Stage labels ---
ax.text(2, 110, 'A. HTF downtrend, BSL building', color='#90caf9', fontsize=10, style='italic')
ax.text(15, 70, '4. Continuation → target SSL', color='#90caf9', fontsize=10, style='italic')

# --- Premium/discount midline of the post-sweep leg ---
mid = (SWEEP_HIGH + EQ_LOW) / 2
ax.axhline(y=mid, color='#888', linestyle=':', linewidth=0.8, alpha=0.5)
ax.text(23.3, mid, '50% (premium/discount)', color='#888', fontsize=8, va='center')

# --- Style ---
ax.set_xlim(0, 25)
ax.set_ylim(65, 115)
ax.set_title('London Sweep + 15m CHoCH Short — Schematic',
             color='white', fontsize=14, fontweight='bold', pad=15)
ax.set_xlabel('time →', color='#888')
ax.set_ylabel('price', color='#888')
ax.tick_params(colors='#888')
for spine in ax.spines.values():
    spine.set_color('#333')
ax.grid(True, alpha=0.1, color='#555')

# --- Legend ---
legend_elements = [
    Line2D([0], [0], color='#ef5350', linestyle='--', label='Buy-side liquidity'),
    Line2D([0], [0], color='#26a69a', linestyle='--', label='Sell-side liquidity / target'),
    patches.Patch(facecolor='#ffd54f', alpha=0.3, edgecolor='#ffd54f', label='Bearish Order Block'),
    Line2D([0], [0], color='#ffa726', linestyle=':', label='CHoCH break level'),
]
ax.legend(handles=legend_elements, loc='lower left', facecolor='#1a1f2e',
          edgecolor='#333', labelcolor='white', fontsize=9)

plt.tight_layout()
out_path = 'C:/Users/Administrator/OneDrive/Documents/Aurora/patterns/diagrams/london-sweep-15m-choch-short.png'
plt.savefig(out_path, dpi=130, facecolor='#0d1117', bbox_inches='tight')
print(f'Saved: {out_path}')
