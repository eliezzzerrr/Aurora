//+------------------------------------------------------------------+
//|                                            Aurora Scalper.mq5    |
//|              XAUUSD ICT/SMC Scalper (MT5) — 1m / 5m / 15m        |
//|                                                                  |
//|  Scalper variant of Aurora. Differences vs day-trader EA:        |
//|    - HTF bias from M15 (not H1)                                  |
//|    - Sweep detection on M5 (not M15)                             |
//|    - CHoCH + OB on M1 (not M15)                                  |
//|    - Up to 3 concurrent positions (not 1)                        |
//|    - NO session/killzone filter — runs 24/5                      |
//|    - Faster pending-order expiry (1m bars)                       |
//|                                                                  |
//|  Same 2:1 RR enforcement, 1% balance risk, BE rule disabled      |
//|  by default (backtest showed BE caps wins).                      |
//+------------------------------------------------------------------+
#property copyright "Aurora — github.com/eliezzzerrr/Aurora"
#property link      "https://github.com/eliezzzerrr/Aurora"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//==================================================================
//                          INPUTS
//==================================================================

input string  IH_Risk          = "════════ Risk ════════";
input double  InpRiskPercent   = 0.5;          // Risk per trade (% of balance) — lower for scalper since 3 concurrent
input double  InpRRMin         = 1.5;          // Minimum reward-to-risk ratio (1.5 = scalper-friendly)
input bool    InpMoveBE_at1R   = false;        // Move SL to BE at +1R (default OFF)

input string  IH_Pos           = "════════ Position Limits ════════";
input int     InpMaxPositions  = 3;            // Max concurrent open positions
input int     InpMaxPendings   = 3;            // Max pending limit orders waiting to fill

input string  IH_Sess          = "════════ Killzones (OFF for scalper) ════════";
input bool    InpUseKillzones  = false;        // Off by default — scalper runs 24/5
input int     InpBrokerToUTC   = -4;
input int     InpLondonOpenH   = 7;
input int     InpLondonCloseH  = 10;
input int     InpNYOpenH       = 12;
input int     InpNYOpenM       = 30;
input int     InpNYCloseH      = 15;
input int     InpNYCloseM      = 30;

input string  IH_Struct        = "════════ Structure (scalper timeframes) ════════";
input ENUM_TIMEFRAMES InpBiasTF     = PERIOD_M15;  // HTF bias timeframe
input ENUM_TIMEFRAMES InpSweepTF    = PERIOD_M5;   // Liquidity sweep detection timeframe
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M1;   // CHoCH + OB + entry timeframe
input int     InpSwingLookback = 2;            // Bars left/right for swing pivot (tighter on 1m)
input bool    InpRequireEqualHighs = false;    // true: only sweep clustered equal-highs/lows. false: sweep any prominent swing (more trades)
input double  InpEqualHighTolPips = 2.0;       // Pip tolerance when InpRequireEqualHighs = true
input int     InpStructureBars = 120;          // M5 bars for liquidity pools (~10 hours)
input int     InpHTFBiasBars   = 30;           // M15 bars for bias (~7.5 hours)
input int     InpSweepTimeoutBars = 8;         // M1 bars after sweep before resetting if no CHoCH (was 15 — tightened)

input string  IH_Exec          = "════════ Execution ════════";
input long    InpMagic         = 87742;        // Magic number (scalper)
input string  InpComment       = "Aurora Scalper";
input int     InpSlippage      = 30;
input double  InpSLBufferPips  = 2.0;          // Extra pips beyond sweep wick (tighter on scalp)
input int     InpLimitExpireBars = 20;         // M1 bars before pending limit auto-cancels (20 min)

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxTradesDay  = 15;           // Higher daily cap for scalper
input int     InpMaxConsecLoss = 3;            // Halt after N consecutive losses
input bool    InpLogToFile     = true;

//==================================================================
//                          GLOBALS
//==================================================================

CTrade        gTrade;
CSymbolInfo   gSym;
CPositionInfo gPos;
COrderInfo    gOrd;

datetime      gLastBarEntry  = 0;
datetime      gTodayKey      = 0;
int           gTradesToday   = 0;
int           gConsecLosses  = 0;
bool          gHaltedToday   = false;

// Per-entry-bar setup state (single state machine, but resets to IDLE
// immediately after placing limit so next bar can hunt fresh setups)
enum ESetupStage {
   STAGE_IDLE       = 0,
   STAGE_SWEPT      = 1,
   STAGE_CHOCH      = 2
};

struct SetupState {
   ESetupStage stage;
   int         direction;        // -1 short, +1 long
   double      sweptLevel;
   double      sweepWickPeak;
   double      chochSwing;
   double      obTop;
   double      obBot;
   double      targetLiq;
   datetime    sweepBarTime;
   datetime    chochBarTime;
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

