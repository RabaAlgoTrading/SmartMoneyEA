#property copyright "Copyright 2023, Aleix Rabassa"

// libs.
#include <Raba_Includes\Raba_Enums.mqh>

/**
 * EXPERT INPUTS
 */
sinput group "### SMART MONEY PARAMS ###"
input bool InpEnableStrategyExec = true;
input bool InpEnableGraphDrawings = true;
bool InpDrawOrderblocks = false;
bool InpDrawMACDTrend = false;
bool InpHideIndicators = true;

input bool InpOBCandleMustBeOpposite = true;            // OB candle must be opposite to its next
input int InpStratParamsMultiplier = 1;                 // Strategy parameters multiplier
input int InpMinOBSize = 30;                            // Min. OB size
input int InpMinOBBodySize = 0;                         // Min. OB body size
input int InpMinPriceVoid = 20;                         // Min. price void
input bool InpFuseOrderBlocksEnabled = true;            // Enable order block fusion
input int InpDistanceToFuse = 50;                       // Max. distanse to fuse order blocks
input int InpSLMargin = 0;                              // SL margin
input int InpEntryMargin = 0;                           // Entry margin
input int InpTPMargin = 0;                              // TP margin

input eSLMethod InpSlMethod = SLFixedPercentage;        // SL method
input double InpSLValue = 1;                            // Stop loss value
input eTPMethod InpTPMethod = TPFixedRR;                // TP method
input double InpTPValue = 0;                            // TP value (0 Disabled)

input bool InpAvoidConsolidations = true;               // Avoid consolidations
input ENUM_MA_METHOD InpConsMAMode = MODE_EMA;          // Consolidation MA mode
input int InpConsMAPeriod = 365;                        // Consolidation MA period
input eTrendMethod InpTrendMethod = MACDHighLowsMethod; // Trend definition method
bool InpEnableBOSCheckout = true;                       // Enable BOS checkout
input ENUM_MA_METHOD InpMAMode = MODE_EMA;              // Trend MA mode
input int InpMAPeriod = 365;                            // Trend MA period
int InpMACDFastPeriod = 12;                             // MACD fast period
int InpMACDSlowPeriod = 26;                             // MACD slow period
int InpMACDSignalSmothing = 9;                          // MACD signal period
input int InpMACDFastMultiplier = 20;                   // Fast MACD(12,26,9) multiplier
input bool InpUseMACDSlowTrend = false;                 // Use MACD slow trend
input int InpMACDSlowMultiplier = 20;                   // Slow MACD(12,26,9) multiplier

input double InpMaxSimultaneousRisk = 1;                // Max. simultaneous risk (%)
input int InpMaxSpread = 10;                            // Max. spread allowed (0 Disabled)

// Raba libs.
#include <Raba_Includes\Raba_ScheduleManagement.mqh>
#include <Raba_Includes\Raba_RiskManagement.mqh>
#include <Raba_Includes\Raba_PositionManagement.mqh>
#include <Raba_Includes\Raba_EAManagement.mqh>

/**
 * DATA STRUCTURES
 */
class COBRectangle
{
    public:
        datetime openTime;
        datetime timeStart;
        datetime timeEnd;
        double priceLow;
        double priceHigh;
        bool active;
        eOBType type;
        int id;
        ENUM_TIMEFRAMES timeFrame;
        void COBRectangle();  
};

class CSmartMoneyStrat
{
   public:
      void Exec();
      bool Init(ulong pExpertMagic, string pSymbol, ENUM_TIMEFRAMES &pTimeFrameArr[]);
      void CSmartMoneyStrat();
      
   private:
   
      // Private libs.
      CPositionInfo pos;
      CTrade trade;
      CBar bar;
      CPositionManagement pm;
      CScheduleManagement sch;
      CStats stats;
      
      // Private variables.
      COBRectangle obList[20];  // Must keep all active simultaneous OBs.
      ulong ExpertMagic;
      string ExpertSymbol;
      ENUM_TIMEFRAMES TimeFrameArr[];
      int currTrend;   // 1 Bullish, 0 consolidating, -1 bearish
      int TrendMA_handle;
      int ConsMA_handle;
      int OBCounter;
      
      // MACD (0 low tf, 1 high tf).
      int MACD0_handle;
      int MACD1_handle;
      double MACD0_HighLowArr[3];
      double MACD0_BOSpoint;
      double MACD1_HighLowArr[3];
      double MACD1_BOSpoint;
      bool currMACD1Trend; // 1 Bullish, 0 Bearish
      
      // Private methods.
      void InitOrderBlocks(int pFromBar);
      void InitOB_CheckMitigated(int pBar);
      void RefreshOBList(int pCurrentBar = 0);
      bool FuseIfOverlapping(int indexOB, ENUM_TIMEFRAMES pCurrentTimeFrame);
      void DrawOrderBlocks();
      bool CheckParams();
      void Add(COBRectangle &newOB);
      bool IsOrderBlock(int pIndexOB);
      void TrendUpdate();      
      int MovingAverageTrend();
      int StrongTrend();      
      ulong Buy(COBRectangle &pOB);
      ulong Sell(COBRectangle &pOB);
      double CalcTakeProfit(eOBType pType, double pSlDistance = 0);
      void DrawData(); 
      bool CheckConsolidation();
      
