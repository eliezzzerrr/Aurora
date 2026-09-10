//+------------------------------------------------------------------+
//|                                            SRLevels_EA_v1.5.mq5   |
//|      4H trend-following limits at support / resistance zones      |
//|                                                                   |
//|  Symbol  : XAUUSD and gold variants (XAUUSDc, XAUUSDm, GOLD...)   |
//|  TFs     : 4H trend / H1 + 4H pivots / 15M entry                  |
//|  Account : built for an Exness USC (cent) account                 |
//|  Version : 1.00                                                   |
//|  Date    : 2026-09-10                                             |
//+------------------------------------------------------------------+
//
//  ================================================================
//                          STRATEGY SPEC
//  ================================================================
//  Modelled on the operator's coach: three supports (S1-S3) below
//  price, three resistances (R1-R3) above, each a ZONE built from
//  several sources stacked on top of each other, traded with resting
//  limits in tiers (BL#1 aggressive at S1, BL#2 default at S2, BL#3
//  conservative at S3) and a take-profit at the next level across.
//
//  TREND (4H, closed bars only)
//    Close above the Ichimoku cloud AND above the MA50  -> BUY side
//    Close below the cloud AND below the MA50           -> SELL side
//    Anything else                                      -> no new orders
//    The coach also bought supports inside a 4H downtrend (1 Sep);
//    the operator asked for the 4H to gate direction, so this EA does
//    not. That is a deliberate narrowing, not an oversight.
//
//  LEVEL SOURCES (each switchable, each with a weight)
//    - swing highs / lows on PivotTF (H1) and MajorPivotTF (4H)
//    - MA50 on 15M / 4H / D1, EMA9 on 4H / D1, MA200 on 4H
//    - Ichimoku cloud edges (Senkou A / B) on 4H and 15M
//    - Fibonacci 0.382 / 0.5 / 0.618 / 0.786 of the last 4H swing
//
//  ZONES
//    Points within ZoneMergeAtrMult x ATR(PivotTF) of each other are
//    merged. A zone's SCORE is the sum of its point weights; zones
//    below ZoneMinScore are ignored. The three nearest qualifying
//    zones below the market are S1..S3, the three above are R1..R3.
//
//  ENTRY
//    LIMIT (default): a limit rests at the near edge of each enabled
//    tier and is re-priced whenever the zone moves. REJECTION: wait
//    for a 15M bar to wick into the zone and close back out of it,
//    then enter at market.
//
//  GEOMETRY
//    SL beyond the far edge of the zone plus a buffer (or beyond the
//    NEXT zone, SL_NEXT_LEVEL). TP at R1 for buys / S1 for sells,
//    minus a buffer, refused below MinRR. Fixed RR available.
//
//  PIP CONVENTION: 1 pip = 0.01 in price on gold = $0.01. Auto-detected
//  from digits (3-digit XAUUSDc -> pip = 10 points = 0.01).
//
//  ================================================================
//                             WARNING
//  ================================================================
//  THIS EA PLACES ORDERS AS SOON AS IT IS ATTACHED. There is no arming
//  switch, matching TrendEMA. Stop it with the Algo Trading toggle,
//  by removing it from the chart, or by dropping SRLEVELS_STOP.txt
//  into MQL5\Files. Demo first.
//+------------------------------------------------------------------+
#property copyright "Aurora SR Levels EA"
#property version   "1.50"   // file is SRLevels_EA_v1.5 - bump both together
#property description "4H trend filter, resting limits at S1-S3 / R1-R3 zones built from pivots, MAs, cloud edges and fibs. TP at the next level."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_TREND_MODE
  {
   TREND_CLOUD_AND_MA,   // Cloud AND MA50 must agree (default)
   TREND_CLOUD_ONLY,     // Ichimoku cloud only
   TREND_MA_ONLY,        // Price vs MA50 only
   TREND_EMA_STACK,      // EMA9 vs MA50 stack plus price above/below both
   TREND_NONE            // No filter: buy supports AND sell resistances (the coach's actual habit)
  };

enum ENUM_ENTRY_MODE
  {
   ENTRY_LIMIT,          // Resting limit at the zone edge (coach style, default)
   ENTRY_REJECTION       // Wait for a 15M close back out of the zone, enter at market
  };

enum ENUM_LIMIT_PLACE
  {
   PLACE_NEAR_EDGE,      // Limit at the near edge of the zone (first touch fills)
   PLACE_MID,            // Limit in the middle of the zone
   PLACE_FAR_EDGE        // Limit at the far edge (fills only on a deep test)
  };

enum ENUM_SL_MODE
  {
   SL_ZONE,              // Beyond the far edge of the traded zone (default)
   SL_NEXT_LEVEL         // Beyond the NEXT zone out (wider, fewer stop-outs)
  };

enum ENUM_TP_MODE
  {
   TP_R1_S1,             // Nearest level across the market: R1 for buys, S1 for sells (default)
   TP_NEXT_ZONE,         // First zone of ANY kind beyond the entry (shorter)
   TP_FIXED_RR           // Fixed reward:risk multiple
  };

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES TrendTF      = PERIOD_H4;  // Trend TF (cloud + MA50)
input ENUM_TIMEFRAMES EntryTF      = PERIOD_M15; // Entry TF (limits re-priced / rejection bars)
input ENUM_TIMEFRAMES PivotTF      = PERIOD_H1;  // Minor swing pivots
input ENUM_TIMEFRAMES MajorPivotTF = PERIOD_H4;  // Major swing pivots

input group "=== 4H TREND ==="
//--- v1.2, 10 Sep 2026: the 4H GATE IS OFF BY DEFAULT. The operator asked
//    for the EA to trade the way the coach's charts do: buy limits at the
//    supports AND sell limits at the resistances at the same time, whatever
//    the 4H says. In the 19 coach screenshots the 4H supplies the levels
//    (swings, cloud edges, MA50/MA200, fib) but never gates the side - on
//    1 Sep he held three buy tiers under a 4H that was below its cloud and
//    MA50. The gated version was the operator's own first instruction and
//    ran for one afternoon as v1.0-v1.1.
//    Evidence, minute-bar tester, both years, for the record: the ungated
//    version LOST where the gated one did not (-1222 in 2026 on the v1.1
//    geometry with a 1.0 reward floor, -3052 as first written; the gated
//    equivalents +530 and -846). The operator chose it with those numbers
//    in front of them. Real-tick results for this mode do not exist yet.
//    TREND_CLOUD_AND_MA restores the gate; BlockOpposingEntries=true goes
//    with it.
input ENUM_TREND_MODE TrendMode = TREND_NONE; // How the 4H picks a side (NONE = both sides, coach style)
input int    TrendMAPeriod      = 50;    // MA50 on the trend TF (SMA, like the coach's blue line)
input int    TrendEMAPeriod     = 9;     // EMA9 on the trend TF (the coach's red line)
input int    IchiTenkan         = 9;     // Ichimoku Conversion Line
input int    IchiKijun          = 26;    // Ichimoku Base Line
input int    IchiSenkou         = 52;    // Ichimoku Leading Span B

input group "=== LEVEL SOURCES ==="
input int    PivotLeft          = 3;     // Bars to the left a swing must beat
input int    PivotRight         = 3;     // Bars to the right a swing must beat
input int    PivotLookback      = 300;   // Minor pivot lookback (bars of PivotTF)
input int    MajorPivotLookback = 150;   // Major pivot lookback (bars of MajorPivotTF)
input double PivotWeight        = 1.0;   // Weight of a minor swing point
input double MajorPivotWeight   = 2.0;   // Weight of a major swing point
input bool   UseMA50_M15        = true;  // MA50 on 15M as a level
input bool   UseMA50_H4         = true;  // MA50 on 4H as a level
input bool   UseMA50_D1         = true;  // MA50 on D1 as a level
input bool   UseEMA9_H4         = true;  // EMA9 on 4H as a level
input bool   UseEMA9_D1         = true;  // EMA9 on D1 as a level
input bool   UseMA200_H4        = true;  // MA200 on 4H as a level
input double MAWeight           = 1.5;   // Weight of a moving-average level
input bool   UseCloud_H4        = true;  // 4H cloud edges as levels
input bool   UseCloud_M15       = true;  // 15M cloud edges as levels
input double CloudWeight        = 1.5;   // Weight of a cloud edge
input bool   UseFib             = true;  // Fib retracement of the last 4H swing
input int    FibSwingBars       = 60;    // 4H bars scanned for the swing high / low
input double FibWeight          = 1.0;   // Weight of a fib level

input group "=== ZONES ==="
input double ZoneMergePips      = 0;     // Merge points this close (0 = use ATR multiple below)
input double ZoneMergeAtrMult   = 0.35;  // ...as a multiple of ATR(14) on PivotTF
input double ZoneMinScore       = 2.0;   // Ignore zones scoring below this
input double MinZoneDistancePips= 100;   // Ignore zones closer than this to the market
input double MaxZoneDistancePips= 3000;  // Ignore zones farther than this from the market
input int    ZoneRetradeBars    = 48;    // Entry bars before the same zone can be traded again
input int    ZoneLossBlockBars  = 96;    // Entry bars a zone is blocked after a loss from it

input group "=== ENTRY ==="
input ENUM_ENTRY_MODE EntryMode = ENTRY_LIMIT; // How a zone is entered
input bool   TradeTier1         = true;  // Trade S1 / R1 (aggressive)
input bool   TradeTier2         = true;  // Trade S2 / R2 (default)
input bool   TradeTier3         = false; // Trade S3 / R3 (conservative)
input ENUM_LIMIT_PLACE LimitPlacement = PLACE_NEAR_EDGE; // Where in the zone the limit rests
input double LimitOffsetPips    = 0;     // Extra shift INSIDE the zone from that placement
input double RepricePips        = 30;    // Re-price a resting limit when the zone moves more than this
input int    PendingExpiryBars  = 32;    // Cancel an unfilled limit after this many entry bars
input bool   RejectionNeedsBody = true;  // REJECTION mode: the bar must close in the trade direction
input bool   CancelOnTrendFlip  = true;  // Cancel resting limits when the 4H side changes

