//+------------------------------------------------------------------+
//|                                        TripleEMA_Trend_v1.0.mq5   |
//|            1-minute trend scalper on a 9 / 21 / 50 EMA stack       |
//|                                                                   |
//|  Symbol  : XAUUSD and gold variants (XAUUSDc, XAUUSDm, GOLD...)   |
//|  TF      : M1 - one timeframe, no higher-TF bias                  |
//|  Account : built for an Exness USC (cent) account                 |
//|  Version : 1.00                                                   |
//|  Date    : 2026-09-16                                             |
//+------------------------------------------------------------------+
//
//  ================================================================
//                          STRATEGY SPEC
//  ================================================================
//  Requested 16 Sep 2026 as a replacement for TrendEMA (removed 14 Sep
//  after 0/12 in its last epoch). No bias, no permission timeframe -
//  the M1 EMA stack IS the trend, and the EA follows it both ways.
//
//  STACK (all reads at shift 1 - the last CLOSED bar - so nothing
//  repaints; entries are placed on the open of the next bar)
//    BULL :  EMA9 > EMA21 > EMA50
//    BEAR :  EMA9 < EMA21 < EMA50
//    NONE :  EMA9 in the middle  -> no trades, arms cleared
//
//  ENTRY (BUY; SELL mirrors)
//    1. Stack is BULL.
//    2. A bar has CLOSED BELOW EMA9 since the last entry - the pullback.
//       Without this, every bar of a trend that closes above EMA9
//       qualifies and the EA is simply always-in, which is not a scalp.
//       (v1.3: EntryMode chooses the qualifier - see that input. Default
//       is ANY_CLOSE, the rule as the operator stated it, with no pullback.)
//    3. The last closed bar closed ABOVE EMA9 and was bullish
//       (close > open). Then BUY at market on the new bar.
//
//  GEOMETRY
//    SL  = EMA50 (shift 1) minus SLBufferPips for a BUY / plus for a
//          SELL. Refused if that distance is under MinSLPips (lot would
//          balloon on a flat stack) or over MaxSLPips (entry is late).
//    TP  = RewardRatio x the SL distance. Default 1.5, from the
//          operator's example (stop 5.658 / target 8.462).
//    Both re-anchored to the ACTUAL fill price after the market order
//    returns, so a slipped fill keeps its intended distances.
//
//    Breakeven win rate = 1 / (1 + RewardRatio) = 40.0% at 1.5R.
//    Spread is ~26 pips on a typical ~550-pip stop here, so the real
//    figure to beat is closer to 41-42%. The panel derives it from
//    realised results once there is one win and one loss.
//
//  RISK
//    0.25% of equity per trade, one position at a time, daily loss
//    halt, spread cap, optional cooldown and session windows. Lot is
//    sized from the SL distance exactly as TrendEMA does (CalcLot).
//
//  PIP CONVENTION: 1 pip = 0.01 in price on gold = $0.01. Auto-detected
//  from digits (3-digit XAUUSDc -> pip = 10 points = 0.01).
//
//  ================================================================
//                             WARNING
//  ================================================================
//  THIS EA PLACES ORDERS AS SOON AS IT IS ATTACHED. Stop it with the
//  Algo Trading toggle, by removing it from the chart, or by dropping
//  TRIPLEEMA_STOP.txt into MQL5\Files. Removing it does NOT close an
//  open position - that keeps its SL/TP on the broker. Demo first.
//+------------------------------------------------------------------+
#property copyright "Aurora TripleEMA Trend EA"
#property version   "1.51"   // file is TripleEMA_Trend_v1.5.1 - bump both together
#property description "M1 scalper: EMA 9/21/50 stack sets direction, pullback below/above EMA9 then a same-colour close re-crossing it triggers a market entry. SL at EMA50, TP 1.5R."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| v1.3: how an entry is qualified once the stack is right            |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
  {
   ENTRY_ANY_CLOSE,           // Any same-colour close across EMA9 while flat (the operator spec, default)
   ENTRY_FIRST_THEN_PULLBACK, // First close after the stack forms, then a pullback before each later entry
   ENTRY_PULLBACK_ONLY,       // A close on the far side of EMA9 required before EVERY entry (v1.0-v1.2 rule)
   ENTRY_FIRST_THEN_TOUCH     // First close after the stack forms; after that every TOUCH of EMA9 from the trade side enters (a wick counts)
  };

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== TIMEFRAME / EMAS ==="
input ENUM_TIMEFRAMES EntryTF   = PERIOD_M1;   // Working timeframe (stack, pullback, trigger)
input int    EmaFastPeriod      = 9;           // Fast EMA
input int    EmaMidPeriod       = 21;          // Middle EMA
input int    EmaSlowPeriod      = 50;          // Slow EMA (stop-loss anchor)
input bool   RequireCandleColor = true;        // Trigger bar must close in the trade direction
//--- v1.3: the pullback requirement was an addition of mine, not part of the
//    spec, and checked against the eight example trades it fails three of
//    the seven winners including the two largest. Two of those (05:31 long,
//    07:55 short on 16 Sep) were the FIRST confirmation bar after the stack
//    formed - a pullback inside the new stack cannot exist yet, and clearing
//    the arms on the flip made those entries impossible. The third (06:02)
//    was a continuation with no close below EMA9. So the qualifier is now a
//    choice, defaulting to the rule as the operator stated it. The tester,
//    not the sample, should pick between them.
//--- v1.4: FIRST_THEN_TOUCH, at the operator request on 17 Sep 00:31. The
//    first entry in a stack still needs the confirming close; every entry
//    after it is a continuation and fires the moment price touches last
//    bar's EMA9 from the trade side - a wick is enough. Touch entries fill
//    at the EMA rather than a point past it, so the stop (EMA50) is the
//    stack width and 1.5R is nearer. The cost is that there is no
//    confirmation at all on those entries: at a trend's end the touch IS the
//    first tick of the reversal. Untested, like every mode here.
input ENUM_ENTRY_MODE EntryMode = ENTRY_FIRST_THEN_TOUCH; // What qualifies an entry once the stack is right
//--- v1.4.1: the close-rule "first entry" is only the first entry if the
//    stack is actually NEW. v1.4 decided that by whether THIS instance had
//    fired yet, so a re-attach in the middle of a two-hour bear stack (00:36
//    on 17 Sep) treated the next bearish close as a first entry and sold at
//    4342.24 with a 383-pip stop - no touch of EMA9, the exact entry the
//    touch mode exists to replace. Now the breakout window is measured in
//    bars since the stack formed, walked back from history on attach, so a
//    restart cannot mistake an old stack for a young one. Inside the window
//    the confirming close enters; after it, only a touch of EMA9 does.
input int    FirstEntryWindowBars = 3;         // Close-rule entries only within this many bars of the stack forming; after that, touch only
//--- v1.1: operator rule, 16 Sep - one position, and the NEXT entry only
//    after the trade is closed. The position cap already enforced the first
//    half. The second half needed this: a pullback seen WHILE a trade was
//    open used to leave the side armed, so the first bullish close after a
//    TP fired immediately with no pullback in between - a chase off the
//    exit, not the pullback-then-entry the method describes. Now every
//    close wipes both arms and the full cycle is required again.
input bool   ResetArmOnClose    = true;        // A closed trade clears the arm: fresh pullback needed before the next entry

input group "=== GEOMETRY ==="
input double RewardRatio        = 1.5;         // TP = this x SL distance (1.5 -> 40% breakeven)
//--- v1.0.1: both tightened toward the eight example trades the operator
//    drew on 16 Sep. Their stops sit ON the blue EMA50 line (09:42 short:
//    stop 4349.334 against EMA50 4349.292 - four pips), so a 20-pip buffer
//    was wider than the method. And two of the eight (05:03, 05:14) had
//    stops only ~90-100 pips out because EMA50 was that close; a 150-pip
//    floor would have REFUSED both. The floor exists only for degenerate
//    cases where a flat stack puts EMA50 on top of price: at 50 pips and
//    0.25% risk on ~28k the lot is ~1.4, still under the 2.0 cap.
input double SLBufferPips       = 5;           // Stop sits this far beyond EMA50 (5 = $0.05)
//--- v1.5.1, 17 Sep 2026: 50 -> 250, the operator's call after the first
//    full day (34 trades). The nine entries whose stop sat 210 pips or less
//    from the fill went 2/9 for -300.70; the other twenty-five went 11/25
//    for +179.10. Four of the nine were stopped inside 30 seconds, all in
//    the 21:56-22:27 block where the three EMAs sat within 80 pips of each
//    other, and the 22:00 buy (179p) slipped 87 pips on the fill and risked
//    0.48% - the biggest loss of the day at -100.30. With risk fixed at
//    0.25% a tight stop is NOT a small loss: the lot scales up, so it is
//    the same money with a far higher chance of being hit, plus fat-lot
//    slippage on top. 250 refuses those nine as logged. It also refuses the
//    two ~100-pip example trades from 16 Sep and the 00:21 sell that won
//    +78.40 on a 97p stop; the operator accepted that. As-logged only: with
//    one slot, removing a trade changes what fires next - re-run, never
//    subtract. Not tested in the Strategy Tester.
input double MinSLPips          = 250;         // Refuse if EMA50 is closer than this (flat stack: stop inside the noise)
//--- v1.4.2, 17 Sep 2026: 1500 -> 1000. The 10:15 sell at 4287.44 needed a
//    1093-pip stop, held for over ninety minutes on a scalper, and sat in
//    the only slot while a fresh BULL stack formed at 11:30 and a touch buy
//    at 4294.82 was logged as blocked by the position cap. The operator
//    asked first for an 800-pip TP cap; with risk fixed at 0.25% that only
//    shrinks the money per win (the lot scales to the stop), so the answer
//    is to refuse the late entry rather than to shorten its target. 1000
//    keeps 1.5R and the 40% breakeven and turns away entries where price
//    has already run 10.00 from the EMA50. On the ten trades to date it
//    would have refused three: +75.00 (1251p), -47.00 (1175p) and the open
//    1093p sell. Not tested in the Strategy Tester; nothing in this EA has
//    been yet.
input double MaxSLPips          = 1000;        // Refuse if EMA50 is further than this (entry is late)