      // MACD (0 low tf, 1 high tf).
      int MACD_LowsHighsTrend(int pMACD);
      bool MACD_Crossover(int pMACD);
      bool MACD_BOSCheck(int pMACD);
      void MACD_UpdateBOSpoint(int pMACD, bool pTrend);
      void MACD_DrawTrend(string pName, datetime ptimeStart, double ppriceLow, datetime ptimeEnd, double ppriceHigh);
      void MACD_DrawBOS(string pName, double pPrice, color clr);
      void MACD_DrawLine(int pIndex, string pName, color pColor);
};
 
/**
 * CSmartMoneyStrat METHODS
 */
CSmartMoneyStrat::CSmartMoneyStrat(void) {}

bool CSmartMoneyStrat::Init(ulong pExpertMagic, string pSymbol, ENUM_TIMEFRAMES &pTimeFrameArr[])
{
    if (!InpEnableStrategyExec) return false;
    
    // Set inputs.
    ExpertMagic = pExpertMagic;
    ExpertSymbol = pSymbol;
    ArrayResize(TimeFrameArr, pTimeFrameArr.Size());
    ArrayCopy(TimeFrameArr, pTimeFrameArr);
    OBCounter = 1;
    
    // Enable graph drawings.
    if (InpEnableGraphDrawings) {
        InpDrawOrderblocks = true;
        InpDrawMACDTrend = true;
        InpHideIndicators = true;
    }

    // Schedule init.
    sch.Init(pExpertMagic, pSymbol);
    
    // Indicators init.
    TesterHideIndicators(InpHideIndicators);
    if (InpTrendMethod == MovingAverageMethod) {
        TrendMA_handle = iMA(ExpertSymbol, TimeFrameArr[0], InpMAPeriod, 0, InpMAMode, PRICE_CLOSE);   
    } else if (InpTrendMethod == MACDHighLowsMethod) {
        MACD0_handle = iMACD(ExpertSymbol, TimeFrameArr[0], InpMACDFastPeriod * InpMACDFastMultiplier, InpMACDSlowPeriod * InpMACDFastMultiplier
                                    , InpMACDSignalSmothing * InpMACDFastMultiplier, PRICE_CLOSE);
        MACD1_handle = iMACD(ExpertSymbol, TimeFrameArr[0], InpMACDFastPeriod * InpMACDSlowMultiplier, InpMACDSlowPeriod * InpMACDSlowMultiplier
                                    , InpMACDSignalSmothing * InpMACDSlowMultiplier, PRICE_CLOSE);
    }
    if (InpAvoidConsolidations) {
        ConsMA_handle = iMA(ExpertSymbol, TimeFrameArr[0], InpConsMAPeriod, 0, InpConsMAMode, PRICE_CLOSE); 
    }

    // Scan last X bars.
    InitOrderBlocks(200);

    // Check OBs params.
    if (!CheckParams()) {
        ErrorLog("OBs input params are wrong.");
        return false;
    }
    
    DrawData();    
    return true;
}

void CSmartMoneyStrat::Exec()
{
    if (!InpEnableStrategyExec) return;
    
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    bool inSpread = SymbolInfoInteger(ExpertSymbol, SYMBOL_SPREAD) <= InpMaxSpread || InpMaxSpread == 0;
    bool inTrend;
    
    // Schedule.
    sch.Exec();
    bool inTime = sch.GetLastInTime();
    
    // Loop orderblocks and opens position if price mitigates any.
    for (uint i = 0; i <= obList.Size() - 1; i++) {
    
        // Case Sell2Buy
        if (obList[i].active && obList[i].type == sell2buy && priceBid - (InpEntryMargin * _Point) <= obList[i].priceHigh) {
            
            inTrend = currTrend == 1 || (currMACD1Trend && InpUseMACDSlowTrend) || InpTrendMethod == DisabledTrend;
            
            // Buy if time, spread and trend (bullish) are ok.
            if (inTime && inSpread && inTrend) {
               if (Buy(obList[i]) < 0) ErrorAlert("Error on Buy() execution. Description: " + ErrorDescription(GetLastError()));
            }
            obList[i].active = false;
        
        // Case Buy2Sell
        } else if (obList[i].active && obList[i].type == buy2sell && priceAsk + (InpEntryMargin * _Point) >= obList[i].priceLow) {
            
            inTrend = currTrend == -1 || (!currMACD1Trend && InpUseMACDSlowTrend) || InpTrendMethod == DisabledTrend;
            
            // Sell if time, spread and trend (bearish) are ok.
            if (inTime && inSpread && inTrend) {
               if (Sell(obList[i]) < 0) ErrorAlert("Error on Sell() execution. Description: " + ErrorDescription(GetLastError()));
            }
            obList[i].active = false;            
        }
    }
    
    // New candle processes.
    if (NewCandle(TimeFrameArr)) {        
        RefreshOBList();
        TrendUpdate();
        CheckConsolidation();
        DrawOrderBlocks();
        stats.UpdateStats(sch.TradingDaysInTheWeek());
    }
    
    // Check for BOS. Placed here because it needs to be checked every tick.
    if (InpTrendMethod == MACDHighLowsMethod && InpEnableBOSCheckout) {
        currTrend = MACD_BOSCheck(0);
        if (InpUseMACDSlowTrend) currMACD1Trend = MACD_BOSCheck(1);
    }
    DrawData();
}

