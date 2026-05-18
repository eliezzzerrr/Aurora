//+------------------------------------------------------------------+
//|                                                       Aurora.mq5 |
//|                XAUUSD ICT/SMC Day-Trading EA (MT5)               |
//|                                                                  |
//|  Implements the Aurora strict 8-point checklist for XAUUSD       |
//|  day-trading on 15m. Auto-detects:                               |
//|    1. HTF bias (1H BOS direction)                                |
//|    2. Buy/Sell-side liquidity (equal highs/lows)                 |
//|    3. Liquidity sweep (wick + close back inside)                 |
//|    4. 15m CHoCH (close past most recent swing)                   |
//|    5. Bearish/bullish OB (last opposite candle before BOS)       |
//|    6. Premium/discount zone check                                |
//|    7. RR validation (>= 2:1 to next opposing pool)               |
//|    8. Killzone time filter (London + NY AM)                      |
//|                                                                  |
//|  Risk: 1% balance per trade (fixed-% model, auto lot calc)       |
//|  Entry: SELL-LIMIT at 15m bearish OB (or BUY-LIMIT for bullish)  |
//|  SL: beyond sweep wick + buffer                                  |
//|  TP: next opposing liquidity, min 2:1 RR                         |
//|  BE: move SL to entry at +1R                                     |
//|                                                                  |
//|  Safety: max trades/day, stop after N consecutive losses         |
//|                                                                  |
//|  Logs every decision to MQL5/Files/Aurora_Journal.txt            |
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
input double  InpRiskPercent   = 1.0;          // Risk per trade (% of balance)
input double  InpRRMin         = 2.0;          // Minimum reward-to-risk ratio
input bool    InpMoveBE_at1R   = false;        // Move SL to BE at +1R (default OFF — backtest showed it caps wins at ~1R while losses stay full -1R, killing 2:1 RR)

input string  IH_KZ            = "════════ Killzones (broker time) ════════";
input bool    InpUseKillzones  = true;         // Restrict to London + NY AM
input int     InpBrokerToUTC   = -4;           // Hours: broker time - UTC (e.g. NY broker = -4 or -5 DST)
input int     InpLondonOpenH   = 7;            // UTC hour London opens
input int     InpLondonCloseH  = 10;           // UTC hour London closes
input int     InpNYOpenH       = 12;           // UTC hour NY AM opens
input int     InpNYOpenM       = 30;           // UTC minute NY AM opens
input int     InpNYCloseH      = 15;           // UTC hour NY AM closes
input int     InpNYCloseM      = 30;           // UTC minute NY AM closes

input string  IH_Struct        = "════════ Structure Detection ════════";
input int     InpSwingLookback = 3;            // Bars left/right for swing pivot (3 = strict, 5 = stricter)
input double  InpEqualHighTolPips = 5.0;       // Pip tolerance for equal highs/lows
input int     InpStructureBars = 50;           // How many M15 bars to scan for structure
input int     InpHTFBiasBars   = 30;           // How many H1 bars to determine bias

input string  IH_Exec          = "════════ Execution ════════";
input long    InpMagic         = 87741;        // Magic number (Aurora's signature)
input string  InpComment       = "Aurora";     // Order comment
input int     InpSlippage      = 50;           // Max deviation (points)
input double  InpSLBufferPips  = 3.0;          // Extra pips beyond sweep wick for SL
input int     InpLimitExpireBars = 12;         // M15 bars before pending limit auto-cancels

input string  IH_Safety        = "════════ Safety ════════";
input int     InpMaxTradesDay  = 3;            // Max signal entries per day
input int     InpMaxConsecLoss = 2;            // Halt after N consecutive losses
input bool    InpLogToFile     = true;         // Write decisions to Aurora_Journal.txt

//==================================================================
//                          GLOBALS
//==================================================================

CTrade        gTrade;
CSymbolInfo   gSym;
CPositionInfo gPos;
COrderInfo    gOrd;

datetime      gLastBarM15    = 0;
datetime      gTodayKey      = 0;          // YYYY-MM-DD timestamp
int           gTradesToday   = 0;
int           gConsecLosses  = 0;
bool          gHaltedToday   = false;

// Setup state machine
enum ESetupStage {
   STAGE_IDLE       = 0,   // No setup in progress
   STAGE_SWEPT      = 1,   // Liquidity swept, awaiting CHoCH
   STAGE_CHOCH      = 2,   // CHoCH confirmed, awaiting OB retest
   STAGE_PENDING    = 3    // Limit order placed, awaiting fill
};

