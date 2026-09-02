//+------------------------------------------------------------------+
//|                                         TrendEMA_EA_v7.27.3.mq5   |
//|          Ichimoku-gated / EMA-directed XAUUSD trend trader        |
//|                                                                   |
//|  Symbol  : XAUUSD and gold variants (XAUUSDm, XAUUSDz, GOLD...)   |
//|  TFs     : 15M trend gate / 5M direction / 1M entry               |
//|  Account : built for an Exness USC (cent) account                 |
//|  Version : 1.00                                                   |
//|  Date    : 2026-08-25                                             |
//+------------------------------------------------------------------+
//
//  ================================================================
//                      PIP CONVENTION - READ FIRST
//  ================================================================
//  Pip size is AUTO-DETECTED from the symbol so the EA can be run on
//  any instrument:  2/4-digit quotes -> pip = point,
//                   3/5-digit quotes -> pip = 10 points.
//
//  On 2-digit gold that gives pip = 0.01, so a 500-pip stop is $5.00:
//  gold at 3400.00, BUY  ->  SL at 3395.00. That is the original
//  design target and is unchanged.
//
//  On 5-digit FX it gives pip = 0.0001, the conventional FX pip - but
//  note a 500-pip stop is then 50 price-pips x 10, i.e. 0.0500, which
//  is enormous for FX. THE SL/TP DEFAULTS ARE TUNED FOR GOLD. Retune
//  SLPips / TakeProfit*Pips for any other instrument, or set
//  PipSizeOverride explicitly. The init log prints the resulting stop
//  in price terms - read it before trading a new symbol.
//
//  ================================================================
//                          STRATEGY SPEC
//  ================================================================
//
//  TREND GATE (15M, closed bars only)
//    Price above BOTH Senkou Span A and B  -> uptrend permitted
//    Price below BOTH                      -> downtrend permitted
//    Price inside the cloud                -> NO TRADE
//    Ichimoku 9 / 26 / 52, lagging 26, shift 26.
//    The 15M EMAs are deliberately NOT part of the gate.
//
//  DIRECTION (5M, closed bars only)
//    The 5M EMA20/EMA50 relationship picks the side. Only ONE
//    direction is ever armed, so a BUY and a SELL can never be
//    armed off the same touch.
//
//      15M cloud | 5M EMA20 vs 50 | trade         | TP
//      ----------|----------------|---------------|------
//      above     | 20 > 50        | BUY           | 1500
//      above     | 20 < 50        | SELL  counter | 1000
//      below     | 20 < 50        | SELL          | 1500
//      below     | 20 > 50        | BUY   counter | 1000
//      inside    | -              | none          | -
//
//  MOMENTUM (5M RSI-14, closed bars) - see ENUM_RSI_MODE below
//    Default VETO: block a BUY above RSI 70, a SELL below RSI 30.
//    SLOPE mode (BUY needs rising RSI) contradicts a pullback entry
//    and produces almost no trades. It is retained for A/B testing
//    only - see the long note above the enum before enabling it.
//
//  ENTRY (1M)
//    A pending LIMIT rests at the 1M EMA50 and is RE-PRICED on every
//    new 1M bar to the freshly closed EMA50 value. Fills on tick.
//
//  RETEST GATE (1M)
//    If the 1M EMAs oppose the trade direction (EMA20 < EMA50 on a
//    BUY, EMA20 > EMA50 on a SELL) the FIRST touch is skipped.
//    Price must touch the EMA50, pull away by RetestDistancePips,
//    then return. Only then is the limit placed.
//
//  RE-ARM
//    After any fill, price must clear the 1M EMA50 by
//    RearmDistancePips before a new setup can arm. Without this the
//    EA would fire repeatedly while price sits on the EMA.
//
//  RISK
//    SL 900 / TP 1500 with-trend (1.67:1, breakeven 37.5%).
//    Counter-trend keeps its own 500 / 1000.
//
//    Narrowed from 2000 on 28 Aug: the operator observed losing trades that
//    had reached +1500 before reversing. That RAISES the required win rate
//    from 31% to 37.5%, so it only pays if those near-misses actually
//    convert. Verify with MFE in the Strategy Tester report - it measures
//    exactly how far losers travelled in favour before turning.
//    Widened from 500/1500 on 28 Aug: a $5.00 stop is under three average
//    1M bars on gold (ATR ~1.69), and the optimizer preferred 900/2000 with
//    PF 1.42 against PF 0.98 at 500/1500. Live win rate at 500 was 21%
//    versus a 25% breakeven; the backtest at 900 implied ~32%.
//    1% of equity per trade, rounded DOWN to lot step, hard-rejected
//    above 1.25%. Max 3 concurrent positions = 3% open risk.
//
//  ================================================================
//                             WARNING
//  ================================================================
//  THIS EA PLACES ORDERS AUTOMATICALLY AS SOON AS IT IS ATTACHED.
//  There is no arming switch - the operator removed it deliberately.
//  Attaching it to a real-money chart with Algo Trading enabled will
//  trade that account. The only stops are:
//      - the Algo Trading toggle in the toolbar
//      - removing the EA from the chart
//      - dropping the kill-switch file into MQL5\Files
//  The panel prints REAL MONEY in red when the account is live.
//  Demo first. 30+ trades minimum before judging the edge.
//
//  Three concurrent positions at 1% each is 3% of the account at
//  risk simultaneously. Gold is correlated with itself: three longs
//  off the same 1M EMA50 in one session are effectively one trade
//  in three pieces, and one adverse move takes all three. The -6%
//  daily stop is therefore reachable in a single move, not only
//  across three separate trades. This is by design, chosen by the
//  operator with the tradeoff understood.
//+------------------------------------------------------------------+
#property copyright "Aurora Trend EA"
#property version   "7.273"  // file is TrendEMA_EA_v7.27.3 - bump both together
#property description "Ichimoku-gated, EMA-directed XAUUSD trader. 15M gate / 5M direction / 1M entry."

#include <Trade\Trade.mqh>

//--- Bump this ONLY when a change alters trading behaviour. It feeds the
//    config signature below, so bumping it resets the win-rate statistics.
//    Display-only and diagnostic changes must NOT bump it.
#define STRATEGY_REV "7.26"

//+------------------------------------------------------------------+
//| RSI GATING MODES                                                  |
//|                                                                   |
//|  IMPORTANT: this entry is a LIMIT at the 1M EMA50, i.e. you are   |
//|  entering a PULLBACK. A pullback moves against the trade, so 5M   |
//|  RSI is naturally rising as price retraces up into the EMA50 for  |
//|  a short. SLOPE mode therefore demands falling RSI at the exact   |
//|  moment the setup produces rising RSI - the two conditions rarely |
//|  coincide and the EA takes almost no trades. SLOPE is kept only   |
//|  so the behaviour can be A/B tested; do not run it by default.    |
//+------------------------------------------------------------------+
enum ENUM_RSI_MODE
  {
   RSI_MODE_OFF,      // Off - RSI does not gate entries
   RSI_MODE_PULLBACK, // Pullback - BUY needs RSI < mid, SELL needs > mid (continuous)
   RSI_MODE_ARM,      // Armed pullback - the cross ARMS entries for N bars (default)
   RSI_MODE_VETO,     // Veto extremes - no BUY above OB, no SELL below OS
   RSI_MODE_LEVEL,    // Level bias - BUY needs RSI > mid (fights the pullback)
   RSI_MODE_SLOPE     // Slope - BUY needs rising RSI (fights the pullback badly)
  };

//+------------------------------------------------------------------+
//| TREND ENTRY STYLE                                                 |
//|                                                                   |
//|  LIMIT  sells rallies INTO the EMA50 (a limit rests above price).  |
//|  CROSS  sells the break DOWN THROUGH the EMA50 (market on touch).  |
//|  They fire at opposite moments of the same move: the limit waits   |
//|  above for a bounce, the cross fires below on the break. Mirrored  |
//|  for buys - cross UP through the level.                           |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_STYLE
  {
   ENTRY_LIMIT,  // Limit only - rest at the EMA50 and wait for price to come to it
   ENTRY_CROSS,  // Cross only - market the moment price breaks through the EMA50
   ENTRY_BOTH    // Both - either can fire (default)
  };

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES TrendTF   = PERIOD_M15;  // Trend gate TF (Ichimoku cloud)
input ENUM_TIMEFRAMES SignalTF  = PERIOD_M5;   // Direction TF (EMA 20/50 + RSI)
input ENUM_TIMEFRAMES EntryTF   = PERIOD_M1;   // Entry TF (EMA 50 limit level)

input group "=== INDICATORS ==="
input int    IchiTenkan         = 9;     // Ichimoku Conversion Line
input int    IchiKijun          = 26;    // Ichimoku Base Line
input int    IchiSenkou         = 52;    // Ichimoku Leading Span B
input int    EmaFastPeriod      = 20;    // Fast EMA (5M direction / 1M retest gate)
input int    EmaSlowPeriod      = 50;    // Slow EMA (direction + 1M entry level)
input int    RsiPeriod          = 14;    // RSI period (5M)
input ENUM_RSI_MODE RsiMode     = RSI_MODE_ARM; // How RSI gates entries (see notes below)
input double RsiOverbought      = 70.0;  // VETO mode: block BUY above this
input double RsiOversold        = 30.0;  // VETO mode: block SELL below this
input double RsiLevelMid        = 50.0;  // LEVEL/PULLBACK/ARM mode: the mid line
input int    RsiArmBars         = 15;    // ARM mode: entries stay valid this many 1M bars after the RSI condition last held

input group "=== ENTRY ==="
input bool   UseRetestGate      = true;  // Skip first touch when 1M EMAs oppose the trade
input double RetestDistancePips = 50;    // Pull-away needed before a return counts as retest
input int    RetestExpiryBars   = 15;    // Reset the retest wait after this many 1M bars
input bool   UseAtrRetest       = false; // ATR-adaptive retest distance instead of fixed
input int    AtrPeriod          = 14;    // ATR period (1M) for adaptive retest
input double AtrRetestMult      = 0.5;   // Retest distance = this x 1M ATR
input ENUM_ENTRY_STYLE EntryStyle = ENTRY_BOTH; // How trend entries are timed
input bool   UseFallbackLevel   = true;  // Fall back to the 5M EMA50 when the 1M level is unplaceable
input bool   UseFallback15M     = true;  // Fall back again to the 15M EMA50 when the 5M level is unplaceable
input double RearmDistancePips  = 200;   // Price must clear EMA50 by this before re-arming
input int    PendingExpiryBars  = 30;    // Cancel an unfilled limit after this many 1M bars

input group "=== RSI EXTREME TRIGGER ==="
//  A second, INDEPENDENT strategy sharing this chassis. It ignores the 15M
//  cloud, the 5M EMA direction and the EMA50 entry levels entirely: it is a
//  mean-reversion knife-catch on a multi-timeframe RSI washout. It still
//  respects every risk gate (position cap, daily loss, spread, cooldown).
//  Scored separately via the RSIX order comment. Default OFF.
input bool   EnableRsiExtreme   = true;  // Master switch for the RSI extreme trigger
//  Levels are entered as BUY-side numbers and mirrored for sells:
//      3TF  25 -> 75     fast  30 -> 70     slow  40 -> 60
input double RsiXFastLevel      = 30.0;  // Fast TF extreme for BUY (SELL mirrors to 70)
input double RsiXSlowLevel      = 40.0;  // 5M confirmation when the 1M is the trigger (SELL 60)
input double RsiXSlow15Level    = 35.0;  // 15M confirmation when the 5M is the trigger (SELL 65)
input double RsiX3TFLevel       = 25.0;  // Stricter fast level that earns the 3TF tag (SELL 75)
input double RsiXResetLevel     = 50.0;  // Fast RSI must recover past this before re-arming
input bool   RsiXWaitForTurn    = true;  // Enter only once fast RSI crosses back through the fast level
input int    RsiXArmExpiryBars  = 30;    // Drop an armed signal after this many 1M bars
input bool   RsiXCancelsTrend   = true;  // Restrict opposing trend entries while an extreme is active
input bool   RsiXUseBarrierTP   = true;  // Target the first 15M structure instead of a fixed distance
//--- v7.26.5: raised from 1.0 to 1.5 on 2 Sep, matching MinCounterRR. At
//    1.0 a washout could be taken needing a 50% win rate while every other
//    trigger needed 37.5%, and RSI-X was running at 35% over 17 resolved
//    trades (6 wins, -142.60). The looser floor sat on the weaker
//    mechanism, which was backwards: RSI-X fades with no trend permission
//    at all, so it should be held to at least the counter-trend standard.
//    With SL 900 this now demands 1350 pips of clear room to the barrier.
input double MinRsiXRR          = 1.5;   // Skip the washout below this reward:risk

input group "=== TREND RSI TRIGGER ==="
//  WITH-TREND pullback exhaustion. The opposite of the RSI EXTREME trigger:
//  that one ignores the trend and catches washouts, this one REQUIRES the
//  15M trend and sells a 1M RSI spike into it (or buys a 1M RSI collapse in
//  an uptrend). It is an alternative way to TIME a trend entry - it competes
//  with the EMA50 limit rather than adding a new strategy, and cancels that
//  limit when it fires. Scored separately via the TRSI order comment.
input bool   EnableTrendRsi     = true;  // Master switch for the with-trend RSI trigger
input double TrendRsiLevel      = 70.0;  // 1M RSI level for SELL (BUY mirrors to 30)
input double TrendRsiResetLevel = 50.0;  // 1M RSI must recover past this before re-arming
input int    TrendRsiExpiryBars = 5;     // Drop an armed signal after this many 1M bars
input bool   TrendRsiCancelsLimit = true;// Cancel the resting EMA50 limit when this fires
input bool   TrendRsiRequire1M  = true;  // Require the 1M EMAs not to oppose the trade

input group "=== RISK ==="
//--- v7.27: one pair for the trend limit, the cross, the trend-RSI trigger
//    and the RSI-X washout. They carried five separate inputs holding the
//    same two numbers, so changing the geometry meant editing six fields
//    and getting all six right. Counter-trend keeps its own tighter pair
//    below - that one is deliberately different, not a duplicate.
input double SLPips                 = 900;  // SL for every trigger EXCEPT counter-trend (900 = $9.00)
input double TPPips                 = 1500; // TP for every trigger EXCEPT counter-trend
input double CounterSLPips          = 500;  // SL counter-trend (500 = $5.00) - kept tight on purpose
input double TakeProfitCounterPips  = 1000; // TP counter-trend cap (1000 pips)
input bool   CounterUseBarrierTP    = true; // Target the first 15M support/resistance, not a fixed distance
input double CounterBarrierBuffer   = 50;   // Stop this many pips short of the barrier
input bool   BarrierUse5M           = true; // Also treat the 5M EMA50 as a barrier (much closer than 15M)
input double MinCounterRR           = 1.5;  // Skip the counter trade below this reward:risk
input bool   UseFixedLot            = false;// Fixed lot instead of % risk (USE FOR EDGE TESTING)
input double FixedLotSize           = 0.01; // Lot used when UseFixedLot is true
//--- v7.26.2: halved on 1 Sep. The account was funded during the session
//    and risk per trade went from 27.00 to 117.00 USC without a single
//    rule changing - a bigger change to the account than anything shipped
//    this week. Cutting size rather than tightening entry rules leaves the
//    strategy measurable: the same trades still happen, at half stake, so
//    a week of results still means something.
input double RiskPercent            = 0.5;  // Target risk per trade, % of capital
input double MaxRiskPercent         = 1.25; // Hard ceiling - reject the trade above this
input bool   SizeFromEquity         = true; // Size from equity (false = balance)
input double MaxLotSizeCap          = 2.0;  // Absolute lot cap (0 = disabled) - runaway-compounding guard
input int    MaxConcurrentPositions = 3;    // Max simultaneous positions
input bool   OnePositionPerTrigger = true;  // Each trigger source may hold only ONE open position
input bool   BlockOpposingEntries   = true; // Never hold a BUY and a SELL at the same time
input int    MaxDailyTradeCount     = 0;    // Max fills per day (0 = unlimited)
input double MaxDailyLossPercent    = 6.0;  // Halt for the day at this realised loss % (0 = disabled)
input int    DayResetHourET         = 12;   // Hour (ET) the trading day rolls over and the halt lifts
input int    ETOffsetHours          = -4;   // ET offset from GMT: -4 Mar-Nov (EDT), -5 Nov-Mar (EST)
input int    CooldownMinutesAfterLoss = 60; // Wait after a losing trade (0 = no cooldown)
input int    MaxSameDirLosses       = 3;    // Block a direction after this many losses in a row (0 = off)
input double MinFreeMarginPercent   = 30.0; // Pause if free margin / equity below this %

input group "=== FILTERS ==="
input double MaxSpreadPips      = 50;    // Skip if spread wider than this (50 = $0.50)
//--- v7.26.4: OFF by choice on 2 Sep. This is the master switch - false
//    disables the MQL5 calendar gate AND the manual windows below, so the
//    EA now trades straight through releases and the operator halts it by
//    hand instead. Two reasons it was worth switching off rather than
//    tuning: MQL5 grades importance far more freely than ForexFactory (on
//    1 Sep it called four USD events high-impact against one red folder,
//    including JOLTS and ISM Prices Paid), and a +-15 minute clock cannot
//    tell a release that reverses from one that trends.
//    The cost is real and has a precedent: on 28 Aug the EA traded through
//    NFP and went from +99 to -139 in the session. Set this true to get
//    the gate back - nothing else has to change.
input bool   BlockNewsWindow    = false; // Block around high-impact USD news
input bool   NewsTimeIsServer   = false; // Calendar times are server time (false = GMT)
//--- The MQL5 calendar silently returned nothing for four days, so every
//    release including NFP traded straight through. This window does not
//    depend on it: give GMT times as "HH:MM-HH:MM", comma separated, and
//    those minutes are blocked outright. 12:30 GMT is the US 08:30 ET slot
//    that carries NFP and CPI.
//--- v7.26.3: emptied by choice on 2 Sep. The operator monitors releases
//    and halts the EA manually, which a fixed clock window cannot do: the
//    windows blocked every day at the same times whether or not anything
//    was scheduled, and released on the minute regardless of what price was
//    doing - on 1 Sep a washout opened at 10:31 ET, sixty seconds after the
//    10:00-10:30 window lifted, and lost 63.00. The MQL5 calendar gate is
//    untouched and still blocks high-impact USD events; set BlockNewsWindow
//    false to disable that one too. Restore a window by typing it back in.
input string ManualNewsWindows  = "";   // GMT blackout windows (empty = none)
input bool   LogNewsProbe       = true;  // Report at startup how many calendar events MQL5 can see
input int    NewsMinutesBefore  = 15;    // Block this long before an event
input int    NewsMinutesAfter   = 15;    // Block this long after an event
input bool   AllowFridayLate    = false; // Allow new entries late Friday
input int    FridayCutoffHour   = 16;    // Friday cutoff hour (GMT) when above is false
input bool   CloseOnTrendFlip   = false; // Close open trades if the 15M gate flips

input group "=== DISPLAY ==="
input bool   ShowPanel          = true;  // Show the on-chart status panel
input bool   ShowEntryLine      = true;  // Draw the live 1M EMA50 limit level
input bool   ShowSLTPLines      = true;  // Draw projected SL / TP for the armed setup
input int    PanelX             = 12;    // Panel X offset (pixels)
input int    PanelY             = 22;    // Panel Y offset (pixels)
input int    PanelFontSize      = 9;     // Panel font size
input int    PanelMaxPositions  = 5;     // Max open positions listed on the panel
input int    PanelRefreshSeconds = 1;    // Redraw the panel this often even with no ticks
input color  PanelTextColor     = clrWhiteSmoke;  // Panel default text colour
input color  PanelBgColor       = C'18,20,26';    // Panel background

input group "=== SAFETY ==="
input bool   SingleInstanceLock = true;  // Refuse to start if another copy runs on this symbol+magic
input bool   RequireGoldSymbol  = false; // Refuse to attach to non-gold instruments
input double PipSizeOverride    = 0.0;   // Force a pip size (0 = auto-detect from digits)
input bool   EnforcePositionStops = true; // Attach a stop to any position found without one
input int    SyncStopsSeconds    = 60;   // Correct slipped SL/TP within this long of the fill
input bool   EnableHeartbeat    = true;  // Write a heartbeat file an external watchdog can poll
input string HeartbeatFile      = "TRENDEMA_HEARTBEAT.txt"; // Written to MQL5\Files
input string EmergencyStopFile  = "TRENDEMA_STOP.txt"; // Kill-switch file in MQL5\Files
input long   MagicNumber        = 8888;  // Trade identifier (Aurora legacy used 7777)
input double MaxSlippagePips    = 10;    // Slippage tolerance
input string TradeCommentPrefix = "TREMA"; // Order comment prefix

input group "=== ALERTS ==="
input bool   AlertOnFill        = true;  // Popup when an order fills
input bool   AlertOnClose       = true;  // Popup when a position closes
input bool   EnablePush         = false; // Mobile push (requires MT5 push setup)

input group "=== DEBUG ==="
input bool   VerboseLog         = false; // Log every gate decision

//+------------------------------------------------------------------+
//| TYPES                                                             |
//+------------------------------------------------------------------+
enum ENUM_CLOUD
  {
   CLOUD_ABOVE,
   CLOUD_BELOW,
   CLOUD_INSIDE,
   CLOUD_UNKNOWN
  };

enum ENUM_SETUP
  {
   SS_IDLE,            // nothing armed
   SS_WAIT_TOUCH,      // retest gate on, waiting for the first touch
   SS_WAIT_PULLAWAY,   // first touch consumed, waiting for price to pull away
   SS_READY            // limit may rest at the EMA50
  };

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade   gTrade;

int      hIchi   = INVALID_HANDLE;
int      hEma5F  = INVALID_HANDLE;
int      hEma5S  = INVALID_HANDLE;
int      hEma15F = INVALID_HANDLE;
int      hEma15S = INVALID_HANDLE;
int      hRsi5   = INVALID_HANDLE;
int      hRsi1   = INVALID_HANDLE;
int      hRsi15  = INVALID_HANDLE;
int      hEma1F  = INVALID_HANDLE;
int      hEma1S  = INVALID_HANDLE;
int      hAtr1   = INVALID_HANDLE;

double   gPip    = 0.01;      // hard convention: 1 pip = 0.01
double   gPoint  = 0.01;
int      gDigits = 2;
bool     gInitOk = false;