input group "=== RISK ==="
input double RiskPercent        = 0.25;        // Risk per trade, % of capital
input double MaxRiskPercent     = 0.50;        // Hard ceiling - reject rather than clamp
input double MaxLotSizeCap      = 2.0;         // Absolute lot cap (0 = disabled)
input bool   SizeFromEquity     = true;        // Size from equity (false = balance)
input bool   UseFixedLot        = false;       // Fixed lot instead of % risk (EDGE TESTING ONLY)
input double FixedLotSize       = 0.01;        // Lot when UseFixedLot is on
input int    MaxConcurrentPositions = 1;       // Scalper: one at a time
//--- v1.3.3: the trigger bar must have OPENED after the last close. Twice on
//    16/17 Sep a take-profit filled on the first tick of a new bar and the EA
//    re-entered seconds later (51 s at 23:48, 4 s at 00:22) - the qualifying
//    bar was the bar the old trade had been open in. The operator's eight
//    example trades never re-enter on the same bar; the tightest gap is about
//    two minutes. This is narrower than the pullback modes: it keeps ANY_CLOSE
//    and the continuation entries, and removes only the zero-gap artefact.
//    1 = the trigger bar starts after the close. 2 = one full bar between.
input int    MinBarsAfterClose  = 1;           // Trigger bar must open this many bars after the last close (0 = off)
input int    MaxDailyTradeCount = 0;           // Max fills per day (0 = unlimited)
input double MaxDailyLossPercent= 3.0;         // Halt for the day at this realised loss % (0 = off)
input int    CooldownMinutesAfterLoss = 0;     // Wait after a losing close (0 = off)
//--- v1.5, 17 Sep 2026: TIME STOP. A position still open after this many
//    minutes is closed at market, whatever its P/L. The edge here is the
//    immediate continuation after a stack forms; a trade that has not paid
//    inside an hour is a stale premise holding the only slot. Record at the
//    time of writing, ten closed trades: every winner done inside 48 min,
//    every loser inside 34, and the single trade past an hour (the 10:15
//    sell, 106 min) was losing and had blocked a touch buy at 11:53.
//    The operator was told plainly what it costs: it cashes a drifting
//    trade at whatever it is, and one day that will be five pips from its
//    target. Chosen anyway. Runs even while the kill-switch file is present,
//    because closing a stale position is risk reduction, not a new entry.
//    NOTE: it applies to a position that is already open when the EA
//    attaches. 0 disables.
input int    MaxHoldMinutes     = 60;          // Close any position older than this at market (0 = off)
input int    DayResetHourET     = 12;          // Hour (ET) the day rolls over (12 = noon ET = midnight Manila)
input int    ETOffsetHours      = -4;          // ET offset from GMT: -4 Mar-Nov, -5 Nov-Mar
input double MaxSpreadPips      = 40;          // Skip entries if spread wider than this
input string SessionWindowsET   = "";          // Trade only inside these ET windows, e.g. "02:00-11:00" (empty = all hours)

input group "=== GUARDS ==="
input bool   SingleInstanceLock = true;        // Refuse to start if another copy is running
input bool   RequireGoldSymbol  = true;        // Refuse non-gold symbols
input double PipSizeOverride    = 0.0;         // Force a pip size (0 = auto-detect from digits)
input long   MagicNumber        = 7333;        // Trade identifier (TrendEMA 8888, SRLevels 9101)
input double MaxSlippagePips    = 10;          // Slippage tolerance on market orders
input string TradeCommentPrefix = "T3EMA";     // Order comment prefix
input bool   EnableHeartbeat    = true;        // Write a heartbeat file for an external watchdog
input string HeartbeatFile      = "TRIPLEEMA_HEARTBEAT.txt"; // Written to MQL5\Files
input string EmergencyStopFile  = "TRIPLEEMA_STOP.txt";      // Kill-switch file in MQL5\Files

input group "=== DISPLAY ==="
input bool   ShowPanel          = true;        // Show the on-chart status panel
//--- v1.2: the 9/21/50 EMAs on the chart in the colours the operator uses
//    (yellow / red / blue), via the companion indicator TripleEMA_Lines.
//    Drawn ONLY while the chart timeframe equals EntryTF: M1 lines on an H1
//    chart would be meaningless, and H1 lines would show a trend the EA does
//    not trade. On any other timeframe the panel says why they are hidden.
input bool   DrawEmas           = true;        // Draw the EMAs (needs TripleEMA_Lines.ex5 in MQL5\Indicators)
input int    PanelX             = 12;          // Panel X offset (pixels)
input int    PanelY             = 22;          // Panel Y offset (pixels)
input int    PanelFontSize      = 9;           // Panel font size
input color  PanelTextColor     = clrWhiteSmoke;  // Panel default text colour
input color  PanelBgColor       = C'18,20,26';    // Panel background

input group "=== ALERTS / DEBUG ==="
input bool   AlertOnFill        = true;        // Popup when an order fills
input bool   AlertOnClose       = true;        // Popup when a position closes
input bool   VerboseLog         = false;       // Log every gate decision

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade   gTrade;
const string PFX = "T3EMA_";

int      hEmaF = INVALID_HANDLE;
int      hEmaM = INVALID_HANDLE;
int      hEmaS = INVALID_HANDLE;

double   gPoint = 0.0;
double   gPip   = 0.0;
double   gTick  = 0.0;
int      gDigits = 0;
bool     gInitOk = false;
bool     gHoldsLock = false;
uint     gLastLockMs = 0;

//--- shift-1 reads (the last CLOSED bar)
double   gEmaF1 = 0.0, gEmaM1 = 0.0, gEmaS1 = 0.0;
double   gClose1 = 0.0, gOpen1 = 0.0;
datetime gLastBar = 0;        // open time of the FORMING bar we last saw
datetime gSkipLogBar    = 0;  // v1.5.1: a refused entry logs once per bar per reason (43 cap refusals in five minutes on 17 Sep)
int      gSkipLogReason = 0;
int      gStack   = 0;        // +1 bull, -1 bear, 0 none
int      gLastStack = 0;
bool     gArmBuy  = false;    // a close below EMA9 has been seen in a BULL stack
bool     gArmSell = false;    // a close above EMA9 has been seen in a BEAR stack
string   gArmText = "-";
//--- v1.4: touch mode. Armed once the stack has had its first (close-rule)
//    entry; then a tick reaching last bar's EMA9 FROM THE TRADE SIDE fires.
//    "From the trade side" is the whole safety of it: right after a stop-out
//    price sits beyond EMA9, and "at or past the line" would re-enter on the
//    very rally that just stopped us. So price must first be back on the
//    trend side of EMA9 and then come back to touch it.
bool     gTouchArmed     = false;
int      gStackAge       = 0;      // v1.4.1: bars the current stack has held, counted from history on attach
bool     gWasOnTradeSide = false;
bool     gTouchSideInit  = false;
string   gLastSignal = "none yet";

//--- status
string   gStatus = "STARTING";
string   gStatusDetail = "";
color    gStatusClr = clrGray;
string   gPhase = "INIT";

//--- kill switch
bool     gStopFilePresent = false;
uint     gLastStopChkMs = 0;

//--- day / stats
long     gDayIndex = -1;
datetime gDayStart = 0;
double   gDayStartBalance = 0.0;
double   gDayPL = 0.0;
int      gDayTrades = 0, gDayWins = 0, gDayLosses = 0;
datetime gLastLossTime = 0;
datetime gLastCloseTime = 0;   // v1.3.3: last OUT deal of ours, any result - rebuilt from history on attach
int      gAllWins = 0, gAllLosses = 0, gAllStreak = 0, gAllBestWin = 0, gAllWorstLoss = 0;
double   gAllGrossWin = 0.0, gAllGrossLoss = 0.0;   // gross loss stored POSITIVE
//--- v1.1: trade durations, paired IN->OUT by position id. The operator
//    asked for the average time in trade; the win/loss split is the useful
//    part - with the stop nearer than the target, losers should die fast
//    and winners run, and a drift in either says something about the tape.
long     gAllDurSum = 0, gWinDurSum = 0, gLossDurSum = 0, gDayDurSum = 0;
int      gAllDurN = 0,   gWinDurN = 0,   gLossDurN = 0,   gDayDurN = 0;

//--- v1.2: EMA lines on the chart
int      hLines = INVALID_HANDLE;
bool     gLinesOnChart = false;
string   gLinesName = "";
bool     gLinesWarned = false;
uint     gLinesRetryMs = 0;   // v1.3.1: throttle for the add-to-chart retry
int      gLinesFails   = 0;   // v1.3.2: consecutive add failures (recreate the handle after a run of them)
uint     gLinesLastLogMs = 0; // v1.3.2: at most one "still retrying" line per minute

//--- panel
int      gPanelMaxW = 0;
int      gPanelRowsDrawn = 0;
datetime gStartTime = 0;
uint     gLastTickMs = 0;
uint     gLastHeartbeatMs = 0;

//+------------------------------------------------------------------+
//| Small helpers                                                     |
//+------------------------------------------------------------------+
string LockName() { return(StringFormat("T3EMA_LOCK_%s_%d", _Symbol, (int)MagicNumber)); }

void TouchLock()
  {
   if(!SingleInstanceLock || MQLInfoInteger(MQL_TESTER)) return;
   uint now = GetTickCount();
   if(gLastLockMs != 0 && (now - gLastLockMs) < 5000) return;
   gLastLockMs = now;
   GlobalVariableSet(LockName(), (double)TimeLocal());
  }

double SnapPrice(const double p)
  {
   if(gTick <= 0.0) return(NormalizeDouble(p, gDigits));
   return(NormalizeDouble(MathRound(p / gTick) * gTick, gDigits));
  }