bool CSmartMoneyStrat::CheckConsolidation() 
{
    if (!InpAvoidConsolidations) return false;
    
    //ConsMA_handle
    
    return false;    
}

// Return true if trend is bullish, false if bearish.
void CSmartMoneyStrat::TrendUpdate() 
{
    if (InpTrendMethod == DisabledTrend) {
        // skip.
    } else if (InpTrendMethod == MovingAverageMethod) {
        currTrend = MovingAverageTrend();
    } else if (InpTrendMethod == MACDHighLowsMethod) {

        // Check trend for every new crossover (MACD 0).
        if (MACD_Crossover(0) || currTrend == NULL) {
            currTrend = MACD_LowsHighsTrend(0);
        }  
        
        // Check trend for every new crossover (MACD 1).
        if (InpUseMACDSlowTrend) {
            if (MACD_Crossover(1) || currMACD1Trend == NULL) {
                currMACD1Trend = MACD_LowsHighsTrend(1);
            }  
        }
    } else if (InpTrendMethod == StrongTrendMethod) {
        currTrend = StrongTrend();
    }
    
    // Set currTrend to 0 if it is consolidating.
    if (InpAvoidConsolidations && CheckConsolidation()) {
        currTrend = 0;
    }
}

int CSmartMoneyStrat::MovingAverageTrend() 
{
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);

    double MAarr[];
    ArraySetAsSeries(MAarr, true); 
    CopyBuffer(TrendMA_handle, MAIN_LINE, 0, 1, MAarr);
    
    if (fmin(priceAsk, priceBid) >= MAarr[0]) {
        return 1;       // bullish.
    } else {
        return -1;      // bearish.
    }
}

bool CSmartMoneyStrat::MACD_Crossover(int pMACD) 
{
    double macdMain[], macdSignal[];
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    
    if (pMACD == 0) {
        CopyBuffer(MACD0_handle, MAIN_LINE, 0, 4, macdMain);
        CopyBuffer(MACD0_handle, SIGNAL_LINE, 0, 4, macdSignal);
    } else {
        CopyBuffer(MACD1_handle, MAIN_LINE, 0, 4, macdMain);
        CopyBuffer(MACD1_handle, SIGNAL_LINE, 0, 4, macdSignal);
    }
    
    // Case equal.
    int iSum = 1;
    if (macdMain[1] == macdSignal[1]) {
        iSum = 2;
        if (macdMain[2] == macdSignal[2]) {
            iSum = 3;
        }
    }
    
    // Check crossover.
    if ((macdMain[0] > macdSignal[0] && macdMain[iSum] < macdSignal[iSum])
            || (macdMain[0] < macdSignal[0] && macdMain[iSum] > macdSignal[iSum])) {
        return true;        
    }
    return false;
}

