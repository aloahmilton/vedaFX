//+------------------------------------------------------------------+
//| VedaFX v1.0                                          |
//| Demo-first SMC + Trend + Confirmation Expert Advisor             |
//| No martingale, grid, averaging down, or guaranteed-profit claims. |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Demo-first Forex EA: H4 trend, H1 structure proxy, M15 liquidity sweep confirmation."

#include <Trade/Trade.mqh>
CTrade trade;

input ulong  InpMagic                 = 26112201;
input double InpRiskPercent           = 0.25;
input double InpDailyLossLimitPercent = 1.00;
input double InpRewardRisk            = 2.00;
input double InpATRMultiplier         = 1.50;
input int    InpMaxSpreadPoints       = 25;
input int    InpMaxTradesPerDay       = 2;
input int    InpStructureLookback     = 12;
input int    InpLiquidityLookback     = 10;
input int    InpRSIPeriod             = 14;
input double InpBuyRSIMin             = 52.0;
input double InpSellRSIMax            = 48.0;
input bool   InpAllowLiveTrading      = false; // Safety lock: keep false in v1.
input bool   InpRequireDemoAccount    = true;
input int    InpSlippagePoints        = 10;

int hEma50H4 = INVALID_HANDLE;
int hEma200H4 = INVALID_HANDLE;
int hAtrM15 = INVALID_HANDLE;
int hRsiM15 = INVALID_HANDLE;
datetime lastM15Bar = 0;
string pauseFile = "VEDAFX_PAUSE.txt";
string dailyKey = "";

enum TrendDirection { TREND_NONE=0, TREND_BULL=1, TREND_BEAR=-1 };

int OnInit()
{
   if(_Period != PERIOD_M15)
      Print("Attach VedaFX to an M15 chart. Current timeframe is not M15.");

   hEma50H4 = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEma200H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   hAtrM15 = iATR(_Symbol, PERIOD_M15, 14);
   hRsiM15 = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);

   if(hEma50H4==INVALID_HANDLE || hEma200H4==INVALID_HANDLE ||
      hAtrM15==INVALID_HANDLE || hRsiM15==INVALID_HANDLE)
   {
      Print("Indicator initialization failed. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   dailyKey = StringFormat("VEDAFX_%I64u_%s_%04d%02d%02d",
                           InpMagic, _Symbol, dt.year, dt.mon, dt.day);
   Print("VedaFX v1.0 initialized. Demo-only safety is active.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hEma50H4!=INVALID_HANDLE) IndicatorRelease(hEma50H4);
   if(hEma200H4!=INVALID_HANDLE) IndicatorRelease(hEma200H4);
   if(hAtrM15!=INVALID_HANDLE) IndicatorRelease(hAtrM15);
   if(hRsiM15!=INVALID_HANDLE) IndicatorRelease(hRsiM15);
}

void OnTick()
{
   if(!IsNewM15Bar()) return;
   if(!SafetyChecks()) return;
   if(IsPaused()) { Print("New entries paused by control file."); return; }
   if(HasOurPosition()) return;
   if(GetTradesToday() >= InpMaxTradesPerDay) return;
   if(!DailyLossWithinLimit()) { Print("Daily loss limit reached. No new trades."); return; }

   TrendDirection trend = GetH4Trend();
   if(trend == TREND_NONE) return;

   bool structureBull=false, structureBear=false;
   if(!GetH1Structure(structureBull, structureBear)) return;

   double atr=0.0, rsi=0.0;
   if(!GetBufferValue(hAtrM15, 0, 1, atr) || !GetBufferValue(hRsiM15, 0, 1, rsi))
      return;
   if(atr <= 0) return;

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, InpLiquidityLookback+3, m15) < InpLiquidityLookback+3)
      return;

   // Signal candle is the last fully closed candle: m15[1].
   double priorLow = DBL_MAX, priorHigh = -DBL_MAX;
   for(int i=2; i<2+InpLiquidityLookback; i++)
   {
      priorLow = MathMin(priorLow, m15[i].low);
      priorHigh = MathMax(priorHigh, m15[i].high);
   }

   bool bullishCandle = (m15[1].close > m15[1].open);
   bool bearishCandle = (m15[1].close < m15[1].open);
   bool buySweep = (m15[1].low < priorLow && m15[1].close > priorLow);
   bool sellSweep = (m15[1].high > priorHigh && m15[1].close < priorHigh);

   if(trend==TREND_BULL && structureBull && buySweep && bullishCandle && rsi>=InpBuyRSIMin)
      OpenTrade(ORDER_TYPE_BUY, atr);
   else if(trend==TREND_BEAR && structureBear && sellSweep && bearishCandle && rsi<=InpSellRSIMax)
      OpenTrade(ORDER_TYPE_SELL, atr);
}

bool IsNewM15Bar()
{
   datetime t=iTime(_Symbol, PERIOD_M15, 0);
   if(t==0 || t==lastM15Bar) return false;
   lastM15Bar=t;
   return true;
}

