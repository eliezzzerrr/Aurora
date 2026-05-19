//+------------------------------------------------------------------+
//|                                            Aurora Scalper.mq5    |
//|        XAUUSD High-Frequency Scalper (MT5) — v3.0                |
//|                                                                  |
//|  Doctrine:                                                       |
//|    - Target: 100 trades/hour                                     |
//|    - Up to 10 concurrent positions                               |
//|    - Tight, fast TP — get out winning quickly                    |
//|    - Time-stop "scratch" rule: any position open longer than     |
//|      InpMaxHoldSeconds is closed at market regardless of P&L     |
//|      (cuts losing trades before they reach full SL)              |
//|    - Position sizing scales with account EQUITY (real-time):     |
//|      lot size grows as capital grows, shrinks if drawdown        |
//|    - Bias from M15 (HH/LL ordering); entry fires on cooldown     |
//|      timer, not per-bar — needed to hit 100/hr throughput        |
//|    - Optional EMA(12) M1 touch requirement (off by default)      |
//+------------------------------------------------------------------+
#property copyright "Aurora — github.com/eliezzzerrr/Aurora"
#property link      "https://github.com/eliezzzerrr/Aurora"
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================

input string  IH_Risk          = "════════ Risk (equity-scaled) ════════";
input double  InpRiskPercent   = 0.5;          // Risk per trade (% of EQUITY — scales with capital)
input double  InpSLPips        = 10.0;         // SL distance (pips)
input double  InpTPPips        = 5.0;          // TP distance (pips) — SMALL for fast wins

input string  IH_Pos           = "════════ Position & Frequency ════════";
input int     InpMaxPositions  = 10;           // Max concurrent open positions
input int     InpMaxTradesDay  = 2400;         // Daily cap (100/hr × 24h)
input int     InpEntryCooldownSec = 30;        // Min seconds between entry attempts (30s → ~120 attempts/hr)
input int     InpMaxHoldSeconds   = 60;        // SCRATCH RULE: close any position open longer than this

input string  IH_Struct        = "════════ Structure ════════";
input ENUM_TIMEFRAMES InpBiasTF  = PERIOD_M15; // HTF bias timeframe
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M1;  // Entry timeframe (for EMA + bar refs)
input int     InpEMAPeriod     = 12;           // EMA period on entry TF
input int     InpHTFBiasBars   = 30;           // M15 bars for swing-based bias
input bool    InpRequireEMATouch = false;      // If true, current M1 bar must touch EMA(12) to enter

input string  IH_Exec          = "════════ Execution ════════";
input bool    InpInvertDirection = false;      // Toggle: flip BUY/SELL on every trigger
input long    InpMagic         = 87742;        // Magic number
input string  InpComment       = "Aurora Scalper v3.0";
input int     InpSlippage      = 30;
input double  InpMaxSpreadPips = 5.0;          // Skip entry if spread exceeds this

input string  IH_Sess          = "════════ Killzones (OFF for scalper) ════════";
input bool    InpUseKillzones  = false;
input int     InpBrokerToUTC   = -4;
input int     InpLondonOpenH   = 7;
input int     InpLondonCloseH  = 10;
input int     InpNYOpenH       = 12;
input int     InpNYOpenM       = 30;
input int     InpNYCloseH      = 15;
input int     InpNYCloseM      = 30;

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxConsecLoss = 15;           // Halt after N consec losses (raised for high-freq)
input bool    InpLogToFile     = true;

//==================================================================
//                          GLOBALS
//==================================================================

CTrade        gTrade;
CSymbolInfo   gSym;
CPositionInfo gPos;
COrderInfo    gOrd;

datetime      gLastEntryTime = 0;
datetime      gTodayKey      = 0;
int           gTradesToday   = 0;
int           gConsecLosses  = 0;
bool          gHaltedToday   = false;

int           gEMAHandle     = INVALID_HANDLE;
double        gPip;

//==================================================================
//                          INIT / DEINIT
//==================================================================

