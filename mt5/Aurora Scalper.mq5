//+------------------------------------------------------------------+
//|                                            Aurora Scalper.mq5    |
//|              XAUUSD EMA-12 Retest Scalper (MT5) — M1 / M15       |
//|                                                                  |
//|  v2.2 (ANTISIGNAL EXPERIMENT — post second blowout 2026-05-19):  |
//|    v2.1 lost -99% over 833 trades: 19.81% wins vs 25% RANDOM     |
//|    baseline at 3:1 RR. The entries themselves are anti-edge —    |
//|    M1 EMA retests in trend direction systematically fail because |
//|    XAUUSD M1 is mean-reverting, not trending. Filters made it    |
//|    worse (removed 79 winners, added 8 losers).                   |
//|                                                                  |
//|  v2.2 flips execution direction (InpInvertDirection=true):       |
//|    - Same triggers, same filters, same SL/TP distances           |
//|    - But where v2.1 went SHORT, v2.2 goes LONG (and vice versa)  |
//|    - Theory: if 80% of v2.1 entries hit SL, fading them should   |
//|      capture the actual mean-reverting move                      |
//|    - RISK: empirical play, may overfit. Backtest on 3 windows.   |
//+------------------------------------------------------------------+
#property copyright "Aurora — github.com/eliezzzerrr/Aurora"
#property link      "https://github.com/eliezzzerrr/Aurora"
#property version   "2.20"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================

input string  IH_Risk          = "════════ Risk (fixed dollars) ════════";
input double  InpStopLossDollars   = 5.0;      // Max loss per trade ($)
input double  InpTakeProfitDollars = 15.0;     // Take profit target per trade ($) — 3:1 RR
input double  InpSLPips            = 10.0;     // SL distance in pips (lot size sized to hit $ risk at this distance)

input string  IH_Pos           = "════════ Position Limits ════════";
input int     InpMaxPositions  = 3;            // Max concurrent open positions

input string  IH_Sess          = "════════ Killzones (OFF for scalper) ════════";
input bool    InpUseKillzones  = false;        // Off by default — scalper runs 24/5
input int     InpBrokerToUTC   = -4;
input int     InpLondonOpenH   = 7;
input int     InpLondonCloseH  = 10;
input int     InpNYOpenH       = 12;
input int     InpNYOpenM       = 30;
input int     InpNYCloseH      = 15;
input int     InpNYCloseM      = 30;

input string  IH_Struct        = "════════ Structure / EMA ════════";
input ENUM_TIMEFRAMES InpBiasTF  = PERIOD_M15; // HTF bias timeframe
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M1;  // Entry timeframe (EMA + retest)
input int     InpEMAPeriod     = 12;           // Entry EMA period (M1 retest)
input int     InpHTFEMAPeriod  = 50;           // HTF trend EMA period (M15)
input int     InpHTFBiasBars   = 30;           // M15 bars for swing-based bias (~7.5h)

input string  IH_Filters       = "════════ Entry Filters (v2.1 — defaults ON) ════════";
input bool    InpRequireRejectionClose = true; // M1 bar must close back on trend side after touch
input bool    InpRequireEMASlope       = true; // M1 EMA(12) must slope in bias direction
input int     InpEMASlopeBars          = 5;    // Bars back used to measure EMA slope
input bool    InpRequireHTFTrend       = true; // M15 EMA(50) must slope in bias direction
input int     InpHTFSlopeBars          = 3;    // M15 bars back to measure HTF EMA slope
input int     InpCooldownBars          = 5;    // Min M1 bars between consecutive entries
input double  InpMaxSpreadPips         = 3.0;  // Skip entry if spread exceeds this (in pips)

input string  IH_Exec          = "════════ Execution ════════";
input bool    InpInvertDirection = true;       // v2.2 ANTISIGNAL: flip BUY/SELL on every trigger
input long    InpMagic         = 87742;        // Magic number
input string  InpComment       = "Aurora Scalper v2.2";
input int     InpSlippage      = 30;

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxTradesDay  = 30;           // Daily cap on filled entries
input int     InpMaxConsecLoss = 4;            // Halt after N consecutive losses
input bool    InpLogToFile     = true;

//==================================================================
//                          GLOBALS
//==================================================================

CTrade        gTrade;
CSymbolInfo   gSym;
CPositionInfo gPos;
COrderInfo    gOrd;

datetime      gLastBarEntry  = 0;
datetime      gLastFillBar   = 0;     // M1 bar time of last placed entry (for cooldown)
datetime      gTodayKey      = 0;
int           gTradesToday   = 0;
int           gConsecLosses  = 0;
bool          gHaltedToday   = false;

