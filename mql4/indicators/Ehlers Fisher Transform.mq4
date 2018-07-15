/**
 * Ehlers' Fisher Transform
 *
 * as described in his book "Cybernetic Analysis for Stocks and Futures". Ehlers used arbitrary smoothing algorythms which
 * are wrongly or not documented in his publications.
 *
 * Indicator buffers to use with iCustom():
 *  � Fisher.MODE_MAIN:      main values
 *  � Fisher.MODE_DIRECTION: value direction and section length
 *    - direction: positive values denote an indicator above zero (+1...+n), negative values an indicator below zero (-1...-n)
 *    - length:    the absolute direction value is each histogram's section length (bars since the last crossing of zero)
 *
 *
 * @see  [Ehlers](etc/doc/ehlers/Cybernetic Analysis for Stocks and Futures.pdf)
 * @see  [Ehlers](etc/doc/ehlers/Using The Fisher Transform [Stocks & Commodities].pdf)
 *
 *
 * TODO:
 *    - implement customizable moving averages for normalized price and Fisher Transform
 *    - implement Max.Values
 *    - implement PRICE_* types
 */
#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern int   Fisher.Periods        = 10;

extern color Histogram.Color.Upper = LimeGreen;             // indicator style management in MQL
extern color Histogram.Color.Lower = Red;
extern int   Histogram.Style.Width = 2;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <stdlibs.mqh>

#define MODE_MAIN           Fisher.MODE_MAIN                // indicator buffer ids
#define MODE_DIRECTION      Fisher.MODE_DIRECTION
#define MODE_UPPER_SECTION  2
#define MODE_LOWER_SECTION  3
#define MODE_PRICE          4
#define MODE_NORMALIZED     5

#property indicator_separate_window
#property indicator_buffers 4

double fisherMain      [];                                  // main value:                invisible, displayed in "Data" window
double fisherDirection [];                                  // direction and length:      invisible
double fisherUpper     [];                                  // positive histogram values: visible
double fisherLower     [];                                  // negative histogram values: visible
double rawPrices       [];                                  // used raw prices:           invisible
double normalizedPrices[];                                  // normalized prices:         invisible

string fisher.name;                                         // indicator name


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   if (InitReason() == IR_RECOMPILE) {
      if (!RestoreInputParameters()) return(last_error);
   }

   // (1) validate inputs
   // Fisher.Periods
   if (Fisher.Periods < 1)        return(catch("onInit(1)  Invalid input parameter Fisher.Periods = "+ Fisher.Periods, ERR_INVALID_INPUT_PARAMETER));

   // Colors: after unserialization the terminal might turn CLR_NONE (0xFFFFFFFF) into Black (0xFF000000)
   if (Histogram.Color.Upper == 0xFF000000) Histogram.Color.Upper = CLR_NONE;
   if (Histogram.Color.Lower == 0xFF000000) Histogram.Color.Lower = CLR_NONE;

   // Styles
   if (Histogram.Style.Width < 1) return(catch("onInit(2)  Invalid input parameter Histogram.Style.Width = "+ Histogram.Style.Width, ERR_INVALID_INPUT_PARAMETER));
   if (Histogram.Style.Width > 5) return(catch("onInit(3)  Invalid input parameter Histogram.Style.Width = "+ Histogram.Style.Width, ERR_INVALID_INPUT_PARAMETER));


   // (2) setup buffer management
   IndicatorBuffers(6);
   SetIndexBuffer(MODE_MAIN,          fisherMain      );    // main values:               invisible, displayed in "Data" window
   SetIndexBuffer(MODE_DIRECTION,     fisherDirection );    // direction and length:      invisible
   SetIndexBuffer(MODE_UPPER_SECTION, fisherUpper     );    // positive histogram values: visible
   SetIndexBuffer(MODE_LOWER_SECTION, fisherLower     );    // negative histogram values: visible
   SetIndexBuffer(MODE_PRICE,         rawPrices       );    // used raw prices:           invisible
   SetIndexBuffer(MODE_NORMALIZED,    normalizedPrices);    // normalized prices:         invisible


   // (3) data display configuration, names and labels
   fisher.name = "Fisher Transform("+ Fisher.Periods +")";
   IndicatorShortName(fisher.name +"  ");                   // subwindow and context menu
   SetIndexLabel(MODE_MAIN,          fisher.name);          // "Data" window and tooltips
   SetIndexLabel(MODE_DIRECTION,     NULL);
   SetIndexLabel(MODE_UPPER_SECTION, NULL);
   SetIndexLabel(MODE_LOWER_SECTION, NULL);
   SetIndexLabel(MODE_PRICE,         NULL);
   SetIndexLabel(MODE_NORMALIZED,    NULL);
   IndicatorDigits(2);


   // (4) drawing options and styles
   int startDraw = 0;
   SetIndexDrawBegin(MODE_UPPER_SECTION, startDraw);
   SetIndexDrawBegin(MODE_LOWER_SECTION, startDraw);
   SetIndicatorStyles();
}