input group "=== RISK ==="
//--- DEFAULTS CHOSEN ON 10 Sep 2026 from 40 headless tester runs, XAUUSD
//    (Exness demo), 15M, 1-minute OHLC, 10,000 deposit, 0.5% risk. The
//    2026 run (1 Jan - 8 Sep) picked the settings; 2025 (full year) is the
//    out-of-sample check. Read the 2025 column as the honest one.
//
//                                   2026 Jan-Sep            2025
//      as first written (zone SL,   -846   PF 0.91          +1540  PF 1.08
//        TP at R1, RR floor 1.0)
//      SL beyond the NEXT zone      +874   PF 1.08          -
//      TP at the next zone          +748   PF 1.10          -
//      both                         +530   PF 1.08          +1053  PF 1.14
//      both + RR floor 0.6          +1205  PF 1.15          +1460  PF 1.16
//      both + 0.6 + breakeven 1.5R  +1619  PF 1.22          +1416  PF 1.16
//
//    What did NOT survive 2025 and is therefore NOT a default:
//      - excluding the US session (22:00-13:00 GMT window): 2026 +1263
//        PF 1.28, 2025 +236 PF 1.04. A 2026-only effect.
//      - breakeven at 0.7R: 2026 +2207 PF 1.38, 2025 +929 PF 1.13.
//      - the limit in the MIDDLE of the zone: -2043 in 2026. Deeper fills
//        are the ones where the level is breaking, not holding.
//      - no 4H filter at all (the coach's both-sides habit): -1222 with
//        the same geometry, -3052 as first written.
//    Tier 2 (S2/R2) lost on its own in both years (-109 and -151) but
//    removing it changes slot interactions more than it saves; left on.
//    The edge is thin: PF 1.16 out of sample, win rate about four points
//    above its own breakeven. Fifty trades will not tell you if it is real.
//
//--- OPERATOR DECISION, 10 Sep 2026: the shipped geometry is a FIXED 3R
//    TARGET with the stop beyond the traded zone, capped at 1000 pips.
//    The operator asked for 3R per trade and confirmed it after seeing
//    the numbers. Recorded here so nobody "fixes" it back without asking:
//
//                                        2026 Jan-Sep          2025
//      next-zone TP, RR floor 0.6,       +1619  PF 1.22        +1416  PF 1.16
//        next-zone SL, BE 1.5R            0.056%/trade          0.043%/trade
//      3R, zone SL <= 1000p, BE 1.5R     +458   PF 1.07        +1904  PF 1.11
//        (THIS BUILD)                     0.020%/trade          0.037%/trade
//      3R, zone SL <= 1500p, no BE       +716   PF 1.06        +468   PF 1.02
//        win 25.4% / 26.5% against a 3R breakeven of 24.3% / 25.6%
//
//    A 3R target lowers the money per trade: the win rate falls in step
//    with the payout. The 2025 trend year flatters every long target and
//    2026 takes it back.
//
//--- v1.1, 10 Sep 2026, same day: REVERSED. The operator ran the 3R build
//    through the live terminal tester on XAUUSDc with 100% real ticks
//    (1 Jan - 9 Sep 2026): 220 trades, -296.58, PF 0.86. 41 targets,
//    139 full stops, 40 breakeven scratches - one winner per 3.4 stops
//    against the one per 3.0 it needs. A quarter of the trades were over
//    inside six minutes: on real ticks the limit fills on a spike and the
//    300-1000 pip zone stop goes in the same move, which minute-bar
//    modelling cannot see. Fills between 22:00 and 02:00 server time, the
//    daily break, were 12 won / 47 lost. (The 2.0 lot cap bound on every
//    trade of that run because the tester deposits USD against a symbol
//    that pays in cents; the structure is valid, the percentages are not.)
//    The next-zone geometry below is what shipped as v1.1: the wider stop
//    is the direct answer to the six-minute stop-outs. It has NOT yet been
//    run on real ticks - that is the next test, and it may fail too.
//
//--- v1.3, 10 Sep 2026, 15:52: the 3R TARGET IS BACK. v1.1 swapped it for
//    the next-zone target on "ship it", v1.2 kept that, and the operator
//    saw resting orders at 0.7R and 1.8R on the live account and said,
//    reasonably, that they had asked for 3R. This is the v1.0.1 geometry
//    (fixed 3R, stop beyond the traded zone capped at 1000 pips, breakeven
//    1.5R) combined with the v1.2 both-sides mode. Real-tick result for the
//    gated 3R build was PF 0.86 (220 trades); for this ungated one, none.
//    The next-zone geometry is four fields away: TPMode=TP_NEXT_ZONE,
//    MinRR=0.6, SLMode=SL_NEXT_LEVEL, MaxSLPips=2500.
input ENUM_SL_MODE SLMode       = SL_ZONE;   // Where the stop goes
input double SLBufferPips       = 150;   // Stop this far beyond the zone edge
input double SLBufferAtrMult    = 0.5;   // ...or this x ATR(14) on EntryTF, whichever is larger
input double MinSLPips          = 300;   // Widen any stop tighter than this
input double MaxSLPips          = 1000;  // Refuse the trade if the stop would be wider than this
//--- v1.5, 10 Sep 2026, 15:56: "the TP goes as high as R1, with a minimum
//    of 2R". Target at the first level beyond the entry (R1 for an S1 buy),
//    less the buffer; when that level is closer than MinRR x the stop, the
//    target is placed AT MinRR instead of the trade being skipped. With no
//    level in range, FixedRR. This replaces the v1.4 rule (3R, else 2R),
//    which the operator clarified was not what they meant.
input ENUM_TP_MODE TPMode       = TP_NEXT_ZONE;  // Where the target goes
input double TPBufferPips       = 50;    // Target this far short of the level (level modes only)
input double MinRR              = 2.0;   // Floor on reward:risk for a level target
input bool   ExtendToMinRR      = true;  // Level closer than MinRR: place the TP at MinRR (false = skip the trade)
input double FixedRR            = 3.0;   // TP_FIXED_RR multiple, also the fallback when no level is in range
//--- v1.4, 10 Sep 2026: "3R if possible, otherwise 2R". A fixed 3R target
//    that sits beyond the first zone in the way is a target the market has
//    to break a level to reach. When that is the case the target drops to
//    FallbackRR instead - the trade is still taken. "In the way" means the
//    first zone of any kind beyond the entry, less TPBufferPips, exactly
//    the level TP_NEXT_ZONE would have used. 0 disables the fallback.
input double FallbackRR         = 2.0;   // Use this multiple when FixedRR would sit beyond the first level (0 = never)
input bool   FallbackToFixedRR  = true;  // No level target -> use FixedRR (false = skip the trade)
input double BreakevenAtR       = 1.5;   // Move SL to entry after this many R (0 = off)
input double BreakevenOffsetPips= 20;    // ...plus this many pips in profit
input bool   UseFixedLot        = false; // Fixed lot instead of % risk (edge testing)
input double FixedLotSize       = 0.01;  // Lot used when UseFixedLot is true
input double RiskPercent        = 0.5;   // Risk per trade, % of capital
input double MaxRiskPercent     = 1.25;  // Hard ceiling - reject the trade above this
input bool   SizeFromEquity     = true;  // Size from equity (false = balance)
input double MaxLotSizeCap      = 2.0;   // Absolute lot cap (0 = disabled)
input int    MaxConcurrentPositions = 2; // Max simultaneous positions
input int    MaxTradesPerDay    = 3;     // Max fills per trading day (0 = unlimited)
input bool   BlockOpposingEntries = false;// Never hold a BUY and a SELL at once (must be false for TREND_NONE)
input double MaxDailyLossPercent= 5.0;   // Halt for the day at this realised loss % (0 = off)
input int    DayResetHourET     = 17;    // Hour (ET) the trading day rolls over
input int    ETOffsetHours      = -4;    // ET offset from GMT: -4 Mar-Nov, -5 Nov-Mar
input double MinFreeMarginPercent = 30.0;// Pause if free margin / equity below this %
input bool   CloseOnTrendFlip   = false; // Close open trades when the 4H side changes

input group "=== FILTERS ==="
input double MaxSpreadPips      = 50;    // Skip if spread wider than this
input string SessionWindowsGMT  = "";    // Trade only inside these GMT windows "HH:MM-HH:MM,..." (empty = always)
input bool   AllowFridayLate    = false; // Allow new entries late Friday
input int    FridayCutoffHour   = 16;    // Friday cutoff hour (GMT) when above is false

input group "=== DISPLAY ==="
input bool   ShowPanel          = true;  // On-chart status panel
input bool   ShowZones          = true;  // Draw S1-S3 / R1-R3 as rectangles
input int    PanelX             = 12;    // Panel X offset
input int    PanelY             = 22;    // Panel Y offset
input int    PanelFontSize      = 9;     // Panel font size
input int    PanelRefreshSeconds= 1;     // Redraw the panel this often with no ticks
input color  PanelTextColor     = clrWhiteSmoke;  // Panel text
input color  PanelBgColor       = C'18,20,26';    // Panel background
input color  SupportColor       = C'22,70,40';    // Support zone fill
input color  ResistanceColor    = C'90,30,30';    // Resistance zone fill

input group "=== SAFETY ==="
input bool   SingleInstanceLock = true;  // Refuse to start if another copy runs on this symbol+magic
input double PipSizeOverride    = 0.0;   // Force a pip size (0 = auto-detect)
input bool   EnforcePositionStops = true;// Attach a stop to any position found without one
input bool   EnableHeartbeat    = true;  // Write a heartbeat file for an external watchdog
input string HeartbeatFile      = "SRLEVELS_HEARTBEAT.txt"; // Written to MQL5\Files
input string EmergencyStopFile  = "SRLEVELS_STOP.txt";      // Kill-switch file in MQL5\Files
input long   MagicNumber        = 9101;  // Trade identifier (TrendEMA uses 8888)
input double MaxSlippagePips    = 10;    // Slippage tolerance
input string TradeCommentPrefix = "SRL"; // Order comment prefix

input group "=== ALERTS ==="
input bool   AlertOnFill        = true;  // Popup when an order fills
input bool   AlertOnClose       = true;  // Popup when a position closes
input bool   EnablePush         = false; // Mobile push

input group "=== DEBUG ==="
input bool   VerboseLog         = false; // Log every gate decision and zone rebuild

//+------------------------------------------------------------------+
//| TYPES                                                             |
//+------------------------------------------------------------------+
//--- one price the market may react to, with where it came from
struct LevelPoint
  {
   double   price;
   double   weight;
   string   tag;      // "piv H1", "MA50 H4", "kumo 15M", "fib 0.5"...
   datetime t;        // bar time for pivots, 0 for dynamic levels
  };

//--- a cluster of points
struct Zone
  {
   double   top;
   double   bottom;
   double   score;
   int      points;
   string   tags;
   datetime firstT;
  };

//--- a zone we have traded or that has failed, so we do not chase it
struct ZoneBlock
  {
   double   top;
   double   bottom;
   int      untilBar;   // entry-bar counter at which the block lifts
   string   why;
  };

//--- a resting limit we own
struct PendingRec
  {
   ulong    ticket;
   int      tier;       // 1..3
   int      dir;        // +1 buy, -1 sell
   double   top;
   double   bottom;
   double   slPips;
   double   tpPips;
   int      bars;
  };

//--- an open position we opened, so a close can be attributed to its zone
struct PosRec
  {
   long     posId;
   int      tier;
   double   top;
   double   bottom;
   double   riskPrice;  // entry-to-stop distance in price at fill
   bool     beAdjusted;
  };

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade   gTrade;

int      hIchiT   = INVALID_HANDLE;  // trend TF cloud
int      hIchiE   = INVALID_HANDLE;  // entry TF cloud
int      hMaT     = INVALID_HANDLE;  // MA50 trend TF
int      hEmaT    = INVALID_HANDLE;  // EMA9 trend TF
int      hMa200T  = INVALID_HANDLE;  // MA200 trend TF
int      hMaE     = INVALID_HANDLE;  // MA50 entry TF
int      hMaD1    = INVALID_HANDLE;  // MA50 D1
int      hEmaD1   = INVALID_HANDLE;  // EMA9 D1
int      hAtrP    = INVALID_HANDLE;  // ATR pivot TF (zone merge width)
int      hAtrE    = INVALID_HANDLE;  // ATR entry TF (stop buffer)

double   gPip    = 0.01;
double   gPoint  = 0.01;
int      gDigits = 2;
bool     gInitOk = false;
bool     gHeadless = false;

//--- trend state (closed bars)
int      gTrendDir   = 0;      // +1 up, -1 down, 0 none
int      gTrendPrev  = 0;
string   gTrendText  = "";
double   gTClose = 0, gTSenA = 0, gTSenB = 0, gTMa = 0, gTEma = 0, gTMa200 = 0;
double   gESenA = 0, gESenB = 0, gEMa = 0, gMaD1 = 0, gEmaD1 = 0;
double   gAtrP = 0, gAtrE = 0;
double   gFibHi = 0, gFibLo = 0; int gFibDirUp = 0;

//--- levels
LevelPoint gPoints[];
Zone       gZones[];
int        gSup[3];   // indices into gZones, -1 = none
int        gRes[3];
int        gNSup = 0, gNRes = 0;
datetime   gZonesBuiltAt = 0;
//--- bumped on every rebuild; ManageLimits runs once per version, so the
//    limits are re-derived exactly when the zones are and not per tick
int        gZonesVersion = 0, gLimitsVersion = -1;

//--- pendings / positions / blocks
PendingRec gPend[];
PosRec     gPos[];
ZoneBlock  gBlocks[];

//--- rejection-mode arming
datetime   gLastRejectBar = 0;

//--- bar tracking
datetime gLastTrendBar = 0;
datetime gLastEntryBar = 0;
datetime gLastPivotBar = 0;
int      gEntryBarCount = 0;
int      gStaleTrend = 0, gStaleEntry = 0;

//--- daily
datetime gDayStart = 0;
long     gDayIndex = -1;
double   gDayStartBalance = 0;
int      gDayTrades = 0, gDayWins = 0, gDayLosses = 0;
double   gDayPL = 0;
int      gAllWins = 0, gAllLosses = 0;
double   gAllNet = 0;

