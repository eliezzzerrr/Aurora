//+------------------------------------------------------------------+
//|                                                       Aurora.mq5 |
//|             XAUUSD ICT/SMC Day-Trading EA (MT5) — v2.0           |
//|                                                                  |
//|  v2.0 changes (quality + risk upgrades):                         |
//|    • Risk: fixed % EQUITY (0.5% SL / 1% TP → 2:1 RR built-in)    |
//|      - Lot size auto-scales as equity grows                      |
//|      - SL distance from structure (sweep wick + buffer)          |
//|      - TP distance = SL × (TP%/SL%), drops opposing-pool TP      |
//|    • New quality filters (all default ON, can disable):          |
//|      - M15 EMA(50)/(200) alignment must confirm H1 HH/LL bias    |
//|      - M15 ADX > 20 (kills ranging/chop entries)                 |
//|      - M15 ATR floor + ceiling (kills dead vol AND news spikes)  |
//|      - Confirmation candle after CHoCH (1 bar continuation)      |
//|    • Same 4-stage state machine: SWEEP → CHoCH → OB → PENDING    |
//|    • Same killzone gating (London + NY AM)                       |
//|    • Same daily safety: max trades/day, consec-loss circuit      |
//+------------------------------------------------------------------+
#property copyright "Aurora — github.com/eliezzzerrr/Aurora"
#property link      "https://github.com/eliezzzerrr/Aurora"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================

input string  IH_Risk          = "════════ Risk (equity-scaled) ════════";
input double  InpSLPercent     = 0.5;          // Stop loss = % of EQUITY per trade
input double  InpTPPercent     = 1.0;          // Take profit = % of EQUITY per trade (1.0/0.5 = 2:1 RR)
input bool    InpMoveBE_at1R   = false;        // Move SL to BE at +1R (off by default — backtest showed it caps wins)

input string  IH_Quality       = "════════ Quality Filters (v2.0 — default ON) ════════";
input bool    InpUseEMAFilter  = true;         // Require M15 EMA(50)/(200) alignment to confirm H1 HH/LL bias
input int     InpEMAFastPeriod = 50;
input int     InpEMASlowPeriod = 200;
input ENUM_TIMEFRAMES InpEMABiasTF = PERIOD_M15;
input bool    InpUseADX        = true;         // Require ADX > threshold (kills chop)
input int     InpADXPeriod     = 14;
input double  InpADXMinValue   = 20.0;
input ENUM_TIMEFRAMES InpADXTF = PERIOD_M15;
input bool    InpUseATR        = true;         // Skip if M15 ATR is too low (dead) or too high (news)
input int     InpATRPeriod     = 14;
input double  InpATRMinPips    = 15.0;         // Dead-chop floor
input double  InpATRMaxPips    = 150.0;        // News-spike ceiling
input ENUM_TIMEFRAMES InpATRTF = PERIOD_M15;
input bool    InpRequireConfirmationCandle = true;  // Wait for 1-bar continuation after CHoCH

input string  IH_KZ            = "════════ Killzones (broker time) ════════";
input bool    InpUseKillzones  = true;         // Restrict to London + NY AM
input int     InpBrokerToUTC   = 0;            // Broker offset from UTC (0 = broker runs on UTC/GMT)
input int     InpLondonOpenH   = 7;
input int     InpLondonCloseH  = 10;
input int     InpNYOpenH       = 12;
input int     InpNYOpenM       = 30;
input int     InpNYCloseH      = 15;
input int     InpNYCloseM      = 30;

input string  IH_Struct        = "════════ Structure Detection ════════";
input int     InpSwingLookback = 3;            // Bars left/right for swing pivot
input double  InpEqualHighTolPips = 5.0;       // Pip tolerance for equal highs/lows
input int     InpStructureBars = 50;           // M15 bars to scan for structure
input int     InpHTFBiasBars   = 30;           // H1 bars to determine HH/LL bias

input string  IH_Exec          = "════════ Execution ════════";
input long    InpMagic         = 87741;        // Magic number
input string  InpComment       = "Aurora v2.0";
input int     InpSlippage      = 50;
input double  InpSLBufferPips  = 3.0;          // Extra pips beyond sweep wick for SL
input int     InpLimitExpireBars = 12;         // M15 bars before pending limit auto-cancels

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxTradesDay  = 3;
input int     InpMaxConsecLoss = 2;
input bool    InpLogToFile     = true;