int CSmartMoneyStrat::MACD_LowsHighsTrend(int pMACD) 
{
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID); 
    bool lastIsHigh;   
    int index0, index1, index2;
    int iSum;
    int crossMargin = 0;    // Not working for >0.
    int macdSize = 500 * InpMACDSlowMultiplier;
    int macdCross0 = -1, macdCross1 = -1, macdCross2 = -1, macdCross3 = -1;
    double macdMain[], macdSignal[];
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    if (pMACD == 0) {
        CopyBuffer(MACD0_handle, MAIN_LINE, 0, macdSize, macdMain);
        CopyBuffer(MACD0_handle, SIGNAL_LINE, 0, macdSize, macdSignal);
    } else {
        CopyBuffer(MACD1_handle, MAIN_LINE, 0, macdSize, macdMain);
        CopyBuffer(MACD1_handle, SIGNAL_LINE, 0, macdSize, macdSignal);
    }

    // Loop MACD.
    for (int i = 0; i < macdSize - 1; i++) {      
  
        // Case equal.
        iSum = 1;
        if (macdMain[i + 1] == macdSignal[i + 1]) {
            iSum = 2;
            if (macdMain[i + 2] == macdSignal[i + 2]) {
                iSum = 3;
            }
        }
        
        // Check crossover.
        if ((macdMain[i] > macdSignal[i] && macdMain[i + iSum] < macdSignal[i + iSum])
                || (macdMain[i] < macdSignal[i] && macdMain[i + iSum] > macdSignal[i + iSum])) {
            
            if (macdCross0 == -1) {
                macdCross0 = i;
            } else if (macdCross1 == -1) {
                macdCross1 = i;
            } else if (macdCross2 == -1) {
                macdCross2 = i;
            } else if (macdCross3 == -1) {
                macdCross3 = i;
                break;
            }
        }
    }
 
    bar.Refresh(ExpertSymbol, TimeFrameArr[0], macdCross3 + crossMargin);
    lastIsHigh = macdMain[macdCross0 + 1] > macdSignal[macdCross0 + 1];
    
    // Find last low and high. 
    if (lastIsHigh) {
        index0 = iHighest(ExpertSymbol, TimeFrameArr[0], MODE_HIGH, macdCross1 - macdCross0 + crossMargin * 2, fmax(0, macdCross0 - crossMargin));
        index1 = iLowest(ExpertSymbol, TimeFrameArr[0], MODE_LOW, macdCross2 - macdCross1 + crossMargin * 2, fmax(0, macdCross1 - crossMargin));
        index2 = iHighest(ExpertSymbol, TimeFrameArr[0], MODE_HIGH, macdCross3 - macdCross2 + crossMargin * 2, fmax(0, macdCross2 - crossMargin));
        if (index0 == NULL || index1 == NULL || index2 == NULL) {
            index0 = index0;
        }
        
        if (pMACD == 0) {
            MACD0_HighLowArr[0] = bar.High(index0);
            MACD0_HighLowArr[1] = bar.Low(index1);
            MACD0_HighLowArr[2] = bar.High(index2);
        } else {
            MACD1_HighLowArr[0] = bar.High(index0);
            MACD1_HighLowArr[1] = bar.Low(index1);
            MACD1_HighLowArr[2] = bar.High(index2);
        }
    } else {
        index0 = iLowest(ExpertSymbol, TimeFrameArr[0], MODE_LOW,  macdCross1 - macdCross0 + crossMargin * 2, fmax(0, macdCross0 - crossMargin));
        index1 = iHighest(ExpertSymbol, TimeFrameArr[0], MODE_HIGH, macdCross2 - macdCross1+ crossMargin * 2, fmax(0, macdCross1 - crossMargin));
        index2 = iLowest(ExpertSymbol, TimeFrameArr[0], MODE_LOW, macdCross3 - macdCross2 + crossMargin * 2, fmax(0, macdCross2 - crossMargin));
        if (index0 == NULL || index1 == NULL || index2 == NULL) {
            index0 = index0;
        }
        if (pMACD == 0) {
            MACD0_HighLowArr[0] = bar.Low(index0);
            MACD0_HighLowArr[1] = bar.High(index1);  
            MACD0_HighLowArr[2] = bar.Low(index2);
        } else {
            MACD1_HighLowArr[0] = bar.Low(index0);
            MACD1_HighLowArr[1] = bar.High(index1);  
            MACD1_HighLowArr[2] = bar.Low(index2);
        }
    }
    
    // Draw MACD trend.
    if (InpDrawMACDTrend) {
        
        // Draw lows and highs.
        //MACD_DrawLine(macdCross0, "macdCross0", clrBlue);
        //MACD_DrawLine(macdCross1, "macdCross1", clrBlue);
        //MACD_DrawLine(macdCross2, "macdCross2", clrBlue);
        //MACD_DrawLine(macdCross3, "macdCross3", clrBlue);
        
        //MACD_DrawLine(index0, "low0", clrMagenta);
        //MACD_DrawLine(index1, "high0", clrMagenta); 
        //MACD_DrawLine(index2, "low1", clrMagenta);
        
        if (pMACD == 0) {
            MACD_DrawTrend("trend0", bar.Time(index0), MACD0_HighLowArr[0], bar.Time(index2), MACD0_HighLowArr[2]);
        } else {
            MACD_DrawTrend("trend1", bar.Time(index0), MACD1_HighLowArr[0], bar.Time(index2), MACD1_HighLowArr[2]);
        }
    }
    
    // Set current trend.    
    int trend; 
    if (pMACD == 0) {
        if (MACD0_HighLowArr[0] > MACD0_HighLowArr[2]) {
            trend = 1;   // bullish.
        } else {
            trend = -1;  // bearish.
        }
    } else {
        if (MACD1_HighLowArr[0] > MACD1_HighLowArr[2]) {
            trend = 1;   // bullish.
        } else {
            trend = -1;  // bearish.
        }
    }
    return trend;
}

void CSmartMoneyStrat::MACD_DrawLine(int pIndex, string pName, color pColor)
{
    bar.Refresh(ExpertSymbol, TimeFrameArr[0], pIndex + 1); 
    ObjectCreate(ChartID(), pName, OBJ_VLINE, 0, bar.Time(pIndex), 0);
    ObjectSetInteger(ChartID(), pName, OBJPROP_COLOR, pColor);
}