double CurrentSpreadPips()
  {
   return((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / gPip);
  }

bool CopyOne(const int handle, const int shift, double &out)
  {
   double b[];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1) return(false);
   out = b[0];
   return(true);
  }

void SetStatus(const string s, const string detail, const color clr)
  {
   if(VerboseLog && (s != gStatus || detail != gStatusDetail))
      PrintFormat("[T3EMA] %s: %s", s, detail);
   gStatus = s; gStatusDetail = detail; gStatusClr = clr;
  }

int VolumeDigits(const double step)
  {
   if(step >= 1.0)   return(0);
   if(step >= 0.1)   return(1);
   if(step >= 0.01)  return(2);
   return(3);
  }

//+------------------------------------------------------------------+
//| Time windows (ET), same grammar as TrendEMA                        |
//+------------------------------------------------------------------+
datetime NowET() { return(TimeGMT() + (datetime)(ETOffsetHours * 3600)); }

bool InWindowList(const string spec, const datetime when)
  {
   if(spec == "") return(false);
   MqlDateTime dt; TimeToStruct(when, dt);
   int nowMin = dt.hour * 60 + dt.min;
   string parts[];
   int n = StringSplit(spec, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string w = parts[i]; StringTrimLeft(w); StringTrimRight(w);
      string ends[];
      if(StringSplit(w, '-', ends) != 2) continue;
      string a[], b[];
      if(StringSplit(ends[0], ':', a) != 2 || StringSplit(ends[1], ':', b) != 2) continue;
      int fromMin = (int)StringToInteger(a[0]) * 60 + (int)StringToInteger(a[1]);
      int toMin   = (int)StringToInteger(b[0]) * 60 + (int)StringToInteger(b[1]);
      if(fromMin <= toMin) { if(nowMin >= fromMin && nowMin <= toMin) return(true); }
      else                 { if(nowMin >= fromMin || nowMin <= toMin) return(true); }
     }
   return(false);
  }

bool InSession()
  {
   if(SessionWindowsET == "") return(true);
   return(InWindowList(SessionWindowsET, NowET()));
  }

//+------------------------------------------------------------------+
//| Day rollover and statistics (history is authoritative)            |
//+------------------------------------------------------------------+
long CurrentDayIndex()
  {
   datetime etNow = NowET();
   return((long)MathFloor((double)(etNow - DayResetHourET * 3600) / 86400.0));
  }

datetime DayStartServerTime()
  {
   long   idx = CurrentDayIndex();
   double boundaryET = (double)idx * 86400.0 + DayResetHourET * 3600.0;
   datetime boundaryGMT = (datetime)(boundaryET - ETOffsetHours * 3600);
   int serverGmtOffset = (int)(TimeTradeServer() - TimeGMT());
   return(boundaryGMT + serverGmtOffset);
  }

void ResetDayState(const bool firstRun)
  {
   gDayIndex = CurrentDayIndex();
   gDayStart = DayStartServerTime();
   gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gDayTrades = 0; gDayPL = 0.0; gLastLossTime = 0;
   if(!firstRun)
      PrintFormat("[T3EMA] New trading day (%02d:00 ET rollover). Counters reset, daily halt lifted.", DayResetHourET);
  }

//--- select FIRST, zero SECOND: a failed HistorySelect must never read as a flat day
void RefreshDailyStats()
  {
   if(!HistorySelect(gDayStart, TimeCurrent() + 60))
     {
      PrintFormat("[T3EMA] HistorySelect failed - keeping previous daily figures (P/L %.2f, %d trades).", gDayPL, gDayTrades);
      return;
     }
   gDayPL = 0.0; gDayTrades = 0; gDayWins = 0; gDayLosses = 0; gLastLossTime = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)     continue;
      double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      gDayPL += net;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN) gDayTrades++;
      if(entry == DEAL_ENTRY_OUT)
        {
         if(net > 0.0) gDayWins++; else if(net < 0.0) gDayLosses++;
         if(net < 0.0)
           {
            datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
            if(dt > gLastLossTime) gLastLossTime = dt;
           }
        }
     }
   //--- derive the day-start balance rather than capture it at attach, so a
   //    re-attach mid-day does not re-baseline the halt to the reduced balance
   gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - gDayPL;
  }

//--- all-time for THIS magic. A fresh magic number is its own epoch, so no
//    config-signature machinery in v1.0: changing inputs does NOT reset these.
void RefreshAllTimeStats()
  {
   if(!HistorySelect(0, TimeCurrent() + 60)) return;
   gAllWins = 0; gAllLosses = 0; gAllStreak = 0; gAllBestWin = 0; gAllWorstLoss = 0;
   gAllGrossWin = 0.0; gAllGrossLoss = 0.0;
   gAllDurSum = 0; gWinDurSum = 0; gLossDurSum = 0; gDayDurSum = 0;
   gAllDurN = 0;   gWinDurN = 0;   gLossDurN = 0;   gDayDurN = 0;
   long     inPos[];  datetime inTime[];   // open legs awaiting their close
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)     continue;
      ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY);
      long     posId = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      datetime dTime = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      if(de == DEAL_ENTRY_IN)
        {
         int n = ArraySize(inPos);
         ArrayResize(inPos, n + 1); ArrayResize(inTime, n + 1);
         inPos[n] = posId; inTime[n] = dTime;
         continue;
        }
      if(de != DEAL_ENTRY_OUT && de != DEAL_ENTRY_INOUT) continue;
      //--- duration: find the IN leg of this position (linear scan; a few
      //    hundred trades at most, and history is chronological)
      long dur = -1;
      for(int k = ArraySize(inPos) - 1; k >= 0; k--)
         if(inPos[k] == posId) { dur = (long)(dTime - inTime[k]); break; }
      if(dur >= 0)
        {
         gAllDurSum += dur; gAllDurN++;
         if(dTime >= gDayStart) { gDayDurSum += dur; gDayDurN++; }
        }
      if(dTime > gLastCloseTime) gLastCloseTime = dTime;   // v1.3.3
      double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      if(net > 0.0)
        {
         gAllWins++; gAllGrossWin += net;
         if(dur >= 0) { gWinDurSum += dur; gWinDurN++; }
         gAllStreak = (gAllStreak > 0) ? gAllStreak + 1 : 1;
         if(gAllStreak > gAllBestWin) gAllBestWin = gAllStreak;
        }
      else if(net < 0.0)
        {
         gAllLosses++; gAllGrossLoss += -net;
         if(dur >= 0) { gLossDurSum += dur; gLossDurN++; }
         gAllStreak = (gAllStreak < 0) ? gAllStreak - 1 : -1;
         if(gAllStreak < gAllWorstLoss) gAllWorstLoss = gAllStreak;
        }
     }
  }

//+------------------------------------------------------------------+
//| Positions                                                         |
//+------------------------------------------------------------------+
//--- v1.5: the time stop. Called every tick; cheap, one loop over our
//    positions. Closes by ticket so a hedging account cannot net the wrong
//    side. Logs the age and the P/L it took, so the cost of the rule is
//    visible in the log rather than only in the equity curve.
void EnforceMaxHold()
  {
   if(MaxHoldMinutes <= 0) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      long age = (long)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME));
      if(age < (long)MaxHoldMinutes * 60) continue;
      double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(gTrade.PositionClose(t))
        {
         PrintFormat("[T3EMA] TIME STOP: closed %s #%I64u after %d min (limit %d) at P/L %+.2f",
                     isBuy ? "BUY" : "SELL", t, (int)(age / 60), MaxHoldMinutes, pl);
         SetStatus("TIME STOP", StringFormat("%s closed after %d min at %+.2f", isBuy ? "BUY" : "SELL", (int)(age / 60), pl), clrOrange);
        }
      else
         PrintFormat("[T3EMA] TIME STOP: close of #%I64u failed (%d): %s", t, gTrade.ResultRetcode(), gTrade.ResultComment());
     }
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      n++;
     }
   return(n);
  }

double OpenRiskPercent()
  {
   double cap = AccountInfoDouble(ACCOUNT_EQUITY);
   if(cap <= 0.0) return(0.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSz <= 0.0) return(0.0);
   double risk = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) continue;
      double dist = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl);
      risk += PositionGetDouble(POSITION_VOLUME) * (dist / tickSz) * tickVal;
     }
   return(risk / cap * 100.0);
  }

//+------------------------------------------------------------------+
//| Lot sizing - lifted from TrendEMA CalcLot                          |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, double &riskPctOut, string &reason)
  {
   riskPctOut = 0.0; reason = "";
   double capital = SizeFromEquity ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   if(capital <= 0.0) { reason = "capital is zero"; return(0.0); }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   int vd = VolumeDigits(step);

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSz <= 0.0) { reason = "broker tick value/size unavailable"; return(0.0); }
   double lossPerLot = (slDistance / tickSz) * tickVal;
   if(lossPerLot <= 0.0) { reason = "loss per lot computed as zero"; return(0.0); }

   if(UseFixedLot)
     {
      double flot = NormalizeDouble(MathFloor(FixedLotSize / step) * step, vd);
      if(flot < minLot) flot = minLot;
      if(flot > maxLot) flot = maxLot;
      riskPctOut = (flot * lossPerLot) / capital * 100.0;
      return(flot);
     }

   double raw = (capital * RiskPercent / 100.0) / lossPerLot;
   double lot = NormalizeDouble(MathFloor(raw / step) * step, vd);   // round DOWN
   if(lot < minLot)
     {
      lot = minLot;
      double pct = (lot * lossPerLot) / capital * 100.0;
      if(pct > MaxRiskPercent)
        {
         reason = StringFormat("min lot %.2f risks %.2f%% > %.2f%% ceiling", lot, pct, MaxRiskPercent);
         return(0.0);
        }
     }
   if(lot > maxLot) lot = maxLot;
   if(MaxLotSizeCap > 0.0 && lot > MaxLotSizeCap) lot = MaxLotSizeCap;
   lot = NormalizeDouble(lot, vd);
   if(lot <= 0.0) { reason = "computed lot is zero"; return(0.0); }

   riskPctOut = (lot * lossPerLot) / capital * 100.0;
   if(riskPctOut > MaxRiskPercent + 0.0001)
     {
      reason = StringFormat("risk %.2f%% exceeds %.2f%% ceiling", riskPctOut, MaxRiskPercent);
      return(0.0);
     }
   double margin = 0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin))
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { reason = "insufficient free margin"; return(0.0); }
   return(lot);
  }