//--- status / throttles
string   gStatus = "INIT", gStatusDetail = ""; color gStatusColor = clrSilver;
uint     gLastStatsMs = 0, gLastPanelMs = 0, gLastLockMs = 0, gLastBeatMs = 0;
uint     gLastStopChkMs = 0, gLastTickMs = 0, gInitMs = 0;
datetime gLastStopSync = 0;
bool     gStopFilePresent = false;
bool     gHoldsLock = false;
string   gPhase = "INIT";
int      gPanelRowsDrawn = 0, gPanelMaxW = 0;
string   gLastRejectKey = "";
string   gTpNote = "";        // which fixed-RR target Geometry chose, for the placement log

const string PFX = "SRL_";

//+------------------------------------------------------------------+
//| Single-instance lock (same pattern as TrendEMA)                    |
//+------------------------------------------------------------------+
string LockName() { return(StringFormat("SRL_LOCK_%s_%d", _Symbol, (int)MagicNumber)); }

void TouchLock()
  {
   if(!SingleInstanceLock || MQLInfoInteger(MQL_TESTER)) return;
   uint now = GetTickCount();
   if(gLastLockMs != 0 && (now - gLastLockMs) < 5000) return;
   gLastLockMs = now;
   GlobalVariableSet(LockName(), (double)TimeLocal());
  }

bool MarketSessionOpen()
  {
   MqlDateTime dt; TimeToStruct(TimeTradeServer(), dt);
   int nowSecs = dt.hour * 3600 + dt.min * 60 + dt.sec;
   datetime from = 0, to = 0;
   for(int i = 0; i < 8; i++)
     {
      if(!SymbolInfoSessionQuote(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to)) break;
      if(nowSecs >= (int)from && nowSecs <= (int)to) return(true);
     }
   return(false);
  }

//--- <local time>|<seconds since last tick>|<1 if market open>|<phase>
void WriteHeartbeat()
  {
   if(!EnableHeartbeat || gHeadless) return;
   uint now = GetTickCount();
   if(gLastBeatMs != 0 && (now - gLastBeatMs) < 5000) return;
   int tickAge = (gLastTickMs > 0) ? (int)((now - gLastTickMs) / 1000) : 99999;
   int h = FileOpen(HeartbeatFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE) return;
   gLastBeatMs = now;
   FileWrite(h, StringFormat("%s|%d|%d|%s", TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
                             tickAge, MarketSessionOpen() ? 1 : 0, gPhase));
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   gInitOk = false;

   if(SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     {
      string lock = LockName();
      if(GlobalVariableCheck(lock))
        {
         int age = (int)(TimeLocal() - (datetime)GlobalVariableGet(lock));
         if(age >= 0 && age < 30)
           {
            PrintFormat("[SRL] REFUSING to start: another instance runs on %s magic %d "
                        "(seen %ds ago). Remove the other chart or set SingleInstanceLock=false.",
                        _Symbol, (int)MagicNumber, age);
            return(INIT_FAILED);
           }
        }
      GlobalVariableSet(lock, (double)TimeLocal());
      gHoldsLock = true;
     }

   //--- input sanity ---------------------------------------------------
   if(RiskPercent <= 0 || MaxRiskPercent < RiskPercent)
     { Print("[SRL] REFUSING: need 0 < RiskPercent <= MaxRiskPercent."); return(INIT_FAILED); }
   if(MinSLPips <= 0 || MaxSLPips < MinSLPips)
     { Print("[SRL] REFUSING: need 0 < MinSLPips <= MaxSLPips."); return(INIT_FAILED); }
   if(MaxConcurrentPositions < 1)
     { Print("[SRL] REFUSING: MaxConcurrentPositions must be >= 1."); return(INIT_FAILED); }
   if(PivotLeft < 1 || PivotRight < 1)
     { Print("[SRL] REFUSING: PivotLeft/PivotRight must be >= 1."); return(INIT_FAILED); }
   if(!TradeTier1 && !TradeTier2 && !TradeTier3)
     Print("[SRL] WARNING: no tier enabled - the EA will draw levels but never trade.");

   //--- symbol metrics ------------------------------------------------
   gDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   gPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0) { Print("[SRL] REFUSING: point size is zero."); return(INIT_FAILED); }
   gPip = (PipSizeOverride > 0.0) ? PipSizeOverride
                                  : gPoint * ((gDigits == 3 || gDigits == 5) ? 10.0 : 1.0);

   //--- indicator handles ---------------------------------------------
   hIchiT  = iIchimoku(_Symbol, TrendTF, IchiTenkan, IchiKijun, IchiSenkou);
   hIchiE  = iIchimoku(_Symbol, EntryTF, IchiTenkan, IchiKijun, IchiSenkou);
   hMaT    = iMA(_Symbol, TrendTF, TrendMAPeriod,  0, MODE_SMA, PRICE_CLOSE);
   hEmaT   = iMA(_Symbol, TrendTF, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hMa200T = iMA(_Symbol, TrendTF, 200,            0, MODE_SMA, PRICE_CLOSE);
   hMaE    = iMA(_Symbol, EntryTF, TrendMAPeriod,  0, MODE_SMA, PRICE_CLOSE);
   hMaD1   = iMA(_Symbol, PERIOD_D1, TrendMAPeriod,  0, MODE_SMA, PRICE_CLOSE);
   hEmaD1  = iMA(_Symbol, PERIOD_D1, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtrP   = iATR(_Symbol, PivotTF, 14);
   hAtrE   = iATR(_Symbol, EntryTF, 14);
   if(hIchiT == INVALID_HANDLE || hIchiE == INVALID_HANDLE || hMaT == INVALID_HANDLE ||
      hEmaT == INVALID_HANDLE || hMa200T == INVALID_HANDLE || hMaE == INVALID_HANDLE ||
      hMaD1 == INVALID_HANDLE || hEmaD1 == INVALID_HANDLE || hAtrP == INVALID_HANDLE ||
      hAtrE == INVALID_HANDLE)
     { Print("[SRL] REFUSING: failed to create an indicator handle."); return(INIT_FAILED); }

   gTrade.SetExpertMagicNumber(MagicNumber);
   gTrade.SetDeviationInPoints((ulong)MathMax(1.0, MaxSlippagePips * gPip / gPoint));
   gTrade.SetTypeFillingBySymbol(_Symbol);
   gTrade.LogLevel(VerboseLog ? LOG_LEVEL_ALL : LOG_LEVEL_ERRORS);

   gHeadless = (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));

   ArrayResize(gPend, 0); ArrayResize(gPos, 0); ArrayResize(gBlocks, 0);
   for(int i = 0; i < 3; i++) { gSup[i] = -1; gRes[i] = -1; }

   ResetDayState(true);
   RefreshDailyStats();
   RefreshAllTimeStats();

   //--- pendings from a previous run are re-derived every bar, so clear
   //    them rather than guess which tier each one belonged to.
   CancelAllPendings("startup - limits are re-placed from fresh zones");
   AdoptOpenPositions();

   gLastTrendBar = 0; gLastEntryBar = 0; gLastPivotBar = 0;
   RefreshTrend(true);
   RebuildZones(true);

   PrintFormat("[SRL] Initialised. Symbol=%s Digits=%d Pip=%.5f  Trend=%s on %s  Entry=%s  "
               "Pivots=%s/%s  Tiers=%s%s%s  SL=%s buffer %.0fp/%.1fxATR [%0.f..%.0f]  TP=%s minRR %.2f  "
               "Risk=%.2f%% MaxPos=%d MaxDay=%d",
               _Symbol, gDigits, gPip, TrendModeName(), EnumToString(TrendTF),
               EntryMode == ENTRY_LIMIT ? "LIMIT" : "REJECTION",
               EnumToString(PivotTF), EnumToString(MajorPivotTF),
               TradeTier1 ? "1" : "-", TradeTier2 ? "2" : "-", TradeTier3 ? "3" : "-",
               SLMode == SL_ZONE ? "zone" : "next-level", SLBufferPips, SLBufferAtrMult,
               MinSLPips, MaxSLPips,
               (TPMode == TP_FIXED_RR && FallbackRR > 0.0)
                  ? StringFormat("fixed %.1fR, %.1fR when a level blocks it", FixedRR, FallbackRR)
                  : (ExtendToMinRR ? TPModeName() + StringFormat(", never under %.1fR", MinRR) : TPModeName()),
               MinRR,
               RiskPercent, MaxConcurrentPositions, MaxTradesPerDay);
   PrintFormat("[SRL] Sources: MA50 15M %s | MA50 4H %s | MA50 D1 %s | EMA9 4H %s | EMA9 D1 %s | "
               "MA200 4H %s | cloud 4H %s | cloud 15M %s | fib %s",
               UseMA50_M15 ? "on" : "off", UseMA50_H4 ? "on" : "off", UseMA50_D1 ? "on" : "off",
               UseEMA9_H4 ? "on" : "off", UseEMA9_D1 ? "on" : "off", UseMA200_H4 ? "on" : "off",
               UseCloud_H4 ? "on" : "off", UseCloud_M15 ? "on" : "off", UseFib ? "on" : "off");
   PrintFormat("[SRL] Day rollover %02d:00 ET (GMT%+d). Daily halt %s. Session windows %s. "
               "Spread cap %.0fp.", DayResetHourET, ETOffsetHours,
               MaxDailyLossPercent > 0 ? StringFormat("%.1f%%", MaxDailyLossPercent) : "OFF",
               StringLen(SessionWindowsGMT) > 0 ? SessionWindowsGMT : "all hours", MaxSpreadPips);
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
      Print("[SRL] *** REAL MONEY ACCOUNT *** Orders are placed automatically. Drop ",
            EmergencyStopFile, " into MQL5\\Files to halt.");
   string why = "";
   if(!AccountAllowsTrading(why))
      Print("[SRL] TRADING BLOCKED: ", why);

   ObjectsDeleteAll(0, PFX);
   gPanelRowsDrawn = 0;
   if(!gHeadless && PanelRefreshSeconds > 0) EventSetTimer(PanelRefreshSeconds);

   gLastTickMs = GetTickCount(); gInitMs = GetTickCount();
   gInitOk = true;
   WriteHeartbeat();
   if(!gHeadless) { DrawPanel(); DrawZones(); }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gHoldsLock && SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     { GlobalVariableDel(LockName()); gHoldsLock = false; }
   if(!gHeadless) { ObjectsDeleteAll(0, PFX); ChartRedraw(); }
   int hs[10]; hs[0]=hIchiT; hs[1]=hIchiE; hs[2]=hMaT; hs[3]=hEmaT; hs[4]=hMa200T;
   hs[5]=hMaE; hs[6]=hMaD1; hs[7]=hEmaD1; hs[8]=hAtrP; hs[9]=hAtrE;
   for(int i = 0; i < 10; i++) if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
  }

void OnTimer()
  {
   if(!gInitOk || gHeadless) return;
   TouchLock();
   WriteHeartbeat();
   uint now = GetTickCount();
   if(gLastPanelMs == 0 || (now - gLastPanelMs) > 300)
     { DrawPanel(); gLastPanelMs = now; }
  }

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!gInitOk) return;
   gLastTickMs = GetTickCount();
   gPhase = "TICK";
   TouchLock();

   if(IsNewDay())
     {
      ResetDayState(false);
      gLastStatsMs = 0;
     }

   gPhase = "INDICATORS";
   bool newTrendBar = RefreshTrend(false);
   bool newEntryBar = RefreshEntry(false);
   if(newEntryBar) gEntryBarCount++;

   //--- zones: pivots change on their own bar, MAs and fibs drift every
   //    entry bar, so rebuild on every entry bar. It is a few hundred
   //    CopyRates calls every 15 minutes, nothing on tick.
   if(newEntryBar || gZonesBuiltAt == 0)
     { gPhase = "ZONES"; RebuildZones(false); }

   uint nowMs = GetTickCount();
   if(newEntryBar || gLastStatsMs == 0 || (nowMs - gLastStatsMs) > 15000)
     { gPhase = "DAILY_STATS"; RefreshDailyStats(); gLastStatsMs = nowMs; }

   //--- trend flip housekeeping
   if(gTrendDir != gTrendPrev)
     {
      if(gTrendPrev != 0 || gTrendDir != 0)
         PrintFormat("[SRL] 4H side changed: %s -> %s  (%s)", DirName(gTrendPrev),
                     DirName(gTrendDir), gTrendText);
      if(CancelOnTrendFlip) CancelAllPendings("4H side changed");
      if(CloseOnTrendFlip && gTrendPrev != 0) CloseAllPositions("4H side changed");
      gTrendPrev = gTrendDir;
     }

   gPhase = "SYNC_STOPS";
   SyncPositionStops();

   if(newEntryBar)
     {
      gPhase = "HOUSEKEEP";
      AgePendings();
      PruneBlocks();
      PrunePosRecs();
     }

   gPhase = "EVALUATE";
   EvaluateAndAct(newEntryBar);

   if(!gHeadless && (newEntryBar || gLastPanelMs == 0 || (nowMs - gLastPanelMs) > 300))
     { gPhase = "DRAW"; DrawPanel(); if(newEntryBar || gLastPanelMs == 0) DrawZones(); gLastPanelMs = nowMs; }
  }

