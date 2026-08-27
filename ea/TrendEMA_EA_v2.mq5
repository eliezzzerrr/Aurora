//+------------------------------------------------------------------+
//|                                              TrendEMA_EA_v2.mq5   |
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
//  StopLossPips / TakeProfit*Pips for any other instrument, or set
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
//    SL 500 pips ($5.00) fixed. TP 1500 with-trend / 1000 counter.
//    2% of equity per trade, rounded DOWN to lot step, hard-rejected
//    above 2.5%. Max 3 concurrent positions = 6% open risk.
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
//  Three concurrent positions at 2% each is 6% of the account at
//  risk simultaneously. Gold is correlated with itself: three longs
//  off the same 1M EMA50 in one session are effectively one trade
//  in three pieces, and one adverse move takes all three. The -6%
//  daily stop is therefore reachable in a single move, not only
//  across three separate trades. This is by design, chosen by the
//  operator with the tradeoff understood.
//+------------------------------------------------------------------+
#property copyright "Aurora Trend EA"
#property version   "2.00"   // file is TrendEMA_EA_v2 - bump both together
#property description "Ichimoku-gated, EMA-directed XAUUSD trader. 15M gate / 5M direction / 1M entry."

#include <Trade\Trade.mqh>

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
   RSI_MODE_PULLBACK, // Pullback - BUY needs RSI < mid, SELL needs > mid (default)
   RSI_MODE_VETO,     // Veto extremes - no BUY above OB, no SELL below OS
   RSI_MODE_LEVEL,    // Level bias - BUY needs RSI > mid (fights the pullback)
   RSI_MODE_SLOPE     // Slope - BUY needs rising RSI (fights the pullback badly)
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
input ENUM_RSI_MODE RsiMode     = RSI_MODE_PULLBACK; // How RSI gates entries (see notes below)
input double RsiOverbought      = 70.0;  // VETO mode: block BUY above this
input double RsiOversold        = 30.0;  // VETO mode: block SELL below this
input double RsiLevelMid        = 50.0;  // LEVEL mode: BUY needs RSI above, SELL below

input group "=== ENTRY ==="
input bool   UseRetestGate      = true;  // Skip first touch when 1M EMAs oppose the trade
input double RetestDistancePips = 50;    // Pull-away needed before a return counts as retest
input int    RetestExpiryBars   = 15;    // Reset the retest wait after this many 1M bars
input bool   UseAtrRetest       = false; // ATR-adaptive retest distance instead of fixed
input int    AtrPeriod          = 14;    // ATR period (1M) for adaptive retest
input double AtrRetestMult      = 0.5;   // Retest distance = this x 1M ATR
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
input bool   EnableRsiExtreme   = false; // Master switch for the RSI extreme trigger
//  Levels are entered as BUY-side numbers and mirrored for sells:
//      3TF  25 -> 75     fast  30 -> 70     slow  40 -> 60
input double RsiXFastLevel      = 30.0;  // Fast TF extreme for BUY (SELL mirrors to 70)
input double RsiXSlowLevel      = 40.0;  // Slow TF confirmation for BUY (SELL mirrors to 60)
input double RsiX3TFLevel       = 25.0;  // Stricter fast level that earns the 3TF tag (SELL 75)
input double RsiXResetLevel     = 50.0;  // Fast RSI must recover past this before re-arming
input bool   RsiXWaitForTurn    = true;  // Enter only once fast RSI crosses back through the fast level
input int    RsiXArmExpiryBars  = 30;    // Drop an armed signal after this many 1M bars
input double RsiXStopLossPips   = 500;   // SL for extreme trades
input double RsiXTakeProfitPips = 1000;  // TP for extreme trades
input bool   RsiXCancelsTrend   = true;  // Cancel resting trend limits while an extreme is active