int           gEMAHandle     = INVALID_HANDLE;  // EMA(12) on M1
int           gHTFEMAHandle  = INVALID_HANDLE;  // EMA(50) on M15
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
      LogError("Failed to create entry EMA handle");
      return INIT_FAILED;
   }
   gHTFEMAHandle = iMA(_Symbol, InpBiasTF, InpHTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (gHTFEMAHandle == INVALID_HANDLE) {
      LogError("Failed to create HTF EMA handle");
      return INIT_FAILED;
   }

   LogInfo("==============================================");
   LogInfo("Aurora Scalper v2.2 (EMA-12 retest + ANTISIGNAL) on " + _Symbol);
   LogInfo("  Invert direction: " + (InpInvertDirection ? "YES (fade v2.1 entries)" : "NO (v2.1 behavior)"));
   LogInfo("  Magic:           " + IntegerToString(InpMagic));
   LogInfo("  Stop loss ($):   " + DoubleToString(InpStopLossDollars, 2));
   LogInfo("  Take profit($):  " + DoubleToString(InpTakeProfitDollars, 2));
   LogInfo("  SL pips:         " + DoubleToString(InpSLPips, 1));
   LogInfo("  RR:              " + DoubleToString(InpTakeProfitDollars / InpStopLossDollars, 2));
   LogInfo("  Max positions:   " + IntegerToString(InpMaxPositions));
   LogInfo("  Bias TF / EMA:   " + EnumToString(InpBiasTF) + " / EMA(" + IntegerToString(InpHTFEMAPeriod) + ")");
   LogInfo("  Entry TF / EMA:  " + EnumToString(InpEntryTF) + " / EMA(" + IntegerToString(InpEMAPeriod) + ")");
   LogInfo("  Filters: rejClose=" + (InpRequireRejectionClose?"Y":"N") +
           " emaSlope=" + (InpRequireEMASlope?"Y":"N") +
           " htfTrend=" + (InpRequireHTFTrend?"Y":"N") +
           " cooldown=" + IntegerToString(InpCooldownBars) +
           " maxSprd=" + DoubleToString(InpMaxSpreadPips, 1) + "p");
   LogInfo("  Killzones:       " + (InpUseKillzones ? "ON" : "OFF (24/5)"));
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (gEMAHandle    != INVALID_HANDLE) { IndicatorRelease(gEMAHandle);    gEMAHandle    = INVALID_HANDLE; }
   if (gHTFEMAHandle != INVALID_HANDLE) { IndicatorRelease(gHTFEMAHandle); gHTFEMAHandle = INVALID_HANDLE; }
   LogInfo("Aurora Scalper deinit. Reason code: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   datetime curBar = iTime(_Symbol, InpEntryTF, 0);
   if (curBar == 0 || curBar == gLastBarEntry) return;
   gLastBarEntry = curBar;

   OnNewEntryBar();
}

//==================================================================
//                          ON NEW ENTRY BAR (M1)
//==================================================================

void OnNewEntryBar() {
   UpdateDailyCounters();

   if (gHaltedToday) return;
   if (gTradesToday >= InpMaxTradesDay) return;
   if (InpUseKillzones && !IsInKillzone()) return;
   if (CountActiveAuroraOrders() >= InpMaxPositions) return;

   // Cooldown gate
   if (gLastFillBar > 0) {
      int barsSinceFill = iBarShift(_Symbol, InpEntryTF, gLastFillBar);
      if (barsSinceFill < InpCooldownBars) return;
   }

   // Spread gate
   double spreadPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double spreadPips  = spreadPrice / gPip;
   if (spreadPips > InpMaxSpreadPips) {
      LogDebug(StringFormat("[SKIP] Spread %.2f pips > max %.1f", spreadPips, InpMaxSpreadPips));
      return;
   }

   int bias = GetHTFBias();
   if (bias == 0) return;

   // HTF trend confirmation (EMA50 on M15 must slope in bias direction)
   if (InpRequireHTFTrend) {
      int htfSlope = GetEMASlope(gHTFEMAHandle, InpHTFSlopeBars);
      if (htfSlope != bias) return;
   }

   // M1 EMA values
   double ema1, ema2;
   if (!GetEMAValue(gEMAHandle, 1, ema1)) return;
   if (!GetEMAValue(gEMAHandle, 2, ema2)) return;

   // M1 EMA slope must match bias
   if (InpRequireEMASlope) {
      int m1Slope = GetEMASlope(gEMAHandle, InpEMASlopeBars);
      if (m1Slope != bias) return;
   }

   double bar1O = iOpen (_Symbol, InpEntryTF, 1);
   double bar1H = iHigh (_Symbol, InpEntryTF, 1);
   double bar1L = iLow  (_Symbol, InpEntryTF, 1);
   double bar1C = iClose(_Symbol, InpEntryTF, 1);
   double bar2H = iHigh (_Symbol, InpEntryTF, 2);
   double bar2L = iLow  (_Symbol, InpEntryTF, 2);

   // ---- "SHORT-side" trigger (bias short + bar wicks up to EMA) ----
   // v2.1 went short here. v2.2 with InpInvertDirection goes LONG (fade the rejection).
   if (bias < 0 && bar2H < ema2 && bar1H >= ema1) {
      if (InpRequireRejectionClose && bar1C >= ema1) {
         LogDebug("[SKIP-S] No rejection close — bar1 closed above EMA");
         return;
      }
      int execDir = (InpInvertDirection ? +1 : -1);
      LogSignal(StringFormat("[RETEST-S%s] H=%s C=%s EMA=%s → exec %s",
               (InpInvertDirection ? "/INV" : ""),
               DoubleToString(bar1H, _Digits),
               DoubleToString(bar1C, _Digits),
               DoubleToString(ema1, _Digits),
               (execDir > 0 ? "BUY" : "SELL")));
      ExecuteEntry(execDir);
      return;
   }

   // ---- "LONG-side" trigger (bias long + bar wicks down to EMA) ----
   // v2.1 went long here. v2.2 with InpInvertDirection goes SHORT.
   if (bias > 0 && bar2L > ema2 && bar1L <= ema1) {
      if (InpRequireRejectionClose && bar1C <= ema1) {
         LogDebug("[SKIP-L] No rejection close — bar1 closed below EMA");
         return;
      }
      int execDir = (InpInvertDirection ? -1 : +1);
      LogSignal(StringFormat("[RETEST-L%s] L=%s C=%s EMA=%s → exec %s",
               (InpInvertDirection ? "/INV" : ""),
               DoubleToString(bar1L, _Digits),
               DoubleToString(bar1C, _Digits),
               DoubleToString(ema1, _Digits),
               (execDir > 0 ? "BUY" : "SELL")));
      ExecuteEntry(execDir);
   }
}

//==================================================================
//                       ENTRY EXECUTION
//==================================================================

void ExecuteEntry(int direction) {
   double slDistPrice = InpSLPips * gPip;

   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsLevelPrice = (double)stopsLevelPts * _Point;
   if (slDistPrice < stopsLevelPrice + _Point) {
      slDistPrice = stopsLevelPrice + _Point;
      LogDebug("SL distance clamped to broker stops level: " + DoubleToString(slDistPrice, _Digits));
   }

   double lots = CalcLotsForDollarRisk(slDistPrice, InpStopLossDollars);
   if (lots <= 0) {
      LogError("Lot calc failed for SL distance " + DoubleToString(slDistPrice, _Digits));
      return;
   }

   double tpDistPrice = slDistPrice * (InpTakeProfitDollars / InpStopLossDollars);

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
      LogError("Order placement failed: " + gTrade.ResultRetcodeDescription());
      return;
   }

   gLastFillBar = iTime(_Symbol, InpEntryTF, 0);

   LogSignal(StringFormat("[%s] #%I64u %.2f lots @ %s · SL %s (-$%.2f) · TP %s (+$%.2f)",
            (direction < 0 ? "SELL" : "BUY"),
            gTrade.ResultOrder(),
            lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits), InpStopLossDollars,
            DoubleToString(tp, _Digits), InpTakeProfitDollars));
}

