//+------------------------------------------------------------------+
//|                                            Aurora Scalper.mq5    |
//|     XAUUSD High-Frequency BB Mean-Reversion Scalper — v3.1       |
//|                                                                  |
//|  v3.0 lost -$910 / 51% wins / PF 0.30. Diagnosis:                |
//|    1. Entry signal was just "fire in bias direction" → near      |
//|       random (51% wins vs 50% expected at 1:2 RR random).        |
//|    2. Scratch rule closed WINNING trades at 60s before TP hit,   |
//|       capping avg win at $1.20 (target was $5).                  |
//|                                                                  |
//|  v3.1 fixes both — same frequency targets retained:              |
//|    - Strategy: M1 Bollinger Band MEAN REVERSION                  |
//|        · Buy when bid ≤ lower band (oversold bounce)             |
//|        · Sell when ask ≥ upper band (overbought fade)            |
//|    - Position mgmt split:                                        |
//|        · Loser scratch: if PnL ≤ 0 after N sec → close           |
//|        · Winner BE-move: if PnL > 0 after N sec → SL to BE       |
//|          then let TP run to completion                           |
//|        · Hard cap: 60s → close regardless                        |
//|    - Frequency: 10 concurrent, 30s cooldown, equity scaling      |
//|      ALL UNCHANGED                                               |
//+------------------------------------------------------------------+
#property copyright "Aurora — github.com/eliezzzerrr/Aurora"
#property link      "https://github.com/eliezzzerrr/Aurora"
#property version   "3.10"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================

input string  IH_Risk          = "════════ Risk (equity-scaled) ════════";
input double  InpRiskPercent   = 0.5;          // Risk per trade (% of EQUITY)
input double  InpSLPips        = 10.0;         // SL distance (pips)
input double  InpTPPips        = 8.0;          // TP distance (pips) — raised from 5 since BE move now protects winners

input string  IH_Pos           = "════════ Position & Frequency ════════";
input int     InpMaxPositions  = 10;           // Max concurrent open positions
input int     InpMaxTradesDay  = 2400;         // Daily cap
input int     InpEntryCooldownSec = 30;        // Min seconds between entry attempts

input string  IH_Manage        = "════════ Position Management (v3.1) ════════";
input int     InpLoserScratchSec  = 30;        // If PnL ≤ 0 after this long → close at market
input int     InpWinnerBEAfterSec = 20;        // If PnL > 0 after this long → move SL to BE + buffer
input double  InpBEBufferPips     = 1.0;       // BE move adds this many pips beyond entry (lock tiny profit)
input int     InpMaxHoldSeconds   = 60;        // Hard cap — close regardless of P&L

input string  IH_Strat         = "════════ Strategy: Bollinger Band Mean Reversion ════════";
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M1;  // BB timeframe
input int     InpBBPeriod      = 20;           // BB period
input double  InpBBDeviation   = 2.0;          // BB standard deviations
input bool    InpRequireBiasMatch = false;     // If true: only buy in bull bias, sell in bear bias
input ENUM_TIMEFRAMES InpBiasTF = PERIOD_M15;  // Bias TF (only used if InpRequireBiasMatch)
input int     InpHTFBiasBars   = 30;           // M15 bars for swing-based bias

input string  IH_Exec          = "════════ Execution ════════";
input bool    InpInvertDirection = false;      // Toggle: flip BUY/SELL
input long    InpMagic         = 87742;
input string  InpComment       = "Aurora Scalper v3.1 BB-MR";
input int     InpSlippage      = 30;
input double  InpMaxSpreadPips = 5.0;          // Skip entry if spread exceeds this

input string  IH_Sess          = "════════ Killzones (OFF) ════════";
input bool    InpUseKillzones  = false;
input int     InpBrokerToUTC   = -4;
input int     InpLondonOpenH   = 7;
input int     InpLondonCloseH  = 10;
input int     InpNYOpenH       = 12;
input int     InpNYOpenM       = 30;
input int     InpNYCloseH      = 15;
input int     InpNYCloseM      = 30;

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxConsecLoss = 15;
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

int           gBBHandle      = INVALID_HANDLE;
double        gPip;