input group "=== RISK ==="
input double StopLossPips           = 500;  // SL distance (500 = $5.00)
input double TakeProfitTrendPips    = 1500; // TP with-trend (1500 = $15.00)
input double TakeProfitCounterPips  = 1000; // TP counter-trend (1000 = $10.00)
input bool   UseFixedLot            = false;// Fixed lot instead of % risk (USE FOR EDGE TESTING)
input double FixedLotSize           = 0.01; // Lot used when UseFixedLot is true
input double RiskPercent            = 2.0;  // Target risk per trade, % of capital
input double MaxRiskPercent         = 2.5;  // Hard ceiling - reject the trade above this
input bool   SizeFromEquity         = true; // Size from equity (false = balance)
input double MaxLotSizeCap          = 0.0;  // Absolute lot cap (0 = disabled)
input int    MaxConcurrentPositions = 3;    // Max simultaneous positions
input bool   BlockOpposingEntries   = false;// Block entries opposing an open position
input int    MaxDailyTradeCount     = 0;    // Max fills per day (0 = unlimited)
input double MaxDailyLossPercent    = 6.0;  // Halt for the day at this realised loss % (0 = disabled)
input int    DayResetHourET         = 12;   // Hour (ET) the trading day rolls over and the halt lifts
input int    ETOffsetHours          = -4;   // ET offset from GMT: -4 Mar-Nov (EDT), -5 Nov-Mar (EST)
input int    CooldownMinutesAfterLoss = 30; // Wait after a losing trade
input double MinFreeMarginPercent   = 30.0; // Pause if free margin / equity below this %

input group "=== FILTERS ==="
input double MaxSpreadPips      = 25;    // Skip if spread wider than this (25 = $0.25)
input bool   BlockNewsWindow    = true;  // Block around high-impact USD news
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
input color  PanelTextColor     = clrWhiteSmoke;  // Panel default text colour
input color  PanelBgColor       = C'18,20,26';    // Panel background

input group "=== SAFETY ==="
input bool   RequireGoldSymbol  = false; // Refuse to attach to non-gold instruments
input double PipSizeOverride    = 0.0;   // Force a pip size (0 = auto-detect from digits)
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
double   gRsi1    = 0.0;   // 1M RSI  (extreme trigger only)
double   gRsi15   = 0.0;   // 15M RSI (extreme trigger only)

//--- RSI extreme trigger state
bool     gXArmed     = false;  // condition met, waiting to fire
int      gXDir       = 0;      // +1 buy, -1 sell
string   gXTag       = "";     // 3TF / 1M5M / 5M15M
bool     gXFastIsM1  = true;   // which TF supplies the turn-up confirmation
int      gXArmBars   = 0;
bool     gXNeedsReset = false; // fired; waiting for RSI to return to neutral
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

//--- daily state
datetime gDayStart        = 0;
long     gDayIndex        = -1;
double   gDayStartBalance = 0.0;
int      gDayTrades       = 0;
double   gDayPL           = 0.0;
datetime gLastLossTime    = 0;

//--- bar tracking
datetime gLastTrendBar  = 0;
datetime gLastSignalBar = 0;
datetime gLastEntryBar  = 0;