bool CSmartMoneyStrat::MACD_BOSCheck(int pMACD)
{
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID); 
    bool trend;
    bool BOSpointIsHigh;
    bool lastIsHigh;
    
    if (pMACD == 0) {
        trend = currTrend;
        BOSpointIsHigh = !currTrend;
        lastIsHigh = MACD0_HighLowArr[0] > MACD0_HighLowArr[1];
        
        // Set BOS point after crossover.
        MACD_UpdateBOSpoint(0, trend);
            
        // Check BOS.
        if ((!BOSpointIsHigh && fmax(priceAsk, priceBid) < MACD0_BOSpoint)
                    || (BOSpointIsHigh && fmin(priceAsk, priceBid) > MACD0_BOSpoint)) {
            
            // BOS.        
            trend = !currTrend;
            
            // Set BOS point after BOS.
            MACD_UpdateBOSpoint(0, trend);
        }
    } else {
        trend = currMACD1Trend;
        BOSpointIsHigh = !currMACD1Trend;
        lastIsHigh = MACD1_HighLowArr[0] > MACD1_HighLowArr[1];
        
        // Set BOS point after crossover.
        MACD_UpdateBOSpoint(1, trend);
            
        // Check BOS.
        if ((!BOSpointIsHigh && fmax(priceAsk, priceBid) < MACD1_BOSpoint)
                    || (BOSpointIsHigh && fmin(priceAsk, priceBid) > MACD1_BOSpoint)) {
            
            // BOS.        
            trend = !currMACD1Trend;
            
            // Set BOS point after BOS.
            MACD_UpdateBOSpoint(1, trend);
        }
    }
    return trend;
}

void CSmartMoneyStrat::MACD_UpdateBOSpoint(int pMACD, bool pTrend) {
    
    if (pMACD == 0) {
        bool lastIsHigh = MACD0_HighLowArr[0] > MACD0_HighLowArr[1];
    
        // Case bullish and last is high.
        if (pTrend && lastIsHigh) {
            MACD0_BOSpoint = MACD0_HighLowArr[1];
            
        // Case bullish and last is low.    
        } else if (pTrend && !lastIsHigh) {
            MACD0_BOSpoint = MACD0_HighLowArr[0];
            
        // Case bearish and last is high.    
        } else if (!pTrend && lastIsHigh) {
            MACD0_BOSpoint = MACD0_HighLowArr[0];
            
        // Case bearish and last is low.   
        } else if (!pTrend && !lastIsHigh) {
            MACD0_BOSpoint = MACD0_HighLowArr[1];
        }
        
        // Draw BOS point.
        if (InpDrawMACDTrend) {
            MACD_DrawBOS("BOS0", MACD0_BOSpoint, clrMagenta);
        }
    } else {
        bool lastIsHigh = MACD1_HighLowArr[0] > MACD1_HighLowArr[1];
    
        // Case bullish and last is high.
        if (pTrend && lastIsHigh) {
            MACD1_BOSpoint = MACD1_HighLowArr[1];
            
        // Case bullish and last is low.    
        } else if (pTrend && !lastIsHigh) {
            MACD1_BOSpoint = MACD1_HighLowArr[0];
            
        // Case bearish and last is high.    
        } else if (!pTrend && lastIsHigh) {
            MACD1_BOSpoint = MACD1_HighLowArr[0];
            
        // Case bearish and last is low.   
        } else if (!pTrend && !lastIsHigh) {
            MACD1_BOSpoint = MACD1_HighLowArr[1];
        }
        
        // Draw BOS point.
        if (InpDrawMACDTrend) {
            MACD_DrawBOS("BOS1", MACD1_BOSpoint, clrMagenta);
        }
    }
}

void CSmartMoneyStrat::MACD_DrawTrend(string pName, datetime ptimeStart, double ppriceLow, datetime ptimeEnd, double ppriceHigh)
{
    color clr;
    ObjectCreate(ChartID(), pName, OBJ_TREND, 0, ptimeStart, ppriceLow, ptimeEnd, ppriceHigh);
    if (ppriceLow > ppriceHigh) {
        clr = clrLightGreen;
    } else {
        clr = clrRed;
    }
    ObjectSetInteger(ChartID(), pName, OBJPROP_COLOR, clr);
}

void CSmartMoneyStrat::MACD_DrawBOS(string pName, double pPrice, color clr)
{
    ObjectCreate(ChartID(), pName, OBJ_HLINE, 0, 0, pPrice);
    ObjectSetInteger(ChartID(), pName, OBJPROP_COLOR, clr);
}

int CSmartMoneyStrat::StrongTrend() {
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    
    // TODO:
    return 1;
}