//==================================================================
//                          GLOBALS
//==================================================================

CTrade        gTrade;
CSymbolInfo   gSym;
CPositionInfo gPos;
COrderInfo    gOrd;

datetime      gLastBarM15    = 0;
datetime      gTodayKey      = 0;
int           gTradesToday   = 0;
int           gConsecLosses  = 0;
bool          gHaltedToday   = false;

// Indicator handles
int           gEMAFastHandle = INVALID_HANDLE;
int           gEMASlowHandle = INVALID_HANDLE;
int           gADXHandle     = INVALID_HANDLE;
int           gATRHandle     = INVALID_HANDLE;

// Setup state machine
enum ESetupStage {
   STAGE_IDLE       = 0,
   STAGE_SWEPT      = 1,
   STAGE_CHOCH      = 2,    // CHoCH detected, awaiting confirmation candle
   STAGE_PENDING    = 3
};

struct SetupState {
   ESetupStage stage;
   int         direction;
   double      sweptLevel;
   double      sweepWickPeak;
   double      chochSwing;
   double      obTop;
   double      obBot;
   datetime    swepBarTime;
   datetime    chochBarTime;
   ulong       pendingTicket;
   double      orderEntry;
   double      orderSL;
   double      orderTP;
};
SetupState    gSt;

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

   // Create indicator handles
   if (InpUseEMAFilter) {
      gEMAFastHandle = iMA(_Symbol, InpEMABiasTF, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      gEMASlowHandle = iMA(_Symbol, InpEMABiasTF, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if (gEMAFastHandle == INVALID_HANDLE || gEMASlowHandle == INVALID_HANDLE) {
         LogError("Failed to create EMA handles");
         return INIT_FAILED;
      }
   }
   if (InpUseADX) {
      gADXHandle = iADX(_Symbol, InpADXTF, InpADXPeriod);
      if (gADXHandle == INVALID_HANDLE) {
         LogError("Failed to create ADX handle");
         return INIT_FAILED;
      }
   }
   if (InpUseATR) {
      gATRHandle = iATR(_Symbol, InpATRTF, InpATRPeriod);
      if (gATRHandle == INVALID_HANDLE) {
         LogError("Failed to create ATR handle");
         return INIT_FAILED;
      }
   }

   ResetSetup("INIT");

   LogInfo("==============================================");
   LogInfo("Aurora EA v2.0 initialized on " + _Symbol);
   LogInfo("  Magic:        " + IntegerToString(InpMagic));
   LogInfo("  SL / TP:      " + DoubleToString(InpSLPercent, 2) + "% / " + DoubleToString(InpTPPercent, 2) + "% of equity (RR " + DoubleToString(InpTPPercent/InpSLPercent, 2) + ")");
   LogInfo("  Pip size:     " + DoubleToString(gPip, _Digits));
   LogInfo("  Filters: EMA=" + (InpUseEMAFilter?"Y":"N") + " ADX=" + (InpUseADX?"Y":"N") + ">" + DoubleToString(InpADXMinValue,1) +
           " ATR=" + (InpUseATR?"Y":"N") + " [" + DoubleToString(InpATRMinPips,0) + "-" + DoubleToString(InpATRMaxPips,0) + "p]" +
           " ConfCandle=" + (InpRequireConfirmationCandle?"Y":"N"));
   LogInfo("  Killzones:    " + (InpUseKillzones ? "ON" : "OFF"));
   LogInfo("  Max/day:      " + IntegerToString(InpMaxTradesDay));
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (gEMAFastHandle != INVALID_HANDLE) IndicatorRelease(gEMAFastHandle);
   if (gEMASlowHandle != INVALID_HANDLE) IndicatorRelease(gEMASlowHandle);
   if (gADXHandle     != INVALID_HANDLE) IndicatorRelease(gADXHandle);
   if (gATRHandle     != INVALID_HANDLE) IndicatorRelease(gATRHandle);
   LogInfo("Aurora EA v2.0 deinit. Reason code: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   ManageOpenPositions();

   datetime curBarM15 = iTime(_Symbol, PERIOD_M15, 0);
   if (curBarM15 == 0 || curBarM15 == gLastBarM15) return;
   gLastBarM15 = curBarM15;

   OnNewM15Bar();
}

//==================================================================
//                          ON NEW M15 BAR
//==================================================================

void OnNewM15Bar() {
   UpdateDailyCounters();

   if (gHaltedToday) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("HALTED");
      return;
   }
   if (gTradesToday >= InpMaxTradesDay) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("MAX_TRADES");
      LogInfo("Daily trade limit reached (" + IntegerToString(gTradesToday) + "). Standing down.");
      return;
   }

   if (InpUseKillzones && !IsInKillzone()) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("OFF_KILLZONE");
      return;
   }

   // ---- v2.0 quality gates (only when looking for new setups) ----
   if (gSt.stage == STAGE_IDLE) {
      if (InpUseATR) {
         double atr;
         if (!GetIndicatorValue(gATRHandle, 0, 1, atr)) {
            LogDebug("ATR read failed, skipping bar");
            return;
         }
         double atrPips = atr / gPip;
         if (atrPips < InpATRMinPips) { LogDebug(StringFormat("ATR %.1fp < min %.1fp — DEAD CHOP, skip", atrPips, InpATRMinPips)); return; }
         if (atrPips > InpATRMaxPips) { LogDebug(StringFormat("ATR %.1fp > max %.1fp — NEWS SPIKE, skip", atrPips, InpATRMaxPips)); return; }
      }
      if (InpUseADX) {
         double adx;
         if (!GetIndicatorValue(gADXHandle, 0, 1, adx)) {
            LogDebug("ADX read failed, skipping bar");
            return;
         }
         if (adx < InpADXMinValue) { LogDebug(StringFormat("ADX %.1f < min %.1f — RANGING, skip", adx, InpADXMinValue)); return; }
      }
   }

   switch (gSt.stage) {
      case STAGE_IDLE:    StageIdle();    break;
      case STAGE_SWEPT:   StageSwept();   break;
      case STAGE_CHOCH:   StageChoch();   break;
      case STAGE_PENDING: StagePending(); break;
   }

   LogStage();
}

