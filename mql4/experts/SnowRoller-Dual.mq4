/**
 * SnowRoller-Strategy: ein unabh�ngiger SnowRoller je Richtung
 */
#property stacksize 32768

#include <stddefine.mqh>
int   __INIT_FLAGS__[] = {INIT_TIMEZONE, INIT_PIPVALUE, INIT_CUSTOMLOG};
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
#include <win32api.mqh>

#include <core/expert.mqh>
#include <SnowRoller/define.mqh>
#include <SnowRoller/functions.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern int    GridSize        = 20;
extern double LotSize         = 0.1;
extern string StartConditions = "@trend(ALMA:3.5xD1)";
extern string StopConditions  = "@profit(500)";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


int      last.GridSize;                                                 // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE
double   last.LotSize;                                                  // mit den Default-Werten �berschrieben. Um dies zu verhindern und um ge�nderte Parameter mit
string   last.StartConditions = "";                                     // alten Werten vergleichen zu k�nnen, werden sie in deinit() in last.* zwischengespeichert und
string   last.StopConditions  = "";                                     // in init() daraus restauriert.

int      instance.id;                                                   // eine Instanz (mit eigener Statusdatei) verwaltet mehrere eigenst�ndige Sequenzen
bool     instance.isTest;                                               // ob die Instanz eine Testinstanz ist (im Tester oder im Online-Chart)

// ---------------------------------------------------------------
bool     start.trend.condition;
string   start.trend.condition.txt;
double   start.trend.periods;
int      start.trend.timeframe, start.trend.timeframeFlag;              // maximal PERIOD_H1
string   start.trend.method;
int      start.trend.lag;

// ---------------------------------------------------------------
bool     stop.profitAbs.condition;
string   stop.profitAbs.condition.txt;
double   stop.profitAbs.value;

// ---------------------------------------------------------------
datetime weekend.stop.condition   = D'1970.01.01 23:05';                // StopSequence()-Zeitpunkt vor Wochenend-Pause (Freitags abend)
datetime weekend.stop.time;

datetime weekend.resume.condition = D'1970.01.01 01:10';                // sp�tester ResumeSequence()-Zeitpunkt nach Wochenend-Pause (Montags morgen)
datetime weekend.resume.time;

// ---------------------------------------------------------------
int      l.sequence.id,                 s.sequence.id;
int      l.sequence.status,             s.sequence.status;
string   l.sequence.status.file[2],     s.sequence.status.file[2];      // [0] => Verzeichnis (relativ zu ".\files\"), [1] => Dateiname
double   l.sequence.startEquity,        s.sequence.startEquity;         // Equity bei Start der Sequenz
bool     l.sequence.weStop.active,      s.sequence.weStop.active;       // Weekend-Stop aktiv (unterscheidet zwischen vor�bergehend und dauerhaft gestoppten Sequenzen)
bool     l.sequence.weResume.triggered, s.sequence.weResume.triggered;  // ???

// ---------------------------------------------------------------
int      l.sequenceStart.event [],      s.sequenceStart.event [];       // Start-Daten (Moment von Statuswechsel zu STATUS_PROGRESSING)
datetime l.sequenceStart.time  [],      s.sequenceStart.time  [];
double   l.sequenceStart.price [],      s.sequenceStart.price [];
double   l.sequenceStart.profit[],      s.sequenceStart.profit[];

int      l.sequenceStop.event  [],      s.sequenceStop.event  [];       // Stop-Daten (Moment von Statuswechsel zu STATUS_STOPPED)
datetime l.sequenceStop.time   [],      s.sequenceStop.time   [];
double   l.sequenceStop.price  [],      s.sequenceStop.price  [];
double   l.sequenceStop.profit [],      s.sequenceStop.profit [];

// ---------------------------------------------------------------
int      l.level,                       s.level;                        // aktueller Grid-Level
int      l.maxLevel,                    s.maxLevel;                     // maximal erreichter Grid-Level

int      l.gridbase.event[],            s.gridbase.event[];             // Gridbasis-Daten
datetime l.gridbase.time [],            s.gridbase.time [];
double   l.gridbase.value[],            s.gridbase.value[];
double   l.gridbase,                    s.gridbase;                     // aktuelle Gridbasis