//--- news
bool     gCalendarOK = true;

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
   if(StopLossPips <= 0 || TakeProfitTrendPips <= 0 || TakeProfitCounterPips <= 0)
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
   gCalendarOK = true;
   if(MQLInfoInteger(MQL_TESTER))
     {
      gCalendarOK = false;
      if(BlockNewsWindow)
         Print("[TREMA] NOTE: economic calendar is unavailable in the Strategy Tester. "
               "News blocking is INACTIVE for this backtest - live results will differ.");
     }

   //--- day state -------------------------------------------------------
   ResetDayState(true);
   RefreshDailyStats();

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
               StopLossPips, StopLossPips * gPip,
               TakeProfitTrendPips, TakeProfitCounterPips,
               RiskPercent, MaxRiskPercent, MaxConcurrentPositions,
               RsiModeName());

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
               _Symbol, StopLossPips, StopLossPips * gPip,
               TakeProfitTrendPips * gPip, TakeProfitCounterPips * gPip);

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

   gInitOk = true;
   DrawPanel();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();

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
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!gInitOk)
      return;

   //--- day rollover ----------------------------------------------------
   if(IsNewDay())
     {
      ResetDayState(false);
      CancelPending("new trading day");
      gLastStatsMs = 0;
     }

   //--- indicators (per-timeframe bar gated) -----------------------------
   bool newEntryBar = RefreshIndicators(false);

   //--- daily stats: a full history scan, so throttle it -----------------
   uint nowMs = GetTickCount();
   if(newEntryBar || gLastStatsMs == 0 || (nowMs - gLastStatsMs) > 15000)
     {
      RefreshDailyStats();
      gLastStatsMs = nowMs;
     }

   //--- trend flip management -------------------------------------------
   if(CloseOnTrendFlip && gCloud != gCloudPrev && gCloudPrev != CLOUD_UNKNOWN)
      CloseAllPositions("15M trend gate flipped");
   gCloudPrev = gCloud;

   //--- evaluate the setup and act ---------------------------------------
   EvaluateAndAct(newEntryBar);

   //--- pending order housekeeping ----------------------------------------
   if(newEntryBar && gPendingTicket != 0)
     {
      gPendingBars++;
      if(gPendingBars > PendingExpiryBars)
         CancelPending(StringFormat("unfilled for %d bars", gPendingBars));
     }

   //--- display: panel recomputes sizing, so cap it at ~3 redraws/sec ------
   if(newEntryBar || gLastPanelMs == 0 || (nowMs - gLastPanelMs) > 300)
     {
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
   if(FileIsExist(EmergencyStopFile))
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

   if(InCooldown())
     {
      int mins = (int)((gLastLossTime + CooldownMinutesAfterLoss * 60 - TimeCurrent()) / 60) + 1;
      SetStatus("COOLDOWN", StringFormat("%d min left after loss", mins), clrOrange);
      CancelPending("cooldown after loss");
      return;
     }

   if(IsFridayCutoff())
     {
      SetStatus("BLOCKED", "Friday cutoff", clrOrange);
      CancelPending("Friday cutoff");
      return;
     }

   if(NewsBlocked())
     {
      SetStatus("BLOCKED", "high-impact news window", clrOrange);
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
   if(EnableRsiExtreme && EvaluateRsiExtreme(newEntryBar))
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
      SetStatus("WAIT", StringFormat("5M RSI %.1f blocks %s (%s mode)",
                                     gRsiNow, dir > 0 ? "BUY" : "SELL",
                                     RsiModeName()), clrSilver);
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

   //--- resolve which EMA50 the limit will rest at ------------------------------
   //    Primary is the 1M EMA50. When a spike puts price the wrong side of it
   //    the limit cannot be placed at all, so fall back to the slower 5M EMA50,
   //    which in a trend sits further from price and is still a valid level.
   //    Every gate below measures against whichever level is chosen here.
   if(!ResolveEntryLevel(dir, gEntryLevel, gEntryLevelSrc))
     {
      SetStatus("WAIT", dir > 0 ? "price below both EMA50 levels"
                                : "price above both EMA50 levels", clrSilver);
      CancelPending("no placeable limit level");
      return;
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
double X3TF (const int dir) { return(dir > 0 ? RsiX3TFLevel  : 100.0 - RsiX3TFLevel);  }

//--- is `v` beyond the threshold in the direction of this trade?
bool XBeyond(const int dir, const double v, const double level)
  {
   return(dir > 0 ? (v < level) : (v > level));
  }

//--- does a washout exist right now? Fills tag / which TF confirms the turn.
bool XConditionMet(const int dir, string &tag, bool &fastIsM1)
  {
   bool pairA = XBeyond(dir, gRsi1, XFast(dir)) && XBeyond(dir, gRsi5Now(), XSlow(dir));
   bool pairB = XBeyond(dir, gRsi5Now(), XFast(dir)) && XBeyond(dir, gRsi15, XSlow(dir));

   //--- 3TF is a strict subset of pairA (the 1M level is tighter), so it is
   //    a LABEL for a stronger washout, not a separate trigger.
   bool three = XBeyond(dir, gRsi1, X3TF(dir)) &&
                XBeyond(dir, gRsi5Now(), XSlow(dir)) &&
                XBeyond(dir, gRsi15, XSlow(dir));

   if(three)      { tag = "3TF";   fastIsM1 = true;  return(true); }
   if(pairA)      { tag = "1M5M";  fastIsM1 = true;  return(true); }
   if(pairB)      { tag = "5M15M"; fastIsM1 = false; return(true); }
   tag = ""; fastIsM1 = true;
   return(false);
  }

double gRsi5Now() { return(gRsiNow); }   // the 5M RSI already cached each 5M bar

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
         if(VerboseLog) Print("[TREMA] RSI extreme reset - trigger re-armed.");
        }
      else
        {
         SetStatus("RSI-X", StringFormat("cooling: fast RSI %.1f -> %.0f",
                                         fastRsi, RsiXResetLevel), clrSilver);
         return(false);   // does not own the tick; trend logic may continue
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
         return(false);

      gXArmed    = true;
      gXDir      = dir;
      gXTag      = tag;
      gXFastIsM1 = fm1;
      gXArmBars  = 0;
      PrintFormat("[TREMA] RSI EXTREME armed: %s %s  1M=%.1f 5M=%.1f 15M=%.1f",
                  dir > 0 ? "BUY" : "SELL", tag, gRsi1, gRsiNow, gRsi15);
     }

   //--- armed: cancel any resting trend limit, this trigger has precedence ---
   if(RsiXCancelsTrend)
      CancelPending("RSI extreme armed");

   if(newEntryBar)
      gXArmBars++;
   if(gXArmBars > RsiXArmExpiryBars)
     {
      Print("[TREMA] RSI extreme expired unfired after ", gXArmBars, " bars.");
      gXArmed = false;
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
         SetStatus("RSI-X", StringFormat("armed %s %s - waiting turn (%.1f)",
                                         gXDir > 0 ? "BUY" : "SELL", gXTag, fastRsi),
                   clrGold);
         return(true);
        }
     }

   //--- risk gates the trigger still has to satisfy ---------------------------
   if(CountPositions() >= MaxConcurrentPositions)
     {
      SetStatus("RSI-X", "blocked: position cap", clrOrange);
      return(true);
     }
   double spr = CurrentSpreadPips();
   if(spr > MaxSpreadPips)
     {
      SetStatus("RSI-X", StringFormat("blocked: spread %.0fp", spr), clrOrange);
      return(true);
     }

   FireRsiExtreme();
   return(true);
  }