//+------------------------------------------------------------------+
//| Indicators - shift 1 only, refreshed once per closed bar           |
//+------------------------------------------------------------------+
bool RefreshIndicators()
  {
   double c[], o[];
   if(CopyClose(_Symbol, EntryTF, 1, 1, c) != 1) return(false);
   if(CopyOpen (_Symbol, EntryTF, 1, 1, o) != 1) return(false);
   if(!CopyOne(hEmaF, 1, gEmaF1)) return(false);
   if(!CopyOne(hEmaM, 1, gEmaM1)) return(false);
   if(!CopyOne(hEmaS, 1, gEmaS1)) return(false);
   gClose1 = c[0]; gOpen1 = o[0];

   if(gEmaF1 > gEmaM1 && gEmaM1 > gEmaS1)      gStack =  1;
   else if(gEmaF1 < gEmaM1 && gEmaM1 < gEmaS1) gStack = -1;
   else                                        gStack =  0;
   return(true);
  }

//+------------------------------------------------------------------+
//| v1.4.1: how many closed bars the current stack has held. Walks back  |
//| from shift 1 while the EMA order matches; capped, so a stack older    |
//| than the cap just reads as the cap.                                   |
//+------------------------------------------------------------------+
int StackAgeFromHistory(const int cap = 300)
  {
   if(gStack == 0) return(0);
   double f[], m[], sl[];
   if(CopyBuffer(hEmaF, 0, 1, cap, f) != cap) return(1);
   if(CopyBuffer(hEmaM, 0, 1, cap, m) != cap) return(1);
   if(CopyBuffer(hEmaS, 0, 1, cap, sl) != cap) return(1);
   //--- CopyBuffer into a plain array is oldest-first: index cap-1 is shift 1
   int age = 0;
   for(int i = cap - 1; i >= 0; i--)
     {
      int st = (f[i] > m[i] && m[i] > sl[i]) ? 1 : ((f[i] < m[i] && m[i] < sl[i]) ? -1 : 0);
      if(st != gStack) break;
      age++;
     }
   return(age);
  }

//+------------------------------------------------------------------+
//| Gates that apply to any new entry                                 |
//+------------------------------------------------------------------+
bool EntryGatesOpen(string &why, const int trigShift = 1)
  {
   if(gStopFilePresent)                        { why = "kill-switch file present";              return(false); }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { why = "algo trading disabled in terminal"; return(false); }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))      { why = "EA not allowed to trade (Common tab)";  return(false); }
   if(!InSession())                            { why = "outside session window " + SessionWindowsET; return(false); }
   if(MaxDailyLossPercent > 0.0 && gDayStartBalance > 0.0 &&
      gDayPL <= -(gDayStartBalance * MaxDailyLossPercent / 100.0))
                                               { why = StringFormat("daily loss halt %.2f%%", MaxDailyLossPercent); return(false); }
   if(MaxDailyTradeCount > 0 && gDayTrades >= MaxDailyTradeCount)
                                               { why = StringFormat("daily trade cap %d/%d", gDayTrades, MaxDailyTradeCount); return(false); }
   if(CooldownMinutesAfterLoss > 0 && gLastLossTime > 0 &&
      TimeCurrent() < gLastLossTime + CooldownMinutesAfterLoss * 60)
                                               { why = StringFormat("cooldown %d min after a loss", CooldownMinutesAfterLoss); return(false); }
   if(CountPositions() >= MaxConcurrentPositions)
                                               { why = StringFormat("position cap %d reached", MaxConcurrentPositions); return(false); }
   //--- v1.3.3: no same-bar re-entry. The bar being acted on (shift 1) must
   //    have opened at least MinBarsAfterClose periods after the last close;
   //    with 1 that means strictly after it, so a TP that fills on the first
   //    tick of a bar cannot be followed by an entry off that same bar.
   if(MinBarsAfterClose > 0 && gLastCloseTime > 0)
     {
      //--- close-rule entries act on the shift-1 bar; a touch entry happens
      //    inside the FORMING bar, so it passes trigShift = 0
      datetime trigOpen = iTime(_Symbol, EntryTF, trigShift);
      datetime need     = gLastCloseTime + (datetime)((MinBarsAfterClose - 1) * PeriodSeconds(EntryTF));
      if(!(trigOpen > need))
        {
         why = StringFormat("trigger bar %s overlaps the last close %s - needs a fresh bar",
                            TimeToString(trigOpen, TIME_MINUTES), TimeToString(gLastCloseTime, TIME_MINUTES | TIME_SECONDS));
         return(false);
        }
     }
   double sp = CurrentSpreadPips();
   if(sp > MaxSpreadPips)                      { why = StringFormat("spread %.0fp > %.0fp", sp, MaxSpreadPips); return(false); }
   return(true);
  }

//+------------------------------------------------------------------+
//| v1.5.1: a touch re-fires on every re-cross of EMA9, so a refused    |
//| entry in a flat stack would log on every tick. One line per bar per |
//| reason; the panel STATUS row carries the live text anyway.          |
//+------------------------------------------------------------------+
bool SkipLogDue(const int reason)
  {
   datetime bar = iTime(_Symbol, EntryTF, 0);
   if(bar == gSkipLogBar && reason == gSkipLogReason) return(false);
   gSkipLogBar = bar; gSkipLogReason = reason;
   return(true);
  }

//+------------------------------------------------------------------+
//| Fire a market entry with SL at EMA50 and TP = RewardRatio x SL     |
//+------------------------------------------------------------------+
void Fire(const int dir)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price   = (dir > 0) ? ask : bid;
   double slLevel = (dir > 0) ? gEmaS1 - SLBufferPips * gPip : gEmaS1 + SLBufferPips * gPip;

   //--- the stop must be on the correct side of the market
   if((dir > 0 && slLevel >= price) || (dir < 0 && slLevel <= price))
     {
      SetStatus("SKIP", StringFormat("%s refused - price already through EMA50 (%.2f)", dir > 0 ? "BUY" : "SELL", gEmaS1), clrOrange);
      return;
     }
   double slDist = MathAbs(price - slLevel);
   double slPips = slDist / gPip;
   if(slPips < MinSLPips)
     {
      SetStatus("SKIP", StringFormat("%s refused - EMA50 only %.0fp away (< %.0fp min)", dir > 0 ? "BUY" : "SELL", slPips, MinSLPips), clrOrange);
      if(SkipLogDue(1)) PrintFormat("[T3EMA] %s SKIPPED: stop would be %.0f pips - below MinSLPips %.0f. Flat stack: the stop would sit inside the bar-to-bar noise.", dir > 0 ? "BUY" : "SELL", slPips, MinSLPips);
      return;
     }
   if(slPips > MaxSLPips)
     {
      SetStatus("SKIP", StringFormat("%s refused - EMA50 is %.0fp away (> %.0fp max)", dir > 0 ? "BUY" : "SELL", slPips, MaxSLPips), clrOrange);
      if(SkipLogDue(2)) PrintFormat("[T3EMA] %s SKIPPED: stop would be %.0f pips - above MaxSLPips %.0f. Price has run far from EMA50; this entry is late.", dir > 0 ? "BUY" : "SELL", slPips, MaxSLPips);
      return;
     }
   long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLvl > 0 && slDist < stopsLvl * gPoint)
     {
      SetStatus("SKIP", "stop inside broker stops_level", clrOrange);
      return;
     }

   double riskPct = 0.0; string why = "";
   double lot = CalcLot(slDist, riskPct, why);
   if(lot <= 0.0)
     {
      SetStatus("REJECT", why, clrRed);
      PrintFormat("[T3EMA] %s REJECTED by sizing: %s", dir > 0 ? "BUY" : "SELL", why);
      return;
     }

   double sl = SnapPrice(slLevel);
   double tp = SnapPrice((dir > 0) ? price + RewardRatio * slDist : price - RewardRatio * slDist);
   string comment = TradeCommentPrefix + (dir > 0 ? "-BUY" : "-SELL");

   bool ok = (dir > 0) ? gTrade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
                       : gTrade.Sell(lot, _Symbol, 0.0, sl, tp, comment);
   if(!ok)
     {
      PrintFormat("[T3EMA] %s FAILED: retcode %d (%s)", dir > 0 ? "BUY" : "SELL", (int)gTrade.ResultRetcode(), gTrade.ResultRetcodeDescription());
      SetStatus("ERROR", StringFormat("order failed %d", (int)gTrade.ResultRetcode()), clrRed);
      return;
     }

   //--- re-anchor SL/TP to the ACTUAL fill so a slipped fill keeps its
   //    intended distances. ResultPrice is populated for synchronous fills.
   double fill = gTrade.ResultPrice();
   if(fill > 0.0 && MathAbs(fill - price) >= gTick)
     {
      //--- v1.3.1: the stop is STRUCTURAL in this strategy - "on the EMA50" -
      //    so it stays at slLevel however the fill slipped, and only the
      //    target moves, so the trade still pays RewardRatio on the distance
      //    actually being risked. v1.3 inherited the TrendEMA re-anchor, which
      //    preserves pip DISTANCE and therefore walked the stop off the
      //    structure by the slippage: first live fill, 16 Sep 22:57, ask at
      //    send ~4349.53, filled 4349.73, EMA50 4342.71 - the stop landed at
      //    4342.86, fifteen pips ABOVE the line it was meant to sit under.
      //    Risk moves with the slip instead (adverse slip = slightly more
      //    risk, favourable = slightly less); the log prints the real figure.
      double slDist2 = MathAbs(fill - slLevel);
      double sl2 = SnapPrice(slLevel);
      double tp2 = SnapPrice((dir > 0) ? fill + RewardRatio * slDist2 : fill - RewardRatio * slDist2);
      riskPct *= (slDist2 / slDist);
      slPips   = slDist2 / gPip;
      ulong posTicket = gTrade.ResultOrder();
      // find the position by magic/symbol opened just now
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
         if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - fill) > gTick) continue;
         if(gTrade.PositionModify(t, sl2, tp2))
            PrintFormat("[T3EMA] Slipped %.0fp on fill (%.2f -> %.2f). Stop kept on EMA50 at %.2f, TP moved to %.2f (%.1fR on %.0fp), risk now %.2f%%.",
                        MathAbs(fill - price) / gPip, price, fill, sl2, tp2, RewardRatio, slPips, riskPct);
         break;
        }
      sl = sl2; tp = tp2; price = fill;
     }

   gLastSignal = StringFormat("%s @ %.2f  SL %.2f (%.0fp)  TP %.2f  lot %.2f  %.2f%%",
                              dir > 0 ? "BUY" : "SELL", price, sl, slPips, tp, lot, riskPct);
   PrintFormat("[T3EMA] %s FILLED %.2f lots @ %.2f  SL %.2f (%.0f pips, EMA50 %.2f)  TP %.2f (%.1fR)  risk %.2f%%  stack %s",
               dir > 0 ? "BUY" : "SELL", lot, price, sl, slPips, gEmaS1, tp, RewardRatio, riskPct,
               gStack > 0 ? "BULL" : "BEAR");
   if(AlertOnFill)
      Alert(StringFormat("T3EMA %s %.2f @ %.2f  SL %.2f  TP %.2f", dir > 0 ? "BUY" : "SELL", lot, price, sl, tp));
   SetStatus("FILLED", gLastSignal, clrLime);
  }