//+------------------------------------------------------------------+
//| Small helpers                                                      |
//+------------------------------------------------------------------+
bool CopyOne(const int handle, const int buffer, const int shift, double &out)
  {
   double tmp[]; ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, buffer, shift, 1, tmp) < 1) return(false);
   if(tmp[0] == EMPTY_VALUE || !MathIsValidNumber(tmp[0])) return(false);
   out = tmp[0];
   return(true);
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);          // "PERIOD_M15"
   return(StringSubstr(s, 7));
  }

string DirName(const int d) { return(d == 2 ? "BOTH" : (d > 0 ? "BUY" : (d < 0 ? "SELL" : "NONE"))); }

string TrendModeName()
  {
   switch(TrendMode)
     {
      case TREND_CLOUD_AND_MA: return("cloud+MA50");
      case TREND_CLOUD_ONLY:   return("cloud");
      case TREND_MA_ONLY:      return("MA50");
      case TREND_NONE:         return("NONE - both sides");
      default:                 return("EMA9/MA50 stack");
     }
  }

string TPModeName()
  {
   switch(TPMode)
     {
      case TP_R1_S1:    return("R1/S1");
      case TP_NEXT_ZONE:return("next zone");
      default:          return(StringFormat("fixed %.1fR", FixedRR));
     }
  }

double CurrentSpreadPips()
  {
   return((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / gPip);
  }

double SnapToTick(const double price)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return(NormalizeDouble(price, gDigits));
   return(NormalizeDouble(MathRound(price / ts) * ts, gDigits));
  }

void SetStatus(const string s, const string detail, const color clr)
  {
   if(VerboseLog && (s != gStatus || detail != gStatusDetail))
      PrintFormat("[SRL] %s - %s", s, detail);
   gStatus = s; gStatusDetail = detail; gStatusColor = clr;
  }

//+------------------------------------------------------------------+
//| Indicator refresh - closed bars only                               |
//+------------------------------------------------------------------+
//--- 4H side. Returns true on a new trend bar.
bool RefreshTrend(const bool force)
  {
   datetime tBar = iTime(_Symbol, TrendTF, 0);
   if(!force && tBar == gLastTrendBar) return(false);
   double c[];
   if(CopyClose(_Symbol, TrendTF, 1, 1, c) == 1 &&
      CopyOne(hIchiT, 2, 1, gTSenA) && CopyOne(hIchiT, 3, 1, gTSenB) &&
      CopyOne(hMaT, 0, 1, gTMa) && CopyOne(hEmaT, 0, 1, gTEma))
     {
      gTClose = c[0];
      CopyOne(hMa200T, 0, 1, gTMa200);     // optional: 200 bars may not exist yet
      double top = MathMax(gTSenA, gTSenB), bot = MathMin(gTSenA, gTSenB);
      int cloud = (gTClose > top) ? 1 : ((gTClose < bot) ? -1 : 0);
      int ma    = (gTClose > gTMa) ? 1 : ((gTClose < gTMa) ? -1 : 0);
      int stack = (gTEma > gTMa && gTClose > gTEma) ? 1
                : ((gTEma < gTMa && gTClose < gTEma) ? -1 : 0);
      int dir = 0;
      switch(TrendMode)
        {
         case TREND_CLOUD_AND_MA: dir = (cloud == ma) ? cloud : 0; break;
         case TREND_CLOUD_ONLY:   dir = cloud; break;
         case TREND_MA_ONLY:      dir = ma;    break;
         case TREND_NONE:         dir = 2;     break;   // "both sides"
         default:                 dir = stack; break;
        }
      gTrendDir  = dir;
      gTrendText = StringFormat("close %.2f  cloud %.2f/%.2f (%s)  MA50 %.2f (%s)  EMA9 %.2f",
                                gTClose, bot, top,
                                cloud > 0 ? "above" : (cloud < 0 ? "below" : "inside"),
                                gTMa, ma > 0 ? "above" : "below", gTEma);
      gLastTrendBar = tBar;
      gStaleTrend = 0;
      return(!force);
     }
   gStaleTrend++;
   return(false);
  }

//--- entry-TF values: ATRs, the 15M cloud and MA, the D1 MAs. Returns
//    true on a new entry bar (never on the forced first read).
bool RefreshEntry(const bool force)
  {
   datetime eBar = iTime(_Symbol, EntryTF, 0);
   if(!force && eBar == gLastEntryBar) return(false);
   bool ok = CopyOne(hAtrE, 0, 1, gAtrE) && CopyOne(hAtrP, 0, 1, gAtrP);
   if(ok)
     {
      CopyOne(hIchiE, 2, 1, gESenA); CopyOne(hIchiE, 3, 1, gESenB);
      CopyOne(hMaE, 0, 1, gEMa);
      CopyOne(hMaD1, 0, 1, gMaD1);  CopyOne(hEmaD1, 0, 1, gEmaD1);
      bool isNew = (!force && gLastEntryBar != 0);
      gLastEntryBar = eBar;
      gStaleEntry = 0;
      return(isNew);
     }
   gStaleEntry++;
   return(false);
  }

//+------------------------------------------------------------------+
//| LEVEL COLLECTION                                                   |
//+------------------------------------------------------------------+
void AddPoint(const double price, const double weight, const string tag, const datetime t)
  {
   if(price <= 0.0 || weight <= 0.0) return;
   int n = ArraySize(gPoints);
   ArrayResize(gPoints, n + 1);
   gPoints[n].price = price; gPoints[n].weight = weight;
   gPoints[n].tag = tag;     gPoints[n].t = t;
  }

//--- Swing highs and lows on one timeframe. A bar is a swing high when
//    its high beats PivotRight newer bars strictly and PivotLeft older
//    bars at least as strictly; mirrored for lows. Older swings are
//    down-weighted a little so a fresh level outranks a month-old one
//    at equal confluence.
void CollectPivots(const ENUM_TIMEFRAMES tf, const int lookback, const double weight,
                   const string tag)
  {
   MqlRates r[]; ArraySetAsSeries(r, true);
   int need = lookback + PivotLeft + PivotRight + 2;
   int got  = CopyRates(_Symbol, tf, 1, need, r);
   if(got < PivotLeft + PivotRight + 3) return;
   for(int i = PivotRight; i < got - PivotLeft; i++)
     {
      bool hi = true, lo = true;
      for(int k = 1; k <= PivotRight && (hi || lo); k++)
        {
         if(r[i - k].high >= r[i].high) hi = false;
         if(r[i - k].low  <= r[i].low)  lo = false;
        }
      for(int k = 1; k <= PivotLeft && (hi || lo); k++)
        {
         if(r[i + k].high > r[i].high) hi = false;
         if(r[i + k].low  < r[i].low)  lo = false;
        }
      if(!hi && !lo) continue;
      double w = weight * (0.6 + 0.4 * (1.0 - (double)i / (double)got));
      if(hi) AddPoint(r[i].high, w, tag, r[i].time);
      if(lo) AddPoint(r[i].low,  w, tag, r[i].time);
     }
  }

//--- Fib retracement of the last swing on the trend TF: the highest
//    high and lowest low of the last FibSwingBars closed bars. Whichever
//    came LAST is the end of the swing, and the retracement levels sit
//    between it and the other extreme - the way the coach draws it.
void CollectFib()
  {
   MqlRates r[]; ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, TrendTF, 1, FibSwingBars, r);
   if(got < 10) return;
   int iHi = 0, iLo = 0;
   for(int i = 1; i < got; i++)
     {
      if(r[i].high > r[iHi].high) iHi = i;
      if(r[i].low  < r[iLo].low)  iLo = i;
     }
   gFibHi = r[iHi].high; gFibLo = r[iLo].low;
   gFibDirUp = (iHi < iLo) ? 1 : -1;       // high more recent -> swing up
   double range = gFibHi - gFibLo;
   if(range <= 0.0) return;
   double ratios[4] = {0.382, 0.5, 0.618, 0.786};
   for(int k = 0; k < 4; k++)
     {
      double p = (gFibDirUp > 0) ? gFibHi - range * ratios[k] : gFibLo + range * ratios[k];
      AddPoint(p, FibWeight, StringFormat("fib %.3f", ratios[k]), 0);
     }
  }

//+------------------------------------------------------------------+
//| ZONE BUILD + RANK                                                  |
//+------------------------------------------------------------------+
double MergeWidth()
  {
   if(ZoneMergePips > 0.0) return(ZoneMergePips * gPip);
   if(gAtrP > 0.0) return(ZoneMergeAtrMult * gAtrP);
   return(150.0 * gPip);
  }

void RebuildZones(const bool force)
  {
   ArrayResize(gPoints, 0);
   string eN = TfName(EntryTF), tN = TfName(TrendTF);

   CollectPivots(PivotTF, PivotLookback, PivotWeight, "piv " + TfName(PivotTF));
   CollectPivots(MajorPivotTF, MajorPivotLookback, MajorPivotWeight, "piv " + TfName(MajorPivotTF));
   if(UseMA50_M15) AddPoint(gEMa,   MAWeight, StringFormat("MA%d %s", TrendMAPeriod, eN), 0);
   if(UseMA50_H4)  AddPoint(gTMa,   MAWeight, StringFormat("MA%d %s", TrendMAPeriod, tN), 0);
   if(UseMA50_D1)  AddPoint(gMaD1,  MAWeight, StringFormat("MA%d D1", TrendMAPeriod), 0);
   if(UseEMA9_H4)  AddPoint(gTEma,  MAWeight, StringFormat("EMA%d %s", TrendEMAPeriod, tN), 0);
   if(UseEMA9_D1)  AddPoint(gEmaD1, MAWeight, StringFormat("EMA%d D1", TrendEMAPeriod), 0);
   if(UseMA200_H4 && gTMa200 > 0.0) AddPoint(gTMa200, MAWeight, "MA200 " + tN, 0);
   if(UseCloud_H4)  { AddPoint(gTSenA, CloudWeight, "kumo " + tN, 0); AddPoint(gTSenB, CloudWeight, "kumo " + tN, 0); }
   if(UseCloud_M15) { AddPoint(gESenA, CloudWeight, "kumo " + eN, 0); AddPoint(gESenB, CloudWeight, "kumo " + eN, 0); }
   if(UseFib) CollectFib();

   int n = ArraySize(gPoints);
   ArrayResize(gZones, 0);
   for(int i = 0; i < 3; i++) { gSup[i] = -1; gRes[i] = -1; }
   gNSup = 0; gNRes = 0;
   if(n == 0) { gZonesBuiltAt = TimeCurrent(); return; }

   //--- sort by price (index sort; n is a few hundred at most)
   int idx[]; ArrayResize(idx, n);
   for(int i = 0; i < n; i++) idx[i] = i;
   for(int i = 1; i < n; i++)
     {
      int v = idx[i]; int j = i - 1;
      while(j >= 0 && gPoints[idx[j]].price > gPoints[v].price) { idx[j + 1] = idx[j]; j--; }
      idx[j + 1] = v;
     }

   //--- greedy clustering: join while the gap to the previous point is
   //    under one width AND the cluster stays under two widths tall, so a
   //    long chain of MAs cannot smear into one giant zone.
   double w = MergeWidth();
   int start = 0;
   while(start < n)
     {
      int end = start;
      double lo = gPoints[idx[start]].price;
      while(end + 1 < n)
        {
         double nxt = gPoints[idx[end + 1]].price;
         if(nxt - gPoints[idx[end]].price > w) break;
         if(nxt - lo > 2.0 * w) break;
         end++;
        }
      Zone z;
      z.top = gPoints[idx[end]].price; z.bottom = lo;
      z.score = 0; z.points = 0; z.tags = ""; z.firstT = 0;
      for(int k = start; k <= end; k++)
        {
         LevelPoint p = gPoints[idx[k]];
         z.score += p.weight; z.points++;
         if(p.t > 0 && (z.firstT == 0 || p.t < z.firstT)) z.firstT = p.t;
         if(StringFind(z.tags, p.tag) < 0)
            z.tags += (z.tags == "" ? "" : ", ") + p.tag;
        }
      //--- a single-point zone still needs some height to be touched
      double minH = MathMax(2.0 * gPip, 0.25 * w);
      if(z.top - z.bottom < minH)
        { double mid = 0.5 * (z.top + z.bottom); z.top = mid + 0.5 * minH; z.bottom = mid - 0.5 * minH; }
      int zi = ArraySize(gZones); ArrayResize(gZones, zi + 1); gZones[zi] = z;
      start = end + 1;
     }

   RankZones();
   gZonesBuiltAt = TimeCurrent();
   gZonesVersion++;
   if(VerboseLog || force)
      PrintFormat("[SRL] Zones rebuilt: %d points -> %d zones (merge %.0fp). S: %s | R: %s",
                  n, ArraySize(gZones), w / gPip, TierText(-1), TierText(+1));
  }