bool CSmartMoneyStrat::IsOrderBlock(int pIndexOB)
{
    bool cond1 = false;     // Is there void between pIndexOB and pIndexOB-2?
    bool cond11 = false;     // Is there void between pIndexOB and pIndexOB-3?
    bool cond2 = false;     // Is void greatter than InpMinPriceVoid?
    bool cond3 = false;     // Is candle opposite to its next candle?   
    bool cond4 = false;     // Is candle greatter than InpMinOBSize?
    bool cond5 = false;     // Is body greater than InpMinOBBodySize?
    
    bar.Refresh(ExpertSymbol, TimeFrameArr[0], pIndexOB + 1);
    
    if (bar.Low(pIndexOB) - bar.High(pIndexOB - 2) > 0 || bar.Low(pIndexOB - 2) - bar.High(pIndexOB) > 0) {
        cond1 = true;
    }
    
    if (bar.Low(pIndexOB) - bar.High(pIndexOB - 3) > 0 || bar.Low(pIndexOB - 3) - bar.High(pIndexOB) > 0) {
        cond11 = true;
    }

    if (cond1) {
        if (bar.Low(pIndexOB) - bar.High(pIndexOB - 2) > InpMinPriceVoid * InpStratParamsMultiplier * _Point 
                    || bar.Low(pIndexOB - 2) - bar.High(pIndexOB) > InpMinPriceVoid * InpStratParamsMultiplier * _Point) {
            cond2 = true;
        }
    } else if (cond11 /*TODO*/) {
        if (bar.Low(pIndexOB) - bar.High(pIndexOB - 3) > InpMinPriceVoid * InpStratParamsMultiplier * _Point 
                    || bar.Low(pIndexOB - 3) - bar.High(pIndexOB) > InpMinPriceVoid * InpStratParamsMultiplier * _Point) {
            cond2 = true;
        }
    }
    
    if ((bar.Open(pIndexOB) < bar.Close(pIndexOB) && bar.Open(pIndexOB - 1) > bar.Close(pIndexOB - 1))
                    || (bar.Open(pIndexOB) > bar.Close(pIndexOB) && bar.Open(pIndexOB - 1) < bar.Close(pIndexOB - 1))) {
        cond3 = true;                
    }
    cond3 = cond3 || !InpOBCandleMustBeOpposite;

    if (bar.High(pIndexOB) - bar.Low(pIndexOB) >= InpMinOBSize * InpStratParamsMultiplier * _Point || InpMinOBSize * InpStratParamsMultiplier < 1) {
        cond4 = true;
    }
    
    if (MathAbs(bar.Open(pIndexOB) - bar.Close(pIndexOB)) >= InpMinOBBodySize * InpStratParamsMultiplier * _Point || InpMinOBBodySize * InpStratParamsMultiplier < 1) {
        cond5 = true;
    }
    
    return (cond1 || cond11) && cond2 && cond3 && cond4 && cond5;
}

ulong CSmartMoneyStrat::Buy(COBRectangle &pOB)
{
    ulong result = -1;
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    long spread = SymbolInfoInteger(ExpertSymbol, SYMBOL_SPREAD);

    // SL calc.
    int OBBarIndex = iBarShift(ExpertSymbol, pOB.timeFrame, pOB.openTime);
    bar.Refresh(ExpertSymbol, pOB.timeFrame, OBBarIndex + 2);
    double sl  = fmin(bar.Low(OBBarIndex), bar.Low(OBBarIndex - 1));        // Min of ob and ob-1
    sl -= (spread * _Point) - (InpSLMargin * _Point);                       // Minus spread and margin.

    // TP calc.
    double slDistance = MathAbs(priceAsk - sl) / _Point;
    double tp = CalcTakeProfit(pOB.type, slDistance);
    
    // Volume calc.
    double riskPercent = InpSLValue;
    if (InpSlMethod == SLFixedBalance) {
        riskPercent = InpSLValue / AccountInfoDouble(ACCOUNT_EQUITY) * 100;
    }
    double vol = pm.CalcVolumeRiskPerc(ExpertSymbol, InpSLValue, slDistance);
    
    // Comment.
    string timeframe = TimeFrameToString(pOB.timeFrame);
    string comm = "BUY | " + "ob" + string(pOB.id) + " | " + timeframe + " | " + ExpertSymbol + " | " + string(ExpertMagic);
    
    // Exec position.
    result = pm.Buy(ExpertMagic, ExpertSymbol, vol, sl, tp, comm);
    return result;
}