//+------------------------------------------------------------------+
//| The trigger - runs once per new closed bar                        |
//+------------------------------------------------------------------+
void Evaluate()
  {
   //--- a stack change clears any pending arm: a pullback inside the OLD
   //    trend is not a setup in the new one. In FIRST_THEN_PULLBACK the new
   //    stack arrives pre-armed, so its first confirmation bar can enter.
   if(gStack != gLastStack)
     {
      gArmBuy = false; gArmSell = false;
      gTouchArmed = false; gTouchSideInit = false;     // v1.4: a new stack needs its own first close
      gStackAge = (gStack == 0) ? 0 : 1;                // v1.4.1: this closed bar is the first of the new stack
      if(EntryMode == ENTRY_FIRST_THEN_PULLBACK)
        {
         if(gStack > 0) gArmBuy  = true;
         if(gStack < 0) gArmSell = true;
        }
     }
   else if(gStack != 0)
      gStackAge++;                                      // v1.4.1: same stack, one more closed bar
   gLastStack = gStack;

   //--- v1.4.1: once the breakout window has passed, continuations are touches
   //    whether or not a close-rule entry ever fired in this stack
   if(EntryMode == ENTRY_FIRST_THEN_TOUCH && gStack != 0 && !gTouchArmed && gStackAge > FirstEntryWindowBars)
     {
      gTouchArmed = true; gTouchSideInit = false;
      PrintFormat("[T3EMA] Stack is %d bars old (window %d) - entries from here are touches of EMA9 only.", gStackAge, FirstEntryWindowBars);
     }

   if(gStack == 0)
     {
      gArmText = "-";
      SetStatus("WAIT", "EMA9 in the middle - no stack, no trades", clrGray);
      return;
     }

   string why = "";
   if(gStack > 0)
     {
      gArmSell = false;
      if(gClose1 < gEmaF1)
        {
         gArmBuy = true;
         if(EntryMode == ENTRY_FIRST_THEN_TOUCH)
           {
            gArmText = gTouchArmed ? StringFormat("TOUCH armed - buy when price comes back up to EMA9 %.2f", gEmaF1)
                                   : StringFormat("BULL stack %d bars old - last bar closed below EMA9", gStackAge);
            SetStatus("WAIT", gTouchArmed ? "below EMA9 - buy on the touch back up" : "young bull stack, last close under EMA9", PanelTextColor);
            return;
           }
         gArmText = (EntryMode == ENTRY_ANY_CLOSE)
                    ? "BULL stack - last bar closed below EMA9, next bullish close above it enters"
                    : "BUY armed - closed below EMA9, waiting for a bullish close back above";
         SetStatus(EntryMode == ENTRY_ANY_CLOSE ? "WAIT" : "ARMED", "BUY - last close under EMA9", clrDeepSkyBlue);
         return;
        }
      bool colourOk = !RequireCandleColor || gClose1 > gOpen1;
      bool armOk    = (EntryMode == ENTRY_ANY_CLOSE)
                   || (EntryMode == ENTRY_FIRST_THEN_TOUCH && !gTouchArmed && gStackAge <= FirstEntryWindowBars)   // v1.4.1: first entry, and only while the stack is young
                   || (EntryMode != ENTRY_FIRST_THEN_TOUCH && gArmBuy);
      if(gClose1 > gEmaF1 && colourOk && armOk)
        {
         if(!EntryGatesOpen(why)) { SetStatus("BLOCKED", "BUY signal but " + why, clrOrange); return; }
         Fire(1);
         gArmBuy = false;
         if(EntryMode == ENTRY_FIRST_THEN_TOUCH) { gTouchArmed = true; gTouchSideInit = false; gArmText = "BUY fired - continuations now fire on any touch of EMA9 from above"; }
         else gArmText = "BUY fired - needs a new pullback";
         return;
        }
      if(EntryMode == ENTRY_FIRST_THEN_TOUCH)
        {
         gArmText = gTouchArmed ? StringFormat("TOUCH armed - buy the moment price dips to EMA9 %.2f (wick counts)", gEmaF1)
                                : StringFormat("BULL stack %d bars old - first bullish close above EMA9 enters (window %d)", gStackAge, FirstEntryWindowBars);
         SetStatus("WAIT", gTouchArmed ? "buy on touch of EMA9" : "bull stack, first confirming close not seen yet", PanelTextColor);
         return;
        }
      if(EntryMode == ENTRY_ANY_CLOSE)
        {
         gArmText = "BULL stack - next bullish close above EMA9 enters";
         SetStatus("WAIT", "bull stack, last bar not a bullish close above EMA9", PanelTextColor);
        }
      else
        {
         gArmText = gArmBuy ? "BUY armed - waiting for a bullish close above EMA9"
                            : "BULL stack - waiting for a pullback below EMA9";
         SetStatus("WAIT", gArmBuy ? "BUY armed, last bar not a bullish close above EMA9" : "bull stack, no pullback yet", PanelTextColor);
        }
      return;
     }

   //--- bear mirror
   gArmBuy = false;
   if(gClose1 > gEmaF1)
     {
      gArmSell = true;
      if(EntryMode == ENTRY_FIRST_THEN_TOUCH)
        {
         gArmText = gTouchArmed ? StringFormat("TOUCH armed - sell when price comes back down to EMA9 %.2f", gEmaF1)
                                : StringFormat("BEAR stack %d bars old - last bar closed above EMA9", gStackAge);
         SetStatus("WAIT", gTouchArmed ? "above EMA9 - sell on the touch back down" : "young bear stack, last close over EMA9", PanelTextColor);
         return;
        }
      gArmText = (EntryMode == ENTRY_ANY_CLOSE)
                 ? "BEAR stack - last bar closed above EMA9, next bearish close below it enters"
                 : "SELL armed - closed above EMA9, waiting for a bearish close back below";
      SetStatus(EntryMode == ENTRY_ANY_CLOSE ? "WAIT" : "ARMED", "SELL - last close over EMA9", clrDeepSkyBlue);
      return;
     }
   bool colourOkS = !RequireCandleColor || gClose1 < gOpen1;
   bool armOkS    = (EntryMode == ENTRY_ANY_CLOSE)
                 || (EntryMode == ENTRY_FIRST_THEN_TOUCH && !gTouchArmed && gStackAge <= FirstEntryWindowBars)
                 || (EntryMode != ENTRY_FIRST_THEN_TOUCH && gArmSell);
   if(gClose1 < gEmaF1 && colourOkS && armOkS)
     {
      if(!EntryGatesOpen(why)) { SetStatus("BLOCKED", "SELL signal but " + why, clrOrange); return; }
      Fire(-1);
      gArmSell = false;
      if(EntryMode == ENTRY_FIRST_THEN_TOUCH) { gTouchArmed = true; gTouchSideInit = false; gArmText = "SELL fired - continuations now fire on any touch of EMA9 from below"; }
      else gArmText = "SELL fired - needs a new pullback";
      return;
     }
   if(EntryMode == ENTRY_FIRST_THEN_TOUCH)
     {
      gArmText = gTouchArmed ? StringFormat("TOUCH armed - sell the moment price rises to EMA9 %.2f (wick counts)", gEmaF1)
                             : StringFormat("BEAR stack %d bars old - first bearish close below EMA9 enters (window %d)", gStackAge, FirstEntryWindowBars);
      SetStatus("WAIT", gTouchArmed ? "sell on touch of EMA9" : "bear stack, first confirming close not seen yet", PanelTextColor);
      return;
     }
   if(EntryMode == ENTRY_ANY_CLOSE)
     {
      gArmText = "BEAR stack - next bearish close below EMA9 enters";
      SetStatus("WAIT", "bear stack, last bar not a bearish close below EMA9", PanelTextColor);
     }
   else
     {
      gArmText = gArmSell ? "SELL armed - waiting for a bearish close below EMA9"
                          : "BEAR stack - waiting for a pullback above EMA9";
      SetStatus("WAIT", gArmSell ? "SELL armed, last bar not a bearish close below EMA9" : "bear stack, no pullback yet", PanelTextColor);
     }
  }