// Bollinger Band buffer indices in MT5
#define BB_BASE  0
#define BB_UPPER 1
#define BB_LOWER 2

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

   gBBHandle = iBands(_Symbol, InpEntryTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   if (gBBHandle == INVALID_HANDLE) {
      LogError("Failed to create Bollinger Bands handle");
      return INIT_FAILED;
   }

   LogInfo("==============================================");
   LogInfo("Aurora Scalper v3.1 (BB Mean Reversion) on " + _Symbol);
   LogInfo("  Magic:              " + IntegerToString(InpMagic));
   LogInfo("  Risk/trade:         " + DoubleToString(InpRiskPercent, 2) + "% of EQUITY");
   LogInfo("  SL pips / TP pips:  " + DoubleToString(InpSLPips, 1) + " / " + DoubleToString(InpTPPips, 1));
   LogInfo("  BB period / dev:    " + IntegerToString(InpBBPeriod) + " / " + DoubleToString(InpBBDeviation, 1));
   LogInfo("  Bias filter:        " + (InpRequireBiasMatch ? "ON" : "OFF (pure mean rev)"));
   LogInfo("  Max positions:      " + IntegerToString(InpMaxPositions));
   LogInfo("  Entry cooldown:     " + IntegerToString(InpEntryCooldownSec) + "s");
   LogInfo("  Loser scratch:      " + IntegerToString(InpLoserScratchSec) + "s");
   LogInfo("  Winner BE move:     " + IntegerToString(InpWinnerBEAfterSec) + "s (+" + DoubleToString(InpBEBufferPips, 1) + "p)");
   LogInfo("  Hard max hold:      " + IntegerToString(InpMaxHoldSeconds) + "s");
   LogInfo("  Invert direction:   " + (InpInvertDirection ? "YES" : "NO"));
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (gBBHandle != INVALID_HANDLE) {
      IndicatorRelease(gBBHandle);
      gBBHandle = INVALID_HANDLE;
   }
   LogInfo("Aurora Scalper v3.1 deinit. Reason: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   // 1) Manage existing positions (BE move + scratch + hard cap)
   ManageOpenPositions();

   // 2) Daily counter refresh
   UpdateDailyCounters();

   // 3) Entry gates
   if (gHaltedToday) return;
   if (gTradesToday >= InpMaxTradesDay) return;
   if (InpUseKillzones && !IsInKillzone()) return;
   if (TimeCurrent() - gLastEntryTime < InpEntryCooldownSec) return;
   if (CountActiveAuroraOrders() >= InpMaxPositions) return;

   double spreadPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   if (spreadPrice / gPip > InpMaxSpreadPips) return;

   // 4) Get BB values from last closed bar (stable)
   double upperBB, lowerBB, baseBB;
   if (!GetBBValue(BB_UPPER, 1, upperBB)) return;
   if (!GetBBValue(BB_LOWER, 1, lowerBB)) return;
   if (!GetBBValue(BB_BASE,  1, baseBB))  return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 5) Optional bias filter
   int bias = 0;
   if (InpRequireBiasMatch) {
      bias = GetHTFBias();
      if (bias == 0) return;
   }

   // 6) BB trigger — fade extremes
   //    Lower band touch → BUY (oversold bounce)
   //    Upper band touch → SELL (overbought fade)
   int triggerDir = 0;
   string trigLabel = "";
   if (bid <= lowerBB) {
      triggerDir = +1;
      trigLabel = "BB-LO";
   } else if (ask >= upperBB) {
      triggerDir = -1;
      trigLabel = "BB-HI";
   }
   if (triggerDir == 0) return;

   // 7) Apply bias filter if enabled
   if (InpRequireBiasMatch && bias != triggerDir) return;

   // 8) Direction inversion toggle
   int execDir = InpInvertDirection ? -triggerDir : triggerDir;

   LogSignal(StringFormat("[%s] %s=%s base=%s upper=%s lower=%s → exec %s",
            trigLabel,
            (triggerDir > 0 ? "bid" : "ask"),
            DoubleToString(triggerDir > 0 ? bid : ask, _Digits),
            DoubleToString(baseBB, _Digits),
            DoubleToString(upperBB, _Digits),
            DoubleToString(lowerBB, _Digits),
            (execDir > 0 ? "BUY" : "SELL")));

   ExecuteEntry(execDir);
   gLastEntryTime = TimeCurrent();
}