//==================================================================
//                       STATE MACHINE STAGES
//==================================================================

void StageIdle() {
   int htfBias = GetHTFBias();
   if (htfBias == 0) {
      LogDebug("Idle: HTF bias unclear, skipping");
      return;
   }

   double bsl = 0, ssl = 0;
   datetime bslTime = 0, sslTime = 0;
   FindLiquidityPools(InpStructureBars, bsl, bslTime, ssl, sslTime);

   double bar1H = iHigh(_Symbol, PERIOD_M15, 1);
   double bar1L = iLow(_Symbol, PERIOD_M15, 1);
   double bar1C = iClose(_Symbol, PERIOD_M15, 1);

   if (htfBias < 0 && bsl > 0) {
      if (bar1H > bsl && bar1C < bsl) {
         gSt.stage          = STAGE_SWEPT;
         gSt.direction      = -1;
         gSt.sweptLevel     = bsl;
         gSt.sweepWickPeak  = bar1H;
         gSt.swepBarTime    = iTime(_Symbol, PERIOD_M15, 1);
         LogSignal("[SWEEP] Short — BSL @ " + DoubleToString(bsl, _Digits) +
                   " wicked to " + DoubleToString(bar1H, _Digits) +
                   ", closed at " + DoubleToString(bar1C, _Digits));
         return;
      }
   }

   if (htfBias > 0 && ssl > 0) {
      if (bar1L < ssl && bar1C > ssl) {
         gSt.stage          = STAGE_SWEPT;
         gSt.direction      = +1;
         gSt.sweptLevel     = ssl;
         gSt.sweepWickPeak  = bar1L;
         gSt.swepBarTime    = iTime(_Symbol, PERIOD_M15, 1);
         LogSignal("[SWEEP] Long — SSL @ " + DoubleToString(ssl, _Digits) +
                   " wicked to " + DoubleToString(bar1L, _Digits) +
                   ", closed at " + DoubleToString(bar1C, _Digits));
      }
   }
}