//+------------------------------------------------------------------+
//| v1.4: touch entries - runs on EVERY tick, unlike Evaluate            |
//+------------------------------------------------------------------+
void CheckTouchEntry()
  {
   if(EntryMode != ENTRY_FIRST_THEN_TOUCH || !gTouchArmed || gStack == 0 || gEmaF1 <= 0.0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   //--- "on the trade side" = beyond EMA9 in the direction of the trend:
   //    above it in a bull stack, below it in a bear stack. The level is
   //    last bar's EMA9, fixed for the whole bar, so nothing repaints.
   bool onSide = (gStack > 0) ? (bid > gEmaF1) : (ask < gEmaF1);
   if(!gTouchSideInit) { gWasOnTradeSide = onSide; gTouchSideInit = true; return; }
   bool touched = gWasOnTradeSide && !onSide;
   gWasOnTradeSide = onSide;
   if(!touched) return;

   string why = "";
   if(!EntryGatesOpen(why, 0))                     // the touch is in the FORMING bar
     {
      SetStatus("BLOCKED", StringFormat("touch of EMA9 %.2f but %s", gEmaF1, why), clrOrange);
      return;
     }
   PrintFormat("[T3EMA] Touch of EMA9 %.2f from the %s side - %s on continuation.",
               gEmaF1, gStack > 0 ? "upper" : "lower", gStack > 0 ? "BUY" : "SELL");
   Fire(gStack);
  }

//+------------------------------------------------------------------+
//| Heartbeat                                                          |
//+------------------------------------------------------------------+
void WriteHeartbeat()
  {
   if(!EnableHeartbeat || MQLInfoInteger(MQL_TESTER)) return;
   uint now = GetTickCount();
   if(gLastHeartbeatMs != 0 && (now - gLastHeartbeatMs) < 5000) return;
   gLastHeartbeatMs = now;
   int h = FileOpen(HeartbeatFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   int age = (gLastTickMs == 0) ? -1 : (int)((now - gLastTickMs) / 1000);
   FileWrite(h, StringFormat("%s|%d|%d|%s", TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS), age,
                             (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED ? 1 : 0, gPhase));
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Panel                                                              |
//+------------------------------------------------------------------+
void PanelLabel(const string name, const int x, const int y, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  PanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
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
   PanelLabel(PFX + "PL" + IntegerToString(row), PanelX, PanelY + row * rowH, (label == "" ? " " : label), labelClr);
   if(value != "")
     {
      uint lw = 0, lh = 0; TextGetSize(label, lw, lh);
      int vx = PanelX + 122;
      int clear = PanelX + (int)lw + 12;
      if(clear > vx) vx = clear;
      PanelLabel(PFX + "PV" + IntegerToString(row), vx, PanelY + row * rowH, value, valueClr);
     }
   else
      ObjectDelete(0, PFX + "PV" + IntegerToString(row));
  }

string FmtDur(const long secs)
  {
   if(secs < 0)     return("--");
   if(secs < 60)    return(StringFormat("%ds", (int)secs));
   if(secs < 3600)  return(StringFormat("%dm", (int)(secs / 60)));
   return(StringFormat("%dh %02dm", (int)(secs / 3600), (int)((secs % 3600) / 60)));
  }

string AvgDur(const long sum, const int n) { return(n > 0 ? FmtDur(sum / n) : "--"); }

string WinRateText(const int w, const int l)
  {
   int n = w + l;
   if(n == 0) return("--");
   return(StringFormat("%d/%d %.0f%%", w, n, 100.0 * w / n));
  }

void DrawPanel()
  {
   if(!ShowPanel) return;
   //--- measure with the font the labels actually use, or the box is sized
   //    against the default font and comes out the wrong width
   TextSetFont("Consolas", -PanelFontSize * 10);
   gPanelMaxW = 0;

   //--- v1.1.1: the background is created FIRST and drawn in FRONT of the
   //    chart. MT5 paints objects in creation order, so a box created after
   //    the labels would cover them; and OBJPROP_BACK=true puts an object
   //    behind the price bars, which is exactly what v1.1 did - the panel
   //    text floated over a chart that showed straight through it. Same
   //    arrangement TrendEMA settled on. XSIZE/YSIZE are set at the END of
   //    this function once the real row count and text extents are known.
   const int rowH = PanelFontSize + 7;
   string bg = PFX + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       C'60,66,80');
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
     }
   ObjectSetInteger(0, bg, OBJPROP_BACK,      false);   // every draw, not only on create
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PanelX - 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PanelY - 4);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,   PanelBgColor);

   int r = 0;
   const color sep = C'70,76,90';
   string acct = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO) ? "DEMO" : "REAL";
   int tickAge = (gLastTickMs == 0) ? 0 : (int)((GetTickCount() - gLastTickMs) / 1000);

   PanelRow(r++, StringFormat("TRIPLE EMA  -  %s  %s", _Symbol, acct), StringFormat("tick %ds", tickAge), clrGold, tickAge > 30 ? clrTomato : clrGray);
   PanelRow(r++, "------------------------------------", "", sep, sep);

   PanelRow(r++, "EMA 9/21/50", StringFormat("%s / %s / %s", DoubleToString(gEmaF1, 2), DoubleToString(gEmaM1, 2), DoubleToString(gEmaS1, 2)), PanelTextColor, PanelTextColor);
   string stackTxt; color stackClr;
   if(gStack > 0)      { stackTxt = StringFormat("BULL   9 > 21 > 50   %d bars", gStackAge); stackClr = clrLime; }
   else if(gStack < 0) { stackTxt = StringFormat("BEAR   9 < 21 < 50   %d bars", gStackAge); stackClr = clrTomato; }
   else                { stackTxt = "NONE   EMA9 in the middle"; stackClr = clrGray; }
   PanelRow(r++, "STACK", stackTxt, PanelTextColor, stackClr);
   PanelRow(r++, "LAST BAR", StringFormat("close %s  %s EMA9  %s candle",
                                          DoubleToString(gClose1, 2),
                                          gClose1 > gEmaF1 ? "above" : (gClose1 < gEmaF1 ? "below" : "at"),
                                          gClose1 > gOpen1 ? "bullish" : (gClose1 < gOpen1 ? "bearish" : "flat")),
            PanelTextColor, PanelTextColor);
   PanelRow(r++, "ARM", gArmText, PanelTextColor, (gArmBuy || gArmSell) ? clrDeepSkyBlue : PanelTextColor);
   PanelRow(r++, "------------------------------------", "", sep, sep);

   PanelRow(r++, "STATUS", gStatus + "  " + gStatusDetail, PanelTextColor, gStatusClr);
   PanelRow(r++, "LAST SIGNAL", gLastSignal, PanelTextColor, PanelTextColor);
   PanelRow(r++, "POSITIONS", StringFormat("%d / %d   open risk %.2f%%", CountPositions(), MaxConcurrentPositions, OpenRiskPercent()), PanelTextColor, PanelTextColor);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      long age = (long)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME));
      PanelRow(r++, "  OPEN", StringFormat("%s %.2f @ %s  SL %s  TP %s  %+.2f  %s", isBuy ? "BUY " : "SELL",
                                            PositionGetDouble(POSITION_VOLUME),
                                            DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 2),
                                            DoubleToString(PositionGetDouble(POSITION_SL), 2),
                                            DoubleToString(PositionGetDouble(POSITION_TP), 2), pl, FmtDur(age)),
               PanelTextColor, pl >= 0 ? clrLime : clrTomato);
     }
   //--- what the next entry would look like from here
     {
      double slPipsNext = 0.0; string nextTxt = "-";
      if(gStack != 0 && gEmaS1 > 0.0)
        {
         double px = (gStack > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         slPipsNext = MathAbs(px - gEmaS1) / gPip + SLBufferPips;
         double rp = 0.0; string why = "";
         double lot = CalcLot(slPipsNext * gPip, rp, why);
         if(slPipsNext < MinSLPips)                    // v1.5.1: say why a flat stack fires nothing
            nextTxt = StringFormat("--  EMA50 only ~%.0fp away, under the %.0fp floor - no entry from here", slPipsNext, MinSLPips);
         else if(slPipsNext > MaxSLPips)
            nextTxt = StringFormat("--  EMA50 ~%.0fp away, over the %.0fp cap - entry would be late", slPipsNext, MaxSLPips);
         else
            nextTxt = (lot > 0.0) ? StringFormat("%.2f  %.2f%%   SL ~%.0fp from EMA50", lot, rp, slPipsNext)
                                  : StringFormat("--  (%s)", why);
        }
      PanelRow(r++, "NEXT LOT", nextTxt, PanelTextColor, PanelTextColor);
     }
   PanelRow(r++, "------------------------------------", "", sep, sep);

   PanelRow(r++, "STREAK", StringFormat("now %+d   best %+d   worst %+d", gAllStreak, gAllBestWin, gAllWorstLoss), PanelTextColor,
            gAllStreak > 0 ? clrLime : (gAllStreak < 0 ? clrTomato : PanelTextColor));
   PanelRow(r++, "WIN RATE", StringFormat("today %s    overall %s", WinRateText(gDayWins, gDayLosses), WinRateText(gAllWins, gAllLosses)),
            PanelTextColor, (gDayWins >= gDayLosses) ? clrLime : clrTomato);
   //--- breakeven from realised results; geometry fallback until one win and one loss exist
     {
      double beRate; bool fromResults = (gAllWins > 0 && gAllLosses > 0 && gAllGrossLoss > 0.0);
      if(fromResults) beRate = 100.0 / (1.0 + (gAllGrossWin / gAllWins) / (gAllGrossLoss / gAllLosses));
      else            beRate = 100.0 / (1.0 + RewardRatio);
      int n = gAllWins + gAllLosses; double nowWR = (n > 0) ? 100.0 * gAllWins / n : 0.0;
      string beTxt; color beClr;
      if(n == 0) { beTxt = StringFormat("need %.1f%% (1:%.1f geometry) - no closed trades yet", beRate, RewardRatio); beClr = clrGray; }
      else       { beTxt = StringFormat("need %.1f%%%s   now %.1f%%   %+.1f pts", beRate, fromResults ? "" : " (geometry)", nowWR, nowWR - beRate);
                   beClr = (nowWR - beRate >= 0.0) ? clrLime : clrTomato; }
      PanelRow(r++, "WIN TARGET", beTxt, PanelTextColor, beClr);
     }
   PanelRow(r++, "AVG TIME", StringFormat("all %s (%d)   wins %s   losses %s   today %s",
                                           AvgDur(gAllDurSum, gAllDurN), gAllDurN,
                                           AvgDur(gWinDurSum, gWinDurN), AvgDur(gLossDurSum, gLossDurN),
                                           AvgDur(gDayDurSum, gDayDurN)),
            PanelTextColor, PanelTextColor);
   double dayPct = (gDayStartBalance > 0.0) ? 100.0 * gDayPL / gDayStartBalance : 0.0;
   PanelRow(r++, "TODAY", StringFormat("%+.2f  (%+.2f%%)    %d trades%s", gDayPL, dayPct, gDayTrades,
                                        MaxDailyLossPercent > 0.0 ? StringFormat("   halt at -%.1f%%", MaxDailyLossPercent) : ""),
            PanelTextColor, gDayPL < 0.0 ? clrTomato : clrLime);
   PanelRow(r++, "------------------------------------", "", sep, sep);

   int up = (int)(TimeLocal() - gStartTime);
   PanelRow(r++, "EA ALIVE", StringFormat("%d:%02d:%02d", up / 3600, (up / 60) % 60, up % 60), PanelTextColor, clrLime);
   //--- shift-1 bar: the FORMING bar minus one period, the bar the values came from
   PanelRow(r++, "BAR USED", TimeToString(gLastBar - PeriodSeconds(EntryTF), TIME_MINUTES) + "  (server time, last closed bar)", PanelTextColor, clrDeepSkyBlue);
   double sp = CurrentSpreadPips();
   PanelRow(r++, "SPREAD", StringFormat("%.0f pips  %s", sp, sp > MaxSpreadPips ? "TOO WIDE" : "ok"), PanelTextColor, sp > MaxSpreadPips ? clrTomato : clrLime);
   if(DrawEmas)
     {
      string lt; color lc;
      if(gLinesOnChart)                         { lt = StringFormat("on chart  yellow %d / red %d / blue %d", EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod); lc = clrLime; }
      else if(ChartPeriod(0) != EntryTF)        { lt = StringFormat("hidden - chart is %s, switch to %s", StringSubstr(EnumToString(ChartPeriod(0)), 7), StringSubstr(EnumToString(EntryTF), 7)); lc = clrOrange; }
      else if(hLines == INVALID_HANDLE)          { lt = "not drawn - iCustom failed, check MQL5/Indicators (retrying)"; lc = clrTomato; }
      else if(BarsCalculated(hLines) <= 0)      { lt = "waiting for the indicator to calculate..."; lc = clrOrange; }
      else                                      { lt = StringFormat("adding to chart... (%d failed, retrying every 5s)", gLinesFails); lc = clrOrange; }
      PanelRow(r++, "EMA LINES", lt, PanelTextColor, lc);
     }

   //--- size the background to what was actually drawn; remove stale rows
   //    left over from a taller previous draw
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, gPanelMaxW + 16);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, r * rowH + 8);
   for(int dead = r; dead < gPanelRowsDrawn; dead++)
     {
      ObjectDelete(0, PFX + "PL" + IntegerToString(dead));
      ObjectDelete(0, PFX + "PV" + IntegerToString(dead));
     }
   gPanelRowsDrawn = r;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| EMA lines: add / remove the companion indicator as the chart TF     |