int OnInit() {
   gTrade.SetExpertMagicNumber(InpMagic);
   gTrade.SetDeviationInPoints(InpSlippage);
   gTrade.SetMarginMode();
   gTrade.SetTypeFillingBySymbol(_Symbol);

   if (!gSym.Name(_Symbol)) {
      LogError("Failed to attach symbol info for " + _Symbol);
      return INIT_FAILED;
   }
   gSym.RefreshRates();

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   gPip = (digits == 5 || digits == 3) ? _Point * 10 : _Point;
   if (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) {
      gPip = _Point * 10;
   }

   gEMAHandle = iMA(_Symbol, InpEntryTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (gEMAHandle == INVALID_HANDLE) {
      LogError("Failed to create EMA handle");
      return INIT_FAILED;
   }

   LogInfo("==============================================");
   LogInfo("Aurora Scalper v3.0 (HIGH-FREQ) on " + _Symbol);
   LogInfo("  Magic:              " + IntegerToString(InpMagic));
   LogInfo("  Risk per trade:     " + DoubleToString(InpRiskPercent, 2) + "% of EQUITY");
   LogInfo("  SL pips / TP pips:  " + DoubleToString(InpSLPips, 1) + " / " + DoubleToString(InpTPPips, 1));
   LogInfo("  Max positions:      " + IntegerToString(InpMaxPositions));
   LogInfo("  Entry cooldown:     " + IntegerToString(InpEntryCooldownSec) + "s");
   LogInfo("  Max hold (scratch): " + IntegerToString(InpMaxHoldSeconds) + "s");
   LogInfo("  Daily cap:          " + IntegerToString(InpMaxTradesDay) + " entries");
   LogInfo("  Bias TF:            " + EnumToString(InpBiasTF));
   LogInfo("  EMA touch required: " + (InpRequireEMATouch ? "YES" : "NO"));
   LogInfo("  Invert direction:   " + (InpInvertDirection ? "YES" : "NO"));
   LogInfo("  Max spread:         " + DoubleToString(InpMaxSpreadPips, 1) + " pips");
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (gEMAHandle != INVALID_HANDLE) {
      IndicatorRelease(gEMAHandle);
      gEMAHandle = INVALID_HANDLE;
   }
   LogInfo("Aurora Scalper v3.0 deinit. Reason code: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   // 1) Manage open positions (scratch via time stop)
   ManageOpenPositions();

   // 2) Daily counter refresh
   UpdateDailyCounters();

   // 3) Entry gates
   if (gHaltedToday) return;
   if (gTradesToday >= InpMaxTradesDay) return;
   if (InpUseKillzones && !IsInKillzone()) return;

   // 4) Entry cooldown
   if (TimeCurrent() - gLastEntryTime < InpEntryCooldownSec) return;

   // 5) Slot availability
   if (CountActiveAuroraOrders() >= InpMaxPositions) return;

   // 6) Spread gate
   double spreadPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double spreadPips  = spreadPrice / gPip;
   if (spreadPips > InpMaxSpreadPips) return;

   // 7) Bias
   int bias = GetHTFBias();
   if (bias == 0) return;

   // 8) Optional EMA touch requirement
   if (InpRequireEMATouch) {
      double ema1;
      if (!GetEMAValue(gEMAHandle, 1, ema1)) return;
      double bar1H = iHigh(_Symbol, InpEntryTF, 1);
      double bar1L = iLow (_Symbol, InpEntryTF, 1);
      bool touched = (bar1L <= ema1 && bar1H >= ema1);
      if (!touched) return;
   }

   // 9) Direction (optionally inverted)
   int execDir = InpInvertDirection ? -bias : bias;

   // 10) Execute
   ExecuteEntry(execDir);
   gLastEntryTime = TimeCurrent();
}

//==================================================================
//                       ENTRY EXECUTION
//==================================================================

void ExecuteEntry(int direction) {
   double slDistPrice = InpSLPips * gPip;
   double tpDistPrice = InpTPPips * gPip;

   // Broker stops level clamp
   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsLevelPrice = (double)stopsLevelPts * _Point;
   if (slDistPrice < stopsLevelPrice + _Point) slDistPrice = stopsLevelPrice + _Point;
   if (tpDistPrice < stopsLevelPrice + _Point) tpDistPrice = stopsLevelPrice + _Point;

   double lots = CalcLotsFromEquityPercent(slDistPrice, InpRiskPercent);
   if (lots <= 0) {
      LogError("Lot calc failed (slDist=" + DoubleToString(slDistPrice, _Digits) + ")");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double entry, sl, tp;
   bool ok;
   if (direction < 0) {
      entry = bid;
      sl    = NormalizeDouble(entry + slDistPrice, _Digits);
      tp    = NormalizeDouble(entry - tpDistPrice, _Digits);
      ok    = gTrade.Sell(lots, _Symbol, entry, sl, tp, InpComment);
   } else {
      entry = ask;
      sl    = NormalizeDouble(entry - slDistPrice, _Digits);
      tp    = NormalizeDouble(entry + tpDistPrice, _Digits);
      ok    = gTrade.Buy(lots, _Symbol, entry, sl, tp, InpComment);
   }

   if (!ok) {
      LogError("Order failed: " + gTrade.ResultRetcodeDescription());
      return;
   }

   LogSignal(StringFormat("[%s] #%I64u %.2f lots @ %s · SL %s · TP %s · equity $%.2f",
            (direction < 0 ? "SELL" : "BUY"),
            gTrade.ResultOrder(), lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits),
            AccountInfoDouble(ACCOUNT_EQUITY)));
}

//==================================================================
//                       POSITION MANAGEMENT (SCRATCH RULE)
//==================================================================

void ManageOpenPositions() {
   datetime now = TimeCurrent();
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!gPos.SelectByIndex(i)) continue;
      if (gPos.Magic() != InpMagic) continue;
      if (gPos.Symbol() != _Symbol) continue;

      datetime openTime = gPos.Time();
      long ageSeconds = (long)(now - openTime);
      if (ageSeconds < InpMaxHoldSeconds) continue;

      // Scratch: close at market regardless of P&L
      ulong ticket = gPos.Ticket();
      double pnl = gPos.Profit() + gPos.Swap() + gPos.Commission();
      if (gTrade.PositionClose(ticket)) {
         LogSignal(StringFormat("[SCRATCH] #%I64u closed after %ds (PnL $%.2f)",
                  ticket, ageSeconds, pnl));
      } else {
         LogError("Scratch close failed for #" + IntegerToString((long)ticket) +
                  ": " + gTrade.ResultRetcodeDescription());
      }
   }
}