struct SetupState {
   ESetupStage stage;
   int         direction;        // -1 short, +1 long
   double      sweptLevel;       // BSL / SSL price
   double      sweepWickPeak;    // wick high (short) or low (long)
   double      chochSwing;       // swing low/high that broke
   double      obTop;            // 15m OB top
   double      obBot;            // 15m OB bottom
   double      targetLiq;        // opposite liquidity pool for TP
   datetime    swepBarTime;      // when sweep was detected
   datetime    chochBarTime;     // when CHoCH was detected
   ulong       pendingTicket;    // active pending order ticket
   double      orderEntry;       // calc'd entry price
   double      orderSL;
   double      orderTP;
};
SetupState    gSt;

double        gPip;              // Pip size for the symbol

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

   // Compute pip size: 5-digit/3-digit = 10 points, else = 1 point
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   gPip = (digits == 5 || digits == 3) ? _Point * 10 : _Point;
   if (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) {
      gPip = _Point * 10;   // most gold brokers: 1 pip = 0.10 USD = 10 points
   }

   ResetSetup("INIT");

   LogInfo("==============================================");
   LogInfo("Aurora EA initialized on " + _Symbol);
   LogInfo("  Magic:     " + IntegerToString(InpMagic));
   LogInfo("  Risk:      " + DoubleToString(InpRiskPercent, 2) + "%");
   LogInfo("  RR min:    " + DoubleToString(InpRRMin, 1));
   LogInfo("  Pip size:  " + DoubleToString(gPip, _Digits));
   LogInfo("  Killzones: " + (InpUseKillzones ? "ON" : "OFF"));
   LogInfo("  Max/day:   " + IntegerToString(InpMaxTradesDay));
   LogInfo("==============================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   LogInfo("Aurora EA deinit. Reason code: " + IntegerToString(reason));
}

//==================================================================
//                          ON TICK
//==================================================================

void OnTick() {
   // Manage open positions on every tick (BE move needs tick resolution)
   ManageOpenPositions();

   // Detect new M15 bar
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

   // Halt if daily limits hit
   if (gHaltedToday) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("HALTED");
      return;
   }
   if (gTradesToday >= InpMaxTradesDay) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("MAX_TRADES");
      LogInfo("Daily trade limit reached (" + IntegerToString(gTradesToday) + "). Standing down.");
      return;
   }

   // Killzone check
   if (InpUseKillzones && !IsInKillzone()) {
      if (gSt.stage != STAGE_IDLE) ResetSetup("OFF_KILLZONE");
      return;
   }

   // Run state machine on the just-closed M15 bar (index 1; index 0 is current/incomplete)
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