ulong CSmartMoneyStrat::Sell(COBRectangle &pOB)
{
    ulong result = -1;
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    long spread = SymbolInfoInteger(ExpertSymbol, SYMBOL_SPREAD);
    double point = SymbolInfoDouble(ExpertSymbol, SYMBOL_POINT);
    
    // SL calc.
    int OBBarIndex = iBarShift(ExpertSymbol, pOB.timeFrame, pOB.openTime);
    bar.Refresh(ExpertSymbol, pOB.timeFrame, OBBarIndex + 2);
    double sl  = fmax(bar.High(OBBarIndex), bar.High(OBBarIndex - 1));      // Max of ob and ob-1
    sl += (spread * point) + (InpSLMargin * point);                         // Add spread and margin.
    
    // TP calc.
    double slDistance = MathAbs(priceBid - sl) / point;
    double tp = CalcTakeProfit(pOB.type, slDistance);
    
    // Volume calc.
    double riskPercent = InpSLValue;
    if (InpSlMethod == SLFixedBalance) {
        riskPercent = InpSLValue / AccountInfoDouble(ACCOUNT_EQUITY) * 100;
    }
    double vol = pm.CalcVolumeRiskPerc(ExpertSymbol, riskPercent, slDistance);
    
    // Comment.
    string timeframe = StringSubstr(EnumToString((ENUM_TIMEFRAMES) pOB.timeFrame), 7);
    string comm = "SELL | " + "ob" + string(pOB.id) + " | " + timeframe + " | " + ExpertSymbol + " | " + string(ExpertMagic);
    
    // Exec position.
    result = pm.Sell(ExpertMagic, ExpertSymbol, vol, sl, tp, comm);
    return result;
}

double CSmartMoneyStrat::CalcTakeProfit(eOBType pType, double pSlDistance = 0)
{
    double priceAsk = SymbolInfoDouble(ExpertSymbol, SYMBOL_ASK);
    double priceBid = SymbolInfoDouble(ExpertSymbol, SYMBOL_BID);
    double tpDistance = 0;
    double tp = 0;
    
    // Case FixedRR. 
    if (InpTPMethod == TPFixedRR) {
        tpDistance = pSlDistance * InpTPValue;
        
    // Case TPToNextHighLow.
    } else if (InpTPMethod == TPToNextHighLow) {
        // TODO:
        
    // Case TPToNextOB.
    } else if (InpTPMethod == TPToNextOB) {
        // TODO:
        
    // Case TPToNextOBorHighLow.
    } else if (InpTPMethod == TPToNextOBorHighLow) {
        // TODO: 
    }
    
    // Case sell2buy.
    if (pType == sell2buy) {
        tp = priceBid + (tpDistance * _Point) + (InpTPMargin * _Point);
        
    // Case buy2sell.
    } else if (pType == buy2sell) {
        tp = priceAsk - (tpDistance * _Point) - (InpTPMargin * _Point);
    }
    
    // Case no TP.
    if (InpTPValue == 0) {
        tp = InpTPValue;
    }
    return tp;
}

void CSmartMoneyStrat::DrawData()
{
    long spread = SymbolInfoInteger(ExpertSymbol, SYMBOL_SPREAD);
    string maxSpread = InpMaxSpread > 0 ? string(InpMaxSpread) : "No limit";
    MqlDateTime time;
    TimeCurrent(time);
    
    Comment("\nSpread: ", spread, " (Max. ", maxSpread, ")",
            "\nSchedule: ", sch.GetLastInTime(), " (", sch.GetScheduleString(), ")",
            "\nDay: ", time.day_of_week, " (", sch.GetDaysString(), ")",
            "\nMinor trend: ", currTrend,
            "\nMajor trend: ", currMACD1Trend,
            "\n",
            "\nStats: ",
            "\nMontly avg: ", stats.GetMonthlyProfitAvg(),
            "\nDaily positions avg: ", stats.GetDailyPositionsAvg(),
            "\n",
            "\nLast error: ", GetLastError(), " - ", ErrorDescription(GetLastError())          
            );
}

void CSmartMoneyStrat::InitOrderBlocks(int pFromBar)
{   
    for (int i = pFromBar - 1; i >= 0; i--) {
        RefreshOBList(i);
        InitOB_CheckMitigated(i);
    }    
}

void CSmartMoneyStrat::InitOB_CheckMitigated(int pBar)
{
    bar.Refresh(ExpertSymbol, TimeFrameArr[0], pBar + 1);
    
    // Loop orderblocks.
    for (uint i = 0; i <= obList.Size() - 1; i++) {
    
        if (obList[i].active) {
        
            // Check if ob is mitigated.
            if ((obList[i].type == sell2buy && bar.Low(pBar) - (InpEntryMargin * _Point) <= obList[i].priceHigh)
                        || (obList[i].type == buy2sell && bar.High(pBar) + (InpEntryMargin * _Point) >= obList[i].priceLow)) {
                
                obList[i].active = false;
            }    
        }
    }
}

bool CSmartMoneyStrat::CheckParams()
{   
    // TODO:
    if (ExpertMagic <= 0) {
        return false;
    }
    return true;
}