   ResetSetup("INIT");

   LogInfo("==============================================");
   LogInfo("Aurora Scalper initialized on " + _Symbol);
   LogInfo("  Magic:        " + IntegerToString(InpMagic));
   LogInfo("  Risk/trade:   " + DoubleToString(InpRiskPercent, 2) + "%");
   LogInfo("  Max positions: " + IntegerToString(InpMaxPositions));
   LogInfo("  RR min:       " + DoubleToString(InpRRMin, 1));
   LogInfo("  Bias TF:      " + EnumToString(InpBiasTF));
   LogInfo("  Sweep TF:     " + EnumToString(InpSweepTF));
   LogInfo("  Entry TF:     " + EnumToString(InpEntryTF));
   LogInfo("  Killzones:    " + (InpUseKillzones ? "ON" : "OFF (24/5)"));
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   LogInfo("Aurora Scalper deinit. Reason code: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   ManageOpenPositions();

   // Run state machine on new M1 bar (entry TF)
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

   if (gHaltedToday) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("HALTED");
      return;
   }
   if (gTradesToday >= InpMaxTradesDay) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("MAX_TRADES");
      return;
   }

   if (InpUseKillzones && !IsInKillzone()) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("OFF_KILLZONE");
      return;
   }

   // State machine
   switch (gSt.stage) {
      case STAGE_IDLE:  StageIdle();  break;
      case STAGE_SWEPT: StageSwept(); break;
      case STAGE_CHOCH: StageChoch(); break;
   }
}

//==================================================================
//                       STATE MACHINE STAGES
//==================================================================

// STAGE 0: IDLE — scan M5 for sweep of liquidity pool
void StageIdle() {
   int htfBias = GetHTFBias();
   if (htfBias == 0) return;

   double bsl = 0, ssl = 0;
   datetime bslTime = 0, sslTime = 0;
   FindLiquidityPools(InpStructureBars, bsl, bslTime, ssl, sslTime);

   // Detect sweep on the just-closed M5 bar (index 1)
   double bar1H = iHigh(_Symbol, InpSweepTF, 1);
   double bar1L = iLow(_Symbol, InpSweepTF, 1);
   double bar1C = iClose(_Symbol, InpSweepTF, 1);

   if (htfBias < 0 && bsl > 0) {
      if (bar1H > bsl && bar1C < bsl) {
         gSt.stage          = STAGE_SWEPT;
         gSt.direction      = -1;
         gSt.sweptLevel     = bsl;
         gSt.sweepWickPeak  = bar1H;
         gSt.sweepBarTime   = iTime(_Symbol, InpSweepTF, 1);
         LogSignal("[SWEEP-S] BSL @ " + DoubleToString(bsl, _Digits) +
                   " wicked to " + DoubleToString(bar1H, _Digits) +
                   ", M5 close " + DoubleToString(bar1C, _Digits));
         return;
      }
   }
   if (htfBias > 0 && ssl > 0) {
      if (bar1L < ssl && bar1C > ssl) {
         gSt.stage          = STAGE_SWEPT;
         gSt.direction      = +1;
         gSt.sweptLevel     = ssl;
         gSt.sweepWickPeak  = bar1L;
         gSt.sweepBarTime   = iTime(_Symbol, InpSweepTF, 1);
         LogSignal("[SWEEP-L] SSL @ " + DoubleToString(ssl, _Digits) +
                   " wicked to " + DoubleToString(bar1L, _Digits) +
                   ", M5 close " + DoubleToString(bar1C, _Digits));
      }
   }
}

// STAGE 1: SWEPT — wait for CHoCH on M1
void StageSwept() {
   // Timeout: configurable M1 bars since sweep
   int barsSince = iBarShift(_Symbol, InpEntryTF, gSt.sweepBarTime);
   if (barsSince > InpSweepTimeoutBars) {
      ResetSetup("SWEEP_TIMEOUT");
      return;
   }

   // Invalidation
   double bar1C = iClose(_Symbol, InpEntryTF, 1);
   if (gSt.direction < 0 && bar1C > gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED");
      return;
   }
   if (gSt.direction > 0 && bar1C < gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED");
      return;
   }

   // Find recent M1 swing low/high BEFORE the sweep bar (mapped to entry TF index)
   int sweepEntryIdx = iBarShift(_Symbol, InpEntryTF, gSt.sweepBarTime);
   double chochLevel = FindRecentSwing(gSt.direction, sweepEntryIdx);
   if (chochLevel <= 0) return;

   if (gSt.direction < 0 && bar1C < chochLevel) {
      gSt.stage         = STAGE_CHOCH;
      gSt.chochSwing    = chochLevel;
      gSt.chochBarTime  = iTime(_Symbol, InpEntryTF, 1);
      LogSignal("[CHoCH-S] M1 close " + DoubleToString(bar1C, _Digits) +
                " < swing " + DoubleToString(chochLevel, _Digits));
   }
   else if (gSt.direction > 0 && bar1C > chochLevel) {
      gSt.stage         = STAGE_CHOCH;
      gSt.chochSwing    = chochLevel;
      gSt.chochBarTime  = iTime(_Symbol, InpEntryTF, 1);
      LogSignal("[CHoCH-L] M1 close " + DoubleToString(bar1C, _Digits) +
                " > swing " + DoubleToString(chochLevel, _Digits));
   }
}