void StageSwept() {
   int barsSinceSweep = iBarShift(_Symbol, PERIOD_M15, gSt.swepBarTime) - 1;
   if (barsSinceSweep > 8) {
      ResetSetup("SWEEP_TIMEOUT");
      return;
   }

   double bar1C = iClose(_Symbol, PERIOD_M15, 1);
   if (gSt.direction < 0 && bar1C > gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED (close > sweep high)");
      return;
   }
   if (gSt.direction > 0 && bar1C < gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED (close < sweep low)");
      return;
   }

   double chochLevel = FindRecentSwing(gSt.direction, gSt.swepBarTime);
   if (chochLevel <= 0) {
      LogDebug("Swept: no valid recent swing found yet");
      return;
   }

   if (gSt.direction < 0 && bar1C < chochLevel) {
      gSt.stage         = STAGE_CHOCH;
      gSt.chochSwing    = chochLevel;
      gSt.chochBarTime  = iTime(_Symbol, PERIOD_M15, 1);
      LogSignal("[CHoCH] Short confirmed — close " + DoubleToString(bar1C, _Digits) +
                " < swing low " + DoubleToString(chochLevel, _Digits));
   }
   else if (gSt.direction > 0 && bar1C > chochLevel) {
      gSt.stage         = STAGE_CHOCH;
      gSt.chochSwing    = chochLevel;
      gSt.chochBarTime  = iTime(_Symbol, PERIOD_M15, 1);
      LogSignal("[CHoCH] Long confirmed — close " + DoubleToString(bar1C, _Digits) +
                " > swing high " + DoubleToString(chochLevel, _Digits));
   }
}

// v2.0: CHoCH stage now waits for confirmation candle (1 bar continuation)
// before placing the OB limit order.
void StageChoch() {
   // Confirmation candle: bar 1 (just-closed, the bar AFTER CHoCH bar) must close in direction
   if (InpRequireConfirmationCandle) {
      double bar1O = iOpen (_Symbol, PERIOD_M15, 1);
      double bar1C = iClose(_Symbol, PERIOD_M15, 1);
      bool confirmed = (gSt.direction < 0) ? (bar1C < bar1O) : (bar1C > bar1O);
      if (!confirmed) {
         ResetSetup("NO_CONFIRMATION_CANDLE");
         return;
      }
      LogSignal("[CONFIRM] Continuation candle closed in direction");
   }

   int chochIdx = iBarShift(_Symbol, PERIOD_M15, gSt.chochBarTime);
   double obTop = 0, obBot = 0;
   if (!FindOB(gSt.direction, chochIdx, obTop, obBot)) {
      ResetSetup("NO_OB_FOUND");
      return;
   }
   gSt.obTop = obTop;
   gSt.obBot = obBot;

   // Compute SL from structure (sweep wick + buffer), TP = SL × (TP%/SL%)
   double entry, sl, tp, slDistance;
   double tpSlRatio = InpTPPercent / InpSLPercent;

   if (gSt.direction < 0) {
      entry      = obTop;
      sl         = gSt.sweepWickPeak + InpSLBufferPips * gPip;
      slDistance = MathAbs(sl - entry);
      tp         = entry - slDistance * tpSlRatio;
   } else {
      entry      = obBot;
      sl         = gSt.sweepWickPeak - InpSLBufferPips * gPip;
      slDistance = MathAbs(entry - sl);
      tp         = entry + slDistance * tpSlRatio;
   }

   if (slDistance <= 0) {
      ResetSetup("BAD_SL_DISTANCE");
      return;
   }

   gSt.orderEntry = entry;
   gSt.orderSL    = sl;
   gSt.orderTP    = tp;

   // Lot size: SL distance × lot value = InpSLPercent of equity
   double lots = CalcLotsFromEquityPercent(slDistance, InpSLPercent);
   if (lots <= 0) {
      ResetSetup("LOT_CALC_FAILED");
      return;
   }

   bool ok;
   if (gSt.direction < 0) {
      ok = gTrade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);
   } else {
      ok = gTrade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);
   }

   if (!ok) {
      LogError("Order placement failed: " + gTrade.ResultRetcodeDescription());
      ResetSetup("ORDER_FAILED");
      return;
   }

   gSt.pendingTicket = gTrade.ResultOrder();
   gSt.stage         = STAGE_PENDING;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double slDollar = equity * InpSLPercent / 100.0;
   double tpDollar = equity * InpTPPercent / 100.0;

   LogSignal(StringFormat("[LIMIT PLACED] %s %.2f lots @ %s · SL %s (-$%.2f / %.2f%%) · TP %s (+$%.2f / %.2f%%) · RR %.2f",
            (gSt.direction < 0 ? "SELL" : "BUY"),
            lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits), slDollar, InpSLPercent,
            DoubleToString(tp, _Digits), tpDollar, InpTPPercent,
            tpSlRatio));
}