void CSmartMoneyStrat::DrawOrderBlocks()
{
    if (InpDrawOrderblocks) {
        for (uint i = 0; i < obList.Size(); i++) { 
            if (obList[i].priceLow != NULL) {
            
                string name = "ob" + string(obList[i].id);
                long clr = obList[i].type == buy2sell ? clrRed : clrWhite;
                string label = name + " " + TimeFrameToString(obList[i].timeFrame) + " " + string(obList[i].active);
                
                // Delete object.
                ObjectDelete(0, name);
                
                // Rectangle.
                ObjectCreate(0, name, OBJ_RECTANGLE, 0, obList[i].timeStart, obList[i].priceLow, obList[i].timeEnd + PeriodSeconds(PERIOD_CURRENT), obList[i].priceHigh);
                ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
                
                // Label.
                ObjectCreate(0, string(i), OBJ_TEXT, 0, obList[i].timeEnd + PeriodSeconds(PERIOD_CURRENT), obList[i].priceHigh);
                ObjectSetInteger(0, string(i), OBJPROP_COLOR, clr);
                ObjectSetString(0, string(i), OBJPROP_TEXT, label);
            }
        }
    }    
}

void CSmartMoneyStrat::RefreshOBList(int pCurrentBar = 0)
{
    int indexOB = pCurrentBar + 4;
    bar.Refresh(ExpertSymbol, TimeFrameArr[0], pCurrentBar + 1);
    
    // Update timeEnd for active OBs.
    for (uint i = 0; i < obList.Size(); i++) {
        if (obList[i].active) { 
            obList[i].timeEnd = fmax(obList[i].timeEnd, bar.Time(pCurrentBar));
        }
    }

    if (IsOrderBlock(indexOB)) {
        
        // Fuse if overlapping with another OB in the list.
        if (!FuseIfOverlapping(indexOB, TimeFrameArr[0])) {
            
            // If not overlapping add new OB to the oblist.
            COBRectangle newOB;
            newOB.active = true;
            newOB.openTime = bar.Time(indexOB);
            newOB.timeStart = bar.Time(indexOB) - 1 * PeriodSeconds(TimeFrameArr[0]);
            newOB.timeEnd = bar.Time(indexOB) + 3 * PeriodSeconds(TimeFrameArr[0]);
            newOB.priceLow = bar.Low(indexOB);
            newOB.priceHigh = bar.High(indexOB);
            newOB.type = bar.Open(indexOB) < bar.Close(indexOB) ? buy2sell : sell2buy;
            newOB.timeFrame = TimeFrameArr[0];  
            newOB.id = OBCounter;          
            Add(newOB);
            OBCounter++;
        }
    }
}

bool CSmartMoneyStrat::FuseIfOverlapping(int pIndexOB, ENUM_TIMEFRAMES pCurrentTimeFrame) 
{
    // Skip if OB fusion is disabled.
    if (!InpFuseOrderBlocksEnabled) return false;
    
    uint indexOBList = -1;
    bool overlapping = false;

    for (uint i = 0; i < obList.Size(); i++) {   
        if (obList[i].active) {
        
            // Skip if same candle.
            if (bar.High(pIndexOB) == obList[i].priceHigh && bar.Low(pIndexOB) == obList[i].priceLow) {
                return true;
            }            
            
            // Check overlapping.
            if ((bar.High(pIndexOB) >= obList[i].priceLow - (InpDistanceToFuse * _Point) && bar.High(pIndexOB) <= obList[i].priceHigh)
                    || (bar.Low(pIndexOB) >= obList[i].priceLow && bar.Low(pIndexOB) <= obList[i].priceHigh + (InpDistanceToFuse * _Point))
                    || (bar.High(pIndexOB) >= obList[i].priceHigh && bar.Low(pIndexOB) <= obList[i].priceLow)
                    || (obList[i].priceHigh >= bar.High(pIndexOB) && obList[i].priceLow <= bar.Low(pIndexOB))) {
                indexOBList = i;
                overlapping = true;          
            }
        }
    }

    // Fuse if overlapping.
    if (overlapping) {
        obList[indexOBList].priceLow = fmin(obList[indexOBList].priceLow, bar.Low(pIndexOB));
        obList[indexOBList].priceHigh = fmax(obList[indexOBList].priceHigh, bar.High(pIndexOB));
        obList[indexOBList].timeFrame = fmax(obList[indexOBList].timeFrame, pCurrentTimeFrame);
    }    
    return overlapping;
}

void CSmartMoneyStrat::Add(COBRectangle &newOB)
{
    bool foundSlot = false;
    bool moveLeft = false;
    
    // Add to the first free slot in obList.
    for (uint i = 0; i <= obList.Size() - 1; i++) {
        if (obList[i].priceLow == NULL) {
            obList[i] = newOB;
            foundSlot = true;
            break;
        }
    }
    
    // If oblist is full, delete the first mitigated OB, move the rest to the left and add the new one to the end.
    if (!foundSlot) {
    
        for (uint i = 0; i <= obList.Size() - 2; i++) {
            if (!obList[i].active) {
                moveLeft = true;
            }            
            if (moveLeft) {
                obList[i] = obList[i + 1];
            }
        }
        obList[obList.Size() - 1] = newOB;
    }
}

/**
 * COBRectangle METHODS
 */
COBRectangle::COBRectangle(void) {}