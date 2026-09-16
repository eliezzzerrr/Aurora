//+------------------------------------------------------------------+
//|                                             TripleEMA_Lines.mq5   |
//|        Companion indicator for TripleEMA_Trend: the 9/21/50 EMAs   |
//|        in the colours the operator uses - yellow / red / blue.     |
//|                                                                   |
//|  The EA adds this to its chart with ChartIndicatorAdd, but ONLY    |
//|  when the chart timeframe equals the EA's EntryTF. A built-in iMA  |
//|  handle cannot be recoloured from an EA, which is the whole reason |
//|  this file exists. Install to MQL5\Indicators\.                     |
//+------------------------------------------------------------------+
#property copyright "Aurora TripleEMA Trend EA"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_width1  2
#property indicator_label1  "EMA fast"

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label2  "EMA mid"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  2
#property indicator_label3  "EMA slow"

input int FastPeriod = 9;    // Fast EMA (yellow)
input int MidPeriod  = 21;   // Middle EMA (red)
input int SlowPeriod = 50;   // Slow EMA (blue)

double bF[], bM[], bS[];
int    hF = INVALID_HANDLE, hM = INVALID_HANDLE, hS = INVALID_HANDLE;

int OnInit()
  {
   SetIndexBuffer(0, bF, INDICATOR_DATA);
   SetIndexBuffer(1, bM, INDICATOR_DATA);
   SetIndexBuffer(2, bS, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, FastPeriod);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, MidPeriod);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, SlowPeriod);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   hF = iMA(_Symbol, _Period, FastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hM = iMA(_Symbol, _Period, MidPeriod,  0, MODE_EMA, PRICE_CLOSE);
   hS = iMA(_Symbol, _Period, SlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hF == INVALID_HANDLE || hM == INVALID_HANDLE || hS == INVALID_HANDLE)
      return(INIT_FAILED);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("TripleEMA Lines(%d,%d,%d)", FastPeriod, MidPeriod, SlowPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hF != INVALID_HANDLE) IndicatorRelease(hF);
   if(hM != INVALID_HANDLE) IndicatorRelease(hM);
   if(hS != INVALID_HANDLE) IndicatorRelease(hS);
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   //--- standard incremental copy: on the first pass take everything, afterwards
   //    only the newest bar plus the one before it (which may still be forming)
   int toCopy;
   if(prev_calculated > rates_total || prev_calculated <= 0) toCopy = rates_total;
   else { toCopy = rates_total - prev_calculated; if(prev_calculated > 0) toCopy++; }

   if(BarsCalculated(hF) < rates_total || BarsCalculated(hM) < rates_total || BarsCalculated(hS) < rates_total)
      return(0);   // ask to be called again once the MAs have caught up
   if(CopyBuffer(hF, 0, 0, toCopy, bF) <= 0) return(0);
   if(CopyBuffer(hM, 0, 0, toCopy, bM) <= 0) return(0);
   if(CopyBuffer(hS, 0, 0, toCopy, bS) <= 0) return(0);
   return(rates_total);
  }
//+------------------------------------------------------------------+