void StagePending() {
   if (!gOrd.Select(gSt.pendingTicket)) {
      if (IsPositionOpen(gSt.pendingTicket)) {
         LogSignal("[FILLED] Position opened from ticket " + IntegerToString((long)gSt.pendingTicket));
         gTradesToday++;
         ResetSetup("FILLED_INTO_POSITION");
         return;
      }
      LogInfo("Pending order " + IntegerToString((long)gSt.pendingTicket) + " no longer exists. Resetting.");
      ResetSetup("ORDER_GONE");
      return;
   }

   double bar1C = iClose(_Symbol, PERIOD_M15, 1);
   if (gSt.direction < 0 && bar1C > gSt.sweepWickPeak) {
      gTrade.OrderDelete(gSt.pendingTicket);
      ResetSetup("PENDING_INVALIDATED (sweep wick broken)");
      return;
   }
   if (gSt.direction > 0 && bar1C < gSt.sweepWickPeak) {
      gTrade.OrderDelete(gSt.pendingTicket);
      ResetSetup("PENDING_INVALIDATED (sweep wick broken)");
      return;
   }

   int barsSinceCHoCH = iBarShift(_Symbol, PERIOD_M15, gSt.chochBarTime) - 1;
   if (barsSinceCHoCH > InpLimitExpireBars) {
      gTrade.OrderDelete(gSt.pendingTicket);
      ResetSetup("PENDING_EXPIRED");
      return;
   }
}

//==================================================================
//                       BIAS DETECTION (v2.0: multi-confirmation)
//==================================================================

// Returns +1 (bullish), -1 (bearish), 0 (no setup).
// v2.0: requires BOTH H1 HH/LL ordering AND M15 EMA(50)/(200) alignment to agree.
int GetHTFBias() {
   int hhllBias = GetHHLLBias();
   if (hhllBias == 0) return 0;

   if (InpUseEMAFilter) {
      int emaBias = GetEMABias();
      if (emaBias == 0)             return 0;
      if (emaBias != hhllBias)      return 0;
   }

   return hhllBias;
}

// H1 HH/LL ordering: bearish if low is more recent than high, bullish if reversed.
int GetHHLLBias() {
   int bars = InpHTFBiasBars;
   if (Bars(_Symbol, PERIOD_H1) < bars + 5) return 0;

   double hh = 0, ll = 99999999;
   int hhIdx = -1, llIdx = -1;
   for (int i = 1; i <= bars; i++) {
      double h = iHigh(_Symbol, PERIOD_H1, i);
      double l = iLow(_Symbol, PERIOD_H1, i);
      if (h > hh) { hh = h; hhIdx = i; }
      if (l < ll) { ll = l; llIdx = i; }
   }
   if (llIdx < hhIdx) return -1;
   if (hhIdx < llIdx) return +1;
   return 0;
}

// M15 EMA(50) vs EMA(200) alignment, with price location confirmation.
// Bullish: EMA50 > EMA200 AND price (close) > EMA50.
// Bearish: EMA50 < EMA200 AND price (close) < EMA50.
// Otherwise: 0 (no clear trend).
int GetEMABias() {
   double emaFast, emaSlow;
   if (!GetIndicatorValue(gEMAFastHandle, 0, 1, emaFast)) return 0;
   if (!GetIndicatorValue(gEMASlowHandle, 0, 1, emaSlow)) return 0;
   double close = iClose(_Symbol, InpEMABiasTF, 1);

   if (emaFast > emaSlow && close > emaFast) return +1;
   if (emaFast < emaSlow && close < emaFast) return -1;
   return 0;
}