//--- the three nearest qualifying zones each side of the market
void RankZones()
  {
   double mid = 0.5 * (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double minD = MinZoneDistancePips * gPip, maxD = MaxZoneDistancePips * gPip;
   int nz = ArraySize(gZones);
   bool used[]; ArrayResize(used, nz); ArrayInitialize(used, false);
   gNSup = 0; gNRes = 0;
   for(int i = 0; i < 3; i++) { gSup[i] = -1; gRes[i] = -1; }
   for(int t = 0; t < 3; t++)
     {
      int best = -1;
      for(int i = 0; i < nz; i++)
        {
         if(used[i] || gZones[i].score < ZoneMinScore) continue;
         if(gZones[i].top > mid - minD || gZones[i].bottom < mid - maxD) continue;
         if(best < 0 || gZones[i].top > gZones[best].top) best = i;
        }
      if(best < 0) break;
      used[best] = true; gSup[t] = best; gNSup++;
     }
   for(int t = 0; t < 3; t++)
     {
      int best = -1;
      for(int i = 0; i < nz; i++)
        {
         if(used[i] || gZones[i].score < ZoneMinScore) continue;
         if(gZones[i].bottom < mid + minD || gZones[i].top > mid + maxD) continue;
         if(best < 0 || gZones[i].bottom < gZones[best].bottom) best = i;
        }
      if(best < 0) break;
      used[best] = true; gRes[t] = best; gNRes++;
     }
  }

string TierText(const int side)
  {
   string s = "";
   for(int t = 0; t < 3; t++)
     {
      int zi = (side > 0) ? gRes[t] : gSup[t];
      if(zi < 0) continue;
      s += StringFormat("%s%d %.2f-%.2f (%.1f)", side > 0 ? "R" : "S", t + 1,
                        gZones[zi].bottom, gZones[zi].top, gZones[zi].score);
      s += "  ";
     }
   return(s == "" ? "none" : s);
  }

//+------------------------------------------------------------------+
//| GATES                                                              |
//+------------------------------------------------------------------+
bool AccountAllowsTrading(string &why)
  {
   why = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { why = "Algo Trading button is OFF";      return(false); }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           { why = "Algo Trading off in EA properties"; return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   { why = "broker disabled trading";          return(false); }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))    { why = "broker disabled EAs";              return(false); }
   return(true);
  }

bool FreeMarginOK()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0) return(false);
   return((AccountInfoDouble(ACCOUNT_MARGIN_FREE) / eq * 100.0) >= MinFreeMarginPercent);
  }

//--- "HH:MM-HH:MM,HH:MM-HH:MM" in GMT. Empty spec = always inside.
bool InSessionWindow()
  {
   if(StringLen(SessionWindowsGMT) == 0) return(true);
   MqlDateTime g; TimeToStruct(TimeGMT(), g);
   int nowM = g.hour * 60 + g.min;
   string parts[]; int n = StringSplit(SessionWindowsGMT, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i]; StringTrimLeft(p); StringTrimRight(p);
      string ab[]; if(StringSplit(p, '-', ab) != 2) continue;
      string h1[], h2[];
      if(StringSplit(ab[0], ':', h1) != 2 || StringSplit(ab[1], ':', h2) != 2) continue;
      int a = (int)StringToInteger(h1[0]) * 60 + (int)StringToInteger(h1[1]);
      int b = (int)StringToInteger(h2[0]) * 60 + (int)StringToInteger(h2[1]);
      if(a <= b) { if(nowM >= a && nowM < b) return(true); }
      else       { if(nowM >= a || nowM < b) return(true); }   // wraps midnight
     }
   return(false);
  }

bool IsFridayCutoff()
  {
   if(AllowFridayLate) return(false);
   MqlDateTime g; TimeToStruct(TimeGMT(), g);
   return(g.day_of_week == 5 && g.hour >= FridayCutoffHour);
  }

//+------------------------------------------------------------------+
//| Core decision                                                      |
//+------------------------------------------------------------------+
void EvaluateAndAct(const bool newEntryBar)
  {
   if(!gHeadless)
     {
      uint nowChk = GetTickCount();
      if(gLastStopChkMs == 0 || (nowChk - gLastStopChkMs) > 500)
        { gStopFilePresent = FileIsExist(EmergencyStopFile); gLastStopChkMs = nowChk; }
     }
   if(gStopFilePresent)
     { SetStatus("HALTED", "kill-switch file present", clrRed); CancelAllPendings("kill switch"); return; }

   string why = "";
   if(!AccountAllowsTrading(why)) { SetStatus("BLOCKED", why, clrRed); return; }

   if(gStaleTrend > 3 || gStaleEntry > 3)
     {
      SetStatus("BLOCKED", StringFormat("stale indicator data (%d/%d)", gStaleTrend, gStaleEntry), clrRed);
      CancelAllPendings("stale indicator data");
      return;
     }
   if(MaxDailyLossPercent > 0.0 && gDayStartBalance > 0.0 &&
      gDayPL <= -MathAbs(gDayStartBalance * MaxDailyLossPercent / 100.0))
     {
      SetStatus("HALTED", StringFormat("daily stop %.2f / -%.1f%%", gDayPL, MaxDailyLossPercent), clrRed);
      CancelAllPendings("daily loss stop"); return;
     }
   if(MaxTradesPerDay > 0 && gDayTrades >= MaxTradesPerDay)
     {
      SetStatus("DAY CAP", StringFormat("%d/%d fills today", gDayTrades, MaxTradesPerDay), clrOrange);
      CancelAllPendings("daily fill cap reached"); return;
     }
   if(!InSessionWindow())
     { SetStatus("SESSION", "outside " + SessionWindowsGMT + " GMT", clrOrange); CancelAllPendings("outside session"); return; }
   if(IsFridayCutoff())
     { SetStatus("FRIDAY", "late-Friday cutoff", clrOrange); CancelAllPendings("Friday cutoff"); return; }
   if(gTrendDir == 0)
     { SetStatus("NO SIDE", "4H inside the cloud or MA disagrees", clrSilver); return; }
   if(!FreeMarginOK())
     { SetStatus("PAUSED", "free margin below floor", clrOrange); return; }
   //--- a spread spike must not tear down resting limits, only stop new ones
   if(CurrentSpreadPips() > MaxSpreadPips)
     { SetStatus("SPREAD", StringFormat("%.0fp > %.0fp cap", CurrentSpreadPips(), MaxSpreadPips), clrOrange); return; }

   //--- gTrendDir == 2 means TREND_NONE: both sides are live at once
   if(EntryMode == ENTRY_LIMIT)
     {
      if(gLimitsVersion != gZonesVersion)
        {
         if(gTrendDir == 2) { ManageLimits(+1); ManageLimits(-1); }
         else ManageLimits(gTrendDir);
         gLimitsVersion = gZonesVersion;
        }
     }
   else if(newEntryBar)
     {
      if(gTrendDir == 2) { EvaluateRejection(+1); EvaluateRejection(-1); }
      else EvaluateRejection(gTrendDir);
     }
  }

//+------------------------------------------------------------------+
//| GEOMETRY                                                           |
//+------------------------------------------------------------------+
double StopBuffer() { return(MathMax(SLBufferPips * gPip, SLBufferAtrMult * gAtrE)); }

//--- SL and TP for a trade of direction dir entering at 'entry' off zone z
//    (tier index t, 0-based). Returns false with a reason when the trade
//    should not be taken.
bool Geometry(const int dir, const double entry, const int t, const Zone &z,
              double &sl, double &tp, string &why)
  {
   why = "";
   double buf = StopBuffer();
   double slRaw = (dir > 0) ? z.bottom - buf : z.top + buf;
   if(SLMode == SL_NEXT_LEVEL && t < 2)
     {
      int nx = (dir > 0) ? gSup[t + 1] : gRes[t + 1];
      if(nx >= 0) slRaw = (dir > 0) ? gZones[nx].bottom - buf : gZones[nx].top + buf;
     }
   double dist = MathAbs(entry - slRaw);
   if(dist < MinSLPips * gPip) { slRaw = entry - dir * MinSLPips * gPip; dist = MinSLPips * gPip; }
   if(dist > MaxSLPips * gPip)
     { why = StringFormat("stop %.0fp wider than %.0fp cap", dist / gPip, MaxSLPips); return(false); }

   double tpRaw = 0.0; string tgt = "";
   gTpNote = "";
   if(TPMode == TP_FIXED_RR)
     {
      double mult = FixedRR;
      gTpNote = StringFormat("%.1fR", FixedRR);
      if(FallbackRR > 0.0 && FallbackRR < FixedRR)
        {
         int bz = -1;
         for(int i = 0; i < ArraySize(gZones); i++)
           {
            if(gZones[i].score < ZoneMinScore) continue;
            if(dir > 0 && gZones[i].bottom > entry + MinZoneDistancePips * gPip &&
               (bz < 0 || gZones[i].bottom < gZones[bz].bottom)) bz = i;
            if(dir < 0 && gZones[i].top < entry - MinZoneDistancePips * gPip &&
               (bz < 0 || gZones[i].top > gZones[bz].top)) bz = i;
           }
         if(bz >= 0)
           {
            double barrier = (dir > 0) ? gZones[bz].bottom - TPBufferPips * gPip
                                       : gZones[bz].top + TPBufferPips * gPip;
            if((barrier - entry) * dir < FixedRR * dist)
              {
               mult = FallbackRR;
               gTpNote = StringFormat("%.1fR (level %.2f-%.2f blocks %.1fR)", FallbackRR,
                                      gZones[bz].bottom, gZones[bz].top, FixedRR);
              }
           }
        }
      tpRaw = entry + dir * mult * dist; tgt = "fixed";
     }
   else
     {
      int zi = -1;
      if(TPMode == TP_R1_S1) zi = (dir > 0) ? gRes[0] : gSup[0];
      else
        {
         for(int i = 0; i < ArraySize(gZones); i++)
           {
            if(gZones[i].score < ZoneMinScore) continue;
            if(dir > 0 && gZones[i].bottom > entry + MinZoneDistancePips * gPip &&
               (zi < 0 || gZones[i].bottom < gZones[zi].bottom)) zi = i;
            if(dir < 0 && gZones[i].top < entry - MinZoneDistancePips * gPip &&
               (zi < 0 || gZones[i].top > gZones[zi].top)) zi = i;
           }
        }
      if(zi >= 0)
        {
         tpRaw = (dir > 0) ? gZones[zi].bottom - TPBufferPips * gPip
                           : gZones[zi].top + TPBufferPips * gPip;
         tgt = StringFormat("%.2f-%.2f", gZones[zi].bottom, gZones[zi].top);
        }
      if(zi < 0 || (tpRaw - entry) * dir <= 0.0)
        {
         if(!FallbackToFixedRR) { why = "no level to target"; return(false); }
         tpRaw = entry + dir * FixedRR * dist; tgt = "fixed (no level)";
        }
     }
   double rr = MathAbs(tpRaw - entry) / dist;
   if(TPMode != TP_FIXED_RR)
      gTpNote = StringFormat("level %s (%.1fR)", tgt, rr);
   if(rr < MinRR)
     {
      if(TPMode == TP_FIXED_RR || !ExtendToMinRR)
        { why = StringFormat("RR %.2f to %s below %.2f floor", rr, tgt, MinRR); return(false); }
      //--- v1.5: the level is too close for the floor, so the floor wins
      tpRaw = entry + dir * MinRR * dist;
      gTpNote = StringFormat("%.1fR floor (level %s was only %.1fR)", MinRR, tgt, rr);
     }
   sl = SnapToTick(slRaw); tp = SnapToTick(tpRaw);
   return(true);
  }