int      l.stops,                       s.stops;                        // Anzahl der bisher getriggerten Stops
double   l.stopsPL,                     s.stopsPL;                      // kumulierter P/L aller bisher ausgestoppten Positionen
double   l.closedPL,                    s.closedPL;                     // kumulierter P/L aller bisher bei Sequencestop geschlossenen Positionen
double   l.floatingPL,                  s.floatingPL;                   // kumulierter P/L aller aktuell offenen Positionen
double   l.totalPL,                     s.totalPL;                      // aktueller Gesamt-P/L der Sequenz: grid.stopsPL + grid.closedPL + grid.floatingPL
double   l.openRisk,                    s.openRisk;                     // vorraussichtlicher kumulierter P/L aller aktuell offenen Level bei deren Stopout: sum(orders.openRisk)
double   l.valueAtRisk,                 s.valueAtRisk;                  // vorraussichtlicher Gesamt-P/L der Sequenz bei Stop in Level 0: grid.stopsPL + grid.openRisk
double   l.breakeven,                   s.breakeven;

double   l.maxProfit,                   s.maxProfit;                    // maximaler bisheriger Gesamt-Profit der Sequenz   (>= 0)
double   l.maxDrawdown,                 s.maxDrawdown;                  // maximaler bisheriger Gesamt-Drawdown der Sequenz (<= 0)

// ---------------------------------------------------------------
int      l.orders.ticket        [],     s.orders.ticket        [];
int      l.orders.level         [],     s.orders.level         [];      // Gridlevel der Order
double   l.orders.gridBase      [],     s.orders.gridBase      [];      // Gridbasis der Order

int      l.orders.pendingType   [],     s.orders.pendingType   [];      // Pending-Orderdaten (falls zutreffend)
datetime l.orders.pendingTime   [],     s.orders.pendingTime   [];      // Zeitpunkt von OrderOpen() bzw. letztem OrderModify()
double   l.orders.pendingPrice  [],     s.orders.pendingPrice  [];

int      l.orders.type          [],     s.orders.type          [];
int      l.orders.openEvent     [],     s.orders.openEvent     [];
datetime l.orders.openTime      [],     s.orders.openTime      [];
double   l.orders.openPrice     [],     s.orders.openPrice     [];
double   l.orders.openRisk      [],     s.orders.openRisk      [];      // vorraussichtlicher P/L des Levels seit letztem Stopout bei erneutem Stopout

int      l.orders.closeEvent    [],     s.orders.closeEvent    [];
datetime l.orders.closeTime     [],     s.orders.closeTime     [];
double   l.orders.closePrice    [],     s.orders.closePrice    [];
double   l.orders.stopLoss      [],     s.orders.stopLoss      [];
bool     l.orders.clientSL      [],     s.orders.clientSL      [];      // client- oder server-seitiger StopLoss
bool     l.orders.closedBySL    [],     s.orders.closedBySL    [];

double   l.orders.swap          [],     s.orders.swap          [];
double   l.orders.commission    [],     s.orders.commission    [];
double   l.orders.profit        [],     s.orders.profit        [];

// ---------------------------------------------------------------
int      l.ignorePendingOrders  [],     s.ignorePendingOrders  [];      // orphaned tickets to ignore
int      l.ignoreOpenPositions  [],     s.ignoreOpenPositions  [];
int      l.ignoreClosedPositions[],     s.ignoreClosedPositions[];

// ---------------------------------------------------------------
double   commission;                                                    // Commission-Betrag je Level

// ---------------------------------------------------------------
string   str.l.stops,                   str.s.stops;                    // Zwischenspeicher zur schnelleren Abarbeitung von ShowStatus()
string   str.l.stopsPL,                 str.s.stopsPL;
string   str.l.totalPL,                 str.s.totalPL;
string   str.l.plStatistics,            str.s.plStatistics;

string   str.LotSize;
string   str.totalPL;
string   str.plStatistics;