//--- cached indicator state (closed bars only)
double      gSenkouA    = 0.0;
double      gSenkouB    = 0.0;
double      gTrendClose = 0.0;
ENUM_CLOUD  gCloud      = CLOUD_UNKNOWN;
ENUM_CLOUD  gCloudPrev  = CLOUD_UNKNOWN;

double   gEma15F  = 0.0;
double   gEma15S  = 0.0;
double   gEma5F   = 0.0;
double   gEma5S   = 0.0;
double   gRsiNow  = 0.0;
double   gRsiPrev = 0.0;

//--- ARM mode state. PULLBACK asked "is RSI beyond the mid RIGHT NOW", which
//    meant a momentary wobble cancelled a limit that was resting perfectly
//    well: on 31 Aug a sell limit at 4438.56 was placed with RSI above 50,
//    killed seconds later when RSI dipped to 45, and price then ran to 4417 -
//    straight through a target that would have paid +45. The condition is
//    sound, the timing was not. Treat the cross as an ARMING event whose
//    permission persists, exactly as the RSI-X and TrendRSI triggers do.
//    One arm per side: whichever side of the mid the 5M RSI is on gets its
//    timestamp refreshed, so the permission is already standing the moment a
//    setup appears rather than only starting to accumulate once one does.
datetime gRsiArmedBuy  = 0;   // last time 5M RSI was BELOW the mid
datetime gRsiArmedSell = 0;   // last time 5M RSI was ABOVE the mid
double   gRsi1    = 0.0;   // 1M RSI  (extreme trigger only)
double   gRsi15   = 0.0;   // 15M RSI (extreme trigger only)

//--- RSI extreme trigger state
bool     gXArmed     = false;  // condition met, waiting to fire
//--- An armed trigger that expires tells you nothing about WHY. The reason
//    lives in gXState/gTState, which only ever reached the panel, so a
//    missed setup could not be diagnosed after the fact: on 31 Aug a
//    TREND-RSI SELL armed at 1M RSI 71.3 and expired six bars later with
//    no record of which of the six gates held it. Record whether the turn
//    ever came, and print the last state alongside the expiry.
bool     gXTurned    = false;
int      gXDir       = 0;      // +1 buy, -1 sell
string   gXTag       = "";     // 3TF / 1M5M / 5M15M
bool     gXFastIsM1  = true;   // which TF supplies the turn-up confirmation
int      gXArmBars   = 0;
bool     gXNeedsReset = false; // fired; waiting for RSI to return to neutral

//--- While an RSI extreme episode is running, trend entries that OPPOSE it are
//    restricted. Overbought means the EA wants to SELL, so a trend BUY is the
//    opposing trade: while merely armed it is pushed out to the deep 15M EMA50
//    (a shallow 1M/5M pullback is buying into exhaustion); once the sell has
//    actually fired it is blocked outright so we are never both ways at once.
int      gXOpposeDir  = 0;     // trend direction currently restricted (0 = none)
bool     gXHardBlock  = false; // true = block entirely, false = force 15M level

//--- The extreme hands the tick back while it waits, so the trend leg
//    overwrites the shared STATUS line. This keeps the extreme's own reason
//    visible on its panel row instead of it silently reading "ARMED".
string   gXState      = "watching";
int      gDir5    = 0;

double   gEma1F   = 0.0;
double   gEma1S   = 0.0;

//--- the level the pending limit rests at this tick, and which TF it came from
double   gEntryLevel   = 0.0;
//    0 = 1M EMA50 (primary), 1 = 5M EMA50, 2 = 15M EMA50
int      gEntryLevelSrc = 0;
double   gAtr1    = 0.0;

//--- setup state machine
ENUM_SETUP gState        = SS_IDLE;
int        gSetupDir     = 0;
bool       gSetupCounter = false;
int        gStateBars    = 0;
bool       gRearmPending = false;

//--- pending order tracking
ulong    gPendingTicket = 0;
int      gPendingBars   = 0;
int      gRepriceFails  = 0;   // consecutive re-price failures (FIX 7)
//--- what the resting limit's comment actually says, so a change of mind
//    while it rests forces a re-place rather than a mislabelled fill
bool     gPendingCounter  = false;
int      gPendingLevelSrc = 0;

//--- daily state
datetime gDayStart        = 0;
long     gDayIndex        = -1;
double   gDayStartBalance = 0.0;
int      gDayTrades       = 0;
int      gDayWins         = 0;
int      gDayLosses       = 0;
//--- all-time is scanned rarely (init + on each close), not per tick
int      gAllWins         = 0;
int      gAllLosses       = 0;
//--- Streaks over the config epoch. A win rate says how often the EA is
//    right; it says nothing about how the losses ARRANGE themselves, and
//    that is what decides both the drawdown and where the cooldown and
//    brake thresholds belong. Six scattered losses and six consecutive
//    ones read identically at 40%.
int      gAllStreak       = 0;   // current run: positive wins, negative losses
int      gAllBestWin      = 0;   // longest winning run this epoch
int      gAllWorstLoss    = 0;   // longest losing run this epoch (negative)
//--- Stats only count deals from this point on. It moves whenever the
//    strategy configuration changes, so the win rate always describes the
//    setup actually running - not an average of ten superseded ones.
datetime gStatsEpoch      = 0;
double   gDayPL           = 0.0;
datetime gLastLossTime    = 0;
//--- Overnight 31 Aug -> 1 Sep the EA sold a 22-point rally five times and
//    was stopped out five times: three tagged TREND (the 15M cloud said
//    down while price rose) and two tagged CROSS-CTR (the 15M said up and
//    it sold anyway). Nothing in the EA could notice it was repeatedly
//    wrong in ONE direction - the position cap, the per-trigger slots and
//    the opposing-entry rule were all satisfied throughout. Count losses
//    per side and stop taking that side until the 15M permission flips.
int      gDirLossStreak   = 0;   // consecutive losing closes on one side
int      gDirLossSide     = 0;   // which side that streak belongs to
int      gBrakeDir        = 0;   // side currently braked (0 = none)
int      gBrakeCloudDir   = 0;   // 15M permission when the brake engaged
int      gLastLossDir     = 0;   // which side the most recent loss was on

//--- bar tracking
datetime gLastTrendBar  = 0;
datetime gLastSignalBar = 0;
datetime gLastEntryBar  = 0;
//--- bar last OBSERVED on the entry timeframe, whether or not the read
//    succeeded. gLastEntryBar advances only on success, so using it to gate
//    the retry made a failing read re-scan every timeframe on every tick.
datetime gLastEntrySeen = 0;

//--- news
bool     gCalendarOK = true;
uint     gNewsCheckMs       = 0;
bool     gNewsBlockedCached = false;

//--- panel row bookkeeping (stale rows must be deleted when the panel shrinks)
int      gPanelRowsDrawn = 0;
//--- Widest row actually rendered this pass, in pixels. The background was
//    a hard-coded 440 while rows were clipped by CHARACTER count, so the
//    two had no relationship: at any font size or DPI where Consolas runs
//    wider than ~6.8px per character the text spilled out of the box.
//    Measure what was drawn and size the box to it.
int      gPanelMaxW      = 0;

//--- consecutive indicator-refresh failures per timeframe. CopyBuffer can
//    fail after a reconnect or a history gap; previously the last-known
//    values simply persisted and the EA kept trading on them indefinitely.
int      gStaleTrend  = 0;
int      gStaleSignal = 0;
int      gStaleEntry  = 0;

//--- Cross-entry state. A crossing needs the PREVIOUS side, so each level
//    is tracked separately; without this the EA cannot tell "price is below
//    the EMA50" (true most of a downtrend) from "price just crossed below".
bool     gCrossInit    = false;
uint     gCrossSeenMs  = 0;
bool     gWasAbove1    = false;
bool     gWasAbove5    = false;
bool     gWasAbove15   = false;
bool     gCrossBlocked = false;
double   gCrossBlockAt = 0.0;

//--- TREND RSI trigger state
bool     gTArmed      = false;
bool     gTTurned     = false;  // did the RSI ever come back through the level
int      gTDir        = 0;
int      gTArmBars    = 0;
bool     gTNeedsReset = false;
string   gTState      = "watching";

//--- Forming-bar values. DISPLAY ONLY - never used for a trade decision,
//    because the forming bar repaints. They exist so the panel can show
//    numbers that match a live chart, next to the closed-bar values the EA
//    actually trades on.
double   gLiveEma5F = 0.0;
double   gLiveEma5S = 0.0;
double   gLiveRsi5  = 0.0;

//--- Where the EA last was in its tick cycle. Written into the heartbeat so
//    that after an "Abnormal termination" - which MQL5 logs with no stack
//    trace - the file still says which stage it died in. On 28 Aug the EA
//    stopped dead at 07:29:00 and left nothing to localise the fault.
string   gPhase        = "INIT";

//--- SyncPositionStops sends a server request whenever a stop looks wrong.
//    It ran on EVERY TICK with no cap: a modify the broker keeps refusing
//    would fire hundreds of synchronous trade calls a minute, which is a
//    plausible way to wedge the EA. Throttled, and capped per bar.
uint     gLastStopSyncMs  = 0;
int      gStopFixFails    = 0;
uint     gStopFixWindowMs = 0;

//--- Last tick arrival measured with GetTickCount (real elapsed ms), NOT
//    TimeCurrent. TimeCurrent is the server time OF THE LAST QUOTE, so when
//    quotes stop it freezes together with the stored value and the age reads
//    0s forever - the detector failed in exactly the case it existed for.
uint     gLastTickMs   = 0;

//--- Uptime, driven by GetTickCount (real elapsed ms). This is the ONLY
//    counter on the panel that moves whether or not quotes are arriving, so
//    a frozen value here means the EA itself has stopped - not that the
//    market is quiet. Tick age and the bar countdowns both stall legitimately
//    when the session closes; this one never should.
uint     gInitMs       = 0;
uint     gLastDrawMs   = 0;
uint     gLastBeatMs   = 0;

//+------------------------------------------------------------------+
//| SINGLE-INSTANCE LOCK                                               |
//|                                                                    |
//|  Two copies of this EA on the same symbol share a magic number, so  |
//|  they cancel each other's pending orders (each sees the other's as  |
//|  an untracked orphan) and can both pass the one-position-per-slot   |
//|  check on the same tick before either has filled. A terminal global |
//|  variable, refreshed while alive, makes a second copy refuse to     |
//|  start. It goes stale after 30s so a crashed instance never locks   |
//|  the symbol out permanently.                                       |
//+------------------------------------------------------------------+
string LockName()
  {
   return(StringFormat("TREMA_LOCK_%s_%d", _Symbol, (int)MagicNumber));
  }

void TouchLock()
  {
   if(!SingleInstanceLock || MQLInfoInteger(MQL_TESTER))
      return;
   //--- v7.16: throttled. The reader treats the lock as live for 30s, so
   //    writing it tens of times a second only dirtied the terminal's
   //    global-variable table for its periodic disk flush.
   uint now = GetTickCount();
   if(gLastLockMs != 0 && (now - gLastLockMs) < 5000)
      return;
   gLastLockMs = now;
   GlobalVariableSet(LockName(), (double)TimeLocal());
  }

//--- headless == running in the Strategy Tester with no visual chart
//--- The barrier rejection is a per-tick decision but a once-per-setup
//    event. v7.19 logged it every tick: thousands of identical lines in an
//    hour. Remember what was last reported and only speak when it changes.
string   gLastRejectKey  = "";
uint     gLastLockMs      = 0;
bool     gHoldsLock       = false;   // did THIS instance claim the lock?
bool     gHeadless        = false;
bool     gStopFilePresent = false;
uint     gLastStopChkMs   = 0;

//--- throttles
uint     gLastStatsMs = 0;
uint     gLastPanelMs = 0;

//--- status reporting
string   gStatus       = "INIT";
string   gStatusDetail = "";
color    gStatusColor  = clrSilver;

//--- object prefix
const string PFX = "TREMA_";

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   gInitOk = false;

   //--- refuse to be a second copy ------------------------------------
   if(SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     {
      string lock = LockName();
      if(GlobalVariableCheck(lock))
        {
         datetime beat = (datetime)GlobalVariableGet(lock);
         int      age  = (int)(TimeLocal() - beat);
         if(age >= 0 && age < 30)
           {
            PrintFormat("[TREMA] REFUSING to start: another instance is already "
                        "running on %s with magic %d (last seen %ds ago). Two "
                        "copies cancel each other's orders and can double-fill "
                        "the same slot. Remove the other chart, or set "
                        "SingleInstanceLock=false if you really want both.",
                        _Symbol, (int)MagicNumber, age);
            return(INIT_FAILED);
           }
         PrintFormat("[TREMA] Stale instance lock found (%ds old) - taking it over.", age);
        }
      GlobalVariableSet(lock, (double)TimeLocal());
      gHoldsLock = true;
     }

   //--- symbol guard -------------------------------------------------
   if(RequireGoldSymbol)
     {
      string up = _Symbol;
      StringToUpper(up);
      if(StringFind(up, "XAU") < 0 && StringFind(up, "GOLD") < 0)
        {
         Print("[TREMA] REFUSING to attach: ", _Symbol,
               " is not a gold symbol. Set RequireGoldSymbol=false to override.");
         return(INIT_FAILED);
        }
     }

   //--- input sanity -------------------------------------------------
   if(SLPips <= 0 || TPPips <= 0 || TakeProfitCounterPips <= 0)
     {
      Print("[TREMA] REFUSING to attach: SL/TP pips must all be > 0.");
      return(INIT_FAILED);
     }
   if(RiskPercent <= 0 || MaxRiskPercent < RiskPercent)
     {
      Print("[TREMA] REFUSING to attach: need 0 < RiskPercent <= MaxRiskPercent.");
      return(INIT_FAILED);
     }
   if(EmaFastPeriod >= EmaSlowPeriod)
     {
      Print("[TREMA] REFUSING to attach: EmaFastPeriod must be < EmaSlowPeriod.");
      return(INIT_FAILED);
     }
   if(MaxConcurrentPositions < 1)
     {
      Print("[TREMA] REFUSING to attach: MaxConcurrentPositions must be >= 1.");
      return(INIT_FAILED);
     }

   //--- symbol metrics -----------------------------------------------
   gDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   gPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(gPoint <= 0.0)
     {
      Print("[TREMA] REFUSING to attach: symbol point size is zero.");
      return(INIT_FAILED);
     }

   //--- pip size: auto-detect so the EA works on any instrument -------------
   //    2/4-digit quotes: pip == point.  3/5-digit quotes: pip == 10 points.
   //    On 2-digit gold this yields 0.01, matching the original convention.
   //    On 5-digit FX it yields 0.0001, the conventional FX pip.
   if(PipSizeOverride > 0.0)
      gPip = PipSizeOverride;
   else
      gPip = gPoint * ((gDigits == 3 || gDigits == 5) ? 10.0 : 1.0);

   if(gPip < gPoint)
     {
      PrintFormat("[TREMA] WARNING: pip (%.5f) is smaller than point (%.5f). "
                  "Check PipSizeOverride and your SL/TP inputs before trading.",
                  gPip, gPoint);
     }

   //--- indicator handles --------------------------------------------
   hIchi  = iIchimoku(_Symbol, TrendTF,  IchiTenkan, IchiKijun, IchiSenkou);
   hEma5F = iMA(_Symbol, SignalTF, EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEma5S = iMA(_Symbol, SignalTF, EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEma15F= iMA(_Symbol, TrendTF,  EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEma15S= iMA(_Symbol, TrendTF,  EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hRsi5  = iRSI(_Symbol, SignalTF, RsiPeriod, PRICE_CLOSE);
   hRsi1  = iRSI(_Symbol, EntryTF,  RsiPeriod, PRICE_CLOSE);
   hRsi15 = iRSI(_Symbol, TrendTF,  RsiPeriod, PRICE_CLOSE);
   hEma1F = iMA(_Symbol, EntryTF,  EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEma1S = iMA(_Symbol, EntryTF,  EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtr1  = iATR(_Symbol, EntryTF,  AtrPeriod);

   if(hIchi  == INVALID_HANDLE || hEma5F == INVALID_HANDLE ||
      hEma5S == INVALID_HANDLE || hRsi5  == INVALID_HANDLE ||
      hEma15F== INVALID_HANDLE || hEma15S== INVALID_HANDLE ||
      hRsi1  == INVALID_HANDLE || hRsi15 == INVALID_HANDLE ||
      hEma1F == INVALID_HANDLE || hEma1S == INVALID_HANDLE ||
      hAtr1  == INVALID_HANDLE)
     {
      Print("[TREMA] REFUSING to attach: failed to create one or more indicator handles.");
      return(INIT_FAILED);
     }

   //--- trade object --------------------------------------------------
   gTrade.SetExpertMagicNumber(MagicNumber);
   gTrade.SetDeviationInPoints((ulong)MathMax(1.0, MaxSlippagePips * gPip / gPoint));
   gTrade.SetTypeFillingBySymbol(_Symbol);
   gTrade.LogLevel(VerboseLog ? LOG_LEVEL_ALL : LOG_LEVEL_ERRORS);

   //--- calendar availability ------------------------------------------
   gHeadless = (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));

   gCalendarOK = true;
   if(MQLInfoInteger(MQL_TESTER))
     {
      gCalendarOK = false;
      if(BlockNewsWindow)
         Print("[TREMA] NOTE: economic calendar is unavailable in the Strategy Tester. "
               "News blocking is INACTIVE for this backtest - live results will differ.");
     }

   //--- v7.21: the washout episode lived only in chart-local globals, so a
   //    re-attach (and this EA is re-attached constantly) forgot that a
   //    washout had already been traded and could take the same one twice.
   //    Park it in a terminal global, which survives reload.
   {
      string kReset = StringFormat("TREMA_XRESET_%s_%d", _Symbol, (int)MagicNumber);
      if(GlobalVariableCheck(kReset) && GlobalVariableGet(kReset) > 0.0)
        {
         gXNeedsReset = true;
         gXDir        = (int)GlobalVariableGet(kReset);
         Print("[TREMA] Restored an unfinished RSI-extreme episode from before "
               "the re-attach - it will not be traded twice.");
        }
     }

   LoadBrakeState();

   ProbeCalendar();

   //--- day state -------------------------------------------------------
   ResetDayState(true);
   SyncStatsEpoch();
   RefreshDailyStats();
   RefreshAllTimeStats();

   //--- first indicator load --------------------------------------------
   gLastTrendBar = 0;
   gLastSignalBar = 0;
   gLastEntryBar = 0;
   RefreshIndicators(true);

   //--- adopt any pending order left over from a previous run ------------
   AdoptExistingPending();

   PrintFormat("[TREMA] Initialised. Symbol=%s Digits=%d Point=%.5f Pip=%.5f "
               "SL=%.0fp(%.5f price) TP=%.0f/%.0fp Risk=%.2f%%/%.2f%% MaxPos=%d RSI=%s",
               _Symbol, gDigits, gPoint, gPip,
               SLPips, SLPips * gPip,
               TPPips, TakeProfitCounterPips,
               RiskPercent, MaxRiskPercent, MaxConcurrentPositions,
               RsiModeName());

   //--- full state dump. Inputs reset to defaults on every re-attach, and a
   //    version bump forces a re-attach, so the log must say what is actually
   //    running rather than what was configured last session.
   if(EnableRsiExtreme)
      PrintFormat("[TREMA] RSI EXTREME: ENABLED  BUY fast %.0f / 5M %.0f / 15M %.0f (3TF %.0f)  "
                  "SELL fast %.0f / 5M %.0f / 15M %.0f (3TF %.0f)  entry=%s  reset=%.0f  "
                  "SL=%.0fp TP=%.0fp  cancels-trend=%s",
                  RsiXFastLevel, RsiXSlowLevel, RsiXSlow15Level, RsiX3TFLevel,
                  100.0 - RsiXFastLevel, 100.0 - RsiXSlowLevel,
                  100.0 - RsiXSlow15Level, 100.0 - RsiX3TFLevel,
                  RsiXWaitForTurn ? "on-turn" : "immediate",
                  RsiXResetLevel, SLPips, TPPips,
                  RsiXCancelsTrend ? "yes" : "no");
   else
      Print("[TREMA] RSI EXTREME: DISABLED - no washout entries can fire. "
            "Set EnableRsiExtreme=true to enable it.");

   if(RsiXUseBarrierTP)
      PrintFormat("[TREMA] RSI extreme also targets the first %s barrier, "
                  "REFUSED below RR %.2f.",
                  BarrierUse5M ? "5M/15M" : "15M", MinRsiXRR);

   if(CounterUseBarrierTP)
      PrintFormat("[TREMA] Counter-trend targets the first %s barrier "
                  "(buffer %.0fp), and is REFUSED below RR %.2f.",
                  BarrierUse5M ? "5M EMA50 / 15M cloud / 15M EMA50" : "15M",
                  CounterBarrierBuffer, MinCounterRR);
   else
      Print("[TREMA] Counter-trend uses its fixed target, barrier rule OFF.");

   string styleName = (EntryStyle == ENTRY_LIMIT) ? "LIMIT only"
                    : (EntryStyle == ENTRY_CROSS) ? "CROSS only" : "LIMIT + CROSS";
   PrintFormat("[TREMA] Trend entry style: %s.  Cross SL=%.0fp TP=%.0fp.",
               styleName, SLPips, TPPips);

   if(EnableTrendRsi)
      PrintFormat("[TREMA] TREND RSI: ENABLED  SELL above %.0f / BUY below %.0f  "
                  "reset=%.0f  SL=%.0fp TP=%.0fp  expiry=%d bars  "
                  "1M-structure=%s  cancels-limit=%s",
                  TrendRsiLevel, 100.0 - TrendRsiLevel, TrendRsiResetLevel,
                  SLPips, TPPips, TrendRsiExpiryBars,
                  TrendRsiRequire1M ? "required" : "ignored",
                  TrendRsiCancelsLimit ? "yes" : "no");
   else
      Print("[TREMA] TREND RSI: DISABLED.");

   Print("[TREMA] One position per trigger slot: ",
         OnePositionPerTrigger ? "ON (EMA1/EMA5/EMA15/RSIX/TRSI)" : "OFF");

   PrintFormat("[TREMA] Risk brakes: cooldown %s | same-direction brake %s",
               CooldownMinutesAfterLoss > 0
                  ? StringFormat("%d min, losing side only", CooldownMinutesAfterLoss)
                  : "OFF",
               MaxSameDirLosses > 0
                  ? StringFormat("after %d losses in a row on one side, until the 15M flips",
                                 MaxSameDirLosses)
                  : "OFF");

   PrintFormat("[TREMA] Guards: lot cap %s | stop enforcement %s | "
               "stop sync %ds | news times %s",
               MaxLotSizeCap > 0.0 ? StringFormat("%.2f", MaxLotSizeCap) : "OFF",
               EnforcePositionStops ? "ON" : "OFF",
               SyncStopsSeconds,
               NewsTimeIsServer ? "server" : "GMT");

   PrintFormat("[TREMA] Day rollover %02d:00 ET (GMT%+d).  Daily halt: %s.  "
               "Trade cap: %s.  Fixed lot: %s.",
               DayResetHourET, ETOffsetHours,
               MaxDailyLossPercent > 0.0
                  ? StringFormat("%.1f%%", MaxDailyLossPercent) : "DISABLED",
               MaxDailyTradeCount > 0
                  ? IntegerToString(MaxDailyTradeCount) : "none",
               UseFixedLot ? StringFormat("%.2f", FixedLotSize) : "off (% risk)");

   //--- broker constraints that can silently prevent limit placement -------
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   PrintFormat("[TREMA] Broker limits: stops_level=%d pts (%.2f price) freeze=%d pts "
               "lot min/max/step = %.2f/%.2f/%.2f contract=%.0f",
               (int)stopsLvl, stopsLvl * gPoint, (int)freezeLvl,
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));

   if(stopsLvl * gPoint > 1.0)
      PrintFormat("[TREMA] WARNING: broker stops_level is %.2f in price terms. "
                  "The 1M EMA50 is often closer to price than that, so limit "
                  "orders will frequently be refused as too close to market.",
                  stopsLvl * gPoint);

   //--- SL/TP in price terms, so a wrong-market attach is obvious ------------
   PrintFormat("[TREMA] On %s a %.0f-pip stop = %.5f in price, TP = %.5f / %.5f. "
               "If those look wrong for this instrument, retune the *Pips inputs "
               "or set PipSizeOverride.",
               _Symbol, SLPips, SLPips * gPip,
               TPPips * gPip, TakeProfitCounterPips * gPip);

   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)
      == ACCOUNT_TRADE_MODE_REAL)
      Print("[TREMA] *** REAL MONEY ACCOUNT *** This EA places orders automatically. "
            "Max ", MaxConcurrentPositions, " positions at ", RiskPercent,
            "% each. Drop ", EmergencyStopFile, " into MQL5\\Files to halt it.");

   //--- surface a trade-permission problem at init, not silently on the panel
   string tradeWhy = "";
   if(!AccountAllowsTrading(tradeWhy))
      Print("[TREMA] TRADING BLOCKED: ", tradeWhy,
            " - the EA will analyse and display but cannot place orders.");

   //--- A crashed or force-closed instance leaves its panel objects saved in
   //    the chart. The new instance does not know they exist, draws its own
   //    rows, and the orphans sit outside the resized background - which is
   //    the stray text seen below the panel. Clear them before drawing.
   ObjectsDeleteAll(0, PFX);
   gPanelRowsDrawn = 0;

   //--- refresh the panel on a timer as well as on ticks, so a quiet market
   //    or a stalled feed cannot leave a stale panel looking live.
   if(!gHeadless && PanelRefreshSeconds > 0)
      EventSetTimer(PanelRefreshSeconds);

   gLastTickMs = GetTickCount();
   gInitMs     = GetTickCount();
   gInitOk = true;
   WriteHeartbeat();
   DrawPanel();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   //--- v7.15: release on ANY exit once we claimed it. The old guard also
   //    required gInitOk, so a failed init (bad symbol, bad input, handle
   //    error) left the lock held - and the corrected re-attach 30s later
   //    was refused as a phantom second instance.
   if(gHoldsLock && SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableDel(LockName());
      gHoldsLock = false;
     }
   if(!gHeadless)
     {
      ObjectsDeleteAll(0, PFX);
      ChartRedraw();
     }

   if(hIchi  != INVALID_HANDLE) IndicatorRelease(hIchi);
   if(hEma5F != INVALID_HANDLE) IndicatorRelease(hEma5F);
   if(hEma5S != INVALID_HANDLE) IndicatorRelease(hEma5S);
   if(hEma15F!= INVALID_HANDLE) IndicatorRelease(hEma15F);
   if(hEma15S!= INVALID_HANDLE) IndicatorRelease(hEma15S);
   if(hRsi5  != INVALID_HANDLE) IndicatorRelease(hRsi5);
   if(hRsi1  != INVALID_HANDLE) IndicatorRelease(hRsi1);
   if(hRsi15 != INVALID_HANDLE) IndicatorRelease(hRsi15);
   if(hEma1F != INVALID_HANDLE) IndicatorRelease(hEma1F);
   if(hEma1S != INVALID_HANDLE) IndicatorRelease(hEma1S);
   if(hAtr1  != INVALID_HANDLE) IndicatorRelease(hAtr1);
  }

//+------------------------------------------------------------------+
//| OnTimer - keeps the panel honest when ticks stop arriving          |
//+------------------------------------------------------------------+
//--- Heartbeat for an external watchdog. Written from OnTimer, NOT OnTick,
//    which is the whole point: OnTimer fires on the terminal clock whether
//    or not quotes are arriving. A stale heartbeat therefore means the EA
//    has genuinely stopped executing, not merely that the market is quiet -
//    so a watchdog can act on it without needing market-hours logic.
//--- Is the symbol inside a quote session right now? Uses TimeTradeServer
//    rather than TimeCurrent: TimeCurrent is the time of the LAST QUOTE, so
//    it freezes exactly when the feed dies and would report the session
//    closed forever. TimeTradeServer keeps advancing on the terminal clock.
bool MarketSessionOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int nowSecs = dt.hour * 3600 + dt.min * 60 + dt.sec;

   datetime from = 0, to = 0;
   for(int i = 0; i < 8; i++)
     {
      if(!SymbolInfoSessionQuote(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week,
                                 i, from, to))
         break;
      if(nowSecs >= (int)from && nowSecs <= (int)to)
         return(true);
     }
   return(false);
  }

//--- The heartbeat now carries THREE fields, because a live heartbeat alone
//    proved nothing: it is written from OnTimer, which runs on the terminal
//    clock, so it stayed fresh through nine hours of the EA receiving no
//    ticks at all. The watchdog needs the tick age to see that.
//        <local time> | <seconds since last tick> | <1 if market open>
void WriteHeartbeat()
  {
   if(!EnableHeartbeat || gHeadless)
      return;
   uint now = GetTickCount();
   if(gLastBeatMs != 0 && (now - gLastBeatMs) < 5000)
      return;
   int tickAge = (gLastTickMs > 0) ? (int)((now - gLastTickMs) / 1000) : 99999;

   int h = FileOpen(HeartbeatFile,
                    FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
      return;           // throttle NOT consumed - retry on the next call
   gLastBeatMs = now;
   FileWrite(h, StringFormat("%s|%d|%d|%s",
                             TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
                             tickAge,
                             MarketSessionOpen() ? 1 : 0,
                             gPhase));
   FileClose(h);
  }


void OnTimer()
  {
   if(!gInitOk || gHeadless)
      return;
   TouchLock();
   WriteHeartbeat();

   //--- v7.16: RefreshIndicators REMOVED from the timer. It advances
   //    gLastEntryBar as a side effect, so a timer tick that landed on a bar
   //    boundary consumed the transition and the next OnTick saw
   //    newEntryBar=false - silently skipping that bar's limit re-price,
   //    pending-expiry count, orphan sweep and retest/arm counters.
   //    Nothing here needs it: the panel reads cached globals, and the
   //    countdowns read iTime/TimeCurrent directly. When ticks stop, no new
   //    bars form either, so there is nothing to refresh anyway.
   //--- and do NOT stamp gPhase: overwriting it every second erased whatever
   //    phase OnTick was in and left the crash locator pointing nowhere.
   //--- share the OnTick throttle so the two pipelines cannot compound into
   //    4-5 full panel rebuilds a second, each scanning every position and
   //    running OrderCalcMargin.
   uint nowTimer = GetTickCount();
   if(gLastPanelMs == 0 || (nowTimer - gLastPanelMs) > 300)
     {
      DrawPanel();
      DrawLevels();
      gLastPanelMs = nowTimer;
     }
  }

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!gInitOk)
      return;
   gLastTickMs = GetTickCount();
   gPhase = "TICK";
   TouchLock();

   //--- day rollover ----------------------------------------------------
   if(IsNewDay())
     {
      ResetDayState(false);
      CancelPending("new trading day");
      gLastStatsMs = 0;
     }

   //--- indicators (per-timeframe bar gated) -----------------------------
   gPhase = "INDICATORS";
   bool newEntryBar = RefreshIndicators(false);

   //--- daily stats: a full history scan, so throttle it -----------------
   uint nowMs = GetTickCount();
   if(newEntryBar || gLastStatsMs == 0 || (nowMs - gLastStatsMs) > 15000)
     {
      gPhase = "DAILY_STATS";
      RefreshDailyStats();
      gLastStatsMs = nowMs;
     }

   //--- trend flip management -------------------------------------------
   if(CloseOnTrendFlip && gCloud != gCloudPrev && gCloudPrev != CLOUD_UNKNOWN)
      CloseAllPositions("15M trend gate flipped");
   gCloudPrev = gCloud;

   //--- FIX 3: never leave a position without a stop. Runs before anything
   //    else that could open more exposure.
   gPhase = "SYNC_STOPS";
   SyncPositionStops();

   //--- FIX 2: clear untracked pendings once per bar
   if(newEntryBar)
     {
      gPhase = "ORPHANS";       // v7.15: set only when the stage is entered
      CancelOrphanPendings();
     }

   //--- evaluate the setup and act ---------------------------------------
   gPhase = "EVALUATE";
   EvaluateAndAct(newEntryBar);

   //--- pending order housekeeping ----------------------------------------
   if(newEntryBar && gPendingTicket != 0)
     {
      gPendingBars++;
      if(gPendingBars > PendingExpiryBars)
         CancelPending(StringFormat("unfilled for %d bars", gPendingBars));
     }

   //--- display: panel recomputes sizing (incl. OrderCalcMargin) on every
   //    redraw, so it is skipped entirely in a non-visual backtest. Drawing
   //    to a chart nobody is watching was pure cost on every optimization
   //    pass, and this EA is optimized in 90-pass sweeps.
   if(!gHeadless &&
      (newEntryBar || gLastPanelMs == 0 || (nowMs - gLastPanelMs) > 300))
     {
      gPhase = "DRAW";
      DrawPanel();
      DrawLevels();
      gLastPanelMs = nowMs;
     }
  }