//==================================================================
//                       ENTRY EXECUTION
//==================================================================

void ExecuteEntry(int direction) {
   double slDistPrice = InpSLPips * gPip;
   double tpDistPrice = InpTPPips * gPip;

   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsLevelPrice = (double)stopsLevelPts * _Point;
   if (slDistPrice < stopsLevelPrice + _Point) slDistPrice = stopsLevelPrice + _Point;
   if (tpDistPrice < stopsLevelPrice + _Point) tpDistPrice = stopsLevelPrice + _Point;

   double lots = CalcLotsFromEquityPercent(slDistPrice, InpRiskPercent);
   if (lots <= 0) {
      LogError("Lot calc failed");
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

   LogSignal(StringFormat("[%s] #%I64u %.2f lots @ %s · SL %s · TP %s · eq $%.2f",
            (direction < 0 ? "SELL" : "BUY"),
            gTrade.ResultOrder(), lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits),
            AccountInfoDouble(ACCOUNT_EQUITY)));
}

//==================================================================
//                  POSITION MANAGEMENT (v3.1 — split rules)
//==================================================================

void ManageOpenPositions() {
   datetime now = TimeCurrent();
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!gPos.SelectByIndex(i)) continue;
      if (gPos.Magic() != InpMagic) continue;
      if (gPos.Symbol() != _Symbol) continue;

      ulong ticket = gPos.Ticket();
      datetime openTime = gPos.Time();
      long ageSec = (long)(now - openTime);
      double pnl = gPos.Profit() + gPos.Swap() + gPos.Commission();

      // ---- Hard cap: always close after max hold ----
      if (ageSec >= InpMaxHoldSeconds) {
         if (gTrade.PositionClose(ticket)) {
            LogSignal(StringFormat("[MAXHOLD] #%I64u closed after %ds (PnL $%.2f)",
                     ticket, ageSec, pnl));
         }
         continue;
      }

      // ---- Loser scratch ----
      if (ageSec >= InpLoserScratchSec && pnl <= 0) {
         if (gTrade.PositionClose(ticket)) {
            LogSignal(StringFormat("[SCRATCH-L] #%I64u closed after %ds (PnL $%.2f)",
                     ticket, ageSec, pnl));
         }
         continue;
      }

      // ---- Winner BE move (only if not already moved) ----
      if (ageSec >= InpWinnerBEAfterSec && pnl > 0) {
         double entry = gPos.PriceOpen();
         double curSL = gPos.StopLoss();
         double tp    = gPos.TakeProfit();
         bool isLong  = (gPos.PositionType() == POSITION_TYPE_BUY);
         double newSL = isLong
                      ? NormalizeDouble(entry + InpBEBufferPips * gPip, _Digits)
                      : NormalizeDouble(entry - InpBEBufferPips * gPip, _Digits);

         // Only modify if SL hasn't been moved past entry yet
         bool needsMove = isLong ? (curSL < newSL) : (curSL > newSL);
         if (needsMove) {
            if (gTrade.PositionModify(ticket, newSL, tp)) {
               LogSignal(StringFormat("[BE-MOVE] #%I64u SL→%s after %ds (PnL $%.2f)",
                        ticket, DoubleToString(newSL, _Digits), ageSec, pnl));
            }
         }
      }
   }
}

//==================================================================
//                       INDICATORS
//==================================================================

bool GetBBValue(int bufferIdx, int shift, double &val) {
   double buf[];
   if (CopyBuffer(gBBHandle, bufferIdx, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
}

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

//==================================================================
//                       RISK / SIZING (equity-scaled)
//==================================================================

double CalcLotsFromEquityPercent(double slDistancePrice, double riskPct) {
   if (slDistancePrice <= 0 || riskPct <= 0) return 0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPct / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0 || tickSize <= 0) return 0;

   double slTicks = slDistancePrice / tickSize;
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
//                       COUNTING / KILLZONE / DAILY
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
      LogInfo("CIRCUIT BREAKER: " + IntegerToString(gConsecLosses) + " consec losses. Halting.");
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