#include <SnowRoller/init-dual.mqh>
#include <SnowRoller/deinit-dual.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   Strategy(D_LONG );
   Strategy(D_SHORT);
   return(last_error);
}


/**
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - Erfolgsstatus
 */
bool Strategy(int direction) {
   if (__STATUS_ERROR)
      return(false);

   bool changes;                                                     // Gridbasis- oder -level�nderung
   int  status, stops[];                                             // getriggerte client-seitige Stops

   if      (direction == D_LONG ) status = l.sequence.status;
   else if (direction == D_SHORT) status = s.sequence.status;
   else return(!catch("Strategy()   illegal parameter direction = "+ direction, ERR_INVALID_FUNCTION_PARAMVALUE));


   // (1) Strategie wartet auf Startsignal, ...
   if (status == STATUS_UNINITIALIZED) {
      if (IsStartSignal(direction))   StartSequence(direction);
   }

   // (2) ... oder auf ResumeSignal ...
   else if (status == STATUS_STOPPED) {
      if  (IsResumeSignal(direction)) ResumeSequence(direction);
      else return(!IsLastError());
   }

   // (3) ... oder l�uft
   else if (UpdateStatus(direction, changes, stops)) {
      if (IsStopSignal(direction))    StopSequence(direction);
      else {
         if (ArraySize(stops) > 0)    ProcessClientStops(stops);
         if (changes)                 UpdatePendingOrders(direction);
      }
   }

   return(!IsLastError());
}


/**
 * Signalgeber f�r StartSequence().
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - ob ein Signal aufgetreten ist
 */
bool IsStartSignal(int direction) {
   if (__STATUS_ERROR)
      return(false);

   int iNull[];

   if (EventListener.BarOpen(iNull, start.trend.timeframeFlag)) {
      int    timeframe   = start.trend.timeframe;
      string maPeriods   = NumberToStr(start.trend.periods, ".+");
      string maTimeframe = PeriodDescription(start.trend.timeframe);
      string maMethod    = start.trend.method;
      int    lag         = start.trend.lag;
      int    signal      = 0;

      if (CheckTrendChange(timeframe, maPeriods, maTimeframe, maMethod, lag, direction, signal)) {
         if (signal != 0) {
            if (__LOG) log(StringConcatenate("IsStartSignal()   start signal \"", start.trend.condition.txt, "\" ", ifString(signal>0, "up", "down")));
            return(true);
         }
      }
   }
   return(false);
}


/**
 * Signalgeber f�r ResumeSequence().
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool
 */
bool IsResumeSignal(int direction) {
   if (__STATUS_ERROR)
      return(false);
   return(IsWeekendResumeSignal());
}


/**
 * Signalgeber f�r ResumeSequence(). Pr�ft, ob die Weekend-Resume-Bedingung erf�llt ist.
 *
 * @return bool
 */