void FireRsiExtreme()
  {
   double riskPct = 0.0; string why = "";
   double lot = CalcLot(RsiXStopLossPips * gPip, riskPct, why);
   if(lot <= 0.0)
     {
      SetStatus("RSI-X", "REJECT " + why, clrRed);
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(gXDir > 0)
     {
      sl = NormalizeDouble(ask - RsiXStopLossPips   * gPip, gDigits);
      tp = NormalizeDouble(ask + RsiXTakeProfitPips * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(bid + RsiXStopLossPips   * gPip, gDigits);
      tp = NormalizeDouble(bid - RsiXTakeProfitPips * gPip, gDigits);
     }

   string comment = StringFormat("%s-RSIX-%s", TradeCommentPrefix, gXTag);
   bool ok = (gXDir > 0)
             ? gTrade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
             : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
     {
      PrintFormat("[TREMA] RSI EXTREME %s %s filled lot %.2f risk %.2f%% SL %.2f TP %.2f",
                  gXDir > 0 ? "BUY" : "SELL", gXTag, lot, riskPct, sl, tp);
      SetStatus("RSI-X", StringFormat("FIRED %s %s  lot %.2f",
                                      gXDir > 0 ? "BUY" : "SELL", gXTag, lot),
                gXDir > 0 ? clrLime : clrTomato);
      gXArmed      = false;
      gXNeedsReset = true;   // one trade per washout event
     }
   else
     {
      PrintFormat("[TREMA] RSI extreme order failed (%d): %s",
                  gTrade.ResultRetcode(), gTrade.ResultComment());
      SetStatus("RSI-X", StringFormat("order rejected %d", gTrade.ResultRetcode()), clrRed);
      gXArmed = false;
     }
  }

//+------------------------------------------------------------------+
//| Pending limit placement / re-pricing                               |
//+------------------------------------------------------------------+
void ManageLimit(const int dir, const bool counter, const bool newEntryBar)
  {
   //--- level was already resolved and validated by ResolveEntryLevel() ------
   double level = NormalizeDouble(gEntryLevel, gDigits);
   string levelTag = EntryLevelTag();

   double tpPips = counter ? TakeProfitCounterPips : TakeProfitTrendPips;
   double sl, tp;
   if(dir > 0)
     {
      sl = NormalizeDouble(level - StopLossPips * gPip, gDigits);
      tp = NormalizeDouble(level + tpPips        * gPip, gDigits);
     }
   else
     {
      sl = NormalizeDouble(level + StopLossPips * gPip, gDigits);
      tp = NormalizeDouble(level - tpPips        * gPip, gDigits);
     }

   //--- sizing ------------------------------------------------------------------
   double riskPct = 0.0;
   string reason  = "";
   double lot     = CalcLot(StopLossPips * gPip, riskPct, reason);
   if(lot <= 0.0)
     {
      SetStatus("REJECT", reason, clrRed);
      CancelPending("sizing rejected: " + reason);
      return;
     }

   //--- already have a live limit: re-price it on each new 1M bar ---------------
   if(gPendingTicket != 0 && PendingAlive(gPendingTicket))
     {
      if(newEntryBar)
        {
         double curPrice = OrderPriceOf(gPendingTicket);
         if(MathAbs(curPrice - level) >= gPoint)
           {
            if(!gTrade.OrderModify(gPendingTicket, level, sl, tp, ORDER_TIME_GTC, 0))
               PrintFormat("[TREMA] Re-price failed (%d): %s",
                           gTrade.ResultRetcode(), gTrade.ResultComment());
           }
        }
      SetStatus("ARMED", StringFormat("%s @ %.2f (%s)  lot %.2f  %.2f%%",
                                      dir > 0 ? "BUY" : "SELL", level, levelTag,
                                      lot, riskPct),
                dir > 0 ? clrLime : clrTomato);
      return;
     }

   //--- no live limit: place one -------------------------------------------------
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
      gPendingTicket = gTrade.ResultOrder();
      gPendingBars   = 0;
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

   //--- 15M trend gate ---------------------------------------------------
   datetime tBar = iTime(_Symbol, TrendTF, 0);
   if(force || tBar != gLastTrendBar)
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
         //--- 15M EMAs are NOT part of the trend gate; they exist only to
         //    supply the deepest fallback entry level.
         CopyOne(hEma15F, 0, 1, gEma15F);
         CopyOne(hEma15S, 0, 1, gEma15S);
         CopyOne(hRsi15,  0, 1, gRsi15);
         gLastTrendBar = tBar;
        }
     }

   //--- 5M direction + momentum --------------------------------------------
   datetime sBar = iTime(_Symbol, SignalTF, 0);
   if(force || sBar != gLastSignalBar)
     {
      if(CopyOne(hEma5F, 0, 1, gEma5F) &&
         CopyOne(hEma5S, 0, 1, gEma5S) &&
         CopyOne(hRsi5,  0, 1, gRsiNow) &&
         CopyOne(hRsi5,  0, 2, gRsiPrev))
        {
         gDir5 = (gEma5F > gEma5S) ? 1 : ((gEma5F < gEma5S) ? -1 : 0);
         gLastSignalBar = sBar;
        }
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
        }
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

bool RsiConfirms(const int dir)
  {
   if(dir == 0)
      return(false);

   switch(RsiMode)
     {
      case RSI_MODE_OFF:
         return(true);

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
   if(LevelIsPlaceable(dir, gEma1S))
     {
      level = gEma1S;
      src   = 0;
      return(true);
     }

   //--- price has run past the 1M EMA50; each slower EMA50 sits further from
   //    price in a trend, so walk out to the next one that is still valid.
   if(UseFallbackLevel && LevelIsPlaceable(dir, gEma5S))
     {
      level = gEma5S;
      src   = 1;
      return(true);
     }

   if(UseFallback15M && LevelIsPlaceable(dir, gEma15S))
     {
      level = gEma15S;
      src   = 2;
      return(true);
     }

   level = gEma1S;
   src   = 0;
   return(false);
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

bool InCooldown()
  {
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

bool NewsBlocked()
  {
   if(!BlockNewsWindow || !gCalendarOK)
      return(false);

   datetime now  = TimeGMT();
   datetime from = now - NewsMinutesAfter  * 60;
   datetime to   = now + NewsMinutesBefore * 60;

   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, from, to, NULL, "USD");
   if(n <= 0)
      return(false);

   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
         return(true);
     }
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
         PrintFormat("[TREMA] Limit #%I64u cancelled: %s", gPendingTicket, why);
      else
         PrintFormat("[TREMA] Limit #%I64u delete failed (%d): %s",
                     gPendingTicket, gTrade.ResultRetcode(), gTrade.ResultComment());
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
   int serverGmtOffset = (int)(TimeCurrent() - TimeGMT());
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
   if(!firstRun)
      PrintFormat("[TREMA] New trading day (%02d:00 ET rollover). Counters reset, "
                  "daily halt lifted.", DayResetHourET);
  }

//--- recompute today from deal history so restarts do not lose state ----
void RefreshDailyStats()
  {
   gDayPL        = 0.0;
   gDayTrades    = 0;
   gLastLossTime = 0;

   if(!HistorySelect(gDayStart, TimeCurrent() + 60))
      return;

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
         if(net < 0.0)
           {
            datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
            if(dt > gLastLossTime)
               gLastLossTime = dt;
           }
        }
     }
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
      //--- a limit filled: force the re-arm distance before the next setup
      gPendingTicket = 0;
      gPendingBars   = 0;
      gRearmPending  = true;
      ResetSetup();

      long dtype = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      string dcom = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      string msg = StringFormat("TREMA FILL %s %.2f lots @ %.2f  [%s EMA50]",
                                dtype == DEAL_TYPE_BUY ? "BUY" : "SELL", vol, price,
                                PositionLevelTag(dcom));
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
      ObjectsDeleteAll(0, PFX + "P");
      return;
     }

   const int rowH  = PanelFontSize + 7;
   int openNow = CountPositions();
   const int rows  = 15 + (openNow > 0 ? openNow : 0) + (EnableRsiExtreme ? 1 : 0);
   const int width = 440;

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
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,     width);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,     rows * rowH + 12);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,   PanelBgColor);

   int r = 0;

   //--- title -----------------------------------------------------------
   bool isReal = ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)
                  == ACCOUNT_TRADE_MODE_REAL);
   PanelRow(r++, StringFormat("TREND EA  -  %s", _Symbol),
            isReal ? "REAL MONEY" : "demo",
            clrGold, isReal ? clrRed : clrLime);
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
   PanelRow(r++, "15M CLOUD", cloudTxt, PanelTextColor, cloudClr);

   string ema5Txt = (gDir5 > 0) ? "20 > 50  bullish"
                    : (gDir5 < 0) ? "20 < 50  bearish" : "flat";
   PanelRow(r++, "5M  EMA", ema5Txt, PanelTextColor,
            gDir5 > 0 ? clrLime : (gDir5 < 0 ? clrTomato : clrGray));

   string ema1Txt = (gEma1F > gEma1S) ? "20 > 50  bullish"
                    : (gEma1F < gEma1S) ? "20 < 50  bearish" : "flat";
   PanelRow(r++, "1M  EMA", ema1Txt, PanelTextColor,
            gEma1F > gEma1S ? clrLime : (gEma1F < gEma1S ? clrTomato : clrGray));

   bool rsiUp = (gRsiNow > gRsiPrev);
   int  pdir = 0; bool pcounter = false;
   bool pHaveDir = DesiredDirection(pdir, pcounter);
   bool rsiOK    = pHaveDir ? RsiConfirms(pdir) : true;
   PanelRow(r++, "RSI 5M",
            StringFormat("%.1f  %s   %s: %s", gRsiNow, rsiUp ? "rising" : "falling",
                         RsiModeName(), rsiOK ? "ok" : "BLOCK"),
            PanelTextColor, rsiOK ? clrLime : clrTomato);

   if(EnableRsiExtreme)
     {
      string xTxt; color xClr;
      if(gXArmed)
        {
         xTxt = StringFormat("ARMED %s %s", gXDir > 0 ? "BUY" : "SELL", gXTag);
         xClr = clrGold;
        }
      else if(gXNeedsReset)
        {
         xTxt = StringFormat("cooling -> RSI %.0f", RsiXResetLevel);
         xClr = clrSilver;
        }
      else
        {
         xTxt = StringFormat("watching  1M %.0f  15M %.0f", gRsi1, gRsi15);
         xClr = clrSilver;
        }
      PanelRow(r++, "RSI-X", xTxt, PanelTextColor, xClr);
     }

   PanelRow(r++, "------------------------------------", "", C'70,76,90', C'70,76,90');

   //--- setup block ---------------------------------------------------------
   int  dir = 0; bool counter = false;
   bool haveDir = DesiredDirection(dir, counter);
   string modeTxt = !haveDir ? "none"
                    : StringFormat("%s (%s)", dir > 0 ? "BUY" : "SELL",
                                   counter ? "COUNTER" : "TREND");
   string tpTxt = !haveDir ? "-"
                  : StringFormat("TP %.0f", counter ? TakeProfitCounterPips
                                                    : TakeProfitTrendPips);
   PanelRow(r++, "MODE", modeTxt + "   " + tpTxt, PanelTextColor,
            !haveDir ? clrGray : (dir > 0 ? clrLime : clrTomato));

   double  shownLevel = (gEntryLevel > 0.0) ? gEntryLevel : gEma1S;
   PanelRow(r++, "LIMIT @",
            StringFormat("%s   %s EMA50%s", DoubleToString(shownLevel, gDigits),
                         EntryLevelTag(),
                         gEntryLevelSrc > 0 ? "  (fallback)" : ""),
            PanelTextColor, gEntryLevelSrc > 0 ? clrGold : clrDeepSkyBlue);

   PanelRow(r++, "STATUS", gStatus + "  " + gStatusDetail, PanelTextColor, gStatusColor);

   double spr = CurrentSpreadPips();
   PanelRow(r++, "SPREAD",
            StringFormat("%.0f pips   %s", spr, spr > MaxSpreadPips ? "WIDE" : "ok"),
            PanelTextColor, spr > MaxSpreadPips ? clrTomato : clrLime);

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
   for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
     {
      ulong pt = PositionGetTicket(pi);
      if(pt == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double popen = PositionGetDouble(POSITION_PRICE_OPEN);
      double ppl   = PositionGetDouble(POSITION_PROFIT)
                   + PositionGetDouble(POSITION_SWAP);
      string pcom  = PositionGetString(POSITION_COMMENT);

      PanelRow(r++, "  OPEN",
               StringFormat("%s %s @ %s  %+.2f",
                            ptype == POSITION_TYPE_BUY ? "BUY " : "SELL",
                            PositionLevelTag(pcom),
                            DoubleToString(popen, gDigits), ppl),
               PanelTextColor, ppl >= 0.0 ? clrLime : clrTomato);
     }

   double riskPct = 0.0; string why = "";
   double lot = CalcLot(StopLossPips * gPip, riskPct, why);
   PanelRow(r++, "NEXT LOT",
            lot > 0.0 ? StringFormat("%s   %.2f%%", DoubleToString(lot, 2), riskPct)
                      : "rejected: " + why,
            PanelTextColor, lot > 0.0 ? PanelTextColor : clrTomato);

   double dayPct = (gDayStartBalance > 0.0) ? gDayPL / gDayStartBalance * 100.0 : 0.0;
   string tradeCap = (MaxDailyTradeCount > 0)
                     ? StringFormat("%d / %d trades", gDayTrades, MaxDailyTradeCount)
                     : StringFormat("%d trades (no cap)", gDayTrades);
   PanelRow(r++, "TODAY",
            StringFormat("%+.2f  (%+.2f%%)    %s", gDayPL, dayPct, tradeCap),
            PanelTextColor, gDayPL < 0.0 ? clrTomato : clrLime);

   ChartRedraw();
  }

void PanelRow(const int row, const string label, const string value,
              const color labelClr, const color valueClr)
  {
   const int rowH = PanelFontSize + 7;
   PanelLabel(PFX + "PL" + IntegerToString(row), PanelX,
              PanelY + row * rowH, label, labelClr);
   if(value != "")
      PanelLabel(PFX + "PV" + IntegerToString(row), PanelX + 108,
                 PanelY + row * rowH, value, valueClr);
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
   ObjectSetString(0, name, OBJPROP_TEXT, text);
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
      double tpPips = counter ? TakeProfitCounterPips : TakeProfitTrendPips;
      double sl = (dir > 0) ? lvl - StopLossPips * gPip : lvl + StopLossPips * gPip;
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