/**
 * Called before recompilation.
 *
 * @return int - error status
 */
int onDeinitRecompile() {
   StoreInputParameters();
   return(last_error);
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   // check for finished buffer initialization
   if (!ArraySize(fisherMain))                                          // can happen on terminal start
      return(log("onTick(1)  size(fisherMain) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // reset all buffers and delete garbage before doing a full recalculation
   if (!ValidBars) {
      ArrayInitialize(fisherMain,       EMPTY_VALUE);
      ArrayInitialize(fisherDirection,            0);
      ArrayInitialize(fisherUpper,      EMPTY_VALUE);
      ArrayInitialize(fisherLower,      EMPTY_VALUE);
      ArrayInitialize(rawPrices,        EMPTY_VALUE);
      ArrayInitialize(normalizedPrices, EMPTY_VALUE);
      SetIndicatorStyles();                                             // fix for various terminal bugs
   }

   // synchronize buffers with a shifted offline chart (if applicable)
   if (ShiftedBars > 0) {
      ShiftIndicatorBuffer(fisherMain,       Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(fisherDirection,  Bars, ShiftedBars,           0);
      ShiftIndicatorBuffer(fisherUpper,      Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(fisherLower,      Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(rawPrices,        Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(normalizedPrices, Bars, ShiftedBars, EMPTY_VALUE);
   }


   // (1) calculate start bar
   int maxBar = Bars-Fisher.Periods;
   int startBar = Min(ChangedBars-1, maxBar);
   if (startBar < 0) return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));


   // (2) recalculate invalid prices
   for (int bar=ChangedBars-1; bar >= 0; bar--) {
      rawPrices[bar] = iMA(NULL, NULL, 1, 0, MODE_SMA, PRICE_MEDIAN, bar);
   }


   double range, rangeHigh, rangeLow, relPrice, centeredPrice, limit=0.9999999999999;


   // (3) recalculate invalid indicator values
   for (bar=startBar; bar >= 0; bar--) {
      rangeHigh = rawPrices[ArrayMaximum(rawPrices, Fisher.Periods, bar)];
      rangeLow  = rawPrices[ArrayMinimum(rawPrices, Fisher.Periods, bar)];
      range     = rangeHigh - rangeLow;

      if (NE(rangeHigh, rangeLow, Digits)) relPrice = (rawPrices[bar]-rangeLow) / range;  // values: 0...1 (a Stochastic Oscillator)
      else                                 relPrice = 0.5;                                // undefined: assume average value
      centeredPrice = 2*relPrice - 1;                                                     // values: -1...+1

      if (bar == maxBar) {
         normalizedPrices[bar] = centeredPrice;
         fisherMain      [bar] = MathLog((1+normalizedPrices[bar])/(1-normalizedPrices[bar]));
      }
      else {
         normalizedPrices[bar] = 0.33*centeredPrice + 0.67*normalizedPrices[bar+1];       // MA(2), not an EMA(alpha=0.33) as stated by Ehlers
         normalizedPrices[bar] = MathMax(MathMin(normalizedPrices[bar], limit), -limit);  // limit avg. values to the original range
         fisherMain      [bar] = 0.5*MathLog((1+normalizedPrices[bar])/(1-normalizedPrices[bar])) + 0.5*fisherMain[bar+1];    // LWMA(2)
      }

      if (fisherMain[bar] > 0) {
         fisherUpper[bar] = fisherMain[bar];
         fisherLower[bar] = EMPTY_VALUE;
      }
      else {
         fisherUpper[bar] = EMPTY_VALUE;
         fisherLower[bar] = fisherMain[bar];
      }

      // update section length
      if      (fisherDirection[bar+1] > 0 && fisherDirection[bar] >= 0) fisherDirection[bar] = fisherDirection[bar+1] + 1;
      else if (fisherDirection[bar+1] < 0 && fisherDirection[bar] <= 0) fisherDirection[bar] = fisherDirection[bar+1] - 1;
      else                                                              fisherDirection[bar] = Sign(fisherMain[bar]);
   }
   return(catch("onTick(2)"));
}


/**
 * Set indicator styles. Workaround for various terminal bugs when setting indicator styles and levels. Usually styles are
 * applied in init(). However after recompilation styles must be applied in start() to not get ignored.
 */
void SetIndicatorStyles() {
   SetIndexStyle(MODE_MAIN,          DRAW_NONE,      EMPTY, EMPTY,                 CLR_NONE             );
   SetIndexStyle(MODE_DIRECTION,     DRAW_NONE,      EMPTY, EMPTY,                 CLR_NONE             );
   SetIndexStyle(MODE_UPPER_SECTION, DRAW_HISTOGRAM, EMPTY, Histogram.Style.Width, Histogram.Color.Upper);
   SetIndexStyle(MODE_LOWER_SECTION, DRAW_HISTOGRAM, EMPTY, Histogram.Style.Width, Histogram.Color.Lower);
}


/**
 * Store input parameters in the chart for restauration after recompilation.
 *
 * @return bool - success status
 */
bool StoreInputParameters() {
   Chart.StoreInt(__NAME__ +".input.Fisher.Periods",        Fisher.Periods       );
   Chart.StoreInt(__NAME__ +".input.Histogram.Color.Upper", Histogram.Color.Upper);
   Chart.StoreInt(__NAME__ +".input.Histogram.Color.Lower", Histogram.Color.Lower);
   Chart.StoreInt(__NAME__ +".input.Histogram.Style.Width", Histogram.Style.Width);
   return(!catch("StoreInputParameters(1)"));
}


/**
 * Restore input parameters found in the chart after recompilation.
 *
 * @return bool - success status
 */
bool RestoreInputParameters() {
   string label = __NAME__ +".input.Fisher.Periods";
   if (ObjectFind(label) == 0) {
      string sValue = StringTrim(ObjectDescription(label));
      if (!StringIsDigit(sValue))   return(!catch("RestoreInputParameters(1)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)), ERR_INVALID_CONFIG_PARAMVALUE));
      ObjectDelete(label);
      Fisher.Periods = StrToInteger(sValue);                      // (int) string
   }

   label = __NAME__ +".input.Histogram.Color.Upper";
   if (ObjectFind(label) == 0) {
      sValue = StringTrim(ObjectDescription(label));
      if (!StringIsInteger(sValue)) return(!catch("RestoreInputParameters(2)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)), ERR_INVALID_CONFIG_PARAMVALUE));
      int iValue = StrToInteger(sValue);
      if (iValue < CLR_NONE || iValue > C'255,255,255')
                                    return(!catch("RestoreInputParameters(3)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)) +" (0x"+ IntToHexStr(iValue) +")", ERR_INVALID_CONFIG_PARAMVALUE));
      ObjectDelete(label);
      Histogram.Color.Upper = iValue;                             // (color)(int) string
   }

   label = __NAME__ +".input.Histogram.Color.Lower";
   if (ObjectFind(label) == 0) {
      sValue = StringTrim(ObjectDescription(label));
      if (!StringIsInteger(sValue)) return(!catch("RestoreInputParameters(4)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)), ERR_INVALID_CONFIG_PARAMVALUE));
      iValue = StrToInteger(sValue);
      if (iValue < CLR_NONE || iValue > C'255,255,255')
                                    return(!catch("RestoreInputParameters(5)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)) +" (0x"+ IntToHexStr(iValue) +")", ERR_INVALID_CONFIG_PARAMVALUE));
      ObjectDelete(label);
      Histogram.Color.Lower = iValue;                             // (color)(int) string
   }

   label = __NAME__ +".input.Histogram.Style.Width";
   if (ObjectFind(label) == 0) {
      sValue = StringTrim(ObjectDescription(label));
      if (!StringIsDigit(sValue))   return(!catch("RestoreInputParameters(6)  illegal chart value "+ label +" = "+ DoubleQuoteStr(ObjectDescription(label)), ERR_INVALID_CONFIG_PARAMVALUE));
      ObjectDelete(label);
      Histogram.Style.Width = StrToInteger(sValue);               // (int) string
   }
   return(!catch("RestoreInputParameters(7)"));
}


/**
 * Return a string representation of the input parameters. Used for logging iCustom() calls.
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("input: ",

                            "Fisher.Periods=",  Fisher.Periods,                          "; ",

                            "Histogram.Color.Upper=", ColorToStr(Histogram.Color.Upper), "; ",
                            "Histogram.Color.Lower=", ColorToStr(Histogram.Color.Lower), "; ",
                            "Histogram.Style.Width=", Histogram.Style.Width,             "; ")
   );
}