bool GetIndicatorValue(int handle, int bufferIdx, int shift, double &val) {
   if (handle == INVALID_HANDLE) return false;
   double buf[];
   if (CopyBuffer(handle, bufferIdx, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
}

//==================================================================
//                       STRUCTURE DETECTION
//==================================================================

void FindLiquidityPools(int lookback, double &bsl, datetime &bslTime, double &ssl, datetime &sslTime) {
   bsl = 0; ssl = 0; bslTime = 0; sslTime = 0;
   double tol = InpEqualHighTolPips * gPip;
   if (Bars(_Symbol, PERIOD_M15) < lookback + 2) return;

   double swingHighs[], swingLows[];
   datetime swingHighsT[], swingLowsT[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingHighsT, 0);
   ArrayResize(swingLowsT, 0);

   int sl = InpSwingLookback;
   for (int i = sl + 1; i <= lookback - sl; i++) {
      double h = iHigh(_Symbol, PERIOD_M15, i);
      double l = iLow(_Symbol, PERIOD_M15, i);
      bool isSwingHigh = true, isSwingLow = true;
      for (int k = 1; k <= sl; k++) {
         if (iHigh(_Symbol, PERIOD_M15, i - k) >= h || iHigh(_Symbol, PERIOD_M15, i + k) >= h) isSwingHigh = false;
         if (iLow(_Symbol, PERIOD_M15, i - k) <= l  || iLow(_Symbol, PERIOD_M15, i + k) <= l)  isSwingLow  = false;
      }
      if (isSwingHigh) {
         int s = ArraySize(swingHighs);
         ArrayResize(swingHighs, s + 1); ArrayResize(swingHighsT, s + 1);
         swingHighs[s] = h; swingHighsT[s] = iTime(_Symbol, PERIOD_M15, i);
      }
      if (isSwingLow) {
         int s = ArraySize(swingLows);
         ArrayResize(swingLows, s + 1); ArrayResize(swingLowsT, s + 1);
         swingLows[s] = l; swingLowsT[s] = iTime(_Symbol, PERIOD_M15, i);
      }
   }

   for (int i = 0; i < ArraySize(swingHighs); i++) {
      for (int j = i + 1; j < ArraySize(swingHighs); j++) {
         if (MathAbs(swingHighs[i] - swingHighs[j]) <= tol) {
            double avg = (swingHighs[i] + swingHighs[j]) / 2.0;
            if (avg > bsl) { bsl = avg; bslTime = swingHighsT[i]; }
            break;
         }
      }
   }
   for (int i = 0; i < ArraySize(swingLows); i++) {
      for (int j = i + 1; j < ArraySize(swingLows); j++) {
         if (MathAbs(swingLows[i] - swingLows[j]) <= tol) {
            double avg = (swingLows[i] + swingLows[j]) / 2.0;
            if (ssl <= 0 || avg < ssl) { ssl = avg; sslTime = swingLowsT[i]; }
            break;
         }
      }
   }

   if (bsl <= 0 && ArraySize(swingHighs) > 0) {
      int idx = ArrayMaximum(swingHighs);
      bsl = swingHighs[idx]; bslTime = swingHighsT[idx];
   }
   if (ssl <= 0 && ArraySize(swingLows) > 0) {
      int idx = ArrayMinimum(swingLows);
      ssl = swingLows[idx]; sslTime = swingLowsT[idx];
   }
}

double FindRecentSwing(int direction, datetime beforeBarTime) {
   int beforeIdx = iBarShift(_Symbol, PERIOD_M15, beforeBarTime);
   int sl = InpSwingLookback;
   for (int i = beforeIdx + 1; i < beforeIdx + 30; i++) {
      if (i + sl >= Bars(_Symbol, PERIOD_M15)) break;
      bool isSwing = true;
      double level = (direction < 0) ? iLow(_Symbol, PERIOD_M15, i) : iHigh(_Symbol, PERIOD_M15, i);
      for (int k = 1; k <= sl; k++) {
         if (direction < 0) {
            if (iLow(_Symbol, PERIOD_M15, i - k) <= level || iLow(_Symbol, PERIOD_M15, i + k) <= level) isSwing = false;
         } else {
            if (iHigh(_Symbol, PERIOD_M15, i - k) >= level || iHigh(_Symbol, PERIOD_M15, i + k) >= level) isSwing = false;
         }
      }
      if (isSwing) return level;
   }
   return 0;
}

bool FindOB(int direction, int chochIdx, double &obTop, double &obBot) {
   for (int i = chochIdx; i < chochIdx + 10; i++) {
      double o = iOpen(_Symbol, PERIOD_M15, i);
      double c = iClose(_Symbol, PERIOD_M15, i);
      bool isOpposing = (direction < 0) ? (c > o) : (c < o);
      if (isOpposing) {
         obTop = iHigh(_Symbol, PERIOD_M15, i);
         obBot = iLow(_Symbol, PERIOD_M15, i);
         return true;
      }
   }
   return false;
}

//==================================================================
//                       RISK / POSITION SIZING (v2.0: equity %)
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
   if (lots < lotMin) {
      LogDebug(StringFormat("Lot clamped UP to min %.2f (target %.4f) — real risk will exceed %.2f%% on small account",
               lotMin, lots, riskPct));
      lots = lotMin;
   }
   if (lots > lotMax) lots = lotMax;
   return NormalizeDouble(lots, 2);
}

//==================================================================
//                       POSITION MANAGEMENT
//==================================================================

void ManageOpenPositions() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (!gPos.SelectByIndex(i)) continue;
      if (gPos.Magic() != InpMagic) continue;
      if (gPos.Symbol() != _Symbol) continue;
      if (InpMoveBE_at1R) MoveToBE(gPos.Ticket());
   }
}

