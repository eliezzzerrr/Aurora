//+------------------------------------------------------------------+
//|                                        CloudThicknessSurvey.mq5   |
//|                                                                   |
//|  Measures the distribution of 15M Ichimoku cloud thickness on the |
//|  attached symbol, so MinCloudPips in TrendEMA_EA can be set from  |
//|  a measured percentile instead of a guess.                        |
//|                                                                   |
//|  Attach to ANY chart of the symbol you trade (the timeframe of    |
//|  the chart does not matter - TrendTF below is what is measured).  |
//|  Output goes to the Experts tab.                                  |
//|                                                                   |
//|  Read it like this: the "blocks" column is the share of bars a    |
//|  MinCloudPips at that value would have refused to trade in. If a  |
//|  threshold blocks 60% of all bars it is not a chop filter, it is  |
//|  an off switch.                                                   |
//+------------------------------------------------------------------+
#property copyright "TrendEMA"
#property version   "1.00"
#property script_show_inputs

input ENUM_TIMEFRAMES TrendTF     = PERIOD_M15; // Must match the EA's TrendTF
input int             IchiTenkan  = 9;          // Must match the EA
input int             IchiKijun   = 26;         // Must match the EA
input int             IchiSenkou  = 52;         // Must match the EA
input int             BarsToScan  = 23000;      // 23000 x 15M is about 8 months
input double          PipSize     = 0.01;       // Gold: 1 pip = 0.01

void OnStart()
  {
   int h = iIchimoku(_Symbol, TrendTF, IchiTenkan, IchiKijun, IchiSenkou);
   if(h == INVALID_HANDLE)
     {
      Print("[SURVEY] iIchimoku failed for ", _Symbol);
      return;
     }

   //--- give the terminal a moment to build the buffers on first use
   int tries = 0;
   while(BarsCalculated(h) < BarsToScan && tries++ < 50)
      Sleep(200);

   int avail = BarsCalculated(h);
   if(avail <= 0)
     {
      Print("[SURVEY] no bars calculated - let the chart load more history and re-run");
      IndicatorRelease(h);
      return;
     }
   int n = (int)MathMin(BarsToScan, avail - 1);

   double A[], B[];
   ArraySetAsSeries(A, true);
   ArraySetAsSeries(B, true);
   if(CopyBuffer(h, 2, 1, n, A) != n || CopyBuffer(h, 3, 1, n, B) != n)
     {
      PrintFormat("[SURVEY] CopyBuffer short - only %d bars available. "
                  "Scroll the chart back to load history, then re-run.", avail);
      IndicatorRelease(h);
      return;
     }
   IndicatorRelease(h);

   double t[];
   ArrayResize(t, n);
   for(int i = 0; i < n; i++)
      t[i] = MathAbs(A[i] - B[i]) / PipSize;
   ArraySort(t);   // ascending

   datetime first = iTime(_Symbol, TrendTF, n);
   PrintFormat("[SURVEY] %s %s - %d bars from %s to now",
               _Symbol, EnumToString(TrendTF), n, TimeToString(first, TIME_DATE));

   //--- percentiles: the value below which that share of bars sits
   int pct[] = {1, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 99};
   Print("[SURVEY] --- cloud thickness distribution (pips) ---");
   for(int i = 0; i < ArraySize(pct); i++)
     {
      int idx = (int)MathFloor((pct[i] / 100.0) * (n - 1));
      PrintFormat("[SURVEY]   p%-3d = %6.0f pips", pct[i], t[idx]);
     }

   //--- and the practical question: what would each threshold cost?
   double thr[] = {50, 100, 150, 200, 250, 300, 400, 500, 700, 1000};
   Print("[SURVEY] --- what a MinCloudPips setting would block ---");
   for(int i = 0; i < ArraySize(thr); i++)
     {
      int blocked = 0;
      for(int j = 0; j < n; j++)
         if(t[j] < thr[i])
            blocked++;
      PrintFormat("[SURVEY]   MinCloudPips=%-5.0f blocks %5.1f%% of bars",
                  thr[i], 100.0 * blocked / n);
     }

   double sum = 0;
   for(int j = 0; j < n; j++)
      sum += t[j];
   PrintFormat("[SURVEY] mean %.0f pips, median %.0f pips, min %.0f, max %.0f",
               sum / n, t[n / 2], t[0], t[n - 1]);
   Print("[SURVEY] Pick a threshold that blocks a MINORITY of bars. Anything "
         "blocking more than about a third is changing the strategy, not filtering it.");
  }
//+------------------------------------------------------------------+