//| moves onto or off EntryTF                                           |
//+------------------------------------------------------------------+
void SyncEmaLines()
  {
   if(!DrawEmas) return;
   bool want = (ChartPeriod(0) == EntryTF);
   if(want && !gLinesOnChart)
     {
      //--- v1.3.1: RETRY, throttled to every 5s, instead of warning once and
      //    giving up. ChartIndicatorAdd from OnInit can fail while the previous
      //    EA instance is still tearing its own indicator down: the v1.2 -> v1.3
      //    re-attach on 16 Sep logged removed/loaded 7 ms apart, the add failed,
      //    and v1.3 then never tried again - a transient hiccup became a
      //    permanent blank, and the panel blamed a missing file that was there.
      uint now = GetTickCount();
      if(gLinesRetryMs != 0 && (now - gLinesRetryMs) < 5000) return;
      gLinesRetryMs = now;

      //--- v1.3.2: the short name is built here, identically to the indicator,
      //    instead of being looked up by index after the add. ChartIndicatorName
      //    by index returns whichever indicator happens to sit last, so v1.2 may
      //    have recorded the wrong name and then failed to delete its own lines
      //    on deinit - leaving an orphan on the chart. MT5 refuses to add a
      //    second indicator with the same short name in the same window
      //    (error 4114), which is what v1.3 and v1.3.1 then hit every 5s for
      //    two minutes on 16 Sep.
      string wantName = StringFormat("TripleEMA Lines(%d,%d,%d)", EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod);

      //--- 1. already on the chart (orphan from an earlier instance, or added
      //       by hand)? Adopt it rather than fight it.
      int existing = ChartIndicatorGet(0, 0, wantName);
      if(existing != INVALID_HANDLE)
        {
         IndicatorRelease(existing);          // we only needed to know it is there
         gLinesOnChart = true;
         gLinesWarned  = false;
         gLinesFails   = 0;
         gLinesName    = wantName;
         PrintFormat("[T3EMA] EMA lines already on the chart as %s - adopted, not re-added.", wantName);
         return;
        }

      //--- 2. our own handle, created (or recreated after a run of failures)
      if(hLines == INVALID_HANDLE)
        {
         ResetLastError();
         hLines = iCustom(_Symbol, EntryTF, "TripleEMA_Lines", EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod);
         if(hLines == INVALID_HANDLE)
           {
            if(!gLinesWarned)
              {
               gLinesWarned = true;
               PrintFormat("[T3EMA] iCustom(TripleEMA_Lines) failed, error %d - is TripleEMA_Lines.ex5 in MQL5\\Indicators? Retrying every 5s. Trading is unaffected.", GetLastError());
              }
            return;
           }
        }

      //--- 3. the indicator must have finished at least one calculation before
      //       the chart will accept it; calling ChartIndicatorAdd sooner is a
      //       documented cause of 4114
      int calc = BarsCalculated(hLines);
      if(calc <= 0)
        {
         if(gLinesLastLogMs == 0 || (now - gLinesLastLogMs) > 60000)
           {
            gLinesLastLogMs = now;
            PrintFormat("[T3EMA] EMA lines: indicator not calculated yet (BarsCalculated=%d) - waiting.", calc);
           }
         return;
        }

      ResetLastError();
      if(ChartIndicatorAdd(0, 0, hLines))
        {
         gLinesOnChart = true;
         gLinesWarned  = false;
         gLinesFails   = 0;
         gLinesName    = wantName;
         PrintFormat("[T3EMA] EMA lines on chart: %s (yellow %d / red %d / blue %d).",
                     wantName, EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod);
         return;
        }

      //--- 4. failed. Say so once immediately, then once a minute while it
      //       persists, and recreate the handle after twelve straight failures
      //       in case the one made during a busy attach is the problem.
      int err = GetLastError();
      gLinesFails++;
      if(!gLinesWarned || (now - gLinesLastLogMs) > 60000)
        {
         gLinesWarned    = true;
         gLinesLastLogMs = now;
         PrintFormat("[T3EMA] ChartIndicatorAdd failed, error %d (%d in a row, BarsCalculated=%d). Retrying every 5s. Trading is unaffected.",
                     err, gLinesFails, calc);
        }
      if(gLinesFails % 12 == 0)
        {
         IndicatorRelease(hLines);
         hLines = INVALID_HANDLE;
         Print("[T3EMA] EMA lines: releasing and recreating the indicator handle.");
        }
     }
   else if(!want && gLinesOnChart)
     {
      ChartIndicatorDelete(0, 0, gLinesName);
      gLinesOnChart = false;
      PrintFormat("[T3EMA] Chart moved to %s - EMA lines removed. They draw only on %s, the timeframe the EA trades.",
                  EnumToString(ChartPeriod(0)), EnumToString(EntryTF));
     }
   else if(!want && !gLinesOnChart && !gLinesWarned)
     {
      gLinesWarned = true;
      PrintFormat("[T3EMA] EMA lines not drawn: chart is %s, the EA trades %s. Switch the chart to %s to see them.",
                  EnumToString(ChartPeriod(0)), EnumToString(EntryTF), EnumToString(EntryTF));
     }
  }