// STAGE 2: CHoCH — find M1 OB, validate RR, place limit, then RESET to IDLE
//                  (so next bar can hunt new setups while limit is pending)
void StageChoch() {
   // Position cap check
   int activeCount = CountActiveAuroraOrders();
   if (activeCount >= InpMaxPositions) {
      LogDebug("Skip placement: " + IntegerToString(activeCount) + " active orders >= max " + IntegerToString(InpMaxPositions));
      ResetSetup("MAX_POSITIONS_REACHED");
      return;
   }

   int chochIdx = iBarShift(_Symbol, InpEntryTF, gSt.chochBarTime);
   double obTop = 0, obBot = 0;
   if (!FindOB(gSt.direction, chochIdx, obTop, obBot)) {
      ResetSetup("NO_OB_FOUND");
      return;
   }
   gSt.obTop = obTop;
   gSt.obBot = obBot;

   double targetLiq = FindOpposingLiquidity(gSt.direction, gSt.sweptLevel);
   if (targetLiq <= 0) {
      ResetSetup("NO_TARGET_LIQUIDITY");
      return;
   }
   gSt.targetLiq = targetLiq;

   double entry, sl, tp;
   if (gSt.direction < 0) {
      entry = obTop;
      sl    = gSt.sweepWickPeak + InpSLBufferPips * gPip;
      tp    = targetLiq;
   } else {
      entry = obBot;
      sl    = gSt.sweepWickPeak - InpSLBufferPips * gPip;
      tp    = targetLiq;
   }

   double risk = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   double rr = (risk > 0) ? reward / risk : 0;
   if (rr < InpRRMin) {
      LogSignal("[RR_FAIL] RR " + DoubleToString(rr, 2) + " < " + DoubleToString(InpRRMin, 1));
      ResetSetup("RR_TOO_LOW");
      return;
   }

   double lots = CalcLotSize(risk);
   if (lots <= 0) {
      ResetSetup("LOT_CALC_FAILED");
      return;
   }

   // Set order expiry time so MT5 auto-cancels if no fill
   datetime expireTime = TimeCurrent() + InpLimitExpireBars * PeriodSeconds(InpEntryTF);

   bool ok;
   if (gSt.direction < 0) {
      ok = gTrade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expireTime, InpComment);
   } else {
      ok = gTrade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expireTime, InpComment);
   }

   if (!ok) {
      LogError("Order placement failed: " + gTrade.ResultRetcodeDescription());
      ResetSetup("ORDER_FAILED");
      return;
   }

   ulong ticket = gTrade.ResultOrder();
   LogSignal(StringFormat("[LIMIT %s] #%I64u %.2f lots @ %s · SL %s · TP %s · RR %.2f",
            (gSt.direction < 0 ? "SELL" : "BUY"),
            ticket,
            lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits),
            rr));

   // RESET IMMEDIATELY so next M1 bar can hunt fresh setups
   ResetSetup("LIMIT_PLACED_RESET");
}

//==================================================================
//                       STRUCTURE DETECTION
//==================================================================

int GetHTFBias() {
   int bars = InpHTFBiasBars;
   if (Bars(_Symbol, InpBiasTF) < bars + 5) return 0;

   double hh = 0, ll = 99999999;
   int hhIdx = -1, llIdx = -1;
   for (int i = 1; i <= bars; i++) {
      double h = iHigh(_Symbol, InpBiasTF, i);
      double l = iLow(_Symbol, InpBiasTF, i);
      if (h > hh) { hh = h; hhIdx = i; }
      if (l < ll) { ll = l; llIdx = i; }
   }
   if (llIdx < hhIdx) return -1;
   if (hhIdx < llIdx) return +1;
   return 0;
}