void MoveToBE(ulong ticket) {
   if (!gPos.SelectByTicket(ticket)) return;
   double entry  = gPos.PriceOpen();
   double sl     = gPos.StopLoss();
   double tp     = gPos.TakeProfit();
   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double risk   = MathAbs(entry - sl);
   if (risk <= 0) return;

   bool isLong = (gPos.PositionType() == POSITION_TYPE_BUY);
   double oneR = isLong ? (entry + risk) : (entry - risk);

   if (isLong && sl >= entry) return;
   if (!isLong && sl <= entry) return;

   bool trigger = isLong ? (curBid >= oneR) : (curAsk <= oneR);
   if (trigger) {
      double newSL = NormalizeDouble(entry, _Digits);
      if (gTrade.PositionModify(ticket, newSL, tp)) {
         LogSignal("[BE MOVE] Position " + IntegerToString((long)ticket) + " SL → BE");
      }
   }
}

bool IsPositionOpen(ulong ticket) {
   for (int i = 0; i < PositionsTotal(); i++) {
      if (!gPos.SelectByIndex(i)) continue;
      if (gPos.Magic() == InpMagic && gPos.Symbol() == _Symbol) return true;
   }
   return false;
}

//==================================================================
//                       KILLZONE CHECK
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
//                       DAILY COUNTERS / CIRCUIT BREAKER
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

   TrackClosedPositionsForCircuitBreaker();
}

void TrackClosedPositionsForCircuitBreaker() {
   HistorySelect(gTodayKey, TimeCurrent());
   int total = HistoryDealsTotal();

   int consec = 0;
   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if (magic != InpMagic) continue;
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
      LogInfo("CIRCUIT BREAKER: " + IntegerToString(gConsecLosses) + " consecutive losses. Halting for the day.");
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
   int h = FileOpen("Aurora_Journal.txt", FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
   if (h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, TimestampStr() + " [" + level + "] " + msg + "\n");
   FileClose(h);
}

void LogInfo(string m)   { Print("[INFO] ",   m); LogToFile("INFO",   m); }
void LogDebug(string m)  { LogToFile("DEBUG",  m); }
void LogSignal(string m) { Print("[SIGNAL] ", m); LogToFile("SIGNAL", m); }
void LogError(string m)  { Print("[ERROR] ",  m); LogToFile("ERROR",  m); }

void LogStage() {
   string s = "STAGE=";
   switch (gSt.stage) {
      case STAGE_IDLE:    s += "IDLE"; break;
      case STAGE_SWEPT:   s += "SWEPT (dir=" + IntegerToString(gSt.direction) + ", level=" + DoubleToString(gSt.sweptLevel, _Digits) + ")"; break;
      case STAGE_CHOCH:   s += "CHOCH-await-confirm (dir=" + IntegerToString(gSt.direction) + ", swing=" + DoubleToString(gSt.chochSwing, _Digits) + ")"; break;
      case STAGE_PENDING: s += "PENDING ticket=" + IntegerToString((long)gSt.pendingTicket); break;
   }
   LogDebug(s);
}

//==================================================================
//                       UTILITY
//==================================================================

void ResetSetup(string reason) {
   if (gSt.stage != STAGE_IDLE) {
      LogInfo("RESET setup: " + reason);
   }
   gSt.stage         = STAGE_IDLE;
   gSt.direction     = 0;
   gSt.sweptLevel    = 0;
   gSt.sweepWickPeak = 0;
   gSt.chochSwing    = 0;
   gSt.obTop         = 0;
   gSt.obBot         = 0;
   gSt.swepBarTime   = 0;
   gSt.chochBarTime  = 0;
   gSt.pendingTicket = 0;
   gSt.orderEntry    = 0;
   gSt.orderSL       = 0;
   gSt.orderTP       = 0;
}