//+------------------------------------------------------------------+
//| LOT SIZING (TrendEMA rules: round down, hard ceiling, lot cap)     |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
  {
   if(step >= 1.0) return(0);
   if(step >= 0.1) return(1);
   if(step >= 0.01) return(2);
   return(3);
  }

double CalcLot(const double slDistance, double &riskPctOut, string &reason)
  {
   riskPctOut = 0.0; reason = "";
   double capital = SizeFromEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   if(capital <= 0.0) { reason = "capital is zero"; return(0.0); }
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSz <= 0.0) { reason = "tick value/size unavailable"; return(0.0); }
   double lossPerLot = (slDistance / tickSz) * tickVal;
   if(lossPerLot <= 0.0) { reason = "loss per lot is zero"; return(0.0); }
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   int vd = VolumeDigits(step);
   double lot;
   if(UseFixedLot)
      lot = NormalizeDouble(MathFloor(FixedLotSize / step) * step, vd);
   else
      lot = NormalizeDouble(MathFloor((capital * RiskPercent / 100.0) / lossPerLot / step) * step, vd);
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(MaxLotSizeCap > 0.0 && lot > MaxLotSizeCap) lot = MaxLotSizeCap;
   lot = NormalizeDouble(lot, vd);
   if(lot <= 0.0) { reason = "computed lot is zero"; return(0.0); }
   riskPctOut = (lot * lossPerLot) / capital * 100.0;
   if(!UseFixedLot && riskPctOut > MaxRiskPercent + 0.0001)
     { reason = StringFormat("risk %.2f%% exceeds %.2f%% ceiling", riskPctOut, MaxRiskPercent); return(0.0); }
   double margin = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { reason = "insufficient free margin"; return(0.0); }
   return(lot);
  }

//+------------------------------------------------------------------+
//| ZONE BLOCKS - do not chase a zone just traded, or one that lost    |
//+------------------------------------------------------------------+
void AddBlock(const double top, const double bottom, const int bars, const string why)
  {
   int n = ArraySize(gBlocks); ArrayResize(gBlocks, n + 1);
   gBlocks[n].top = top; gBlocks[n].bottom = bottom;
   gBlocks[n].untilBar = gEntryBarCount + bars; gBlocks[n].why = why;
  }

bool ZoneBlocked(const Zone &z, string &why)
  {
   for(int i = 0; i < ArraySize(gBlocks); i++)
     {
      if(gEntryBarCount >= gBlocks[i].untilBar) continue;
      if(z.top < gBlocks[i].bottom || z.bottom > gBlocks[i].top) continue;
      why = StringFormat("%s (%d bars left)", gBlocks[i].why, gBlocks[i].untilBar - gEntryBarCount);
      return(true);
     }
   return(false);
  }

void PruneBlocks()
  {
   for(int i = ArraySize(gBlocks) - 1; i >= 0; i--)
      if(gEntryBarCount >= gBlocks[i].untilBar) ArrayRemove(gBlocks, i, 1);
  }

//+------------------------------------------------------------------+
//| PENDING ORDERS                                                     |
//+------------------------------------------------------------------+
//--- Pendings are matched to zones by PRICE OVERLAP, not by tier label.
//    The first backtest re-ranked the same zone from R2 to R1 every time a
//    nearer zone dissolved, and a tier-keyed lookup cancelled the R2 limit
//    and placed an identical R1 limit at the same price: 449 needless
//    cancel/re-place pairs in eight months, each a brief window with no
//    order resting. The zone is the thing being traded; the label is
//    just its rank today.
int FindPendingByZone(const int dir, const Zone &z, const bool &claimed[])
  {
   for(int i = 0; i < ArraySize(gPend); i++)
     {
      if(claimed[i] || gPend[i].dir != dir) continue;
      if(z.top < gPend[i].bottom || z.bottom > gPend[i].top) continue;
      return(i);
     }
   return(-1);
  }

bool PendingAlive(const ulong ticket) { return(OrderSelect(ticket)); }

int CountOurPendings()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      c++;
     }
   return(c);
  }

void CancelPendingRec(const int i, const string why)
  {
   if(i < 0 || i >= ArraySize(gPend)) return;
   ulong t = gPend[i].ticket;
   if(PendingAlive(t))
     {
      if(gTrade.OrderDelete(t))
         PrintFormat("[SRL] Cancelled %s%d limit #%I64u: %s", gPend[i].dir > 0 ? "S" : "R", gPend[i].tier, t, why);
      else
         PrintFormat("[SRL] Cancel #%I64u failed (%d): %s", t, gTrade.ResultRetcode(), gTrade.ResultComment());
     }
   ArrayRemove(gPend, i, 1);
  }

void CancelAllPendings(const string why)
  {
   for(int i = ArraySize(gPend) - 1; i >= 0; i--) CancelPendingRec(i, why);
   //--- and anything with our magic we do not remember (previous run)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(gTrade.OrderDelete(t)) PrintFormat("[SRL] Cancelled untracked #%I64u: %s", t, why);
     }
  }

//--- once per entry bar: drop records whose order is gone, expire old ones
void AgePendings()
  {
   for(int i = ArraySize(gPend) - 1; i >= 0; i--)
     {
      if(!PendingAlive(gPend[i].ticket)) { ArrayRemove(gPend, i, 1); continue; }
      gPend[i].bars++;
      if(gPend[i].bars > PendingExpiryBars)
         CancelPendingRec(i, StringFormat("unfilled for %d bars", gPend[i].bars));
     }
  }

//+------------------------------------------------------------------+
//| LIMIT MODE - one resting limit per enabled tier                    |
//+------------------------------------------------------------------+
double LimitEntry(const int dir, const Zone &z)
  {
   double near = (dir > 0) ? z.top : z.bottom;
   double far  = (dir > 0) ? z.bottom : z.top;
   double p;
   switch(LimitPlacement)
     {
      case PLACE_MID:      p = 0.5 * (near + far); break;
      case PLACE_FAR_EDGE: p = far;                break;
      default:             p = near;               break;
     }
   p -= dir * LimitOffsetPips * gPip;
   return(SnapToTick(p));
  }

void ManageLimits(const int dir)
  {
   //--- the tester and the broker both refuse orders in the daily break;
   //    run 1 logged 87 "Market closed" failures at 19:15-21:00 server time
   if(!MarketSessionOpen()) { SetStatus("CLOSED", "outside quote session", clrSilver); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * gPoint;
   string state = "";

   //--- drop records whose order is gone before matching
   for(int i = ArraySize(gPend) - 1; i >= 0; i--)
      if(!PendingAlive(gPend[i].ticket)) ArrayRemove(gPend, i, 1);
   bool claimed[]; ArrayResize(claimed, ArraySize(gPend)); ArrayInitialize(claimed, false);

   for(int t = 0; t < 3; t++)
     {
      bool enabled = (t == 0 && TradeTier1) || (t == 1 && TradeTier2) || (t == 2 && TradeTier3);
      if(!enabled) continue;
      int zi = (dir > 0) ? gSup[t] : gRes[t];
      string tname = StringFormat("%s%d", dir > 0 ? "S" : "R", t + 1);
      if(zi < 0) { state += tname + " none  "; continue; }
      Zone z = gZones[zi];
      int ex = FindPendingByZone(dir, z, claimed);
      if(ex >= 0) { claimed[ex] = true; gPend[ex].tier = t + 1; }
      string why = "";
      if(ZoneBlocked(z, why)) { if(ex >= 0) { CancelPendingRec(ex, why); ArrayRemove(claimed, ex, 1); } state += tname + " blocked  "; continue; }

      double entry = LimitEntry(dir, z);
      //--- a limit must rest on the far side of the market from the fill
      if((dir > 0 && entry > ask - stops) || (dir < 0 && entry < bid + stops))
        { if(ex >= 0) { CancelPendingRec(ex, "price already at the zone"); ArrayRemove(claimed, ex, 1); } state += tname + " at mkt  "; continue; }

      double sl = 0, tp = 0;
      if(!Geometry(dir, entry, t, z, sl, tp, why))
        {
         if(ex >= 0) { CancelPendingRec(ex, why); ArrayRemove(claimed, ex, 1); }
         string key = tname + why;
         if(key != gLastRejectKey) { gLastRejectKey = key; PrintFormat("[SRL] %s skipped: %s", tname, why); }
         state += tname + " no-geo  "; continue;
        }

      if(ex >= 0)
        {
         PendingRec p = gPend[ex];
         //--- OrderGetDouble reads the LAST selected order, which after the
         //    cleanup loop above is whichever ticket was checked last
         if(!OrderSelect(p.ticket)) { ArrayRemove(gPend, ex, 1); ArrayRemove(claimed, ex, 1); ex = -1; }
         else
           {
            double curPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            double curSl    = OrderGetDouble(ORDER_SL);
            double curTp    = OrderGetDouble(ORDER_TP);
            bool moved = MathAbs(curPrice - entry) > RepricePips * gPip ||
                         MathAbs(curSl - sl) > RepricePips * gPip ||
                         MathAbs(curTp - tp) > RepricePips * gPip;
            if(moved)
              {
               if(gTrade.OrderModify(p.ticket, entry, sl, tp, ORDER_TIME_GTC, 0))
                 {
                  gPend[ex].top = z.top; gPend[ex].bottom = z.bottom;
                  gPend[ex].slPips = MathAbs(entry - sl) / gPip; gPend[ex].tpPips = MathAbs(tp - entry) / gPip;
                  if(VerboseLog) PrintFormat("[SRL] %s limit re-priced to %.2f SL %.2f TP %.2f", tname, entry, sl, tp);
                 }
               else
                  PrintFormat("[SRL] %s re-price failed (%d): %s", tname, gTrade.ResultRetcode(), gTrade.ResultComment());
              }
            state += tname + " resting  ";
            continue;
           }
        }

      //--- capacity for a NEW limit
      int open = CountPositions(), pend = CountOurPendings();
      if(open + pend >= MaxConcurrentPositions) { state += tname + " cap  "; continue; }
      if(MaxTradesPerDay > 0 && gDayTrades + pend >= MaxTradesPerDay) { state += tname + " daycap  "; continue; }
      if(BlockOpposingEntries && HasOpposingPosition(dir)) { state += tname + " opposed  "; continue; }

      double riskPct = 0.0;
      double lot = CalcLot(MathAbs(entry - sl), riskPct, why);
      if(lot <= 0.0) { SetStatus("REJECT", why, clrRed); state += tname + " no-lot  "; continue; }

      string comment = StringFormat("%s-%s", TradeCommentPrefix, tname);
      bool ok = (dir > 0) ? gTrade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment)
                          : gTrade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
      if(ok && gTrade.ResultOrder() > 0)
        {
         int n = ArraySize(gPend); ArrayResize(gPend, n + 1);
         gPend[n].ticket = gTrade.ResultOrder(); gPend[n].tier = t + 1; gPend[n].dir = dir;
         gPend[n].top = z.top; gPend[n].bottom = z.bottom;
         gPend[n].slPips = MathAbs(entry - sl) / gPip; gPend[n].tpPips = MathAbs(tp - entry) / gPip;
         gPend[n].bars = 0;
         //--- keep the claim list the same length as gPend, or the next
         //    tier's lookup reads past its end (array out of range halted
         //    the very first batch run after four trades)
         ArrayResize(claimed, n + 1); claimed[n] = true;
         PrintFormat("[SRL] %s LIMIT %s @ %.2f  zone %.2f-%.2f score %.1f [%s]  lot %.2f risk %.2f%%  "
                     "SL %.2f (%.0fp)  TP %.2f (%.0fp)  RR %.2f  target %s",
                     dir > 0 ? "BUY" : "SELL", tname, entry, z.bottom, z.top, z.score, z.tags,
                     lot, riskPct, sl, gPend[n].slPips, tp, gPend[n].tpPips,
                     gPend[n].tpPips / MathMax(gPend[n].slPips, 1.0), gTpNote == "" ? "level" : gTpNote);
         state += tname + " placed  ";
        }
      else
        {
         PrintFormat("[SRL] %s limit failed (%d): %s", tname, gTrade.ResultRetcode(), gTrade.ResultComment());
         state += tname + " failed  ";
        }
     }
   //--- whatever no ranked zone claimed this pass is stale. Only THIS side:
   //    in TREND_NONE the other side's limits are managed by the next call.
   for(int i = ArraySize(claimed) - 1; i >= 0; i--)
      if(!claimed[i] && i < ArraySize(gPend) && gPend[i].dir == dir)
         CancelPendingRec(i, "zone no longer ranked");
   SetStatus(dir > 0 ? "BUY SIDE" : "SELL SIDE", state == "" ? "no tiers" : state,
             dir > 0 ? clrLime : clrTomato);
  }