//+------------------------------------------------------------------+
//| Init / Deinit                                                      |
//+------------------------------------------------------------------+
int OnInit()
  {
   gStartTime = TimeLocal();

   if(SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     {
      string lock = LockName();
      if(GlobalVariableCheck(lock))
        {
         int age = (int)(TimeLocal() - (datetime)GlobalVariableGet(lock));
         if(age >= 0 && age < 30)
           {
            PrintFormat("[T3EMA] REFUSING to start: another instance is running on %s with magic %d (seen %ds ago). Remove the other chart or set SingleInstanceLock=false.", _Symbol, (int)MagicNumber, age);
            return(INIT_FAILED);
           }
         PrintFormat("[T3EMA] Stale instance lock (%ds old) - taking it over.", age);
        }
      GlobalVariableSet(lock, (double)TimeLocal());
      gHoldsLock = true;
     }

   if(RequireGoldSymbol && StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
     {
      PrintFormat("[T3EMA] REFUSING to start on %s - built for gold. Set RequireGoldSymbol=false to override.", _Symbol);
      return(INIT_FAILED);
     }
   if(RewardRatio <= 0.0 || RiskPercent <= 0.0 || EmaFastPeriod >= EmaMidPeriod || EmaMidPeriod >= EmaSlowPeriod)
     {
      Print("[T3EMA] REFUSING to start: RewardRatio and RiskPercent must be > 0 and EMA periods must be strictly increasing (fast < mid < slow).");
      return(INIT_FAILED);
     }

   gDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   gPoint  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   gTick   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(gTick <= 0.0) gTick = gPoint;
   gPip    = (PipSizeOverride > 0.0) ? PipSizeOverride : ((gDigits == 3 || gDigits == 5) ? 10.0 * gPoint : gPoint);

   hEmaF = iMA(_Symbol, EntryTF, EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaM = iMA(_Symbol, EntryTF, EmaMidPeriod,  0, MODE_EMA, PRICE_CLOSE);
   hEmaS = iMA(_Symbol, EntryTF, EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hEmaF == INVALID_HANDLE || hEmaM == INVALID_HANDLE || hEmaS == INVALID_HANDLE)
     {
      Print("[T3EMA] Indicator handle creation failed.");
      return(INIT_FAILED);
     }

   gTrade.SetExpertMagicNumber(MagicNumber);
   gTrade.SetDeviationInPoints((ulong)MathMax(1.0, MaxSlippagePips * gPip / gPoint));
   gTrade.SetTypeFillingBySymbol(_Symbol);
   gTrade.SetAsyncMode(false);

   ResetDayState(true);
   RefreshDailyStats();
   RefreshAllTimeStats();
   gLastBar = iTime(_Symbol, EntryTF, 0);
   if(RefreshIndicators())
     {
      gLastStack = gStack;
      gStackAge  = StackAgeFromHistory();
      if(EntryMode == ENTRY_FIRST_THEN_TOUCH && gStack != 0 && gStackAge > FirstEntryWindowBars)
        {
         gTouchArmed = true; gTouchSideInit = false;
         PrintFormat("[T3EMA] Attached inside a %s stack that is %d bars old (window %d) - starting in TOUCH mode, no close-rule entry.",
                     gStack > 0 ? "BULL" : "BEAR", gStackAge, FirstEntryWindowBars);
        }
      else if(gStack != 0)
         PrintFormat("[T3EMA] Attached in a %s stack %d bars old.", gStack > 0 ? "BULL" : "BEAR", gStackAge);
     }

   EventSetTimer(1);
   gInitOk = true;

   PrintFormat("[T3EMA] Initialised. Symbol=%s Digits=%d Point=%.5f Pip=%.5f  TF=%s  EMAs %d/%d/%d  Risk=%.2f%%/%.2f%%  MaxPos=%d",
               _Symbol, gDigits, gPoint, gPip, EnumToString(EntryTF), EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod, RiskPercent, MaxRiskPercent, MaxConcurrentPositions);
   PrintFormat("[T3EMA] Time stop: %s.  Late-entry cap: MaxSLPips %.0f.",
               MaxHoldMinutes > 0 ? StringFormat("close at market after %d min", MaxHoldMinutes) : "OFF", MaxSLPips);
   string modeTxt = (EntryMode == ENTRY_ANY_CLOSE) ? "ANY same-colour close across EMA9 while flat (operator spec)"
                  : (EntryMode == ENTRY_FIRST_THEN_PULLBACK) ? "first close after the stack forms, then a pullback before each later entry"
                  : (EntryMode == ENTRY_FIRST_THEN_TOUCH) ? "first close after the stack forms, then every TOUCH of EMA9 from the trade side (wick counts)"
                  : "a pullback across EMA9 before EVERY entry";
   PrintFormat("[T3EMA] Entry: 9/21/50 stack + %s%s. Market order on the next bar open.",
               modeTxt, RequireCandleColor ? ", same-direction candle required" : "");
   PrintFormat("[T3EMA] One position at a time (MaxConcurrentPositions=%d). Next entry only after the trade is closed%s%s.",
               MaxConcurrentPositions,
               (ResetArmOnClose && EntryMode != ENTRY_ANY_CLOSE) ? " AND a fresh pullback has been seen (ResetArmOnClose)" : "",
               MinBarsAfterClose > 0 ? StringFormat(", and never off the bar the trade closed in (MinBarsAfterClose=%d)", MinBarsAfterClose) : "");
   PrintFormat("[T3EMA] Geometry: SL at EMA50 %s %.0fp buffer, clamped [%.0f..%.0f] pips. TP = %.1f x SL. Breakeven win rate %.1f%% before spread.",
               "+/-", SLBufferPips, MinSLPips, MaxSLPips, RewardRatio, 100.0 / (1.0 + RewardRatio));
   PrintFormat("[T3EMA] Guards: daily halt %s | trade cap %s | cooldown %s | spread cap %.0fp | session %s | lot cap %.2f",
               MaxDailyLossPercent > 0 ? StringFormat("%.1f%%", MaxDailyLossPercent) : "off",
               MaxDailyTradeCount > 0 ? IntegerToString(MaxDailyTradeCount) : "none",
               CooldownMinutesAfterLoss > 0 ? StringFormat("%d min", CooldownMinutesAfterLoss) : "off",
               MaxSpreadPips, SessionWindowsET == "" ? "all hours" : SessionWindowsET, MaxLotSizeCap);
   PrintFormat("[T3EMA] Broker: stops_level=%d pts  lot min/max/step %.2f/%.2f/%.2f  tick %.5f",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), gTick);
   Print("[T3EMA] *** REAL MONEY ACCOUNT *** Orders are placed automatically. Drop ", EmergencyStopFile,
         " into MQL5\\Files to halt new entries. Removing the EA does NOT close an open position.");
   if(!MQLInfoInteger(MQL_TESTER))
      Print("[T3EMA] No config-signature epoch: the WIN RATE overall counter covers every trade under magic ", MagicNumber, " and does NOT reset when inputs change.");
   SyncEmaLines();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(gHoldsLock && SingleInstanceLock && !MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableDel(LockName());
      gHoldsLock = false;
     }
   ObjectsDeleteAll(0, PFX);
   //--- v1.3.2: always attempt the delete by the deterministic name, whether or
   //    not this instance believes it added the lines - an orphan left by an
   //    earlier instance must not survive another re-attach.
   ChartIndicatorDelete(0, 0, StringFormat("TripleEMA Lines(%d,%d,%d)", EmaFastPeriod, EmaMidPeriod, EmaSlowPeriod));
   gLinesOnChart = false;
   if(hLines != INVALID_HANDLE) { IndicatorRelease(hLines); hLines = INVALID_HANDLE; }
   ChartRedraw();
   if(hEmaF != INVALID_HANDLE) IndicatorRelease(hEmaF);
   if(hEmaM != INVALID_HANDLE) IndicatorRelease(hEmaM);
   if(hEmaS != INVALID_HANDLE) IndicatorRelease(hEmaS);
  }

//+------------------------------------------------------------------+
//| Tick / Timer / Trade events                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!gInitOk) return;
   gLastTickMs = GetTickCount();
   TouchLock();

   //--- kill switch, checked at most every 2s
   uint nowChk = GetTickCount();
   if(gLastStopChkMs == 0 || (nowChk - gLastStopChkMs) > 2000)
     {
      gStopFilePresent = FileIsExist(EmergencyStopFile);
      gLastStopChkMs   = nowChk;
     }

   if(CurrentDayIndex() != gDayIndex)
     {
      ResetDayState(false);
      RefreshDailyStats();
     }

   //--- act once per new bar: every read is at shift 1, so re-evaluating
   //    intra-bar would just repeat the same decision on the same data
   datetime bar = iTime(_Symbol, EntryTF, 0);
   if(bar != gLastBar)
     {
      gLastBar = bar;
      gPhase = "REFRESH";
      if(RefreshIndicators())
        {
         RefreshDailyStats();
         gPhase = "EVAL";
         if(gStopFilePresent) SetStatus("HALTED", "kill-switch file present - no new entries", clrRed);
         else                 Evaluate();
        }
      else
         SetStatus("STALE", "indicator read failed on the new bar", clrRed);
     }
   gPhase = "HOLD";
   EnforceMaxHold();                              // v1.5: time stop, every tick, kill switch or not
   gPhase = "TOUCH";
   if(!gStopFilePresent) CheckTouchEntry();       // v1.4: intrabar, every tick
   gPhase = "IDLE";
   WriteHeartbeat();
   DrawPanel();
  }

void OnTimer()
  {
   if(!gInitOk) return;
   SyncEmaLines();      // v1.3.1: self-throttled retry until the lines are on
   WriteHeartbeat();
   DrawPanel();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      SyncEmaLines();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)     return;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
     {
      datetime ct = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      if(ct > gLastCloseTime) gLastCloseTime = ct;       // v1.3.3
      if(ResetArmOnClose && EntryMode != ENTRY_ANY_CLOSE && EntryMode != ENTRY_FIRST_THEN_TOUCH && (gArmBuy || gArmSell))
        {
         gArmBuy = false; gArmSell = false;
         gArmText = "cleared on close - waiting for a fresh pullback";
         Print("[T3EMA] Trade closed - arm cleared. A new pullback across EMA9 is required before the next entry.");
        }
      double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      PrintFormat("[T3EMA] CLOSE %.2f lots @ %.2f  P/L %+.2f", HistoryDealGetDouble(trans.deal, DEAL_VOLUME), HistoryDealGetDouble(trans.deal, DEAL_PRICE), net);
      if(AlertOnClose) Alert(StringFormat("T3EMA CLOSE %.2f @ %.2f  P/L %+.2f", HistoryDealGetDouble(trans.deal, DEAL_VOLUME), HistoryDealGetDouble(trans.deal, DEAL_PRICE), net));
      RefreshDailyStats();
      RefreshAllTimeStats();
     }
  }
//+------------------------------------------------------------------+