//+------------------------------------------------------------------+
//| Core decision + execution                                          |
//+------------------------------------------------------------------+
void EvaluateAndAct(const bool newEntryBar)
  {
   //--- hard blocks first, most severe to least ---------------------------
   //--- D: FileIsExist is a filesystem call. Checking it on every tick was
   //    measurable in backtests; live it is checked at most twice a second,
   //    which is far faster than a human can react anyway.
   if(!gHeadless)
     {
      uint nowChk = GetTickCount();
      if(gLastStopChkMs == 0 || (nowChk - gLastStopChkMs) > 500)
        {
         gStopFilePresent = FileIsExist(EmergencyStopFile);
         gLastStopChkMs   = nowChk;
        }
     }
   if(gStopFilePresent)
     {
      SetStatus("HALTED", "kill-switch file present", clrRed);
      CancelPending("kill-switch file present");
      return;
     }

   string tradeWhy = "";
   if(!AccountAllowsTrading(tradeWhy))
     {
      SetStatus("BLOCKED", tradeWhy, clrRed);
      return;
     }

   //--- A: refuse to act on indicator values we could not refresh. Three
   //    consecutive failed reads on any timeframe means the data feed is
   //    broken, and trading a stale EMA is worse than not trading.
   if(gStaleTrend > 3 || gStaleSignal > 3 || gStaleEntry > 3)
     {
      SetStatus("BLOCKED", StringFormat("stale indicator data (%d/%d/%d)",
                                        gStaleTrend, gStaleSignal, gStaleEntry),
                clrRed);
      CancelPending("stale indicator data");
      return;
     }

   //--- 0 disables the halt entirely (same convention as MaxDailyTradeCount).
   //    Without this guard a value of 0 would mean "halt at zero loss", i.e.
   //    stop for the day on the first losing cent - the opposite of "off".
   if(MaxDailyLossPercent > 0.0 && gDayStartBalance > 0.0 &&
      gDayPL <= -MathAbs(gDayStartBalance * MaxDailyLossPercent / 100.0))
     {
      SetStatus("HALTED", StringFormat("daily stop  %.2f / -%.1f%%",
                                       gDayPL, MaxDailyLossPercent), clrRed);
      CancelPending("daily loss stop reached");
      return;
     }

   if(MaxDailyTradeCount > 0 && gDayTrades >= MaxDailyTradeCount)
     {
      SetStatus("HALTED", StringFormat("daily trade cap %d/%d",
                                       gDayTrades, MaxDailyTradeCount), clrOrange);
      CancelPending("daily trade cap reached");
      return;
     }

   UpdateDirBrake();

   //--- v7.26: this used to be a blanket "return", which meant that during a
   //    cooldown EvaluateRsiExtreme was never called at all - so gXArmBars
   //    stopped incrementing and an armed washout could not expire. On 1 Sep
   //    a BUY armed at 09:20 would have sat frozen through a cooldown running
   //    to 10:22 and then been re-tested against an hour-old signal. The gate
   //    now lives at each entry point instead: the triggers keep running and
   //    ageing, and only the entry itself is refused.

   if(IsFridayCutoff())
     {
      SetStatus("BLOCKED", "Friday cutoff", clrOrange);
      CancelPending("Friday cutoff");
      return;
     }

   if(NewsBlocked())
     {
      SetStatus("BLOCKED", InManualNewsWindow()
                ? "manual news blackout window" : "high-impact news window",
                clrOrange);
      CancelPending("news window");
      return;
     }

   if(!FreeMarginOK())
     {
      SetStatus("BLOCKED", "free margin below floor", clrRed);
      CancelPending("free margin floor");
      return;
     }

   //--- RSI extreme trigger ------------------------------------------------
   //    Runs BEFORE the trend logic because it takes precedence: while an
   //    extreme is armed it owns the tick and any resting trend limit is
   //    cancelled. Existing trend POSITIONS are left alone - this cancels
   //    orders, it does not close trades.
   //--- B: if the trigger is switched off while armed, its restriction on the
   //    opposing trend direction would otherwise persist forever, silently
   //    forcing every entry out to the 15M level or blocking it outright.
   if(!EnableRsiExtreme && (gXOpposeDir != 0 || gXArmed))
     {
      gXOpposeDir  = 0;
      gXHardBlock  = false;
      gXArmed      = false;
      gXNeedsReset = false;
      gXState      = "disabled";
     }

   gPhase = "EVAL_XTREME";
   if(EnableRsiExtreme && EvaluateRsiExtreme(newEntryBar))
      return;

   //--- with-trend RSI exhaustion. Runs after the extreme (which has
   //    precedence) but before the EMA50 limit logic, because when it fires
   //    it replaces that entry rather than adding to it.
   if(!EnableTrendRsi && (gTArmed || gTNeedsReset))
     {
      gTArmed      = false;
      gTNeedsReset = false;
      gTState      = "disabled";
     }
   gPhase = "EVAL_TRSI";
   if(EnableTrendRsi && EvaluateTrendRsi(newEntryBar))
      return;

   //--- direction ----------------------------------------------------------
   int  dir     = 0;
   bool counter = false;
   if(!DesiredDirection(dir, counter))
     {
      SetStatus("NO TRADE", "price inside the 15M cloud", clrSilver);
      ResetSetup();
      CancelPending("inside the cloud");
      return;
     }

   if(!RsiConfirms(dir))
     {
      SetStatus("WAIT", (RsiMode == RSI_MODE_ARM)
                ? StringFormat("5M RSI %.1f - %s arm cold (needs a touch %s %.0f)",
                               gRsiNow, dir > 0 ? "BUY" : "SELL",
                               dir > 0 ? "<" : ">", RsiLevelMid)
                : StringFormat("5M RSI %.1f blocks %s (%s mode)",
                               gRsiNow, dir > 0 ? "BUY" : "SELL", RsiModeName()),
                clrSilver);
      ResetSetup();
      CancelPending("RSI does not confirm");
      return;
     }

   //--- exposure limits -----------------------------------------------------
   int openPos = CountPositions();
   if(openPos >= MaxConcurrentPositions)
     {
      SetStatus("FULL", StringFormat("%d/%d positions open",
                                     openPos, MaxConcurrentPositions), clrOrange);
      CancelPending("position limit reached");
      return;
     }

   if(InCooldown(dir))
     {
      SetStatus("COOLDOWN", StringFormat("%s cooling - %d min left after a loss",
                                         dir > 0 ? "BUY" : "SELL", CooldownMinsLeft()),
                clrOrange);
      CancelPending("cooldown after loss");
      return;
     }

   if(DirectionBraked(dir))
     {
      SetStatus("BRAKED", StringFormat("%s blocked - %d losses in a row on that side",
                                       dir > 0 ? "BUY" : "SELL", gDirLossStreak),
                clrOrange);
      CancelPending("direction brake");
      return;
     }

   if(BlockOpposingEntries && HasOpposingPosition(dir))
     {
      SetStatus("BLOCKED", "opposing position open", clrOrange);
      CancelPending("opposing position open");
      return;
     }

   //--- direction change resets the state machine ----------------------------
   if(dir != gSetupDir)
     {
      ResetSetup();
      CancelPending("direction changed");
      gCrossInit    = false;   // stale side-of-level memory must not fire
      gCrossBlocked = false;
      gSetupDir     = dir;
      gSetupCounter = counter;
     }
   gSetupCounter = counter;

   //--- spread -----------------------------------------------------------------
   double spreadPips = CurrentSpreadPips();
   if(spreadPips > MaxSpreadPips)
     {
      SetStatus("BLOCKED", StringFormat("spread %.0fp > %.0fp",
                                        spreadPips, MaxSpreadPips), clrOrange);
      CancelPending("spread too wide");
      return;
     }

   //--- v7.16: the RSI-extreme restriction used to live BELOW this block, so
   //    cross entries escaped it entirely - a market order could fire against
   //    a live washout while the limit path was correctly blocked. The hard
   //    block is evaluated here, before any cross can fire.
   if(gXOpposeDir != 0 && dir == gXOpposeDir && gXHardBlock)
     {
      SetStatus("BLOCKED", StringFormat("%s opposes a live RSI extreme",
                                        dir > 0 ? "BUY" : "SELL"), clrOrange);
      CancelPending("opposes a live RSI extreme");
      return;
     }

   //--- cross entries: evaluated before the limit level is resolved, because
   //    a break through the level is precisely when that level stops being a
   //    valid place to rest a limit.
   if(EntryStyle == ENTRY_CROSS || EntryStyle == ENTRY_BOTH)
     {
      //--- while an extreme is merely ARMED the limit path is pushed out to
      //    the 15M level; the cross equivalent is to allow only the 15M
      //    break, never the shallow 1M/5M ones.
      gPhase = "EVAL_CROSS";
      bool deepOnly = (gXOpposeDir != 0 && dir == gXOpposeDir);
      if(EvaluateCross(dir, counter, deepOnly))
         return;
     }
   if(EntryStyle == ENTRY_CROSS)
     {
      SetStatus("WATCH", StringFormat("%s on a break of the EMA50",
                                      dir > 0 ? "BUY" : "SELL"), clrSilver);
      CancelPending("cross-only entry style");
      return;
     }

   //--- resolve which EMA50 the limit will rest at ------------------------------
   //    Primary is the 1M EMA50. When a spike puts price the wrong side of it
   //    the limit cannot be placed at all, so fall back to the slower 5M EMA50,
   //    which in a trend sits further from price and is still a valid level.
   //    Every gate below measures against whichever level is chosen here.
   if(!ResolveEntryLevel(dir, gEntryLevel, gEntryLevelSrc))
     {
      SetStatus("WAIT", dir > 0
                ? "no free EMA50 level below price"
                : "no free EMA50 level above price", clrSilver);
      CancelPending("no placeable limit level");
      return;
     }

   //--- RSI extreme restriction on the OPPOSING trend direction ------------------
   //    Overbought => the EA wants to sell, so a trend BUY is opposing.
   //      armed  : force the entry out to the deep 15M EMA50
   //      fired  : block entirely until RSI returns to neutral
   //    Non-opposing trend entries are untouched.
   if(gXOpposeDir != 0 && dir == gXOpposeDir)
     {
      //--- the hard block is handled earlier now, above the cross evaluation
      if(gEntryLevelSrc != 2)   // anything shallower than the 15M EMA50
        {
         if(!LevelIsPlaceable(dir, gEma15S))
           {
            SetStatus("WAIT", "RSI extreme: 15M EMA50 only, not reachable", clrOrange);
            CancelPending("15M-only restriction, level unreachable");
            return;
           }
         gEntryLevel    = gEma15S;
         gEntryLevelSrc = 2;
         if(VerboseLog)
            PrintFormat("[TREMA] RSI extreme active: %s forced to the 15M EMA50.",
                        dir > 0 ? "BUY" : "SELL");
        }
     }

   //--- re-arm -------------------------------------------------------------------
   double distPips = MathAbs(CurrentPrice(dir) - gEntryLevel) / gPip;
   if(gRearmPending)
     {
      if(distPips >= RearmDistancePips)
        {
         gRearmPending = false;
         if(VerboseLog)
            PrintFormat("[TREMA] Re-armed: price %.0fp clear of 1M EMA50.", distPips);
        }
      else
        {
         SetStatus("WAIT", StringFormat("re-arm %.0f / %.0f pips",
                                        distPips, RearmDistancePips), clrSilver);
         return;
        }
     }

   //--- retest gate ---------------------------------------------------------------
   bool needsRetest = UseRetestGate && OpposingEntryEmas(dir, gEntryLevelSrc);

   if(!needsRetest)
     {
      gState = SS_READY;
     }
   else
     {
      if(newEntryBar)
         gStateBars++;

      if(gState == SS_IDLE)
        {
         gState      = SS_WAIT_TOUCH;
         gStateBars  = 0;
        }

      if(gStateBars > RetestExpiryBars && gState != SS_READY)
        {
         gState     = SS_WAIT_TOUCH;
         gStateBars = 0;
         if(VerboseLog)
            Print("[TREMA] Retest wait expired, restarting the touch count.");
        }

      double retestPips = RetestPips();

      if(gState == SS_WAIT_TOUCH)
        {
         if(TouchedEma50(dir))
           {
            gState     = SS_WAIT_PULLAWAY;
            gStateBars = 0;
            if(VerboseLog)
               Print("[TREMA] First touch consumed, waiting for pull-away.");
           }
         else
           {
            SetStatus("WAIT", "first touch not taken (retest gate)", clrSilver);
            CancelPending("retest gate armed");
            return;
           }
        }

      if(gState == SS_WAIT_PULLAWAY)
        {
         double away = PullAwayPips(dir);
         if(away >= retestPips)
           {
            gState     = SS_READY;
            gStateBars = 0;
            if(VerboseLog)
               PrintFormat("[TREMA] Pull-away %.0fp complete, retest entry armed.", away);
           }
         else
           {
            SetStatus("WAIT", StringFormat("retest pull-away %.0f / %.0f pips",
                                           away, retestPips), clrSilver);
            CancelPending("awaiting retest pull-away");
            return;
           }
        }
     }

   //--- place or maintain the limit ---------------------------------------------
   gPhase = "MANAGE_LIMIT";
   ManageLimit(dir, counter, newEntryBar);
  }