//+------------------------------------------------------------------+
//| REJECTION MODE - a closed entry bar that wicked into the zone and  |
//| closed back out of it. At most one market entry per bar.          |
//+------------------------------------------------------------------+
void EvaluateRejection(const int dir)
  {
   MqlRates r[]; ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, EntryTF, 1, 2, r) < 2) return;
   string state = "";
   for(int t = 0; t < 3; t++)
     {
      bool enabled = (t == 0 && TradeTier1) || (t == 1 && TradeTier2) || (t == 2 && TradeTier3);
      if(!enabled) continue;
      int zi = (dir > 0) ? gSup[t] : gRes[t];
      if(zi < 0) continue;
      Zone z = gZones[zi];
      string tname = StringFormat("%s%d", dir > 0 ? "S" : "R", t + 1);
      bool hit;
      if(dir > 0)
         hit = r[0].low <= z.top && r[0].close > z.top && r[1].close > z.bottom &&
               (!RejectionNeedsBody || r[0].close > r[0].open);
      else
         hit = r[0].high >= z.bottom && r[0].close < z.bottom && r[1].close < z.top &&
               (!RejectionNeedsBody || r[0].close < r[0].open);
      if(!hit) { state += tname + " watch  "; continue; }

      string why = "";
      if(ZoneBlocked(z, why)) { state += tname + " blocked  "; continue; }
      int open = CountPositions();
      if(open >= MaxConcurrentPositions) { state += tname + " cap  "; continue; }
      if(BlockOpposingEntries && HasOpposingPosition(dir)) { state += tname + " opposed  "; continue; }

      //--- the wick is the real far edge of the zone for this trade
      Zone ze = z;
      if(dir > 0) ze.bottom = MathMin(z.bottom, r[0].low); else ze.top = MathMax(z.top, r[0].high);
      double entry = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0, tp = 0;
      if(!Geometry(dir, entry, t, ze, sl, tp, why)) { PrintFormat("[SRL] %s rejection skipped: %s", tname, why); state += tname + " no-geo  "; continue; }
      double riskPct = 0.0;
      double lot = CalcLot(MathAbs(entry - sl), riskPct, why);
      if(lot <= 0.0) { SetStatus("REJECT", why, clrRed); continue; }
      string comment = StringFormat("%s-%s-RJ", TradeCommentPrefix, tname);
      bool ok = (dir > 0) ? gTrade.Buy(lot, _Symbol, 0.0, sl, tp, comment)
                          : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);
      if(ok)
        {
         int n = ArraySize(gPend); ArrayResize(gPend, n + 1);   // so the fill handler can attribute it
         gPend[n].ticket = gTrade.ResultOrder(); gPend[n].tier = t + 1; gPend[n].dir = dir;
         gPend[n].top = z.top; gPend[n].bottom = z.bottom;
         gPend[n].slPips = MathAbs(entry - sl) / gPip; gPend[n].tpPips = MathAbs(tp - entry) / gPip;
         gPend[n].bars = 0;
         PrintFormat("[SRL] %s REJECTION %s @ %.2f  zone %.2f-%.2f [%s]  lot %.2f risk %.2f%%  SL %.2f TP %.2f",
                     dir > 0 ? "BUY" : "SELL", tname, entry, z.bottom, z.top, z.tags, lot, riskPct, sl, tp);
         SetStatus("FIRED", tname + " rejection", dir > 0 ? clrLime : clrTomato);
         return;
        }
      PrintFormat("[SRL] %s rejection order failed (%d): %s", tname, gTrade.ResultRetcode(), gTrade.ResultComment());
     }
   SetStatus(dir > 0 ? "BUY SIDE" : "SELL SIDE", state == "" ? "no tiers" : state, dir > 0 ? clrLime : clrTomato);
  }

//+------------------------------------------------------------------+
//| POSITIONS                                                          |
//+------------------------------------------------------------------+
bool OurPosition(const int i, ulong &ticket)
  {
   ticket = PositionGetTicket(i);
   if(ticket == 0) return(false);
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) return(false);
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)     return(false);
   return(true);
  }

int CountPositions()
  {
   int c = 0; ulong t;
   for(int i = PositionsTotal() - 1; i >= 0; i--) if(OurPosition(i, t)) c++;
   return(c);
  }

bool HasOpposingPosition(const int dir)
  {
   ulong t;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!OurPosition(i, t)) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir > 0 && type == POSITION_TYPE_SELL) return(true);
      if(dir < 0 && type == POSITION_TYPE_BUY)  return(true);
     }
   return(false);
  }

void CloseAllPositions(const string why)
  {
   ulong t;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!OurPosition(i, t)) continue;
      if(gTrade.PositionClose(t)) PrintFormat("[SRL] Closed #%I64u: %s", t, why);
      else PrintFormat("[SRL] Close #%I64u failed (%d): %s", t, gTrade.ResultRetcode(), gTrade.ResultComment());
     }
  }

int FindPosRec(const long posId)
  {
   for(int i = 0; i < ArraySize(gPos); i++) if(gPos[i].posId == posId) return(i);
   return(-1);
  }

void AddPosRec(const long posId, const int tier, const double top, const double bottom, const double riskPrice)
  {
   if(FindPosRec(posId) >= 0) return;
   int n = ArraySize(gPos); ArrayResize(gPos, n + 1);
   gPos[n].posId = posId; gPos[n].tier = tier; gPos[n].top = top; gPos[n].bottom = bottom;
   gPos[n].riskPrice = riskPrice; gPos[n].beAdjusted = false;
  }

//--- positions found at attach: we know their stop, not their zone
void AdoptOpenPositions()
  {
   ulong t;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!OurPosition(i, t)) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      AddPosRec(PositionGetInteger(POSITION_IDENTIFIER), 0, op, op, sl > 0 ? MathAbs(op - sl) : 0.0);
      PrintFormat("[SRL] Adopted open position #%I64u (SL %.2f).", t, sl);
     }
  }

void PrunePosRecs()
  {
   for(int i = ArraySize(gPos) - 1; i >= 0; i--)
     {
      bool alive = false; ulong t;
      for(int k = PositionsTotal() - 1; k >= 0; k--)
         if(OurPosition(k, t) && PositionGetInteger(POSITION_IDENTIFIER) == gPos[i].posId) { alive = true; break; }
      if(!alive) ArrayRemove(gPos, i, 1);
     }
  }

//--- never leave a position without a stop; optional breakeven
void SyncPositionStops()
  {
   //--- throttled on SERVER time, not GetTickCount. A whole eight-month
   //    backtest runs in about two seconds of wall clock, so a 5s real-time
   //    throttle ran this once per test and the breakeven never fired -
   //    BreakevenAtR=1 produced a report identical to BreakevenAtR=0.
   //    Live, server time and wall time advance together, so nothing
   //    changes there.
   datetime now = TimeCurrent();
   if(gLastStopSync != 0 && (now - gLastStopSync) < 5) return;
   gLastStopSync = now;
   ulong t;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!OurPosition(i, t)) continue;
      long   type = PositionGetInteger(POSITION_TYPE);
      int    dir  = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double op   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(EnforcePositionStops && sl == 0.0)
        {
         double nsl = SnapToTick(op - dir * MaxSLPips * gPip);
         if(gTrade.PositionModify(t, nsl, tp))
            PrintFormat("[SRL] Position #%I64u had NO STOP - attached SL %.2f (%.0fp, the MaxSLPips cap).", t, nsl, MaxSLPips);
         else
            PrintFormat("[SRL] Could not attach a stop to #%I64u (%d): %s", t, gTrade.ResultRetcode(), gTrade.ResultComment());
         continue;
        }
      if(BreakevenAtR <= 0.0) continue;
      int pr = FindPosRec(PositionGetInteger(POSITION_IDENTIFIER));
      if(pr < 0 || gPos[pr].beAdjusted || gPos[pr].riskPrice <= 0.0) continue;
      double cur = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if((cur - op) * dir < BreakevenAtR * gPos[pr].riskPrice) continue;
      double nsl = SnapToTick(op + dir * BreakevenOffsetPips * gPip);
      if((dir > 0 && nsl <= sl) || (dir < 0 && sl > 0 && nsl >= sl)) { gPos[pr].beAdjusted = true; continue; }
      if(gTrade.PositionModify(t, nsl, tp))
        { gPos[pr].beAdjusted = true; PrintFormat("[SRL] #%I64u to breakeven: SL %.2f after %.1fR.", t, nsl, BreakevenAtR); }
     }
  }

//+------------------------------------------------------------------+
//| DAY STATE + STATS (same rollover model as TrendEMA)                |
//+------------------------------------------------------------------+
long CurrentDayIndex()
  {
   datetime etNow = TimeGMT() + (datetime)(ETOffsetHours * 3600);
   return((long)MathFloor((double)(etNow - DayResetHourET * 3600) / 86400.0));
  }

datetime DayStartServerTime()
  {
   long idx = CurrentDayIndex();
   double boundaryET = (double)idx * 86400.0 + DayResetHourET * 3600.0;
   datetime boundaryGMT = (datetime)(boundaryET - ETOffsetHours * 3600);
   int serverGmtOffset = (int)(TimeTradeServer() - TimeGMT());
   return(boundaryGMT + serverGmtOffset);
  }

bool IsNewDay() { return(CurrentDayIndex() != gDayIndex); }

void ResetDayState(const bool firstRun)
  {
   gDayIndex = CurrentDayIndex();
   gDayStart = DayStartServerTime();
   gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gDayTrades = 0; gDayPL = 0.0;
   if(!firstRun) PrintFormat("[SRL] New trading day (%02d:00 ET rollover). Counters reset.", DayResetHourET);
  }