//==================================================================
//                       INDICATORS / BIAS
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
   if (llIdx < hhIdx) return -1;  // low more recent → bearish
   if (hhIdx < llIdx) return +1;  // high more recent → bullish
   return 0;
}

bool GetEMAValue(int handle, int shift, double &val) {
   double buf[];
   if (CopyBuffer(handle, 0, shift, 1, buf) < 1) {
      LogError("CopyBuffer EMA failed at shift " + IntegerToString(shift));
      return false;
   }
   val = buf[0];
   return true;
}

// Returns -1 (down), 0 (flat), +1 (up) based on EMA value at bar 1 vs bar lookbackBars
int GetEMASlope(int handle, int lookbackBars) {
   double now, then;
   if (!GetEMAValue(handle, 1, now)) return 0;
   if (!GetEMAValue(handle, lookbackBars + 1, then)) return 0;
   double diff = now - then;
   if (MathAbs(diff) < _Point) return 0;
   return (diff > 0) ? +1 : -1;
}

//==================================================================
//                       RISK / POSITION SIZING
//==================================================================

double CalcLotsForDollarRisk(double slDistancePrice, double riskDollars) {
   if (slDistancePrice <= 0 || riskDollars <= 0) return 0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0 || tickSize <= 0) return 0;

   double slTicks    = slDistancePrice / tickSize;
   double moneyPerLot = slTicks * tickValue;
   if (moneyPerLot <= 0) return 0;

   double lots = riskDollars / moneyPerLot;

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
//                       KILLZONE (off by default, optional)
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
