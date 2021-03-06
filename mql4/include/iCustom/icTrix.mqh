/**
 * Load the "Trix" indicator and return an indicator value.
 *
 * @param  int    timeframe       - timeframe to load the indicator (NULL: the current timeframe)
 * @param  int    emaPeriods      - indicator parameter
 * @param  string emaAppliedPrice - indicator parameter
 * @param  int    iBuffer         - indicator buffer index of the value to return
 * @param  int    iBar            - bar index of the value to return
 *
 * @return double - indicator value or NULL in case of errors
 */
double icTrix(int timeframe, int emaPeriods, string emaAppliedPrice, int iBuffer, int iBar) {
   static int lpSuperContext = 0; if (!lpSuperContext)
      lpSuperContext = GetIntsAddress(__ExecutionContext);

   double value = iCustom(NULL, timeframe, "Trix",
                          emaPeriods,                                      // int    EMA.Periods
                          emaAppliedPrice,                                 // string EMA.AppliedPrice

                          DodgerBlue,                                      // color  MainLine.Color
                          1,                                               // int    MainLine.Width

                          LimeGreen,                                       // color  Histogram.Color.Upper
                          Red,                                             // color  Histogram.Color.Lower
                          2,                                               // int    Histogram.Style.Width

                          -1,                                              // int    Max.Values

                          "",                                              // string _____________________
                          lpSuperContext,                                  // int    __SuperContext__

                          iBuffer, iBar);

   int error = GetLastError();
   if (error != NO_ERROR) {
      if (error != ERS_HISTORY_UPDATE)
         return(!catch("icTrix(1)", error));
      warn("icTrix(2)  "+ PeriodDescription(ifInt(!timeframe, Period(), timeframe)) +" (tick="+ Tick +")", ERS_HISTORY_UPDATE);
   }                                                                       // TODO: check number of loaded bars

   error = __ExecutionContext[I_EC.mqlError];                              // TODO: synchronize execution contexts
   if (error != NO_ERROR)
      return(!SetLastError(error));
   return(value);
}