//+------------------------------------------------------------------+
//| RSI EXTREME TRIGGER                                                |
//|                                                                    |
//|  Independent mean-reversion entry. Fires on a multi-timeframe RSI  |
//|  washout regardless of trend. Returns true when it owns this tick. |
//+------------------------------------------------------------------+
//--- mirrored thresholds: a BUY level of 25 implies a SELL level of 75
double XFast(const int dir) { return(dir > 0 ? RsiXFastLevel : 100.0 - RsiXFastLevel); }
double XSlow(const int dir) { return(dir > 0 ? RsiXSlowLevel : 100.0 - RsiXSlowLevel); }
//--- the 15M gets its own confirmation level: it is a slower, less twitchy
//    RSI, so requiring it to lean harder is a meaningful extra filter.
double XSlow15(const int dir) { return(dir > 0 ? RsiXSlow15Level : 100.0 - RsiXSlow15Level); }
double X3TF (const int dir) { return(dir > 0 ? RsiX3TFLevel  : 100.0 - RsiX3TFLevel);  }

//--- is `v` beyond the threshold in the direction of this trade?
bool XBeyond(const int dir, const double v, const double level)
  {
   return(dir > 0 ? (v < level) : (v > level));
  }

//--- does a washout exist right now? Fills tag / which TF confirms the turn.
bool XConditionMet(const int dir, string &tag, bool &fastIsM1)
  {
   //--- 0.0 means "never read", not "maximally oversold". Without this an
   //    early failed CopyBuffer arms a phantom BUY washout at startup.
   if(gRsi1 <= 0.0 || gRsiNow <= 0.0 || gRsi15 <= 0.0)
     {
      tag = ""; fastIsM1 = true;
      return(false);
     }
   bool pairA = XBeyond(dir, gRsi1,      XFast(dir)) &&
                XBeyond(dir, gRsi5Now(), XSlow(dir));
   bool pairB = XBeyond(dir, gRsi5Now(), XFast(dir)) &&
                XBeyond(dir, gRsi15,     XSlow15(dir));

   //--- 3TF is a strict subset of pairA (the 1M level is tighter), so it is
   //    a LABEL for a stronger washout, not a separate trigger.
   bool three = XBeyond(dir, gRsi1,      X3TF(dir))    &&
                XBeyond(dir, gRsi5Now(), XSlow(dir))    &&
                XBeyond(dir, gRsi15,     XSlow15(dir));

   if(three)      { tag = "3TF";   fastIsM1 = true;  return(true); }
   if(pairA)      { tag = "1M5M";  fastIsM1 = true;  return(true); }
   if(pairB)      { tag = "5M15M"; fastIsM1 = false; return(true); }
   tag = ""; fastIsM1 = true;
   return(false);
  }

double gRsi5Now() { return(gRsiNow); }   // the 5M RSI already cached each 5M bar

void SetXState(const string txt, const color clr)
  {
   gXState = txt;
   //--- NOTE: this must call SetStatus, never itself. A v5.2.2 regex once
   //    rewrote this line into SetXState(txt, clr) - infinite recursion,
   //    stack overflow, and an EA death on EVERY washout arm for two days.
   SetStatus("RSI-X", txt, clr);
  }

bool EvaluateRsiExtreme(const bool newEntryBar)
  {
   double fastRsi = gXFastIsM1 ? gRsi1 : gRsiNow;

   //--- waiting for RSI to return to neutral after a fire --------------------
   if(gXNeedsReset)
     {
      bool recovered = (gXDir > 0) ? (fastRsi > RsiXResetLevel)
                                   : (fastRsi < RsiXResetLevel);
      if(recovered)
        {
         gXNeedsReset = false;
         gXOpposeDir  = 0;
         gXHardBlock  = false;
         if(!MQLInfoInteger(MQL_TESTER))
            GlobalVariableDel(StringFormat("TREMA_XRESET_%s_%d", _Symbol,
                                           (int)MagicNumber));
         if(VerboseLog) Print("[TREMA] RSI extreme reset - trigger re-armed.");
        }
      else
        {
         //--- the sell has fired and RSI is still elevated: opposing trend
         //    entries are blocked outright until RSI returns to neutral.
         if(RsiXCancelsTrend)
           {
            gXOpposeDir = -gXDir;
            gXHardBlock = true;
           }
         SetXState(StringFormat("cooling: fast RSI %.1f -> %.0f",
                                         fastRsi, RsiXResetLevel), clrSilver);
         return(false);   // does not own the tick; trend logic runs restricted
        }
     }

   //--- arm ------------------------------------------------------------------
   if(!gXArmed)
     {
      string tag = ""; bool fm1 = true;
      int dir = 0;
      if(XConditionMet(1, tag, fm1))       dir = 1;
      else if(XConditionMet(-1, tag, fm1)) dir = -1;
      if(dir == 0)
        {
         gXOpposeDir = 0;
         gXHardBlock = false;
         gXState = StringFormat("watching  1M %.0f  5M %.0f  15M %.0f",
                                gRsi1, gRsiNow, gRsi15);
         return(false);
        }

      gXArmed    = true;
      gXTurned   = false;
      gXDir      = dir;
      gXTag      = tag;
      gXFastIsM1 = fm1;
      gXArmBars  = 0;
      PrintFormat("[TREMA] RSI EXTREME armed: %s %s  1M=%.1f 5M=%.1f 15M=%.1f",
                  dir > 0 ? "BUY" : "SELL", tag, gRsi1, gRsiNow, gRsi15);
     }

   //--- armed but not yet fired: opposing trend entries are pushed out to the
   //    15M EMA50 rather than cancelled, so a genuinely deep pullback is still
   //    tradeable while a shallow one is not.
   if(RsiXCancelsTrend)
     {
      gXOpposeDir = -gXDir;
      gXHardBlock = false;
     }

   if(newEntryBar)
      gXArmBars++;
   if(gXArmBars > RsiXArmExpiryBars)
     {
      PrintFormat("[TREMA] RSI extreme expired unfired after %d bars.  "
                  "turn=%s  last state: %s",
                  gXArmBars, gXTurned ? "yes" : "NEVER", gXState);
      gXArmed     = false;
      gXOpposeDir = 0;
      gXHardBlock = false;
      return(false);
     }

   fastRsi = gXFastIsM1 ? gRsi1 : gRsiNow;

   //--- entry timing ----------------------------------------------------------
   if(RsiXWaitForTurn)
     {
      bool turned = (gXDir > 0) ? (fastRsi > XFast(gXDir))
                                : (fastRsi < XFast(gXDir));
      if(!turned)
        {
         SetXState(StringFormat("armed %s %s - waiting turn (%.1f)",
                                         gXDir > 0 ? "BUY" : "SELL", gXTag, fastRsi),
                   clrGold);
         //--- return FALSE so the trend leg still runs; it will be held to the
         //    15M level for the opposing direction by gXOpposeDir.
         return(false);
        }
      gXTurned = true;
     }

   //--- risk gates the trigger still has to satisfy ---------------------------
   if(CountPositions() >= MaxConcurrentPositions)
     {
      SetXState("blocked: position cap", clrOrange);
      return(false);
     }
   double spr = CurrentSpreadPips();
   if(spr > MaxSpreadPips)
     {
      SetXState(StringFormat("blocked: spread %.0fp", spr), clrOrange);
      return(false);
     }

   //--- never end up long and short at once. Stay ARMED rather than disarming:
   //    if the opposing position closes while the washout is still valid, the
   //    trigger can still take it.
   if(InCooldown(gXDir))
     {
      SetXState(StringFormat("held: %s cooling, %d min left",
                             gXDir > 0 ? "BUY" : "SELL", CooldownMinsLeft()), clrOrange);
      return(false);
     }
   if(DirectionBraked(gXDir))
     {
      SetXState(StringFormat("held: %s brake (%d losses in a row)",
                             gXDir > 0 ? "BUY" : "SELL", gDirLossStreak), clrOrange);
      return(false);
     }
   if(BlockOpposingEntries && HasOpposingPosition(gXDir))
     {
      SetXState("held: opposing position open", clrOrange);
      return(false);
     }
   if(SlotOccupied("RSIX"))
     {
      SetXState("held: an extreme position is already open", clrOrange);
      return(false);
     }

   FireRsiExtreme();
   return(true);
  }