bool IsWeekendResumeSignal() {
   return(!catch("IsWeekendResumeSignal()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Signalgeber f�r StopSequence().
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - ob ein Signal aufgetreten ist
 */
bool IsStopSignal(int direction) {
   return(!catch("IsStopSignal()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Startet eine neue Trade-Sequenz.
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - Erfolgsstatus
 */
bool StartSequence(int direction) {
   return(!catch("StartSequence()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Schlie�t alle PendingOrders und offenen Positionen der Sequenz.
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - Erfolgsstatus: ob die Sequenz erfolgreich gestoppt wurde
 */
bool StopSequence(int direction) {
   return(!catch("StopSequence()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Setzt eine gestoppte Sequenz fort.
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - Erfolgsstatus
 */
bool ResumeSequence(int direction) {
   return(!catch("ResumeSequence()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Pr�ft und synchronisiert die im EA gespeicherten mit den aktuellen Laufzeitdaten.
 *
 * @param  int  direction        - D_LONG | D_SHORT
 * @param  bool lpChanges        - Variable, die nach R�ckkehr anzeigt, ob sich Gridbasis oder Gridlevel der Sequenz ge�ndert haben
 * @param  int  triggeredStops[] - Array, das nach R�ckkehr die Array-Indizes getriggerter client-seitiger Stops enth�lt (Pending- und SL-Orders)
 *
 * @return bool - Erfolgsstatus
 */
bool UpdateStatus(int direction, bool &lpChanges, int triggeredStops[]) {
   return(!catch("UpdateStatus()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Ordermanagement getriggerter client-seitiger Stops. Kann eine getriggerte Stop-Order oder ein getriggerter Stop-Loss sein.
 *
 * @param  int stops[] - Array-Indizes der Orders mit getriggerten Stops
 *
 * @return bool - Erfolgsstatus
 */
bool ProcessClientStops(int stops[]) {
   return(!catch("ProcessClientStops()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Aktualisiert vorhandene, setzt fehlende und l�scht unn�tige PendingOrders.
 *
 * @param  int direction - D_LONG | D_SHORT
 *
 * @return bool - Erfolgsstatus
 */
bool UpdatePendingOrders(int direction) {
   return(!catch("UpdatePendingOrders()", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Speichert die aktuelle Konfiguration zwischen, um sie bei Fehleingaben nach Parameter�nderungen restaurieren zu k�nnen.
 *
 * @return void
 */
void StoreConfiguration(bool save=true) {
   static int    _GridSize;
   static double _LotSize;
   static string _StartConditions;
   static string _StopConditions;

   static bool   _start.trend.condition;
   static string _start.trend.condition.txt;
   static double _start.trend.periods;
   static int    _start.trend.timeframe;
   static int    _start.trend.timeframeFlag;
   static string _start.trend.method;
   static int    _start.trend.lag;

   static bool   _stop.profitAbs.condition;
   static string _stop.profitAbs.condition.txt;
   static double _stop.profitAbs.value;

   if (save) {
      _GridSize                     = GridSize;
      _LotSize                      = LotSize;
      _StartConditions              = StringConcatenate(StartConditions, "");    // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)
      _StopConditions               = StringConcatenate(StopConditions,  "");

      _start.trend.condition        = start.trend.condition;
      _start.trend.condition.txt    = start.trend.condition.txt;
      _start.trend.periods          = start.trend.periods;
      _start.trend.timeframe        = start.trend.timeframe;
      _start.trend.timeframeFlag    = start.trend.timeframeFlag;
      _start.trend.method           = start.trend.method;
      _start.trend.lag              = start.trend.lag;

      _stop.profitAbs.condition     = stop.profitAbs.condition;
      _stop.profitAbs.condition.txt = stop.profitAbs.condition.txt;
      _stop.profitAbs.value         = stop.profitAbs.value;
   }
   else {
      GridSize                      = _GridSize;
      LotSize                       = _LotSize;
      StartConditions               = _StartConditions;
      StopConditions                = _StopConditions;

      start.trend.condition         = _start.trend.condition;
      start.trend.condition.txt     = _start.trend.condition.txt;
      start.trend.periods           = _start.trend.periods;
      start.trend.timeframe         = _start.trend.timeframe;
      start.trend.timeframeFlag     = _start.trend.timeframeFlag;
      start.trend.method            = _start.trend.method;
      start.trend.lag               = _start.trend.lag;

      stop.profitAbs.condition      = _stop.profitAbs.condition;
      stop.profitAbs.condition.txt  = _stop.profitAbs.condition.txt;
      stop.profitAbs.value          = _stop.profitAbs.value;
   }
}


/**
 * Restauriert eine zuvor gespeicherte Konfiguration.
 *
 * @return void
 */
void RestoreConfiguration() {
   StoreConfiguration(false);
}


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @param  bool interactive - ob fehlerhafte Parameter interaktiv korrigiert werden k�nnen
 *
 * @return bool - ob die Konfiguration g�ltig ist
 */
bool ValidateConfiguration(bool interactive) {
   if (__STATUS_ERROR)
      return(false);

   bool reasonParameters = (UninitializeReason() == REASON_PARAMETERS);
   if (reasonParameters)
      interactive = true;


   // (1) GridSize
   if (reasonParameters) {
      if (GridSize != last.GridSize)             return(_false(ValidateConfig.HandleError("ValidateConfiguration(1)", "Cannot change GridSize of running strategy", interactive)));
      // TODO: Modify ist erlaubt, solange nicht die erste Sequenz gestartet wurde
   }
   if (GridSize < 1)                             return(_false(ValidateConfig.HandleError("ValidateConfiguration(2)", "Invalid GridSize = "+ GridSize, interactive)));


   // (2) LotSize
   if (reasonParameters) {
      if (NE(LotSize, last.LotSize))             return(_false(ValidateConfig.HandleError("ValidateConfiguration(3)", "Cannot change LotSize of running strategy", interactive)));
      // TODO: Modify ist erlaubt, solange nicht die erste Sequenz gestartet wurde
   }
   if (LE(LotSize, 0))                           return(_false(ValidateConfig.HandleError("ValidateConfiguration(4)", "Invalid LotSize = "+ NumberToStr(LotSize, ".+"), interactive)));
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT );
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT );
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                           return(_false(catch("ValidateConfiguration(5)   symbol=\""+ Symbol() +"\"", error)));
   if (LT(LotSize, minLot))                      return(_false(ValidateConfig.HandleError("ValidateConfiguration(6)", "Invalid LotSize = "+ NumberToStr(LotSize, ".+") +" (MinLot="+  NumberToStr(minLot, ".+" ) +")", interactive)));
   if (GT(LotSize, maxLot))                      return(_false(ValidateConfig.HandleError("ValidateConfiguration(7)", "Invalid LotSize = "+ NumberToStr(LotSize, ".+") +" (MaxLot="+  NumberToStr(maxLot, ".+" ) +")", interactive)));
   if (NE(MathModFix(LotSize, lotStep), 0))      return(_false(ValidateConfig.HandleError("ValidateConfiguration(8)", "Invalid LotSize = "+ NumberToStr(LotSize, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", interactive)));
   SS.LotSize();


   // (3) StartConditions: "@trend(**MA:7xD1[+1])"
   // --------------------------------------------
   if (!reasonParameters || StartConditions!=last.StartConditions) {
      start.trend.condition = false;

      string expr, elems[], key, value;
      double dValue;

      expr = StringToLower(StringTrim(StartConditions));
      if (StringLen(expr) == 0)                  return(_false(ValidateConfig.HandleError("ValidateConfiguration(9)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));

      if (StringGetChar(expr, 0) != '@')         return(_false(ValidateConfig.HandleError("ValidateConfiguration(10)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      if (Explode(expr, "(", elems, NULL) != 2)  return(_false(ValidateConfig.HandleError("ValidateConfiguration(11)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      if (!StringEndsWith(elems[1], ")"))        return(_false(ValidateConfig.HandleError("ValidateConfiguration(12)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      key = StringTrim(elems[0]);
      if (key != "@trend")                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(13)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      value = StringTrim(StringLeft(elems[1], -1));
      if (StringLen(value) == 0)                 return(_false(ValidateConfig.HandleError("ValidateConfiguration(14)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));

      if (Explode(value, ":", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(15)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      key   = StringToUpper(StringTrim(elems[0]));
      value = StringToUpper(elems[1]);
      // key="ALMA"
      if      (key == "SMA" ) start.trend.method = key;
      else if (key == "EMA" ) start.trend.method = key;
      else if (key == "SMMA") start.trend.method = key;
      else if (key == "LWMA") start.trend.method = key;
      else if (key == "ALMA") start.trend.method = key;
      else                                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(16)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      // value="7XD1[+2]"
      if (Explode(value, "+", elems, NULL) == 1) {
         start.trend.lag = 0;
      }
      else {
         value = StringTrim(elems[1]);
         if (!StringIsDigit(value))              return(_false(ValidateConfig.HandleError("ValidateConfiguration(17)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         start.trend.lag = StrToInteger(value);
         if (start.trend.lag < 0)                return(_false(ValidateConfig.HandleError("ValidateConfiguration(18)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         value = elems[0];
      }
      // value="7XD1"
      if (Explode(value, "X", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(19)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      elems[1]              = StringTrim(elems[1]);
      start.trend.timeframe = PeriodToId(elems[1]);
      if (start.trend.timeframe == -1)           return(_false(ValidateConfig.HandleError("ValidateConfiguration(20)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      value = StringTrim(elems[0]);
      if (!StringIsNumeric(value))               return(_false(ValidateConfig.HandleError("ValidateConfiguration(21)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      dValue = StrToDouble(value);
      if (dValue <= 0)                           return(_false(ValidateConfig.HandleError("ValidateConfiguration(22)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      if (NE(MathModFix(dValue, 0.5), 0))        return(_false(ValidateConfig.HandleError("ValidateConfiguration(23)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      elems[0] = NumberToStr(dValue, ".+");
      switch (start.trend.timeframe) {           // Timeframes > H1 auf H1 umrechnen, iCustom() soll unabh�ngig vom MA mit maximal PERIOD_H1 laufen
         case PERIOD_MN1:                        return(_false(ValidateConfig.HandleError("ValidateConfiguration(24)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         case PERIOD_H4 : { dValue *=   4; start.trend.timeframe = PERIOD_H1; break; }
         case PERIOD_D1 : { dValue *=  24; start.trend.timeframe = PERIOD_H1; break; }
         case PERIOD_W1 : { dValue *= 120; start.trend.timeframe = PERIOD_H1; break; }
      }
      start.trend.periods       = NormalizeDouble(dValue, 1);
      start.trend.timeframeFlag = PeriodFlag(start.trend.timeframe);
      start.trend.condition.txt = "@trend("+ start.trend.method +":"+ elems[0] +"x"+ elems[1] + ifString(!start.trend.lag, "", "+"+ start.trend.lag) +")";
      start.trend.condition     = true;

      StartConditions           = start.trend.condition.txt;
   }


   // (4) StopConditions: "@profit(1234)"
   // -----------------------------------
   if (!reasonParameters || StopConditions!=last.StopConditions) {
      stop.profitAbs.condition = false;

      // StopConditions parsen und validieren
      expr = StringToLower(StringTrim(StopConditions));
      if (StringLen(expr) == 0)                   return(_false(ValidateConfig.HandleError("ValidateConfiguration(25)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));

      if (StringGetChar(expr, 0) != '@')          return(_false(ValidateConfig.HandleError("ValidateConfiguration(26)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      if (Explode(expr, "(", elems, NULL) != 2)   return(_false(ValidateConfig.HandleError("ValidateConfiguration(27)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      if (!StringEndsWith(elems[1], ")"))         return(_false(ValidateConfig.HandleError("ValidateConfiguration(28)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      key = StringTrim(elems[0]);
      if (key != "@profit")                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(29)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      value = StringTrim(StringLeft(elems[1], -1));
      if (StringLen(value) == 0)                  return(_false(ValidateConfig.HandleError("ValidateConfiguration(30)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      if (!StringIsNumeric(value))                return(_false(ValidateConfig.HandleError("ValidateConfiguration(31)", "Invalid StopConditions = \""+ StopConditions +"\"", interactive)));
      dValue = StrToDouble(value);

      stop.profitAbs.value         = NormalizeDouble(dValue, 2);
      stop.profitAbs.condition.txt = key +"("+ NumberToStr(dValue, ".2") +")";
      stop.profitAbs.condition     = true;

      StopConditions               = stop.profitAbs.condition.txt;
   }


   // (5) __STATUS_INVALID_INPUT zur�cksetzen
   if (interactive)
      __STATUS_INVALID_INPUT = false;

   return(!last_error|catch("ValidateConfiguration(32)"));
}


/**
 * Exception-Handler f�r ung�ltige Input-Parameter. Je nach Situation wird der Fehler weitergereicht oder zur Korrektur aufgefordert.
 *
 * @param  string location    - Ort, an dem der Fehler auftrat
 * @param  string message     - Fehlermeldung
 * @param  bool   interactive - ob der Fehler interaktiv behandelt werden kann
 *
 * @return int - der resultierende Fehlerstatus
 */
int ValidateConfig.HandleError(string location, string message, bool interactive) {
   if (IsTesting())
      interactive = false;
   if (!interactive)
      return(catch(location +"   "+ message, ERR_INVALID_CONFIG_PARAMVALUE));

   if (__LOG) log(StringConcatenate(location, "   ", message), ERR_INVALID_INPUT);
   ForceSound("chord.wav");
   int button = ForceMessageBox(__NAME__ +" - "+ location, message, MB_ICONERROR|MB_RETRYCANCEL);

   __STATUS_INVALID_INPUT = true;

   if (button == IDRETRY)
      __STATUS_RELAUNCH_INPUT = true;

   return(NO_ERROR);
}


/**
 * Speichert Instanzdaten im Chart, soda� die Instanz nach einem Recompile oder Terminal-Restart daraus wiederhergestellt werden kann.
 *
 * @return int - Fehlerstatus
 */
int StoreStickyStatus() {
   if (!instance.id)
      return(NO_ERROR);                                                       // R�ckkehr, falls die Instanz nicht initialisiert ist

   string label = StringConcatenate(__NAME__, ".sticky.Instance.ID");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate(ifString(IsTest(), "T", ""), instance.id), 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS_INVALID_INPUT), 1);

   label = StringConcatenate(__NAME__, ".sticky.CANCELLED_BY_USER");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", last_error==ERR_CANCELLED_BY_USER), 1);

   return(catch("StoreStickyStatus()"));
}


/**
 * Restauriert im Chart gespeicherte Instanzdaten.
 *
 * @return bool - ob Daten einer Instanz gefunden wurden
 */
bool RestoreStickyStatus() {
   string label, strValue;
   bool   idFound;

   label = StringConcatenate(__NAME__, ".sticky.Instance.ID");
   if (ObjectFind(label) == 0) {
      strValue = StringToUpper(StringTrim(ObjectDescription(label)));
      if (StringLeft(strValue, 1) == "T") {
         strValue        = StringRight(strValue, -1);
         instance.isTest = true;
      }
      if (!StringIsDigit(strValue))
         return(_false(catch("RestoreStickyStatus(1)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
      int iValue = StrToInteger(strValue);
      if (iValue <= 0)
         return(_false(catch("RestoreStickyStatus(2)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));

      instance.id = iValue; SS.InstanceId();
      idFound     = true;
      SetCustomLog(instance.id, NULL);

      label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(3)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS_INVALID_INPUT = StrToInteger(strValue) != 0;
      }

      label = StringConcatenate(__NAME__, ".sticky.CANCELLED_BY_USER");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(4)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         if (StrToInteger(strValue) != 0)
            SetLastError(ERR_CANCELLED_BY_USER);
      }
   }

   return(idFound && !(last_error|catch("RestoreStickyStatus(13)")));
}


/**
 * L�scht alle im Chart gespeicherten Instanzdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearStickyStatus() {
   string label, prefix=StringConcatenate(__NAME__, ".sticky.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearStickyStatus()"));
}


/**
 * Zeigt den aktuellen Status der Sequenz an.
 *
 * @return int - Fehlerstatus
 */
int ShowStatus() {
   if (!IsChart)
      return(NO_ERROR);

   string str.error, l.msg, s.msg;

   if      (__STATUS_INVALID_INPUT) str.error = StringConcatenate("  [", ErrorDescription(ERR_INVALID_INPUT), "]");
   else if (__STATUS_ERROR        ) str.error = StringConcatenate("  [", ErrorDescription(last_error       ), "]");

   switch (l.sequence.status) {
      case STATUS_UNINITIALIZED:
      case STATUS_WAITING:       l.msg =                                        " waiting";                                                 break;
      case STATUS_STARTING:      l.msg = StringConcatenate("  ", l.sequence.id, " starting at level ",    l.level, "  (", l.maxLevel, ")"); break;
      case STATUS_PROGRESSING:   l.msg = StringConcatenate("  ", l.sequence.id, " progressing at level ", l.level, "  (", l.maxLevel, ")"); break;
      case STATUS_STOPPING:      l.msg = StringConcatenate("  ", l.sequence.id, " stopping at level ",    l.level, "  (", l.maxLevel, ")"); break;
      case STATUS_STOPPED:       l.msg = StringConcatenate("  ", l.sequence.id, " stopped at level ",     l.level, "  (", l.maxLevel, ")"); break;
      default:
         return(catch("ShowStatus(1)   illegal long sequence status = "+ l.sequence.status, ERR_RUNTIME_ERROR));
   }

   switch (s.sequence.status) {
      case STATUS_UNINITIALIZED:
      case STATUS_WAITING:       s.msg =                                        " waiting";                                                 break;
      case STATUS_STARTING:      s.msg = StringConcatenate("  ", s.sequence.id, " starting at level ",    s.level, "  (", s.maxLevel, ")"); break;
      case STATUS_PROGRESSING:   s.msg = StringConcatenate("  ", s.sequence.id, " progressing at level ", s.level, "  (", s.maxLevel, ")"); break;
      case STATUS_STOPPING:      s.msg = StringConcatenate("  ", s.sequence.id, " stopping at level ",    s.level, "  (", s.maxLevel, ")"); break;
      case STATUS_STOPPED:       s.msg = StringConcatenate("  ", s.sequence.id, " stopped at level ",     s.level, "  (", s.maxLevel, ")"); break;
      default:
         return(catch("ShowStatus(2)   illegal short sequence status = "+ s.sequence.status, ERR_RUNTIME_ERROR));
   }

   string msg = StringConcatenate(__NAME__, str.error,                                   NL,
                                                                                         NL,
                                  "Grid:           ", GridSize, " pip",                  NL,
                                  "LotSize:       ",  str.LotSize,                       NL,
                                  "Start:          ", StartConditions,                   NL,
                                  "Stop:          ",  StopConditions,                    NL,
                                  "Profit/Loss:   ",  str.totalPL, str.plStatistics,     NL,
                                                                                         NL,
                                  "LONG:       ",     l.msg,                             NL,
                                  "Stops:         ",  str.l.stops, str.l.stopsPL,        NL,
                                  "Profit/Loss:   ",  str.l.totalPL, str.l.plStatistics, NL,
                                                                                         NL,
                                  "SHORT:     ",      s.msg,                             NL,
                                  "Stops:         ",  str.s.stops, str.s.stopsPL,        NL,
                                  "Profit/Loss:   ",  str.s.totalPL, str.s.plStatistics, NL);

   // 3 Zeilen Abstand nach oben f�r Instrumentanzeige und ggf. vorhandene Legende
   Comment(StringConcatenate(NL, NL, NL, msg));
   if (__WHEREAMI__ == FUNC_INIT)
      WindowRedraw();

   return(catch("ShowStatus(3)"));
}


/**
 * ShowStatus(): Aktualisiert die Anzeige der Instanz-ID in der Titelzeile des Strategy Testers.
 */
void SS.InstanceId() {
   if (IsTesting()) {
      if (!SetWindowTextA(GetTesterWindow(), StringConcatenate("Tester - SR-Dual.", instance.id)))
         catch("SS.InstanceId()->user32::SetWindowTextA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
   }
}


/**
 * ShowStatus(): Aktualisiert die String-Repr�sentation von LotSize.
 */
void SS.LotSize() {
   if (!IsChart)
      return;

   str.LotSize = StringConcatenate(NumberToStr(LotSize, ".+"), " lot = ", DoubleToStr(GridSize * PipValue(LotSize) - commission, 2), "/stop");
}


/**
 * Ob die Instanz im Tester erzeugt wurde, also eine Test-Instanz ist. Der Aufruf dieser Funktion in Online-Charts mit einer im Tester
 * erzeugten Instanz gibt daher ebenfalls TRUE zur�ck.
 *
 * @return bool
 */
bool IsTest() {
   return(instance.isTest || IsTesting());
}


/**
 * Unterdr�ckt unn�tze Compilerwarnungen.
 */
void DummyCalls() {
   CheckTrendChange(NULL, NULL, NULL, NULL, NULL, NULL, iNull);
   ConfirmTick1Trade(NULL, NULL);
   CreateEventId();
   CreateSequenceId();
   FindChartSequences(sNulls, iNulls);
   IsSequenceStatus(NULL);
   StatusToStr(NULL);
}