void RefreshDailyStats()
  {
   if(!HistorySelect(gDayStart, TimeCurrent() + 60))
     { PrintFormat("[SRL] HistorySelect failed - keeping previous daily figures (P/L %.2f, %d fills).", gDayPL, gDayTrades); return; }
   gDayPL = 0.0; gDayTrades = 0; gDayWins = 0; gDayLosses = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i); if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != MagicNumber || HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      gDayPL += net;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN) gDayTrades++;
      if(entry == DEAL_ENTRY_OUT) { if(net > 0.0) gDayWins++; else if(net < 0.0) gDayLosses++; }
     }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > 0.0) gDayStartBalance = bal - gDayPL;
  }

void RefreshAllTimeStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 60)) return;
   gAllWins = 0; gAllLosses = 0; gAllNet = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i); if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != MagicNumber || HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      gAllNet += net;
      if(net > 0.0) gAllWins++; else if(net < 0.0) gAllLosses++;
     }
  }

//+------------------------------------------------------------------+
//| Fills and closes                                                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)     return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double vol   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   long   posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   long   dtype = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

   if(entry == DEAL_ENTRY_IN)
     {
      ulong dealOrder = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      string tag = "adopted";
      for(int i = 0; i < ArraySize(gPend); i++)
        {
         if(gPend[i].ticket != dealOrder) continue;
         tag = StringFormat("%s%d", gPend[i].dir > 0 ? "S" : "R", gPend[i].tier);
         AddPosRec(posId, gPend[i].tier, gPend[i].top, gPend[i].bottom, gPend[i].slPips * gPip);
         AddBlock(gPend[i].top, gPend[i].bottom, ZoneRetradeBars, tag + " already traded");
         ArrayRemove(gPend, i, 1);
         break;
        }
      gLastStatsMs = 0;
      string msg = StringFormat("SRL FILL %s %.2f lots @ %.2f [%s]", dtype == DEAL_TYPE_BUY ? "BUY" : "SELL", vol, price, tag);
      Print("[SRL] ", msg);
      if(AlertOnFill) Alert(msg);
      if(EnablePush)  SendNotification(msg);
     }
   else if(entry == DEAL_ENTRY_OUT)
     {
      double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      int pr = FindPosRec(posId);
      string tag = (pr >= 0 && gPos[pr].tier > 0) ? StringFormat("tier %d", gPos[pr].tier) : "adopted";
      //--- a zone that just stopped us out is not one to buy again in an hour
      if(net < 0.0 && pr >= 0 && gPos[pr].tier > 0)
         AddBlock(gPos[pr].top, gPos[pr].bottom, ZoneLossBlockBars, StringFormat("lost %.2f here", net));
      if(pr >= 0) ArrayRemove(gPos, pr, 1);
      gLastStatsMs = 0;
      RefreshAllTimeStats();
      string msg = StringFormat("SRL CLOSE %.2f lots @ %.2f  P/L %.2f [%s]", vol, price, net, tag);
      Print("[SRL] ", msg);
      if(AlertOnClose) Alert(msg);
      if(EnablePush)   SendNotification(msg);
     }
  }

//+------------------------------------------------------------------+
//| PANEL                                                              |
//+------------------------------------------------------------------+
string BarCountdown(const ENUM_TIMEFRAMES tf)
  {
   datetime opened = iTime(_Symbol, tf, 0);
   if(opened <= 0) return("--:--");
   int per = PeriodSeconds(tf), left = per - (int)(TimeCurrent() - opened);
   if(left < 0) left = 0; if(left > per) left = per;
   return(StringFormat("%d:%02d", left / 60, left % 60));
  }

void PanelLabel(const string name, const int x, const int y, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   string shown = text;
   if(StringLen(shown) > 64) shown = StringSubstr(shown, 0, 61) + "...";
   ObjectSetString(0, name, OBJPROP_TEXT, shown);
   uint tw = 0, th = 0; TextGetSize(shown, tw, th);
   int rightEdge = (x - PanelX) + (int)tw;
   if(rightEdge > gPanelMaxW) gPanelMaxW = rightEdge;
  }

void PanelRow(const int row, const string label, const string value, const color labelClr, const color valueClr)
  {
   const int rowH = PanelFontSize + 7;
   PanelLabel(PFX + "PL" + IntegerToString(row), PanelX, PanelY + row * rowH, label == "" ? " " : label, labelClr);
   if(value != "")
     {
      uint lw = 0, lh = 0; TextGetSize(label, lw, lh);
      int vx = PanelX + 110, clear = PanelX + (int)lw + 12;
      if(clear > vx) vx = clear;
      PanelLabel(PFX + "PV" + IntegerToString(row), vx, PanelY + row * rowH, value, valueClr);
     }
   else
      ObjectDelete(0, PFX + "PV" + IntegerToString(row));
  }

void DrawPanel()
  {
   if(!ShowPanel || gHeadless) return;
   //--- v1.0.1: the background was created AFTER the rows and drawn BEHIND
   //    the chart (OBJPROP_BACK true), so candles and the zone rectangles
   //    painted straight over the text. On the first live attach the panel
   //    was unreadable. Create the box first, in the foreground, and let the
   //    labels created after it stack on top; size it once the rows are in.
   //    Same construction as the TrendEMA panel.
   TextSetFont("Consolas", -PanelFontSize * 10);
   gPanelMaxW = 0;
   string bg = PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'60,64,72');
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PanelX - 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PanelY - 4);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, PanelBgColor);
   int row = 0;
   bool real = ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL);
   PanelRow(row++, "SR LEVELS EA v1.5", real ? "REAL MONEY" : "demo", clrGold, real ? clrRed : clrSilver);
   uint up = (GetTickCount() - gInitMs) / 1000;
   PanelRow(row++, "EA ALIVE", StringFormat("%dh%02dm  tick %ds ago", up / 3600, (up % 3600) / 60,
            (GetTickCount() - gLastTickMs) / 1000), PanelTextColor, clrSilver);
   PanelRow(row++, "STATUS", gStatus + "  " + gStatusDetail, PanelTextColor, gStatusColor);
   PanelRow(row++, "4H SIDE", StringFormat("%s  (%s)", DirName(gTrendDir), TrendModeName()), PanelTextColor,
            gTrendDir > 0 ? clrLime : (gTrendDir < 0 ? clrTomato : clrSilver));
   PanelRow(row++, "4H VALUES", StringFormat("close %.2f  cloud %.2f/%.2f  MA50 %.2f", gTClose,
            MathMin(gTSenA, gTSenB), MathMax(gTSenA, gTSenB), gTMa), PanelTextColor, clrSilver);
   PanelRow(row++, "NEXT CLOSE", StringFormat("%s %s   %s %s", TfName(EntryTF), BarCountdown(EntryTF),
            TfName(TrendTF), BarCountdown(TrendTF)), PanelTextColor, clrSilver);
   PanelRow(row++, "", "", PanelTextColor, PanelTextColor);
   for(int t = 2; t >= 0; t--)
     {
      int zi = gRes[t];
      PanelRow(row++, StringFormat("R%d", t + 1), zi < 0 ? "-" :
               StringFormat("%.2f-%.2f  %.1f  %s", gZones[zi].bottom, gZones[zi].top, gZones[zi].score, gZones[zi].tags),
               clrTomato, zi < 0 ? clrGray : PanelTextColor);
     }
   PanelRow(row++, "MARKET", StringFormat("%.2f / %.2f  spread %.0fp", SymbolInfoDouble(_Symbol, SYMBOL_BID),
            SymbolInfoDouble(_Symbol, SYMBOL_ASK), CurrentSpreadPips()), clrGold, PanelTextColor);
   for(int t = 0; t < 3; t++)
     {
      int zi = gSup[t];
      PanelRow(row++, StringFormat("S%d", t + 1), zi < 0 ? "-" :
               StringFormat("%.2f-%.2f  %.1f  %s", gZones[zi].bottom, gZones[zi].top, gZones[zi].score, gZones[zi].tags),
               clrLime, zi < 0 ? clrGray : PanelTextColor);
     }
   PanelRow(row++, "", "", PanelTextColor, PanelTextColor);
   string pend = "";
   for(int i = 0; i < ArraySize(gPend); i++)
     {
      if(!OrderSelect(gPend[i].ticket)) continue;
      pend += StringFormat("%s%d@%.2f  ", gPend[i].dir > 0 ? "S" : "R", gPend[i].tier, OrderGetDouble(ORDER_PRICE_OPEN));
     }
   PanelRow(row++, "LIMITS", pend == "" ? "none" : pend, PanelTextColor, pend == "" ? clrGray : clrDeepSkyBlue);
   ulong tk; int shown = 0;
   for(int i = PositionsTotal() - 1; i >= 0 && shown < 4; i--)
     {
      if(!OurPosition(i, tk)) continue;
      shown++;
      double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      PanelRow(row++, shown == 1 ? "POSITIONS" : "", StringFormat("%s %.2f @ %.2f  SL %.2f TP %.2f  %+.2f",
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY " : "SELL",
               PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN),
               PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP), pl),
               PanelTextColor, pl >= 0 ? clrLime : clrTomato);
     }
   if(shown == 0) PanelRow(row++, "POSITIONS", "none", PanelTextColor, clrGray);
   PanelRow(row++, "TODAY", StringFormat("%d/%s fills  %dW %dL  P/L %+.2f", gDayTrades,
            MaxTradesPerDay > 0 ? IntegerToString(MaxTradesPerDay) : "-", gDayWins, gDayLosses, gDayPL),
            PanelTextColor, gDayPL >= 0 ? clrLime : clrTomato);
   PanelRow(row++, "ALL TIME", StringFormat("%dW %dL  %.0f%%  net %+.2f", gAllWins, gAllLosses,
            (gAllWins + gAllLosses) > 0 ? 100.0 * gAllWins / (gAllWins + gAllLosses) : 0.0, gAllNet),
            PanelTextColor, clrSilver);

   for(int r = row; r < gPanelRowsDrawn; r++)
     { ObjectDelete(0, PFX + "PL" + IntegerToString(r)); ObjectDelete(0, PFX + "PV" + IntegerToString(r)); }
   gPanelRowsDrawn = row;

   ObjectSetInteger(0, bg, OBJPROP_XSIZE, gPanelMaxW + 18);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, row * (PanelFontSize + 7) + 8);
   ChartRedraw();
  }

//--- S1-S3 / R1-R3 as filled rectangles from their first pivot to the right edge
void DrawZones()
  {
   if(gHeadless) return;
   for(int t = 0; t < 3; t++) { ObjectDelete(0, PFX + "ZS" + IntegerToString(t)); ObjectDelete(0, PFX + "ZR" + IntegerToString(t));
                                ObjectDelete(0, PFX + "TS" + IntegerToString(t)); ObjectDelete(0, PFX + "TR" + IntegerToString(t)); }
   if(!ShowZones) return;
   datetime now = TimeCurrent(), right = now + PeriodSeconds(TrendTF) * 12;
   for(int side = 0; side < 2; side++)
      for(int t = 0; t < 3; t++)
        {
         int zi = (side == 0) ? gSup[t] : gRes[t];
         if(zi < 0) continue;
         Zone z = gZones[zi];
         datetime left = (z.firstT > 0) ? z.firstT : now - PeriodSeconds(TrendTF) * 40;
         string nm = PFX + (side == 0 ? "ZS" : "ZR") + IntegerToString(t);
         ObjectCreate(0, nm, OBJ_RECTANGLE, 0, left, z.top, right, z.bottom);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, side == 0 ? SupportColor : ResistanceColor);
         ObjectSetInteger(0, nm, OBJPROP_FILL, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         string tn = PFX + (side == 0 ? "TS" : "TR") + IntegerToString(t);
         ObjectCreate(0, tn, OBJ_TEXT, 0, now + PeriodSeconds(TrendTF) * 2, side == 0 ? z.top : z.bottom);
         ObjectSetString(0, tn, OBJPROP_TEXT, StringFormat("%s%d %.0f-%.0f  %s", side == 0 ? "S" : "R", t + 1, z.bottom, z.top, z.tags));
         ObjectSetInteger(0, tn, OBJPROP_COLOR, side == 0 ? clrLime : clrTomato);
         ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, tn, OBJPROP_ANCHOR, side == 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
        }
   ChartRedraw();
  }
//+------------------------------------------------------------------+