void FireRsiExtreme()
  {
   double riskPct = 0.0; string why = "";
   double lot = CalcLot(SLPips * gPip, riskPct, why);
   if(lot <= 0.0)
     {
      SetXState("REJECT " + why, clrRed);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryNow = (gXDir > 0) ? ask : bid;

   //--- v7.20: the washout has the same structural problem as the
   //    counter-trend leg - it fades into the cloud and the 15M EMA50, and a
   //    fixed 2000-pip target routinely sits far beyond both. Aim at the
   //    first barrier instead, and refuse when the room is not worth the risk.
   double tpPips = TPPips;
   if(RsiXUseBarrierTP)
     {
      double barrier = 0.0, room = 0.0;
      tpPips = BarrierTargetPips(gXDir, entryNow, TPPips,
                                 barrier, room);
      double rr = (SLPips > 0.0) ? tpPips / SLPips : 0.0;
      if(rr < MinRsiXRR)
        {
         string rkz = StringFormat("RSIX%d%.0f%.2f", gXDir, room, barrier);
         if(rkz != gLastRejectKey)
           {
            gLastRejectKey = rkz;
            PrintFormat("[TREMA] RSI EXTREME %s REFUSED: only %.0f pips to the "
                        "%s barrier at %.2f (entry %.2f), RR %.2f below the "
                        "%.2f floor.", gXDir > 0 ? "BUY" : "SELL", room,
                        gBarrierName, barrier, entryNow, rr, MinRsiXRR);
           }
         SetXState(StringFormat("blocked: %.0fp room, RR %.2f", room, rr),
                   clrOrange);
         gXArmed = false;      // do not sit armed on a setup we will not take
         return;
        }
     }

   double sl, tp;
   if(gXDir > 0)
     {
      sl = NormalizeDouble(ask - SLPips * gPip, gDigits);
      tp = NormalizeDouble(ask + tpPips           * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(bid + SLPips * gPip, gDigits);
      tp = NormalizeDouble(bid - tpPips           * gPip, gDigits);
     }

   string comment = StringFormat("%s-RSIX-%s", TradeCommentPrefix, gXTag);
   bool ok = (gXDir > 0)
             ? gTrade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
             : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
     {
      RememberGeometry(gTrade.ResultOrder(), SLPips, tpPips);
      PrintFormat("[TREMA] RSI EXTREME %s %s filled lot %.2f risk %.2f%% SL %.2f TP %.2f",
                  gXDir > 0 ? "BUY" : "SELL", gXTag, lot, riskPct, sl, tp);
      SetXState(StringFormat("FIRED %s %s  lot %.2f",
                                      gXDir > 0 ? "BUY" : "SELL", gXTag, lot),
                gXDir > 0 ? clrLime : clrTomato);
      gXArmed      = false;
      gXNeedsReset = true;   // one trade per washout event
      if(!MQLInfoInteger(MQL_TESTER))
         GlobalVariableSet(StringFormat("TREMA_XRESET_%s_%d", _Symbol,
                                        (int)MagicNumber), (double)gXDir);
     }
   else
     {
      PrintFormat("[TREMA] RSI extreme order failed (%d): %s",
                  gTrade.ResultRetcode(), gTrade.ResultComment());
      SetXState(StringFormat("order rejected %d", gTrade.ResultRetcode()), clrRed);
      gXArmed = false;
     }
  }

//+------------------------------------------------------------------+
//| CROSS ENTRY  (break through the EMA50, market on touch)            |
//+------------------------------------------------------------------+
//--- v7.18: a cross entry can be with-trend OR counter-trend, exactly like a
//    limit entry. Until now it never asked: every cross used the with-trend
//    900/2000 geometry and was tagged "XING-5M" with no record of which it
//    was. So a counter-trend trade entered through the cross door risked $9
//    for $20 instead of the $5 for $10 the operator specified, and was later
//    scored in the with-trend column. The flag is the same one DesiredDirection
//    already produces - it was simply being discarded here.
void FireCross(const int dir, const string levelTag, const double level,
               const bool counter)
  {
   double slPips = counter ? CounterSLPips         : SLPips;
   double tpPips = counter ? TakeProfitCounterPips : TPPips;

   //--- same barrier rule as the limit path: a cross into a counter-trend
   //    setup is the same trade arriving through a different door.
   if(counter)
     {
      double entryNow = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double barrier = 0.0, room = 0.0;
      tpPips = CounterTargetPips(dir, entryNow, barrier, room);
      double rr = (slPips > 0.0) ? tpPips / slPips : 0.0;
      if(rr < MinCounterRR)
        {
         string rkx = StringFormat("XCTR%d%.0f%.2f", dir, room, barrier);
         if(rkx != gLastRejectKey)
           {
            gLastRejectKey = rkx;
            PrintFormat("[TREMA] Counter-trend CROSS %s REFUSED: only %.0f pips "
                        "to the %s barrier at %.2f, RR %.2f below the %.2f "
                        "floor.", dir > 0 ? "BUY" : "SELL", room,
                        gBarrierName, barrier,
                        rr, MinCounterRR);
           }
         SetStatus("SKIP", StringFormat("counter cross %.0fp room, RR %.2f",
                                        room, rr), clrOrange);
         return;
        }
     }

   double riskPct = 0.0; string why = "";
   double lot = CalcLot(slPips * gPip, riskPct, why);
   if(lot <= 0.0)
     {
      SetStatus("REJECT", why, clrRed);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(dir > 0)
     {
      sl = NormalizeDouble(ask - slPips * gPip, gDigits);
      tp = NormalizeDouble(ask + tpPips * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(bid + slPips * gPip, gDigits);
      tp = NormalizeDouble(bid - tpPips * gPip, gDigits);
     }

   //--- the tag now records BOTH facts: the door (XING) and the direction
   //    type (CTR or not), so results can be attributed correctly.
   string comment = counter
                    ? StringFormat("%s-XING-CTR-%s", TradeCommentPrefix, levelTag)
                    : StringFormat("%s-XING-%s",     TradeCommentPrefix, levelTag);
   bool ok = (dir > 0)
             ? gTrade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
             : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
     {
      RememberGeometry(gTrade.ResultOrder(), slPips, tpPips);
      PrintFormat("[TREMA] CROSS%s %s through the %s EMA50 @ %.2f  lot %.2f "
                  "risk %.2f%% SL %.2f TP %.2f",
                  counter ? "-CTR" : "", dir > 0 ? "BUY" : "SELL",
                  levelTag, level, lot, riskPct, sl, tp);
      SetStatus(counter ? "CROSS-CTR" : "CROSS",
                StringFormat("%s through %s EMA50  lot %.2f",
                             dir > 0 ? "BUY" : "SELL", levelTag, lot),
                dir > 0 ? clrLime : clrTomato);
      //--- do not re-fire while price oscillates around the same level
      gCrossBlocked = true;
      gCrossBlockAt = level;
     }
   else
     {
      PrintFormat("[TREMA] Cross order failed (%d): %s",
                  gTrade.ResultRetcode(), gTrade.ResultComment());
      SetStatus("ERROR", StringFormat("cross rejected %d", gTrade.ResultRetcode()),
                clrRed);
     }
  }

//--- Returns true when a cross fired. Runs on raw levels rather than the
//    resolved limit level: for a SELL the limit becomes unplaceable exactly
//    when price breaks below, which is the moment this trigger cares about.
bool EvaluateCross(const int dir, const bool counter,
                   const bool deepOnly = false)
  {
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   uint   nowCross = GetTickCount();

   //--- v7.15: the side memory is refreshed only when this function runs,
   //    but every gate above it in EvaluateAndAct returns early (RSI veto,
   //    position cap, spread, news, cooldown, an armed extreme owning the
   //    tick). After such a stretch the remembered side is minutes stale and
   //    the first call back fires a "crossing" that already happened, at a
   //    far worse price. Memory older than a bar and a half is no memory.
   if(gCrossInit && (nowCross - gCrossSeenMs) > 90000)
     {
      gCrossInit = false;
      if(VerboseLog)
         Print("[TREMA] Cross side-memory went stale - re-seeding, no fire.");
     }

   bool a1  = (bid > gEma1S);
   bool a5  = (bid > gEma5S);
   bool a15 = (bid > gEma15S);

   bool fired = false;

   //--- re-arm: price must clear the crossed level before another cross counts
   if(gCrossBlocked)
     {
      if(MathAbs(bid - gCrossBlockAt) >= RearmDistancePips * gPip)
         gCrossBlocked = false;
     }

   if(gCrossInit && !gCrossBlocked)
     {
      bool x1  = (dir < 0) ? (gWasAbove1  && !a1)  : (!gWasAbove1  && a1);
      bool x5  = (dir < 0) ? (gWasAbove5  && !a5)  : (!gWasAbove5  && a5);
      bool x15 = (dir < 0) ? (gWasAbove15 && !a15) : (!gWasAbove15 && a15);

      //--- a crossing whose slot is already occupied is skipped, not queued:
      //    the next level is still considered, since it is a different slot.
      if(!deepOnly && x1 && gEma1S > 0.0 && !SlotOccupied("EMA1"))
        { FireCross(dir, "1M",  gEma1S,  counter); fired = true; }
      else if(!deepOnly && x5 && gEma5S > 0.0 && !SlotOccupied("EMA5"))
        { FireCross(dir, "5M",  gEma5S,  counter); fired = true; }
      else if(x15 && gEma15S > 0.0 && !SlotOccupied("EMA15"))
        { FireCross(dir, "15M", gEma15S, counter); fired = true; }
     }

   //--- always update, or the same crossing would re-fire every tick
   gWasAbove1   = a1;
   gWasAbove5   = a5;
   gWasAbove15  = a15;
   gCrossInit   = true;
   gCrossSeenMs = nowCross;

   return(fired);
  }

//+------------------------------------------------------------------+
//| TREND RSI TRIGGER  (with-trend pullback exhaustion)                |
//|                                                                    |
//|  15M below cloud + 1M RSI spikes above 70  -> sell the exhaustion.  |
//|  15M above cloud + 1M RSI drops below 30   -> buy it.               |
//|  The 5M must not be pointing the other way. Entry is market, taken  |
//|  only once the 1M RSI turns back through the level - the same       |
//|  confirmation that stopped the extreme trigger firing 10 minutes    |
//|  and 2.6R too early on 26 Aug.                                      |
//+------------------------------------------------------------------+
//--- 70 for a SELL implies 30 for a BUY
double TLevel(const int dir) { return(dir > 0 ? 100.0 - TrendRsiLevel : TrendRsiLevel); }

bool TBeyond(const int dir, const double v, const double lvl)
  {
   return(dir > 0 ? (v < lvl) : (v > lvl));
  }

//--- direction comes from the 15M cloud alone; inside the cloud there is no
//    trend to be with, so this trigger stands aside.
int TDirFromCloud()
  {
   if(gCloud == CLOUD_ABOVE) return(1);
   if(gCloud == CLOUD_BELOW) return(-1);
   return(0);
  }

//--- the 5M need not agree, but it must not actively oppose
bool T5mNotOpposing(const int dir)
  {
   if(dir > 0) return(gDir5 >= 0);
   if(dir < 0) return(gDir5 <= 0);
   return(false);
  }

void FireTrendRsi()
  {
   double riskPct = 0.0; string why = "";
   double lot = CalcLot(SLPips * gPip, riskPct, why);
   if(lot <= 0.0)
     {
      gTState = "REJECT " + why;
      SetStatus("TRSI", gTState, clrRed);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(gTDir > 0)
     {
      sl = NormalizeDouble(ask - SLPips * gPip, gDigits);
      tp = NormalizeDouble(ask + TPPips * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(bid + SLPips * gPip, gDigits);
      tp = NormalizeDouble(bid - TPPips * gPip, gDigits);
     }

   string comment = StringFormat("%s-TRSI", TradeCommentPrefix);
   bool ok = (gTDir > 0)
             ? gTrade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
             : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
     {
      RememberGeometry(gTrade.ResultOrder(), SLPips, TPPips);
      PrintFormat("[TREMA] TREND-RSI %s filled lot %.2f risk %.2f%% SL %.2f TP %.2f",
                  gTDir > 0 ? "BUY" : "SELL", lot, riskPct, sl, tp);
      //--- this trigger and the EMA50 limit want the same trade; the operator
      //    chose RSI timing over level timing, so the limit goes.
      if(TrendRsiCancelsLimit)
         CancelPending("trend-RSI trigger fired");
      gTState      = StringFormat("FIRED %s  lot %.2f", gTDir > 0 ? "BUY" : "SELL", lot);
      SetStatus("TRSI", gTState, gTDir > 0 ? clrLime : clrTomato);
      gTArmed      = false;
      gTNeedsReset = true;
     }
   else
     {
      PrintFormat("[TREMA] TREND-RSI order failed (%d): %s",
                  gTrade.ResultRetcode(), gTrade.ResultComment());
      gTState = StringFormat("order rejected %d", gTrade.ResultRetcode());
      SetStatus("TRSI", gTState, clrRed);
      gTArmed = false;
     }
  }

//--- returns true when it fired and owns this tick
bool EvaluateTrendRsi(const bool newEntryBar)
  {
   //--- one entry per exhaustion: wait for RSI to return to neutral
   if(gTNeedsReset)
     {
      bool recovered = (gTDir > 0) ? (gRsi1 > TrendRsiResetLevel)
                                   : (gRsi1 < TrendRsiResetLevel);
      if(recovered)
         gTNeedsReset = false;
      else
        {
         gTState = StringFormat("cooling: 1M RSI %.1f -> %.0f",
                                gRsi1, TrendRsiResetLevel);
         return(false);
        }
     }

   if(gRsi1 <= 0.0)   // no valid 1M RSI yet - see XConditionMet note
      return(false);

   int dir = TDirFromCloud();
   if(dir == 0 || !T5mNotOpposing(dir))
     {
      gTArmed = false;
      gTState = (dir == 0) ? "idle: inside the 15M cloud" : "idle: 5M opposes";
      return(false);
     }

   if(!gTArmed)
     {
      if(!TBeyond(dir, gRsi1, TLevel(dir)))
        {
         gTState = StringFormat("watching  1M RSI %.1f (need %s %.0f)",
                                gRsi1, dir > 0 ? "<" : ">", TLevel(dir));
         return(false);
        }
      gTArmed   = true;
      gTTurned  = false;
      gTDir     = dir;
      gTArmBars = 0;
      PrintFormat("[TREMA] TREND-RSI armed: %s  1M RSI=%.1f  15M %s cloud  5M dir=%d",
                  dir > 0 ? "BUY" : "SELL", gRsi1,
                  dir > 0 ? "above" : "below", gDir5);
     }

   if(newEntryBar)
      gTArmBars++;
   if(gTArmBars > TrendRsiExpiryBars)
     {
      PrintFormat("[TREMA] TREND-RSI expired unfired after %d bars.  "
                  "turn=%s  last state: %s",
                  gTArmBars, gTTurned ? "yes" : "NEVER", gTState);
      gTArmed = false;
      return(false);
     }

   //--- turn confirmation: RSI must come back through the level
   bool turned = (gTDir > 0) ? (gRsi1 > TLevel(gTDir)) : (gRsi1 < TLevel(gTDir));
   if(!turned)
     {
      gTState = StringFormat("armed %s - waiting turn (%.1f)",
                             gTDir > 0 ? "BUY" : "SELL", gRsi1);
      return(false);
     }
   gTTurned = true;

   //--- Structural confirmation on the EXECUTION timeframe.
   //    Without this the trigger bought a 1M downtrend because a 15M cloud
   //    twenty points below still said "uptrend": on 27 Aug it armed at
   //    12:00 with 1M RSI 29.8 and fired 21 minutes later at a LOWER price,
   //    with the 1M EMA20 sitting below the EMA50 the whole time. RSI alone
   //    cannot tell a two-minute washout from a slow grind down; the 1M EMA
   //    relationship can. This is the same idea as the retest gate that the
   //    limit entries already have, applied at fire time so the setup still
   //    gets a chance to mature while armed.
   if(TrendRsiRequire1M)
     {
      bool oppose = (gTDir > 0) ? (gEma1F < gEma1S) : (gEma1F > gEma1S);
      if(oppose)
        {
         gTState = StringFormat("blocked: 1M EMAs oppose (%.2f/%.2f)",
                                gEma1F, gEma1S);
         return(false);
        }
     }

   if(CountPositions() >= MaxConcurrentPositions)
     {
      gTState = "blocked: position cap";
      return(false);
     }
   double spr = CurrentSpreadPips();
   if(spr > MaxSpreadPips)
     {
      gTState = StringFormat("blocked: spread %.0fp", spr);
      return(false);
     }
   if(InCooldown(gTDir))
     {
      gTState = StringFormat("held: %s cooling, %d min left",
                             gTDir > 0 ? "BUY" : "SELL", CooldownMinsLeft());
      return(false);
     }
   if(DirectionBraked(gTDir))
     {
      gTState = StringFormat("held: %s brake (%d losses in a row)",
                             gTDir > 0 ? "BUY" : "SELL", gDirLossStreak);
      return(false);
     }
   if(BlockOpposingEntries && HasOpposingPosition(gTDir))
     {
      gTState = "held: opposing position open";
      return(false);
     }
   if(SlotOccupied("TRSI"))
     {
      gTState = "held: a trend-RSI position is already open";
      return(false);
     }

   FireTrendRsi();
   return(true);
  }

//+------------------------------------------------------------------+
//| Pending limit placement / re-pricing                               |
//+------------------------------------------------------------------+
void ManageLimit(const int dir, const bool counter, const bool newEntryBar)
  {
   //--- level was already resolved and validated by ResolveEntryLevel() ------
   double level = NormalizeDouble(gEntryLevel, gDigits);
   string levelTag = EntryLevelTag();

   //--- The counter-trend leg keeps its own tighter 500/1000 geometry. It is
   //    fading a confirmed 15M trend on a 5M wobble, so it should be cut
   //    quickly rather than given the room a with-trend entry deserves.
   double slPips = counter ? CounterSLPips        : SLPips;
   double tpPips = counter ? TakeProfitCounterPips : TPPips;

   //--- counter-trend: aim at the first 15M barrier, and refuse the trade if
   //    the room left is not worth the risk.
   if(counter)
     {
      double barrier = 0.0, room = 0.0;
      tpPips = CounterTargetPips(dir, level, barrier, room);
      double rr = (slPips > 0.0) ? tpPips / slPips : 0.0;
      if(rr < MinCounterRR)
        {
         SetStatus("SKIP", StringFormat("counter %.0fp to %s barrier, RR %.2f < %.2f",
                                        room, gBarrierName, rr, MinCounterRR), clrOrange);
         string rk = StringFormat("CTR%d%.0f%.2f", dir, room, barrier);
         if(rk != gLastRejectKey)
           {
            gLastRejectKey = rk;
            PrintFormat("[TREMA] Counter-trend %s REFUSED: only %.0f pips of room "
                        "to the %s barrier at %.2f (entry %.2f), RR %.2f below "
                        "the %.2f floor.", dir > 0 ? "BUY" : "SELL", room,
                        gBarrierName, barrier, level, rr, MinCounterRR);
           }
         CancelPending("counter-trend target blocked by 15M structure");
         return;
        }
     }

   double sl, tp;
   if(dir > 0)
     {
      sl = NormalizeDouble(level - slPips * gPip, gDigits);
      tp = NormalizeDouble(level + tpPips * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(level + slPips * gPip, gDigits);
      tp = NormalizeDouble(level - tpPips * gPip, gDigits);
     }

   //--- one position per trigger source ------------------------------------------
   string slot = SlotForLevel(gEntryLevelSrc);
   if(SlotOccupied(slot))
     {
      SetStatus("SLOT", StringFormat("%s EMA50 already has a position", levelTag),
                clrOrange);
      //--- cancel any limit resting on this level too, or it would fill and
      //    become the second position this rule exists to prevent.
      CancelPending("slot already occupied: " + slot);
      return;
     }

   //--- sizing ------------------------------------------------------------------
   double riskPct = 0.0;
   string reason  = "";
   double lot     = CalcLot(slPips * gPip, riskPct, reason);
   if(lot <= 0.0)
     {
      SetStatus("REJECT", reason, clrRed);
      CancelPending("sizing rejected: " + reason);
      return;
     }

   //--- v7.15: the comment is written once at placement and is what
   //    TriggerSlot and SyncPositionStops read after the fill. If the level
   //    source or counter/trend flag changed while the limit rested,
   //    re-pricing left a "-1M"/"TREND" comment on what is now a 5M or
   //    counter-trend entry: wrong slot occupied, wrong stop geometry
   //    applied by the repair sweep, lot sized against the other stop.
   //    Cancel and re-place so the label always matches the order.
   if(gPendingTicket != 0 && PendingAlive(gPendingTicket) &&
      (gPendingCounter != counter || gPendingLevelSrc != gEntryLevelSrc))
     {
      PrintFormat("[TREMA] Pending #%I64u no longer matches its comment "
                  "(%s->%s, level %d->%d) - cancelling to re-place.",
                  gPendingTicket, gPendingCounter ? "CTR" : "TREND",
                  counter ? "CTR" : "TREND", gPendingLevelSrc, gEntryLevelSrc);
      CancelPending("counter/level changed under a resting limit");
     }

   //--- already have a live limit: re-price it on each new 1M bar ---------------
   if(gPendingTicket != 0 && PendingAlive(gPendingTicket))
     {
      if(newEntryBar)
        {
         double curPrice = OrderPriceOf(gPendingTicket);
         //--- FIX 7: stop retrying a re-price that keeps failing. Left
         //    unbounded it retried every bar forever, spamming the journal
         //    and hammering the broker with a request it always rejects.
         if(MathAbs(curPrice - level) >= gPoint && gRepriceFails < 3)
           {
            if(gTrade.OrderModify(gPendingTicket, level, sl, tp, ORDER_TIME_GTC, 0))
              {
               gRepriceFails = 0;
              }
            else
              {
               gRepriceFails++;
               PrintFormat("[TREMA] Re-price failed %d/3 (%d): %s",
                           gRepriceFails, gTrade.ResultRetcode(),
                           gTrade.ResultComment());
               if(gRepriceFails >= 3)
                 {
                  Print("[TREMA] Re-pricing abandoned; cancelling the limit "
                        "so a stale level cannot fill.");
                  CancelPending("re-price failed 3 times");
                  return;
                 }
              }
           }
        }
      SetStatus("ARMED", StringFormat("%s @ %.2f (%s)  lot %.2f  %.2f%%",
                                      dir > 0 ? "BUY" : "SELL", level, levelTag,
                                      lot, riskPct),
                dir > 0 ? clrLime : clrTomato);
      return;
     }

   //--- no live limit: place one -------------------------------------------------
   //    FIX 2: count committed exposure (open positions + any pending) before
   //    adding another. Reaching here means we hold no tracked pending, so a
   //    non-zero count is an orphan or a race.
   if(CountPositions() + CountOurPendings() >= MaxConcurrentPositions)
     {
      SetStatus("FULL", "position + pending cap reached", clrOrange);
      return;
     }

   //--- comment carries direction type AND which EMA50 level filled it, so
   //    the backtest report can be split by entry level after the fact.
   //    e.g. TREMA-TREND-15M  /  TREMA-CTR-5M
   string comment = StringFormat("%s-%s-%s", TradeCommentPrefix,
                                 counter ? "CTR" : "TREND", levelTag);
   bool ok = (dir > 0)
             ? gTrade.BuyLimit(lot, level, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment)
             : gTrade.SellLimit(lot, level, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);

   if(ok)
     {
      gPendingTicket   = gTrade.ResultOrder();
      RememberGeometry(gPendingTicket, slPips, tpPips);
      gPendingBars     = 0;
      gRepriceFails    = 0;
      gLastRejectKey   = "";              // next rejection may speak again
      gPendingCounter  = counter;         // remember what the comment claims
      gPendingLevelSrc = gEntryLevelSrc;
      PrintFormat("[TREMA] %s LIMIT placed #%I64u @ %.2f (%s EMA50) SL %.2f TP %.2f "
                  "lot %.2f risk %.2f%% [%s]",
                  dir > 0 ? "BUY" : "SELL", gPendingTicket, level, levelTag,
                  sl, tp, lot, riskPct, counter ? "COUNTER" : "TREND");
      SetStatus("ARMED", StringFormat("%s @ %.2f (%s)  lot %.2f  %.2f%%",
                                      dir > 0 ? "BUY" : "SELL", level, levelTag,
                                      lot, riskPct),
                dir > 0 ? clrLime : clrTomato);
     }
   else
     {
      PrintFormat("[TREMA] Limit placement failed (%d): %s",
                  gTrade.ResultRetcode(), gTrade.ResultComment());
      SetStatus("ERROR", StringFormat("order rejected %d", gTrade.ResultRetcode()), clrRed);
     }
  }

//+------------------------------------------------------------------+
//| COUNTER-TREND BARRIER TARGET                                       |
//|                                                                    |
//|  A counter-trend entry sits at an EMA50 inside a confirmed 15M      |
//|  trend, so it is fading that trend into its own support. The fixed  |
//|  1000-pip target ignored what stands in the way: on 28 Aug a short  |
//|  entered 147 pips above the cloud top and was given a 2000-pip      |
//|  target, i.e. it needed price to cut clean through the structure    |
//|  defining the uptrend. Aim at the barrier instead of past it, and   |
//|  refuse the trade when the room left is not worth the risk.         |
//+------------------------------------------------------------------+
//--- first structure price meets moving AWAY from a counter entry.
//    Selling from above: the highest candidate that is below the entry.
//    Buying from below : the lowest candidate that is above the entry.
//    Returns 0.0 when nothing stands in the way.
//--- v7.23: the 5M EMA50 joins the 15M cloud and 15M EMA50. 15M structure
//    is far away; 5M structure is close, and it is what actually turns
//    price first - "EMA 50 1M TF is hit 2x now without hitting the TP".
//    Targets past a level price visibly respects are targets that do not
//    get paid. Note this mostly REJECTS counters rather than shrinking
//    them, because MinCounterRR still has to be cleared afterwards.
string gBarrierName = "";   // which level won, for the logs

//--- consider one candidate; keeps the "nearest on the correct side" rule
//    and the winner's name in one place instead of four copies of it.
void BarrierTry(const int dir, const double entry, const double lvl,
                const string name, double &best)
  {
   if(lvl <= 0.0)
      return;
   if(dir < 0)                       // selling: barrier must be BELOW us
     {
      if(lvl >= entry) return;
      if(best <= 0.0 || lvl > best) { best = lvl; gBarrierName = name; }
     }
   else                              // buying: barrier must be ABOVE us
     {
      if(lvl <= entry) return;
      if(best <= 0.0 || lvl < best) { best = lvl; gBarrierName = name; }
     }
  }

double CounterBarrier(const int dir, const double entry)
  {
   double cloudTop = MathMax(gSenkouA, gSenkouB);
   double cloudBot = MathMin(gSenkouA, gSenkouB);
   double best     = 0.0;

   gBarrierName = "none";
   BarrierTry(dir, entry, (dir < 0 ? cloudTop : cloudBot), "15M cloud", best);
   BarrierTry(dir, entry, gEma15S, "15M EMA50", best);
   if(BarrierUse5M)
      BarrierTry(dir, entry, gEma5S, "5M EMA50", best);
   return(best);
  }

//--- TP in pips for a counter entry: the fixed cap, or the room to the
//    barrier less a buffer, whichever is smaller. barrierOut/roomOut are
//    filled for logging so a rejection can say exactly why.
//--- v7.20: generalised. The question "what stands between here and the
//    target" is the same for a counter-trend entry and for an RSI washout -
//    both fade into structure. Only the cap and the risk floor differ.
double BarrierTargetPips(const int dir, const double entry, const double capPips,
                         double &barrierOut, double &roomOut)
  {
   barrierOut = 0.0;
   roomOut    = 0.0;

   barrierOut = CounterBarrier(dir, entry);
   if(barrierOut <= 0.0)
      return(capPips);                    // clear air - keep the fixed target

   roomOut = MathAbs(entry - barrierOut) / gPip - CounterBarrierBuffer;
   if(roomOut < 0.0)
      roomOut = 0.0;
   return(MathMin(capPips, roomOut));
  }

double CounterTargetPips(const int dir, const double entry,
                         double &barrierOut, double &roomOut)
  {
   barrierOut = 0.0;
   roomOut    = 0.0;
   if(!CounterUseBarrierTP)
      return(TakeProfitCounterPips);
   return(BarrierTargetPips(dir, entry, TakeProfitCounterPips,
                            barrierOut, roomOut));
  }

//+------------------------------------------------------------------+
//| Position sizing: 2% target, rounded down, 2.5% hard ceiling        |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, double &riskPctOut, string &reason)
  {
   riskPctOut = 0.0;
   reason     = "";

   double capital = SizeFromEquity
                    ? AccountInfoDouble(ACCOUNT_EQUITY)
                    : AccountInfoDouble(ACCOUNT_BALANCE);
   if(capital <= 0.0)
     {
      reason = "capital is zero";
      return(0.0);
     }

   //--- fixed-lot diagnostic mode -------------------------------------------
   //    Compounding sizing makes an edge impossible to measure: wins land at
   //    one size and losses at another, so the win/loss averages stop
   //    reflecting the actual R multiples. Run a backtest with this ON to
   //    see the raw edge, then turn it OFF for money management.
   if(UseFixedLot)
     {
      double fmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double fmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double fstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(fstep <= 0.0)
         fstep = 0.01;
      double flot = NormalizeDouble(MathFloor(FixedLotSize / fstep) * fstep,
                                    VolumeDigits(fstep));
      if(flot < fmin) flot = fmin;
      if(flot > fmax) flot = fmax;

      double ftickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ftickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(ftickVal > 0.0 && ftickSz > 0.0)
         riskPctOut = (flot * (slDistance / ftickSz) * ftickVal) / capital * 100.0;
      return(flot);
     }

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSz <= 0.0)
     {
      reason = "broker tick value/size unavailable";
      return(0.0);
     }

   double lossPerLot = (slDistance / tickSz) * tickVal;
   if(lossPerLot <= 0.0)
     {
      reason = "loss per lot computed as zero";
      return(0.0);
     }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   int vd = VolumeDigits(step);

   //--- ideal size, then round DOWN so we never drift above the target -----
   double raw = (capital * RiskPercent / 100.0) / lossPerLot;
   double lot = NormalizeDouble(MathFloor(raw / step) * step, vd);

   //--- rounding down landed below the broker minimum ----------------------
   if(lot < minLot)
     {
      lot = minLot;
      double pct = (lot * lossPerLot) / capital * 100.0;
      if(pct > MaxRiskPercent)
        {
         reason = StringFormat("min lot %.2f risks %.2f%% > %.2f%% ceiling",
                               lot, pct, MaxRiskPercent);
         return(0.0);
        }
     }

   if(lot > maxLot)
      lot = maxLot;
   if(MaxLotSizeCap > 0.0 && lot > MaxLotSizeCap)
      lot = MaxLotSizeCap;

   lot = NormalizeDouble(lot, vd);
   if(lot <= 0.0)
     {
      reason = "computed lot is zero";
      return(0.0);
     }

   riskPctOut = (lot * lossPerLot) / capital * 100.0;

   //--- the ceiling is a hard reject, never a silent clamp ------------------
   if(riskPctOut > MaxRiskPercent + 0.0001)
     {
      reason = StringFormat("risk %.2f%% exceeds %.2f%% ceiling",
                            riskPctOut, MaxRiskPercent);
      return(0.0);
     }

   //--- margin check ---------------------------------------------------------
   double margin = 0.0;
   double price  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, price, margin))
     {
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        {
         reason = "insufficient free margin for this lot";
         return(0.0);
        }
     }

   return(lot);
  }

int VolumeDigits(const double step)
  {
   if(step >= 1.0)   return(0);
   if(step >= 0.1)   return(1);
   if(step >= 0.01)  return(2);
   return(3);
  }

//+------------------------------------------------------------------+
//| Indicator refresh - closed bars only for trend and direction       |
//| Returns true when a new EntryTF bar opened this tick.              |
//+------------------------------------------------------------------+
bool RefreshIndicators(const bool force)
  {
   bool newEntryBar = false;

   //--- Detect the 1M bar change FIRST, then use it to force a re-read of the
   //    slower timeframes too. Previously a failed 5M read waited up to five
   //    minutes for the next 5M close before even retrying; now every
   //    timeframe gets another attempt once a minute.
   datetime eBarNow  = iTime(_Symbol, EntryTF, 0);
   //--- v7.21: gLastEntryBar only advances on a SUCCESSFUL 1M read, so while
   //    that read was failing entryTick stayed true on every tick and forced
   //    a full re-read of all three timeframes thousands of times a minute.
   //    Gate the retry on the bar itself, not on whether it worked.
   bool     entryTick = (eBarNow != gLastEntrySeen);
   gLastEntrySeen     = eBarNow;

   //--- 15M trend gate ---------------------------------------------------
   datetime tBar = iTime(_Symbol, TrendTF, 0);
   if(force || entryTick || tBar != gLastTrendBar)
     {
      double closeArr[];
      if(CopyClose(_Symbol, TrendTF, 1, 1, closeArr) == 1 &&
         CopyOne(hIchi, 2, 1, gSenkouA) &&
         CopyOne(hIchi, 3, 1, gSenkouB))
        {
         gTrendClose = closeArr[0];
         double top  = MathMax(gSenkouA, gSenkouB);
         double bot  = MathMin(gSenkouA, gSenkouB);
         if(gTrendClose > top)      gCloud = CLOUD_ABOVE;
         else if(gTrendClose < bot) gCloud = CLOUD_BELOW;
         else                       gCloud = CLOUD_INSIDE;
         gStaleTrend = 0;
         //--- 15M EMAs are NOT part of the trend gate; they exist only to
         //    supply the deepest fallback entry level.
         //--- v7.15: these were unchecked, so gStaleTrend was cleared even
         //    when the 15M EMAs/RSI failed to read. gRsi15 then stayed 0.0
         //    and the stale-data hard block never saw it.
         if(!CopyOne(hEma15F, 0, 1, gEma15F) ||
            !CopyOne(hEma15S, 0, 1, gEma15S) ||
            !CopyOne(hRsi15,  0, 1, gRsi15))
            gStaleTrend++;
         gLastTrendBar = tBar;
        }
      else
         gStaleTrend++;
     }

   //--- 5M direction + momentum --------------------------------------------
   datetime sBar = iTime(_Symbol, SignalTF, 0);
   if(force || entryTick || sBar != gLastSignalBar)
     {
      if(CopyOne(hEma5F, 0, 1, gEma5F) &&
         CopyOne(hEma5S, 0, 1, gEma5S) &&
         CopyOne(hRsi5,  0, 1, gRsiNow) &&
         CopyOne(hRsi5,  0, 2, gRsiPrev))
        {
         gDir5 = (gEma5F > gEma5S) ? 1 : ((gEma5F < gEma5S) ? -1 : 0);
         UpdateRsiArms();
         gLastSignalBar = sBar;
         gStaleSignal   = 0;
        }
      else
         gStaleSignal++;
     }

   //--- 1M entry level -------------------------------------------------------
   datetime eBar = iTime(_Symbol, EntryTF, 0);
   if(force || eBar != gLastEntryBar)
     {
      if(CopyOne(hEma1F, 0, 1, gEma1F) &&
         CopyOne(hEma1S, 0, 1, gEma1S))
        {
         CopyOne(hRsi1, 0, 1, gRsi1);
         if(UseAtrRetest)
            CopyOne(hAtr1, 0, 1, gAtr1);
         newEntryBar   = (!force && gLastEntryBar != 0);
         gLastEntryBar = eBar;
         gStaleEntry   = 0;

         //--- forming-bar snapshot for the panel only
         CopyOne(hEma5F, 0, 0, gLiveEma5F);
         CopyOne(hEma5S, 0, 0, gLiveEma5S);
         CopyOne(hRsi5,  0, 0, gLiveRsi5);
        }
      else
         gStaleEntry++;
     }

   return(newEntryBar);
  }

bool CopyOne(const int handle, const int buffer, const int shift, double &out)
  {
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buffer, shift, 1, tmp) < 1)
      return(false);
   if(tmp[0] == EMPTY_VALUE || !MathIsValidNumber(tmp[0]))
      return(false);
   out = tmp[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| Direction resolution                                               |
//+------------------------------------------------------------------+
bool DesiredDirection(int &dir, bool &counter)
  {
   dir     = 0;
   counter = false;

   if(gCloud == CLOUD_ABOVE)
     {
      if(gDir5 < 0) { dir = -1; counter = true;  }   // counter-trend short
      else          { dir =  1; counter = false; }   // with-trend long
      return(true);
     }
   if(gCloud == CLOUD_BELOW)
     {
      if(gDir5 > 0) { dir =  1; counter = true;  }   // counter-trend long
      else          { dir = -1; counter = false; }   // with-trend short
      return(true);
     }
   return(false);   // inside the cloud, or unknown
  }

//--- Refresh the arm whenever the pullback condition holds. Expiry is
//    measured from the LAST moment it held, so a sustained bounce keeps the
//    window open and a brief dip does not close it.
void UpdateRsiArms()
  {
   if(gRsiNow <= 0.0)
      return;
   if(gRsiNow < RsiLevelMid) gRsiArmedBuy  = TimeCurrent();
   if(gRsiNow > RsiLevelMid) gRsiArmedSell = TimeCurrent();
  }

//--- seconds left on this side's arm, 0 if cold
int RsiArmLeft(const int dir)
  {
   datetime t = (dir > 0) ? gRsiArmedBuy : gRsiArmedSell;
   if(t == 0)
      return(0);
   int left = (RsiArmBars * 60) - (int)(TimeCurrent() - t);
   return(left > 0 ? left : 0);
  }

bool RsiArmed(const int dir)
  {
   return(RsiArmLeft(dir) > 0);
  }

bool RsiConfirms(const int dir)
  {
   if(dir == 0)
      return(false);

   switch(RsiMode)
     {
      case RSI_MODE_OFF:
         return(true);

      case RSI_MODE_ARM:
         //--- the cross ARMS; permission then stands for RsiArmBars minutes,
         //    so a wobble back across the mid no longer kills a live setup.
         return(RsiArmed(dir));

      case RSI_MODE_PULLBACK:
         // The limit rests at the 1M EMA50, so every entry is a pullback.
         // A BUY should be taken while short-term momentum is DEPRESSED
         // (RSI below mid) and a SELL while it is ELEVATED. This is the
         // only mode that agrees with the entry mechanism.
         return(dir > 0 ? (gRsiNow < RsiLevelMid) : (gRsiNow > RsiLevelMid));

      case RSI_MODE_VETO:   // do not enter an already-exhausted move
         return(dir > 0 ? (gRsiNow <= RsiOverbought) : (gRsiNow >= RsiOversold));

      case RSI_MODE_LEVEL:  // NOTE: fights the pullback, kept for A/B only
         return(dir > 0 ? (gRsiNow > RsiLevelMid) : (gRsiNow < RsiLevelMid));

      case RSI_MODE_SLOPE:  // see the warning at the top of this file
         return(dir > 0 ? (gRsiNow > gRsiPrev) : (gRsiNow < gRsiPrev));
     }
   return(true);
  }

string RsiModeName()
  {
   switch(RsiMode)
     {
      case RSI_MODE_OFF:      return("off");
      case RSI_MODE_ARM:      return("armed");
      case RSI_MODE_PULLBACK: return("pullback");
      case RSI_MODE_VETO:  return("veto");
      case RSI_MODE_LEVEL: return("level");
      case RSI_MODE_SLOPE: return("slope");
     }
   return("?");
  }

//--- can a limit at this level legally rest on the correct side? -------
bool LevelIsPlaceable(const int dir, const double level)
  {
   if(level <= 0.0)
      return(false);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minD = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * gPoint;
   if(minD <= 0.0)
      minD = gPoint;

   if(dir > 0) return(level <= ask - minD);   // buy limit must sit below market
   if(dir < 0) return(level >= bid + minD);   // sell limit must sit above market
   return(false);
  }

//--- pick the level the limit rests at: 1M EMA50 first, 5M EMA50 as fallback
//    Returns false when neither is on the correct side of the market.
bool ResolveEntryLevel(const int dir, double &level, int &src)
  {
   //--- v7.17: a level whose SLOT is already taken is not a candidate, so the
   //    cascade must step over it rather than stop there. Previously the
   //    resolver returned the first PLACEABLE level and ManageLimit then
   //    cancelled outright when that level's slot was occupied - killing a
   //    limit that was resting safely at a deeper, free level and re-placing
   //    it on the next tick. On 28 Aug that churned 26 placements against 23
   //    cancellations, 18 of them "slot already occupied: EMA5", including
   //    the same order re-sent thirteen times in ten minutes.
   if(LevelIsPlaceable(dir, gEma1S) && !SlotOccupied("EMA1"))
     {
      level = gEma1S;
      src   = 0;
      return(true);
     }

   //--- price has run past the 1M EMA50; each slower EMA50 sits further from
   //    price in a trend, so walk out to the next one that is still valid.
   if(UseFallbackLevel && LevelIsPlaceable(dir, gEma5S) && !SlotOccupied("EMA5"))
     {
      level = gEma5S;
      src   = 1;
      return(true);
     }

   if(UseFallback15M && LevelIsPlaceable(dir, gEma15S) && !SlotOccupied("EMA15"))
     {
      level = gEma15S;
      src   = 2;
      return(true);
     }

   level = gEma1S;
   src   = 0;
   return(false);
  }

//--- Full human-readable reason an open position exists, recovered from the
//    comment written at fill time. Comments are PREFIX-TYPE-DETAIL, e.g.
//    TREMA-TREND-15M or TREMA-RSIX-5M15M. Brokers sometimes rewrite or
//    truncate comments; when that happens this says so rather than guessing.
string PositionReason(const string comment)
  {
   if(StringFind(comment, "TRSI") >= 0)
      return("TrendRSI 1M");

   if(StringFind(comment, "XING") >= 0)
     {
      //--- v7.18: say WHICH kind of cross, not just that it was one
      string kind = (StringFind(comment, "-CTR-") >= 0) ? "CROSS-CTR" : "CROSS";
      if(StringFind(comment, "-15M") >= 0) return(kind + " 15M EMA50");
      if(StringFind(comment, "-5M")  >= 0) return(kind + " 5M EMA50");
      if(StringFind(comment, "-1M")  >= 0) return(kind + " 1M EMA50");
      return(kind + " EMA50");
     }

   if(StringFind(comment, "RSIX") >= 0)
     {
      if(StringFind(comment, "3TF")   >= 0) return("RSI-X 3TF washout");
      if(StringFind(comment, "5M15M") >= 0) return("RSI-X 5M+15M");
      if(StringFind(comment, "1M5M")  >= 0) return("RSI-X 1M+5M");
      return("RSI-X (?)");
     }

   string kind = "";
   if(StringFind(comment, "-TREND-") >= 0) kind = "TREND";
   else if(StringFind(comment, "-CTR-") >= 0) kind = "COUNTER";
   else if(StringFind(comment, "-RNG-") >= 0) kind = "RANGE";

   string lvl = "";
   if(StringFind(comment, "-15M") >= 0)      lvl = "15M EMA50";
   else if(StringFind(comment, "-5M") >= 0)  lvl = "5M EMA50";
   else if(StringFind(comment, "-1M") >= 0)  lvl = "1M EMA50";

   if(kind == "" && lvl == "")
      return("unknown (comment lost)");
   if(lvl == "")
      return(kind);
   return(kind + " " + lvl);
  }

//--- recover the entry level from a position comment written at fill time.
//    Comment format is PREFIX-TYPE-LEVEL, e.g. TREMA-TREND-15M. Some brokers
//    rewrite or truncate comments; when that happens this returns "?" rather
//    than guessing at a level that may be wrong.
string PositionLevelTag(const string comment)
  {
   if(StringFind(comment, "RSIX") >= 0)
     {
      if(StringFind(comment, "3TF")   >= 0) return("X3TF");
      if(StringFind(comment, "5M15M") >= 0) return("X5/15");
      if(StringFind(comment, "1M5M")  >= 0) return("X1/5");
      return("X?");
     }
   if(StringFind(comment, "-15M") >= 0) return("15M");
   if(StringFind(comment, "-5M")  >= 0) return("5M ");
   if(StringFind(comment, "-1M")  >= 0) return("1M ");
   return("?  ");
  }

string EntryLevelTag()
  {
   if(gEntryLevelSrc == 2) return("15M");
   if(gEntryLevelSrc == 1) return("5M");
   return("1M");
  }

//--- true when the EMAs on the ACTIVE level's timeframe oppose the trade
//    Note: on the 5M this is false by construction, because the 5M EMA
//    relationship is what selected the direction in the first place. So a
//    fallback entry never carries a retest requirement.
bool OpposingEntryEmas(const int dir, const int src)
  {
   double fast = gEma1F, slow = gEma1S;
   if(src == 1) { fast = gEma5F;  slow = gEma5S;  }
   if(src == 2) { fast = gEma15F; slow = gEma15S; }

   if(dir > 0) return(fast < slow);
   if(dir < 0) return(fast > slow);
   return(false);
  }

double RetestPips()
  {
   if(UseAtrRetest && gAtr1 > 0.0)
      return(MathMax(1.0, (gAtr1 * AtrRetestMult) / gPip));
   return(RetestDistancePips);
  }

//--- price reached the 1M EMA50 from the side the entry expects -------
bool TouchedEma50(const int dir)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir > 0) return(bid <= gEntryLevel);   // long: price dipped into the level
   if(dir < 0) return(ask >= gEntryLevel);   // short: price rallied into the level
   return(false);
  }

//--- distance travelled away from the level in the favourable direction
double PullAwayPips(const int dir)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir > 0) return(MathMax(0.0, (bid - gEntryLevel) / gPip));
   if(dir < 0) return(MathMax(0.0, (gEntryLevel - ask) / gPip));
   return(0.0);
  }