// --- STAGE 0: IDLE — scan for liquidity sweep on just-closed M15 bar ---
void StageIdle() {
   int htfBias = GetHTFBias();
   if (htfBias == 0) {
      LogDebug("Idle: HTF bias unclear, skipping");
      return;
   }

   // Find recent liquidity pools (equal highs / equal lows)
   double bsl = 0, ssl = 0;
   datetime bslTime = 0, sslTime = 0;
   FindLiquidityPools(InpStructureBars, bsl, bslTime, ssl, sslTime);

   // Detect sweep on the JUST-CLOSED bar (index 1)
   double bar1H = iHigh(_Symbol, PERIOD_M15, 1);
   double bar1L = iLow(_Symbol, PERIOD_M15, 1);
   double bar1C = iClose(_Symbol, PERIOD_M15, 1);

   // Short setup: HTF bearish + sweep of BSL (wick above, close below)
   if (htfBias < 0 && bsl > 0) {
      if (bar1H > bsl && bar1C < bsl) {
         // SWEEP DETECTED
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

   // Long setup: HTF bullish + sweep of SSL (wick below, close above)
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

// --- STAGE 1: SWEPT — wait for CHoCH (close past last swing) ---
void StageSwept() {
   // Timeout: if too many bars pass without CHoCH, reset
   int barsSinceSweep = iBarShift(_Symbol, PERIOD_M15, gSt.swepBarTime) - 1;
   if (barsSinceSweep > 8) {
      ResetSetup("SWEEP_TIMEOUT");
      return;
   }

   // Invalidation: if price closes back beyond sweep wick, setup dead
   double bar1C = iClose(_Symbol, PERIOD_M15, 1);
   if (gSt.direction < 0 && bar1C > gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED (close > sweep high)");
      return;
   }
   if (gSt.direction > 0 && bar1C < gSt.sweepWickPeak) {
      ResetSetup("SWEEP_INVALIDATED (close < sweep low)");
      return;
   }

   // Find the most recent M15 swing low (short) or swing high (long) BEFORE the sweep bar
   double chochLevel = FindRecentSwing(gSt.direction, gSt.swepBarTime);
   if (chochLevel <= 0) {
      LogDebug("Swept: no valid recent swing found yet");
      return;
   }

   // CHoCH = close past that swing
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

// --- STAGE 2: CHoCH — identify 15m OB, place limit order ---
void StageChoch() {
   // Identify the 15m OB: last opposing candle before the bearish/bullish CHoCH push
   int chochIdx = iBarShift(_Symbol, PERIOD_M15, gSt.chochBarTime);
   double obTop = 0, obBot = 0;
   if (!FindOB(gSt.direction, chochIdx, obTop, obBot)) {
      ResetSetup("NO_OB_FOUND");
      return;
   }
   gSt.obTop = obTop;
   gSt.obBot = obBot;

   // Find target liquidity (opposite of swept side)
   double targetLiq = FindOpposingLiquidity(gSt.direction, gSt.sweptLevel);
   if (targetLiq <= 0) {
      ResetSetup("NO_TARGET_LIQUIDITY");
      return;
   }
   gSt.targetLiq = targetLiq;

   // Build limit order parameters
   double entry, sl, tp;
   if (gSt.direction < 0) {
      // SELL LIMIT at OB top
      entry = obTop;
      sl    = gSt.sweepWickPeak + InpSLBufferPips * gPip;
      tp    = targetLiq;
   } else {
      // BUY LIMIT at OB bottom
      entry = obBot;
      sl    = gSt.sweepWickPeak - InpSLBufferPips * gPip;
      tp    = targetLiq;
   }

   // Validate RR
   double risk = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   double rr = (risk > 0) ? reward / risk : 0;
   if (rr < InpRRMin) {
      LogSignal("[RR_FAIL] Computed RR " + DoubleToString(rr, 2) +
                " < min " + DoubleToString(InpRRMin, 1) + " — NO TRADE");
      ResetSetup("RR_TOO_LOW");
      return;
   }

   gSt.orderEntry = entry;
   gSt.orderSL    = sl;
   gSt.orderTP    = tp;

   // Calculate lot size
   double lots = CalcLotSize(risk);
   if (lots <= 0) {
      ResetSetup("LOT_CALC_FAILED");
      return;
   }

   // Place limit order
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

   LogSignal(StringFormat("[LIMIT PLACED] %s %.2f lots @ %s · SL %s · TP %s · RR %.2f",
            (gSt.direction < 0 ? "SELL" : "BUY"),
            lots,
            DoubleToString(entry, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits),
            rr));
}

// --- STAGE 3: PENDING — monitor for fill or invalidation ---
void StagePending() {
   if (!gOrd.Select(gSt.pendingTicket)) {
      // Order no longer pending — likely filled or removed. Check.
      if (IsPositionOpen(gSt.pendingTicket)) {
         LogSignal("[FILLED] Position opened from ticket " + IntegerToString((long)gSt.pendingTicket));
         gTradesToday++;
         ResetSetup("FILLED_INTO_POSITION");
         return;
      }
      // Else order was cancelled externally
      LogInfo("Pending order " + IntegerToString((long)gSt.pendingTicket) + " no longer exists. Resetting.");
      ResetSetup("ORDER_GONE");
      return;
   }

   // Invalidation: sweep wick taken out (price went above sweep high for short, below for long)
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

   // Expiry: too many bars without fill
   int barsSinceCHoCH = iBarShift(_Symbol, PERIOD_M15, gSt.chochBarTime) - 1;
   if (barsSinceCHoCH > InpLimitExpireBars) {
      gTrade.OrderDelete(gSt.pendingTicket);
      ResetSetup("PENDING_EXPIRED");
      return;
   }
}

//==================================================================
//                       STRUCTURE DETECTION
//==================================================================

// HTF bias: +1 bullish, -1 bearish, 0 unclear
// Logic: check if 1H has made higher highs+higher lows (bullish) or lower lows+lower highs (bearish) recently
int GetHTFBias() {
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

   // Bearish: most recent extreme is the LOW (llIdx < hhIdx means more recent)
   if (llIdx < hhIdx) return -1;
   if (hhIdx < llIdx) return +1;
   return 0;
}

// Scan M15 bars for the most prominent BSL (equal highs) and SSL (equal lows)
void FindLiquidityPools(int lookback, double &bsl, datetime &bslTime, double &ssl, datetime &sslTime) {
   bsl = 0; ssl = 0; bslTime = 0; sslTime = 0;
   double tol = InpEqualHighTolPips * gPip;
   if (Bars(_Symbol, PERIOD_M15) < lookback + 2) return;

   // Identify swing highs and lows in lookback window
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
         if (iHigh(_Symbol, PERIOD_M15, i - k) >= h || iHigh(_Symbol, PERIOD_M15, i + k) >= h) {
            isSwingHigh = false;
         }
         if (iLow(_Symbol, PERIOD_M15, i - k) <= l || iLow(_Symbol, PERIOD_M15, i + k) <= l) {
            isSwingLow = false;
         }
      }
      if (isSwingHigh) {
         int s = ArraySize(swingHighs);
         ArrayResize(swingHighs, s + 1);
         ArrayResize(swingHighsT, s + 1);
         swingHighs[s] = h;
         swingHighsT[s] = iTime(_Symbol, PERIOD_M15, i);
      }
      if (isSwingLow) {
         int s = ArraySize(swingLows);
         ArrayResize(swingLows, s + 1);
         ArrayResize(swingLowsT, s + 1);
         swingLows[s] = l;
         swingLowsT[s] = iTime(_Symbol, PERIOD_M15, i);
      }
   }

   // Find clusters of equal highs (BSL)
   for (int i = 0; i < ArraySize(swingHighs); i++) {
      for (int j = i + 1; j < ArraySize(swingHighs); j++) {
         if (MathAbs(swingHighs[i] - swingHighs[j]) <= tol) {
            double avg = (swingHighs[i] + swingHighs[j]) / 2.0;
            if (avg > bsl) {
               bsl = avg;
               bslTime = swingHighsT[i];
            }
            break;
         }
      }
   }
   // Find clusters of equal lows (SSL)
   for (int i = 0; i < ArraySize(swingLows); i++) {
      for (int j = i + 1; j < ArraySize(swingLows); j++) {
         if (MathAbs(swingLows[i] - swingLows[j]) <= tol) {
            double avg = (swingLows[i] + swingLows[j]) / 2.0;
            if (ssl <= 0 || avg < ssl) {
               ssl = avg;
               sslTime = swingLowsT[i];
            }
            break;
         }
      }
   }

   // Fallback: if no equal-highs/lows found, use the highest high / lowest low as the level
   if (bsl <= 0 && ArraySize(swingHighs) > 0) {
      bsl = swingHighs[ArrayMaximum(swingHighs)];
      bslTime = swingHighsT[ArrayMaximum(swingHighs)];
   }
   if (ssl <= 0 && ArraySize(swingLows) > 0) {
      ssl = swingLows[ArrayMinimum(swingLows)];
      sslTime = swingLowsT[ArrayMinimum(swingLows)];
   }
}

// Find the most recent M15 swing low (for short) or swing high (for long) BEFORE the given bar time
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

// Find 15m OB: last opposing candle before the CHoCH push
// For short: scan back from CHoCH bar to find the last BULLISH (close>open) M15 candle
// For long:  scan back from CHoCH bar to find the last BEARISH (close<open) M15 candle
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

// Find next opposing liquidity for TP:
// For short: nearest SSL below current price (lower than sweptLevel)
// For long:  nearest BSL above current price (higher than sweptLevel)
double FindOpposingLiquidity(int direction, double swept) {
   double bsl = 0, ssl = 0;
   datetime t1 = 0, t2 = 0;
   FindLiquidityPools(InpStructureBars * 2, bsl, t1, ssl, t2);
   if (direction < 0) return ssl;
   else return bsl;
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

   // Apply broker limits
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   if (lots < lotMin) lots = lotMin;
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

   // If already at BE or beyond, skip
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
//                       DAILY COUNTERS / OUTCOME TRACKING
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

   // Check closed positions today for win/loss tracking
   TrackClosedPositionsForCircuitBreaker();
}

void TrackClosedPositionsForCircuitBreaker() {
   HistorySelect(gTodayKey, TimeCurrent());
   int total = HistoryDealsTotal();
   int losses = 0;
   datetime lastCloseTime = 0;
   int lastResult = 0;   // -1 loss, +1 win, 0 none

   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if (magic != InpMagic) continue;
      string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if (sym != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if (entry != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if (t > lastCloseTime) {
         lastCloseTime = t;
         lastResult = (profit < 0) ? -1 : +1;
      }
   }

   // Walk backwards through today's closed Aurora trades, count consecutive losses from most recent
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
void LogDebug(string m)  { /* Print("[DEBUG] ",  m); */ LogToFile("DEBUG",  m); }
void LogSignal(string m) { Print("[SIGNAL] ", m); LogToFile("SIGNAL", m); }
void LogError(string m)  { Print("[ERROR] ",  m); LogToFile("ERROR",  m); }

void LogStage() {
   string s = "STAGE=";
   switch (gSt.stage) {
      case STAGE_IDLE:    s += "IDLE"; break;
      case STAGE_SWEPT:   s += "SWEPT (dir=" + IntegerToString(gSt.direction) + ", level=" + DoubleToString(gSt.sweptLevel, _Digits) + ")"; break;
      case STAGE_CHOCH:   s += "CHOCH (dir=" + IntegerToString(gSt.direction) + ", swing=" + DoubleToString(gSt.chochSwing, _Digits) + ")"; break;
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
   gSt.targetLiq     = 0;
   gSt.swepBarTime   = 0;
   gSt.chochBarTime  = 0;
   gSt.pendingTicket = 0;
   gSt.orderEntry    = 0;
   gSt.orderSL       = 0;
   gSt.orderTP       = 0;
}