bool SafetyChecks()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;

   if(InpRequireDemoAccount)
   {
      ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
      if(mode != ACCOUNT_TRADE_MODE_DEMO)
      {
         Print("Safety lock: this build only trades DEMO accounts.");
         return false;
      }
   }
   if(!InpAllowLiveTrading && (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask<=0 || tick.bid<=0) return false;
   double spreadPts=(tick.ask-tick.bid)/_Point;
   if(spreadPts > InpMaxSpreadPoints) return false;
   return true;
}

bool IsPaused()
{
   if(!FileIsExist(pauseFile, FILE_COMMON)) return false;
   int fh=FileOpen(pauseFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh==INVALID_HANDLE) return true; // Fail closed if pause file exists but cannot be read.
   string value=FileReadString(fh);
   FileClose(fh);
   StringToUpper(value);
   return (value=="PAUSE");
}

TrendDirection GetH4Trend()
{
   double e50=0,e200=0;
   if(!GetBufferValue(hEma50H4,0,1,e50) || !GetBufferValue(hEma200H4,0,1,e200))
      return TREND_NONE;
   double close=iClose(_Symbol,PERIOD_H4,1);
   if(close>e50 && e50>e200) return TREND_BULL;
   if(close<e50 && e50<e200) return TREND_BEAR;
   return TREND_NONE;
}

bool GetH1Structure(bool &bull, bool &bear)
{
   bull=false; bear=false;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   int need=InpStructureLookback+3;
   if(CopyRates(_Symbol,PERIOD_H1,0,need,r)<need) return false;
   double priorHigh=-DBL_MAX, priorLow=DBL_MAX;
   // Exclude latest closed candle r[1] from the reference range.
   for(int i=2;i<2+InpStructureLookback;i++)
   {
      priorHigh=MathMax(priorHigh,r[i].high);
      priorLow=MathMin(priorLow,r[i].low);
   }
   bull=(r[1].close>priorHigh);
   bear=(r[1].close<priorLow);
   return true;
}

bool GetBufferValue(int handle,int buffer,int shift,double &value)
{
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(handle,buffer,shift,1,a)!=1) return false;
   value=a[0];
   return true;
}

bool HasOurPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic)
         return true;
   }
   return false;
}

int GetTradesToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime start=StructToTime(dt);
   if(!HistorySelect(start,TimeTradeServer())) return 0;
   int count=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         count++;
   }
   return count;
}

bool DailyLossWithinLimit()
{
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(),dt);
   string key=StringFormat("VEDAFX_DAYSTART_%I64u_%s_%04d%02d%02d",
                           InpMagic,_Symbol,dt.year,dt.mon,dt.day);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key,equity);
   double baseline=GlobalVariableGet(key);
   if(baseline<=0) return false;
   double dd=(baseline-equity)/baseline*100.0;
   return (dd < InpDailyLossLimitPercent);
}

double NormalizeVolume(double volume)
{
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) return 0;
   volume=MathFloor(volume/step)*step;
   if(volume<vmin) return 0; // Never round up beyond risk budget.
   return MathMin(volume,vmax);
}

void OpenTrade(ENUM_ORDER_TYPE type,double atr)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double entry=(type==ORDER_TYPE_BUY ? tick.ask : tick.bid);
   double distance=atr*InpATRMultiplier;
   int stops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   distance=MathMax(distance,(stops+2)*_Point);

   double sl=(type==ORDER_TYPE_BUY ? entry-distance : entry+distance);
   double tp=(type==ORDER_TYPE_BUY ? entry+distance*InpRewardRisk : entry-distance*InpRewardRisk);
   sl=NormalizeDouble(sl,_Digits);
   tp=NormalizeDouble(tp,_Digits);

   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0;
   double oneLotProfit=0;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,oneLotProfit)) return;
   double oneLotLoss=MathAbs(oneLotProfit);
   if(oneLotLoss<=0 || riskMoney<=0) return;

   double volume=NormalizeVolume(riskMoney/oneLotLoss);
   if(volume<=0)
   {
      Print("Trade rejected: broker minimum volume exceeds risk budget.");
      return;
   }

   double estimatedLoss=0;
   if(!OrderCalcProfit(type,_Symbol,volume,entry,sl,estimatedLoss)) return;
   if(MathAbs(estimatedLoss)>riskMoney*1.02)
   {
      Print("Trade rejected: calculated risk exceeds allowed budget.");
      return;
   }

   bool ok=false;
   if(type==ORDER_TYPE_BUY)
      ok=trade.Buy(volume,_Symbol,0,sl,tp,"VedaFX BUY");
   else
      ok=trade.Sell(volume,_Symbol,0,sl,tp,"VedaFX SELL");

   if(!ok)
      Print("Order failed. Retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   else
      Print("Order placed: ",(type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " volume=",DoubleToString(volume,2),
            " SL=",DoubleToString(sl,_Digits)," TP=",DoubleToString(tp,_Digits));
}