double CurrentPrice(const int dir)
  {
   return(dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
  }

double CurrentSpreadPips()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return((ask - bid) / gPip);
  }

//+------------------------------------------------------------------+
//| Gates                                                              |
//+------------------------------------------------------------------+
bool AccountAllowsTrading(string &why)
  {
   why = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     { why = "Algo Trading button is OFF (toolbar)";      return(false); }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     { why = "Algo Trading off in EA properties";         return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     { why = "broker disabled trading on this account";   return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     { why = "broker disabled EAs on this account";       return(false); }
   return(true);
  }

bool FreeMarginOK()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0) return(false);
   double fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return((fm / eq * 100.0) >= MinFreeMarginPercent);
  }

//+------------------------------------------------------------------+
//| BRAKE STATE PERSISTENCE                                            |
//|                                                                    |
//|  The streak lived only in RAM, so every OnInit reset it - a restart,|
//|  a re-attach, even OK in the Inputs dialog. On 2 Sep the BUY side   |
//|  lost at 00:00 and 01:47, the v7.26.4 attach at 04:47 wiped the     |
//|  count, and the brake then needed three MORE losses before engaging |
//|  at 11:35. Five losses to trigger a three-loss rule, because we     |
//|  deployed in the middle of it.                                     |
//|                                                                    |
//|  gLastLossDir had the same problem and it quietly broke the         |
//|  cooldown too: at 0 the direction test cannot short-circuit, so the |
//|  one-sided cooldown silently reverted to blocking both sides after  |
//|  every re-attach.                                                  |
//|                                                                    |
//|  Terminal GlobalVariables survive reloads and MT5 restarts. The     |
//|  instance lock, the stats epoch and the RSI-X episode already use   |
//|  them; this is the same pattern applied to state that never got it. |
//+------------------------------------------------------------------+
string BrakeGV(const string key)
  {
   return(StringFormat("TREMA_%s_%s_%d", key, _Symbol, (int)MagicNumber));
  }

void SaveBrakeState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;                        // a backtest must not inherit live state
   GlobalVariableSet(BrakeGV("STREAK"),  (double)gDirLossStreak);
   GlobalVariableSet(BrakeGV("SIDE"),    (double)gDirLossSide);
   GlobalVariableSet(BrakeGV("BRAKE"),   (double)gBrakeDir);
   GlobalVariableSet(BrakeGV("BCLOUD"),  (double)gBrakeCloudDir);
   GlobalVariableSet(BrakeGV("LOSSDIR"), (double)gLastLossDir);
   GlobalVariableSet(BrakeGV("DAY"),     (double)CurrentDayIndex());
  }

void LoadBrakeState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(!GlobalVariableCheck(BrakeGV("STREAK")))
      return;

   //--- a streak from a previous trading day describes a regime that has
   //    already ended. Bounded by the same 12:00 ET rollover the daily
   //    counters use, so the brake cannot outlive the day that earned it.
   long savedDay = (long)GlobalVariableGet(BrakeGV("DAY"));
   if(savedDay != CurrentDayIndex())
     {
      ClearBrakeState();
      Print("[TREMA] Brake state from a previous trading day discarded.");
      return;
     }

   gDirLossStreak = (int)GlobalVariableGet(BrakeGV("STREAK"));
   gDirLossSide   = (int)GlobalVariableGet(BrakeGV("SIDE"));
   gBrakeDir      = (int)GlobalVariableGet(BrakeGV("BRAKE"));
   gBrakeCloudDir = (int)GlobalVariableGet(BrakeGV("BCLOUD"));
   gLastLossDir   = (int)GlobalVariableGet(BrakeGV("LOSSDIR"));

   if(gDirLossStreak > 0 || gBrakeDir != 0)
      PrintFormat("[TREMA] Restored brake state across the re-attach: "
                  "%d %s loss(es) in a row%s.",
                  gDirLossStreak,
                  gDirLossSide > 0 ? "BUY" : (gDirLossSide < 0 ? "SELL" : ""),
                  gBrakeDir != 0
                     ? StringFormat(", %s BLOCKED pending a 15M flip",
                                    gBrakeDir > 0 ? "BUY" : "SELL")
                     : "");
   //--- UpdateDirBrake runs on the next tick and releases the brake by
   //    itself if the 15M moved while the EA was down, so a stale block
   //    cannot survive its own reason disappearing.
  }

void ClearBrakeState()
  {
   gDirLossStreak = 0; gDirLossSide = 0;
   gBrakeDir      = 0; gBrakeCloudDir = 0; gLastLossDir = 0;
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableDel(BrakeGV("STREAK"));  GlobalVariableDel(BrakeGV("SIDE"));
   GlobalVariableDel(BrakeGV("BRAKE"));   GlobalVariableDel(BrakeGV("BCLOUD"));
   GlobalVariableDel(BrakeGV("LOSSDIR")); GlobalVariableDel(BrakeGV("DAY"));
  }

//--- release the brake once the 15M permission has moved off the side we
//    were repeatedly wrong on. Releasing on a timer instead would just let
//    the same losing direction resume into the same conditions.
void UpdateDirBrake()
  {
   if(gBrakeDir == 0)
      return;
   int now = TDirFromCloud();
   if(now != 0 && now != gBrakeCloudDir)
     {
      PrintFormat("[TREMA] %s brake RELEASED - 15M permission flipped.",
                  gBrakeDir > 0 ? "BUY" : "SELL");
      gBrakeDir      = 0;
      gDirLossStreak = 0;
      gDirLossSide   = 0;
      SaveBrakeState();
     }
  }

int CooldownMinsLeft()
  {
   int left = (int)((gLastLossTime + CooldownMinutesAfterLoss * 60 - TimeCurrent()) / 60) + 1;
   return(left > 0 ? left : 0);
  }

bool DirectionBraked(const int dir)
  {
   return(gBrakeDir != 0 && dir == gBrakeDir);
  }

//--- one losing close, on one side. A win on that side clears the count:
//    the run of being wrong is what matters, not the running total.
void NoteClosedTrade(const int posDir, const double net)
  {
   if(MaxSameDirLosses <= 0 || posDir == 0)
      return;

   if(net > 0.0)
     {
      if(posDir == gDirLossSide)
        { gDirLossStreak = 0; gDirLossSide = 0; SaveBrakeState(); }
      return;
     }
   if(net == 0.0)
      return;

   gLastLossDir = posDir;

   if(posDir == gDirLossSide)
      gDirLossStreak++;
   else
     { gDirLossSide = posDir; gDirLossStreak = 1; }

   if(gDirLossStreak >= MaxSameDirLosses && gBrakeDir != posDir)
     {
      gBrakeDir      = posDir;
      gBrakeCloudDir = TDirFromCloud();
      PrintFormat("[TREMA] %s brake ENGAGED after %d losses in a row on that "
                  "side. No more %s entries until the 15M permission flips "
                  "(it is %d now).",
                  posDir > 0 ? "BUY" : "SELL", gDirLossStreak,
                  posDir > 0 ? "BUY" : "SELL", gBrakeCloudDir);
     }
   SaveBrakeState();
  }

//--- v7.26: the cooldown now asks WHICH side. Blocking both after a losing
//    BUY also blocked the SELL that the failure arguably argued for, which
//    is the opposite of the lesson. Repetition is the direction brake's job;
//    this one only cools the side that just lost.
bool InCooldown(const int dir)
  {
   if(dir != 0 && gLastLossDir != 0 && dir != gLastLossDir)
      return(false);
   if(CooldownMinutesAfterLoss <= 0 || gLastLossTime == 0)
      return(false);
   return(TimeCurrent() < gLastLossTime + CooldownMinutesAfterLoss * 60);
  }

bool IsFridayCutoff()
  {
   if(AllowFridayLate) return(false);
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return(dt.day_of_week == 5 && dt.hour >= FridayCutoffHour);
  }

//--- Is the current GMT time inside one of the manual blackout windows?
//    Independent of the MQL5 calendar entirely - this is the one that works.
bool InManualNewsWindow()
  {
   if(StringLen(ManualNewsWindows) == 0)
      return(false);

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int nowMin = dt.hour * 60 + dt.min;

   string parts[];
   int n = StringSplit(ManualNewsWindows, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string w = parts[i];
      StringTrimLeft(w);
      StringTrimRight(w);
      int dash = StringFind(w, "-");
      if(dash < 0) continue;

      string a = StringSubstr(w, 0, dash);
      string b = StringSubstr(w, dash + 1);
      int ca = StringFind(a, ":"), cb = StringFind(b, ":");
      if(ca < 0 || cb < 0) continue;

      int fromMin = (int)StringToInteger(StringSubstr(a, 0, ca)) * 60
                  + (int)StringToInteger(StringSubstr(a, ca + 1));
      int toMin   = (int)StringToInteger(StringSubstr(b, 0, cb)) * 60
                  + (int)StringToInteger(StringSubstr(b, cb + 1));

      if(fromMin <= toMin) { if(nowMin >= fromMin && nowMin <= toMin) return(true); }
      else                 { if(nowMin >= fromMin || nowMin <= toMin) return(true); }
     }
   return(false);
  }

//--- One-shot startup probe. The gate failing silently is what hid this for
//    four days, so make the terminal state visible instead of assumed.
void ProbeCalendar()
  {
   if(!LogNewsProbe || MQLInfoInteger(MQL_TESTER))
      return;

   datetime now = NewsTimeIsServer ? TimeTradeServer() : TimeGMT();
   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, now - 3600, now + 86400, NULL, "USD");
   int err = GetLastError();

   if(n <= 0)
     {
      PrintFormat("[TREMA] NEWS PROBE: CalendarValueHistory returned %d USD "
                  "events for the next 24h (error %d). The MQL5 calendar gate "
                  "is INOPERATIVE - only ManualNewsWindows will protect you.",
                  n, err);
      return;
     }

   //--- v7.25.1: a bare count could not be reconciled with anything. On
   //    1 Sep the probe reported 4 high-impact USD events while ForexFactory
   //    showed a single red folder, and there was no way to tell whether
   //    MQL5 grades events differently or the rolling 24h window was simply
   //    reaching into the following day. Name them and time them and the
   //    question answers itself - and the quiet windows stop being a
   //    surprise.
   int high = 0;
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      high++;
      datetime t = values[i].time;
      PrintFormat("[TREMA] NEWS PROBE   HIGH %s  %s  (blocks %s - %s)",
                  TimeToString(t, TIME_DATE | TIME_MINUTES), ev.name,
                  TimeToString(t - NewsMinutesBefore * 60, TIME_MINUTES),
                  TimeToString(t + NewsMinutesAfter  * 60, TIME_MINUTES));
     }
   PrintFormat("[TREMA] NEWS PROBE: %d USD events in the next 24h, %d of them "
               "high-impact (listed above, %s). Calendar gate is live.",
               n, high, NewsTimeIsServer ? "server time" : "GMT");
  }

bool NewsBlocked()
  {
   if(!BlockNewsWindow)
      return(false);

   //--- manual window first: it cannot silently fail
   if(InManualNewsWindow())
      return(true);

   if(!gCalendarOK)
      return(false);

   //--- FIX 8: some brokers report calendar times in server time, not GMT.
   //    A wrong assumption here blocks the wrong window entirely.
   datetime now  = NewsTimeIsServer ? TimeTradeServer() : TimeGMT();
   datetime from = now - NewsMinutesAfter  * 60;
   datetime to   = now + NewsMinutesBefore * 60;

   //--- v7.15: this ran on EVERY tick - a calendar query plus one lookup per
   //    returned event, several times a second. Cached for 30s; a news window
   //    is 15 minutes wide, so half a minute of staleness cannot matter.
   uint nowNews = GetTickCount();
   if(gNewsCheckMs != 0 && (nowNews - gNewsCheckMs) < 30000)
      return(gNewsBlockedCached);
   gNewsCheckMs = nowNews;

   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, from, to, NULL, "USD");
   if(n <= 0)
     {
      gNewsBlockedCached = false;
      return(false);
     }

   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
        {
         gNewsBlockedCached = true;
         return(true);
        }
     }
   gNewsBlockedCached = false;
   return(false);
  }

//+------------------------------------------------------------------+
//| Position / order helpers                                           |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      c++;
     }
   return(c);
  }

bool HasOpposingPosition(const int dir)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type == POSITION_TYPE_SELL) return(true);
      if(dir < 0 && type == POSITION_TYPE_BUY)  return(true);
     }
   return(false);
  }

void CloseAllPositions(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      if(gTrade.PositionClose(t))
         PrintFormat("[TREMA] Closed #%I64u: %s", t, why);
      else
         PrintFormat("[TREMA] Close #%I64u failed (%d): %s",
                     t, gTrade.ResultRetcode(), gTrade.ResultComment());
     }
  }