//==================================================================
//                       BIAS / EMA
//==================================================================

int GetHTFBias() {
   int bars = InpHTFBiasBars;
   if (Bars(_Symbol, InpBiasTF) < bars + 5) return 0;

   double hh = 0, ll = 99999999;
   int hhIdx = -1, llIdx = -1;
   for (int i = 1; i <= bars; i++) {
      double h = iHigh(_Symbol, InpBiasTF, i);
      double l = iLow (_Symbol, InpBiasTF, i);
      if (h > hh) { hh = h; hhIdx = i; }
      if (l < ll) { ll = l; llIdx = i; }
   }
   if (llIdx < hhIdx) return -1;
   if (hhIdx < llIdx) return +1;
   return 0;
}

bool GetEMAValue(int handle, int shift, double &val) {
   double buf[];
   if (CopyBuffer(handle, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
}

//==================================================================
//                       RISK / POSITION SIZING (EQUITY-SCALED)
//==================================================================

double CalcLotsFromEquityPercent(double slDistancePrice, double riskPct) {
   if (slDistancePrice <= 0 || riskPct <= 0) return 0;

   // *** Equity, not balance — scales with floating P&L too ***
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPct / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0 || tickSize <= 0) return 0;

   double slTicks    = slDistancePrice / tickSize;
   double moneyPerLot = slTicks * tickValue;
   if (moneyPerLot <= 0) return 0;

   double lots = riskMoney / moneyPerLot;

   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   if (lots < lotMin) lots = lotMin;
   if (lots > lotMax) lots = lotMax;
   return NormalizeDouble(lots, 2);
}

//==================================================================
//                       POSITION / ORDER COUNTING
//==================================================================

int CountActiveAuroraOrders() {
   int n = 0;
   for (int i = 0; i < PositionsTotal(); i++) {
      if (!gPos.SelectByIndex(i)) continue;
      if (gPos.Magic() == InpMagic && gPos.Symbol() == _Symbol) n++;
   }
   for (int i = 0; i < OrdersTotal(); i++) {
      if (!gOrd.SelectByIndex(i)) continue;
      if (gOrd.Magic() == InpMagic && gOrd.Symbol() == _Symbol) n++;
   }
   return n;
}

//==================================================================
//                       KILLZONE (off by default)
//==================================================================

bool IsInKillzone() {
   datetime brokerNow = TimeCurrent();
   MqlDateTime utc;
   datetime utcNow = brokerNow - InpBrokerToUTC * 3600;
   TimeToStruct(utcNow, utc);
   int curMin = utc.hour * 60 + utc.min;
   int londonStart = InpLondonOpenH * 60;
   int londonEnd   = InpLondonCloseH * 60;
   if (curMin >= londonStart && curMin < londonEnd) return true;
   int nyStart = InpNYOpenH * 60 + InpNYOpenM;
   int nyEnd   = InpNYCloseH * 60 + InpNYCloseM;
   if (curMin >= nyStart && curMin < nyEnd) return true;
   return false;
}

//==================================================================
//                       DAILY COUNTERS
//==================================================================

void UpdateDailyCounters() {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", now.year, now.mon, now.day));

   if (today != gTodayKey) {
      gTodayKey = today;
      gTradesToday = 0;
      gHaltedToday = false;
      LogInfo("--- New trading day: " + TimeToString(today, TIME_DATE) + " ---");
   }

   HistorySelect(gTodayKey, TimeCurrent());
   int total = HistoryDealsTotal();
   int filled = 0, consec = 0;
   for (int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if (entry == DEAL_ENTRY_IN) filled++;
   }
   gTradesToday = filled;

   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if (entry != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if (profit < 0) consec++;
      else break;
   }
   gConsecLosses = consec;
   if (gConsecLosses >= InpMaxConsecLoss && !gHaltedToday) {
      gHaltedToday = true;
      LogInfo("CIRCUIT BREAKER: " + IntegerToString(gConsecLosses) + " consecutive losses. Halting.");
   }
}

//==================================================================
//                       LOGGING
//==================================================================

string TimestampStr() {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.mon, t.day, t.hour, t.min, t.sec);
}

void LogToFile(string level, string msg) {
   if (!InpLogToFile) return;
   int h = FileOpen("Aurora Scalper Journal.txt", FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if (h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, TimestampStr() + " [" + level + "] " + msg + "\n");
   FileClose(h);
}

void LogInfo(string m)   { Print("[INFO] ",   m); LogToFile("INFO",   m); }
void LogDebug(string m)  { LogToFile("DEBUG",  m); }
void LogSignal(string m) { Print("[SIG] ",    m); LogToFile("SIGNAL", m); }
void LogError(string m)  { Print("[ERR] ",    m); LogToFile("ERROR",  m); }
