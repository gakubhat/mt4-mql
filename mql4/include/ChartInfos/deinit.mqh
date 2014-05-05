/**
 * Deinitialisierung
 *
 * @return int - Fehlerstatus
 */
int onDeinit() {
   RemoveChartObjects();
   QC.StopChannels();
   return(last_error);
}


/**
 * außerhalb iCustom(): bei Parameteränderung
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitParameterChange() {
   // Remote-Positionsdaten in Library zwischenspeichern
   int error = ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data);
   if (IsError(error))
      return(SetLastError(error));
   return(NO_ERROR);
}


/**
 * außerhalb iCustom(): bei Symbol- oder Timeframewechsel
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitChartChange() {
   // Pending-Orders in Library zwischenspeichern
   int error = ChartInfos.CopyLfxOrders(true, lfxOrders);
   if (IsError(error))
      return(SetLastError(error));

   // Remote-Positionsdaten in Library zwischenspeichern
   error = ChartInfos.CopyRemotePositions(true, remote.position.tickets, remote.position.types, remote.position.data);
   if (IsError(error))
      return(SetLastError(error));
   return(NO_ERROR);
}


/**
 * außerhalb iCustom(): Indikator von Hand entfernt oder Chart geschlossen
 * innerhalb iCustom(): in allen deinit()-Fällen
 *
 * @return int - Fehlerstatus
 *
int onDeinitRemove() {
   return(NO_ERROR);
}


/**
 * außerhalb iCustom(): bei Recompilation
 * innerhalb iCustom(): nie
 *
 * @return int - Fehlerstatus
 */
int onDeinitRecompile() {
   // TODO: Remote-Positionsdaten irgendwo zwischenspeichern (QuickChannel ?)
   return(NO_ERROR);
}


/**
 * Deinitialisierung Postprocessing
 *
 * @return int - Fehlerstatus
 *
int afterDeinit() {
   return(NO_ERROR);
}
*/