//--- FIX 2: a resting limit is a future position, so it must count against
//    MaxConcurrentPositions. Without this, positions + a resting limit could
//    exceed the cap the moment that limit filled.
//+------------------------------------------------------------------+
//| TRIGGER SLOTS                                                      |
//|                                                                    |
//|  Each source may hold at most one open position. A second touch of |
//|  the 1M EMA50 while a 1M entry is already running does NOT stack;   |
//|  a touch of the 5M or 15M level still can, because those are        |
//|  different slots. Same for the RSI extreme and the trend-RSI.       |
//|                                                                    |
//|  The 1M slot deliberately covers BOTH the limit and the cross entry |
//|  at that level - they are two ways of trading the same EMA, so      |
//|  letting them stack would be the doubling-up this rule prevents.    |
//+------------------------------------------------------------------+
string TriggerSlot(const string comment)
  {
   if(StringFind(comment, "RSIX") >= 0) return("RSIX");
   if(StringFind(comment, "TRSI") >= 0) return("TRSI");
   if(StringFind(comment, "-15M") >= 0) return("EMA15");
   if(StringFind(comment, "-5M")  >= 0) return("EMA5");
   if(StringFind(comment, "-1M")  >= 0) return("EMA1");
   return("OTHER");
  }

//--- slot name for an EMA level index (0 = 1M, 1 = 5M, 2 = 15M)
string SlotForLevel(const int src)
  {
   if(src == 2) return("EMA15");
   if(src == 1) return("EMA5");
   return("EMA1");
  }

bool SlotOccupied(const string slot)
  {
   if(!OnePositionPerTrigger)
      return(false);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      if(TriggerSlot(PositionGetString(POSITION_COMMENT)) == slot)
         return(true);
     }
   return(false);
  }

int CountOurPendings()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      c++;
     }
   return(c);
  }

//--- Cancel any pending of ours the EA is not tracking. These can only exist
//    through a bug or an interrupted session, and an untracked order is one
//    nothing will ever cancel or re-price.
void CancelOrphanPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      if(t == gPendingTicket) continue;
      if(gTrade.OrderDelete(t))
         PrintFormat("[TREMA] Cancelled ORPHAN pending #%I64u (untracked).", t);
     }
  }

bool PendingAlive(const ulong ticket)
  {
   if(ticket == 0) return(false);
   return(OrderSelect(ticket));
  }

double OrderPriceOf(const ulong ticket)
  {
   if(!OrderSelect(ticket)) return(0.0);
   return(OrderGetDouble(ORDER_PRICE_OPEN));
  }

void CancelPending(const string why)
  {
   if(gPendingTicket == 0)
      return;
   if(PendingAlive(gPendingTicket))
     {
      if(gTrade.OrderDelete(gPendingTicket))
        {
         PrintFormat("[TREMA] Limit #%I64u cancelled: %s", gPendingTicket, why);
        }
      else
        {
         //--- v7.15: keep tracking it. Zeroing the ticket on a failed delete
         //    orphaned a LIVE limit - nothing re-priced it, nothing cancelled
         //    it, and ManageLimit was then free to place a second one.
         PrintFormat("[TREMA] Limit #%I64u delete FAILED (%d): %s - still "
                     "tracked, will retry.", gPendingTicket,
                     gTrade.ResultRetcode(), gTrade.ResultComment());
         return;
        }
     }
   gPendingTicket = 0;
   gPendingBars   = 0;
  }

//--- reattach to a limit left behind by a restart / recompile ---------
void AdoptExistingPending()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      gPendingTicket = t;
      gPendingBars   = 0;
      PrintFormat("[TREMA] Adopted existing pending order #%I64u.", t);
      return;
     }
  }

//--- FIX 3 + 4.  Two jobs, both about the stop actually being right:
//      * a position with NO stop is repaired at any age. That is the
//        catastrophic case - an unstopped gold position on a live account.
//      * a position whose stop is the wrong DISTANCE is repaired only within
//        SyncStopsSeconds of the fill. That catches market-order slippage
//        (the extreme trigger sends market orders and fills in fast
//        conditions) without the EA fighting a stop you moved by hand later.
//+------------------------------------------------------------------+
//| GEOMETRY MEMO                                                      |
//|                                                                    |
//|  SyncPositionStops re-derived a position's intended SL/TP from its  |
//|  comment tag. That works for fixed-pip trades and fails for barrier |
//|  ones, whose target came from live structure that has since moved.  |
//|  The v7.19 workaround - "keep whatever TP the order carries" - then  |
//|  blocked the re-anchor even when the barrier never bound.           |
//|                                                                    |
//|  31 Aug, RSI-X BUY: expected entry 4416.683, actual fill 4417.171.  |
//|  The stop followed the fill to 4408.171, a correct 900 pips. The    |
//|  target stayed at 4431.683 - still measured from the entry that was |
//|  never used - leaving 1451.2 pips instead of 1500. The slippage came|
//|  out of the reward and left the risk untouched.                     |
//|                                                                    |
//|  Remember what each ticket was MEANT to have at send time rather    |
//|  than trying to reconstruct it afterwards.                          |
//+------------------------------------------------------------------+
#define GEOM_MEMO 32
struct GeomMemo
  {
   ulong  ticket;
   double slPips;
   double tpPips;
  };
GeomMemo gGeom[GEOM_MEMO];
int      gGeomNext = 0;

void RememberGeometry(const ulong ticket, const double slPips, const double tpPips)
  {
   if(ticket == 0)
      return;
   for(int i = 0; i < GEOM_MEMO; i++)          // refresh in place if known
      if(gGeom[i].ticket == ticket)
        { gGeom[i].slPips = slPips; gGeom[i].tpPips = tpPips; return; }
   gGeom[gGeomNext].ticket = ticket;
   gGeom[gGeomNext].slPips = slPips;
   gGeom[gGeomNext].tpPips = tpPips;
   gGeomNext = (gGeomNext + 1) % GEOM_MEMO;
  }

bool LookupGeometry(const ulong ticket, double &slPips, double &tpPips)
  {
   if(ticket == 0)
      return(false);
   for(int i = 0; i < GEOM_MEMO; i++)
      if(gGeom[i].ticket == ticket)
        { slPips = gGeom[i].slPips; tpPips = gGeom[i].tpPips; return(true); }
   return(false);
  }

//--- round a price onto the broker's tick grid. NormalizeDouble alone only
//    fixes the number of decimals; a symbol whose tick size is coarser than
//    one digit step still receives a price it has to round itself.
double SnapToTick(const double price)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0)
      return(NormalizeDouble(price, gDigits));
   return(NormalizeDouble(MathRound(price / ts) * ts, gDigits));
  }

void SyncPositionStops(const bool force = false)
  {
   if(!EnforcePositionStops)
      return;

   //--- at most once every 2s, and never more than 5 repair attempts before
   //    the next bar resets the budget. A stop the broker will not accept
   //    must not be retried indefinitely at tick rate.
   //--- v7.15: the v7.13 budget was wrong in three ways - it counted
   //    SUCCESSES, it was shared across positions so one stubborn ticket
   //    starved the others, and it only reset on a new 1M bar (never, with
   //    the market closed). Now: failures only, and time-based reset.
   uint nowSync = GetTickCount();
   //--- v7.16: force=true for the call made from OnTradeTransaction on a
   //    fill. Its whole purpose is to re-anchor SL/TP to the price actually
   //    received, and the 2s throttle was silently suppressing exactly that.
   if(!force && gLastStopSyncMs != 0 && (nowSync - gLastStopSyncMs) < 2000)
      return;
   gLastStopSyncMs = nowSync;

   if(gStopFixFails >= 10 && (nowSync - gStopFixWindowMs) < 60000)
      return;                       // broker keeps refusing; back off a minute
   if((nowSync - gStopFixWindowMs) >= 60000)
     {
      gStopFixWindowMs = nowSync;
      gStopFixFails    = 0;
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      long     type  = PositionGetInteger(POSITION_TYPE);
      double   open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double   curSL = PositionGetDouble(POSITION_SL);
      double   curTP = PositionGetDouble(POSITION_TP);
      datetime opened= (datetime)PositionGetInteger(POSITION_TIME);
      string   com   = PositionGetString(POSITION_COMMENT);
      if(open <= 0.0) continue;

      bool   isX  = (StringFind(com, "RSIX") >= 0);
      bool   isT  = (StringFind(com, "TRSI") >= 0);
      bool   isC  = (StringFind(com, "XING") >= 0);
      //--- v7.18: "-CTR-" now appears in cross tags too (TREMA-XING-CTR-5M),
      //    so counter must be tested BEFORE the plain cross case or a
      //    counter-trend cross would be repaired to the wrong geometry.
      bool   isCtr = (StringFind(com, "-CTR-") >= 0);
      double slP, tpP;
      if(isX)             { slP = SLPips;  tpP = TPPips;  }
      else if(isT)        { slP = SLPips;    tpP = TPPips;      }
      else if(isCtr)      { slP = CounterSLPips;     tpP = TakeProfitCounterPips; }
      else if(isC)        { slP = SLPips;       tpP = TPPips;         }
      else                { slP = SLPips;      tpP = TPPips; }

      //--- v7.24: prefer the geometry this ticket was actually given. The
      //    tag only names a trigger; two RSI-X trades can carry different
      //    targets because the barrier bound for one and not the other.
      //    POSITION_IDENTIFIER is the opening order ticket for both market
      //    and pending entries, which is the key RememberGeometry stored.
      bool known = LookupGeometry((ulong)PositionGetInteger(POSITION_IDENTIFIER),
                                  slP, tpP);

      double wantSL, wantTP;
      if(type == POSITION_TYPE_BUY)
        {
         wantSL = NormalizeDouble(open - slP * gPip, gDigits);
         wantTP = NormalizeDouble(open + tpP * gPip, gDigits);
        }
      else
        {
         wantSL = NormalizeDouble(open + slP * gPip, gDigits);
         wantTP = NormalizeDouble(open - tpP * gPip, gDigits);
        }

      bool missing = (curSL <= 0.0);
      bool young   = (TimeCurrent() - opened) <= SyncStopsSeconds;
      double tol   = gPip;
      //--- v7.19: a counter-trend TP is computed from live structure at
      //    entry time, so it cannot be recomputed here from a fixed pip
      //    count. Keep whatever the order actually carries and only repair
      //    the stop; otherwise the sweep would drag the target back out to
      //    the fixed distance the barrier rule deliberately shortened.
      //--- v7.23.1: this override has to happen BEFORE the drift test, not
      //    after it. Sitting after, the test compared a barrier TP against
      //    the fixed-pip TP it was deliberately shortened from, called the
      //    difference drift, and sent a "correction" that the override had
      //    already turned back into the current value. The broker answered
      //    10025 No changes and the whole thing repeated every 2 seconds:
      //    33 times on 28 Aug, 67 on 31 Aug, on RSI-X and counter positions
      //    only - the two that use barrier targets.
      //--- v7.24: only needed when the intent was NOT recorded - an EA
      //    restart, or a ticket aged out of the memo. With a known target
      //    there is nothing to guess and the re-anchor must be allowed to
      //    run, which is exactly what this guard used to prevent.
      if(!known)
        {
         if(isCtr && CounterUseBarrierTP && curTP > 0.0)
            wantTP = curTP;
         if(isX && RsiXUseBarrierTP && curTP > 0.0)
            wantTP = curTP;   // computed from live structure at entry
        }

      bool drifted = young && (MathAbs(curSL - wantSL) > tol ||
                               curTP <= 0.0 ||
                               MathAbs(curTP - wantTP) > tol);

      if(!missing && !drifted)
         continue;

      //--- v7.23: snap to the broker's own tick grid, not just the digit
      //    count. Asking for a price the broker will round back onto the
      //    value it already holds is how a repair turns into a no-op that
      //    still costs a retry.
      wantSL = SnapToTick(wantSL);
      wantTP = SnapToTick(wantTP);

      if(gTrade.PositionModify(t, wantSL, wantTP))
        {
         if(missing)
            PrintFormat("[TREMA] WARNING position #%I64u had NO stop-loss. "
                        "Attached SL %.2f TP %.2f from open %.2f.",
                        t, wantSL, wantTP, open);
         else
            PrintFormat("[TREMA] Corrected slipped stops on #%I64u: "
                        "SL %.2f -> %.2f, TP %.2f -> %.2f (open %.2f).",
                        t, curSL, wantSL, curTP, wantTP, open);
        }
      //--- v7.23: 10025 NO_CHANGES is the broker saying "already set to
      //    that". That is the outcome this function wants, not a failure.
      //    Counting it as one let a non-problem burn the 10-attempt budget
      //    and leave a genuinely unprotected position unrepaired for the
      //    rest of the minute - the safety net switching itself off at the
      //    one moment it is needed.
      else if(gTrade.ResultRetcode() == TRADE_RETCODE_NO_CHANGES)
        {
         if(missing)
            PrintFormat("[TREMA] position #%I64u reports no SL locally but the "
                        "broker says stops are already correct - not retrying.", t);
        }
      else
        {
         gStopFixFails++;          // only genuine FAILURES consume the budget
         PrintFormat("[TREMA] FAILED to set stops on #%I64u (%d): %s",
                     t, gTrade.ResultRetcode(), gTrade.ResultComment());
        }
     }
  }

void ResetSetup()
  {
   gState        = SS_IDLE;
   gSetupDir     = 0;
   gSetupCounter = false;
   gStateBars    = 0;
  }

//+------------------------------------------------------------------+
//| Daily bookkeeping                                                  |
//+------------------------------------------------------------------+
//--- The trading day rolls over at DayResetHourET in Eastern time, NOT at
//    broker midnight. Returns the index of the ET trading day containing
//    `now`, so a change in the index means a new day has started.
long CurrentDayIndex()
  {
   datetime etNow = TimeGMT() + (datetime)(ETOffsetHours * 3600);
   return((long)MathFloor((double)(etNow - DayResetHourET * 3600) / 86400.0));
  }

//--- server-time timestamp of the boundary that opened the current day
datetime DayStartServerTime()
  {
   long   idx        = CurrentDayIndex();
   double boundaryET = (double)idx * 86400.0 + DayResetHourET * 3600.0;
   datetime boundaryGMT = (datetime)(boundaryET - ETOffsetHours * 3600);
   //--- shift into the broker server clock, which is what HistorySelect uses
   //--- v7.16: TimeCurrent is the server time of the LAST QUOTE, so it is
   //    stale by the whole weekend when attaching with the market closed -
   //    which shifted the day boundary by up to 48h. TimeTradeServer keeps
   //    advancing on the terminal clock.
   int serverGmtOffset = (int)(TimeTradeServer() - TimeGMT());
   return(boundaryGMT + serverGmtOffset);
  }

bool IsNewDay()
  {
   return(CurrentDayIndex() != gDayIndex);
  }

void ResetDayState(const bool firstRun)
  {
   gDayIndex        = CurrentDayIndex();
   gDayStart        = DayStartServerTime();
   gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gDayTrades       = 0;
   gDayPL           = 0.0;
   gLastLossTime    = 0;
   //--- v7.27: the loss streak belongs to the day that earned it. Startup
   //    checks this too, but a session that simply runs through the
   //    rollover would otherwise carry yesterday's brake into today.
   if(!firstRun)
     {
      ClearBrakeState();
      PrintFormat("[TREMA] New trading day (%02d:00 ET rollover). Counters reset, "
                  "daily halt lifted, brake cleared.", DayResetHourET);
     }
  }

//--- recompute today from deal history so restarts do not lose state ----
void RefreshDailyStats()
  {
   //--- Select FIRST, zero SECOND. Zeroing before the guard meant one failed
   //    HistorySelect reported a flat day: the -6% daily halt and the
   //    post-loss cooldown both silently lifted while real losses stood.
   //    On failure the previous figures are kept - stale is far safer than
   //    a fabricated zero on a risk control.
   if(!HistorySelect(gDayStart, TimeCurrent() + 60))
     {
      PrintFormat("[TREMA] HistorySelect failed - keeping previous daily "
                  "figures (P/L %.2f, %d trades). Risk gates stay armed.",
                  gDayPL, gDayTrades);
      return;
     }

   gDayPL        = 0.0;
   gDayTrades    = 0;
   gDayWins      = 0;
   gDayLosses    = 0;
   gLastLossTime = 0;
   gLastLossDir  = 0;      // rebuilt below from the same deal as the time

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC)  != MagicNumber) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL)  != _Symbol)     continue;

      gDayPL += HistoryDealGetDouble(t, DEAL_PROFIT)
              + HistoryDealGetDouble(t, DEAL_SWAP)
              + HistoryDealGetDouble(t, DEAL_COMMISSION);

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
         gDayTrades++;

      if(entry == DEAL_ENTRY_OUT)
        {
         double net = HistoryDealGetDouble(t, DEAL_PROFIT)
                    + HistoryDealGetDouble(t, DEAL_SWAP)
                    + HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(net > 0.0)      gDayWins++;
         else if(net < 0.0) gDayLosses++;

         if(net < 0.0)
           {
            datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
            if(dt > gLastLossTime)
              {
               gLastLossTime = dt;
               //--- v7.27.1: the direction sat in this same deal and went
               //    unread, so gLastLossDir stayed 0 after every restart
               //    while gLastLossTime was correctly rebuilt. At 0 the
               //    direction test in InCooldown cannot short-circuit, so
               //    the one-sided cooldown silently reverted to blocking
               //    BOTH sides. On 2 Sep a BUY loss at 11:35 cooled the
               //    SELL side until 12:35 - the with-trend side, in a
               //    downtrend, on a day when every SELL had won.
               //    v7.27 persisted the value instead, which only helps
               //    from the next loss onward and not on a first run.
               //    History is authoritative and available immediately.
               //    An OUT deal is the opposite side to the position it
               //    closed: a SELL deal closes a BUY.
               gLastLossDir = (HistoryDealGetInteger(t, DEAL_TYPE) == DEAL_TYPE_BUY)
                              ? -1 : 1;
              }
           }
        }
     }

   //--- FIX 9: derive the day-start balance instead of capturing it at attach.
   //    Capturing it meant every re-attach re-baselined the daily loss stop
   //    to the already-reduced balance, so the halt never measured the day.
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > 0.0)
      gDayStartBalance = bal - gDayPL;
  }

//--- Signature of every input that changes how the EA TRADES. Panel colours,
//    alert switches, heartbeat settings and risk sizing are deliberately
//    excluded: none of them alters whether a trade wins or loses.
double ConfigSignature()
  {
   string sig = StringFormat(
      "%s|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.1f|%.0f|%.1f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%d|%.1f|%.1f|%.1f|%d|"
      "%d|%.1f|%.1f|%.1f|%.1f|%d|%d|%d|%.1f|%.1f|%d|%d|%d|%.0f|%.0f|%d|%d|%d|"
      "%d|%d|%d|%d|%d|%d|%d",
      STRATEGY_REV,
      SLPips, TPPips, TakeProfitCounterPips, CounterSLPips,
      CounterUseBarrierTP ? 1.0 : 0.0, CounterBarrierBuffer, MinCounterRR,
      RsiXUseBarrierTP ? 1.0 : 0.0, MinRsiXRR,
      SLPips, TPPips, SLPips, TPPips,
      SLPips, TPPips,
      (int)RsiMode, RsiOverbought, RsiOversold, RsiLevelMid,
      (int)EntryStyle,
      EnableRsiExtreme ? 1 : 0, RsiXFastLevel, RsiXSlowLevel,
      RsiXSlow15Level, RsiX3TFLevel, (int)RsiXResetLevel,
      RsiXWaitForTurn ? 1 : 0, RsiXArmExpiryBars,
      TrendRsiLevel, TrendRsiResetLevel, TrendRsiExpiryBars,
      EnableTrendRsi ? 1 : 0, TrendRsiRequire1M ? 1 : 0,
      RetestDistancePips, RearmDistancePips, UseRetestGate ? 1 : 0,
      OnePositionPerTrigger ? 1 : 0, MaxConcurrentPositions,
      EmaFastPeriod, EmaSlowPeriod, RsiPeriod,
      IchiTenkan, IchiKijun, IchiSenkou,
      (UseFallbackLevel ? 1 : 0) + (UseFallback15M ? 2 : 0));

   long h = 5381;
   int  n = StringLen(sig);
   for(int i = 0; i < n; i++)
      h = ((h * 33) + StringGetCharacter(sig, i)) % 2147483647;
   return((double)h);
  }

//--- Compare against the stored signature; a difference starts a new epoch.
void SyncStatsEpoch()
  {
   string kCfg   = StringFormat("TREMA_CFG_%s_%d",   _Symbol, (int)MagicNumber);
   string kEpoch = StringFormat("TREMA_EPOCH_%s_%d", _Symbol, (int)MagicNumber);

   double nowSig = ConfigSignature();
   double oldSig = GlobalVariableCheck(kCfg) ? GlobalVariableGet(kCfg) : -1.0;

   if(oldSig != nowSig || !GlobalVariableCheck(kEpoch))
     {
      gStatsEpoch = TimeCurrent();
      GlobalVariableSet(kCfg,   nowSig);
      GlobalVariableSet(kEpoch, (double)gStatsEpoch);
      PrintFormat("[TREMA] Strategy configuration changed - win-rate statistics "
                  "RESET. Counting from %s. Previous results described a setup "
                  "that is no longer running.",
                  TimeToString(gStatsEpoch, TIME_DATE | TIME_MINUTES));
     }
   else
     {
      gStatsEpoch = (datetime)GlobalVariableGet(kEpoch);
      PrintFormat("[TREMA] Strategy configuration unchanged - win rate continues "
                  "from %s.", TimeToString(gStatsEpoch, TIME_DATE | TIME_MINUTES));
     }
  }

//--- Full-history win/loss tally. Deliberately NOT called per tick: it walks
//    every deal on the account. Init and each close is enough, since nothing
//    else can change it.
void RefreshAllTimeStats()
  {
   gAllWins    = 0;
   gAllLosses  = 0;
   gAllStreak  = 0;
   gAllBestWin = 0;
   gAllWorstLoss = 0;
   if(!HistorySelect(gStatsEpoch, TimeCurrent() + 60))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)     continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      double net = HistoryDealGetDouble(t, DEAL_PROFIT)
                 + HistoryDealGetDouble(t, DEAL_SWAP)
                 + HistoryDealGetDouble(t, DEAL_COMMISSION);
      //--- streaks depend on ORDER, unlike the counts above. HistorySelect
      //    over a time range returns deals chronologically, which is the
      //    same assumption the rest of this loop already relies on.
      if(net > 0.0)
        {
         gAllWins++;
         gAllStreak = (gAllStreak > 0) ? gAllStreak + 1 : 1;
         if(gAllStreak > gAllBestWin) gAllBestWin = gAllStreak;
        }
      else
         if(net < 0.0)
           {
            gAllLosses++;
            gAllStreak = (gAllStreak < 0) ? gAllStreak - 1 : -1;
            if(gAllStreak < gAllWorstLoss) gAllWorstLoss = gAllStreak;
           }
     }
  }