void FindLiquidityPools(int lookback, double &bsl, datetime &bslTime, double &ssl, datetime &sslTime) {
   bsl = 0; ssl = 0; bslTime = 0; sslTime = 0;
   double tol = InpEqualHighTolPips * gPip;
   if (Bars(_Symbol, InpSweepTF) < lookback + 2) return;

   double swingHighs[], swingLows[];
   datetime swingHighsT[], swingLowsT[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);
   ArrayResize(swingHighsT, 0);
   ArrayResize(swingLowsT, 0);

   int sl = InpSwingLookback;
   for (int i = sl + 1; i <= lookback - sl; i++) {
      double h = iHigh(_Symbol, InpSweepTF, i);
      double l = iLow(_Symbol, InpSweepTF, i);
      bool isSwingHigh = true, isSwingLow = true;
      for (int k = 1; k <= sl; k++) {
         if (iHigh(_Symbol, InpSweepTF, i - k) >= h || iHigh(_Symbol, InpSweepTF, i + k) >= h) isSwingHigh = false;
         if (iLow(_Symbol, InpSweepTF, i - k) <= l  || iLow(_Symbol, InpSweepTF, i + k) <= l)  isSwingLow  = false;
      }
      if (isSwingHigh) {
         int s = ArraySize(swingHighs);
         ArrayResize(swingHighs, s + 1); ArrayResize(swingHighsT, s + 1);
         swingHighs[s] = h; swingHighsT[s] = iTime(_Symbol, InpSweepTF, i);
      }
      if (isSwingLow) {
         int s = ArraySize(swingLows);
         ArrayResize(swingLows, s + 1); ArrayResize(swingLowsT, s + 1);
         swingLows[s] = l; swingLowsT[s] = iTime(_Symbol, InpSweepTF, i);
      }
   }

   if (InpRequireEqualHighs) {
      // STRICT mode: only clustered equal-highs / equal-lows count as liquidity pools
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
   }

   // Fallback / LOOSE mode: use the most recent prominent swing high/low
   // (swingHighs[0] = newest because the scan iterates from low index = recent bar)
   if (bsl <= 0 && ArraySize(swingHighs) > 0) {
      bsl = swingHighs[0]; bslTime = swingHighsT[0];
   }
   if (ssl <= 0 && ArraySize(swingLows) > 0) {
      ssl = swingLows[0]; sslTime = swingLowsT[0];
   }
}

double FindRecentSwing(int direction, int afterIdx) {
   int sl = InpSwingLookback;
   for (int i = afterIdx + 1; i < afterIdx + 30; i++) {
      if (i + sl >= Bars(_Symbol, InpEntryTF)) break;
      bool isSwing = true;
      double level = (direction < 0) ? iLow(_Symbol, InpEntryTF, i) : iHigh(_Symbol, InpEntryTF, i);
      for (int k = 1; k <= sl; k++) {
         if (direction < 0) {
            if (iLow(_Symbol, InpEntryTF, i - k) <= level || iLow(_Symbol, InpEntryTF, i + k) <= level) isSwing = false;
         } else {
            if (iHigh(_Symbol, InpEntryTF, i - k) >= level || iHigh(_Symbol, InpEntryTF, i + k) >= level) isSwing = false;
         }
      }
      if (isSwing) return level;
   }
   return 0;
}

bool FindOB(int direction, int chochIdx, double &obTop, double &obBot) {
   for (int i = chochIdx; i < chochIdx + 8; i++) {
      double o = iOpen(_Symbol, InpEntryTF, i);
      double c = iClose(_Symbol, InpEntryTF, i);
      bool isOpposing = (direction < 0) ? (c > o) : (c < o);
      if (isOpposing) {
         obTop = iHigh(_Symbol, InpEntryTF, i);
         obBot = iLow(_Symbol, InpEntryTF, i);
         return true;
      }
   }
   return false;
}

double FindOpposingLiquidity(int direction, double swept) {
   double bsl = 0, ssl = 0;
   datetime t1 = 0, t2 = 0;
   FindLiquidityPools(InpStructureBars * 2, bsl, t1, ssl, t2);
   if (direction < 0) return ssl;
   return bsl;
}

//==================================================================
//                       RISK / POSITION SIZING
//==================================================================

double CalcLotSize(double slDistancePrice) {
   if (slDistancePrice <= 0) return 0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

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
         LogSignal("[BE] Pos " + IntegerToString((long)ticket) + " SL→BE");
      }
   }
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

   // Count today's filled trades + circuit breaker
   HistorySelect(gTodayKey, TimeCurrent());
   int total = HistoryDealsTotal();
   int filled = 0, consec = 0;
   bool breakLoop = false;
   for (int i = 0; i < total && !breakLoop; i++) {
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

//==================================================================
//                       UTILITY
//==================================================================

void ResetSetup(string reason) {
   if (gSt.stage != STAGE_IDLE) LogDebug("RESET: " + reason);
   gSt.stage         = STAGE_IDLE;
   gSt.direction     = 0;
   gSt.sweptLevel    = 0;
   gSt.sweepWickPeak = 0;
   gSt.chochSwing    = 0;
   gSt.obTop         = 0;
   gSt.obBot         = 0;
   gSt.targetLiq     = 0;
   gSt.sweepBarTime  = 0;
   gSt.chochBarTime  = 0;
}