string WinRateText(const int wins, const int losses)
  {
   int n = wins + losses;
   if(n <= 0)
      return("0/0  --");
   return(StringFormat("%d/%d  %.0f%%", wins, n, 100.0 * wins / n));
  }

//+------------------------------------------------------------------+
//| Trade transactions - fills, closes, re-arm trigger                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)     return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double vol   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   if(entry == DEAL_ENTRY_IN)
     {
      //--- CRITICAL: only clear the tracked pending when the deal actually
      //    came from THAT order. The RSI extreme sends a MARKET order, and
      //    blindly zeroing the ticket here orphaned any resting trend limit:
      //    CancelPending() then became a no-op and ManageLimit placed a
      //    second limit, letting the position cap be exceeded.
      ulong dealOrder = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      if(gPendingTicket != 0 && dealOrder == gPendingTicket)
        {
         gPendingTicket = 0;
         gPendingBars   = 0;
         gRearmPending  = true;   // trend entry: enforce the re-arm distance
         ResetSetup();
        }

      //--- correct SL/TP against the price we actually got, not the price we
      //    read before sending. Market fills slip, and they slip most in the
      //    fast conditions the extreme trigger exists for.
      SyncPositionStops(true);   // force: never throttle a fill correction

      //--- a close may have just changed the day P/L; do not wait 15s for it
      gLastStatsMs = 0;

      long dtype = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      string dcom = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      string msg = StringFormat("TREMA FILL %s %.2f lots @ %.2f  [%s]",
                                dtype == DEAL_TYPE_BUY ? "BUY" : "SELL", vol, price,
                                PositionReason(dcom));
      Print("[TREMA] ", msg);
      if(AlertOnFill) Alert(msg);
      if(EnablePush)  SendNotification(msg);
     }
   else
      if(entry == DEAL_ENTRY_OUT)
        {
         double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
         if(net < 0.0)
            gLastLossTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
         //--- an OUT deal is the OPPOSITE side to the position it closed:
         //    a SELL position is closed by a BUY deal.
         NoteClosedTrade((HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY)
                         ? -1 : 1, net);
         gLastStatsMs = 0;   // FIX 6: daily halt must not run up to 15s stale
         RefreshAllTimeStats();

         string msg = StringFormat("TREMA CLOSE %.2f lots @ %.2f  P/L %.2f",
                                   vol, price, net);
         Print("[TREMA] ", msg);
         if(AlertOnClose) Alert(msg);
         if(EnablePush)   SendNotification(msg);
        }
  }

//+------------------------------------------------------------------+
//| Status helper                                                      |
//+------------------------------------------------------------------+
void SetStatus(const string s, const string detail, const color clr)
  {
   if(VerboseLog && (s != gStatus || detail != gStatusDetail))
      PrintFormat("[TREMA] %s - %s", s, detail);
   gStatus       = s;
   gStatusDetail = detail;
   gStatusColor  = clr;
  }

//+------------------------------------------------------------------+
//| PANEL                                                              |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   if(!ShowPanel)
     {
      //--- v7.16: only sweep once. This enumerated the whole chart object
      //    list on every redraw even though nothing can recreate the rows
      //    while the flag is off.
      if(gPanelRowsDrawn != 0)
        {
         ObjectsDeleteAll(0, PFX + "P");
         gPanelRowsDrawn = 0;
        }
      return;
     }

   const int rowH  = PanelFontSize + 7;
   int openNow = CountPositions();
   //--- negative size = tenths of a point, matching OBJPROP_FONTSIZE, so
   //    TextGetSize reports the same metrics the labels will be drawn with.
   TextSetFont("Consolas", -PanelFontSize * 10);
   gPanelMaxW = 0;

   //--- background ------------------------------------------------------
   string bg = PFX + "Pbg";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       C'60,66,80');
      ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PanelX - 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PanelY - 6);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,   PanelBgColor);
   //--- XSIZE and YSIZE are both set at the end of this function, once the
   //    real row count and the real text extents are known. Guessing either
   //    up front left the box the wrong size.

   int r = 0;

   //--- title -----------------------------------------------------------
   bool isReal = ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)
                  == ACCOUNT_TRADE_MODE_REAL);
   uint nowDrawMs = GetTickCount();
   int  upSecs    = (gInitMs > 0) ? (int)((nowDrawMs - gInitMs) / 1000) : 0;
   int  drawAgo   = (gLastDrawMs > 0) ? (int)((nowDrawMs - gLastDrawMs) / 1000) : 0;
   gLastDrawMs    = nowDrawMs;

   int tickAge = (gLastTickMs > 0)
                 ? (int)((nowDrawMs - gLastTickMs) / 1000) : 999;
   PanelRow(r++, StringFormat("TREND EA  -  %s", _Symbol),
            StringFormat("%s   tick %ds", isReal ? "REAL" : "demo", tickAge),
            clrGold, tickAge > 30 ? clrRed : (isReal ? clrOrange : clrLime));
   PanelRow(r++, "------------------------------------", "", C'70,76,90', C'70,76,90');

   //--- trend block -------------------------------------------------------
   string cloudTxt; color cloudClr;
   switch(gCloud)
     {
      case CLOUD_ABOVE:  cloudTxt = "UP   above cloud"; cloudClr = clrLime;     break;
      case CLOUD_BELOW:  cloudTxt = "DOWN below cloud"; cloudClr = clrTomato;   break;
      case CLOUD_INSIDE: cloudTxt = "NONE inside cloud";cloudClr = clrGray;     break;
      default:           cloudTxt = "loading...";       cloudClr = clrGray;     break;
     }
   //--- print the real numbers the EA is using. Comparing the panel against a
   //    chart carrying different indicators (SMA 9/50 vs the EA's EMA 20/50)
   //    produced repeated false alarms; numbers end that argument.
   PanelRow(r++, "15M CLOUD",
            StringFormat("%s  %s/%s", cloudTxt,
                         DoubleToString(MathMin(gSenkouA, gSenkouB), 2),
                         DoubleToString(MathMax(gSenkouA, gSenkouB), 2)),
            PanelTextColor, cloudClr);

   string ema5Txt = StringFormat("%s / %s  %s",
                                 DoubleToString(gEma5F, 2), DoubleToString(gEma5S, 2),
                                 gDir5 > 0 ? "bull" : (gDir5 < 0 ? "bear" : "flat"));
   PanelRow(r++, "5M EMA20/50", ema5Txt, PanelTextColor,
            gDir5 > 0 ? clrLime : (gDir5 < 0 ? clrTomato : clrGray));

   string ema1Txt = StringFormat("%s / %s  %s",
                                 DoubleToString(gEma1F, 2), DoubleToString(gEma1S, 2),
                                 gEma1F > gEma1S ? "bull" : (gEma1F < gEma1S ? "bear" : "flat"));
   PanelRow(r++, "1M EMA20/50", ema1Txt, PanelTextColor,
            gEma1F > gEma1S ? clrLime : (gEma1F < gEma1S ? clrTomato : clrGray));

   bool rsiUp = (gRsiNow > gRsiPrev);
   int  pdir = 0; bool pcounter = false;
   bool pHaveDir = DesiredDirection(pdir, pcounter);
   bool rsiOK    = pHaveDir ? RsiConfirms(pdir) : true;

   //--- in ARM mode show how much of the window is left, so a resting limit
   //    that is about to lose its permission is visible before it happens
   string rsiTxt = StringFormat("%.1f  %s   %s: %s",
                                gRsiNow, rsiUp ? "rising" : "falling",
                                RsiModeName(), rsiOK ? "ok" : "BLOCK");
   if(RsiMode == RSI_MODE_ARM)
     {
      int bLeft = RsiArmLeft(1), sLeft = RsiArmLeft(-1);
      rsiTxt = StringFormat("%.1f  %s   arm  BUY %s / SELL %s",
                            gRsiNow, rsiUp ? "rising" : "falling",
                            bLeft > 0 ? StringFormat("%d:%02d", bLeft / 60, bLeft % 60) : "cold",
                            sLeft > 0 ? StringFormat("%d:%02d", sLeft / 60, sLeft % 60) : "cold");
     }
   PanelRow(r++, "RSI 5M", rsiTxt, PanelTextColor, rsiOK ? clrLime : clrTomato);

   if(EnableRsiExtreme)
     {
      string xTxt = gXState;
      color  xClr = gXArmed ? clrGold : (gXNeedsReset ? clrSilver : clrSilver);
      if(gXOpposeDir != 0)
         xTxt += StringFormat("  |  %s %s",
                              gXOpposeDir > 0 ? "BUY" : "SELL",
                              gXHardBlock ? "BLOCKED" : "15M only");
      PanelRow(r++, "RSI-X", xTxt, PanelTextColor, xClr);
     }

   if(EnableTrendRsi)
      PanelRow(r++, "TRSI", gTState, PanelTextColor,
               gTArmed ? clrGold : clrSilver);

   PanelRow(r++, "------------------------------------", "", C'70,76,90', C'70,76,90');

   //--- setup block ---------------------------------------------------------
   int  dir = 0; bool counter = false;
   bool haveDir = DesiredDirection(dir, counter);
   string modeTxt = !haveDir ? "none"
                    : StringFormat("%s (%s)", dir > 0 ? "BUY" : "SELL",
                                   counter ? "COUNTER" : "TREND");
   string tpTxt = !haveDir ? "-"
                  : StringFormat("TP %.0f", counter ? TakeProfitCounterPips
                                                    : TPPips);
   PanelRow(r++, "MODE", modeTxt + "   " + tpTxt, PanelTextColor,
            !haveDir ? clrGray : (dir > 0 ? clrLime : clrTomato));

   double  shownLevel = (gEntryLevel > 0.0) ? gEntryLevel : gEma1S;
   PanelRow(r++, "LIMIT @",
            StringFormat("%s   %s EMA50%s", DoubleToString(shownLevel, gDigits),
                         EntryLevelTag(),
                         gEntryLevelSrc > 0 ? "  (fallback)" : ""),
            PanelTextColor, gEntryLevelSrc > 0 ? clrGold : clrDeepSkyBlue);

   PanelRow(r++, "STATUS", gStatus + "  " + gStatusDetail, PanelTextColor, gStatusColor);

   PanelRow(r++, "------------------------------------", "", C'70,76,90', C'70,76,90');

   //--- account block ----------------------------------------------------------
   int openPos = CountPositions();
   PanelRow(r++, "POSITIONS",
            StringFormat("%d / %d   open risk %.1f%%",
                         openPos, MaxConcurrentPositions, openPos * RiskPercent),
            PanelTextColor, openPos >= MaxConcurrentPositions ? clrOrange : PanelTextColor);

   //--- one row per open position: direction, the EMA50 level that filled
   //    it, entry price and live P/L. This is the only place the fill level
   //    is visible after the fact, so it stays even when the panel is busy.
   int shownPos = 0;
   int capPos   = (PanelMaxPositions > 0 ? PanelMaxPositions : 5);
   for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
     {
      ulong pt = PositionGetTicket(pi);
      if(pt == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      if(shownPos >= capPos) continue;   // remainder summarised below
      shownPos++;

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double popen = PositionGetDouble(POSITION_PRICE_OPEN);
      double ppl   = PositionGetDouble(POSITION_PROFIT)
                   + PositionGetDouble(POSITION_SWAP);
      string pcom  = PositionGetString(POSITION_COMMENT);

      PanelRow(r++, "  OPEN",
               StringFormat("%s  %s", ptype == POSITION_TYPE_BUY ? "BUY " : "SELL",
                            PositionReason(pcom)),
               PanelTextColor, ptype == POSITION_TYPE_BUY ? clrLime : clrTomato);
      PanelRow(r++, "",
               StringFormat("      @ %s   %+.2f",
                            DoubleToString(popen, gDigits), ppl),
               PanelTextColor, ppl >= 0.0 ? clrLime : clrTomato);
     }

   if(openNow > shownPos)
      PanelRow(r++, "", StringFormat("      ... and %d more not shown",
                                     openNow - shownPos),
               PanelTextColor, clrSilver);

   //--- v7.15: use the stop that will ACTUALLY be traded. A counter-trend
   //    setup sizes off CounterSLPips (500), so quoting the 900 stop here
   //    showed roughly half the real lot.
   int    pdir2 = 0; bool pctr2 = false;
   double panelSL = SLPips;
   if(DesiredDirection(pdir2, pctr2) && pctr2)
      panelSL = CounterSLPips;
   double riskPct = 0.0; string why = "";
   double lot = CalcLot(panelSL * gPip, riskPct, why);
   PanelRow(r++, "NEXT LOT",
            lot > 0.0 ? StringFormat("%s   %.2f%%", DoubleToString(lot, 2), riskPct)
                      : "rejected: " + why,
            PanelTextColor, lot > 0.0 ? PanelTextColor : clrTomato);

   double dayPct = (gDayStartBalance > 0.0) ? gDayPL / gDayStartBalance * 100.0 : 0.0;
   if(CooldownMinutesAfterLoss > 0 && gLastLossDir != 0 && InCooldown(gLastLossDir))
      PanelRow(r++, "COOLDOWN",
               StringFormat("%s only - %d min left (%s still allowed)",
                            gLastLossDir > 0 ? "BUY" : "SELL", CooldownMinsLeft(),
                            gLastLossDir > 0 ? "SELL" : "BUY"),
               PanelTextColor, clrOrange);

   if(gBrakeDir != 0)
      PanelRow(r++, "BRAKE",
               StringFormat("%s blocked - %d losses in a row, waiting for 15M flip",
                            gBrakeDir > 0 ? "BUY" : "SELL", gDirLossStreak),
               PanelTextColor, clrOrange);

   //--- streaks sit under the win rate because they answer the question it
   //    cannot: how the losses arrange themselves. "worst" is the run the
   //    brake threshold has to be set against.
   if(gAllWins + gAllLosses > 0)
      PanelRow(r++, "STREAK",
               StringFormat("now %s%d    best +%d    worst %d   (this config)",
                            gAllStreak > 0 ? "+" : "", gAllStreak,
                            gAllBestWin, gAllWorstLoss),
               PanelTextColor,
               gAllStreak > 0 ? clrLime : (gAllStreak < 0 ? clrTomato : PanelTextColor));

   PanelRow(r++, "WIN RATE",
            StringFormat("today %s    overall %s",
                         WinRateText(gDayWins, gDayLosses),
                         WinRateText(gAllWins, gAllLosses)),
            PanelTextColor,
            (gDayWins >= gDayLosses) ? clrLime : clrTomato);

   string tradeCap = (MaxDailyTradeCount > 0)
                     ? StringFormat("%d / %d trades", gDayTrades, MaxDailyTradeCount)
                     : StringFormat("%d trades (no cap)", gDayTrades);
   PanelRow(r++, "TODAY",
            StringFormat("%+.2f  (%+.2f%%)    %s", gDayPL, dayPct, tradeCap),
            PanelTextColor, gDayPL < 0.0 ? clrTomato : clrLime);

   //--- remove rows left behind by a taller previous pass. Without this a
   //    closed position leaves its labels on the chart, overlapping whatever
   //    now occupies those rows.
   for(int dead = r; dead < gPanelRowsDrawn; dead++)
     {
      ObjectDelete(0, PFX + "PL" + IntegerToString(dead));
      ObjectDelete(0, PFX + "PV" + IntegerToString(dead));
     }
   gPanelRowsDrawn = r;

   //--- v7.27.3: health and diagnostics moved to the bottom. They were
   //    interleaved between the market read and the RSI rows, which pushed
   //    the things actually watched - MODE, STATUS, positions, P/L - down
   //    the panel behind uptime and bar timestamps. Order is now: what the
   //    market is doing, what the EA intends to do, what the triggers see,
   //    what it costs, and only then whether the plumbing is healthy.
   PanelRow(r++, "------------------------------------", "", C'70,76,90', C'70,76,90');

   PanelRow(r++, "EA ALIVE",
            StringFormat("%d:%02d:%02d    drawn %ds ago",
                         upSecs / 3600, (upSecs % 3600) / 60, upSecs % 60,
                         drawAgo),
            PanelTextColor, drawAgo > 5 ? clrOrange : clrLime);

   PanelRow(r++, "NEXT CLOSE",
            StringFormat("1M %s   5M %s   15M %s",
                         BarCountdown(EntryTF), BarCountdown(SignalTF),
                         BarCountdown(TrendTF)),
            PanelTextColor, clrDeepSkyBlue);

   PanelRow(r++, "BARS USED",
            StringFormat("15M %s   5M %s   1M %s",
                         TimeToString(gLastTrendBar,  TIME_MINUTES),
                         TimeToString(gLastSignalBar, TIME_MINUTES),
                         TimeToString(gLastEntryBar,  TIME_MINUTES)),
            PanelTextColor, clrDeepSkyBlue);

   PanelRow(r++, "LIVE 5M",
            StringFormat("%s / %s  RSI %.1f  (not traded)",
                         DoubleToString(gLiveEma5F, 2),
                         DoubleToString(gLiveEma5S, 2), gLiveRsi5),
            clrGray, gLiveEma5F > gLiveEma5S ? clrLime : clrTomato);

   double spr = CurrentSpreadPips();
   PanelRow(r++, "SPREAD",
            StringFormat("%.0f pips   %s", spr, spr > MaxSpreadPips ? "WIDE" : "ok"),
            PanelTextColor, spr > MaxSpreadPips ? clrTomato : clrLime);

   ObjectSetInteger(0, bg, OBJPROP_YSIZE, r * rowH + 12);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, gPanelMaxW + 18);

   ChartRedraw();
  }

//--- Time left on the current bar of a timeframe, as m:ss. Driven by
//    TimeCurrent(), which is the server time of the last quote - so if the
//    feed stops these countdowns stop with it, which makes a stalled
//    terminal obvious at a glance.
string BarCountdown(const ENUM_TIMEFRAMES tf)
  {
   datetime opened = iTime(_Symbol, tf, 0);
   if(opened <= 0)
      return("--:--");
   int per  = PeriodSeconds(tf);
   int left = per - (int)(TimeCurrent() - opened);
   if(left < 0)   left = 0;
   if(left > per) left = per;
   return(StringFormat("%d:%02d", left / 60, left % 60));
  }

void PanelRow(const int row, const string label, const string value,
              const color labelClr, const color valueClr)
  {
   const int rowH = PanelFontSize + 7;
   //--- MT5 paints its default "Label" caption when an OBJ_LABEL text is set
   //    to an empty string, so blank continuation rows need a real space.
   PanelLabel(PFX + "PL" + IntegerToString(row), PanelX,
              PanelY + row * rowH, (label == "" ? " " : label), labelClr);
   //--- v7.27.3: the value column was pinned at +122px while the title row
   //    label is "TREND EA  -  XAUUSDc" - about 160px of Consolas at size 9.
   //    The two drew on top of each other. Measure the label and push the
   //    value past it when it is long, so ordinary rows stay aligned on the
   //    same column and only an oversized label moves its own value.
   if(value != "")
     {
      uint lw = 0, lh = 0;
      TextGetSize(label, lw, lh);
      int vx    = PanelX + 122;
      int clear = PanelX + (int)lw + 12;
      if(clear > vx) vx = clear;
      PanelLabel(PFX + "PV" + IntegerToString(row), vx,
                 PanelY + row * rowH, value, valueClr);
     }
  }

void PanelLabel(const string name, const int x, const int y,
                const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  PanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   //--- E: clip rather than let a long status line run past the panel edge.
   //    The cap is generous now that the box is sized to the content - the
   //    old 46 truncated live status text such as
   //    "5M RSI 38.7 - SELL arm cold (needs a touch > 50)".
   string shown = text;
   if(StringLen(shown) > 60)
      shown = StringSubstr(shown, 0, 57) + "...";
   ObjectSetString(0, name, OBJPROP_TEXT, shown);

   uint tw = 0, th = 0;          // TextGetSize takes uint references
   TextGetSize(shown, tw, th);
   int rightEdge = (x - PanelX) + (int)tw;
   if(rightEdge > gPanelMaxW)
      gPanelMaxW = rightEdge;
  }

//+------------------------------------------------------------------+
//| Chart lines: live limit level plus projected SL / TP               |
//+------------------------------------------------------------------+
void DrawLevels()
  {
   int  dir = 0; bool counter = false;
   double lvl = (gEntryLevel > 0.0) ? gEntryLevel : gEma1S;
   bool haveSetup = DesiredDirection(dir, counter) && lvl > 0.0;

   if(!haveSetup)
     {
      ObjectDelete(0, PFX + "Lentry");
      ObjectDelete(0, PFX + "Lsl");
      ObjectDelete(0, PFX + "Ltp");
      return;
     }

   if(ShowEntryLine)
      HLine(PFX + "Lentry", lvl,
            gEntryLevelSrc > 0 ? clrGold : clrDeepSkyBlue, STYLE_SOLID, 1,
            StringFormat("TREMA limit (%s EMA50%s)", EntryLevelTag(),
                         gEntryLevelSrc > 0 ? " fallback" : ""));
   else
      ObjectDelete(0, PFX + "Lentry");

   if(ShowSLTPLines)
     {
      double tpPips = counter ? TakeProfitCounterPips : TPPips;
      //--- v7.15: counter-aware, matching ManageLimit. The TP line already
      //    was; the SL line drew 900 for a setup that trades 500.
      double slP = counter ? CounterSLPips : SLPips;
      double sl = (dir > 0) ? lvl - slP * gPip : lvl + slP * gPip;
      double tp = (dir > 0) ? lvl + tpPips        * gPip : lvl - tpPips        * gPip;
      HLine(PFX + "Lsl", sl, clrTomato, STYLE_DOT, 1, "TREMA SL");
      HLine(PFX + "Ltp", tp, clrLime,   STYLE_DOT, 1, "TREMA TP");
     }
   else
     {
      ObjectDelete(0, PFX + "Lsl");
      ObjectDelete(0, PFX + "Ltp");
     }
  }

void HLine(const string name, const double price, const color clr,
           const ENUM_LINE_STYLE style, const int width, const string tip)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
  }
//+------------------------------------------------------------------+
