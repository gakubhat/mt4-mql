/**
 * Datentypen und Speichergr��en in C, Win32-API (16-bit word size) und MQL:
 * =========================================================================
 *
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * |         |         |        |        |        |                 |              max(hex) |            signed range(dec) |            unsigned range(dec) |       C        |        Win32        |      MQL       |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * |         |         |        |        |  1 bit |                 |                  0x01 |                        0 - 1 |                            0-1 |                |                     |                |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * |         |         |        | 1 byte |  8 bit | 2 nibbles       |                  0xFF |                   -128 - 127 |                          0-255 |                |      BYTE,CHAR      |                |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * |         |         | 1 word | 2 byte | 16 bit | HIBYTE + LOBYTE |                0xFFFF |             -32.768 - 32.767 |                       0-65.535 |     short      |   SHORT,WORD,WCHAR  |                |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * |         | 1 dword | 2 word | 4 byte | 32 bit | HIWORD + LOWORD |            0xFFFFFFFF |             -2.147.483.648 - |              0 - 4.294.967.295 | int,long,float | BOOL,INT,LONG,DWORD |  bool,char,int |
 * |         |         |        |        |        |                 |                       |              2.147.483.647   |                                |                |    WPARAM,LPARAM    | color,datetime |
 * |         |         |        |        |        |                 |                       |                              |                                |                | (handles, pointers) |                |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 * | 1 qword | 2 dword | 4 word | 8 byte | 64 bit |                 | 0xFFFFFFFF 0xFFFFFFFF | -9.223.372.036.854.775.808 - | 0 - 18.446.744.073.709.551.616 |     double     |  LONGLONG,DWORDLONG |  double,string | MQL-double: 53 bit Mantisse (Integers bis 53 bit ohne Genauigkeitsverlust)
 * |         |         |        |        |        |                 |                       |  9.223.372.036.854.775.807   |                                |                |                     |                |
 * +---------+---------+--------+--------+--------+-----------------+-----------------------+------------------------------+--------------------------------+----------------+---------------------+----------------+
 */
#property library
#property stacksize  32768


#include <stddefine.mqh>
#include <timezones.mqh>
#include <win32api.mqh>

#import "stdlib2.ex4"
   int GetPrivateProfileKeys.2(string fileName, string section, string keys[]);
#import


/**
 * Initialisierung der Library beim Laden in den Speicher
 *
 * @return int - Fehlercode
 */
int init() {
   __SCRIPT__ = WindowExpertName();
   return(NO_ERROR);
}


/**
 * Deinitialisierung der Library beim Entladen aus dem Speicher
 *
 * @return int - Fehlercode
 */
int deinit() {
   return(NO_ERROR);
}


/**
 * Wird vom Compiler ben�tigt, jedoch niemals aufgerufen.
 *
 * @return int - Fehlercode
 */
int onStart() {
   return(catch("onStart()", ERR_WRONG_JUMP));
}


/**
 * Wird vom Compiler ben�tigt, jedoch niemals aufgerufen.
 *
 * @return int - Fehlercode
 */
int onTick() {
   return(catch("onTick()", ERR_WRONG_JUMP));
}


/**
 * Initialisierung interner Variablen der Library.
 *
 * @param  int    scriptType         - Typ des aufrufenden Programms
 * @param  string scriptName         - Name des aufrufenden Programms
 * @param  int    initFlags          - optionale, zus�tzlich durchzuf�hrende Initialisierungstasks: [IT_CHECK_TIMEZONE_CONFIG | IT_RESET_BARS_ON_HIST_UPDATE]
 * @param  int    uninitializeReason - der letzte UninitializeReason() des aufrufenden Programms
 *
 * @return int - Fehlercode
 */
int stdlib_onInit(int scriptType, string scriptName, int initFlags, int uninitializeReason) {
   __TYPE__   = scriptType;
   __SCRIPT__ = StringConcatenate(scriptName, "::", WindowExpertName());

   PipDigits   = Digits & (~1);
   PipPoint    = MathPow(10, Digits-PipDigits) +0.1;                 //(int) double
   PipPoints   = PipPoint;
   Pip         = 1/MathPow(10, PipDigits);
   Pips        = Pip;
   PriceFormat = StringConcatenate(".", PipDigits, ifString(Digits==PipDigits, "", "'"));
   TickSize    = MarketInfo(Symbol(), MODE_TICKSIZE);

   int error = GetLastError();
   if (error == ERR_UNKNOWN_SYMBOL) {                                // Symbol nicht subscribed (Start, Account- oder Templatewechsel)
      last_error = ERR_TERMINAL_NOT_YET_READY;                       // (das Symbol kann sp�ter evt. noch "auftauchen")
   }
   else if (IsError(error)) {
      catch("stdlib_onInit(1)", error);
   }
   else if (TickSize < 0.00000001) {
      catch("stdlib_onInit(2)   TickSize = "+ NumberToStr(TickSize, ".+"), ERR_INVALID_MARKETINFO);
   }

   if (last_error == NO_ERROR) {
      if (initFlags & IT_CHECK_TIMEZONE_CONFIG != 0)
         GetServerTimezone();
   }

   if (last_error == NO_ERROR) {
      if (IsExpert()) {                                              // nach Neuladen eines EA's den Orderkontext der Library ausdr�cklich zur�cksetzen
         int reasons[] = { REASON_REMOVE, REASON_CHARTCLOSE, REASON_ACCOUNT, REASON_APPEXIT };
         if (IntInArray(uninitializeReason, reasons))
            OrderSelect(0, SELECT_BY_TICKET);
      }
   }

   // Es kann vorkommen, da� GetTerminalWindow() zu einem Zeitpunkt benutzt wird, an dem das Terminal-Hauptfenster nicht mehr existiert (z.B. im Tester
   // bei Shutdown). Da sich das Handle w�hrend der Laufzeit der Terminal-Instanz nicht �ndert und es intern gecacht wird, wird die Funktion sofort hier
   // beim Laden der Library aufgerufen. Analog dazu ebenfalls das Handle des UI-Threads, dessen Ermittlung auf ein g�ltiges Hauptfenster-Handle angewiesen ist.
   if (last_error == NO_ERROR)
      GetTerminalWindow();

   if (last_error == NO_ERROR)
      GetUIThreadId();

   return(last_error);
}


/**
 * Informiert die Library �ber das Aufrufen der start()-Funktion des laufenden Programms. Erm�glicht den Library-Funktionen zu erkennen, ob der Aufruf w�hrend desselben
 * oder eines neuen Ticks erfolgt (z.B. in EventListenern).
 *
 * @param  int ticks       - Tickz�hler (synchronisiert den Tickz�hler des aufrufenden Scripts und den der Library)
 * @param  int validBars   - Anzahl der seit dem letzten Tick unver�nderten Bars oder -1, wenn die Funktion nicht aus einem Indikator aufgerufen wird
 * @param  int changedBars - Anzahl der seit dem letzten Tick ge�nderten Bars oder -1, wenn die Funktion nicht aus einem Indikator aufgerufen wird
 *
 * @return int - Fehlercode
 */
int stdlib_onStart(int ticks, int validBars, int changedBars) {
   Tick        = ticks;                 // der konkrete Wert hat keine Bedeutung
   Ticks       = Tick;
   ValidBars   = validBars;
   ChangedBars = changedBars;
   return(NO_ERROR);
}


/**
 * Gibt den letzten in dieser Library aufgetretenen Fehler zur�ck. Der Aufruf dieser Funktion setzt den internen Fehlercode zur�ck.
 *
 * @return int - Fehlercode
 */
int stdlib_GetLastError() {
   int error = last_error;
   last_error = NO_ERROR;
   return(error);
}


/**
 * Gibt den letzten in dieser Library aufgetretenen Fehler zur�ck. Der Aufruf dieser Funktion setzt den internen Fehlercode *nicht* zur�ck.
 *
 * @return int - Fehlercode
 */
int stdlib_PeekLastError() {
   return(last_error);
}


/**
 * Ob der Indikator im Tester ausgef�hrt wird.
 *
 * @return bool
 */
bool iIsTesting() {
   if (IsIndicator())
      return(GetCurrentThreadId() != GetUIThreadId());
   return(false);
}


/**
 * Gibt den Offset der angegebenen GMT-Zeit zu FXT (Forex Standard Time) zur�ck (entgegengesetzter Wert des Offsets von FXT zu GMT).
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetGMTToFXTOffset(datetime gmtTime) {
   if (gmtTime < 0) {
      catch("GetGMTToFXTOffset()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   int offset, year = TimeYear(gmtTime)-1970;

   // FXT                                       GMT+0200,GMT+0300
   if      (gmtTime < FXT_transitions[year][2]) offset = -2 * HOURS;
   else if (gmtTime < FXT_transitions[year][3]) offset = -3 * HOURS;
   else                                         offset = -2 * HOURS;

   return(offset);
}


/**
 * Gibt den Offset der angegebenen Serverzeit zu FXT (Forex Standard Time) zur�ck (positive Werte f�r �stlich von FXT liegende Zeitzonen).
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetServerToFXTOffset(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0) {
      catch("GetServerToFXTOffset()   invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(EMPTY_VALUE);

   // schnelle R�ckkehr, wenn der Tradeserver unter FXT l�uft
   if (zone == "FXT")
      return(0);

   // Offset Server zu GMT
   int offset1;
   if (zone != "GMT") {
      offset1 = GetServerToGMTOffset(serverTime);
      if (offset1 == EMPTY_VALUE)
         return(EMPTY_VALUE);
   }

   // Offset GMT zu FXT
   int offset2 = GetGMTToFXTOffset(serverTime - offset1);
   if (offset2 == EMPTY_VALUE)
      return(EMPTY_VALUE);

   return(offset1 + offset2);
}


/**
 * Gibt den Offset der angegebenen Serverzeit zu GMT (Greenwich Mean Time) zur�ck (positive Werte f�r �stlich von Greenwich liegende Zeitzonen).
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetServerToGMTOffset(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0) {
      catch("GetServerToGMTOffset(1)   invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(EMPTY_VALUE);

   int offset, year = TimeYear(serverTime)-1970;

   if (zone == "Europe/Minsk") {                    // GMT+0200,GMT+0300
      if      (serverTime < EMST_transitions[year][0]) offset = 2 * HOURS;
      else if (serverTime < EMST_transitions[year][1]) offset = 3 * HOURS;
      else                                             offset = 2 * HOURS;
   }
   else if (zone == "Europe/Kiev") {                // GMT+0200,GMT+0300
      if      (serverTime < EEST_transitions[year][0]) offset = 2 * HOURS;
      else if (serverTime < EEST_transitions[year][1]) offset = 3 * HOURS;
      else                                             offset = 2 * HOURS;
   }
   else if (zone == "FXT") {                        // GMT+0200,GMT+0300
      if      (serverTime < FXT_transitions[year][0])  offset = 2 * HOURS;
      else if (serverTime < FXT_transitions[year][1])  offset = 3 * HOURS;
      else                                             offset = 2 * HOURS;
   }
   else if (zone == "Europe/Berlin") {              // GMT+0100,GMT+0200
      if      (serverTime < CEST_transitions[year][0]) offset = 1 * HOURS;
      else if (serverTime < CEST_transitions[year][1]) offset = 2 * HOURS;
      else                                             offset = 1 * HOURS;
   }
   else if (zone == "GMT") {                        // GMT+0000
                                                       offset = 0;
   }
   else if (zone == "Europe/London") {              // GMT+0000,GMT+0100
      if      (serverTime < BST_transitions[year][0])  offset = 0;
      else if (serverTime < BST_transitions[year][1])  offset = 1 * HOUR;
      else                                             offset = 0;
   }
   else if (zone == "America/New_York") {           // GMT-0500,GMT-0400
      if      (serverTime < EDT_transitions[year][0])  offset = -5 * HOURS;
      else if (serverTime < EDT_transitions[year][1])  offset = -4 * HOURS;
      else                                             offset = -5 * HOURS;
   }
   else {
      catch("GetServerToGMTOffset(2)  unknown timezone \""+ zone +"\"", ERR_INVALID_TIMEZONE_CONFIG);
      return(EMPTY_VALUE);
   }

   return(offset);
}


/**
 * Dropin-Ersatz f�r MessageBox()
 *
 * Zeigt eine MessageBox an, auch wenn dies im aktuellen Kontext des Terminals nicht unterst�tzt wird (z.B. im Tester oder in Indikatoren).
 *
 * @param string message
 * @param string caption
 * @param int    flags
 *
 * @return int - Tastencode
 */
int ForceMessageBox(string message, string caption, int flags=MB_OK) {
   int button;

   if (!IsTesting() && !IsIndicator()) button = MessageBox(message, caption, flags);
   else                                button = MessageBoxA(NULL, message, caption, flags);  // TODO: hWndOwner fixen

   return(button);
}


/**
 * Dropin-Ersatz f�r PlaySound()
 *
 * Spielt ein Soundfile ab, auch wenn dies im aktuellen Kontext des Terminals nicht unterst�tzt wird (z.B. im Tester).
 *
 * @param string soundfile
 */
void ForceSound(string soundfile) {
   if (!IsTesting()) {
      PlaySound(soundfile);
   }
   else {
      soundfile = StringConcatenate(TerminalPath(), "\\sounds\\", soundfile);
      PlaySoundA(soundfile, NULL, SND_FILENAME|SND_ASYNC);
   }
}


/**
 * Gibt die Namen aller Abschnitte einer ini-Datei zur�ck.
 *
 * @param  string fileName - Name der ini-Datei (wenn NULL, wird WIN.INI durchsucht)
 * @param  string names[]  - Array zur Aufnahme der gefundenen Abschnittsnamen
 *
 * @return int - Anzahl der gefundenen Abschnitte oder -1, falls ein Fehler auftrat
 */
int GetPrivateProfileSectionNames(string fileName, string names[]) {
   int bufferSize = 200;
   int buffer[]; InitializeBuffer(buffer, bufferSize);

   int chars = GetPrivateProfileSectionNamesA(buffer, bufferSize, fileName);

   // zu kleinen Buffer abfangen
   while (chars == bufferSize-2) {
      bufferSize <<= 1;
      InitializeBuffer(buffer, bufferSize);
      chars = GetPrivateProfileSectionNamesA(buffer, bufferSize, fileName);
   }

   int length;

   if (chars == 0) length = ArrayResize(names, 0);                   // keine Sections gefunden (File nicht gefunden oder leer)
   else            length = ExplodeStrings(buffer, names);

   if (catch("GetPrivateProfileSectionNames") != NO_ERROR)
      return(-1);
   return(length);
}


/**
 * Gibt die Namen aller Eintr�ge eines Abschnitts einer ini-Datei zur�ck.
 *
 * @param  string fileName - Name der ini-Datei
 * @param  string section  - Name des Abschnitts
 * @param  string keys[]   - Array zur Aufnahme der gefundenen Schl�sselnamen
 *
 * @return int - Anzahl der gefundenen Schl�ssel oder -1, falls ein Fehler auftrat
 */
int GetPrivateProfileKeys(string fileName, string section, string keys[]) {
   return(GetPrivateProfileKeys.2(fileName, section, keys));
}


/**
 * L�scht einen einzelnen Eintrag einer ini-Datei.
 *
 * @param  string fileName - Name der ini-Datei
 * @param  string section  - Abschnitt des Eintrags
 * @param  string key      - Name des zu l�schenden Eintrags
 *
 * @return int - Fehlerstatus
 */
int DeletePrivateProfileKey(string fileName, string section, string key) {
   string sNull;

   if (!WritePrivateProfileStringA(section, key, sNull, fileName))
      return(catch("DeletePrivateProfileKey() ->kernel32::WritePrivateProfileStringA(section=\""+ section +"\", key=\""+ key +"\", value=NULL, fileName=\""+ fileName +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));

   return(NO_ERROR);
}


/**
 * Gibt den Versionsstring des Terminals zur�ck.
 *
 * @return string - Version oder Leerstring, wenn ein Fehler auftrat
 */
string GetTerminalVersion() {
   int    bufferSize = MAX_PATH;
   string filename[]; InitializeStringBuffer(filename, bufferSize);
   int chars = GetModuleFileNameA(NULL, filename[0], bufferSize);
   if (chars == 0)
      return(_empty(catch("GetTerminalVersion(1) ->kernel32::GetModuleFileNameA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   int iNull[];
   int infoSize = GetFileVersionInfoSizeA(filename[0], iNull);
   if (infoSize == 0)
      return(_empty(catch("GetTerminalVersion(2) ->version::GetFileVersionInfoSizeA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   int infoBuffer[]; InitializeBuffer(infoBuffer, infoSize);
   if (!GetFileVersionInfoA(filename[0], 0, infoSize, infoBuffer))
      return(_empty(catch("GetTerminalVersion(3) ->version::GetFileVersionInfoA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   string infoString = BufferToStr(infoBuffer);                      // Strings im Buffer sind Unicode-Strings
   //infoString = Е4���V�S�_�V�E�R�S�I�O�N�_�I�N�F�O�����������������ᅅ�����ᅅ�?���������������������������0�����S�t�r�i�n�g�F�i�l�e�I�n�f�o���������0�0�0�0�0�4�b�0���L�����C�o�m�m�e�n�t�s���h�t�t�p�:�/�/�w�w�w�.�m�e�t�a�q�u�o�t�e�s�.�n�e�t���T�����C�o�m�p�a�n�y�N�a�m�e�����M�e�t�a�Q�u�o�t�e�s� �S�o�f�t�w�a�r�e� �C�o�r�p�.���>�����F�i�l�e�D�e�s�c�r�i�p�t�i�o�n�����M�e�t�a�T�r�a�d�e�r�����6�����F�i�l�e�V�e�r�s�i�o�n�����4�.�0�.�0�.�2�2�5�������6�����I�n�t�e�r�n�a�l�N�a�m�e���M�e�t�a�T�r�a�d�e�r�������1���L�e�g�a�l�C�o�p�y�r�i�g�h�t���C�o�p�y�r�i�g�h�t� ��� �2�0�0�1�-�2�0�0�9�,� �M�e�t�a�Q�u�o�t�e�s� �S�o�f�t�w�a�r�e� �C�o�r�p�.�����@�����L�e�g�a�l�T�r�a�d�e�m�a�r�k�s�����M�e�t�a�T�r�a�d�e�r�����(�����O�r�i�g�i�n�a�l�F�i�l�e�n�a�m�e��� �����P�r�i�v�a�t�e�B�u�i�l�d���6�����P�r�o�d�u�c�t�N�a�m�e�����M�e�t�a�T�r�a�d�e�r�����:�����P�r�o�d�u�c�t�V�e�r�s�i�o�n���4�.�0�.�0�.�2�2�5������� �����S�p�e�c�i�a�l�B�u�i�l�d���D�����V�a�r�F�i�l�e�I�n�f�o�����$�����T�r�a�n�s�l�a�t�i�o�n���������FE2X����������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������������
   string Z                  = CharToStr(PLACEHOLDER_ZERO_CHAR);
   string C                  = CharToStr(PLACEHOLDER_CTL_CHAR);
   string key.ProductVersion = StringConcatenate(C,Z,"P",Z,"r",Z,"o",Z,"d",Z,"u",Z,"c",Z,"t",Z,"V",Z,"e",Z,"r",Z,"s",Z,"i",Z,"o",Z,"n",Z,Z);
   string key.FileVersion    = StringConcatenate(C,Z,"F",Z,"i",Z,"l",Z,"e",Z,"V",Z,"e",Z,"r",Z,"s",Z,"i",Z,"o",Z,"n",Z,Z);

   int pos = StringFind(infoString, key.ProductVersion);             // zuerst nach ProductVersion suchen...
   if (pos != -1) {
      pos += StringLen(key.ProductVersion);
   }
   else {
      debug("GetTerminalVersion()->GetFileVersionInfoA()   ProductVersion not found");
      pos = StringFind(infoString, key.FileVersion);                 // ...dann nach FileVersion
      if (pos == -1) {
         //debug("GetTerminalVersion()->GetFileVersionInfoA()   FileVersion not found");
         return(_empty(catch("GetTerminalVersion(4)   terminal version info not found", ERR_RUNTIME_ERROR)));
      }
      pos += StringLen(key.FileVersion);
   }

   // erstes Nicht-NULL-Byte nach dem Version-Key finden
   for (; pos < infoSize; pos++) {
      if (BufferGetChar(infoBuffer, pos) != 0x00)
         break;
   }
   if (pos == infoSize) {
      //debug("GetTerminalVersion()   no non-NULL byte after version key found");
      return(_empty(catch("GetTerminalVersion(5)   terminal version info value not found", ERR_RUNTIME_ERROR)));
   }

   // Unicode-String auslesen und konvertieren
   string version = BufferWCharsToStr(infoBuffer, pos/4, (infoSize-pos)/4);

   if (IsError(catch("GetTerminalVersion(6)")))
      return("");
   return(version);
}


/**
 * Gibt die Build-Version des Terminals zur�ck.
 *
 * @return int - Build-Version oder 0, wenn ein Fehler auftrat
 */
int GetTerminalBuild() {
   string version = GetTerminalVersion();
   if (StringLen(version) == 0)
      return(0);

   string strings[];

   int size = Explode(version, ".", strings);
   if (size != 4)
      return(_ZERO(catch("GetTerminalBuild(1)   unexpected terminal version format = \""+ version +"\"", ERR_RUNTIME_ERROR)));

   if (!StringIsDigit(strings[size-1]))
      return(_ZERO(catch("GetTerminalBuild(2)   unexpected terminal version format = \""+ version +"\"", ERR_RUNTIME_ERROR)));

   int build = StrToInteger(strings[size-1]);

   if (IsError(catch("GetTerminalBuild(3)")))
      return(0);
   return(build);
}


/**
 * Initialisiert einen Buffer zur Aufnahme von Bytes in der gew�nschten L�nge. Byte-Buffer k�nnen in MQL nur �ber Integer-Arrays dargestellt werden.
 *
 * @param  int buffer[] - das f�r den Buffer zu verwendende Integer-Array
 * @param  int length   - L�nge des Buffers in Bytes
 *
 * @return int - Fehlerstatus
 */
int InitializeBuffer(int buffer[], int length) {
   if (ArrayDimension(buffer) > 1)
      return(catch("InitializeBuffer(1)  invalid parameter buffer, too many dimensions: "+ ArrayDimension(buffer), ERR_INCOMPATIBLE_ARRAYS));
   if (length < 0)
      return(catch("InitializeBuffer(2)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE));

   if (length & 0x03 == 0) length = length >> 2;                     // length & 0x03 = length % 4
   else                    length = length >> 2 + 1;

   if (ArraySize(buffer) != length)
      ArrayResize(buffer, length);
   ArrayInitialize(buffer, 0);

   return(catch("InitializeBuffer(3)"));
}


/**
 * Initialisiert einen Buffer zur Aufnahme eines Strings der gew�nschten L�nge.
 *
 * @param  string buffer[] - das f�r den Buffer zu verwendende String-Array
 * @param  int    length   - L�nge des Buffers in Zeichen
 *
 * @return int - Fehlerstatus
 */
int InitializeStringBuffer(string& buffer[], int length) {
   if (ArrayDimension(buffer) > 1)
      return(catch("InitializeStringBuffer(1)  invalid parameter buffer, too many dimensions: "+ ArrayDimension(buffer), ERR_INCOMPATIBLE_ARRAYS));
   if (length < 0)
      return(catch("InitializeStringBuffer(2)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE));

   if (ArraySize(buffer) == 0)
      ArrayResize(buffer, 1);

   buffer[0] = CreateString(length);

   return(catch("InitializeStringBuffer(3)"));
}


/**
 * Erzeugt einen neuen String der gew�nschten L�nge.
 *
 * @param  int length - L�nge
 *
 * @return string
 */
string CreateString(int length) {
   if (length < 0)
      return(_empty(catch("CreateString()  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE)));

   string newStr = StringConcatenate(MAX_STRING_LITERAL, "");        // Um immer einen neuen String zu erhalten (MT4-Zeigerproblematik), darf Ausgangsbasis kein Literal sein.
   int strLen = StringLen(newStr);                                   // Daher wird auch beim Initialisieren StringConcatenate() verwendet (siehe MQL.doc).

   while (strLen < length) {
      newStr = StringConcatenate(newStr, MAX_STRING_LITERAL);
      strLen = StringLen(newStr);
   }

   if (strLen != length)
      newStr = StringSubstr(newStr, 0, length);
   return(newStr);
}


/**
 * Gibt die Strategy-ID einer MagicNumber zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Strategy-ID
 */
int StrategyId(int magicNumber) {
   return(magicNumber >> 22);                                        // 10 bit (Bit 23-32) => Bereich 0-1023, aber immer gr��er 100
}


/**
 * Gibt die Currency-ID der MagicNumber einer LFX-Position zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Currency-ID
 */
int LFX.CurrencyId(int magicNumber) {
   return(magicNumber >> 18 & 0xF);                                  // 4 bit (Bit 19-22) => Bereich 0-15
}


/**
 * Gibt die W�hrung der MagicNumber einer LFX-Position zur�ck.
 *
 * @param  int magicNumber
 *
 * @return string - W�hrungsk�rzel ("EUR", "GBP", "USD" etc.)
 */
string LFX.Currency(int magicNumber) {
   return(GetCurrency(LFX.CurrencyId(magicNumber)));
}


/**
 * Gibt den Wert des Position-Counters der MagicNumber einer LFX-Position zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Counter
 */
int LFX.Counter(int magicNumber) {
   return(magicNumber & 0xF);                                        // 4 bit (Bit 1-4 ) => Bereich 0-15
}


/**
 * Gibt den Units-Wert der MagicNumber einer LFX-Position zur�ck.
 *
 * @param  int magicNumber
 *
 * @return double - Units
 */
double LFX.Units(int magicNumber) {
   return(magicNumber >> 13 & 0x1F / 10.0);                          // 5 bit (Bit 14-18) => Bereich 0-31
}


/**
 * Gibt die Instanz-ID der MagicNumber einer LFX-Position zur�ck.
 *
 * @param  int magicNumber
 *
 * @return int - Instanz-ID
 */
int LFX.Instance(int magicNumber) {
   return(magicNumber >> 4 & 0x1FF);                                 // 9 bit (Bit 5-13) => Bereich 0-511
}


/**
 * Gibt den vollst�ndigen Dateinamen der lokalen Konfigurationsdatei zur�ck.
 * Existiert die Datei nicht, wird sie angelegt.
 *
 * @return string - Dateiname
 */
string GetLocalConfigPath() {
   static string cache.localConfigPath[];                            // timeframe-�bergreifenden String-Cache einrichten (ohne Initializer) ...
   if (ArraySize(cache.localConfigPath) == 0) {
      ArrayResize(cache.localConfigPath, 1);
      cache.localConfigPath[0] = "";
   }
   else if (StringLen(cache.localConfigPath[0]) > 0)                 // ... und m�glichst gecachten Wert zur�ckgeben
      return(cache.localConfigPath[0]);

   // Cache-miss, aktuellen Wert ermitteln
   string iniFile = StringConcatenate(TerminalPath(), "\\metatrader-local-config.ini");
   bool createIniFile = false;

   if (!IsFile(iniFile)) {
      string lnkFile = StringConcatenate(iniFile, ".lnk");

      if (IsFile(lnkFile)) {
         iniFile = GetWin32ShortcutTarget(lnkFile);
         createIniFile = !IsFile(iniFile);
      }
      else {
         createIniFile = true;
      }

      if (createIniFile) {
         int hFile = _lcreat(iniFile, AT_NORMAL);
         if (hFile == HFILE_ERROR)
            return(_empty(catch("GetLocalConfigPath(1) ->kernel32::_lcreat(filename=\""+ iniFile +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));
         _lclose(hFile);
      }
   }

   cache.localConfigPath[0] = iniFile;                               // Ergebnis cachen

   if (IsError(catch("GetLocalConfigPath(2)")))
      return("");
   return(iniFile);
}


/**
 * Gibt den vollst�ndigen Dateinamen der globalen Konfigurationsdatei zur�ck.
 * Existiert die Datei nicht, wird sie angelegt.
 *
 * @return string - Dateiname
 */
string GetGlobalConfigPath() {
   static string cache.globalConfigPath[];                           // timeframe-�bergreifenden String-Cache einrichten (ohne Initializer) ...
   if (ArraySize(cache.globalConfigPath) == 0) {
      ArrayResize(cache.globalConfigPath, 1);
      cache.globalConfigPath[0] = "";
   }
   else if (StringLen(cache.globalConfigPath[0]) > 0)                // ... und m�glichst gecachten Wert zur�ckgeben
      return(cache.globalConfigPath[0]);

   // Cache-miss, aktuellen Wert ermitteln
   string iniFile = StringConcatenate(TerminalPath(), "\\..\\metatrader-global-config.ini");
   bool createIniFile = false;

   if (!IsFile(iniFile)) {
      string lnkFile = StringConcatenate(iniFile, ".lnk");

      if (IsFile(lnkFile)) {
         iniFile = GetWin32ShortcutTarget(lnkFile);
         createIniFile = !IsFile(iniFile);
      }
      else {
         createIniFile = true;
      }

      if (createIniFile) {
         int hFile = _lcreat(iniFile, AT_NORMAL);
         if (hFile == HFILE_ERROR)
            return(_empty(catch("GetGlobalConfigPath(1) ->kernel32::_lcreat(filename=\""+ iniFile +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));
         _lclose(hFile);
      }
   }

   cache.globalConfigPath[0] = iniFile;                              // Ergebnis cachen

   if (IsError(catch("GetGlobalConfigPath(2)")))
      return("");
   return(iniFile);
}


/**
 * Gibt die eindeutige ID einer W�hrung zur�ck.
 *
 * @param  string currency - 3-stelliger W�hrungsbezeichner
 *
 * @return int - Currency-ID
 */
int GetCurrencyId(string currency) {
   string curr = StringToUpper(currency);

   if (curr == C_AUD) return(CID_AUD);
   if (curr == C_CAD) return(CID_CAD);
   if (curr == C_CHF) return(CID_CHF);
   if (curr == C_CNY) return(CID_CNY);
   if (curr == C_CZK) return(CID_CZK);
   if (curr == C_DKK) return(CID_DKK);
   if (curr == C_EUR) return(CID_EUR);
   if (curr == C_GBP) return(CID_GBP);
   if (curr == C_HKD) return(CID_HKD);
   if (curr == C_HRK) return(CID_HRK);
   if (curr == C_HUF) return(CID_HUF);
   if (curr == C_INR) return(CID_INR);
   if (curr == C_JPY) return(CID_JPY);
   if (curr == C_LTL) return(CID_LTL);
   if (curr == C_LVL) return(CID_LVL);
   if (curr == C_MXN) return(CID_MXN);
   if (curr == C_NOK) return(CID_NOK);
   if (curr == C_NZD) return(CID_NZD);
   if (curr == C_PLN) return(CID_PLN);
   if (curr == C_RUB) return(CID_RUB);
   if (curr == C_SAR) return(CID_SAR);
   if (curr == C_SEK) return(CID_SEK);
   if (curr == C_SGD) return(CID_SGD);
   if (curr == C_THB) return(CID_THB);
   if (curr == C_TRY) return(CID_TRY);
   if (curr == C_TWD) return(CID_TWD);
   if (curr == C_USD) return(CID_USD);
   if (curr == C_ZAR) return(CID_ZAR);

   return(_ZERO(catch("GetCurrencyId()   unknown currency = \""+ currency +"\"", ERR_RUNTIME_ERROR)));
}


/**
 * Gibt den 3-stelligen Bezeichner einer W�hrungs-ID zur�ck.
 *
 * @param  int id - W�hrungs-ID
 *
 * @return string - W�hrungsbezeichner
 */
string GetCurrency(int id) {
   switch (id) {
      case CID_AUD: return(C_AUD);
      case CID_CAD: return(C_CAD);
      case CID_CHF: return(C_CHF);
      case CID_CNY: return(C_CNY);
      case CID_CZK: return(C_CZK);
      case CID_DKK: return(C_DKK);
      case CID_EUR: return(C_EUR);
      case CID_GBP: return(C_GBP);
      case CID_HKD: return(C_HKD);
      case CID_HRK: return(C_HRK);
      case CID_HUF: return(C_HUF);
      case CID_INR: return(C_INR);
      case CID_JPY: return(C_JPY);
      case CID_LTL: return(C_LTL);
      case CID_LVL: return(C_LVL);
      case CID_MXN: return(C_MXN);
      case CID_NOK: return(C_NOK);
      case CID_NZD: return(C_NZD);
      case CID_PLN: return(C_PLN);
      case CID_RUB: return(C_RUB);
      case CID_SAR: return(C_SAR);
      case CID_SEK: return(C_SEK);
      case CID_SGD: return(C_SGD);
      case CID_THB: return(C_THB);
      case CID_TRY: return(C_TRY);
      case CID_TWD: return(C_TWD);
      case CID_USD: return(C_USD);
      case CID_ZAR: return(C_ZAR);
   }
   return(_empty(catch("GetCurrency()   unknown currency id = "+ id, ERR_RUNTIME_ERROR)));
}


/**
 * Sortiert die �bergebenen Tickets in chronologischer Reihenfolge (nach OpenTime und Ticket#).
 *
 * @param  int tickets[] - zu sortierende Tickets
 *
 * @return int - Fehlerstatus
 */
int SortTicketsChronological(int& tickets[]) {
   int sizeOfTickets = ArraySize(tickets);
   int data[][2]; ArrayResize(data, sizeOfTickets);

   OrderPush("SortTicketsChronological(1)");

   // Tickets aufsteigend nach OrderOpenTime() sortieren
   for (int i=0; i < sizeOfTickets; i++) {
      if (!OrderSelectByTicket(tickets[i], "SortTicketsChronological(2)", NULL, O_POP))
         return(last_error);
      data[i][0] = OrderOpenTime();
      data[i][1] = tickets[i];
   }
   ArraySort(data);

   // Tickets mit derselben OpenTime nach Ticket# sortieren
   int open, lastOpen=-1, sortFrom=-1;

   for (i=0; i < sizeOfTickets; i++) {
      open = data[i][0];

      if (open == lastOpen) {
         if (sortFrom == -1) {
            sortFrom = i-1;
            data[sortFrom][0] = data[sortFrom][1];
         }
         data[i][0] = data[i][1];
      }
      else if (sortFrom != -1) {
         ArraySort(data, i-sortFrom, sortFrom);
         sortFrom = -1;
      }
      lastOpen = open;
   }
   if (sortFrom != -1)
      ArraySort(data, i+1-sortFrom, sortFrom);

   // Tickets zur�ck ins Ausgangsarray schreiben
   for (i=0; i < sizeOfTickets; i++) {
      tickets[i] = data[i][1];
   }

   return(catch("SortTicketsChronological(3)", NULL, O_POP));
}


/**
 * Aktiviert oder deaktiviert die Ausf�hrung von Expert-Advisern.
 *
 * @param  bool enable - gew�nschter Status
 *
 * @return int - Fehlerstatus
 *
 *
 * NOTE:
 * -----
 * Im aktivierten Zustand wird die start()-Funktion bei jedem Tick ausgef�hrt, im deaktivierten Zustand nicht. Die init()-Funktion wird immer ausgef�hrt.
 */
int SwitchExperts(bool enable) {

   // TODO: In EAs und Scripten SendMessage(), in Indikatoren PostMessage() verwenden (Erkennung des Scripttyps �ber Thread-ID)

   if (enable) {
      if (!IsExpertEnabled()) {
         SendMessageA(GetTerminalWindow(), WM_COMMAND, 33020, 0);
      }
   }
   else /*disable*/ {
      if (IsExpertEnabled()) {
         SendMessageA(GetTerminalWindow(), WM_COMMAND, 33020, 0);
      }
   }
   return(catch("SwitchExperts()"));
}


/**
 * Erzeugt und positioniert ein neues Legendenlabel f�r den angegebenen Namen. Das erzeugte Label hat keinen Text.
 *
 * @param  string name - Indikatorname
 *
 * @return string - vollst�ndiger Name des erzeugten Labels
 */
string CreateLegendLabel(string name) {
   int totalObj = ObjectsTotal(),
       labelObj = ObjectsTotal(OBJ_LABEL);

   string substrings[0], objName;
   int legendLabels, maxLegendId, maxYDistance=2;

   for (int i=0; i < totalObj && labelObj > 0; i++) {
      objName = ObjectName(i);
      if (ObjectType(objName) == OBJ_LABEL) {
         if (StringStartsWith(objName, "Legend.")) {
            legendLabels++;
            Explode(objName, ".", substrings);
            maxLegendId  = MathMax(maxLegendId, StrToInteger(substrings[1]));
            maxYDistance = MathMax(maxYDistance, ObjectGet(objName, OBJPROP_YDISTANCE));
         }
         labelObj--;
      }
   }

   string label = StringConcatenate("Legend.", maxLegendId+1, ".", name);
   if (ObjectFind(label) >= 0)
      ObjectDelete(label);
   if (ObjectCreate(label, OBJ_LABEL, 0, 0, 0)) {
      ObjectSet(label, OBJPROP_CORNER,    CORNER_TOP_LEFT);
      ObjectSet(label, OBJPROP_XDISTANCE,               5);
      ObjectSet(label, OBJPROP_YDISTANCE, maxYDistance+19);
   }
   else GetLastError();
   ObjectSetText(label, " ");

   if (IsError(catch("CreateLegendLabel()")))
      return("");
   return(label);
}


/**
 * Positioniert die Legende neu (wird nach Entfernen eines Legendenlabels aufgerufen).
 *
 * @return int - Fehlerstatus
 */
int RepositionLegend() {
   int objects = ObjectsTotal(),
       labels  = ObjectsTotal(OBJ_LABEL);

   string legends[];       ArrayResize(legends,    0);   // Namen der gefundenen Label
   int    yDistances[][2]; ArrayResize(yDistances, 0);   // Y-Distance und legends[]-Index, um Label nach Position sortieren zu k�nnen

   int legendLabels;

   for (int i=0; i < objects && labels > 0; i++) {
      string objName = ObjectName(i);
      if (ObjectType(objName) == OBJ_LABEL) {
         if (StringStartsWith(objName, "Legend.")) {
            legendLabels++;
            ArrayResize(legends,    legendLabels);
            ArrayResize(yDistances, legendLabels);
            legends   [legendLabels-1]    = objName;
            yDistances[legendLabels-1][0] = ObjectGet(objName, OBJPROP_YDISTANCE);
            yDistances[legendLabels-1][1] = legendLabels-1;
         }
         labels--;
      }
   }

   if (legendLabels > 0) {
      ArraySort(yDistances);
      for (i=0; i < legendLabels; i++) {
         ObjectSet(legends[yDistances[i][1]], OBJPROP_YDISTANCE, 21 + i*19);
      }
   }
   return(catch("RepositionLegend()"));
}


/**
 * Ob ein Tradeserver-Error tempor�r (also vor�bergehend) ist oder nicht. Bei einem vor�bergehenden Fehler *kann* der erneute Versuch,
 * die Order auszuf�hren, erfolgreich sein.
 *
 * @param  int error - Fehlercode
 *
 * @return bool
 *
 * @see IsPermanentTradeError()
 */
bool IsTemporaryTradeError(int error) {
   switch (error) {
      // temporary errors
      case ERR_COMMON_ERROR:                 //        2   trade denied
      case ERR_SERVER_BUSY:                  //        4   trade server is busy
      case ERR_TRADE_TIMEOUT:                //      128   trade timeout
      case ERR_INVALID_PRICE:                //      129   Kurs bewegt sich zu schnell (aus dem Fenster)
      case ERR_PRICE_CHANGED:                //      135   price changed
      case ERR_OFF_QUOTES:                   //      136   off quotes
      case ERR_BROKER_BUSY:                  //      137   broker is busy
      case ERR_REQUOTE:                      //      138   requote
      case ERR_TRADE_CONTEXT_BUSY:           //      146   trade context is busy
         return(true);

      // permanent errors
      case ERR_NO_RESULT:                    //        1   no result
      case ERR_INVALID_TRADE_PARAMETERS:     //        3   invalid trade parameters
      case ERR_OLD_VERSION:                  //        5   old version of client terminal
      case ERR_NO_CONNECTION:                //        6   no connection to trade server
      case ERR_NOT_ENOUGH_RIGHTS:            //        7   not enough rights
      case ERR_TOO_FREQUENT_REQUESTS:        // ???    8   too frequent requests
      case ERR_MALFUNCTIONAL_TRADE:          //        9   malfunctional trade operation
      case ERR_ACCOUNT_DISABLED:             //       64   account disabled
      case ERR_INVALID_ACCOUNT:              //       65   invalid account
      case ERR_INVALID_STOPS:                //      130   invalid stop
      case ERR_INVALID_TRADE_VOLUME:         //      131   invalid trade volume
      case ERR_MARKET_CLOSED:                //      132   market is closed
      case ERR_TRADE_DISABLED:               //      133   trading is disabled
      case ERR_NOT_ENOUGH_MONEY:             //      134   not enough money
      case ERR_ORDER_LOCKED:                 //      139   order is locked
      case ERR_LONG_POSITIONS_ONLY_ALLOWED:  //      140   long positions only allowed
      case ERR_TOO_MANY_REQUESTS:            // ???  141   too many requests
      case ERR_TRADE_MODIFY_DENIED:          //      145   modification denied because too close to market
      case ERR_TRADE_EXPIRATION_DENIED:      //      147   expiration settings denied by broker
      case ERR_TRADE_TOO_MANY_ORDERS:        //      148   number of open and pending orders has reached the broker limit
      case ERR_TRADE_HEDGE_PROHIBITED:       //      149   hedging prohibited
      case ERR_TRADE_PROHIBITED_BY_FIFO:     //      150   prohibited by FIFO rules
         return(false);
   }
   return(false);
}


/**
 * Ob ein Tradeserver-Error permanent (also nicht nur vor�bergehend) ist oder nicht. Bei einem permanenten Fehler wird auch der erneute Versuch,
 * die Order auszuf�hren, fehlschlagen.
 *
 * @param  int error - Fehlercode
 *
 * @return bool
 *
 * @see IsTemporaryTradeError()
 */
bool IsPermanentTradeError(int error) {
   return(!IsTemporaryTradeError(error));
}


/**
 * F�gt ein Element am Ende eines Double-Arrays an.
 *
 * @param  double array[] - Double-Array
 * @param  double value   - hinzuzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays
 */
int ArrayPushDouble(double& array[], double value) {
   int size = ArraySize(array);

   ArrayResize(array, size+1);
   array[size] = value;

   return(size+1);
}


/**
 * Entfernt ein Element vom Ende eines Double-Array und gibt es zur�ck.
 *
 * @param  int double[] - Double-Array
 *
 * @return double - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
double ArrayPopDouble(double array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayPopDouble()   cannot pop element from empty array = {}", ERR_SOME_ARRAY_ERROR)));

   double popped = array[size-1];
   ArrayResize(array, size-1);

   return(popped);
}


/**
 * Entfernt ein Element vom Beginn eines Double-Arrays und gibt es zur�ck.
 *
 * @param  double array[] - Double-Array
 *
 * @return double - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
double ArrayShiftDouble(double array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayShiftDouble()   cannot shift from an empty array = {}", ERR_SOME_ARRAY_ERROR)));

   double shifted = array[0];

   if (size > 1)
      ArrayCopy(array, array, 0, 1);
   ArrayResize(array, size-1);

   return(shifted);
}


/**
 * F�gt ein Element am Ende eines Integer-Arrays an.
 *
 * @param  int array[] - Integer-Array
 * @param  int value   - hinzuzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays
 */
int ArrayPushInt(int& array[], int value) {
   int size = ArraySize(array);

   ArrayResize(array, size+1);
   array[size] = value;

   return(size+1);
}


/**
 * Entfernt ein Element vom Ende eines Integer-Arrays und gibt es zur�ck.
 *
 * @param  int array[] - Integer-Array
 *
 * @return int - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
int ArrayPopInt(int array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayPopInt()   cannot pop element from empty array = {}", ERR_SOME_ARRAY_ERROR)));

   int popped = array[size-1];
   ArrayResize(array, size-1);

   return(popped);
}


/**
 * Entfernt ein Element vom Beginn eines Integer-Arrays und gibt es zur�ck.
 *
 * @param  int array[] - Integer-Array
 *
 * @return int - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
int ArrayShiftInt(int array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayShiftInt()   cannot shift element from empty array = {}", ERR_SOME_ARRAY_ERROR)));

   int shifted = array[0];

   if (size > 1)
      ArrayCopy(array, array, 0, 1);
   ArrayResize(array, size-1);

   return(shifted);
}


/**
 * F�gt ein Element am Ende eines String-Arrays an.
 *
 * @param  string array[] - String-Array
 * @param  string value   - hinzuzuf�gendes Element
 *
 * @return int - neue Gr��e des Arrays
 */
int ArrayPushString(string& array[], string value) {
   int size = ArraySize(array);

   ArrayResize(array, size+1);
   array[size] = value;

   return(size+1);
}


/**
 * Entfernt ein Element vom Ende eines String-Arrays und gibt es zur�ck.
 *
 * @param  string array[] - String-Array
 *
 * @return string - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
string ArrayPopString(string array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayPopString()   cannot pop element from empty array = {}", ERR_SOME_ARRAY_ERROR)));

   string popped = array[size-1];
   ArrayResize(array, size-1);

   return(popped);
}


/**
 * Entfernt ein Element vom Beginn eines String-Arrays und gibt es zur�ck.
 *
 * @param  string array[] - String-Array
 *
 * @return string - das entfernte Element
 *
 * NOTE:
 * -----
 * Ist das �bergebene Array leer, wird ein Laufzeitfehler ausgel�st.
 */
string ArrayShiftString(string array[]) {
   int size = ArraySize(array);
   if (size == 0)
      return(_NULL(catch("ArrayShiftString()   cannot shift from an empty array = {}", ERR_SOME_ARRAY_ERROR)));

   string shifted = array[0];

   if (size > 1)
      ArrayCopy(array, array, 0, 1);
   ArrayResize(array, size-1);

   return(shifted);
}


/**
 * Ob die Indizierung der internen Implementierung des angegebenen Double-Arrays umgekehrt ist oder nicht.
 *
 * @param  double array[] - Double-Array
 *
 * @return bool
 */
bool IsReverseIndexedDoubleArray(double array[]) {
   if (ArraySetAsSeries(array, false))
      return(!ArraySetAsSeries(array, true));
   return(false);
}


/**
 * Ob die Indizierung der internen Implementierung des angegebenen Integer-Arrays umgekehrt ist oder nicht.
 *
 * @param  int array[] - Integer-Array
 *
 * @return bool
 */
bool IsReverseIndexedIntArray(int array[]) {
   if (ArraySetAsSeries(array, false))
      return(!ArraySetAsSeries(array, true));
   return(false);
}


/**
 * Ob die Indizierung der internen Implementierung des angegebenen String-Arrays umgekehrt ist oder nicht.
 *
 * @param  string array[] - String-Array
 *
 * @return bool
 */
bool IsReverseIndexedStringArray(string array[]) {
   if (ArraySetAsSeries(array, false))
      return(!ArraySetAsSeries(array, true));
   return(false);
}


/**
 * Kehrt die Reihenfolge der Elemente eines Double-Arrays um.
 *
 * @param  double array[] - Double-Array
 *
 * @return bool - TRUE, wenn die Indizierung der internen Arrayimplementierung nach der Verarbeitung ebenfalls umgekehrt ist
 *                FALSE, wenn die interne Indizierung normal ist
 *
 * @see IsReverseIndexedDoubleArray()
 */
bool ReverseDoubleArray(double array[]) {
   if (ArraySetAsSeries(array, true))
      return(!ArraySetAsSeries(array, false));
   return(true);
}


/**
 * Kehrt die Reihenfolge der Elemente eines Integer-Arrays um.
 *
 * @param  int array[] - Integer-Array
 *
 * @return bool - TRUE, wenn die Indizierung der internen Arrayimplementierung nach der Verarbeitung ebenfalls umgekehrt ist
 *                FALSE, wenn die interne Indizierung normal ist
 *
 * @see IsReverseIndexedIntArray()
 */
bool ReverseIntArray(int array[]) {
   if (ArraySetAsSeries(array, true))
      return(!ArraySetAsSeries(array, false));
   return(true);
}


/**
 * Kehrt die Reihenfolge der Elemente eines String-Arrays um.
 *
 * @param  string array[] - String-Array
 *
 * @return bool - TRUE, wenn die Indizierung der internen Arrayimplementierung nach der Verarbeitung ebenfalls umgekehrt ist
 *                FALSE, wenn die interne Indizierung normal ist
 *
 * @see IsReverseIndexedStringArray()
 */
bool ReverseStringArray(string array[]) {
   if (ArraySetAsSeries(array, true))
      return(!ArraySetAsSeries(array, false));
   return(true);
}


/**
 * Win32 structure WIN32_FIND_DATA
 *
 * typedef struct _WIN32_FIND_DATA {
 *    DWORD    dwFileAttributes;          //   4     => wfd[ 0]
 *    FILETIME ftCreationTime;            //   8     => wfd[ 1]
 *    FILETIME ftLastAccessTime;          //   8     => wfd[ 3]
 *    FILETIME ftLastWriteTime;           //   8     => wfd[ 5]
 *    DWORD    nFileSizeHigh;             //   4     => wfd[ 7]
 *    DWORD    nFileSizeLow;              //   4     => wfd[ 8]
 *    DWORD    dwReserved0;               //   4     => wfd[ 9]
 *    DWORD    dwReserved1;               //   4     => wfd[10]
 *    TCHAR    cFileName[MAX_PATH];       // 260     => wfd[11]      A: 260 * 1 byte      W: 260 * 2 byte
 *    TCHAR    cAlternateFileName[14];    //  14     => wfd[76]      A:  14 * 1 byte      W:  14 * 2 byte
 * } WIN32_FIND_DATA, wfd;                // 318 byte = int[80]      2 byte �berhang
 *
 * BufferToHexStr(WIN32_FIND_DATA) = 20000000
 *                                   C0235A72 81BDC801
 *                                   00F0D85B C9CBCB01
 *                                   00884084 D32BC101
 *                                   00000000 D2430000 05000000 3FE1807C
 *
 *                                   52686F64 6F64656E 64726F6E 2E626D70 00000000 00000000 00000000 00000000 00000000 00000000
 *                                    R h o d  o d e n  d r o n  . b m p
 *                                   00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                   00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                   00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                   00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                   00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                   00000000 00000000 00000000 00000000 00000000
 *
 *                                   52484F44 4F447E31 2E424D50 00000000
 *                                    R H O D  O D ~ 1  . B M P
 */
int    wfd.FileAttributes            (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0]); }
bool   wfd.FileAttribute.ReadOnly    (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_READONLY      == FILE_ATTRIBUTE_READONLY     ); }
bool   wfd.FileAttribute.Hidden      (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_HIDDEN        == FILE_ATTRIBUTE_HIDDEN       ); }
bool   wfd.FileAttribute.System      (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_SYSTEM        == FILE_ATTRIBUTE_SYSTEM       ); }
bool   wfd.FileAttribute.Directory   (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_DIRECTORY     == FILE_ATTRIBUTE_DIRECTORY    ); }
bool   wfd.FileAttribute.Archive     (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_ARCHIVE       == FILE_ATTRIBUTE_ARCHIVE      ); }
bool   wfd.FileAttribute.Device      (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_DEVICE        == FILE_ATTRIBUTE_DEVICE       ); }
bool   wfd.FileAttribute.Normal      (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_NORMAL        == FILE_ATTRIBUTE_NORMAL       ); }
bool   wfd.FileAttribute.Temporary   (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_TEMPORARY     == FILE_ATTRIBUTE_TEMPORARY    ); }
bool   wfd.FileAttribute.SparseFile  (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_SPARSE_FILE   == FILE_ATTRIBUTE_SPARSE_FILE  ); }
bool   wfd.FileAttribute.ReparsePoint(/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_REPARSE_POINT == FILE_ATTRIBUTE_REPARSE_POINT); }
bool   wfd.FileAttribute.Compressed  (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_COMPRESSED    == FILE_ATTRIBUTE_COMPRESSED   ); }
bool   wfd.FileAttribute.Offline     (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_OFFLINE       == FILE_ATTRIBUTE_OFFLINE      ); }
bool   wfd.FileAttribute.NotIndexed  (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_NOT_INDEXED   == FILE_ATTRIBUTE_NOT_INDEXED  ); }
bool   wfd.FileAttribute.Encrypted   (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_ENCRYPTED     == FILE_ATTRIBUTE_ENCRYPTED    ); }
bool   wfd.FileAttribute.Virtual     (/*WIN32_FIND_DATA*/int wfd[]) { return(wfd[0] & FILE_ATTRIBUTE_VIRTUAL       == FILE_ATTRIBUTE_VIRTUAL      ); }
string wfd.FileName                  (/*WIN32_FIND_DATA*/int wfd[]) { return(BufferCharsToStr(wfd, 44, MAX_PATH)); }
string wfd.AlternateFileName         (/*WIN32_FIND_DATA*/int wfd[]) { return(BufferCharsToStr(wfd, 304, 14)); }


/**
 * Gibt die lesbare Version eines FileAttributes zur�ck.
 *
 * @param  int wdf[] - WIN32_FIND_DATA structure
 *
 * @return string
 */
string wdf.FileAttributesToStr(/*WIN32_FIND_DATA*/int wdf[]) {
   string result = "";
   int flags = wfd.FileAttributes(wdf);

   if (flags & FILE_ATTRIBUTE_READONLY      == FILE_ATTRIBUTE_READONLY     ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_READONLY"     );
   if (flags & FILE_ATTRIBUTE_HIDDEN        == FILE_ATTRIBUTE_HIDDEN       ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_HIDDEN"       );
   if (flags & FILE_ATTRIBUTE_SYSTEM        == FILE_ATTRIBUTE_SYSTEM       ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_SYSTEM"       );
   if (flags & FILE_ATTRIBUTE_DIRECTORY     == FILE_ATTRIBUTE_DIRECTORY    ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_DIRECTORY"    );
   if (flags & FILE_ATTRIBUTE_ARCHIVE       == FILE_ATTRIBUTE_ARCHIVE      ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_ARCHIVE"      );
   if (flags & FILE_ATTRIBUTE_DEVICE        == FILE_ATTRIBUTE_DEVICE       ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_DEVICE"       );
   if (flags & FILE_ATTRIBUTE_NORMAL        == FILE_ATTRIBUTE_NORMAL       ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_NORMAL"       );
   if (flags & FILE_ATTRIBUTE_TEMPORARY     == FILE_ATTRIBUTE_TEMPORARY    ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_TEMPORARY"    );
   if (flags & FILE_ATTRIBUTE_SPARSE_FILE   == FILE_ATTRIBUTE_SPARSE_FILE  ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_SPARSE_FILE"  );
   if (flags & FILE_ATTRIBUTE_REPARSE_POINT == FILE_ATTRIBUTE_REPARSE_POINT) result = StringConcatenate(result, " | FILE_ATTRIBUTE_REPARSE_POINT");
   if (flags & FILE_ATTRIBUTE_COMPRESSED    == FILE_ATTRIBUTE_COMPRESSED   ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_COMPRESSED"   );
   if (flags & FILE_ATTRIBUTE_OFFLINE       == FILE_ATTRIBUTE_OFFLINE      ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_OFFLINE"      );
   if (flags & FILE_ATTRIBUTE_NOT_INDEXED   == FILE_ATTRIBUTE_NOT_INDEXED  ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_NOT_INDEXED"  );
   if (flags & FILE_ATTRIBUTE_ENCRYPTED     == FILE_ATTRIBUTE_ENCRYPTED    ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_ENCRYPTED"    );
   if (flags & FILE_ATTRIBUTE_VIRTUAL       == FILE_ATTRIBUTE_VIRTUAL      ) result = StringConcatenate(result, " | FILE_ATTRIBUTE_VIRTUAL"      );

   if (StringLen(result) > 0)
      result = StringSubstr(result, 3);
   return(result);
}


/**
 * Win32 structure FILETIME
 *
 * typedef struct _FILETIME {
 *    DWORD dwLowDateTime;
 *    DWORD dwHighDateTime;
 * } FILETIME, ft;
 *
 * BufferToHexStr(FILETIME) =
 */


/**
 * Win32 structure PROCESS_INFORMATION
 *
 * typedef struct _PROCESS_INFORMATION {
 *    HANDLE hProcess;
 *    HANDLE hThread;
 *    DWORD  dwProcessId;
 *    DWORD  dwThreadId;
 * } PROCESS_INFORMATION, pi;       // = 16 byte = int[4]
 *
 * BufferToHexStr(PROCESS_INFORMATION) = 68020000 74020000 D40E0000 B80E0000
 */
int pi.hProcess (/*PROCESS_INFORMATION*/int pi[]) { return(pi[0]); }
int pi.hThread  (/*PROCESS_INFORMATION*/int pi[]) { return(pi[1]); }
int pi.ProcessId(/*PROCESS_INFORMATION*/int pi[]) { return(pi[2]); }
int pi.ThreadId (/*PROCESS_INFORMATION*/int pi[]) { return(pi[3]); }


/**
 * Win32 structure SECURITY_ATTRIBUTES
 *
 * typedef struct _SECURITY_ATTRIBUTES {
 *    DWORD  nLength;
 *    LPVOID lpSecurityDescriptor;
 *    BOOL   bInheritHandle;
 * } SECURITY_ATTRIBUTES, sa;       // = 12 byte = int[3]
 *
 * BufferToHexStr(SECURITY_ATTRIBUTES) = 0C000000 00000000 00000000
 */
int  sa.Length            (/*SECURITY_ATTRIBUTES*/int sa[]) { return(sa[0]); }
int  sa.SecurityDescriptor(/*SECURITY_ATTRIBUTES*/int sa[]) { return(sa[1]); }
bool sa.InheritHandle     (/*SECURITY_ATTRIBUTES*/int sa[]) { return(sa[2] != 0); }


/**
 * Win32 structure STARTUPINFO
 *
 * typedef struct _STARTUPINFO {
 *    DWORD  cb;                        =>  si[ 0]
 *    LPTSTR lpReserved;                =>  si[ 1]
 *    LPTSTR lpDesktop;                 =>  si[ 2]
 *    LPTSTR lpTitle;                   =>  si[ 3]
 *    DWORD  dwX;                       =>  si[ 4]
 *    DWORD  dwY;                       =>  si[ 5]
 *    DWORD  dwXSize;                   =>  si[ 6]
 *    DWORD  dwYSize;                   =>  si[ 7]
 *    DWORD  dwXCountChars;             =>  si[ 8]
 *    DWORD  dwYCountChars;             =>  si[ 9]
 *    DWORD  dwFillAttribute;           =>  si[10]
 *    DWORD  dwFlags;                   =>  si[11]
 *    WORD   wShowWindow;               =>  si[12]
 *    WORD   cbReserved2;               =>  si[12]
 *    LPBYTE lpReserved2;               =>  si[13]
 *    HANDLE hStdInput;                 =>  si[14]
 *    HANDLE hStdOutput;                =>  si[15]
 *    HANDLE hStdError;                 =>  si[16]
 * } STARTUPINFO, si;       // = 68 byte = int[17]
 *
 * BufferToHexStr(STARTUPINFO) = 44000000 103E1500 703E1500 D83D1500 00000000 00000000 00000000 00000000 00000000 00000000 00000000 010E0000 03000000 00000000 41060000 01000100 00000000
 */
int si.cb            (/*STARTUPINFO*/int si[]) { return(si[ 0]); }
int si.Desktop       (/*STARTUPINFO*/int si[]) { return(si[ 2]); }
int si.Title         (/*STARTUPINFO*/int si[]) { return(si[ 3]); }
int si.X             (/*STARTUPINFO*/int si[]) { return(si[ 4]); }
int si.Y             (/*STARTUPINFO*/int si[]) { return(si[ 5]); }
int si.XSize         (/*STARTUPINFO*/int si[]) { return(si[ 6]); }
int si.YSize         (/*STARTUPINFO*/int si[]) { return(si[ 7]); }
int si.XCountChars   (/*STARTUPINFO*/int si[]) { return(si[ 8]); }
int si.YCountChars   (/*STARTUPINFO*/int si[]) { return(si[ 9]); }
int si.FillAttribute (/*STARTUPINFO*/int si[]) { return(si[10]); }
int si.Flags         (/*STARTUPINFO*/int si[]) { return(si[11]); }
int si.ShowWindow    (/*STARTUPINFO*/int si[]) { return(si[12] & 0xFFFF); }
int si.hStdInput     (/*STARTUPINFO*/int si[]) { return(si[14]); }
int si.hStdOutput    (/*STARTUPINFO*/int si[]) { return(si[15]); }
int si.hStdError     (/*STARTUPINFO*/int si[]) { return(si[16]); }

int si.setCb         (/*STARTUPINFO*/int& si[], int size   ) { si[ 0] =  size; }
int si.setFlags      (/*STARTUPINFO*/int& si[], int flags  ) { si[11] = flags; }
int si.setShowWindow (/*STARTUPINFO*/int& si[], int cmdShow) { si[12] = (si[12] & 0xFFFF0000) + (cmdShow & 0xFFFF); }


/**
 * Gibt die lesbare Version eines STARTUPINFO-Flags zur�ck.
 *
 * @param  int si[] - STARTUPINFO structure
 *
 * @return string
 */
string si.FlagsToStr(/*STARTUPINFO*/int si[]) {
   string result = "";
   int flags = si.Flags(si);

   if (flags & STARTF_FORCEONFEEDBACK  == STARTF_FORCEONFEEDBACK ) result = StringConcatenate(result, " | STARTF_FORCEONFEEDBACK" );
   if (flags & STARTF_FORCEOFFFEEDBACK == STARTF_FORCEOFFFEEDBACK) result = StringConcatenate(result, " | STARTF_FORCEOFFFEEDBACK");
   if (flags & STARTF_PREVENTPINNING   == STARTF_PREVENTPINNING  ) result = StringConcatenate(result, " | STARTF_PREVENTPINNING"  );
   if (flags & STARTF_RUNFULLSCREEN    == STARTF_RUNFULLSCREEN   ) result = StringConcatenate(result, " | STARTF_RUNFULLSCREEN"   );
   if (flags & STARTF_TITLEISAPPID     == STARTF_TITLEISAPPID    ) result = StringConcatenate(result, " | STARTF_TITLEISAPPID"    );
   if (flags & STARTF_TITLEISLINKNAME  == STARTF_TITLEISLINKNAME ) result = StringConcatenate(result, " | STARTF_TITLEISLINKNAME" );
   if (flags & STARTF_USECOUNTCHARS    == STARTF_USECOUNTCHARS   ) result = StringConcatenate(result, " | STARTF_USECOUNTCHARS"   );
   if (flags & STARTF_USEFILLATTRIBUTE == STARTF_USEFILLATTRIBUTE) result = StringConcatenate(result, " | STARTF_USEFILLATTRIBUTE");
   if (flags & STARTF_USEHOTKEY        == STARTF_USEHOTKEY       ) result = StringConcatenate(result, " | STARTF_USEHOTKEY"       );
   if (flags & STARTF_USEPOSITION      == STARTF_USEPOSITION     ) result = StringConcatenate(result, " | STARTF_USEPOSITION"     );
   if (flags & STARTF_USESHOWWINDOW    == STARTF_USESHOWWINDOW   ) result = StringConcatenate(result, " | STARTF_USESHOWWINDOW"   );
   if (flags & STARTF_USESIZE          == STARTF_USESIZE         ) result = StringConcatenate(result, " | STARTF_USESIZE"         );
   if (flags & STARTF_USESTDHANDLES    == STARTF_USESTDHANDLES   ) result = StringConcatenate(result, " | STARTF_USESTDHANDLES"   );

   if (StringLen(result) > 0)
      result = StringSubstr(result, 3);
   return(result);
}


/**
 * Gibt die lesbare Konstante einer STARTUPINFO ShowWindow command ID zur�ck.
 *
 * @param  int si[] - STARTUPINFO structure
 *
 * @return string
 */
string si.ShowWindowToStr(/*STARTUPINFO*/int si[]) {
   switch (si.ShowWindow(si)) {
      case SW_HIDE           : return("SW_HIDE"           );
      case SW_SHOWNORMAL     : return("SW_SHOWNORMAL"     );
      case SW_SHOWMINIMIZED  : return("SW_SHOWMINIMIZED"  );
      case SW_SHOWMAXIMIZED  : return("SW_SHOWMAXIMIZED"  );
      case SW_SHOWNOACTIVATE : return("SW_SHOWNOACTIVATE" );
      case SW_SHOW           : return("SW_SHOW"           );
      case SW_MINIMIZE       : return("SW_MINIMIZE"       );
      case SW_SHOWMINNOACTIVE: return("SW_SHOWMINNOACTIVE");
      case SW_SHOWNA         : return("SW_SHOWNA"         );
      case SW_RESTORE        : return("SW_RESTORE"        );
      case SW_SHOWDEFAULT    : return("SW_SHOWDEFAULT"    );
      case SW_FORCEMINIMIZE  : return("SW_FORCEMINIMIZE"  );
   }
   return("");
}


/**
 * Win32 structure SYSTEMTIME
 *
 * typedef struct _SYSTEMTIME {
 *    WORD wYear;
 *    WORD wMonth;
 *    WORD wDayOfWeek;
 *    WORD wDay;
 *    WORD wHour;
 *    WORD wMinute;
 *    WORD wSecond;
 *    WORD wMilliseconds;
 * } SYSTEMTIME, st;       // = 16 byte = int[4]
 *
 * BufferToHexStr(SYSTEMTIME) = DB070100 06000F00 12003600 05000A03
 */
int st.Year     (/*SYSTEMTIME*/int st[]) { return(st[0] &  0x0000FFFF); }
int st.Month    (/*SYSTEMTIME*/int st[]) { return(st[0] >> 16        ); }
int st.DayOfWeek(/*SYSTEMTIME*/int st[]) { return(st[1] &  0x0000FFFF); }
int st.Day      (/*SYSTEMTIME*/int st[]) { return(st[1] >> 16        ); }
int st.Hour     (/*SYSTEMTIME*/int st[]) { return(st[2] &  0x0000FFFF); }
int st.Minute   (/*SYSTEMTIME*/int st[]) { return(st[2] >> 16        ); }
int st.Second   (/*SYSTEMTIME*/int st[]) { return(st[3] &  0x0000FFFF); }
int st.MilliSec (/*SYSTEMTIME*/int st[]) { return(st[3] >> 16        ); }


/**
 * Win32 structure TIME_ZONE_INFORMATION
 *
 * typedef struct _TIME_ZONE_INFORMATION {
 *    LONG       Bias;                //     4     => tzi[ 0]     Formeln:               GMT = UTC
 *    WCHAR      StandardName[32];    //    64     => tzi[ 1]     --------              Bias = -Offset
 *    SYSTEMTIME StandardDate;        //    16     => tzi[17]               LocalTime + Bias = GMT        (LocalTime -> GMT)
 *    LONG       StandardBias;        //     4     => tzi[21]                   GMT + Offset = LocalTime  (GMT -> LocalTime)
 *    WCHAR      DaylightName[32];    //    64     => tzi[22]
 *    SYSTEMTIME DaylightDate;        //    16     => tzi[38]
 *    LONG       DaylightBias;        //     4     => tzi[42]
 * } TIME_ZONE_INFORMATION, tzi;      // = 172 byte = int[43]
 *
 * BufferToHexStr(TIME_ZONE_INFORMATION) = 88FFFFFF
 *                                         47005400 42002000 4E006F00 72006D00 61006C00 7A006500 69007400 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                         G   T    B   .    N   o    r   m    a   l    z   e    i   t
 *                                         00000A00 00000500 04000000 00000000
 *                                         00000000
 *                                         47005400 42002000 53006F00 6D006D00 65007200 7A006500 69007400 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000
 *                                         G   T    B   .    S   o    m   m    e   r    z   e    i   t
 *                                         00000300 00000500 03000000 00000000
 *                                         C4FFFFFF
 */
int    tzi.Bias        (/*TIME_ZONE_INFORMATION*/int tzi[])                         { return(tzi[0]); }                               // Bias in Minuten
string tzi.StandardName(/*TIME_ZONE_INFORMATION*/int tzi[])                         { return(BufferWCharsToStr(tzi, 1, 16)); }
void   tzi.StandardDate(/*TIME_ZONE_INFORMATION*/int tzi[], /*SYSTEMTIME*/int st[]) { ArrayCopy(st, tzi, 0, 17, 4); }
int    tzi.StandardBias(/*TIME_ZONE_INFORMATION*/int tzi[])                         { return(tzi[21]); }                              // Bias in Minuten
string tzi.DaylightName(/*TIME_ZONE_INFORMATION*/int tzi[])                         { return(BufferWCharsToStr(tzi, 22, 16)); }
void   tzi.DaylightDate(/*TIME_ZONE_INFORMATION*/int tzi[], /*SYSTEMTIME*/int st[]) { ArrayCopy(st, tzi, 0, 38, 4); }
int    tzi.DaylightBias(/*TIME_ZONE_INFORMATION*/int tzi[])                         { return(tzi[42]); }                              // Bias in Minuten


/**
 * Gibt den kompletten Inhalt eines Byte-Buffers als lesbaren String zur�ck. NULL-Bytes werden gestrichelt (�), Control-Character (<0x20) fett (�) dargestellt.
 * N�tzlich, um im Buffer enthaltene Daten schnell visualisieren zu k�nnen.
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur �ber ein Integer-Array abgebildet werden)
 *
 * @return string
 */
string BufferToStr(int buffer[]) {
   int    size   = ArraySize(buffer);
   string result = CreateString(size << 2);                       // ein Integer = 4 Byte = 4 Zeichen

   for (int i=0; i < size; i++) {
      int integer = buffer[i];                                    // Integers nacheinander verarbeiten
                                                                                                            // +---+------------+------+
      for (int n=0; n < 4; n++) {                                                                           // | n |    byte    | char |
         int byte = integer & 0xFF;                               // einzelnes Byte des Integers lesen      // +---+------------+------+
         if (byte < 0x20) {                                       // nicht darstellbare Zeichen ersetzen    // | 0 | 0x000000FF |   1  |
            if (byte == 0x00) byte = PLACEHOLDER_ZERO_CHAR;       // NULL-Byte                   (�)        // | 1 | 0x0000FF00 |   2  |
            else              byte = PLACEHOLDER_CTL_CHAR;        // sonstiges Control-Character (�)        // | 2 | 0x00FF0000 |   3  |
         }                                                                                                  // | 3 | 0xFF000000 |   4  |
         result = StringSetChar(result, i<<2 + n, byte);          // Zeichen setzen                         // +---+------------+------+
         integer >>= 8;
      }
   }

   if (IsError(catch("BufferToStr()")))
      return("");
   return(result);
}


/**
 * Gibt den kompletten Inhalt eines Byte-Buffers als hexadezimalen String zur�ck.
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur �ber ein Integer-Array abgebildet werden)
 *
 * @return string
 */
string BufferToHexStr(int buffer[]) {
   string result = "";
   int size = ArraySize(buffer);

   // Structs werden in MQL mit Hilfe von Integer-Arrays nachgebildet. Integers sind interpretierte bin�re Werte (Reihenfolge von HIBYTE, LOBYTE, HIWORD, LOWORD).
   // Diese Interpretation mu� wieder r�ckg�ngig gemacht werden.
   for (int i=0; i < size; i++) {
      string hex   = IntToHexStr(buffer[i]);
      string byte1 = StringSubstr(hex, 6, 2);
      string byte2 = StringSubstr(hex, 4, 2);
      string byte3 = StringSubstr(hex, 2, 2);
      string byte4 = StringSubstr(hex, 0, 2);
      result = StringConcatenate(result, " ", byte1, byte2, byte3, byte4);
   }

   if (size > 0)
      result = StringSubstr(result, 1);

   if (IsError(catch("BufferToHexStr()")))
      return("");
   return(result);
}


/**
 * Gibt ein einzelnes Zeichen (ein Byte) von der angegebenen Position des Buffers zur�ck.
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur �ber ein Integer-Array abgebildet werden)
 * @param  int pos      - Zeichen-Position
 *
 * @return int - Zeichen-Code oder -1, wenn ein Fehler auftrat
 */
int BufferGetChar(int buffer[], int pos) {
   int chars = ArraySize(buffer) << 2;

   if (pos < 0)      return(_int(-1, catch("BufferGetChar(1)  invalid parameter pos: "+ pos, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (pos >= chars) return(_int(-1, catch("BufferGetChar(2)  invalid parameter pos: "+ pos, ERR_INVALID_FUNCTION_PARAMVALUE)));

   int i = pos >> 2;                      // Index des relevanten Integers des Arrays     // +---+------------+
   int b = pos & 0x03;                    // Index des relevanten Bytes des Integers      // | b |    byte    |
                                                                                          // +---+------------+
   int integer = buffer[i] >> (b<<3);                                                     // | 0 | 0x000000FF |
   int char    = integer & 0xFF;                                                          // | 1 | 0x0000FF00 |
                                                                                          // | 2 | 0x00FF0000 |
   return(char);                                                                          // | 3 | 0xFF000000 |
}                                                                                         // +---+------------+


/**
 * Gibt die in einem Byte-Buffer im angegebenen Bereich gespeicherte und mit einem NULL-Byte terminierte ANSI-Charactersequenz zur�ck.
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur �ber ein Integer-Array abgebildet werden)
 * @param  int from     - Index des ersten Bytes des f�r die Charactersequenz reservierten Bereichs, beginnend mit 0
 * @param  int length   - Anzahl der im Buffer f�r die Charactersequenz reservierten Bytes
 *
 * @return string       - ANSI-String
 */
string BufferCharsToStr(int buffer[], int from, int length) {
   int fromChar=from, toChar=fromChar+length, bufferChars=ArraySize(buffer)<<2;

   if (fromChar < 0)            return(_empty(catch("BufferCharsToStr(1)  invalid parameter from: "+ from, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (fromChar >= bufferChars) return(_empty(catch("BufferCharsToStr(2)  invalid parameter from: "+ from, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (length < 0)              return(_empty(catch("BufferCharsToStr(3)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (toChar >= bufferChars)   return(_empty(catch("BufferCharsToStr(4)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (length == 0)
      return("");

   string result = "";
   int    chars, fromInt=fromChar>>2, toInt=toChar>>2, n=fromChar&0x03; // Indizes der relevanten Array-Integers und des ersten Chars (liegt evt. nicht auf Integer-Boundary)

   for (int i=fromInt; i <= toInt; i++) {
      int byte, integer=buffer[i];

      for (; n < 4; n++) {                                           // n: 0-1-2-3
         if (chars == length)
            break;
         byte = integer >> (n<<3) & 0xFF;                            // integer >> 0-8-16-24
         if (byte == 0x00)                                           // NULL-Byte: Ausbruch aus innerer Schleife
            break;
         result = StringConcatenate(result, CharToStr(byte));
         chars++;
      }
      if (byte == 0x00)                                              // NULL-Byte: Ausbruch aus �u�erer Schleife
         break;
      n = 0;
   }

   if (IsError(catch("BufferCharsToStr(5)")))
      return("");
   return(result);
}


/**
 * Gibt die in einem Byte-Buffer im angegebenen Bereich gespeicherte und mit einem NULL-Byte terminierte WCHAR-Charactersequenz (Multibyte-Characters).
 *
 * @param  int buffer[] - Byte-Buffer (kann in MQL nur �ber ein Integer-Array abgebildet werden)
 * @param  int from     - Index des ersten Integers der Charactersequenz
 * @param  int length   - Anzahl der Integers des im Buffer f�r die Charactersequenz reservierten Bereiches
 *
 * @return string       - ANSI-String
 *
 *
 * NOTE: Zur Zeit arbeitet diese Funktion nur mit Charactersequenzen, die an Integer-Boundaries beginnen und enden.
 * ----
 */
string BufferWCharsToStr(int buffer[], int from, int length) {
   if (from < 0)
      return(catch("BufferWCharsToStr(1)  invalid parameter from: "+ from, ERR_INVALID_FUNCTION_PARAMVALUE));
   int to = from+length, size=ArraySize(buffer);
   if (to > size)
      return(catch("BufferWCharsToStr(2)  invalid parameter length: "+ length, ERR_INVALID_FUNCTION_PARAMVALUE));

   string result = "";

   for (int i=from; i < to; i++) {
      string strChar;
      int word, shift=0, integer=buffer[i];

      for (int n=0; n < 2; n++) {
         word = integer >> shift & 0xFFFF;
         if (word == 0)                                        // termination character (0x00)
            break;
         int byte1 = word      & 0xFF;
         int byte2 = word >> 8 & 0xFF;

         if (byte1!=0 && byte2==0) strChar = CharToStr(byte1);
         else                      strChar = "?";              // multi-byte character
         result = StringConcatenate(result, strChar);
         shift += 16;
      }
      if (word == 0)
         break;
   }

   if (IsError(catch("BufferWCharsToStr(3)")))
      return("");
   return(result);
}


/**
 * Konvertiert einen String-Buffer in ein String-Array.
 *
 * @param  int    buffer[]  - Buffer mit durch NULL-Zeichen getrennten Strings, terminiert durch ein weiteres NULL-Zeichen
 * @param  string results[] - Ergebnisarray
 *
 * @return int - Anzahl der konvertierten Strings
 */
int ExplodeStrings(int buffer[], string& results[]) {
   int  bufferSize = ArraySize(buffer);
   bool separator  = true;

   ArrayResize(results, 0);
   int resultSize = 0;

   for (int i=0; i < bufferSize; i++) {
      int value, shift=0, integer=buffer[i];

      // Die Reihenfolge von HIBYTE, LOBYTE, HIWORD und LOWORD eines Integers mu� in die eines Strings konvertiert werden.
      for (int n=0; n < 4; n++) {
         value = integer >> shift & 0xFF;             // Integer in Bytes zerlegen

         if (value != 0x00) {                         // kein Trennzeichen, Character in Array ablegen
            if (separator) {
               resultSize++;
               ArrayResize(results, resultSize);
               results[resultSize-1] = "";
               separator = false;
            }
            results[resultSize-1] = StringConcatenate(results[resultSize-1], CharToStr(value));
         }
         else {                                       // Trennzeichen
            if (separator) {                          // 2 Trennzeichen = Separator + Terminator, beide Schleifen verlassen
               i = bufferSize;
               break;
            }
            separator = true;
         }
         shift += 8;
      }
   }

   if (IsError(catch("ExplodeStrings()")))
      return(0);
   return(ArraySize(results));
}


/**
 * Alias f�r ExplodeStringsA()
 */
int ExplodeStringsA(int buffer[], string& results[]) {
   return(ExplodeStrings(buffer, results));
}


/**
 *
 */
int ExplodeStringsW(int buffer[], string& results[]) {
   return(catch("ExplodeStringsW()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Ermittelt den vollst�ndigen Dateipfad der Zieldatei, auf die ein Windows-Shortcut (.lnk-File) zeigt.
 *
 * @return string lnkFilename - Pfadangabe zum Shortcut
 *
 * @return string - Dateipfad der Zieldatei
 */
string GetWin32ShortcutTarget(string lnkFilename) {
   // --------------------------------------------------------------------------
   // How to read the target's path from a .lnk-file:
   // --------------------------------------------------------------------------
   // Problem:
   //
   //    The COM interface to shell32.dll IShellLink::GetPath() fails!
   //
   // Solution:
   //
   //   We need to parse the file manually. The path can be found like shown
   //   here.  If the shell item id list is not present (as signaled in flags),
   //   we have to assume A = -6.
   //
   //  +-----------------+----------------------------------------------------+
   //  |     Byte-Offset | Description                                        |
   //  +-----------------+----------------------------------------------------+
   //  |               0 | 'L' (magic value)                                  |
   //  +-----------------+----------------------------------------------------+
   //  |            4-19 | GUID                                               |
   //  +-----------------+----------------------------------------------------+
   //  |           20-23 | shortcut flags                                     |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | ...                                                |
   //  +-----------------+----------------------------------------------------+
   //  |           76-77 | A (16 bit): size of shell item id list, if present |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | shell item id list, if present                     |
   //  +-----------------+----------------------------------------------------+
   //  |      78 + 4 + A | B (32 bit): size of file location info             |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | file location info                                 |
   //  +-----------------+----------------------------------------------------+
   //  |      78 + A + B | C (32 bit): size of local volume table             |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | local volume table                                 |
   //  +-----------------+----------------------------------------------------+
   //  |  78 + A + B + C | target path string (ending with 0x00)              |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | ...                                                |
   //  +-----------------+----------------------------------------------------+
   //  |             ... | 0x00                                               |
   //  +-----------------+----------------------------------------------------+
   //
   // @see http://www.codeproject.com/KB/shell/ReadLnkFile.aspx
   // --------------------------------------------------------------------------

   if (StringLen(lnkFilename) < 4 || StringRight(lnkFilename, 4)!=".lnk")
      return(_empty(catch("GetWin32ShortcutTarget(1)  invalid parameter lnkFilename: \""+ lnkFilename +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   // --------------------------------------------------------------------------
   // Get the .lnk-file content:
   // --------------------------------------------------------------------------
   int hFile = _lopen(string lnkFilename, OF_READ);
   if (hFile == HFILE_ERROR)
      return(_empty(catch("GetWin32ShortcutTarget(2) ->kernel32::_lopen(\""+ lnkFilename +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   int iNull[];
   int fileSize = GetFileSize(hFile, iNull);
   if (fileSize == 0xFFFFFFFF) {
      catch("GetWin32ShortcutTarget(3) ->kernel32::GetFileSize(\""+ lnkFilename +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
      _lclose(hFile);
      return("");
   }
   int buffer[]; InitializeBuffer(buffer, fileSize);

   int bytes = _lread(hFile, buffer, fileSize);
   if (bytes != fileSize) {
      catch("GetWin32ShortcutTarget(4) ->kernel32::_lread(\""+ lnkFilename +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
      _lclose(hFile);
      return("");
   }
   _lclose(hFile);

   if (bytes < 24)
      return(_empty(catch("GetWin32ShortcutTarget(5)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   int integers  = ArraySize(buffer);
   int charsSize = bytes;
   int chars[]; ArrayResize(chars, charsSize);     // int-Array in char-Array umwandeln

   for (int i, n=0; i < integers; i++) {
      for (int shift=0; shift<32 && n<charsSize; shift+=8, n++) {
         chars[n] = buffer[i] >> shift & 0xFF;
      }
   }

   // --------------------------------------------------------------------------
   // Check the magic value (first byte) and the GUID (16 byte from 5th byte):
   // --------------------------------------------------------------------------
   // The GUID is telling the version of the .lnk-file format. We expect the
   // following GUID (hex): 01 14 02 00 00 00 00 00 C0 00 00 00 00 00 00 46.
   // --------------------------------------------------------------------------
   if (chars[0] != 'L')                            // test the magic value
      return(_empty(catch("GetWin32ShortcutTarget(6)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   if (chars[ 4] != 0x01 ||                        // test the GUID
       chars[ 5] != 0x14 ||
       chars[ 6] != 0x02 ||
       chars[ 7] != 0x00 ||
       chars[ 8] != 0x00 ||
       chars[ 9] != 0x00 ||
       chars[10] != 0x00 ||
       chars[11] != 0x00 ||
       chars[12] != 0xC0 ||
       chars[13] != 0x00 ||
       chars[14] != 0x00 ||
       chars[15] != 0x00 ||
       chars[16] != 0x00 ||
       chars[17] != 0x00 ||
       chars[18] != 0x00 ||
       chars[19] != 0x46) {
      return(_empty(catch("GetWin32ShortcutTarget(7)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));
   }

   // --------------------------------------------------------------------------
   // Get the flags (4 byte from 21st byte) and
   // --------------------------------------------------------------------------
   // Check if it points to a file or directory.
   // --------------------------------------------------------------------------
   // Flags (4 byte little endian):
   //        Bit 0 -> has shell item id list
   //        Bit 1 -> points to file or directory
   //        Bit 2 -> has description
   //        Bit 3 -> has relative path
   //        Bit 4 -> has working directory
   //        Bit 5 -> has commandline arguments
   //        Bit 6 -> has custom icon
   // --------------------------------------------------------------------------
   int dwFlags  = chars[20];
       dwFlags |= chars[21] <<  8;
       dwFlags |= chars[22] << 16;
       dwFlags |= chars[23] << 24;

   bool hasShellItemIdList = (dwFlags & 0x00000001 == 0x00000001);
   bool pointsToFileOrDir  = (dwFlags & 0x00000002 == 0x00000002);

   if (!pointsToFileOrDir)
      return(_empty(log("GetWin32ShortcutTarget(8)  shortcut target is not a file or directory: \""+ lnkFilename +"\"")));

   // --------------------------------------------------------------------------
   // Shell item id list (starts at offset 76 with 2 byte length):
   // --------------------------------------------------------------------------
   int A = -6;
   if (hasShellItemIdList) {
      i = 76;
      if (charsSize < i+2)
         return(_empty(catch("GetWin32ShortcutTarget(8)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));
      A  = chars[76];               // little endian format
      A |= chars[77] << 8;
   }

   // --------------------------------------------------------------------------
   // File location info:
   // --------------------------------------------------------------------------
   // Follows the shell item id list and starts with 4 byte structure length,
   // followed by 4 byte offset.
   // --------------------------------------------------------------------------
   i = 78 + 4 + A;
   if (charsSize < i+4)
      return(_empty(catch("GetWin32ShortcutTarget(9)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   int B  = chars[i];       i++;    // little endian format
       B |= chars[i] <<  8; i++;
       B |= chars[i] << 16; i++;
       B |= chars[i] << 24;

   // --------------------------------------------------------------------------
   // Local volume table:
   // --------------------------------------------------------------------------
   // Follows the file location info and starts with 4 byte table length for
   // skipping the actual table and moving to the local path string.
   // --------------------------------------------------------------------------
   i = 78 + A + B;
   if (charsSize < i+4)
      return(_empty(catch("GetWin32ShortcutTarget(10)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   int C  = chars[i];       i++;    // little endian format
       C |= chars[i] <<  8; i++;
       C |= chars[i] << 16; i++;
       C |= chars[i] << 24;

   // --------------------------------------------------------------------------
   // Local path string (ending with 0x00):
   // --------------------------------------------------------------------------
   i = 78 + A + B + C;
   if (charsSize < i+1)
      return(_empty(catch("GetWin32ShortcutTarget(11)  unknown .lnk file format in \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   string target = "";
   for (; i < charsSize; i++) {
      if (chars[i] == 0x00)
         break;
      target = StringConcatenate(target, CharToStr(chars[i]));
   }
   if (StringLen(target) == 0)
      return(_empty(catch("GetWin32ShortcutTarget(12)  invalid target in .lnk file \""+ lnkFilename +"\"", ERR_RUNTIME_ERROR)));

   // --------------------------------------------------------------------------
   // Convert the target path into the long filename format:
   // --------------------------------------------------------------------------
   // GetLongPathNameA() fails if the target file doesn't exist!
   // --------------------------------------------------------------------------
   string lfnBuffer[]; InitializeStringBuffer(lfnBuffer, MAX_PATH);
   if (GetLongPathNameA(target, lfnBuffer[0], MAX_PATH) != 0)        // file does exist
      target = lfnBuffer[0];

   //debug("GetWin32ShortcutTarget()   chars="+ ArraySize(chars) +"   A="+ A +"   B="+ B +"   C="+ C +"   target=\""+ target +"\"");

   if (IsError(catch("GetWin32ShortcutTarget(13)")))
      return("");
   return(target);
}


/**
 * Schickt per PostMessage() einen einzelnen Fake-Tick an den aktuellen Chart.
 *
 * @param  bool sound - ob der Tick akustisch best�tigt werden soll oder nicht (default: nein)
 *
 * @return int - Fehlerstatus (-1, wenn das Script im Backtester l�uft und WindowHandle() nicht benutzt werden kann)
 */
int SendTick(bool sound=false) {
   if (IsTesting()) {
      debug("SendTick()   skipping in tester");    // TODO: IsTesting() funktioniert nicht in Indikatoren
      return(-1);
   }

   if (WM_MT4 == 0)
      WM_MT4 = RegisterWindowMessageA("MetaTrader4_Internal_Message");

   int hWnd = WindowHandle(Symbol(), Period());
   if (hWnd == 0)
      return(catch("SendTick(1) ->WindowHandle() = "+ hWnd, ERR_RUNTIME_ERROR));

   PostMessageA(hWnd, WM_MT4, 2, 1);
   if (sound)
      PlaySound("tick1.wav");
   return(catch("SendTick(2)"));
}


/**
 * Gibt den Namen des aktuellen Kurshistory-Verzeichnisses zur�ck.  Der Name ist bei bestehender Verbindung identisch mit dem R�ckgabewert von AccountServer(),
 * l��t sich mit dieser Funktion aber auch ohne Verbindung und bei Accountwechsel zuverl�ssig ermitteln.
 *
 * @return string - Verzeichnisname oder Leerstring, wenn ein Fehler auftrat
 */
string GetTradeServerDirectory() {
   // Der Verzeichnisname wird zwischengespeichert und erst mit Auftreten von ValidBars = 0 verworfen und neu ermittelt.  Bei Accountwechsel zeigen
   // die R�ckgabewerte der MQL-Accountfunktionen evt. schon auf den neuen Account, der aktuelle Tick geh�rt aber noch zum alten Chart des alten Verzeichnisses.
   // Erst ValidBars = 0 stellt sicher, da� wir uns tats�chlich im neuen Verzeichnis befinden.

   static string cache.directory[];
   static int    lastTick;                                           // hilft bei der Erkennung von Mehrfachaufrufen w�hrend desselben Ticks

   // 1) wenn ValidBars==0 && neuer Tick, Cache verwerfen
   if (ValidBars == 0) /*&&*/ if (Tick != lastTick)
      ArrayResize(cache.directory, 0);
   lastTick = Tick;

   // 2) wenn Wert im Cache, gecachten Wert zur�ckgeben
   if (ArraySize(cache.directory) > 0)
      return(cache.directory[0]);

   // 3.1) Wert ermitteln
   string directory = AccountServer();

   // 3.2) wenn AccountServer() == "", Verzeichnis manuell ermitteln
   if (StringLen(directory) == 0) {
      // eindeutigen Dateinamen erzeugen und tempor�re Datei anlegen
      string fileName = StringConcatenate("_t", GetCurrentThreadId(), ".tmp");
      int hFile = FileOpenHistory(fileName, FILE_BIN|FILE_WRITE);
      if (hFile < 0)                                                 // u.a. wenn das Serververzeichnis noch nicht existiert
         return(_empty(catch("GetTradeServerDirectory(1)->FileOpenHistory(\""+ fileName +"\")")));
      FileClose(hFile);

      // Datei suchen und Verzeichnisnamen auslesen
      string pattern = StringConcatenate(TerminalPath(), "\\history\\*");
      /*WIN32_FIND_DATA*/int wfd[]; InitializeBuffer(wfd, WIN32_FIND_DATA.size);
      int hFindDir=FindFirstFileA(pattern, wfd), result=hFindDir;

      while (result > 0) {
         if (wfd.FileAttribute.Directory(wfd)) {
            string name = wfd.FileName(wfd);
            if (name != ".") /*&&*/ if (name != "..") {
               pattern = StringConcatenate(TerminalPath(), "\\history\\", name, "\\", fileName);
               int hFindFile = FindFirstFileA(pattern, wfd);
               if (hFindFile == INVALID_HANDLE_VALUE) {
                  // hier m��te eigentlich auf ERR_FILE_NOT_FOUND gepr�ft werden, doch MQL kann es nicht
               }
               else {
                  //debug("FindTradeServerDirectory()   file = "+ pattern +"   found");
                  FindClose(hFindFile);
                  directory = name;
                  if (!DeleteFileA(pattern))                         // tmp. Datei per Win-API l�schen (MQL kann es im History-Verzeichnis nicht)
                     return(catch("GetTradeServerDirectory(2) ->kernel32::DeleteFileA(filename=\""+ pattern +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));
                  break;
               }
            }
         }
         result = FindNextFileA(hFindDir, wfd);
      }
      if (result == INVALID_HANDLE_VALUE)
         return(_empty(catch("GetTradeServerDirectory(3) ->kernel32::FindFirstFileA(filename=\""+ pattern +"\")   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));
      FindClose(hFindDir);
      //debug("GetTradeServerDirectory()   resolved directory = \""+ directory +"\"");
   }

   int error = GetLastError();
   if (IsError(error))
      return(_empty(catch("GetTradeServerDirectory(4)", error)));

   if (StringLen(directory) == 0)
      return(_empty(catch("GetTradeServerDirectory(5)  cannot find trade server directory", ERR_RUNTIME_ERROR)));

   // 3.3) Wert cachen
   ArrayResize(cache.directory, 1);
   cache.directory[0] = directory;

   return(directory);
}


/**
 * Gibt den Kurznamen der Firma des aktuellen Accounts zur�ck. Der Name wird aus dem Namen des Account-Servers und
 * nicht aus dem R�ckgabewert von AccountCompany() ermittelt.
 *
 * @return string - Kurzname
 */
string ShortAccountCompany() {
   string server=StringToLower(GetTradeServerDirectory());

   if      (StringStartsWith(server, "alpari-"            )) return("Alpari"          );
   else if (StringStartsWith(server, "alparibroker-"      )) return("Alpari"          );
   else if (StringStartsWith(server, "alpariuk-"          )) return("Alpari"          );
   else if (StringStartsWith(server, "alparius-"          )) return("Alpari"          );
   else if (StringStartsWith(server, "apbgtrading-"       )) return("APBG"            );
   else if (StringStartsWith(server, "atcbrokers-"        )) return("ATC Brokers"     );
   else if (StringStartsWith(server, "atcbrokersest-"     )) return("ATC Brokers"     );
   else if (StringStartsWith(server, "atcbrokersliq1-"    )) return("ATC Brokers"     );
   else if (StringStartsWith(server, "broco-"             )) return("BroCo"           );
   else if (StringStartsWith(server, "brocoinvestments-"  )) return("BroCo"           );
   else if (StringStartsWith(server, "dukascopy-"         )) return("Dukascopy"       );
   else if (StringStartsWith(server, "easyforex-"         )) return("EasyForex"       );
   else if (StringStartsWith(server, "finfx-"             )) return("FinFX"           );
   else if (StringStartsWith(server, "forex-"             )) return("Forex Ltd"       );
   else if (StringStartsWith(server, "forexbaltic-"       )) return("FB Capital"      );
   else if (StringStartsWith(server, "fxprimus-"          )) return("FX Primus"       );
   else if (StringStartsWith(server, "fxpro.com-"         )) return("FxPro"           );
   else if (StringStartsWith(server, "fxdd-"              )) return("FXDD"            );
   else if (StringStartsWith(server, "gcmfx-"             )) return("Gallant"         );
   else if (StringStartsWith(server, "inovatrade-"        )) return("InovaTrade"      );
   else if (StringStartsWith(server, "investorseurope-"   )) return("Investors Europe");
   else if (StringStartsWith(server, "londoncapitalgr-"   )) return("London Capital"  );
   else if (StringStartsWith(server, "londoncapitalgroup-")) return("London Capital"  );
   else if (StringStartsWith(server, "mbtrading-"         )) return("MB Trading"      );
   else if (StringStartsWith(server, "migbank-"           )) return("MIG"             );
   else if (StringStartsWith(server, "oanda-"             )) return("Oanda"           );
   else if (StringStartsWith(server, "sig-"               )) return("SIG"             );
   else if (StringStartsWith(server, "sts-"               )) return("STS"             );
   else if (StringStartsWith(server, "teletrade-"         )) return("TeleTrade"       );

   return(AccountCompany());
}


/**
 * F�hrt eine Anwendung aus und wartet, bis sie beendet ist.
 *
 * @param  string cmdLine - Befehlszeile
 * @param  int    cmdShow - ShowWindow() command id
 *
 * @return int - Fehlerstatus
 */
int WinExecAndWait(string cmdLine, int cmdShow) {
   string sNull;
   int    iNull[];

   /*STARTUPINFO*/int si[]; InitializeBuffer(si, STARTUPINFO.size);
      si.setCb        (si, STARTUPINFO.size);
      si.setFlags     (si, STARTF_USESHOWWINDOW);
      si.setShowWindow(si, cmdShow);

   /*PROCESS_INFORMATION*/int pi[]; InitializeBuffer(pi, PROCESS_INFORMATION.size);

   if (!CreateProcessA(sNull, cmdLine, iNull, iNull, false, 0, iNull, sNull, si, pi))
      return(catch("WinExecAndWait(1) ->kernel32::CreateProcessA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));

   int result = WaitForSingleObject(pi.hProcess(pi), INFINITE);

   if (result != WAIT_OBJECT_0) {
      if (result == WAIT_FAILED) catch("WinExecAndWait(2) ->kernel32::WaitForSingleObject()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR);
      else                       log("WinExecAndWait() ->kernel32::WaitForSingleObject() => "+ WaitForSingleObjectValueToStr(result));
   }

   CloseHandle(pi.hProcess(pi));
   CloseHandle(pi.hThread(pi));

   return(catch("WinExecAndWait(3)"));
}


/**
 * Liest eine Datei zeilenweise (ohne Zeilenende-Zeichen) in ein Array ein.
 *
 * @param  string filename       - Dateiname mit zu "{terminal-path}\experts\files" relativer Pfadangabe
 * @param  string result[]       - Ergebnisarray f�r die Zeilen der Datei
 * @param  bool   skipEmptyLines - ob leere Zeilen �bersprungen werden sollen oder nicht (default: FALSE)
 *
 * @return int - Anzahl der eingelesenen Zeilen oder -1, falls ein Fehler auftrat
 */
int FileReadLines(string filename, string result[], bool skipEmptyLines=false) {
   int fieldSeparator = '\t';

   // Datei �ffnen
   int hFile = FileOpen(filename, FILE_CSV|FILE_READ, fieldSeparator);  // FileOpen() erwartet Pfadangabe relativ zu .\experts\files
   if (hFile < 0)
      return(_int(-1, catch("FileReadLines(1)->FileOpen(\""+ filename +"\")", GetLastError())));


   // Schnelle R�ckkehr bei leerer Datei
   if (FileSize(hFile) == 0) {
      FileClose(hFile);
      ArrayResize(result, 0);
      return(ifInt(IsError(catch("FileReadLines(2)")), -1, 0));
   }


   // Datei zeilenweise einlesen
   bool newLine=true, blankLine=false, lineEnd=true;
   string line, lines[]; ArrayResize(lines, 0);                         // Zwischenspeicher f�r gelesene Zeilen
   int i = 0;                                                           // Zeilenz�hler

   while (!FileIsEnding(hFile)) {
      newLine = false;
      if (lineEnd) {                                                    // Wenn beim letzten Durchlauf das Zeilenende erreicht wurde,
         newLine   = true;                                              // Flags auf Zeilenbeginn setzen.
         blankLine = false;
         lineEnd   = false;
      }

      // Zeile auslesen
      string value = FileReadString(hFile);

      // auf Zeilen- und Dateiende pr�fen
      if (FileIsLineEnding(hFile) || FileIsEnding(hFile)) {
         lineEnd = true;
         if (newLine) {
            if (StringLen(value) == 0) {
               if (FileIsEnding(hFile))                                 // Zeilenbeginn + Leervalue + Dateiende  => nichts, also Abbruch
                  break;
               blankLine = true;                                        // Zeilenbeginn + Leervalue + Zeilenende => Leerzeile
            }
         }
      }

      // Leerzeilen ggf. �berspringen
      if (blankLine) /*&&*/ if (skipEmptyLines)
         continue;

      // Wert in neuer Zeile speichern oder vorherige Zeile aktualisieren
      if (newLine) {
         i++;
         ArrayResize(lines, i);
         lines[i-1] = value;
         //log("FileReadLines()   new line = \""+ lines[i-1] +"\"");
      }
      else {
         lines[i-1] = StringConcatenate(lines[i-1], CharToStr(fieldSeparator), value);
         //log("FileReadLines()   updated line = \""+ lines[i-1] +"\"");
      }
   }

   // Dateiende hat ERR_END_OF_FILE ausgel�st
   int error = GetLastError();
   if (error!=ERR_END_OF_FILE) /*&&*/ if (IsError(error)) {
      FileClose(hFile);
      return(_int(-1, catch("FileReadLines(2)", error)));
   }

   // Datei schlie�en
   FileClose(hFile);

   // Zeilen in Ergebnisarray kopieren
   ArrayResize(result, i);
   if (i > 0)
      ArrayCopy(result, lines);

   return(ifInt(catch("FileReadLines(3)")==NO_ERROR, i, -1));
}


/**
 * Gibt die lesbare Version eines R�ckgabewertes von WaitForSingleObject() zur�ck.
 *
 * @param  int value - R�ckgabewert
 *
 * @return string
 */
string WaitForSingleObjectValueToStr(int value) {
   switch (value) {
      case WAIT_FAILED   : return("WAIT_FAILED"   );
      case WAIT_ABANDONED: return("WAIT_ABANDONED");
      case WAIT_OBJECT_0 : return("WAIT_OBJECT_0" );
      case WAIT_TIMEOUT  : return("WAIT_TIMEOUT"  );
   }
   return("");
}


/**
 * Gibt das Standardsymbol des aktuellen Symbols zur�ck.
 * (z.B. StdSymbol() => "EURUSD")
 *
 * @return string - Standardsymbol oder das aktuelle Symbol, wenn das Standardsymbol unbekannt ist
 *
 *
 * NOTE:
 * -----
 * Alias f�r GetStandardSymbol(Symbol())
 *
 * @see GetStandardSymbol()
 */
string StdSymbol() {
   static string stdSymbol[1];                                       // Um Strings timeframe�bergreifend statisch zu speichern, m�ssen sie in einem Array abgelegt werden.
   static bool   done;
   if (!done) {
      stdSymbol[0] = GetStandardSymbol(Symbol());
      done = true;
   }
   return(stdSymbol[0]);
}


/**
 * Gibt f�r ein broker-spezifisches Symbol das Standardsymbol zur�ck.
 * (z.B. GetStandardSymbol("EURUSDm") => "EURUSD")
 *
 * @param  string symbol - broker-spezifisches Symbol
 *
 * @return string - Standardsymbol oder der �bergebene Ausgangswert, wenn das Brokersymbol unbekannt ist
 *
 *
 * NOTE:
 * -----
 * Alias f�r GetStandardSymbolOrAlt(symbol, symbol)
 *
 * @see GetStandardSymbolStrict()
 * @see GetStandardSymbolOrAlt()
 */
string GetStandardSymbol(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetStandardSymbol()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));
   return(GetStandardSymbolOrAlt(symbol, symbol));
}


/**
 * Gibt f�r ein broker-spezifisches Symbol das Standardsymbol oder den angegebenen Alternativwert zur�ck.
 * (z.B. GetStandardSymbolOrAlt("EURUSDm") => "EURUSD")
 *
 * @param  string symbol   - broker-spezifisches Symbol
 * @param  string altValue - alternativer R�ckgabewert, falls kein Standardsymbol gefunden wurde
 *
 * @return string - Ergebnis
 *
 *
 * NOTE:
 * -----
 * Im Unterschied zu GetStandardSymbolStrict() erlaubt diese Funktion die bequeme Angabe eines Alternativwertes, l��t jedoch nicht mehr so
 * einfach erkennen, ob ein Standardsymbol gefunden wurde oder nicht.
 *
 * @see GetStandardSymbolStrict()
 */
string GetStandardSymbolOrAlt(string symbol, string altValue="") {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetStandardSymbolOrAlt()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string value = GetStandardSymbolStrict(symbol);

   if (StringLen(value) == 0)
      value = altValue;

   return(value);
}


/**
 * Gibt f�r ein broker-spezifisches Symbol das Standardsymbol zur�ck.
 * (z.B. GetStandardSymbolStrict("EURUSDm") => "EURUSD")
 *
 * @param  string symbol - Broker-spezifisches Symbol
 *
 * @return string - Standardsymbol oder Leerstring, wenn kein Standardsymbol gefunden wurde.
 *
 *
 * @see GetStandardSymbolOrAlt() - f�r die Angabe eines Alternativwertes, wenn kein Standardsymbol gefunden wurde
 */
string GetStandardSymbolStrict(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetStandardSymbolStrict()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   symbol = StringToUpper(symbol);

   if      (StringEndsWith(symbol, "_ASK")) symbol = StringLeft(symbol, -4);
   else if (StringEndsWith(symbol, "_AVG")) symbol = StringLeft(symbol, -4);

   switch (StringGetChar(symbol, 0)) {
      case '#': if (symbol == "#DAX.XEI" ) return("#DAX.X");
                if (symbol == "#DJI.XDJ" ) return("#DJI.X");
                if (symbol == "#DJT.XDJ" ) return("#DJT.X");
                if (symbol == "#SPX.X.XP") return("#SPX.X");
                break;

      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9': break;

      case 'A': if (StringStartsWith(symbol, "AUDCAD")) return("AUDCAD");
                if (StringStartsWith(symbol, "AUDCHF")) return("AUDCHF");
                if (StringStartsWith(symbol, "AUDDKK")) return("AUDDKK");
                if (StringStartsWith(symbol, "AUDJPY")) return("AUDJPY");
                if (StringStartsWith(symbol, "AUDLFX")) return("AUDLFX");
                if (StringStartsWith(symbol, "AUDNZD")) return("AUDNZD");
                if (StringStartsWith(symbol, "AUDPLN")) return("AUDPLN");
                if (StringStartsWith(symbol, "AUDSGD")) return("AUDSGD");
                if (StringStartsWith(symbol, "AUDUSD")) return("AUDUSD");
                break;

      case 'B': break;

      case 'C': if (StringStartsWith(symbol, "CADCHF")) return("CADCHF");
                if (StringStartsWith(symbol, "CADJPY")) return("CADJPY");
                if (StringStartsWith(symbol, "CADLFX")) return("CADLFX");
                if (StringStartsWith(symbol, "CADSGD")) return("CADSGD");
                if (StringStartsWith(symbol, "CHFJPY")) return("CHFJPY");
                if (StringStartsWith(symbol, "CHFLFX")) return("CHFLFX");
                if (StringStartsWith(symbol, "CHFPLN")) return("CHFPLN");
                if (StringStartsWith(symbol, "CHFSGD")) return("CHFSGD");
                if (StringStartsWith(symbol, "CHFZAR")) return("CHFZAR");
                break;

      case 'D': break;

      case 'E': if (StringStartsWith(symbol, "EURAUD")) return("EURAUD");
                if (StringStartsWith(symbol, "EURCAD")) return("EURCAD");
                if (StringStartsWith(symbol, "EURCCK")) return("EURCZK");
                if (StringStartsWith(symbol, "EURCZK")) return("EURCZK");
                if (StringStartsWith(symbol, "EURCHF")) return("EURCHF");
                if (StringStartsWith(symbol, "EURDKK")) return("EURDKK");
                if (StringStartsWith(symbol, "EURGBP")) return("EURGBP");
                if (StringStartsWith(symbol, "EURHKD")) return("EURHKD");
                if (StringStartsWith(symbol, "EURHUF")) return("EURHUF");
                if (StringStartsWith(symbol, "EURJPY")) return("EURJPY");
                if (StringStartsWith(symbol, "EURLFX")) return("EURLFX");
                if (StringStartsWith(symbol, "EURLVL")) return("EURLVL");
                if (StringStartsWith(symbol, "EURMXN")) return("EURMXN");
                if (StringStartsWith(symbol, "EURNOK")) return("EURNOK");
                if (StringStartsWith(symbol, "EURNZD")) return("EURNZD");
                if (StringStartsWith(symbol, "EURPLN")) return("EURPLN");
                if (StringStartsWith(symbol, "EURRUB")) return("EURRUB");
                if (StringStartsWith(symbol, "EURRUR")) return("EURRUB");
                if (StringStartsWith(symbol, "EURSEK")) return("EURSEK");
                if (StringStartsWith(symbol, "EURSGD")) return("EURSGD");
                if (StringStartsWith(symbol, "EURTRY")) return("EURTRY");
                if (StringStartsWith(symbol, "EURUSD")) return("EURUSD");
                if (StringStartsWith(symbol, "EURZAR")) return("EURZAR");
                if (symbol == "ECX" )                   return("EURX"  );
                if (symbol == "EURX")                   return("EURX"  );
                break;

      case 'F': break;

      case 'G': if (StringStartsWith(symbol, "GBPAUD")) return("GBPAUD");
                if (StringStartsWith(symbol, "GBPCAD")) return("GBPCAD");
                if (StringStartsWith(symbol, "GBPCHF")) return("GBPCHF");
                if (StringStartsWith(symbol, "GBPDKK")) return("GBPDKK");
                if (StringStartsWith(symbol, "GBPJPY")) return("GBPJPY");
                if (StringStartsWith(symbol, "GBPLFX")) return("GBPLFX");
                if (StringStartsWith(symbol, "GBPNOK")) return("GBPNOK");
                if (StringStartsWith(symbol, "GBPNZD")) return("GBPNZD");
                if (StringStartsWith(symbol, "GBPPLN")) return("GBPPLN");
                if (StringStartsWith(symbol, "GBPRUB")) return("GBPRUB");
                if (StringStartsWith(symbol, "GBPRUR")) return("GBPRUB");
                if (StringStartsWith(symbol, "GBPSEK")) return("GBPSEK");
                if (StringStartsWith(symbol, "GBPUSD")) return("GBPUSD");
                if (StringStartsWith(symbol, "GBPZAR")) return("GBPZAR");
                if (symbol == "GOLD"    )               return("XAUUSD");
                if (symbol == "GOLDEURO")               return("XAUEUR");
                break;

      case 'H': if (StringStartsWith(symbol, "HKDJPY")) return("HKDJPY");
                break;

      case 'I':
      case 'J':
      case 'K': break;

      case 'L': if (StringStartsWith(symbol, "LFXJPY")) return("LFXJPY");
                break;

      case 'M': if (StringStartsWith(symbol, "MXNJPY")) return("MXNJPY");
                break;

      case 'N': if (StringStartsWith(symbol, "NOKJPY")) return("NOKJPY");
                if (StringStartsWith(symbol, "NOKSEK")) return("NOKSEK");
                if (StringStartsWith(symbol, "NZDCAD")) return("NZDCAD");
                if (StringStartsWith(symbol, "NZDCHF")) return("NZDCHF");
                if (StringStartsWith(symbol, "NZDJPY")) return("NZDJPY");
                if (StringStartsWith(symbol, "NZDLFX")) return("NZDLFX");
                if (StringStartsWith(symbol, "NZDSGD")) return("NZDSGD");
                if (StringStartsWith(symbol, "NZDUSD")) return("NZDUSD");
                break;

      case 'O': break;

      case 'P': if (StringStartsWith(symbol, "PLNJPY")) return("PLNJPY");
                break;

      case 'Q': break;

      case 'S': if (StringStartsWith(symbol, "SEKJPY")) return("SEKJPY");
                if (StringStartsWith(symbol, "SGDJPY")) return("SGDJPY");
                if (symbol == "SILVER"    )             return("XAGUSD");
                if (symbol == "SILVEREURO")             return("XAGEUR");
                break;

      case 'T': break;
                if (StringStartsWith(symbol, "TRYJPY")) return("TRYJPY");

      case 'U': if (StringStartsWith(symbol, "USDCAD")) return("USDCAD");
                if (StringStartsWith(symbol, "USDCHF")) return("USDCHF");
                if (StringStartsWith(symbol, "USDCCK")) return("USDCZK");
                if (StringStartsWith(symbol, "USDCNY")) return("USDCNY");
                if (StringStartsWith(symbol, "USDCZK")) return("USDCZK");
                if (StringStartsWith(symbol, "USDDKK")) return("USDDKK");
                if (StringStartsWith(symbol, "USDHKD")) return("USDHKD");
                if (StringStartsWith(symbol, "USDHRK")) return("USDHRK");
                if (StringStartsWith(symbol, "USDHUF")) return("USDHUF");
                if (StringStartsWith(symbol, "USDINR")) return("USDINR");
                if (StringStartsWith(symbol, "USDJPY")) return("USDJPY");
                if (StringStartsWith(symbol, "USDLFX")) return("USDLFX");
                if (StringStartsWith(symbol, "USDLTL")) return("USDLTL");
                if (StringStartsWith(symbol, "USDLVL")) return("USDLVL");
                if (StringStartsWith(symbol, "USDMXN")) return("USDMXN");
                if (StringStartsWith(symbol, "USDNOK")) return("USDNOK");
                if (StringStartsWith(symbol, "USDPLN")) return("USDPLN");
                if (StringStartsWith(symbol, "USDRUB")) return("USDRUB");
                if (StringStartsWith(symbol, "USDRUR")) return("USDRUB");
                if (StringStartsWith(symbol, "USDSEK")) return("USDSEK");
                if (StringStartsWith(symbol, "USDSAR")) return("USDSAR");
                if (StringStartsWith(symbol, "USDSGD")) return("USDSGD");
                if (StringStartsWith(symbol, "USDTHB")) return("USDTHB");
                if (StringStartsWith(symbol, "USDTRY")) return("USDTRY");
                if (StringStartsWith(symbol, "USDTWD")) return("USDTWD");
                if (StringStartsWith(symbol, "USDZAR")) return("USDZAR");
                if (symbol == "USDX")                   return("USDX"  );
                break;

      case 'V':
      case 'W': break;

      case 'X': if (StringStartsWith(symbol, "XAGEUR")) return("XAGEUR");
                if (StringStartsWith(symbol, "XAGJPY")) return("XAGJPY");
                if (StringStartsWith(symbol, "XAGUSD")) return("XAGUSD");
                if (StringStartsWith(symbol, "XAUEUR")) return("XAUEUR");
                if (StringStartsWith(symbol, "XAUJPY")) return("XAUJPY");
                if (StringStartsWith(symbol, "XAUUSD")) return("XAUUSD");
                break;

      case 'Y': break;

      case 'Z': if (StringStartsWith(symbol, "ZARJPY")) return("ZARJPY");

      case '_': if (symbol == "_DJI"   ) return("#DJI.X"  );
                if (symbol == "_DJT"   ) return("#DJT.X"  );
                if (symbol == "_N225"  ) return("#NIK.X"  );
                if (symbol == "_NQ100" ) return("#N100.X" );
                if (symbol == "_NQCOMP") return("#NCOMP.X");
                if (symbol == "_SP500" ) return("#SPX.X"  );
                break;
   }

   return("");
}


/**
 * Gibt den Kurznamen eines Symbols zur�ck.
 * (z.B. GetSymbolName("EURUSD") => "EUR/USD")
 *
 * @param  string symbol - broker-spezifisches Symbol
 *
 * @return string - Kurzname oder der �bergebene Ausgangswert, wenn das Symbol unbekannt ist
 *
 *
 * NOTE:
 * -----
 * Alias f�r GetSymbolNameOrAlt(symbol, symbol)
 *
 * @see GetSymbolNameStrict()
 * @see GetSymbolNameOrAlt()
 */
string GetSymbolName(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetSymbolName()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));
   return(GetSymbolNameOrAlt(symbol, symbol));
}


/**
 * Gibt den Kurznamen eines Symbols zur�ck oder den angegebenen Alternativwert, wenn das Symbol unbekannt ist.
 * (z.B. GetSymbolNameOrAlt("EURUSD") => "EUR/USD")
 *
 * @param  string symbol   - Symbol
 * @param  string altValue - alternativer R�ckgabewert
 *
 * @return string - Ergebnis
 *
 * @see GetSymbolNameStrict()
 */
string GetSymbolNameOrAlt(string symbol, string altValue="") {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetSymbolNameOrAlt()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string value = GetSymbolNameStrict(symbol);

   if (StringLen(value) == 0)
      value = altValue;

   return(value);
}


/**
 * Gibt den Kurznamen eines Symbols zur�ck.
 * (z.B. GetSymbolNameStrict("EURUSD") => "EUR/USD")
 *
 * @param  string symbol - Symbol
 *
 * @return string - Kurzname oder Leerstring, wenn das Symbol unbekannt ist
 */
string GetSymbolNameStrict(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetSymbolNameStrict()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   symbol = GetStandardSymbolStrict(symbol);
   if (StringLen(symbol) == 0)
      return("");

   if (symbol == "#DAX.X"  ) return("DAX"      );
   if (symbol == "#DJI.X"  ) return("DJIA"     );
   if (symbol == "#DJT.X"  ) return("DJTA"     );
   if (symbol == "#N100.X" ) return("N100"     );
   if (symbol == "#NCOMP.X") return("NCOMP"    );
   if (symbol == "#NIK.X"  ) return("Nikkei"   );
   if (symbol == "#SPX.X"  ) return("SP500"    );
   if (symbol == "AUDCAD"  ) return("AUD/CAD"  );
   if (symbol == "AUDCHF"  ) return("AUD/CHF"  );
   if (symbol == "AUDDKK"  ) return("AUD/DKK"  );
   if (symbol == "AUDJPY"  ) return("AUD/JPY"  );
   if (symbol == "AUDLFX"  ) return("AUD-Index");
   if (symbol == "AUDNZD"  ) return("AUD/NZD"  );
   if (symbol == "AUDPLN"  ) return("AUD/PLN"  );
   if (symbol == "AUDSGD"  ) return("AUD/SGD"  );
   if (symbol == "AUDUSD"  ) return("AUD/USD"  );
   if (symbol == "CADCHF"  ) return("CAD/CHF"  );
   if (symbol == "CADJPY"  ) return("CAD/JPY"  );
   if (symbol == "CADLFX"  ) return("CAD-Index");
   if (symbol == "CADSGD"  ) return("CAD/SGD"  );
   if (symbol == "CHFJPY"  ) return("CHF/JPY"  );
   if (symbol == "CHFLFX"  ) return("CHF-Index");
   if (symbol == "CHFPLN"  ) return("CHF/PLN"  );
   if (symbol == "CHFSGD"  ) return("CHF/SGD"  );
   if (symbol == "CHFZAR"  ) return("CHF/ZAR"  );
   if (symbol == "EURAUD"  ) return("EUR/AUD"  );
   if (symbol == "EURCAD"  ) return("EUR/CAD"  );
   if (symbol == "EURCHF"  ) return("EUR/CHF"  );
   if (symbol == "EURCZK"  ) return("EUR/CZK"  );
   if (symbol == "EURDKK"  ) return("EUR/DKK"  );
   if (symbol == "EURGBP"  ) return("EUR/GBP"  );
   if (symbol == "EURHKD"  ) return("EUR/HKD"  );
   if (symbol == "EURHUF"  ) return("EUR/HUF"  );
   if (symbol == "EURJPY"  ) return("EUR/JPY"  );
   if (symbol == "EURLFX"  ) return("EUR-Index");
   if (symbol == "EURLVL"  ) return("EUR/LVL"  );
   if (symbol == "EURMXN"  ) return("EUR/MXN"  );
   if (symbol == "EURNOK"  ) return("EUR/NOK"  );
   if (symbol == "EURNZD"  ) return("EUR/NZD"  );
   if (symbol == "EURPLN"  ) return("EUR/PLN"  );
   if (symbol == "EURRUB"  ) return("EUR/RUB"  );
   if (symbol == "EURSEK"  ) return("EUR/SEK"  );
   if (symbol == "EURSGD"  ) return("EUR/SGD"  );
   if (symbol == "EURTRY"  ) return("EUR/TRY"  );
   if (symbol == "EURUSD"  ) return("EUR/USD"  );
   if (symbol == "EURX"    ) return("EUR-Index");
   if (symbol == "EURZAR"  ) return("EUR/ZAR"  );
   if (symbol == "GBPAUD"  ) return("GBP/AUD"  );
   if (symbol == "GBPCAD"  ) return("GBP/CAD"  );
   if (symbol == "GBPCHF"  ) return("GBP/CHF"  );
   if (symbol == "GBPDKK"  ) return("GBP/DKK"  );
   if (symbol == "GBPJPY"  ) return("GBP/JPY"  );
   if (symbol == "GBPLFX"  ) return("GBP-Index");
   if (symbol == "GBPNOK"  ) return("GBP/NOK"  );
   if (symbol == "GBPNZD"  ) return("GBP/NZD"  );
   if (symbol == "GBPPLN"  ) return("GBP/PLN"  );
   if (symbol == "GBPRUB"  ) return("GBP/RUB"  );
   if (symbol == "GBPSEK"  ) return("GBP/SEK"  );
   if (symbol == "GBPUSD"  ) return("GBP/USD"  );
   if (symbol == "GBPZAR"  ) return("GBP/ZAR"  );
   if (symbol == "HKDJPY"  ) return("HKD/JPY"  );
   if (symbol == "LFXJPY"  ) return("JPY-Index");
   if (symbol == "MXNJPY"  ) return("MXN/JPY"  );
   if (symbol == "NOKJPY"  ) return("NOK/JPY"  );
   if (symbol == "NOKSEK"  ) return("NOK/SEK"  );
   if (symbol == "NZDCAD"  ) return("NZD/CAD"  );
   if (symbol == "NZDCHF"  ) return("NZD/CHF"  );
   if (symbol == "NZDJPY"  ) return("NZD/JPY"  );
   if (symbol == "NZDLFX"  ) return("NZD-Index");
   if (symbol == "NZDSGD"  ) return("NZD/SGD"  );
   if (symbol == "NZDUSD"  ) return("NZD/USD"  );
   if (symbol == "PLNJPY"  ) return("PLN/JPY"  );
   if (symbol == "SEKJPY"  ) return("SEK/JPY"  );
   if (symbol == "SGDJPY"  ) return("SGD/JPY"  );
   if (symbol == "TRYJPY"  ) return("TRY/JPY"  );
   if (symbol == "USDCAD"  ) return("USD/CAD"  );
   if (symbol == "USDCHF"  ) return("USD/CHF"  );
   if (symbol == "USDCNY"  ) return("USD/CNY"  );
   if (symbol == "USDCZK"  ) return("USD/CZK"  );
   if (symbol == "USDDKK"  ) return("USD/DKK"  );
   if (symbol == "USDHKD"  ) return("USD/HKD"  );
   if (symbol == "USDHRK"  ) return("USD/HRK"  );
   if (symbol == "USDHUF"  ) return("USD/HUF"  );
   if (symbol == "USDINR"  ) return("USD/INR"  );
   if (symbol == "USDJPY"  ) return("USD/JPY"  );
   if (symbol == "USDLFX"  ) return("USD-Index");
   if (symbol == "USDLTL"  ) return("USD/LTL"  );
   if (symbol == "USDLVL"  ) return("USD/LVL"  );
   if (symbol == "USDMXN"  ) return("USD/MXN"  );
   if (symbol == "USDNOK"  ) return("USD/NOK"  );
   if (symbol == "USDPLN"  ) return("USD/PLN"  );
   if (symbol == "USDRUB"  ) return("USD/RUB"  );
   if (symbol == "USDSAR"  ) return("USD/SAR"  );
   if (symbol == "USDSEK"  ) return("USD/SEK"  );
   if (symbol == "USDSGD"  ) return("USD/SGD"  );
   if (symbol == "USDTHB"  ) return("USD/THB"  );
   if (symbol == "USDTRY"  ) return("USD/TRY"  );
   if (symbol == "USDTWD"  ) return("USD/TWD"  );
   if (symbol == "USDX"    ) return("USD-Index");
   if (symbol == "USDZAR"  ) return("USD/ZAR"  );
   if (symbol == "XAGEUR"  ) return("XAG/EUR"  );
   if (symbol == "XAGJPY"  ) return("XAG/JPY"  );
   if (symbol == "XAGUSD"  ) return("XAG/USD"  );
   if (symbol == "XAUEUR"  ) return("XAU/EUR"  );
   if (symbol == "XAUJPY"  ) return("XAU/JPY"  );
   if (symbol == "XAUUSD"  ) return("XAU/USD"  );
   if (symbol == "ZARJPY"  ) return("ZAR/JPY"  );

   return("");
}


/**
 * Gibt den Langnamen eines Symbols zur�ck.
 * (z.B. GetLongSymbolName("EURUSD") => "EUR/USD")
 *
 * @param  string symbol - broker-spezifisches Symbol
 *
 * @return string - Langname oder der �bergebene Ausgangswert, wenn kein Langname gefunden wurde
 *
 *
 * NOTE:
 * -----
 * Alias f�r GetLongSymbolNameOrAlt(symbol, symbol)
 *
 * @see GetLongSymbolNameStrict()
 * @see GetLongSymbolNameOrAlt()
 */
string GetLongSymbolName(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetLongSymbolName()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));
   return(GetLongSymbolNameOrAlt(symbol, symbol));
}


/**
 * Gibt den Langnamen eines Symbols zur�ck oder den angegebenen Alternativwert, wenn kein Langname gefunden wurde.
 * (z.B. GetLongSymbolNameOrAlt("USDLFX") => "USD-Index (LFX)")
 *
 * @param  string symbol   - Symbol
 * @param  string altValue - alternativer R�ckgabewert
 *
 * @return string - Ergebnis
 */
string GetLongSymbolNameOrAlt(string symbol, string altValue="") {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetLongSymbolNameOrAlt()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string value = GetLongSymbolNameStrict(symbol);

   if (StringLen(value) == 0)
      value = altValue;

   return(value);
}


/**
 * Gibt den Langnamen eines Symbols zur�ck.
 * (z.B. GetLongSymbolNameStrict("USDLFX") => "USD-Index (LFX)")
 *
 * @param  string symbol - Symbol
 *
 * @return string - Langname oder Leerstring, wenn das Symnol unbekannt ist oder keinen Langnamen hat
 */
string GetLongSymbolNameStrict(string symbol) {
   if (StringLen(symbol) == 0)
      return(_empty(catch("GetLongSymbolNameStrict()   invalid parameter symbol: \""+ symbol +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));

   symbol = GetStandardSymbolStrict(symbol);

   if (StringLen(symbol) == 0)
      return("");

   if (symbol == "#DJI.X"  ) return("Dow Jones Industrial"    );
   if (symbol == "#DJT.X"  ) return("Dow Jones Transportation");
   if (symbol == "#N100.X" ) return("Nasdaq 100"              );
   if (symbol == "#NCOMP.X") return("Nasdaq Composite"        );
   if (symbol == "#NIK.X"  ) return("Nikkei 225"              );
   if (symbol == "#SPX.X"  ) return("S&P 500"                 );
   if (symbol == "AUDLFX"  ) return("AUD-Index (LFX)"         );
   if (symbol == "CADLFX"  ) return("CAD-Index (LFX)"         );
   if (symbol == "CHFLFX"  ) return("CHF-Index (LFX)"         );
   if (symbol == "EURLFX"  ) return("EUR-Index (LFX)"         );
   if (symbol == "EURX"    ) return("EUR-Index (CME)"         );
   if (symbol == "GBPLFX"  ) return("GBP-Index (LFX)"         );
   if (symbol == "LFXJPY"  ) return("1/JPY-Index (LFX)"       );
   if (symbol == "NZDLFX"  ) return("NZD-Index (LFX)"         );
   if (symbol == "USDLFX"  ) return("USD-Index (LFX)"         );
   if (symbol == "USDX"    ) return("USD-Index (CME)"         );
   if (symbol == "XAGEUR"  ) return("Silver/EUR"              );
   if (symbol == "XAGJPY"  ) return("Silver/JPY"              );
   if (symbol == "XAGUSD"  ) return("Silver/USD"              );
   if (symbol == "XAUEUR"  ) return("Gold/EUR"                );
   if (symbol == "XAUJPY"  ) return("Gold/JPY"                );
   if (symbol == "XAUUSD"  ) return("Gold/USD"                );

   string prefix = StringLeft(symbol, -3);
   string suffix = StringRight(symbol, 3);

   if      (suffix == ".AB") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Account Balance" ));
   else if (suffix == ".EQ") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Account Equity"  ));
   else if (suffix == ".LV") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Account Leverage"));
   else if (suffix == ".PL") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Profit/Loss"     ));
   else if (suffix == ".FM") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Free Margin"     ));
   else if (suffix == ".UM") if (StringIsDigit(prefix)) return(StringConcatenate("#", prefix, " Used Margin"     ));

   return("");
}


/**
 *
 */
void trace(string script, string function) {
   string stack[];
   int    stackSize = ArraySize(stack);

   if (script != "-1") {
      ArrayResize(stack, stackSize+1);
      stack[stackSize] = StringConcatenate(script, "::", function);
   }
   else if (stackSize > 0) {
      ArrayResize(stack, stackSize-1);
   }

   Print("trace()    ", script, "::", function, "   stackSize=", ArraySize(stack));
}


/**
 * Konvertiert einen Boolean in den String "true" oder "false".
 *
 * @param  bool value
 *
 * @return string
 */
string BoolToStr(bool value) {
   if (value)
      return("true");
   return("false");
}


/**
 * Konvertiert ein Boolean-Array in einen lesbaren String.
 *
 * @param  bool   values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string BoolArrayToStr(bool values[], string separator=", ") {
   if (ArraySize(values) == 0)
      return("{}");
   if (separator == "0")   // NULL
      separator = ", ";
   return(StringConcatenate("{", JoinBools(values, separator), "}"));
}


/**
 * Gibt die aktuelle Zeit in GMT zur�ck.
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime TimeGMT() {
   /*SYSTEMTIME*/int st[]; InitializeBuffer(st, SYSTEMTIME.size);
   GetSystemTime(st);

   int year  = st.Year(st);
   int month = st.Month(st);
   int day   = st.Day(st);
   int hour  = st.Hour(st);
   int min   = st.Minute(st);
   int sec   = st.Second(st);

   string strTime = StringConcatenate(year, ".", month, ".", day, " ", hour, ":", min, ":", sec);
   datetime time  = StrToTime(strTime);

   int error = GetLastError();
   if (IsError(error))
      return(_int(-1, catch("TimeGMT()", error)));

   return(time);
}


/**
 * Inlined conditional String-Statement.
 *
 * @param  bool   condition
 * @param  string thenValue
 * @param  string elseValue
 *
 * @return string
 */
string ifString(bool condition, string thenValue, string elseValue) {
   if (condition)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional Integer-Statement.
 *
 * @param  bool condition
 * @param  int  thenValue
 * @param  int  elseValue
 *
 * @return int
 */
int ifInt(bool condition, int thenValue, int elseValue) {
   if (condition)
      return(thenValue);
   return(elseValue);
}


/**
 * Inlined conditional Double-Statement.
 *
 * @param  bool   condition
 * @param  double thenValue
 * @param  double elseValue
 *
 * @return double
 */
double ifDouble(bool condition, double thenValue, double elseValue) {
   if (condition)
      return(thenValue);
   return(elseValue);
}


/**
 * Gibt die Anzahl der Dezimal- bzw. Nachkommastellen eines Zahlenwertes zur�ck.
 *
 * @param  double number
 *
 * @return int - Anzahl der Nachkommastellen, h�chstens jedoch 8
 */
int CountDecimals(double number) {
   string str = number;
   int dot    = StringFind(str, ".");

   for (int i=StringLen(str)-1; i > dot; i--) {
      if (StringGetChar(str, i) != '0')
         break;
   }
   return(i - dot);
}


/**
 * Gibt den Divisionsrest zweier Doubles zur�ck (fehlerbereinigter Ersatz f�r MathMod()).
 *
 * @param  double a
 * @param  double b
 *
 * @return double - Divisionsrest
 */
double MathModFix(double a, double b) {
   double remainder = MathMod(a, b);
   if (EQ(remainder, b))
      remainder = 0;
   return(remainder);
}


/**
 * Ob ein String mit dem angegebenen Teilstring beginnt. Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string prefix - Substring
 *
 * @return bool
 */
bool StringStartsWith(string object, string prefix) {
   if (StringLen(prefix) == 0) {
      catch("StringStartsWith()   empty prefix \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(object, prefix) == 0);
}


/**
 * Ob ein String mit dem angegebenen Teilstring beginnt. Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object - zu pr�fender String
 * @param  string prefix - Substring
 *
 * @return bool
 */
bool StringIStartsWith(string object, string prefix) {
   if (StringLen(prefix) == 0) {
      catch("StringIStartsWith()   empty prefix \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(StringToUpper(object), StringToUpper(prefix)) == 0);
}


/**
 * Ob ein String mit dem angegebenen Teilstring endet. Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object  - zu pr�fender String
 * @param  string postfix - Substring
 *
 * @return bool
 */
bool StringEndsWith(string object, string postfix) {
   int lenPostfix = StringLen(postfix);
   if (lenPostfix == 0) {
      catch("StringEndsWith()   empty postfix \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(object, postfix) == StringLen(object)-lenPostfix);
}


/**
 * Ob ein String mit dem angegebenen Teilstring endet. Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object  - zu pr�fender String
 * @param  string postfix - Substring
 *
 * @return bool
 */
bool StringIEndsWith(string object, string postfix) {
   int lenPostfix = StringLen(postfix);
   if (lenPostfix == 0) {
      catch("StringIEndsWith()   empty postfix \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(StringToUpper(object), StringToUpper(postfix)) == StringLen(object)-lenPostfix);
}


/**
 * Gibt einen linken Teilstring eines Strings zur�ck.
 *
 * Ist N positiv, gibt StringLeft() die N am meisten links stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringLeft("ABCDEFG",  2)  =>  "AB"
 *
 * Ist N negativ, gibt StringLeft() alle au�er den N am meisten rechts stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringLeft("ABCDEFG", -2)  =>  "ABCDE"
 *
 * @param  string value
 * @param  int    n
 *
 * @return string
 */
string StringLeft(string value, int n) {
   if (n > 0) return(StringSubstr   (value, 0, n                 ));
   if (n < 0) return(StringSubstrFix(value, 0, StringLen(value)+n));
   return("");
}


/**
 * Gibt einen rechten Teilstring eines Strings zur�ck.
 *
 * Ist N positiv, gibt StringRight() die N am meisten rechts stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringRight("ABCDEFG",  2)  =>  "FG"
 *
 * Ist N negativ, gibt StringRight() alle au�er den N am meisten links stehenden Zeichen des Strings zur�ck.
 *    z.B.  StringRight("ABCDEFG", -2)  =>  "CDEFG"
 *
 * @param  string value
 * @param  int    n
 *
 * @return string
 */
string StringRight(string value, int n) {
   if (n > 0) return(StringSubstr(value, StringLen(value)-n));
   if (n < 0) return(StringSubstr(value, -n                ));
   return("");
}


/**
 * Bugfix f�r StringSubstr(string, start, length=0), die MQL-Funktion gibt f�r length=0 Unfug zur�ck.
 * Erm�glicht zus�tzlich die Angabe negativer Werte f�r start und length.
 *
 * @param  string object
 * @param  int    start  - wenn negativ, Startindex vom Ende des Strings
 * @param  int    length - wenn negativ, Anzahl der zur�ckzugebenden Zeichen links vom Startindex
 *
 * @return string
 */
string StringSubstrFix(string object, int start, int length=EMPTY_VALUE) {
   if (length == 0)
      return("");

   if (start < 0)
      start = MathMax(0, start + StringLen(object));

   if (length < 0) {
      start += 1 + length;
      length = MathAbs(length);
   }
   return(StringSubstr(object, start, length));
}


/**
 * Ersetzt in einem String alle Vorkommen eines Substrings durch einen anderen String (kein rekursives Ersetzen).
 *
 * @param  string object  - Ausgangsstring
 * @param  string search  - Suchstring
 * @param  string replace - Ersatzstring
 *
 * @return string
 */
string StringReplace(string object, string search, string replace) {
   if (StringLen(object) == 0) return(object);
   if (StringLen(search) == 0) return(object);

   int startPos = 0;
   int foundPos = StringFind(object, search, startPos);
   if (foundPos == -1) return(object);

   string result = "";

   while (foundPos > -1) {
      result   = StringConcatenate(result, StringSubstrFix(object, startPos, foundPos-startPos), replace);
      startPos = foundPos + StringLen(search);
      foundPos = StringFind(object, search, startPos);
   }
   result = StringConcatenate(result, StringSubstr(object, startPos));

   int error = GetLastError();
   if (IsError(error))
      return(_empty(catch("StringReplace()", error)));
   return(result);
}


/**
 * Erweitert einen String mit einem anderen String linksseitig auf eine gew�nschte Mindestl�nge.
 *
 * @param  string input      - Ausgangsstring
 * @param  int    pad_length - gew�nschte Mindestl�nge
 * @param  string pad_string - zum Erweitern zu verwendender String (default: Leerzeichen)
 *
 * @return string
 */
string StringLeftPad(string input, int pad_length, string pad_string=" ") {
   int length = StringLen(input);

   while (length < pad_length) {
      input  = StringConcatenate(pad_string, input);
      length = StringLen(input);
   }
   if (length > pad_length)
      input = StringRight(input, pad_length);

   return(input);
}


/**
 * Erweitert einen String mit einem anderen String rechtsseitig auf eine gew�nschte Mindestl�nge.
 *
 * @param  string input      - Ausgangsstring
 * @param  int    pad_length - gew�nschte Mindestl�nge
 * @param  string pad_string - zum Erweitern zu verwendender String (default: Leerzeichen)
 *
 * @return string
 */
string StringRightPad(string input, int pad_length, string pad_string=" ") {
   int length = StringLen(input);

   while (length < pad_length) {
      input  = StringConcatenate(input, pad_string);
      length = StringLen(input);
   }
   if (length > pad_length)
      input = StringLeft(input, pad_length);

   return(input);
}


/**
 * Gibt die Startzeit der vorherigen Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetServerPrevSessionStartTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerPrevSessionStartTime(1)  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime fxtTime = ServerToFXT(serverTime);
   if (fxtTime == -1)
      return(-1);

   datetime startTime = GetFXTPrevSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(FXTToServerTime(startTime));
}


/**
 * Gibt die Endzeit der vorherigen Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetServerPrevSessionEndTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerPrevSessionEndTime(1)  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetServerPrevSessionStartTime(serverTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Startzeit oder -1, falls ein Fehler auftrat
 */
datetime GetServerSessionStartTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG, ERR_MARKET_CLOSED*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerSessionStartTime(1)  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   int offset = GetServerToFXTOffset(datetime serverTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime fxtTime = serverTime - offset;
   if (fxtTime < 0)
      return(_int(-1, catch("GetServerSessionStartTime(2)  illegal datetime result: "+ fxtTime +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   int dayOfWeek = TimeDayOfWeek(fxtTime);

   if (dayOfWeek==SATURDAY || dayOfWeek==SUNDAY)
      return(_int(-1, SetLastError(ERR_MARKET_CLOSED)));

   fxtTime   -= TimeHour(fxtTime)*HOURS + TimeMinute(fxtTime)*MINUTES + TimeSeconds(fxtTime)*SECONDS;
   serverTime = fxtTime + offset;

   if (serverTime < 0)
      return(_int(-1, catch("GetServerSessionStartTime(3)  illegal datetime result: "+ serverTime +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_INVALID_FUNCTION_PARAMVALUE)));
   return(serverTime);
}


/**
 * Gibt die Endzeit der Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetServerSessionEndTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG, ERR_MARKET_CLOSED*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerSessionEndTime()  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetServerSessionStartTime(serverTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der n�chsten Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetServerNextSessionStartTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerNextSessionStartTime()  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime fxtTime = ServerToFXT(serverTime);
   if (fxtTime == -1)
      return(-1);

   datetime startTime = GetFXTNextSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(FXTToServerTime(startTime));
}


/**
 * Gibt die Endzeit der n�chsten Handelssession f�r den angegebenen Tradeserver-Zeitpunkt zur�ck.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetServerNextSessionEndTime(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("GetServerNextSessionEndTime()  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetServerNextSessionStartTime(datetime serverTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der vorherigen Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTPrevSessionStartTime(datetime gmtTime) {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTPrevSessionStartTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime fxtTime = GMTToFXT(gmtTime);
   if (fxtTime == -1)
      return(-1);

   datetime startTime = GetFXTPrevSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(FXTToGMT(startTime));
}


/**
 * Gibt die Endzeit der vorherigen Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTPrevSessionEndTime(datetime gmtTime) {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTPrevSessionEndTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetGMTPrevSessionStartTime(gmtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTSessionStartTime(datetime gmtTime) /*throws ERR_MARKET_CLOSED*/ {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTSessionStartTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime fxtTime = GMTToFXT(gmtTime);
   if (fxtTime == -1)
      return(-1);

   datetime startTime = GetFXTSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(FXTToGMT(startTime));
}


/**
 * Gibt die Endzeit der Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTSessionEndTime(datetime gmtTime) /*throws ERR_MARKET_CLOSED*/ {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTSessionEndTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetGMTSessionStartTime(datetime gmtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der n�chsten Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTNextSessionStartTime(datetime gmtTime) {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTNextSessionStartTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime fxtTime = GMTToFXT(gmtTime);
   if (fxtTime == -1)
      return(-1);

   datetime startTime = GetFXTNextSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(FXTToGMT(startTime));
}


/**
 * Gibt die Endzeit der n�chsten Handelssession f�r den angegebenen GMT-Zeitpunkt zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetGMTNextSessionEndTime(datetime gmtTime) {
   if (gmtTime < 0)
      return(_int(-1, catch("GetGMTNextSessionEndTime()  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetGMTNextSessionStartTime(datetime gmtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der vorherigen Handelssession f�r den FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTPrevSessionStartTime(datetime fxtTime) {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTPrevSessionStartTime(1)  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = fxtTime - TimeHour(fxtTime)*HOURS - TimeMinute(fxtTime)*MINUTES - TimeSeconds(fxtTime) - 1*DAY;
   if (startTime < 0)
      return(_int(-1, catch("GetFXTPrevSessionStartTime(2)  illegal datetime result: "+ startTime +" (not a time)", ERR_RUNTIME_ERROR)));

   // Wochenenden ber�cksichtigen
   int dow = TimeDayOfWeek(startTime);
   if      (dow == SATURDAY) startTime -= 1*DAY;
   else if (dow == SUNDAY  ) startTime -= 2*DAYS;

   if (startTime < 0)
      return(_int(-1, catch("GetFXTPrevSessionStartTime(3)  illegal datetime result: "+ startTime +" (not a time)", ERR_RUNTIME_ERROR)));

   return(startTime);
}


/**
 * Gibt die Endzeit der vorherigen Handelssession f�r den angegebenen FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTPrevSessionEndTime(datetime fxtTime) {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTPrevSessionEndTime()  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetFXTPrevSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der Handelssession f�r den angegebenen FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTSessionStartTime(datetime fxtTime) /*throws ERR_MARKET_CLOSED*/ {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTSessionStartTime(1)  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = fxtTime - TimeHour(fxtTime)*HOURS - TimeMinute(fxtTime)*MINUTES - TimeSeconds(fxtTime);
   if (startTime < 0)
      return(_int(-1, catch("GetFXTSessionStartTime(2)  illegal datetime result: "+ startTime +" (not a time)", ERR_RUNTIME_ERROR)));

   // Wochenenden ber�cksichtigen
   int dow = TimeDayOfWeek(startTime);
   if (dow == SATURDAY || dow == SUNDAY)
      return(_int(-1, SetLastError(ERR_MARKET_CLOSED)));

   return(startTime);
}


/**
 * Gibt die Endzeit der Handelssession f�r den angegebenen FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTSessionEndTime(datetime fxtTime) /*throws ERR_MARKET_CLOSED*/ {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTSessionEndTime()  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetFXTSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Gibt die Startzeit der n�chsten Handelssession f�r den angegebenen FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTNextSessionStartTime(datetime fxtTime) {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTNextSessionStartTime()  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = fxtTime - TimeHour(fxtTime)*HOURS - TimeMinute(fxtTime)*MINUTES - TimeSeconds(fxtTime) + 1*DAY;

   // Wochenenden ber�cksichtigen
   int dow = TimeDayOfWeek(startTime);
   if      (dow == SATURDAY) startTime += 2*DAYS;
   else if (dow == SUNDAY  ) startTime += 1*DAY;

   return(startTime);
}


/**
 * Gibt die Endzeit der n�chsten Handelssession f�r den angegebenen FXT-Zeitpunkt (Forex Standard Time) zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GetFXTNextSessionEndTime(datetime fxtTime) {
   if (fxtTime < 0)
      return(_int(-1, catch("GetFXTNextSessionEndTime()  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   datetime startTime = GetFXTNextSessionStartTime(fxtTime);
   if (startTime == -1)
      return(-1);

   return(startTime + 1*DAY);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Then": (double1 < double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool LT(double double1, double double2) {
   if (EQ(double1, double2))
      return(false);
   return(double1 < double2);
}


/**
 * Korrekter Vergleich zweier Doubles auf "Lower-Or-Equal": (double1 <= double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool LE(double double1, double double2) {
   if (double1 < double2)
      return(true);
   return(EQ(double1, double2));

}


/**
 * Korrekter Vergleich zweier Doubles auf Gleichheit "Equal": (double1 == double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool EQ(double double1, double double2) {
   double diff = double1 - double2;
   if (diff < 0)                             // Wir pr�fen die Differenz anhand der 14. Nachkommastelle und nicht wie
      diff = -diff;                          // die Original-MetaQuotes-Funktion anhand der 8. (benutzt NormalizeDouble()).
   return(diff <= 0.00000000000001);         // siehe auch: NormalizeDouble() in MQL.doc
}


/**
 * Korrekter Vergleich zweier Doubles auf Ungleichheit "Not-Equal": (double1 != double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool NE(double double1, double double2) {
   return(!EQ(double1, double2));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Or-Equal": (double1 >= double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool GE(double double1, double double2) {
   if (double1 > double2)
      return(true);
   return(EQ(double1, double2));
}


/**
 * Korrekter Vergleich zweier Doubles auf "Greater-Then": (double1 > double2)
 *
 * @param  double1 - erster Wert
 * @param  double2 - zweiter Wert
 *
 * @return bool
 */
bool GT(double double1, double double2) {
   if (EQ(double1, double2))
      return(false);
   return(double1 > double2);
}


/**
 * Korrekter Vergleich zweier Doubles.
 *
 * MetaQuotes-Alias f�r EQ()
 */
bool CompareDoubles(double double1, double double2) {
   return(EQ(double1, double2));
}


/**
 * Gibt die hexadezimale Repr�sentation einer Ganzzahl zur�ck.
 *
 * @param  int integer - Ganzzahl
 *
 * @return string - hexadezimaler Wert entsprechender L�nge
 *
 * Beispiel: IntegerToHexStr(2058) => "80A"
 */
string IntegerToHexStr(int integer) {
   if (integer == 0)
      return("0");

   string hexStr, char, chars[] = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
   int    value = integer;

   while (value != 0) {
      char   = chars[value & 0x0F];                // value % 16
      hexStr = StringConcatenate(char, hexStr);
      value >>= 4;                                 // value / 16
   }
   return(hexStr);
}


/**
 * Alias
 */
string DecimalToHexStr(int integer) {
   return(IntegerToHexStr(integer));
}


/**
 * Gibt die hexadezimale Repr�sentation eines Bytes zur�ck.
 *
 * @param  int byte - Byte
 *
 * @return string - hexadezimaler Wert mit 2 Stellen
 *
 * Beispiel: ByteToHexStr(10) => "0A"
 */
string ByteToHexStr(int byte) {
   string hexStr, char, chars[] = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
   int    value = byte;

   for (int i=0; i < 2; i++) {
      char   = chars[value & 0x0F];                // value % 16
      hexStr = StringConcatenate(char, hexStr);
      value >>= 4;                                 // value / 16
   }
   return(hexStr);
}


/**
 * Alias
 */
string CharToHexStr(int char) {
   return(ByteToHexStr(char));
}


/**
 * Gibt die hexadezimale Repr�sentation eines Words zur�ck.
 *
 * @param  int word - Word (2 Byte)
 *
 * @return string - hexadezimaler Wert mit 4 Stellen
 *
 * Beispiel: WordToHexStr(2595) => "0A23"
 */
string WordToHexStr(int word) {
   string hexStr, char, chars[] = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
   int    value = word;

   for (int i=0; i < 4; i++) {
      char   = chars[value & 0x0F];                // value % 16
      hexStr = StringConcatenate(char, hexStr);
      value >>= 4;                                 // value / 16
   }
   return(hexStr);
}


/**
 * Gibt die hexadezimale Repr�sentation eines Dwords zur�ck.
 *
 * @param  int dword - Dword (4 Byte, entspricht einem MQL-Integer)
 *
 * @return string - hexadezimaler Wert mit 8 Stellen
 *
 * Beispiel: DwordToHexStr(13465610) => "00CD780A"
 */
string DwordToHexStr(int dword) {
   string hexStr, char, chars[] = {"0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"};
   int    value = dword;

   for (int i=0; i < 8; i++) {
      char   = chars[value & 0x0F];                // value % 16
      hexStr = StringConcatenate(char, hexStr);
      value >>= 4;                                 // value / 16
   }
   return(hexStr);
}


/**
 * Alias
 */
string IntToHexStr(int integer) {
   return(DwordToHexStr(integer));
}


/**
 * Gibt die n�chstkleinere Periode der angegebenen Periode zur�ck.
 *
 * @param  int period - Timeframe-Periode (default: 0 - die aktuelle Periode)
 *
 * @return int - n�chstkleinere Periode oder der urspr�ngliche Wert, wenn keine kleinere Periode existiert
 */
int DecreasePeriod(int period = 0) {
   if (period == 0)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return(PERIOD_M1 );
      case PERIOD_M5 : return(PERIOD_M1 );
      case PERIOD_M15: return(PERIOD_M5 );
      case PERIOD_M30: return(PERIOD_M15);
      case PERIOD_H1 : return(PERIOD_M30);
      case PERIOD_H4 : return(PERIOD_H1 );
      case PERIOD_D1 : return(PERIOD_H4 );
      case PERIOD_W1 : return(PERIOD_D1 );
      case PERIOD_MN1: return(PERIOD_W1 );
   }
   return(_ZERO(catch("DecreasePeriod()  invalid parameter period: "+ period, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Konvertiert einen Double in einen String und entfernt abschlie�ende Nullstellen.
 *
 * @param  double value - Double
 *
 * @return string
 */
string DoubleToStrTrim(double value) {
   string result = value;

   int digits = MathMax(1, CountDecimals(value));  // mindestens eine Dezimalstelle wird erhalten

   if (digits < 8)
      result = StringLeft(result, digits-8);

   return(result);
}


/**
 * Konvertiert die angegebene FXT-Zeit (Forex Standard Time) nach GMT.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime FXTToGMT(datetime fxtTime) {
   if (fxtTime < 0)
      return(_int(-1, catch("FXTToGMT(1)  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   int offset = GetFXTToGMTOffset(fxtTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime result = fxtTime - offset;
   if (result < 0)
      return(_int(-1, catch("FXTToGMT(2)   illegal datetime result: "+ result +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   return(result);
}


/**
 * Konvertiert die angegebene FXT-Zeit (Forex Standard Time) nach Tradeserver-Zeit.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime FXTToServerTime(datetime fxtTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (fxtTime < 0)
      return(_int(-1, catch("FXTToServerTime(1)  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   int offset = GetFXTToServerTimeOffset(fxtTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime result = fxtTime - offset;
   if (result < 0)
      return(_int(-1, catch("FXTToServerTime(2)   illegal datetime result: "+ result +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   return(result);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein Event des angegebenen Typs aufgetreten ist.
 *
 * @param  int event     - Event
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener(int event, int results[], int flags=0) {
   switch (event) {
      case EVENT_BAR_OPEN       : return(EventListener.BarOpen       (results, flags));
      case EVENT_ORDER_PLACE    : return(EventListener.OrderPlace    (results, flags));
      case EVENT_ORDER_CHANGE   : return(EventListener.OrderChange   (results, flags));
      case EVENT_ORDER_CANCEL   : return(EventListener.OrderCancel   (results, flags));
      case EVENT_POSITION_OPEN  : return(EventListener.PositionOpen  (results, flags));
      case EVENT_POSITION_CLOSE : return(EventListener.PositionClose (results, flags));
      case EVENT_ACCOUNT_CHANGE : return(EventListener.AccountChange (results, flags));
      case EVENT_ACCOUNT_PAYMENT: return(EventListener.AccountPayment(results, flags));
      case EVENT_HISTORY_CHANGE : return(EventListener.HistoryChange (results, flags));
   }

   catch("EventListener()  invalid parameter event: "+ event, ERR_INVALID_FUNCTION_PARAMVALUE);
   return(false);
}


/**
 * Pr�ft unabh�ngig von der aktuell gew�hlten Chartperiode, ob der aktuelle Tick im angegebenen Zeitrahmen ein BarOpen-Event ausl�st.
 *
 * @param  int results[] - Zielarray f�r die Flags der Timeframes, in denen das Event aufgetreten ist (mehrere sind m�glich)
 * @param  int flags     - ein oder mehrere Timeframe-Flags (default: Flag der aktuellen Chartperiode)
 *
 * @return bool - Ergebnis
 */
bool EventListener.BarOpen(int& results[], int flags=0) {
   ArrayResize(results, 1);
   results[0] = 0;

   int currentPeriodFlag = PeriodFlag(Period());
   if (flags == 0)
      flags = currentPeriodFlag;

   // Die aktuelle Periode wird mit einem einfachen und schnelleren Algorythmus gepr�ft.
   if (flags & currentPeriodFlag != 0) {
      static datetime lastOpenTime = 0;
      if (lastOpenTime != 0) if (lastOpenTime != Time[0])
         results[0] |= currentPeriodFlag;
      lastOpenTime = Time[0];
   }

   // Pr�fungen f�r andere als die aktuelle Chartperiode
   else {
      static datetime lastTick   = 0;
      static int      lastMinute = 0;

      datetime tick = MarketInfo(Symbol(), MODE_TIME);      // nur Sekundenaufl�sung
      int minute;

      // PERIODFLAG_M1
      if (flags & PERIODFLAG_M1 != 0) {
         if (lastTick == 0) {
            lastTick   = tick;
            lastMinute = TimeMinute(tick);
            //debug("EventListener.BarOpen(M1)   initialisiert   lastTick: ", TimeToStr(lastTick, TIME_DATE|TIME_MINUTES|TIME_SECONDS), " (", lastMinute, ")");
         }
         else if (lastTick != tick) {
            minute = TimeMinute(tick);
            if (lastMinute < minute)
               results[0] |= PERIODFLAG_M1;
            //debug("EventListener.BarOpen(M1)   pr�fe   alt: ", TimeToStr(lastTick, TIME_DATE|TIME_MINUTES|TIME_SECONDS), " (", lastMinute, ")   neu: ", TimeToStr(tick, TIME_DATE|TIME_MINUTES|TIME_SECONDS), " (", minute, ")");
            lastTick   = tick;
            lastMinute = minute;
         }
         //else debug("EventListener.BarOpen(M1)   zwei Ticks in derselben Sekunde");
      }
   }

   // TODO: verbleibende Timeframe-Flags verarbeiten
   if (false) {
      if (flags & PERIODFLAG_M5  != 0) results[0] |= PERIODFLAG_M5 ;
      if (flags & PERIODFLAG_M15 != 0) results[0] |= PERIODFLAG_M15;
      if (flags & PERIODFLAG_M30 != 0) results[0] |= PERIODFLAG_M30;
      if (flags & PERIODFLAG_H1  != 0) results[0] |= PERIODFLAG_H1 ;
      if (flags & PERIODFLAG_H4  != 0) results[0] |= PERIODFLAG_H4 ;
      if (flags & PERIODFLAG_D1  != 0) results[0] |= PERIODFLAG_D1 ;
      if (flags & PERIODFLAG_W1  != 0) results[0] |= PERIODFLAG_W1 ;
      if (flags & PERIODFLAG_MN1 != 0) results[0] |= PERIODFLAG_MN1;
   }

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.BarOpen()", error)==NO_ERROR);

   return(results[0] != 0);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein OrderChange-Event aufgetreten ist.
 *
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener.OrderChange(int results[], int flags=0) {
   bool eventStatus = false;

   if (ArraySize(results) > 0)
      ArrayResize(results, 0);

   // TODO: implementieren

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.OrderChange()", error)==NO_ERROR);

   return(eventStatus);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein OrderPlace-Event aufgetreten ist.
 *
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener.OrderPlace(int results[], int flags=0) {
   bool eventStatus = false;

   if (ArraySize(results) > 0)
      ArrayResize(results, 0);

   // TODO: implementieren

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.OrderPlace()", error)==NO_ERROR);

   return(eventStatus);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein OrderCancel-Event aufgetreten ist.
 *
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener.OrderCancel(int results[], int flags=0) {
   bool eventStatus = false;

   if (ArraySize(results) > 0)
      ArrayResize(results, 0);

   // TODO: implementieren

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.OrderCancel()", error)==NO_ERROR);

   return(eventStatus);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein PositionOpen-Event aufgetreten ist. Werden zus�tzliche Orderkriterien angegeben, wird das Event nur
 * dann signalisiert, wenn alle angegebenen Kriterien erf�llt sind.
 *
 * @param  int tickets[] - Zielarray f�r Ticketnummern neu ge�ffneter Positionen
 * @param  int flags     - ein oder mehrere zus�tzliche Orderkriterien: OFLAG_CURRENTSYMBOL, OFLAG_BUY, OFLAG_SELL, OFLAG_MARKETORDER, OFLAG_PENDINGORDER
 *                         (default: 0)
 * @return bool - Ergebnis
 */
bool EventListener.PositionOpen(int& tickets[], int flags=0) {
   // ohne Verbindung zum Tradeserver sofortige R�ckkehr
   int account = AccountNumber();
   if (account == 0)
      return(false);

   // Ergebnisarray sicherheitshalber zur�cksetzen
   if (ArraySize(tickets) > 0)
      ArrayResize(tickets, 0);

   static int      accountNumber[1];
   static datetime accountInitTime[1];                               // GMT-Zeit
   static int      knownPendings[][2];                               // die bekannten pending Orders und ihr Typ
   static int      knownPositions[];                                 // die bekannten Positionen

   if (accountNumber[0] == 0) {                                      // 1. Aufruf
      accountNumber[0]   = account;
      accountInitTime[0] = TimeGMT();
      //debug("EventListener.PositionOpen()   Account "+ account +" nach 1. Lib-Aufruf initialisiert, GMT-Zeit: "+ TimeToStr(accountInitTime[0], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }
   else if (accountNumber[0] != account) {                           // Aufruf nach Accountwechsel zur Laufzeit: bekannte Positionen l�schen
      accountNumber[0]   = account;
      accountInitTime[0] = TimeGMT();
      ArrayResize(knownPendings, 0);
      ArrayResize(knownPositions, 0);
      //debug("EventListener.PositionOpen()   Account "+ account +" nach Accountwechsel initialisiert, GMT-Zeit: "+ TimeToStr(accountInitTime[0], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   OrderPush("EventListener.PositionOpen(1)");
   int orders = OrdersTotal();

   // pending Orders und offene Positionen �berpr�fen
   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))               // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;

      int n, pendings, positions, type=OrderType(), ticket=OrderTicket();

      // pending Orders �berpr�fen und ggf. aktualisieren
      if (type==OP_BUYLIMIT || type==OP_SELLLIMIT || type==OP_BUYSTOP || type==OP_SELLSTOP) {
         pendings = ArrayRange(knownPendings, 0);
         for (n=0; n < pendings; n++)
            if (knownPendings[n][0] == ticket)                       // bekannte pending Order
               break;
         if (n < pendings)
            continue;

         ArrayResize(knownPendings, pendings+1);                     // neue (unbekannte) pending Order
         knownPendings[pendings][0] = ticket;
         knownPendings[pendings][1] = type;
         //debug("EventListener.PositionOpen()   pending order #", ticket, " added: ", OperationTypeDescription(type));
      }

      // offene Positionen �berpr�fen und ggf. aktualisieren
      else if (type==OP_BUY || type==OP_SELL) {
         positions = ArraySize(knownPositions);
         for (n=0; n < positions; n++)
            if (knownPositions[n] == ticket)                         // bekannte Position
               break;
         if (n < positions)
            continue;

         // Die offenen Positionen stehen u.U. (z.B. nach Accountwechsel) erst nach einigen Ticks zur Verf�gung. Daher m�ssen
         // neue Positionen zus�tzlich anhand ihres OrderOpen-Timestamps auf ihren jeweiligen Status �berpr�ft werden.

         // neue (unbekannte) Position: pr�fen, ob sie nach Accountinitialisierung ge�ffnet wurde (= wirklich neu ist)
         if (accountInitTime[0] <= ServerToGMT(OrderOpenTime())) {
            // ja, in flags angegebene Orderkriterien pr�fen
            int event = 1;
            pendings = ArrayRange(knownPendings, 0);

            if (flags & OFLAG_CURRENTSYMBOL != 0)   event &= (OrderSymbol()==Symbol())+0;    // MQL kann Booleans f�r Bin�rops. nicht casten
            if (flags & OFLAG_BUY           != 0)   event &= (type==OP_BUY )+0;
            if (flags & OFLAG_SELL          != 0)   event &= (type==OP_SELL)+0;
            if (flags & OFLAG_MARKETORDER   != 0) {
               for (int z=0; z < pendings; z++)
                  if (knownPendings[z][0] == ticket)                                         // Order war pending
                     break;                         event &= (z==pendings)+0;
            }
            if (flags & OFLAG_PENDINGORDER  != 0) {
               for (z=0; z < pendings; z++)
                  if (knownPendings[z][0] == ticket)                                         // Order war pending
                     break;                         event &= (z<pendings)+0;
            }

            // wenn alle Kriterien erf�llt sind, Ticket in Resultarray speichern
            if (event == 1) {
               ArrayResize(tickets, ArraySize(tickets)+1);
               tickets[ArraySize(tickets)-1] = ticket;
            }
         }

         ArrayResize(knownPositions, positions+1);
         knownPositions[positions] = ticket;
         //debug("EventListener.PositionOpen()   position #", ticket, " added: ", OperationTypeDescription(type));
      }
   }

   bool eventStatus = (ArraySize(tickets) > 0);
   //debug("EventListener.PositionOpen()   eventStatus: "+ eventStatus);

   int error = GetLastError();
   if (IsError(error))
      return(_false(catch("EventListener.PositionOpen(2)", error, O_POP)));

   return(eventStatus && OrderPop("EventListener.PositionOpen(3)"));
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein PositionClose-Event aufgetreten ist. Werden zus�tzliche Orderkriterien angegeben, wird das Event nur
 * dann signalisiert, wenn alle angegebenen Kriterien erf�llt sind.
 *
 * @param  int tickets[] - Zielarray f�r Ticket-Nummern geschlossener Positionen
 * @param  int flags     - ein oder mehrere zus�tzliche Orderkriterien: OFLAG_CURRENTSYMBOL, OFLAG_BUY, OFLAG_SELL, OFLAG_MARKETORDER, OFLAG_PENDINGORDER
 *                         (default: 0)
 * @return bool - Ergebnis
 */
bool EventListener.PositionClose(int& tickets[], int flags=0) {
   // ohne Verbindung zum Tradeserver sofortige R�ckkehr
   int account = AccountNumber();
   if (account == 0)
      return(false);

   OrderPush("EventListener.PositionClose(1)");

   // Ergebnisarray sicherheitshalber zur�cksetzen
   if (ArraySize(tickets) > 0)
      ArrayResize(tickets, 0);

   static int accountNumber[1];
   static int knownPositions[];                                         // bekannte Positionen
          int noOfKnownPositions = ArraySize(knownPositions);

   if (accountNumber[0] == 0) {
      accountNumber[0] = account;
      //debug("EventListener.PositionClose()   Account "+ account +" nach 1. Lib-Aufruf initialisiert");
   }
   else if (accountNumber[0] != account) {
      accountNumber[0] = account;
      ArrayResize(knownPositions, 0);
      //debug("EventListener.PositionClose()   Account "+ account +" nach Accountwechsel initialisiert");
   }
   else {
      // alle beim letzten Aufruf offenen Positionen pr�fen             // TODO: bei offenen Orders und dem ersten Login in einen anderen Account crasht alles
      for (int i=0; i < noOfKnownPositions; i++) {
         if (!OrderSelectByTicket(knownPositions[i], "EventListener.PositionClose(2)", NULL, O_POP))
            return(false);

         if (OrderCloseTime() > 0) {                                    // Position geschlossen, in flags angegebene Orderkriterien pr�fen
            int    event=1, type=OrderType();
            bool   pending;
            string comment = StringToLower(StringTrim(OrderComment()));

            if      (StringStartsWith(comment, "so:" )) pending = true; // Margin Stopout, wie pending behandeln
            else if (StringEndsWith  (comment, "[tp]")) pending = true;
            else if (StringEndsWith  (comment, "[sl]")) pending = true;
            else if (OrderTakeProfit() > 0) {
               if      (type == OP_BUY )                pending = (OrderClosePrice() >= OrderTakeProfit());
               else if (type == OP_SELL)                pending = (OrderClosePrice() <= OrderTakeProfit());
            }

            if (flags & OFLAG_CURRENTSYMBOL != 0) event &= (OrderSymbol()==Symbol()) +0;  // MQL kann Booleans f�r Bin�roperationen nicht casten
            if (flags & OFLAG_BUY           != 0) event &= (type==OP_BUY )           +0;
            if (flags & OFLAG_SELL          != 0) event &= (type==OP_SELL)           +0;
            if (flags & OFLAG_MARKETORDER   != 0) event &= (!pending)                +0;
            if (flags & OFLAG_PENDINGORDER  != 0) event &= ( pending)                +0;

            // wenn alle Kriterien erf�llt sind, Ticket in Resultarray speichern
            if (event == 1)
               ArrayPushInt(tickets, knownPositions[i]);
         }
      }
   }


   // offene Positionen jedes mal neu einlesen (l�scht auch vorher gespeicherte und jetzt ggf. geschlossene Positionen)
   if (noOfKnownPositions > 0) {
      ArrayResize(knownPositions, 0);
      noOfKnownPositions = 0;
   }
   int orders = OrdersTotal();
   for (i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))         // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine aktive Order geschlossen oder gestrichen
         break;
      if (OrderType()==OP_BUY || OrderType()==OP_SELL) {
         noOfKnownPositions++;
         ArrayResize(knownPositions, noOfKnownPositions);
         knownPositions[noOfKnownPositions-1] = OrderTicket();
         //debug("EventListener.PositionClose()   open position #", ticket, " added: ", OperationTypeDescription(OrderType()));
      }
   }

   bool eventStatus = (ArraySize(tickets) > 0);
   //debug("EventListener.PositionClose()   eventStatus: "+ eventStatus);

   int error = GetLastError();
   if (IsError(error))
      return(_false(catch("EventListener.PositionClose(3)", error, O_POP)));

   return(eventStatus && OrderPop("EventListener.PositionClose(4)"));
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein AccountPayment-Event aufgetreten ist.
 *
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener.AccountPayment(int results[], int flags=0) {
   bool eventStatus = false;

   if (ArraySize(results) > 0)
      ArrayResize(results, 0);

   // TODO: implementieren

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.AccountPayment()", error)==NO_ERROR);

   return(eventStatus);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein HistoryChange-Event aufgetreten ist.
 *
 * @param  int results[] - im Erfolgsfall eventspezifische Detailinformationen
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 */
bool EventListener.HistoryChange(int results[], int flags=0) {
   bool eventStatus = false;

   if (ArraySize(results) > 0)
      ArrayResize(results, 0);

   // TODO: implementieren

   int error = GetLastError();
   if (error != NO_ERROR)
      return(catch("EventListener.HistoryChange()", error)==NO_ERROR);

   return(eventStatus);
}


/**
 * Pr�ft, ob seit dem letzten Aufruf ein AccountChange-Event aufgetreten ist.
 *
 * @param  int results[] - eventspezifische Detailinfos {last_account, current_account, current_account_login}
 * @param  int flags     - zus�tzliche eventspezifische Flags (default: 0)
 *
 * @return bool - Ergebnis
 *
 * NOTE:
 * -----
 * W�hrend des Terminal-Starts und bei Accountwechseln mit schnellen Prozesoren kann AccountNumber() kurzfristig 0 zur�ckgeben.
 * Diese start()-Aufrufe des noch nicht vollst�ndig initialisierten Acconts werden nicht als Accountwechsel im Sinne dieses Listeners interpretiert.
 */
bool EventListener.AccountChange(int results[], int flags=0) {
   static int accountData[3];                         // {last_account, current_account, current_account_login}

   bool eventStatus = false;
   int  account = AccountNumber();

   if (account != 0) {                                // AccountNumber() == 0 ignorieren
      if (accountData[1] == 0) {                      // 1. Lib-Aufruf
         accountData[0] = 0;
         accountData[1] = account;
         accountData[2] = GMTToServerTime(TimeGMT());
         //debug("EventListener.AccountChange()   Account "+ account +" nach 1. Lib-Aufruf initialisiert, ServerTime="+ TimeToStr(accountData[2], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
      }
      else if (accountData[1] != account) {           // Aufruf nach Accountwechsel zur Laufzeit
         accountData[0] = accountData[1];
         accountData[1] = account;
         accountData[2] = GMTToServerTime(TimeGMT());
         //debug("EventListener.AccountChange()   Account "+ account +" nach Accountwechsel initialisiert, ServerTime="+ TimeToStr(accountData[2], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
         eventStatus = true;
      }
   }
   //debug("EventListener.AccountChange()   eventStatus: "+ eventStatus);

   if (ArraySize(results) != 3)
      ArrayResize(results, 3);
   ArrayCopy(results, accountData);

   int error = GetLastError();
   if (error != NO_ERROR)
      return(_false(catch("EventListener.AccountChange()", error)));

   return(eventStatus);
}


/**
 * Zerlegt einen String in Teilstrings.
 *
 * @param  string object    - zu zerlegender String
 * @param  string separator - Trennstring
 * @param  string results[] - Zielarray f�r die Teilstrings
 * @param  int    limit     - maximale Anzahl von Teilstrings (default: kein Limit)
 *
 * @return int - Anzahl der Teilstrings oder -1, wennn ein Fehler auftrat
 */
int Explode(string object, string separator, string& results[], int limit=NULL) {
   // Der Parameter object *KANN* ein Element des Ergebnisarrays results[] sein, daher erstellen wir
   // vor Modifikation von results[] eine Kopie von object und verwenden diese.
   string _object = StringConcatenate(object, "");

   int lenObject    = StringLen(_object),
       lenSeparator = StringLen(separator);

   if (lenObject == 0) {                     // Leerstring
      ArrayResize(results, 1);
      results[0] = _object;
   }
   else if (StringLen(separator) == 0) {     // String in einzelne Zeichen zerlegen
      if (limit==NULL || limit > lenObject)
         limit = lenObject;
      ArrayResize(results, limit);

      for (int i=0; i < limit; i++) {
         results[i] = StringSubstr(_object, i, 1);
      }
   }
   else {                                    // String in Substrings zerlegen
      int size, pos;
      i = 0;

      while (i < lenObject) {
         ArrayResize(results, size+1);

         pos = StringFind(_object, separator, i);
         if (limit == size+1)
            pos = -1;
         if (pos == -1) {
            results[size] = StringSubstr(_object, i);
            break;
         }
         else if (pos == i) {
            results[size] = "";
         }
         else {
            results[size] = StringSubstrFix(_object, i, pos-i);
         }
         size++;
         i = pos + lenSeparator;
      }

      if (i == lenObject) {                  // bei abschlie�endem Separator Substrings mit Leerstring beenden
         ArrayResize(results, size+1);
         results[size] = "";                 // TODO: !!! Wechselwirkung zwischen Limit und Separator am Ende �berpr�fen
      }
   }

   int error = GetLastError();
   if (IsError(error))
      return(_int(-1, catch("Explode()", error)));

   return(ArraySize(results));
}


/**
 * Liest die History eines Accounts aus dem Dateisystem in das angegebene Array ein (Daten werden als Strings gespeichert).
 *
 * @param  int    account                    - Account-Nummer
 * @param  string results[][HISTORY_COLUMNS] - Zeiger auf Ergebnisarray
 *
 * @return int - Fehlerstatus
 */
int GetAccountHistory(int account, string results[][HISTORY_COLUMNS]) {
   if (ArrayRange(results, 1) != HISTORY_COLUMNS)
      return(catch("GetAccountHistory(1)   invalid parameter results["+ ArrayRange(results, 0) +"]["+ ArrayRange(results, 1) +"]", ERR_INCOMPATIBLE_ARRAYS));

   int    cache.account[1];
   string cache[][HISTORY_COLUMNS];

   ArrayResize(results, 0);

   // Daten nach M�glichkeit aus dem Cache liefern
   if (cache.account[0] == account) {
      ArrayCopy(results, cache);
      log("GetAccountHistory()   delivering "+ ArrayRange(cache, 0) +" history entries for account "+ account +" from cache");
      return(catch("GetAccountHistory(2)"));
   }

   // Cache-Miss, History-Datei auslesen
   string header[HISTORY_COLUMNS] = { "Ticket","OpenTime","OpenTimestamp","Description","Type","Size","Symbol","OpenPrice","StopLoss","TakeProfit","CloseTime","CloseTimestamp","ClosePrice","ExpirationTime","ExpirationTimestamp","MagicNumber","Commission","Swap","NetProfit","GrossProfit","Balance","Comment" };

   string filename = ShortAccountCompany() +"/"+ account + "_account_history.csv";
   int hFile = FileOpen(filename, FILE_CSV|FILE_READ, '\t');
   if (hFile < 0) {
      int error = GetLastError();
      if (error == ERR_CANNOT_OPEN_FILE)
         return(error);
      return(catch("GetAccountHistory(3)->FileOpen(\""+ filename +"\")", error));
   }

   string value;
   bool   newLine=true, blankLine=false, lineEnd=true;
   int    lines=0, row=-2, col=-1;
   string result[][HISTORY_COLUMNS]; ArrayResize(result, 0);   // tmp. Zwischenspeicher f�r ausgelesene Daten

   // Daten feldweise einlesen und Zeilen erkennen
   while (!FileIsEnding(hFile)) {
      newLine = false;
      if (lineEnd) {                                           // Wenn beim letzten Durchlauf das Zeilenende erreicht wurde,
         newLine   = true;                                     // Flags auf Zeilenbeginn setzen.
         blankLine = false;
         lineEnd   = false;
         col = -1;                                             // Spaltenindex vor der ersten Spalte (erste Spalte = 0)
      }

      // n�chstes Feld auslesen
      value = FileReadString(hFile);

      // auf Leerzeilen, Zeilen- und Dateiende pr�fen
      if (FileIsLineEnding(hFile) || FileIsEnding(hFile)) {
         lineEnd = true;
         if (newLine) {
            if (StringLen(value) == 0) {
               if (FileIsEnding(hFile))                        // Zeilenbeginn + Leervalue + Dateiende  => nichts, also Abbruch
                  break;
               blankLine = true;                               // Zeilenbeginn + Leervalue + Zeilenende => Leerzeile
            }
         }
         lines++;
      }

      // Leerzeilen �berspringen
      if (blankLine)
         continue;

      value = StringTrim(value);

      // Kommentarzeilen �berspringen
      if (newLine) /*&&*/ if (StringGetChar(value, 0)=='#')
         continue;

      // Zeilen- und Spaltenindex aktualisieren und Bereich �berpr�fen
      col++;
      if (lineEnd) /*&&*/ if (col!=HISTORY_COLUMNS-1) {
         error = catch("GetAccountHistory(4)   data format error in \""+ filename +"\", column count in line "+ lines +" is not "+ HISTORY_COLUMNS, ERR_RUNTIME_ERROR);
         break;
      }
      if (newLine)
         row++;

      // Headerinformationen in der ersten Datenzeile �berpr�fen und Headerzeile �berspringen
      if (row == -1) {
         if (value != header[col]) {
            error = catch("GetAccountHistory(5)   data format error in \""+ filename +"\", unexpected column header \""+ value +"\"", ERR_RUNTIME_ERROR);
            break;
         }
         continue;            // jmp
      }

      // Ergebnisarray vergr��ern und Rohdaten speichern (als String)
      if (newLine)
         ArrayResize(result, row+1);
      result[row][col] = value;
   }

   // Hier hat entweder ein Formatfehler ERR_RUNTIME_ERROR (bereits gemeldet) oder das Dateiende END_OF_FILE ausgel�st.
   if (error == NO_ERROR) {
      error = GetLastError();
      if (error == ERR_END_OF_FILE) {
         error = NO_ERROR;
      }
      else {
         catch("GetAccountHistory(6)", error);
      }
   }

   // vor evt. Fehler-R�ckkehr auf jeden Fall Datei schlie�en
   FileClose(hFile);

   if (error != NO_ERROR)     // ret
      return(error);


   // Daten in Zielarray kopieren und cachen
   if (ArrayRange(result, 0) > 0) {       // "leere" Historydaten nicht cachen (falls Datei noch erstellt wird)
      ArrayCopy(results, result);

      cache.account[0] = account;
      ArrayResize(cache, 0);
      ArrayCopy(cache, result);
      //log("GetAccountHistory()   caching "+ ArrayRange(cache, 0) +" history entries for account "+ account);
   }

   return(catch("GetAccountHistory(7)"));
}


/**
 * Gibt die aktuelle Account-Nummer zur�ck (unabh�ngig von einer Connection zum Tradeserver).
 *
 * @return int - Account-Nummer (positiver Wert) oder 0, falls ein Fehler aufgetreten ist.
 *
 * NOTE:
 * ----
 * W�hrend des Terminalstarts kann der Fehler ERR_TERMINAL_NOT_YET_READY auftreten.
 */
int GetAccountNumber() {
   int account = AccountNumber();

   if (account == 0) {                                // ohne Connection Titelzeile des Hauptfensters auswerten
      string title = GetWindowText(GetTerminalWindow());
      if (StringLen(title) == 0)
         return(_ZERO(SetLastError(ERR_TERMINAL_NOT_YET_READY)));

      int pos = StringFind(title, ":");
      if (pos < 1)
         return(_ZERO(catch("GetAccountNumber(1)   account number separator not found in top window title \""+ title +"\"", ERR_RUNTIME_ERROR)));

      string strAccount = StringLeft(title, pos);
      if (!StringIsDigit(strAccount))
         return(_ZERO(catch("GetAccountNumber(2)   account number in top window title contains non-digit characters: "+ strAccount, ERR_RUNTIME_ERROR)));

      account = StrToInteger(strAccount);
   }

   if (IsError(catch("GetAccountNumber(3)")))
      return(0);
   return(account);
}


/**
 * Schreibt die Balance-History eines Accounts in die angegebenen Ergebnisarrays (aufsteigend nach Zeitpunkt sortiert).
 *
 * @param  int      account  - Account-Nummer
 * @param  datetime times[]  - Zeiger auf Ergebnisarray f�r die Zeitpunkte der Balance�nderung
 * @param  double   values[] - Zeiger auf Ergebnisarray der entsprechenden Balancewerte
 *
 * @return int - Fehlerstatus
 */
int GetBalanceHistory(int account, datetime& times[], double& values[]) {
   int      cache.account[1];
   datetime cache.times[];
   double   cache.values[];

   ArrayResize(times,  0);
   ArrayResize(values, 0);

   // Daten nach M�glichkeit aus dem Cache liefern       TODO: paralleles Cachen mehrerer Wertereihen erm�glichen
   if (cache.account[0] == account) {
      /**
       * TODO: Fehler tritt nach Neustart auf, wenn Balance-Indikator geladen ist und AccountNumber() noch 0 zur�ckgibt
       *
       * stdlib: Error: incorrect start position 0 for ArrayCopy function
       * stdlib: Log:   Balance::stdlib::GetBalanceHistory()   delivering 0 balance values for account 0 from cache
       * stdlib: Alert: ERROR:   AUDUSD,M15::Balance::stdlib::GetBalanceHistory(1)  [4051 - invalid function parameter value]
       */
      ArrayCopy(times , cache.times);
      ArrayCopy(values, cache.values);
      log("GetBalanceHistory()   delivering "+ ArraySize(cache.times) +" balance values for account "+ account +" from cache");
      return(catch("GetBalanceHistory(1)"));
   }

   // Cache-Miss, Balance-Daten aus Account-History auslesen
   string data[][HISTORY_COLUMNS]; ArrayResize(data, 0);
   int error = GetAccountHistory(account, data);
   if (error == ERR_CANNOT_OPEN_FILE) return(catch("GetBalanceHistory(2)", error));
   if (error != NO_ERROR            ) return(catch("GetBalanceHistory(3)"));

   // Balancedatens�tze einlesen und auswerten (History ist nach CloseTime sortiert)
   datetime time, lastTime;
   double   balance, lastBalance;
   int n, size=ArrayRange(data, 0);

   if (size == 0)
      return(catch("GetBalanceHistory(4)"));

   for (int i=0; i<size; i++) {
      balance = StrToDouble (data[i][AH_BALANCE       ]);
      time    = StrToInteger(data[i][AH_CLOSETIMESTAMP]);

      // der erste Datensatz wird immer geschrieben...
      if (i == 0) {
         ArrayResize(times,  n+1);
         ArrayResize(values, n+1);
         times [n] = time;
         values[n] = balance;
         n++;                                // n: Anzahl der existierenden Ergebnisdaten => ArraySize(lpTimes)
      }
      else if (balance != lastBalance) {
         // ... alle weiteren nur, wenn die Balance sich ge�ndert hat
         if (time == lastTime) {             // Existieren mehrere Balance�nderungen zum selben Zeitpunkt,
            values[n-1] = balance;           // wird der letzte Wert nur mit dem aktuellen �berschrieben.
         }
         else {
            ArrayResize(times,  n+1);
            ArrayResize(values, n+1);
            times [n] = time;
            values[n] = balance;
            n++;
         }
      }
      lastTime    = time;
      lastBalance = balance;
   }

   // Daten cachen
   cache.account[0] = account;
   ArrayResize(cache.times,  0); ArrayCopy(cache.times,  times );
   ArrayResize(cache.values, 0); ArrayCopy(cache.values, values);
   log("GetBalanceHistory()   caching "+ ArraySize(times) +" balance values for account "+ account);

   return(catch("GetBalanceHistory(5)"));
}


/**
 * Gibt den Rechnernamen des laufenden Systems zur�ck.
 *
 * @return string - Name oder Leerstring, falls ein Fehler auftrat
 */
string GetComputerName() {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);
   int    lpBufferSize[1]; lpBufferSize[0] = bufferSize;

   if (!GetComputerNameA(buffer[0], lpBufferSize))
      return(_empty(catch("GetComputerName() ->kernel32::GetComputerNameA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   return(buffer[0]);
}


/**
 * Gibt einen Konfigurationswert als Boolean zur�ck.  Dabei werden die globale als auch die lokale Konfiguration der MetaTrader-Installation durchsucht.
 * Lokale Konfigurationswerte haben eine h�here Priorit�t als globale Werte.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return bool - Konfigurationswert
 */
bool GetConfigBool(string section, string key, bool defaultValue=false) {
   string strDefault = defaultValue;

   int bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   // zuerst globale, dann lokale Config auslesen                             // zu kleiner Buffer ist hier nicht m�glich
   GetPrivateProfileStringA(section, key, strDefault, buffer[0], bufferSize, GetGlobalConfigPath());
   GetPrivateProfileStringA(section, key, buffer[0] , buffer[0], bufferSize, GetLocalConfigPath());

   buffer[0] = StringToLower(buffer[0]);
   bool result = true;

   if (buffer[0]!="1") /*&&*/ if (buffer[0]!="true") /*&&*/ if (buffer[0]!="yes") /*&&*/ if (buffer[0]!="on") {
      result = false;
   }

   if (catch("GetConfigBool()") != NO_ERROR)
      return(false);
   return(result);
}


/**
 * Gibt einen Konfigurationswert als Double zur�ck.  Dabei werden die globale als auch die lokale Konfiguration der MetaTrader-Installation durchsucht.
 * Lokale Konfigurationswerte haben eine h�here Priorit�t als globale Werte.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return double - Konfigurationswert
 */
double GetConfigDouble(string section, string key, double defaultValue=0) {
   int bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   // zuerst globale, dann lokale Config auslesen                             // zu kleiner Buffer ist hier nicht m�glich
   GetPrivateProfileStringA(section, key, DoubleToStr(defaultValue, 8), buffer[0], bufferSize, GetGlobalConfigPath());
   GetPrivateProfileStringA(section, key, buffer[0]                   , buffer[0], bufferSize, GetLocalConfigPath());

   double result = StrToDouble(buffer[0]);

   if (IsError(catch("GetConfigDouble()")))
      return(0);
   return(result);
}


/**
 * Gibt einen Konfigurationswert als Integer zur�ck.  Dabei werden die globale als auch die lokale Konfiguration der MetaTrader-Installation durchsucht.
 * Lokale Konfigurationswerte haben eine h�here Priorit�t als globale Werte.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return int - Konfigurationswert
 */
int GetConfigInt(string section, string key, int defaultValue=0) {
   // zuerst globale, dann lokale Config auslesen
   int result = GetPrivateProfileIntA(section, key, defaultValue, GetGlobalConfigPath());    // gibt auch negative Werte richtig zur�ck
       result = GetPrivateProfileIntA(section, key, result      , GetLocalConfigPath());

   if (IsError(catch("GetConfigInt()")))
      return(0);
   return(result);
}


/**
 * Gibt einen Konfigurationswert als String zur�ck.  Dabei werden die globale als auch die lokale Konfiguration der MetaTrader-Installation durchsucht.
 * Lokale Konfigurationswerte haben eine h�here Priorit�t als globale Werte.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return string - Konfigurationswert
 */
string GetConfigString(string section, string key, string defaultValue="") {
   // zuerst globale, dann lokale Config auslesen
   string value = GetPrivateProfileString(GetGlobalConfigPath(), section, key, defaultValue);
          value = GetPrivateProfileString(GetLocalConfigPath() , section, key, value       );
   return(value);
}


/**
 * Ob der angegebene Schl�ssel in der lokalen Konfigurationsdatei existiert oder nicht.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsLocalConfigKey(string section, string key) {
   string keys[];
   GetPrivateProfileKeys(GetLocalConfigPath(), section, keys);

   int size = ArraySize(keys);
   if (size == 0)
      return(false);

   key = StringToLower(key);

   for (int i=0; i < size; i++) {
      if (key == StringToLower(keys[i]))
         return(true);
   }
   return(false);
}


/**
 * Ob der angegebene Schl�ssel in der globalen Konfigurationsdatei existiert oder nicht.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsGlobalConfigKey(string section, string key) {
   string keys[];
   GetPrivateProfileKeys(GetGlobalConfigPath(), section, keys);

   int size = ArraySize(keys);
   if (size == 0)
      return(false);

   key = StringToLower(key);

   for (int i=0; i < size; i++) {
      if (key == StringToLower(keys[i]))
         return(true);
   }
   return(false);
}


/**
 * Ob der angegebene Schl�ssel in der globalen oder lokalen Konfigurationsdatei existiert oder nicht.
 *
 * @param  string section - Name des Konfigurationsabschnittes
 * @param  string key     - Schl�ssel
 *
 * @return bool
 */
bool IsConfigKey(string section, string key) {
   if (IsGlobalConfigKey(section, key))
      return(true);
   return(IsLocalConfigKey(section, key));
}


/**
 * Gibt den Offset der angegebenen FXT-Zeit (Forex Standard Time) zu GMT zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetFXTToGMTOffset(datetime fxtTime) {
   if (fxtTime < 0) {
      catch("GetFXTToGMTOffset()  invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   int offset, year = TimeYear(fxtTime)-1970;

   // FXT                                           GMT+0200,GMT+0300
   if      (fxtTime < FXT_transitions[year][0]) offset = 2 * HOURS;
   else if (fxtTime < FXT_transitions[year][1]) offset = 3 * HOURS;
   else                                         offset = 2 * HOURS;

   return(offset);
}


/**
 * Gibt den Offset der angegebenen FXT-Zeit (Forex Standard Time) zu Tradeserver-Zeit zur�ck.
 *
 * @param  datetime fxtTime - FXT-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetFXTToServerTimeOffset(datetime fxtTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (fxtTime < 0) {
      catch("GetFXTToServerTimeOffset(1)   invalid parameter fxtTime: "+ fxtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   // Offset FXT zu GMT
   int offset1 = GetFXTToGMTOffset(fxtTime);
   if (offset1 == EMPTY_VALUE)
      return(EMPTY_VALUE);

   // Offset GMT zu Tradeserver
   int offset2 = GetGMTToServerTimeOffset(fxtTime - offset1);
   if (offset2 == EMPTY_VALUE)
      return(EMPTY_VALUE);

   return(offset1 + offset2);
}


/**
 * Gibt einen globalen Konfigurationswert als Boolean zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return bool - Konfigurationswert
 */
bool GetGlobalConfigBool(string section, string key, bool defaultValue=false) {
   string strDefault = defaultValue;

   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   GetPrivateProfileStringA(section, key, strDefault, buffer[0], bufferSize, GetGlobalConfigPath());

   buffer[0] = StringToLower(buffer[0]);
   bool result = true;

   if (buffer[0]!="1") /*&&*/ if (buffer[0]!="true") /*&&*/ if (buffer[0]!="yes") /*&&*/ if (buffer[0]!="on") {
      result = false;
   }

   if (catch("GetGlobalConfigBool()") != NO_ERROR)
      return(false);
   return(result);
}


/**
 * Gibt einen globalen Konfigurationswert als Double zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return double - Konfigurationswert
 */
double GetGlobalConfigDouble(string section, string key, double defaultValue=0) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   GetPrivateProfileStringA(section, key, DoubleToStr(defaultValue, 8), buffer[0], bufferSize, GetGlobalConfigPath());

   double result = StrToDouble(buffer[0]);

   if (IsError(catch("GetGlobalConfigDouble()")))
      return(0);
   return(result);
}


/**
 * Gibt einen globalen Konfigurationswert als Integer zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return int - Konfigurationswert
 */
int GetGlobalConfigInt(string section, string key, int defaultValue=0) {
   int result = GetPrivateProfileIntA(section, key, defaultValue, GetGlobalConfigPath());    // gibt auch negative Werte richtig zur�ck

   if (IsError(catch("GetGlobalConfigInt()")))
      return(0);
   return(result);
}


/**
 * Gibt einen globalen Konfigurationswert als String zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return string - Konfigurationswert
 */
string GetGlobalConfigString(string section, string key, string defaultValue="") {
   return(GetPrivateProfileString(GetGlobalConfigPath(), section, key, defaultValue));
}


/**
 * Gibt den Offset der angegebenen GMT-Zeit zur Tradeserver-Zeit zur�ck.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 *
 *
 * NOTE: Das Ergebnis ist der entgegengesetzte Wert des Offsets von Tradeserver-Zeit zu GMT.
 * -----
 *
 */
int GetGMTToServerTimeOffset(datetime gmtTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (gmtTime < 0) {
      catch("GetGMTToServerTimeOffset(1)   invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   string timezone = GetServerTimezone();
   if (StringLen(timezone) == 0)
      return(EMPTY_VALUE);
   int offset, year = TimeYear(gmtTime)-1970;

   if (timezone == "Europe/Minsk") {             // GMT+0200,GMT+0300
      if      (gmtTime < EMST_transitions[year][2]) offset = -2 * HOURS;
      else if (gmtTime < EMST_transitions[year][3]) offset = -3 * HOURS;
      else                                          offset = -2 * HOURS;
   }

   else if (timezone == "Europe/Kiev") {         // GMT+0200,GMT+0300
      if      (gmtTime < EEST_transitions[year][2]) offset = -2 * HOURS;
      else if (gmtTime < EEST_transitions[year][3]) offset = -3 * HOURS;
      else                                          offset = -2 * HOURS;
   }

   else if (timezone == "FXT") {                 // GMT+0200,GMT+0300
      if      (gmtTime < FXT_transitions[year][2])  offset = -2 * HOURS;
      else if (gmtTime < FXT_transitions[year][3])  offset = -3 * HOURS;
      else                                          offset = -2 * HOURS;
   }

   else if (timezone == "Europe/Berlin") {       // GMT+0100,GMT+0200
      if      (gmtTime < CEST_transitions[year][2]) offset = -1 * HOUR;
      else if (gmtTime < CEST_transitions[year][3]) offset = -2 * HOURS;
      else                                          offset = -1 * HOUR;
   }
                                                 // GMT+0000
   else if (timezone == "GMT")                      offset =  0;

   else if (timezone == "Europe/London") {       // GMT+0000,GMT+0100
      if      (gmtTime < BST_transitions[year][2])  offset =  0;
      else if (gmtTime < BST_transitions[year][3])  offset = -1 * HOUR;
      else                                          offset =  0;
   }

   else if (timezone == "America/New_York") {    // GMT-0500,GMT-0400
      if      (gmtTime < EDT_transitions[year][2])  offset = 5 * HOURS;
      else if (gmtTime < EDT_transitions[year][3])  offset = 4 * HOURS;
      else                                          offset = 5 * HOURS;
   }

   else {
      catch("GetGMTToServerTimeOffset(2)  unknown timezone \""+ timezone +"\"", ERR_INVALID_TIMEZONE_CONFIG);
      return(EMPTY_VALUE);
   }

   if (catch("GetGMTToServerTimeOffset(3)") != NO_ERROR)
      return(EMPTY_VALUE);

   return(offset);
}


/**
 * Gibt einen Wert des angegebenen Abschnitts einer .ini-Datei als String zur�ck.
 *
 * @param  string fileName     - Name der .ini-Datei
 * @param  string section      - Abschnittsname
 * @param  string key          - Schl�sselname
 * @param  string defaultValue - R�ckgabewert, falls kein Wert gefunden wurde
 *
 * @return string
 */
string GetPrivateProfileString(string fileName, string section, string key, string defaultValue="") {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   int chars = GetPrivateProfileStringA(section, key, defaultValue, buffer[0], bufferSize, fileName);

   // zu kleinen Buffer abfangen
   while (chars == bufferSize-1) {
      bufferSize <<= 1;
      InitializeStringBuffer(buffer, bufferSize);
      chars = GetPrivateProfileStringA(section, key, defaultValue, buffer[0], bufferSize, fileName);
   }

   if (IsError(catch("GetPrivateProfileString()")))
      return("");
   return(buffer[0]);
}


/**
 * Gibt einen lokalen Konfigurationswert als Boolean zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  bool   defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return bool - Konfigurationswert
 */
bool GetLocalConfigBool(string section, string key, bool defaultValue=false) {
   string strDefault = defaultValue;

   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   GetPrivateProfileStringA(section, key, strDefault, buffer[0], bufferSize, GetLocalConfigPath());

   buffer[0] = StringToLower(buffer[0]);
   bool result = true;

   if (buffer[0]!="1") /*&&*/ if (buffer[0]!="true") /*&&*/ if (buffer[0]!="yes") /*&&*/ if (buffer[0]!="on") {
      result = false;
   }

   if (catch("GetLocalConfigBool()") != NO_ERROR)
      return(false);
   return(result);
}


/**
 * Gibt einen lokalen Konfigurationswert als Double zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  double defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return double - Konfigurationswert
 */
double GetLocalConfigDouble(string section, string key, double defaultValue=0) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   GetPrivateProfileStringA(section, key, DoubleToStr(defaultValue, 8), buffer[0], bufferSize, GetLocalConfigPath());

   double result = StrToDouble(buffer[0]);

   if (IsError(catch("GetLocalConfigDouble()")))
      return(0);
   return(result);
}


/**
 * Gibt einen lokalen Konfigurationswert als Integer zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  int    defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return int - Konfigurationswert
 */
int GetLocalConfigInt(string section, string key, int defaultValue=0) {
   int result = GetPrivateProfileIntA(section, key, defaultValue, GetLocalConfigPath());     // gibt auch negative Werte richtig zur�ck

   if (IsError(catch("GetLocalConfigInt()")))
      return(0);
   return(result);
}


/**
 * Gibt einen lokalen Konfigurationswert als String zur�ck.
 *
 * @param  string section      - Name des Konfigurationsabschnittes
 * @param  string key          - Konfigurationsschl�ssel
 * @param  string defaultValue - Wert, der zur�ckgegeben wird, wenn unter diesem Schl�ssel kein Konfigurationswert gefunden wird
 *
 * @return string - Konfigurationswert
 */
string GetLocalConfigString(string section, string key, string defaultValue="") {
   return(GetPrivateProfileString(GetLocalConfigPath(), section, key, defaultValue));
}


/**
 * Gibt den Wochentag des angegebenen Zeitpunkts zur�ck.
 *
 * @param  datetime time - Zeitpunkt
 * @param  bool     long - TRUE, um die Langform zur�ckzugeben (default)
 *                         FALSE, um die Kurzform zur�ckzugeben
 *
 * @return string - Wochentag
 */
string GetDayOfWeek(datetime time, bool long=true) {
   if (time < 0)
      return(_empty(catch("GetDayOfWeek(1)  invalid parameter time: "+ time +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   static string weekDays[] = {"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"};

   string day = weekDays[TimeDayOfWeek(time)];

   if (!long)
      day = StringSubstr(day, 0, 3);

   return(day);
}


/**
 * Gibt die Beschreibung eines MQL-Fehlercodes zur�ck.
 *
 * @param  int error - MQL-Fehlercode
 *
 * @return string
 */
string ErrorDescription(int error) {
   switch (error) {
      case NO_ERROR                       : return("no error"                                                      ); //    0

      // trade server errors
      case ERR_NO_RESULT                  : return("no result"                                                     ); //    1
      case ERR_COMMON_ERROR               : return("trade denied"                                                  ); //    2
      case ERR_INVALID_TRADE_PARAMETERS   : return("invalid trade parameters"                                      ); //    3
      case ERR_SERVER_BUSY                : return("trade server is busy"                                          ); //    4
      case ERR_OLD_VERSION                : return("old version of client terminal"                                ); //    5
      case ERR_NO_CONNECTION              : return("no connection to trade server"                                 ); //    6
      case ERR_NOT_ENOUGH_RIGHTS          : return("not enough rights"                                             ); //    7
      case ERR_TOO_FREQUENT_REQUESTS      : return("too frequent requests"                                         ); //    8
      case ERR_MALFUNCTIONAL_TRADE        : return("malfunctional trade operation"                                 ); //    9
      case ERR_ACCOUNT_DISABLED           : return("account disabled"                                              ); //   64
      case ERR_INVALID_ACCOUNT            : return("invalid account"                                               ); //   65
      case ERR_TRADE_TIMEOUT              : return("trade timeout"                                                 ); //  128
      case ERR_INVALID_PRICE              : return("invalid price"                                                 ); //  129 Kurs bewegt sich zu schnell (aus dem Fenster)
      case ERR_INVALID_STOPS              : return("invalid stop"                                                  ); //  130
      case ERR_INVALID_TRADE_VOLUME       : return("invalid trade volume"                                          ); //  131
      case ERR_MARKET_CLOSED              : return("market is closed"                                              ); //  132
      case ERR_TRADE_DISABLED             : return("trading is disabled"                                           ); //  133
      case ERR_NOT_ENOUGH_MONEY           : return("not enough money"                                              ); //  134
      case ERR_PRICE_CHANGED              : return("price changed"                                                 ); //  135
      case ERR_OFF_QUOTES                 : return("off quotes"                                                    ); //  136
      case ERR_BROKER_BUSY                : return("broker is busy"                                                ); //  137
      case ERR_REQUOTE                    : return("requote"                                                       ); //  138
      case ERR_ORDER_LOCKED               : return("order is locked"                                               ); //  139
      case ERR_LONG_POSITIONS_ONLY_ALLOWED: return("long positions only allowed"                                   ); //  140
      case ERR_TOO_MANY_REQUESTS          : return("too many requests"                                             ); //  141
      case ERR_TRADE_MODIFY_DENIED        : return("modification denied because too close to market"               ); //  145
      case ERR_TRADE_CONTEXT_BUSY         : return("trade context is busy"                                         ); //  146
      case ERR_TRADE_EXPIRATION_DENIED    : return("expiration settings denied by broker"                          ); //  147
      case ERR_TRADE_TOO_MANY_ORDERS      : return("number of open and pending orders has reached the broker limit"); //  148
      case ERR_TRADE_HEDGE_PROHIBITED     : return("hedging prohibited"                                            ); //  149
      case ERR_TRADE_PROHIBITED_BY_FIFO   : return("prohibited by FIFO rules"                                      ); //  150

      // runtime errors
      case ERR_RUNTIME_ERROR              : return("runtime error"                                                 ); // 4000 common runtime error (no mql error)
      case ERR_WRONG_FUNCTION_POINTER     : return("wrong function pointer"                                        ); // 4001
      case ERR_ARRAY_INDEX_OUT_OF_RANGE   : return("array index out of range"                                      ); // 4002
      case ERR_NO_MEMORY_FOR_CALL_STACK   : return("no memory for function call stack"                             ); // 4003
      case ERR_RECURSIVE_STACK_OVERFLOW   : return("recursive stack overflow"                                      ); // 4004
      case ERR_NOT_ENOUGH_STACK_FOR_PARAM : return("not enough stack for parameter"                                ); // 4005
      case ERR_NO_MEMORY_FOR_PARAM_STRING : return("no memory for parameter string"                                ); // 4006
      case ERR_NO_MEMORY_FOR_TEMP_STRING  : return("no memory for temp string"                                     ); // 4007
      case ERR_NOT_INITIALIZED_STRING     : return("not initialized string"                                        ); // 4008
      case ERR_NOT_INITIALIZED_ARRAYSTRING: return("not initialized string in array"                               ); // 4009
      case ERR_NO_MEMORY_FOR_ARRAYSTRING  : return("no memory for string in array"                                 ); // 4010
      case ERR_TOO_LONG_STRING            : return("string too long"                                               ); // 4011
      case ERR_REMAINDER_FROM_ZERO_DIVIDE : return("remainder from division by zero"                               ); // 4012
      case ERR_ZERO_DIVIDE                : return("division by zero"                                              ); // 4013
      case ERR_UNKNOWN_COMMAND            : return("unknown command"                                               ); // 4014
      case ERR_WRONG_JUMP                 : return("wrong jump"                                                    ); // 4015
      case ERR_NOT_INITIALIZED_ARRAY      : return("array not initialized"                                         ); // 4016
      case ERR_DLL_CALLS_NOT_ALLOWED      : return("DLL calls are not allowed"                                     ); // 4017
      case ERR_CANNOT_LOAD_LIBRARY        : return("cannot load library"                                           ); // 4018
      case ERR_CANNOT_CALL_FUNCTION       : return("cannot call function"                                          ); // 4019
      case ERR_EXTERNAL_CALLS_NOT_ALLOWED : return("expert function calls are not allowed"                         ); // 4020
      case ERR_NO_MEMORY_FOR_RETURNED_STR : return("not enough memory for temp string returned from function"      ); // 4021
      case ERR_SYSTEM_BUSY                : return("system busy"                                                   ); // 4022
      case ERR_INVALID_FUNCTION_PARAMSCNT : return("invalid function parameter count"                              ); // 4050 invalid parameters count
      case ERR_INVALID_FUNCTION_PARAMVALUE: return("invalid function parameter value"                              ); // 4051 invalid parameter value
      case ERR_STRING_FUNCTION_INTERNAL   : return("string function internal error"                                ); // 4052
      case ERR_SOME_ARRAY_ERROR           : return("array error"                                                   ); // 4053 some array error
      case ERR_INCORRECT_SERIESARRAY_USING: return("incorrect series array using"                                  ); // 4054
      case ERR_CUSTOM_INDICATOR_ERROR     : return("custom indicator error"                                        ); // 4055 custom indicator error
      case ERR_INCOMPATIBLE_ARRAYS        : return("incompatible arrays"                                           ); // 4056 incompatible arrays
      case ERR_GLOBAL_VARIABLES_PROCESSING: return("global variables processing error"                             ); // 4057
      case ERR_GLOBAL_VARIABLE_NOT_FOUND  : return("global variable not found"                                     ); // 4058
      case ERR_FUNC_NOT_ALLOWED_IN_TESTING: return("function not allowed in test mode"                             ); // 4059
      case ERR_FUNCTION_NOT_CONFIRMED     : return("function not confirmed"                                        ); // 4060
      case ERR_SEND_MAIL_ERROR            : return("send mail error"                                               ); // 4061
      case ERR_STRING_PARAMETER_EXPECTED  : return("string parameter expected"                                     ); // 4062
      case ERR_INTEGER_PARAMETER_EXPECTED : return("integer parameter expected"                                    ); // 4063
      case ERR_DOUBLE_PARAMETER_EXPECTED  : return("double parameter expected"                                     ); // 4064
      case ERR_ARRAY_AS_PARAMETER_EXPECTED: return("array parameter expected"                                      ); // 4065
      case ERR_HISTORY_UPDATE             : return("requested history data in update state"                        ); // 4066 history in update state
      case ERR_TRADE_ERROR                : return("error in trading function"                                     ); // 4067 error in trading function
      case ERR_END_OF_FILE                : return("end of file"                                                   ); // 4099 end of file
      case ERR_SOME_FILE_ERROR            : return("file error"                                                    ); // 4100 some file error
      case ERR_WRONG_FILE_NAME            : return("wrong file name"                                               ); // 4101
      case ERR_TOO_MANY_OPENED_FILES      : return("too many opened files"                                         ); // 4102
      case ERR_CANNOT_OPEN_FILE           : return("cannot open file"                                              ); // 4103
      case ERR_INCOMPATIBLE_FILEACCESS    : return("incompatible file access"                                      ); // 4104
      case ERR_NO_ORDER_SELECTED          : return("no order selected"                                             ); // 4105
      case ERR_UNKNOWN_SYMBOL             : return("unknown symbol"                                                ); // 4106
      case ERR_INVALID_PRICE_PARAM        : return("invalid price parameter for trade function"                    ); // 4107
      case ERR_INVALID_TICKET             : return("invalid ticket"                                                ); // 4108
      case ERR_TRADE_NOT_ALLOWED          : return("live trading is not enabled"                                   ); // 4109
      case ERR_LONGS_NOT_ALLOWED          : return("long trades are not enabled"                                   ); // 4110
      case ERR_SHORTS_NOT_ALLOWED         : return("short trades are not enabled"                                  ); // 4111
      case ERR_OBJECT_ALREADY_EXISTS      : return("object already exists"                                         ); // 4200
      case ERR_UNKNOWN_OBJECT_PROPERTY    : return("unknown object property"                                       ); // 4201
      case ERR_OBJECT_DOES_NOT_EXIST      : return("object doesn't exist"                                          ); // 4202
      case ERR_UNKNOWN_OBJECT_TYPE        : return("unknown object type"                                           ); // 4203
      case ERR_NO_OBJECT_NAME             : return("no object name"                                                ); // 4204
      case ERR_OBJECT_COORDINATES_ERROR   : return("object coordinates error"                                      ); // 4205
      case ERR_NO_SPECIFIED_SUBWINDOW     : return("no specified subwindow"                                        ); // 4206
      case ERR_SOME_OBJECT_ERROR          : return("object error"                                                  ); // 4207

      // custom errors
      case ERR_WIN32_ERROR                : return("win32 api error"                                               ); // 5000
      case ERR_FUNCTION_NOT_IMPLEMENTED   : return("function not implemented"                                      ); // 5001
      case ERR_INVALID_INPUT_PARAMVALUE   : return("invalid input parameter value"                                 ); // 5002
      case ERR_INVALID_CONFIG_PARAMVALUE  : return("invalid configuration parameter value"                         ); // 5003
      case ERR_TERMINAL_NOT_YET_READY     : return("terminal not yet ready"                                        ); // 5004
      case ERR_INVALID_TIMEZONE_CONFIG    : return("invalid or missing timezone configuration"                     ); // 5005
      case ERR_INVALID_MARKETINFO         : return("invalid MarketInfo() data"                                     ); // 5006
      case ERR_FILE_NOT_FOUND             : return("file not found"                                                ); // 5007
      case ERR_CANCELLED_BY_USER          : return("cancelled by user intervention"                                ); // 5008
   }
   return("unknown error");
}


/**
 * Gibt die lesbare Konstante eines MQL-Fehlercodes zur�ck.
 *
 * @param  int error - MQL-Fehlercode
 *
 * @return string
 */
string ErrorToStr(int error) {
   switch (error) {
      case NO_ERROR                       : return("NO_ERROR"                       ); //    0

      // trade server errors
      case ERR_NO_RESULT                  : return("ERR_NO_RESULT"                  ); //    1
      case ERR_COMMON_ERROR               : return("ERR_COMMON_ERROR"               ); //    2
      case ERR_INVALID_TRADE_PARAMETERS   : return("ERR_INVALID_TRADE_PARAMETERS"   ); //    3
      case ERR_SERVER_BUSY                : return("ERR_SERVER_BUSY"                ); //    4
      case ERR_OLD_VERSION                : return("ERR_OLD_VERSION"                ); //    5
      case ERR_NO_CONNECTION              : return("ERR_NO_CONNECTION"              ); //    6
      case ERR_NOT_ENOUGH_RIGHTS          : return("ERR_NOT_ENOUGH_RIGHTS"          ); //    7
      case ERR_TOO_FREQUENT_REQUESTS      : return("ERR_TOO_FREQUENT_REQUESTS"      ); //    8
      case ERR_MALFUNCTIONAL_TRADE        : return("ERR_MALFUNCTIONAL_TRADE"        ); //    9
      case ERR_ACCOUNT_DISABLED           : return("ERR_ACCOUNT_DISABLED"           ); //   64
      case ERR_INVALID_ACCOUNT            : return("ERR_INVALID_ACCOUNT"            ); //   65
      case ERR_TRADE_TIMEOUT              : return("ERR_TRADE_TIMEOUT"              ); //  128
      case ERR_INVALID_PRICE              : return("ERR_INVALID_PRICE"              ); //  129
      case ERR_INVALID_STOPS              : return("ERR_INVALID_STOPS"              ); //  130
      case ERR_INVALID_TRADE_VOLUME       : return("ERR_INVALID_TRADE_VOLUME"       ); //  131
      case ERR_MARKET_CLOSED              : return("ERR_MARKET_CLOSED"              ); //  132
      case ERR_TRADE_DISABLED             : return("ERR_TRADE_DISABLED"             ); //  133
      case ERR_NOT_ENOUGH_MONEY           : return("ERR_NOT_ENOUGH_MONEY"           ); //  134
      case ERR_PRICE_CHANGED              : return("ERR_PRICE_CHANGED"              ); //  135
      case ERR_OFF_QUOTES                 : return("ERR_OFF_QUOTES"                 ); //  136
      case ERR_BROKER_BUSY                : return("ERR_BROKER_BUSY"                ); //  137
      case ERR_REQUOTE                    : return("ERR_REQUOTE"                    ); //  138
      case ERR_ORDER_LOCKED               : return("ERR_ORDER_LOCKED"               ); //  139
      case ERR_LONG_POSITIONS_ONLY_ALLOWED: return("ERR_LONG_POSITIONS_ONLY_ALLOWED"); //  140
      case ERR_TOO_MANY_REQUESTS          : return("ERR_TOO_MANY_REQUESTS"          ); //  141
      case ERR_TRADE_MODIFY_DENIED        : return("ERR_TRADE_MODIFY_DENIED"        ); //  145
      case ERR_TRADE_CONTEXT_BUSY         : return("ERR_TRADE_CONTEXT_BUSY"         ); //  146
      case ERR_TRADE_EXPIRATION_DENIED    : return("ERR_TRADE_EXPIRATION_DENIED"    ); //  147
      case ERR_TRADE_TOO_MANY_ORDERS      : return("ERR_TRADE_TOO_MANY_ORDERS"      ); //  148
      case ERR_TRADE_HEDGE_PROHIBITED     : return("ERR_TRADE_HEDGE_PROHIBITED"     ); //  149
      case ERR_TRADE_PROHIBITED_BY_FIFO   : return("ERR_TRADE_PROHIBITED_BY_FIFO"   ); //  150

      // runtime errors
      case ERR_RUNTIME_ERROR              : return("ERR_RUNTIME_ERROR"              ); // 4000
      case ERR_WRONG_FUNCTION_POINTER     : return("ERR_WRONG_FUNCTION_POINTER"     ); // 4001
      case ERR_ARRAY_INDEX_OUT_OF_RANGE   : return("ERR_ARRAY_INDEX_OUT_OF_RANGE"   ); // 4002
      case ERR_NO_MEMORY_FOR_CALL_STACK   : return("ERR_NO_MEMORY_FOR_CALL_STACK"   ); // 4003
      case ERR_RECURSIVE_STACK_OVERFLOW   : return("ERR_RECURSIVE_STACK_OVERFLOW"   ); // 4004
      case ERR_NOT_ENOUGH_STACK_FOR_PARAM : return("ERR_NOT_ENOUGH_STACK_FOR_PARAM" ); // 4005
      case ERR_NO_MEMORY_FOR_PARAM_STRING : return("ERR_NO_MEMORY_FOR_PARAM_STRING" ); // 4006
      case ERR_NO_MEMORY_FOR_TEMP_STRING  : return("ERR_NO_MEMORY_FOR_TEMP_STRING"  ); // 4007
      case ERR_NOT_INITIALIZED_STRING     : return("ERR_NOT_INITIALIZED_STRING"     ); // 4008
      case ERR_NOT_INITIALIZED_ARRAYSTRING: return("ERR_NOT_INITIALIZED_ARRAYSTRING"); // 4009
      case ERR_NO_MEMORY_FOR_ARRAYSTRING  : return("ERR_NO_MEMORY_FOR_ARRAYSTRING"  ); // 4010
      case ERR_TOO_LONG_STRING            : return("ERR_TOO_LONG_STRING"            ); // 4011
      case ERR_REMAINDER_FROM_ZERO_DIVIDE : return("ERR_REMAINDER_FROM_ZERO_DIVIDE" ); // 4012
      case ERR_ZERO_DIVIDE                : return("ERR_ZERO_DIVIDE"                ); // 4013
      case ERR_UNKNOWN_COMMAND            : return("ERR_UNKNOWN_COMMAND"            ); // 4014
      case ERR_WRONG_JUMP                 : return("ERR_WRONG_JUMP"                 ); // 4015
      case ERR_NOT_INITIALIZED_ARRAY      : return("ERR_NOT_INITIALIZED_ARRAY"      ); // 4016
      case ERR_DLL_CALLS_NOT_ALLOWED      : return("ERR_DLL_CALLS_NOT_ALLOWED"      ); // 4017
      case ERR_CANNOT_LOAD_LIBRARY        : return("ERR_CANNOT_LOAD_LIBRARY"        ); // 4018
      case ERR_CANNOT_CALL_FUNCTION       : return("ERR_CANNOT_CALL_FUNCTION"       ); // 4019
      case ERR_EXTERNAL_CALLS_NOT_ALLOWED : return("ERR_EXTERNAL_CALLS_NOT_ALLOWED" ); // 4020
      case ERR_NO_MEMORY_FOR_RETURNED_STR : return("ERR_NO_MEMORY_FOR_RETURNED_STR" ); // 4021
      case ERR_SYSTEM_BUSY                : return("ERR_SYSTEM_BUSY"                ); // 4022
      case ERR_INVALID_FUNCTION_PARAMSCNT : return("ERR_INVALID_FUNCTION_PARAMSCNT" ); // 4050
      case ERR_INVALID_FUNCTION_PARAMVALUE: return("ERR_INVALID_FUNCTION_PARAMVALUE"); // 4051
      case ERR_STRING_FUNCTION_INTERNAL   : return("ERR_STRING_FUNCTION_INTERNAL"   ); // 4052
      case ERR_SOME_ARRAY_ERROR           : return("ERR_SOME_ARRAY_ERROR"           ); // 4053
      case ERR_INCORRECT_SERIESARRAY_USING: return("ERR_INCORRECT_SERIESARRAY_USING"); // 4054
      case ERR_CUSTOM_INDICATOR_ERROR     : return("ERR_CUSTOM_INDICATOR_ERROR"     ); // 4055
      case ERR_INCOMPATIBLE_ARRAYS        : return("ERR_INCOMPATIBLE_ARRAYS"        ); // 4056
      case ERR_GLOBAL_VARIABLES_PROCESSING: return("ERR_GLOBAL_VARIABLES_PROCESSING"); // 4057
      case ERR_GLOBAL_VARIABLE_NOT_FOUND  : return("ERR_GLOBAL_VARIABLE_NOT_FOUND"  ); // 4058
      case ERR_FUNC_NOT_ALLOWED_IN_TESTING: return("ERR_FUNC_NOT_ALLOWED_IN_TESTING"); // 4059
      case ERR_FUNCTION_NOT_CONFIRMED     : return("ERR_FUNCTION_NOT_CONFIRMED"     ); // 4060
      case ERR_SEND_MAIL_ERROR            : return("ERR_SEND_MAIL_ERROR"            ); // 4061
      case ERR_STRING_PARAMETER_EXPECTED  : return("ERR_STRING_PARAMETER_EXPECTED"  ); // 4062
      case ERR_INTEGER_PARAMETER_EXPECTED : return("ERR_INTEGER_PARAMETER_EXPECTED" ); // 4063
      case ERR_DOUBLE_PARAMETER_EXPECTED  : return("ERR_DOUBLE_PARAMETER_EXPECTED"  ); // 4064
      case ERR_ARRAY_AS_PARAMETER_EXPECTED: return("ERR_ARRAY_AS_PARAMETER_EXPECTED"); // 4065
      case ERR_HISTORY_UPDATE             : return("ERR_HISTORY_UPDATE"             ); // 4066
      case ERR_TRADE_ERROR                : return("ERR_TRADE_ERROR"                ); // 4067
      case ERR_END_OF_FILE                : return("ERR_END_OF_FILE"                ); // 4099
      case ERR_SOME_FILE_ERROR            : return("ERR_SOME_FILE_ERROR"            ); // 4100
      case ERR_WRONG_FILE_NAME            : return("ERR_WRONG_FILE_NAME"            ); // 4101
      case ERR_TOO_MANY_OPENED_FILES      : return("ERR_TOO_MANY_OPENED_FILES"      ); // 4102
      case ERR_CANNOT_OPEN_FILE           : return("ERR_CANNOT_OPEN_FILE"           ); // 4103
      case ERR_INCOMPATIBLE_FILEACCESS    : return("ERR_INCOMPATIBLE_FILEACCESS"    ); // 4104
      case ERR_NO_ORDER_SELECTED          : return("ERR_NO_ORDER_SELECTED"          ); // 4105
      case ERR_UNKNOWN_SYMBOL             : return("ERR_UNKNOWN_SYMBOL"             ); // 4106
      case ERR_INVALID_PRICE_PARAM        : return("ERR_INVALID_PRICE_PARAM"        ); // 4107
      case ERR_INVALID_TICKET             : return("ERR_INVALID_TICKET"             ); // 4108
      case ERR_TRADE_NOT_ALLOWED          : return("ERR_TRADE_NOT_ALLOWED"          ); // 4109
      case ERR_LONGS_NOT_ALLOWED          : return("ERR_LONGS_NOT_ALLOWED"          ); // 4110
      case ERR_SHORTS_NOT_ALLOWED         : return("ERR_SHORTS_NOT_ALLOWED"         ); // 4111
      case ERR_OBJECT_ALREADY_EXISTS      : return("ERR_OBJECT_ALREADY_EXISTS"      ); // 4200
      case ERR_UNKNOWN_OBJECT_PROPERTY    : return("ERR_UNKNOWN_OBJECT_PROPERTY"    ); // 4201
      case ERR_OBJECT_DOES_NOT_EXIST      : return("ERR_OBJECT_DOES_NOT_EXIST"      ); // 4202
      case ERR_UNKNOWN_OBJECT_TYPE        : return("ERR_UNKNOWN_OBJECT_TYPE"        ); // 4203
      case ERR_NO_OBJECT_NAME             : return("ERR_NO_OBJECT_NAME"             ); // 4204
      case ERR_OBJECT_COORDINATES_ERROR   : return("ERR_OBJECT_COORDINATES_ERROR"   ); // 4205
      case ERR_NO_SPECIFIED_SUBWINDOW     : return("ERR_NO_SPECIFIED_SUBWINDOW"     ); // 4206
      case ERR_SOME_OBJECT_ERROR          : return("ERR_SOME_OBJECT_ERROR"          ); // 4207

      // custom errors
      case ERR_WIN32_ERROR                : return("ERR_WIN32_ERROR"                ); // 5000
      case ERR_FUNCTION_NOT_IMPLEMENTED   : return("ERR_FUNCTION_NOT_IMPLEMENTED"   ); // 5001
      case ERR_INVALID_INPUT_PARAMVALUE   : return("ERR_INVALID_INPUT_PARAMVALUE"   ); // 5002
      case ERR_INVALID_CONFIG_PARAMVALUE  : return("ERR_INVALID_CONFIG_PARAMVALUE"  ); // 5003
      case ERR_TERMINAL_NOT_YET_READY     : return("ERR_TERMINAL_NOT_YET_READY"     ); // 5004
      case ERR_INVALID_TIMEZONE_CONFIG    : return("ERR_INVALID_TIMEZONE_CONFIG"    ); // 5005
      case ERR_INVALID_MARKETINFO         : return("ERR_INVALID_MARKETINFO"         ); // 5006
      case ERR_FILE_NOT_FOUND             : return("ERR_FILE_NOT_FOUND"             ); // 5007
      case ERR_CANCELLED_BY_USER          : return("ERR_CANCELLED_BY_USER"          ); // 5008
   }
   return(error);
}


/**
 * Gibt die lesbare Beschreibung eines ShellExecute() oder ShellExecuteEx()-Fehlercodes zur�ck.
 *
 * @param  int error - ShellExecute-Fehlercode
 *
 * @return string
 */
string ShellExecuteErrorToStr(int error) {
   switch (error) {
      case 0                     : return("Out of memory or resources."                        );
      case ERROR_BAD_FORMAT      : return("Incorrect file format."                             );
      case SE_ERR_FNF            : return("File not found."                                    );
      case SE_ERR_PNF            : return("Path not found."                                    );
      case SE_ERR_ACCESSDENIED   : return("Access denied."                                     );
      case SE_ERR_OOM            : return("Out of memory."                                     );
      case SE_ERR_SHARE          : return("A sharing violation occurred."                      );
      case SE_ERR_ASSOCINCOMPLETE: return("File association information incomplete or invalid.");
      case SE_ERR_DDETIMEOUT     : return("DDE operation timed out."                           );
      case SE_ERR_DDEFAIL        : return("DDE operation failed."                              );
      case SE_ERR_DDEBUSY        : return("DDE operation is busy."                             );
      case SE_ERR_NOASSOC        : return("File association information not available."        );
      case SE_ERR_DLLNOTFOUND    : return("Dynamic-link library not found."                    );
   }
   return("unknown error");
}


/**
 * Gibt die lesbare Version eines Events zur�ck.
 *
 * @param  int event - Event
 *
 * @return string
 */
string EventToStr(int event) {
   switch (event) {
      case EVENT_BAR_OPEN       : return("BarOpen"       );
      case EVENT_ORDER_PLACE    : return("OrderPlace"    );
      case EVENT_ORDER_CHANGE   : return("OrderChange"   );
      case EVENT_ORDER_CANCEL   : return("OrderCancel"   );
      case EVENT_POSITION_OPEN  : return("PositionOpen"  );
      case EVENT_POSITION_CLOSE : return("PositionClose" );
      case EVENT_ACCOUNT_CHANGE : return("AccountChange" );
      case EVENT_ACCOUNT_PAYMENT: return("AccountPayment");
      case EVENT_HISTORY_CHANGE : return("HistoryChange" );
   }
   return(_empty(catch("EventToStr()   unknown event: "+ event, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt den Offset der angegebenen lokalen Zeit zu GMT (Greenwich Mean Time) zur�ck.
 *
 * @return int - Offset in Sekunden oder EMPTY_VALUE, falls ein Fehler auftrat
 */
int GetLocalToGMTOffset() {
   /*TIME_ZONE_INFORMATION*/int tzi[]; InitializeBuffer(tzi, TIME_ZONE_INFORMATION.size);
   int type = GetTimeZoneInformation(tzi);

   int offset = 0;

   if (type != TIME_ZONE_ID_UNKNOWN) {
      offset = tzi.Bias(tzi);
      if (type == TIME_ZONE_ID_DAYLIGHT)
         offset += tzi.DaylightBias(tzi);
      offset *= -60;
   }

   if (catch("GetLocalToGMTOffset()") != NO_ERROR)
      return(EMPTY_VALUE);

   return(offset);
}


/**
 * Gibt die lesbare Konstante einer MovingAverage-Methode zur�ck.
 *
 * @param  int type - MA-Methode
 *
 * @return string
 */
string MovingAverageMethodToStr(int method) {
   switch (method) {
      case MODE_SMA : return("MODE_SMA" );
      case MODE_EMA : return("MODE_EMA" );
      case MODE_SMMA: return("MODE_SMMA");
      case MODE_LWMA: return("MODE_LWMA");
      case MODE_ALMA: return("MODE_ALMA");
   }
   return(_empty(catch("MovingAverageMethodToStr()  invalid paramter method = "+ method, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Beschreibung einer MovingAverage-Methode zur�ck.
 *
 * @param  int type - MA-Methode
 *
 * @return string
 */
string MovingAverageMethodDescription(int method) {
   switch (method) {
      case MODE_SMA : return("SMA" );
      case MODE_EMA : return("EMA" );
      case MODE_SMMA: return("SMMA");
      case MODE_LWMA: return("LWMA");
      case MODE_ALMA: return("ALMA");
   }
   return(_empty(catch("MovingAverageMethodDescription()  invalid paramter method = "+ method, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die numerische Konstante einer MovingAverage-Methode zur�ck.
 *
 * @param  string method - MA-Methode: [MODE_][SMA|EMA|SMMA|LWMA|ALMA]
 *
 * @return int - MA-Konstante oder -1, wenn der Methodenbezeichner unbekannt ist
 */
int MovingAverageMethodToId(string method) {
   string value = StringToUpper(method);

   if (StringStartsWith(value, "MODE_"))
      value = StringRight(value, -5);

   if (value == "SMA" ) return(MODE_SMA );
   if (value == "EMA" ) return(MODE_EMA );
   if (value == "SMMA") return(MODE_SMMA);
   if (value == "LWMA") return(MODE_LWMA);
   if (value == "ALMA") return(MODE_ALMA);

   return(_int(-1, log("MovingAverageMethodToId()  invalid parameter method: \""+ method +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante einer MessageBox-Command-ID zur�ck.
 *
 * @param  int cmd - Command-ID (entspricht dem gedr�ckten Messagebox-Button)
 *
 * @return string
 */
string MessageBoxCmdToStr(int cmd) {
   switch (cmd) {
      case IDOK      : return("IDOK"      );
      case IDCANCEL  : return("IDCANCEL"  );
      case IDABORT   : return("IDABORT"   );
      case IDRETRY   : return("IDRETRY"   );
      case IDIGNORE  : return("IDIGNORE"  );
      case IDYES     : return("IDYES"     );
      case IDNO      : return("IDNO"      );
      case IDCLOSE   : return("IDCLOSE"   );
      case IDHELP    : return("IDHELP"    );
      case IDTRYAGAIN: return("IDTRYAGAIN");
      case IDCONTINUE: return("IDCONTINUE");
   }
   return(_empty(catch("MessageBoxCmdToStr()  unknown message box command = "+ cmd, ERR_RUNTIME_ERROR)));
}


/**
 * Ob der �bergebene Parameter eine Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsTradeOperation(int value) {
   switch (value) {
      case OP_BUY:
      case OP_SELL:
      case OP_BUYLIMIT:
      case OP_SELLLIMIT:
      case OP_BUYSTOP:
      case OP_SELLSTOP:
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine Long-Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsLongTradeOperation(int value) {
   switch (value) {
      case OP_BUY:
      case OP_BUYLIMIT:
      case OP_BUYSTOP:
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine Short-Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsShortTradeOperation(int value) {
   switch (value) {
      case OP_SELL:
      case OP_SELLLIMIT:
      case OP_SELLSTOP:
         return(true);
   }
   return(false);
}


/**
 * Ob der �bergebene Parameter eine "pending" Tradeoperation bezeichnet.
 *
 * @param  int value - zu pr�fender Wert
 *
 * @return bool
 */
bool IsPendingTradeOperation(int value) {
   switch (value) {
      case OP_BUYLIMIT:
      case OP_SELLLIMIT:
      case OP_BUYSTOP:
      case OP_SELLSTOP:
         return(true);
   }
   return(false);
}


/**
 * Gibt die lesbare Konstante eines Operation-Types zur�ck.
 *
 * @param  int type - Operation-Type
 *
 * @return string
 */
string OperationTypeToStr(int type) {
   switch (type) {
      case OP_BUY      : return("OP_BUY"      );
      case OP_SELL     : return("OP_SELL"     );
      case OP_BUYLIMIT : return("OP_BUYLIMIT" );
      case OP_SELLLIMIT: return("OP_SELLLIMIT");
      case OP_BUYSTOP  : return("OP_BUYSTOP"  );
      case OP_SELLSTOP : return("OP_SELLSTOP" );
      case OP_BALANCE  : return("OP_BALANCE"  );
      case OP_CREDIT   : return("OP_CREDIT"   );
   }
   return(_empty(catch("OperationTypeToStr()  invalid parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die Beschreibung eines Operation-Types zur�ck.
 *
 * @param  int type - Operation-Type
 *
 * @return string
 */
string OperationTypeDescription(int type) {
   switch (type) {
      case OP_BUY      : return("Buy"       );
      case OP_SELL     : return("Sell"      );
      case OP_BUYLIMIT : return("Buy Limit" );
      case OP_SELLLIMIT: return("Sell Limit");
      case OP_BUYSTOP  : return("Stop Buy"  );
      case OP_SELLSTOP : return("Stop Sell" );
      case OP_BALANCE  : return("Balance"   );
      case OP_CREDIT   : return("Credit"    );
   }
   return(_empty(catch("OperationTypeDescription()  invalid parameter type = "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante eines Price-Identifiers zur�ck.
 *
 * @param  int appliedPrice - Price-Typ, siehe: iMA(symbol, timeframe, period, ma_shift, ma_method, int *APPLIED_PRICE*, bar)
 *
 * @return string
 */
string AppliedPriceToStr(int appliedPrice) {
   switch (appliedPrice) {
      case PRICE_CLOSE   : return("PRICE_CLOSE"   );     // Close price
      case PRICE_OPEN    : return("PRICE_OPEN"    );     // Open price
      case PRICE_HIGH    : return("PRICE_HIGH"    );     // High price
      case PRICE_LOW     : return("PRICE_LOW"     );     // Low price
      case PRICE_MEDIAN  : return("PRICE_MEDIAN"  );     // Median price:         (High+Low)/2
      case PRICE_TYPICAL : return("PRICE_TYPICAL" );     // Typical price:        (High+Low+Close)/3
      case PRICE_WEIGHTED: return("PRICE_WEIGHTED");     // Weighted close price: (High+Low+Close+Close)/4
   }
   return(_empty(catch("AppliedPriceToStr()  invalid parameter appliedPrice: "+ appliedPrice, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Version eines Price-Identifiers zur�ck.
 *
 * @param  int appliedPrice - Price-Typ, siehe: iMA(symbol, timeframe, period, ma_shift, ma_method, int *APPLIED_PRICE*, bar)
 *
 * @return string
 */
string AppliedPriceDescription(int appliedPrice) {
   switch (appliedPrice) {
      case PRICE_CLOSE   : return("Close"   );     // Close price
      case PRICE_OPEN    : return("Open"    );     // Open price
      case PRICE_HIGH    : return("High"    );     // High price
      case PRICE_LOW     : return("Low"     );     // Low price
      case PRICE_MEDIAN  : return("Median"  );     // Median price:         (High+Low)/2
      case PRICE_TYPICAL : return("Typical" );     // Typical price:        (High+Low+Close)/3
      case PRICE_WEIGHTED: return("Weighted");     // Weighted close price: (High+Low+Close+Close)/4
   }
   return(_empty(catch("AppliedPriceDescription()  invalid parameter appliedPrice: "+ appliedPrice, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt den Integer-Wert eines Timeframe-Bezeichners zur�ck.
 *
 * @param  string timeframe - M1, M5, M15, M30 etc.
 *
 * @return int - Timeframe-Code oder -1, wenn der Bezeichner ung�ltig ist
 */
int PeriodToId(string timeframe) {
   timeframe = StringToUpper(timeframe);

   if (StringStartsWith(timeframe, "PERIOD_"))
      timeframe = StringRight(timeframe, -7);

   if (timeframe == "M1" ) return(PERIOD_M1 );     //     1  1 minute
   if (timeframe == "M5" ) return(PERIOD_M5 );     //     5  5 minutes
   if (timeframe == "M15") return(PERIOD_M15);     //    15  15 minutes
   if (timeframe == "M30") return(PERIOD_M30);     //    30  30 minutes
   if (timeframe == "H1" ) return(PERIOD_H1 );     //    60  1 hour
   if (timeframe == "H4" ) return(PERIOD_H4 );     //   240  4 hour
   if (timeframe == "D1" ) return(PERIOD_D1 );     //  1440  daily
   if (timeframe == "W1" ) return(PERIOD_W1 );     // 10080  weekly
   if (timeframe == "MN1") return(PERIOD_MN1);     // 43200  monthly

   return(_int(-1, log("PeriodToId()  invalid parameter timeframe: \""+ timeframe +"\"", ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante einer Timeframe-ID zur�ck.
 *
 * @param  int period - Timeframe-Code bzw. Anzahl der Minuten je Chart-Bar (default: aktuelle Periode)
 *
 * @return string
 */
string PeriodToStr(int period=NULL) {
   if (period == NULL)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return("PERIOD_M1" );     //     1  1 minute
      case PERIOD_M5 : return("PERIOD_M5" );     //     5  5 minutes
      case PERIOD_M15: return("PERIOD_M15");     //    15  15 minutes
      case PERIOD_M30: return("PERIOD_M30");     //    30  30 minutes
      case PERIOD_H1 : return("PERIOD_H1" );     //    60  1 hour
      case PERIOD_H4 : return("PERIOD_H4" );     //   240  4 hour
      case PERIOD_D1 : return("PERIOD_D1" );     //  1440  daily
      case PERIOD_W1 : return("PERIOD_W1" );     // 10080  weekly
      case PERIOD_MN1: return("PERIOD_MN1");     // 43200  monthly
   }
   return(_empty(catch("PeriodToStr()  invalid parameter period: "+ period, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die Beschreibung eines Timeframe-Codes zur�ck.
 *
 * @param  int period - Timeframe-Code bzw. Anzahl der Minuten je Chart-Bar (default: aktuelle Periode)
 *
 * @return string
 */
string PeriodDescription(int period=NULL) {
   if (period == NULL)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return("M1" );     //     1  1 minute
      case PERIOD_M5 : return("M5" );     //     5  5 minutes
      case PERIOD_M15: return("M15");     //    15  15 minutes
      case PERIOD_M30: return("M30");     //    30  30 minutes
      case PERIOD_H1 : return("H1" );     //    60  1 hour
      case PERIOD_H4 : return("H4" );     //   240  4 hour
      case PERIOD_D1 : return("D1" );     //  1440  daily
      case PERIOD_W1 : return("W1" );     // 10080  weekly
      case PERIOD_MN1: return("MN1");     // 43200  monthly
   }
   return(_empty(catch("PeriodDescription()  invalid parameter period: "+ period, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt das Timeframe-Flag der angegebenen Chartperiode zur�ck.
 *
 * @param  int period - Timeframe-Identifier (default: Periode des aktuellen Charts)
 *
 * @return int - Timeframe-Flag
 */
int PeriodFlag(int period=NULL) {
   if (period == NULL)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return(PERIODFLAG_M1 );
      case PERIOD_M5 : return(PERIODFLAG_M5 );
      case PERIOD_M15: return(PERIODFLAG_M15);
      case PERIOD_M30: return(PERIODFLAG_M30);
      case PERIOD_H1 : return(PERIODFLAG_H1 );
      case PERIOD_H4 : return(PERIODFLAG_H4 );
      case PERIOD_D1 : return(PERIODFLAG_D1 );
      case PERIOD_W1 : return(PERIODFLAG_W1 );
      case PERIOD_MN1: return(PERIODFLAG_MN1);
   }
   return(_ZERO(catch("PeriodFlag()  invalid parameter period: "+ period, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Version eines Timeframe-Flags zur�ck.
 *
 * @param  int flags - Kombination verschiedener Timeframe-Flags
 *
 * @return string
 */
string PeriodFlagToStr(int flags) {
   string result = "";

   if (flags & PERIODFLAG_M1  != 0) result = StringConcatenate(result, " | M1" );
   if (flags & PERIODFLAG_M5  != 0) result = StringConcatenate(result, " | M5" );
   if (flags & PERIODFLAG_M15 != 0) result = StringConcatenate(result, " | M15");
   if (flags & PERIODFLAG_M30 != 0) result = StringConcatenate(result, " | M30");
   if (flags & PERIODFLAG_H1  != 0) result = StringConcatenate(result, " | H1" );
   if (flags & PERIODFLAG_H4  != 0) result = StringConcatenate(result, " | H4" );
   if (flags & PERIODFLAG_D1  != 0) result = StringConcatenate(result, " | D1" );
   if (flags & PERIODFLAG_W1  != 0) result = StringConcatenate(result, " | W1" );
   if (flags & PERIODFLAG_MN1 != 0) result = StringConcatenate(result, " | MN1");

   if (StringLen(result) > 0)
      result = StringSubstr(result, 3);
   return(result);
}


/**
 * Gibt die Zeitzone des aktuellen MT-Servers zur�ck (nach Olson Timezone Database).
 *
 * @return string - Zeitzonen-Identifier oder Leerstring, wenn ein Fehler auftrat
 *
 * @see http://en.wikipedia.org/wiki/Tz_database
 */
string GetServerTimezone() /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {

   // Die Timezone-ID wird zwischengespeichert und erst mit Auftreten von ValidBars = 0 verworfen und neu ermittelt.  Bei Accountwechsel zeigen die
   // R�ckgabewerte der MQL-Accountfunktionen evt. schon auf den neuen Account, der aktuelle Tick geh�rt aber noch zum alten Chart (mit den alten Bars).
   // Erst ValidBars = 0 stellt sicher, da� wir uns tats�chlich im neuen Chart mit neuer Zeitzone befinden.
   static string cache.timezone[];
   static int    lastTick;                                           // Erkennung von Mehrfachaufrufen w�hrend desselben Ticks

   // 1) wenn ValidBars==0 && neuer Tick, Cache verwerfen
   if (ValidBars == 0) /*&&*/ if (Tick != lastTick)
      ArrayResize(cache.timezone, 0);
   lastTick = Tick;

   // 2) wenn Wert im Cache, gecachten Wert zur�ckgeben
   if (ArraySize(cache.timezone) > 0)
      return(cache.timezone[0]);

   // 3) Timezone-ID ermitteln
   string timezone, directory=StringToLower(GetTradeServerDirectory());

   if (StringLen(directory) == 0)
      return("");
   else if (StringStartsWith(directory, "alpari-"            )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "alparibroker-"      )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "alpariuk-"          )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "alparius-"          )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "apbgtrading-"       )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "atcbrokers-"        )) timezone = "FXT";
   else if (StringStartsWith(directory, "atcbrokersest-"     )) timezone = "America/New_York";
   else if (StringStartsWith(directory, "atcbrokersliq1-"    )) timezone = "FXT";
   else if (StringStartsWith(directory, "broco-"             )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "brocoinvestments-"  )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "dukascopy-"         )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "easyforex-"         )) timezone = "GMT";
   else if (StringStartsWith(directory, "finfx-"             )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "forex-"             )) timezone = "GMT";
   else if (StringStartsWith(directory, "fxprimus-"          )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "fxpro.com-"         )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "fxdd-"              )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "gcmfx-"             )) timezone = "GMT";
   else if (StringStartsWith(directory, "inovatrade-"        )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "investorseurope-"   )) timezone = "Europe/London";
   else if (StringStartsWith(directory, "londoncapitalgr-"   )) timezone = "GMT";
   else if (StringStartsWith(directory, "londoncapitalgroup-")) timezone = "GMT";
   else if (StringStartsWith(directory, "mbtrading-"         )) timezone = "America/New_York";
   else if (StringStartsWith(directory, "migbank-"           )) timezone = "Europe/Berlin";
   else if (StringStartsWith(directory, "oanda-"             )) timezone = "America/New_York";
   else if (StringStartsWith(directory, "sig-"               )) timezone = "Europe/Minsk";
   else if (StringStartsWith(directory, "sts-"               )) timezone = "Europe/Kiev";
   else if (StringStartsWith(directory, "teletrade-"         )) timezone = "Europe/Berlin";
   else {
      // Fallback zur manuellen Konfiguration in globaler Config
      timezone = GetGlobalConfigString("Timezones", directory, "");
      if (StringLen(timezone) == 0)
         return(_empty(catch("GetServerTimezone(1)  missing timezone configuration for trade server \""+ GetTradeServerDirectory() +"\"", ERR_INVALID_TIMEZONE_CONFIG)));
   }

   // 4) Timezone-ID cachen
   ArrayResize(cache.timezone, 1);
   cache.timezone[0] = timezone;

   if (IsError(catch("GetServerTimezone(2)")))
      return("");
   return(timezone);
}


/**
 * Gibt das Handle des Hauptfensters des MetaTrader-Terminals zur�ck.
 *
 * @return int - Handle oder 0, falls ein Fehler auftrat
 */
int GetTerminalWindow() {
   static int hWnd;                             // in Library �berleben statische Variablen Timeframe-Wechsel, solange sie nicht per Initializer initialisiert werden
   if (hWnd != 0)
      return(hWnd);

   // WindowHandle()
   if (!IsTesting() || IsVisualMode()) {
      hWnd = WindowHandle(Symbol(), NULL);      // schl�gt in etlichen Situationen fehl (init(), deinit(), in start() bei Programmstart, im Tester)
      if (hWnd != 0) {
         hWnd = GetAncestor(hWnd, GA_ROOT);
         if (GetClassName(hWnd) != MT4_TERMINAL_CLASSNAME) {
            catch("GetTerminalWindow(1)   wrong top-level window found (class \""+ GetClassName(hWnd) +"\"), handle originates from WindowHandle()", ERR_RUNTIME_ERROR);
            hWnd = 0;
         }
         return(hWnd);
      }
   }

   // alle Top-level-Windows durchlaufen
   int processId[1], hWndNext=GetTopWindow(NULL), myProcessId=GetCurrentProcessId();

   while (hWndNext != 0) {
      GetWindowThreadProcessId(hWndNext, processId);
      if (processId[0]==myProcessId) /*&&*/ if (GetClassName(hWndNext)==MT4_TERMINAL_CLASSNAME)
         break;
      hWndNext = GetWindow(hWndNext, GW_HWNDNEXT);
   }
   if (hWndNext == 0) {
      catch("GetTerminalWindow(2)   could not find terminal window", ERR_RUNTIME_ERROR);
      hWnd = 0;
   }
   hWnd = hWndNext;

   return(hWnd);
}


/**
 * Gibt die ID des Userinterface-Threads zur�ck.
 *
 * @return int - tats�chliche Thread-ID (nicht das Pseudo-Handle)
 */
int GetUIThreadId() {
   static int hThread;                       // in Library �berleben statische Variablen Timeframe-Wechsel, solange sie nicht per Initializer initialisiert werden
   if (hThread != 0)
      return(hThread);

   int iNull[];
   hThread = GetWindowThreadProcessId(GetTerminalWindow(), iNull);

   catch("GetUIThreadId()");
   return(hThread);
}


/**
 * Gibt die Beschreibung eines UninitializeReason-Codes zur�ck (siehe UninitializeReason()).
 *
 * @param  int reason - Code
 *
 * @return string
 */
string UninitializeReasonDescription(int reason) {
   switch (reason) {
      case REASON_APPEXIT    : return("application exit"                      );
      case REASON_REMOVE     : return("expert or indicator removed from chart");
      case REASON_RECOMPILE  : return("expert or indicator recompiled"        );
      case REASON_CHARTCHANGE: return("symbol or timeframe changed"           );
      case REASON_CHARTCLOSE : return("chart closed"                          );
      case REASON_PARAMETERS : return("input parameters changed"              );
      case REASON_ACCOUNT    : return("account changed"                       );
   }
   return(_empty(catch("UninitializeReasonDescription()  invalid parameter reason: "+ reason, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt die lesbare Konstante eines UninitializeReason-Codes zur�ck (siehe UninitializeReason()).
 *
 * @param  int reason - Code
 *
 * @return string
 */
string UninitializeReasonToStr(int reason) {
   switch (reason) {
      case REASON_APPEXIT    : return("REASON_APPEXIT"    );
      case REASON_REMOVE     : return("REASON_REMOVE"     );
      case REASON_RECOMPILE  : return("REASON_RECOMPILE"  );
      case REASON_CHARTCHANGE: return("REASON_CHARTCHANGE");
      case REASON_CHARTCLOSE : return("REASON_CHARTCLOSE" );
      case REASON_PARAMETERS : return("REASON_PARAMETERS" );
      case REASON_ACCOUNT    : return("REASON_ACCOUNT"    );
   }
   return(_empty(catch("UninitializeReasonToStr()  invalid parameter reason: "+ reason, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Gibt den Text der Titelbar des angegebenen Fensters zur�ck (wenn es einen hat).  Ist das angegebene Fenster ein Windows-Control,
 * wird dessen Text zur�ckgegeben.
 *
 * @param  int hWnd - Handle des Fensters oder Controls
 *
 * @return string - Text
 */
string GetWindowText(int hWnd) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   int chars = GetWindowTextA(hWnd, buffer[0], bufferSize);

   return(buffer[0]);
}


/**
 * Gibt den Klassennamen des angegebenen Fensters zur�ck.
 *
 * @param  int hWnd - Handle des Fensters
 *
 * @return string - Klassenname
 */
string GetClassName(int hWnd) {
   int    bufferSize = 255;
   string buffer[]; InitializeStringBuffer(buffer, bufferSize);

   int chars = GetClassNameA(hWnd, buffer[0], bufferSize);
   if (chars == 0)
      return(_empty(catch("GetClassName() ->user32::GetClassNameA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR)));

   return(buffer[0]);
}


/**
 * Konvertiert die angegebene GMT-Zeit nach FXT-Zeit (Forex Standard Time).
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GMTToFXT(datetime gmtTime) {
   if (gmtTime < 0)
      return(_int(-1, catch("GMTToFXT(1)  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   int offset = GetGMTToFXTOffset(gmtTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime result = gmtTime - offset;
   if (result < 0)
      return(_int(-1, catch("GMTToFXT(2)   illegal datetime result: "+ result +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   return(result);
}


/**
 * Konvertiert die angegebene GMT-Zeit nach Tradeserver-Zeit.
 *
 * @param  datetime gmtTime - GMT-Zeitpunkt
 *
 * @return datetime - Tradeserver-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime GMTToServerTime(datetime gmtTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (gmtTime < 0)
      return(_int(-1, catch("GMTToServerTime(1)  invalid parameter gmtTime: "+ gmtTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(-1);

   // schnelle R�ckkehr, wenn der Tradeserver unter GMT l�uft
   if (zone == "GMT")
      return(gmtTime);

   int offset = GetGMTToServerTimeOffset(gmtTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime result = gmtTime - offset;
   if (result < 0)
      return(_int(-1, catch("GMTToServerTime(2)   illegal datetime result: "+ result +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   return(result);
}


/**
 * Berechnet den Balancewert eines Accounts am angegebenen Offset des aktuellen Charts und schreibt ihn in das Ergebnisarray.
 *
 * @param  int    account - Account, f�r den der Wert berechnet werden soll
 * @param  double buffer  - Ergebnisarray (z.B. Indikatorpuffer)
 * @param  int    bar     - Barindex des zu berechnenden Wertes (Chart-Offset)
 *
 * @return int - Fehlerstatus
 */
int iAccountBalance(int account, double buffer[], int bar) {

   // TODO: Berechnung einzelner Bar implementieren (zur Zeit wird der Indikator hier noch komplett neuberechnet)

   if (iAccountBalanceSeries(account, buffer) == ERR_HISTORY_UPDATE) {
      catch("iAccountBalance(1)");
      return(SetLastError(ERR_HISTORY_UPDATE));
   }

   return(catch("iAccountBalance(2)"));
}


/**
 * Berechnet den Balanceverlauf eines Accounts f�r alle Bars des aktuellen Charts und schreibt die Werte in das angegebene Zielarray.
 *
 * @param  int    account - Account-Nummer
 * @param  double buffer  - Ergebnisarray (z.B. Indikatorpuffer)
 *
 * @return int - Fehlerstatus
 */
int iAccountBalanceSeries(int account, double& buffer[]) {
   if (ArraySize(buffer) != Bars) {
      ArrayResize(buffer, Bars);
      ArrayInitialize(buffer, EMPTY_VALUE);
   }

   // Balance-History holen
   datetime times []; ArrayResize(times , 0);
   double   values[]; ArrayResize(values, 0);

   int error = GetBalanceHistory(account, times, values);   // aufsteigend nach Zeit sortiert (in times[0] stehen die �ltesten Werte)
   if (error != NO_ERROR) {
      catch("iAccountBalanceSeries(1)");
      return(error);
   }

   int bar, lastBar, historySize=ArraySize(values);

   // Balancewerte f�r Bars des aktuellen Charts ermitteln und ins Ergebnisarray schreiben
   for (int i=0; i < historySize; i++) {
      // Barindex des Zeitpunkts berechnen
      bar = iBarShiftNext(NULL, 0, times[i]);
      if (bar == EMPTY_VALUE)                               // ERR_HISTORY_UPDATE ?
         return(stdlib_GetLastError());
      if (bar == -1)                                        // dieser und alle folgenden Werte sind zu neu f�r den Chart
         break;

      // L�cken mit vorherigem Balancewert f�llen
      if (bar < lastBar-1) {
         for (int z=lastBar-1; z > bar; z--) {
            buffer[z] = buffer[lastBar];
         }
      }

      // aktuellen Balancewert eintragen
      buffer[bar] = values[i];
      lastBar = bar;
   }

   // Ergebnisarray bis zur ersten Bar mit dem letzten bekannten Balancewert f�llen
   for (bar=lastBar-1; bar >= 0; bar--) {
      buffer[bar] = buffer[lastBar];
   }

   return(catch("iAccountBalanceSeries(2)"));
}


/**
 * Ermittelt den Chart-Offset (Bar) eines Zeitpunktes und gibt bei nicht existierender Bar die letzte vorherige existierende Bar zur�ck.
 *
 * @param  string   symbol - Symbol der zu verwendenden Datenreihe (default: NULL = aktuelles Symbol)
 * @param  int      period - Periode der zu verwendenden Datenreihe (default: 0 = aktuelle Periode)
 * @param  datetime time   - Zeitpunkt
 *
 * @return int - Bar-Index oder -1, wenn keine entsprechende Bar existiert (Zeitpunkt ist zu alt f�r den Chart);
 *               EMPTY_VALUE, wenn ein Fehler aufgetreten ist
 */
int iBarShiftPrevious(string symbol/*=NULL*/, int period/*=0*/, datetime time) /*throws ERR_HISTORY_UPDATE*/ {
   if (symbol == "0")                                       // NULL ist Integer (0)
      symbol = Symbol();

   if (time < 0) {
      catch("iBarShiftPrevious(1)  invalid parameter time: "+ time +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   // Datenreihe holen
   datetime times[];
   int bars  = ArrayCopySeries(times, MODE_TIME, symbol, period);
   int error = GetLastError();                              // ERR_HISTORY_UPDATE ???

   if (error == NO_ERROR) {
      // Bars �berpr�fen
      if (time < times[bars-1]) {
         int bar = -1;                                      // Zeitpunkt ist zu alt f�r den Chart
      }
      else {
         bar   = iBarShift(symbol, period, time);
         error = GetLastError();                            // ERR_HISTORY_UPDATE ???
      }
   }

   if (error != NO_ERROR) {
      last_error = error;
      if (error != ERR_HISTORY_UPDATE)
         catch("iBarShiftPrevious(2)", error);
      return(EMPTY_VALUE);
   }
   return(bar);
}


/**
 * Ermittelt den Chart-Offset (Bar) eines Zeitpunktes und gibt bei nicht existierender Bar die n�chste existierende Bar zur�ck.
 *
 * @param  string   symbol - Symbol der zu verwendenden Datenreihe (default: NULL = aktuelles Symbol)
 * @param  int      period - Periode der zu verwendenden Datenreihe (default: 0 = aktuelle Periode)
 * @param  datetime time   - Zeitpunkt
 *
 * @return int - Bar-Index oder -1, wenn keine entsprechende Bar existiert (Zeitpunkt ist zu jung f�r den Chart);
 *               EMPTY_VALUE, wenn ein Fehler aufgetreten ist
 */
int iBarShiftNext(string symbol/*=NULL*/, int period/*=0*/, datetime time) /*throws ERR_HISTORY_UPDATE*/ {
   if (symbol == "0")                                       // NULL ist Integer (0)
      symbol = Symbol();

   if (time < 0) {
      catch("iBarShiftNext(1)  invalid parameter time: "+ time +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(EMPTY_VALUE);
   }

   int bar   = iBarShift(symbol, period, time, true);
   int error = GetLastError();                              // ERR_HISTORY_UPDATE ???

   if (error==NO_ERROR) /*&&*/ if (bar==-1) {               // falls die Bar nicht existiert und auch kein Update l�uft
      // Datenreihe holen
      datetime times[];
      int bars = ArrayCopySeries(times, MODE_TIME, symbol, period);
      error = GetLastError();                               // ERR_HISTORY_UPDATE ???

      if (error == NO_ERROR) {
         // Bars �berpr�fen
         if (time < times[bars-1])                          // Zeitpunkt ist zu alt f�r den Chart, die �lteste Bar zur�ckgeben
            bar = bars-1;

         else if (time < times[0]) {                        // Kursl�cke, die n�chste existierende Bar zur�ckgeben
            bar   = iBarShift(symbol, period, time) - 1;
            error = GetLastError();                         // ERR_HISTORY_UPDATE ???
         }
         //else: (time > times[0]) => bar=-1                // Zeitpunkt ist zu neu f�r den Chart, bar bleibt -1
      }
   }

   if (error != NO_ERROR) {
      last_error = error;
      if (error != ERR_HISTORY_UPDATE)
         catch("iBarShiftNext(2)", error);
      return(EMPTY_VALUE);
   }
   return(bar);
}


/**
 * Gibt die n�chstgr��ere Periode der angegebenen Periode zur�ck.
 *
 * @param  int period - Timeframe-Periode (default: 0 - die aktuelle Periode)
 *
 * @return int - N�chstgr��ere Periode oder der urspr�ngliche Wert, wenn keine gr��ere Periode existiert.
 */
int IncreasePeriod(int period = 0) {
   if (period == 0)
      period = Period();

   switch (period) {
      case PERIOD_M1 : return(PERIOD_M5 );
      case PERIOD_M5 : return(PERIOD_M15);
      case PERIOD_M15: return(PERIOD_M30);
      case PERIOD_M30: return(PERIOD_H1 );
      case PERIOD_H1 : return(PERIOD_H4 );
      case PERIOD_H4 : return(PERIOD_D1 );
      case PERIOD_D1 : return(PERIOD_W1 );
      case PERIOD_W1 : return(PERIOD_MN1);
      case PERIOD_MN1: return(PERIOD_MN1);
   }
   return(_ZERO(catch("IncreasePeriod()  invalid parameter period: "+ period, ERR_INVALID_FUNCTION_PARAMVALUE)));
}


/**
 * Verbindet die Werte eines Boolean-Arrays unter Verwendung des angegebenen Separators.
 *
 * @param  bool   values[]  - Array mit Ausgangswerten
 * @param  string separator - zu verwendender Separator
 *
 * @return string
 */
string JoinBools(bool values[], string separator) {
   string strings[];

   int size = ArraySize(values);
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      if (values[i]) strings[i] = "true";
      else           strings[i] = "false";
   }

   return(JoinStrings(strings, separator));
}


/**
 * Verbindet die Werte eines Double-Arrays unter Verwendung des angegebenen Separators.
 *
 * @param  double values[]  - Array mit Ausgangswerten
 * @param  string separator - zu verwendender Separator
 *
 * @return string
 */
string JoinDoubles(double values[], string separator) {
   string strings[];

   int size = ArraySize(values);
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = NumberToStr(values[i], ".1+");
   }

   return(JoinStrings(strings, separator));
}


/**
 * Konvertiert ein Double-Array in einen lesbaren String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string DoubleArrayToStr(double values[], string separator=", ") {
   if (ArraySize(values) == 0)
      return("{}");
   if (separator == "0")   // NULL
      separator = ", ";
   return(StringConcatenate("{", JoinDoubles(values, separator), "}"));
}


/**
 * Konvertiert ein Array mit Kursen in einen lesbaren String.
 *
 * @param  double values[]
 * @param  string format    - Zahlenformat entsprechend NumberToStr()
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string PriceArrayToStr(double values[], string format, string separator=", ") {
   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   string strings[];
   ArrayResize(strings, size);

   if (separator == "0")   // NULL
      separator = ", ";

   for (int i=0; i < size; i++) {
      strings[i] = NumberToStr(values[i], format);
   }
   return(StringConcatenate("{", JoinStrings(strings, separator), "}"));
}


/**
 * Konvertiert ein Array mit Geldbetr�gen in einen lesbaren String.
 *
 * @param  double values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string - String bestehend aus Geldbetr�gen mit je 2 Nachkommastellen
 */
string MoneyArrayToStr(double values[], string separator=", ") {
   return(PriceArrayToStr(values, ".2", separator));
}


/**
 * Verbindet die Werte eines Integer-Arrays unter Verwendung des angegebenen Separators.
 *
 * @param  int    values[]  - Array mit Ausgangswerten
 * @param  string separator - zu verwendender Separator
 *
 * @return string
 */
string JoinInts(int values[], string separator) {
   string strings[];

   int size = ArraySize(values);
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = values[i];
   }

   return(JoinStrings(strings, separator));
}


/**
 * Konvertiert ein Integer-Array in einen lesbaren String.
 *
 * @param  int    values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string IntArrayToStr(int values[][], string separator=", ") {
   if (separator == "0")   // NULL
      separator = ", ";

   int dimensions = ArrayDimension(values);

   // ein-dimensionales Array
   if (dimensions == 1) {
      if (ArraySize(values) == 0)
         return("{}");
      return(StringConcatenate("{", JoinInts(values, separator), "}"));
   }

   // zwei-dimensionales Array
   if (dimensions == 2) {
      int size1=ArrayRange(values, 0), size2=ArrayRange(values, 1);
      if (size2 == 0)
         return("{}");

      string strTmp[]; ArrayResize(strTmp, size1);
      int    iTmp[];   ArrayResize(iTmp,   size2);

      for (int i=0; i < size1; i++) {
         for (int z=0; z < size2; z++) {
            iTmp[z] = values[i][z];
         }
         strTmp[i] = IntArrayToStr(iTmp);
      }
      return(StringConcatenate("{", JoinStrings(strTmp, separator), "}"));
   }

   // multi-dimensional
   return("{too many dimensions}");
}


/**
 * Konvertiert ein DateTime-Array in einen lesbaren String.
 *
 * @param  datetime values[]
 * @param  string   separator - Separator (default: ", ")
 *
 * @return string
 */
string DateTimeArrayToStr(int values[], string separator=", ") {
   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = TimeToStr(values[i], TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   }
   return(StringConcatenate("{", JoinStrings(strings, ", "), "}"));
}


/**
 * Konvertiert ein OperationType-Array in einen lesbaren String.
 *
 * @param  int    values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string OperationTypeArrayToStr(int values[], string separator=", ") {
   int size = ArraySize(values);
   if (ArraySize(values) == 0)
      return("{}");

   string strings[];
   ArrayResize(strings, size);

   for (int i=0; i < size; i++) {
      strings[i] = OperationTypeToStr(values[i]);
   }
   return(StringConcatenate("{", JoinStrings(strings, ", "), "}"));
}


/**
 * Verbindet die Werte eines Stringarrays unter Verwendung des angegebenen Separators.
 *
 * @param  string values[]  - Array mit Ausgangswerten
 * @param  string separator - zu verwendender Separator
 *
 * @return string
 */
string JoinStrings(string values[], string separator) {
   string result = "";

   int size = ArraySize(values);

   for (int i=1; i < size; i++) {
      result = StringConcatenate(result, separator, values[i]);
   }
   if (size > 0)
      result = StringConcatenate(values[0], result);

   if (IsError(catch("JoinStrings()")))
      return("");
   return(result);
}


/**
 * Konvertiert ein String-Array in einen lesbaren String.
 *
 * @param  string values[]
 * @param  string separator - Separator (default: ", ")
 *
 * @return string
 */
string StringArrayToStr(string values[], string separator=", ") {
   if (ArraySize(values) == 0)
      return("{}");

   if (separator == "0")   // NULL
      separator = ", ";

   return(StringConcatenate("{\"", JoinStrings(values, StringConcatenate("\"", separator, "\"")), "\"}"));
}


/**
 * Durchsucht ein Integer-Array nach einem Wert und gibt dessen Index zur�ck.
 *
 * @param  int needle     - zu suchender Wert
 * @param  int haystack[] - zu durchsuchendes Array
 *
 * @return int - Index des Wertes oder -1, wenn der Wert nicht im Array enthalten ist
 */
int ArraySearchInt(int needle, int &haystack[]) {
   if (ArrayDimension(haystack) > 1)
      return(_int(-1, catch("ArraySearchInt()   too many dimensions in parameter haystack = "+ ArrayDimension(haystack), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(haystack);

   for (int i=0; i < size; i++) {
      if (haystack[i] == needle)
         return(i);
   }
   return(-1);
}


/**
 * Pr�ft, ob ein Integer in einem Array enthalten ist.
 *
 * @param  int needle     - zu suchender Wert
 * @param  int haystack[] - zu durchsuchendes Array
 *
 * @return bool
 */
bool IntInArray(int needle, int &haystack[]) {
   return(ArraySearchInt(needle, haystack) > -1);
}


/**
 * Durchsucht ein Double-Array nach einem Wert und gibt dessen Index zur�ck.
 *
 * @param  double needle     - zu suchender Wert
 * @param  double haystack[] - zu durchsuchendes Array
 *
 * @return int - Index des Wertes oder -1, wenn der Wert nicht im Array enthalten ist
 */
int ArraySearchDouble(double needle, double &haystack[]) {
   if (ArrayDimension(haystack) > 1)
      return(_int(-1, catch("ArraySearchDouble()   too many dimensions in parameter haystack = "+ ArrayDimension(haystack), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(haystack);

   for (int i=0; i < size; i++) {
      if (EQ(haystack[i], needle))
         return(i);
   }
   return(-1);
}


/**
 * Pr�ft, ob ein Double in einem Array enthalten ist.
 *
 * @param  double needle     - zu suchender Wert
 * @param  double haystack[] - zu durchsuchendes Array
 *
 * @return bool
 */
bool DoubleInArray(double needle, double &haystack[]) {
   return(ArraySearchDouble(needle, haystack) > -1);
}


/**
 * Durchsucht ein String-Array nach einem Wert und gibt dessen Index zur�ck.
 *
 * @param  string needle     - zu suchender Wert
 * @param  string haystack[] - zu durchsuchendes Array
 *
 * @return int - Index des Wertes oder -1, wenn der Wert nicht im Array enthalten ist
 */
int ArraySearchString(string needle, string &haystack[]) {
   if (ArrayDimension(haystack) > 1)
      return(_int(-1, catch("ArraySearchString()   too many dimensions in parameter haystack = "+ ArrayDimension(haystack), ERR_INCOMPATIBLE_ARRAYS)));

   int size = ArraySize(haystack);

   for (int i=0; i < size; i++) {
      if (haystack[i] == needle)
         return(i);
   }
   return(-1);
}


/**
 * Pr�ft, ob ein String in einem Array enthalten ist.
 *
 * @param  string needle     - zu suchender Wert
 * @param  string haystack[] - zu durchsuchendes Array
 *
 * @return bool
 */
bool StringInArray(string needle, string &haystack[]) {
   return(ArraySearchString(needle, haystack) > -1);
}


/**
 *
 *
abstract*/ int onBarOpen(int details[]) {
   return(catch("onBarOpen()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onOrderPlace(int details[]) {
   return(catch("onOrderPlace()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onOrderChange(int details[]) {
   return(catch("onOrderChange()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onOrderCancel(int details[]) {
   return(catch("onOrderCancel()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Handler f�r PositionOpen-Events.
 *
 * @param  int tickets[] - Tickets der neuen Positionen
 *
 * @return int - Fehlerstatus
 *
abstract*/ int onPositionOpen(int tickets[]) {
   return(catch("onPositionOpen()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onPositionClose(int details[]) {
   return(catch("onPositionClose()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onAccountChange(int details[]) {
   return(catch("onAccountChange()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onAccountPayment(int details[]) {
   return(catch("onAccountPayment()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 *
 *
abstract*/ int onHistoryChange(int details[]) {
   return(catch("onHistoryChange()   function not implemented", ERR_FUNCTION_NOT_IMPLEMENTED));
}


/**
 * Entfernt die angegebenen Objekte aus dem aktuellen Chart.
 *
 * @param  string objects[] - Array mit Objektlabels
 *
 * @return int - Fehlerstatus
 */
int RemoveChartObjects(string objects[]) {
   int size = ArraySize(objects);
   if (size == 0)
      return(NO_ERROR);

   for (int i=0; i < size; i++) {
      ObjectDelete(objects[i]);
   }
   ArrayResize(objects, 0);

   int error = GetLastError();
   if (error == ERR_OBJECT_DOES_NOT_EXIST)
      return(NO_ERROR);
   return(catch("RemoveChartObjects()", error));
}


/**
 * Schickt eine SMS an die angegebene Telefonnummer.
 *
 * @param  string receiver - Telefonnummer des Empf�ngers (internationales Format: 49123456789)
 * @param  string message  - Text der SMS
 *
 * @return int - Fehlerstatus
 */
int SendTextMessage(string receiver, string message) {
   if (!StringIsDigit(receiver))
      return(catch("SendTextMessage(1)   invalid parameter receiver: \""+ receiver +"\"", ERR_INVALID_FUNCTION_PARAMVALUE));

   // TODO: Gateway-Zugangsdaten auslagern

   // Befehlszeile f�r Shellaufruf zusammensetzen
   string url          = "https://api.clickatell.com/http/sendmsg?user={user}&password={password}&api_id={id}&to="+ receiver +"&text="+ UrlEncode(message);
   string filesDir     = TerminalPath() +"\\experts\\files";
   string time         = StringReplace(StringReplace(TimeToStr(TimeLocal(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), ".", "-"), ":", ".");
   string responseFile = filesDir +"\\sms_"+ time +"_"+ GetCurrentThreadId() +".response";
   string logFile      = filesDir +"\\sms.log";
   string cmdLine      = "wget.exe -b --no-check-certificate \""+ url +"\" -O \""+ responseFile +"\" -a \""+ logFile +"\"";

   int error = WinExec(cmdLine, SW_HIDE);       // SW_SHOWNORMAL|SW_HIDE
   if (error < 32)
      return(catch("SendTextMessage(1) ->kernel32::WinExec(cmdLine=\""+ cmdLine +"\"), error="+ error +" ("+ ShellExecuteErrorToStr(error) +")", ERR_WIN32_ERROR));

   /**
    * TODO: Pr�fen, ob wget.exe im Pfad gefunden werden kann:  =>  error=2 [File not found]
    *
    *
    * TODO: Fehlerauswertung nach dem Versand
    *
    * --2011-03-23 08:32:06--  https://api.clickatell.com/http/sendmsg?user={user}&password={password}&api_id={id}&to={receiver}&text={text}
    * Resolving api.clickatell.com... failed: Unknown host.
    * wget: unable to resolve host address `api.clickatell.com'
    */

   return(catch("SendTextMessage(2)"));
}


/**
 * Konvertiert die angegebene Tradeserver-Zeit nach FXT (Forex Standard Time).
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - FXT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime ServerToFXT(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("ServerToFXT()  invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(-1);

   // schnelle R�ckkehr, wenn der Tradeserver unter FXT l�uft
   if (zone == "FXT")
      return(serverTime);

   datetime gmtTime = ServerToGMT(serverTime);
   if (gmtTime == -1)
      return(-1);

   return(GMTToFXT(gmtTime));
}


/**
 * Konvertiert die angegebene Tradeserver-Zeit nach GMT.
 *
 * @param  datetime serverTime - Tradeserver-Zeitpunkt
 *
 * @return datetime - GMT-Zeitpunkt oder -1, falls ein Fehler auftrat
 */
datetime ServerToGMT(datetime serverTime) /*throws ERR_INVALID_TIMEZONE_CONFIG*/ {
   if (serverTime < 0)
      return(_int(-1, catch("ServerToGMT(1)   invalid parameter serverTime: "+ serverTime +" (not a time)", ERR_INVALID_FUNCTION_PARAMVALUE)));

   string zone = GetServerTimezone();
   if (StringLen(zone) == 0)
      return(-1);

   // schnelle R�ckkehr, wenn der Tradeserver unter GMT l�uft
   if (zone == "GMT")
      return(serverTime);

   int offset = GetServerToGMTOffset(serverTime);
   if (offset == EMPTY_VALUE)
      return(-1);

   datetime result = serverTime - offset;
   if (result < 0)
      return(_int(-1, catch("ServerToGMT(2)   illegal datetime result: "+ result +" (not a time) for timezone offset of "+ (-offset/MINUTES) +" minutes", ERR_RUNTIME_ERROR)));

   return(result);
}


/**
 * Setzt den Text der Titelbar des angegebenen Fensters (wenn es eine hat). Ist das agegebene Fenster ein Control, wird dessen Text ge�ndert.
 *
 * @param  int    hWnd - Handle des Fensters
 * @param  string text - Text
 *
 * @return int - Fehlerstatus
 */
int SetWindowText(int hWnd, string text) {
   if (!SetWindowTextA(hWnd, text))
      return(catch("SetWindowText() ->user32::SetWindowTextA()   error="+ RtlGetLastWin32Error(), ERR_WIN32_ERROR));

   return(0);
}


/**
 * Pr�ft, ob ein String einen Substring enth�lt.  Gro�-/Kleinschreibung wird beachtet.
 *
 * @param  string object    - zu durchsuchender String
 * @param  string substring - zu suchender Substring
 *
 * @return bool
 */
bool StringContains(string object, string substring) {
   if (StringLen(substring) == 0) {
      catch("StringContains()   empty substring \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(object, substring) != -1);
}


/**
 * Pr�ft, ob ein String einen Substring enth�lt.  Gro�-/Kleinschreibung wird nicht beachtet.
 *
 * @param  string object    - zu durchsuchender String
 * @param  string substring - zu suchender Substring
 *
 * @return bool
 */
bool StringIContains(string object, string substring) {
   if (StringLen(substring) == 0) {
      catch("StringIContains()   empty substring \"\"", ERR_INVALID_FUNCTION_PARAMVALUE);
      return(false);
   }
   return(StringFind(StringToUpper(object), StringToUpper(substring)) != -1);
}


/**
 * Vergleicht zwei Strings ohne Ber�cksichtigung der Gro�-/Kleinschreibung.
 *
 * @param  string string1
 * @param  string string2
 *
 * @return bool
 */
bool StringICompare(string string1, string string2) {
   return(StringToUpper(string1) == StringToUpper(string2));
}


/**
 * Pr�ft, ob ein String nur Ziffern enth�lt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsDigit(string value) {
   int chr, len=StringLen(value);

   if (len == 0)
      return(false);

   for (int i=0; i < len; i++) {
      chr = StringGetChar(value, i);
      if (chr < '0') return(false);
      if (chr > '9') return(false);       // Conditions f�r MQL optimiert
   }

   return(true);
}


/**
 * Pr�ft, ob ein String einen g�ltigen numerischen Wert darstellt (Zeichen 0123456789.-)
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsNumeric(string value) {
   int chr, len=StringLen(value);

   if (len == 0)
      return(false);

   bool period = false;

   for (int i=0; i < len; i++) {
      chr = StringGetChar(value, i);

      if (chr == '-') {
         if (i != 0) return(false);
         continue;
      }
      if (chr == '.') {
         if (period) return(false);
         period = true;
         continue;
      }
      if (chr < '0') return(false);
      if (chr > '9') return(false);       // Conditions f�r MQL optimiert
   }

   return(true);
}


/**
 * Pr�ft, ob ein String einen g�ltigen Integer darstellt.
 *
 * @param  string value - zu pr�fender String
 *
 * @return bool
 */
bool StringIsInteger(string value) {
   return(value == StringConcatenate("", StrToInteger(value)));
}


/**
 * Durchsucht einen String vom Ende aus nach einem Substring und gibt dessen Position zur�ck.
 *
 * @param  string object - zu durchsuchender String
 * @param  string search - zu suchender Substring
 *
 * @return int - letzte Position des Substrings oder -1, wenn der Substring nicht gefunden wurde
 */
int StringFindR(string object, string search) {
   int lenObject = StringLen(object),
       lastFound  = -1,
       result     =  0;

   for (int i=0; i < lenObject; i++) {
      result = StringFind(object, search, i);
      if (result == -1)
         break;
      lastFound = result;
   }

   if (IsError(catch("StringFindR()")))
      return(-1);
   return(lastFound);
}


/**
 * Konvertiert einen String in Kleinschreibweise.
 *
 * @param  string value
 *
 * @return string
 */
string StringToLower(string value) {
   string result = value;
   int char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      char = StringGetChar(value, i);
      //logische Version
      //if      (64 < char && char < 91)              result = StringSetChar(result, i, char+32);
      //else if (char==138 || char==140 || char==142) result = StringSetChar(result, i, char+16);
      //else if (char==159)                           result = StringSetChar(result, i,     255);  // � -> �
      //else if (191 < char && char < 223)            result = StringSetChar(result, i, char+32);

      // f�r MQL optimierte Version
      if      (char == 138)                 result = StringSetChar(result, i, char+16);
      else if (char == 140)                 result = StringSetChar(result, i, char+16);
      else if (char == 142)                 result = StringSetChar(result, i, char+16);
      else if (char == 159)                 result = StringSetChar(result, i,     255);   // � -> �
      else if (char < 91) { if (char >  64) result = StringSetChar(result, i, char+32); }
      else if (191 < char)  if (char < 223) result = StringSetChar(result, i, char+32);
   }

   if (IsError(catch("StringToLower()")))
      return("");
   return(result);
}


/**
 * Konvertiert einen String in Gro�schreibweise.
 *
 * @param  string value
 *
 * @return string
 */
string StringToUpper(string value) {
   string result = value;
   int char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      char = StringGetChar(value, i);
      //logische Version
      //if      (96 < char && char < 123)             result = StringSetChar(result, i, char-32);
      //else if (char==154 || char==156 || char==158) result = StringSetChar(result, i, char-16);
      //else if (char==255)                           result = StringSetChar(result, i,     159);  // � -> �
      //else if (char > 223)                          result = StringSetChar(result, i, char-32);

      // f�r MQL optimierte Version
      if      (char == 255)                 result = StringSetChar(result, i,     159);   // � -> �
      else if (char  > 223)                 result = StringSetChar(result, i, char-32);
      else if (char == 158)                 result = StringSetChar(result, i, char-16);
      else if (char == 156)                 result = StringSetChar(result, i, char-16);
      else if (char == 154)                 result = StringSetChar(result, i, char-16);
      else if (char  >  96) if (char < 123) result = StringSetChar(result, i, char-32);
   }

   if (IsError(catch("StringToUpper()")))
      return("");
   return(result);
}


/**
 * Trimmt einen String beidseitig.
 *
 * @param  string value
 *
 * @return string
 */
string StringTrim(string value) {
   return(StringTrimLeft(StringTrimRight(value)));
}


/**
 * URL-kodiert einen String.  Leerzeichen werden als "+"-Zeichen kodiert.
 *
 * @param  string value
 *
 * @return string - URL-kodierter String
 */
string UrlEncode(string value) {
   string strChar, result="";
   int    char, len=StringLen(value);

   for (int i=0; i < len; i++) {
      strChar = StringSubstr(value, i, 1);
      char    = StringGetChar(strChar, 0);

      if      (47 < char && char <  58) result = StringConcatenate(result, strChar);                  // 0-9
      else if (64 < char && char <  91) result = StringConcatenate(result, strChar);                  // A-Z
      else if (96 < char && char < 123) result = StringConcatenate(result, strChar);                  // a-z
      else if (char == ' ')             result = StringConcatenate(result, "+");
      else                              result = StringConcatenate(result, "%", CharToHexStr(char));
   }

   if (IsError(catch("UrlEncode()")))
      return("");
   return(result);
}


/**
 * Pr�ft, ob der angegebene Name eine existierende und normale Datei ist (kein Verzeichnis).
 *
 * @return string pathName - Pfadangabe
 *
 * @return bool
 */
bool IsFile(string pathName) {
   bool result = false;

   if (StringLen(pathName) > 0) {
      /*WIN32_FIND_DATA*/int wfd[]; InitializeBuffer(wfd, WIN32_FIND_DATA.size);

      int hSearch = FindFirstFileA(pathName, wfd);

      if (hSearch != INVALID_HANDLE_VALUE) {          // TODO: konkreten Fehler pr�fen
         FindClose(hSearch);
         result = !wfd.FileAttribute.Directory(wfd);
      }
   }

   catch("IsFile()");
   return(result);
}


/**
 * Pr�ft, ob der angegebene Name ein existierendes Verzeichnis ist (keine normale Datei).
 *
 * @return string pathName - Pfadangabe
 *
 * @return bool
 */
bool IsDirectory(string pathName) {
   bool result = false;

   if (StringLen(pathName) > 0) {
      /*WIN32_FIND_DATA*/int wfd[]; InitializeBuffer(wfd, WIN32_FIND_DATA.size);

      int hSearch = FindFirstFileA(pathName, wfd);

      if (hSearch != INVALID_HANDLE_VALUE) {
         FindClose(hSearch);
         result = wfd.FileAttribute.Directory(wfd);
      }
   }

   catch("IsDirectory()");
   return(result);
}


/**
 * Konvertiert drei R-G-B-Farbwerte in eine Farbe.
 *
 * @param  int red   - Rotanteil (0-255)
 * @param  int green - Gr�nanteil (0-255)
 * @param  int blue  - Blauanteil (0-255)
 *
 * @return color - Farbe oder -1, wenn ein Fehler auftrat
 *
 * Beispiel: RGB(255, 255, 255) => 0x00FFFFFF (wei�)
 */
color RGB(int red, int green, int blue) {
   if (0 <= red && red <= 255) {
      if (0 <= green && green <= 255) {
         if (0 <= blue && blue <= 255) {
            return(red + green<<8 + blue<<16);
         }
         else catch("RGB(1)  invalid parameter blue: "+ blue, ERR_INVALID_FUNCTION_PARAMVALUE);
      }
      else catch("RGB(2)  invalid parameter green: "+ green, ERR_INVALID_FUNCTION_PARAMVALUE);
   }
   else catch("RGB(3)  invalid parameter red: "+ red, ERR_INVALID_FUNCTION_PARAMVALUE);

   return(-1);
}


/**
 * Konvertiert eine Farbe in ihre HTML-Repr�sentation.
 *
 * @param  color rgb
 *
 * @return string - HTML-Farbwert
 *
 * Beispiel: ColorToHtmlStr(C'255,255,255') => "#FFFFFF"
 */
string ColorToHtmlStr(color rgb) {
   int red   = rgb & 0x0000FF;
   int green = rgb & 0x00FF00;
   int blue  = rgb & 0xFF0000;

   int value = red<<16 + green + blue>>16;   // rot und blau vertauschen, um IntToHexStr() benutzen zu k�nnen

   return(StringConcatenate("#", StringRight(IntToHexStr(value), 6)));
}


/**
 * Konvertiert eine Farbe in ihre RGB-Repr�sentation.
 *
 * @param  color rgb
 *
 * @return string
 *
 * Beispiel: ColorToRGBStr(White) => "255,255,255"
 */
string ColorToRGBStr(color rgb) {
   int red   = rgb       & 0xFF;
   int green = rgb >>  8 & 0xFF;
   int blue  = rgb >> 16 & 0xFF;

   return(StringConcatenate(red, ",", green, ",", blue));
}


/**
 * Konvertiert drei RGB-Farbwerte in den HSV-Farbraum (Hue-Saturation-Value).
 *
 * @param  int    red   - Rotanteil  (0-255)
 * @param  int    green - Gr�nanteil (0-255)
 * @param  int    blue  - Blauanteil (0-255)
 * @param  double hsv[] - Array zur Aufnahme der HSV-Werte
 *
 * @return int - Fehlerstatus
 */
int RGBValuesToHSVColor(int red, int green, int blue, double hsv[]) {
   return(RGBToHSVColor(RGB(red, green, blue), hsv));
}


/**
 * Konvertiert eine RGB-Farbe in den HSV-Farbraum (Hue-Saturation-Value).
 *
 * @param  color  rgb   - Farbe
 * @param  double hsv[] - Array zur Aufnahme der HSV-Werte
 *
 * @return int - Fehlerstatus
 */
int RGBToHSVColor(color rgb, double& hsv[]) {
   int red   = rgb       & 0xFF;
   int green = rgb >>  8 & 0xFF;
   int blue  = rgb >> 16 & 0xFF;

   double r=red/255.0, g=green/255.0, b=blue/255.0;      // scale to unity (0-1)

   double dMin   = MathMin(r, MathMin(g, b)); int iMin   = MathMin(red, MathMin(green, blue));
   double dMax   = MathMax(r, MathMax(g, b)); int iMax   = MathMax(red, MathMax(green, blue));
   double dDelta = dMax - dMin;               int iDelta = iMax - iMin;

   double hue, sat, val=dMax;

   if (iDelta == 0) {
      hue = 0;
      sat = 0;
   }
   else {
      sat = dDelta / dMax;
      double del_R = ((dMax-r)/6 + dDelta/2) / dDelta;
      double del_G = ((dMax-g)/6 + dDelta/2) / dDelta;
      double del_B = ((dMax-b)/6 + dDelta/2) / dDelta;

      if      (red   == iMax) { hue =         del_B - del_G; }
      else if (green == iMax) { hue = 1.0/3 + del_R - del_B; }
      else if (blue  == iMax) { hue = 2.0/3 + del_G - del_R; }

      if      (hue < 0) { hue += 1; }
      else if (hue > 1) { hue -= 1; }
   }

   if (ArraySize(hsv) != 3)
      ArrayResize(hsv, 3);

   hsv[0] = hue * 360;
   hsv[1] = sat;
   hsv[2] = val;

   return(catch("RGBToHSVColor()"));
}


/**
 * Umrechnung einer Farbe aus dem HSV- in den RGB-Farbraum.
 *
 * @param  double hsv - HSV-Farbwerte
 *
 * @return color - Farbe oder -1, wenn ein Fehler auftrat
 */
color HSVToRGBColor(double hsv[3]) {
   if (ArrayDimension(hsv) != 1)
      return(catch("HSVToRGBColor(1)   illegal parameter hsv: "+ DoubleArrayToStr(hsv), ERR_INCOMPATIBLE_ARRAYS));
   if (ArraySize(hsv) != 3)
      return(catch("HSVToRGBColor(2)   illegal parameter hsv: "+ DoubleArrayToStr(hsv), ERR_INCOMPATIBLE_ARRAYS));

   return(HSVValuesToRGBColor(hsv[0], hsv[1], hsv[2]));
}


/**
 * Konvertiert drei HSV-Farbwerte in eine RGB-Farbe.
 *
 * @param  double hue        - Farbton    (0.0 - 360.0)
 * @param  double saturation - S�ttigung  (0.0 - 1.0)
 * @param  double value      - Helligkeit (0.0 - 1.0)
 *
 * @return color - Farbe oder -1, wenn ein Fehler auftrat
 */
color HSVValuesToRGBColor(double hue, double saturation, double value) {
   if (hue < 0.0 || hue > 360.0)             return(_int(-1, catch("HSVValuesToRGBColor(1)  invalid parameter hue: "+ NumberToStr(hue, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (saturation < 0.0 || saturation > 1.0) return(_int(-1, catch("HSVValuesToRGBColor(2)  invalid parameter saturation: "+ NumberToStr(saturation, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));
   if (value < 0.0 || value > 1.0)           return(_int(-1, catch("HSVValuesToRGBColor(3)  invalid parameter value: "+ NumberToStr(value, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));

   double red, green, blue;

   if (EQ(saturation, 0)) {
      red   = value;
      green = value;
      blue  = value;
   }
   else {
      double h  = hue / 60;                           // h = hue / 360 * 6
      int    i  = MathFloor(h);
      double f  = h - i;                              // f(ract) = MathMod(h, 1)
      double d1 = value * (1 - saturation        );
      double d2 = value * (1 - saturation *    f );
      double d3 = value * (1 - saturation * (1-f));

      if      (i == 0) { red = value; green = d3;    blue = d1;    }
      else if (i == 1) { red = d2;    green = value; blue = d1;    }
      else if (i == 2) { red = d1;    green = value; blue = d3;    }
      else if (i == 3) { red = d1;    green = d2;    blue = value; }
      else if (i == 4) { red = d3;    green = d1;    blue = value; }
      else             { red = value; green = d1;    blue = d2;    }
   }

   int r = MathRound(red   * 255);
   int g = MathRound(green * 255);
   int b = MathRound(blue  * 255);

   color rgb = r + g<<8 + b<<16;

   int error = GetLastError();
   if (IsError(error))
      return(_int(-1, catch("HSVValuesToRGBColor(4)", error)));

   return(rgb);
}


/**
 * Modifiziert die HSV-Werte einer Farbe.
 *
 * @param  color  rgb            - zu modifizierende Farbe
 * @param  double mod_hue        - �nderung des Farbtons: +/-360.0�
 * @param  double mod_saturation - �nderung der S�ttigung in %
 * @param  double mod_value      - �nderung der Helligkeit in %
 *
 * @return color - modifizierte Farbe oder -1, wenn ein Fehler auftrat
 *
 * Beispiel:
 * ---------
 *   C'90,128,162' wird um 30% aufgehellt
 *   Color.ModifyHSV(C'90,128,162', NULL, NULL, 30) => C'119,168,212'
 */
color Color.ModifyHSV(color rgb, double mod_hue, double mod_saturation, double mod_value) {
   if (0 <= rgb) {
      if (-360 <= mod_hue && mod_hue <= 360) {
         if (-100 <= mod_saturation) {
            if (-100 <= mod_value) {
               // nach HSV konvertieren
               double hsv[]; RGBToHSVColor(rgb, hsv);

               // Farbton anpassen
               if (NE(mod_hue, 0)) {
                  hsv[0] += mod_hue;
                  if      (hsv[0] <   0) hsv[0] += 360;
                  else if (hsv[0] > 360) hsv[0] -= 360;
               }

               // S�ttigung anpassen
               if (NE(mod_saturation, 0)) {
                  hsv[1] = hsv[1] * (1 + mod_saturation/100);
                  if (hsv[1] > 1)
                     hsv[1] = 1;    // mehr als 100% geht nicht
               }

               // Helligkeit anpassen (modifiziert HSV.value *und* HSV.saturation)
               if (NE(mod_value, 0)) {

                  // TODO: HSV.sat und HSV.val zu gleichen Teilen �ndern

                  hsv[2] = hsv[2] * (1 + mod_value/100);
                  if (hsv[2] > 1)
                     hsv[2] = 1;
               }

               // zur�ck nach RGB konvertieren
               color result = HSVValuesToRGBColor(hsv[0], hsv[1], hsv[2]);

               int error = GetLastError();
               if (IsError(error))
                  return(_int(-1, catch("Color.ModifyHSV(1)", error)));

               return(result);
            }
            else catch("Color.ModifyHSV(2)  invalid parameter mod_value: "+ NumberToStr(mod_value, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE);
         }
         else catch("Color.ModifyHSV(3)  invalid parameter mod_saturation: "+ NumberToStr(mod_saturation, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE);
      }
      else catch("Color.ModifyHSV(4)  invalid parameter mod_hue: "+ NumberToStr(mod_hue, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE);
   }
   else catch("Color.ModifyHSV(5)  invalid parameter rgb: "+ rgb, ERR_INVALID_FUNCTION_PARAMVALUE);

   return(-1);
}


/**
 * Konvertiert einen Double in einen String mit bis zu 16 Nachkommastellen.
 *
 * @param double value  - zu konvertierender Wert
 * @param int    digits - Anzahl von Nachkommastellen
 *
 * @return string
 */
string DoubleToStrEx(double value, int digits) {
   if (digits < 0 || digits > 16)
      return(_empty(catch("DoubleToStrEx()  illegal parameter digits: "+ digits, ERR_INVALID_FUNCTION_PARAMVALUE)));

   /*
   double decimals[17] = { 1.0,     // Der Compiler interpretiert �ber mehrere Zeilen verteilte Array-Initializer
                          10.0,     // als in einer Zeile stehend und gibt bei Fehlern falsche Zeilennummern zur�ck.
                         100.0,
                        1000.0,
                       10000.0,
                      100000.0,
                     1000000.0,
                    10000000.0,
                   100000000.0,
                  1000000000.0,
                 10000000000.0,
                100000000000.0,
               1000000000000.0,
              10000000000000.0,
             100000000000000.0,
            1000000000000000.0,
           10000000000000000.0 };
   */
   double decimals[17] = { 1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0, 100000000.0, 1000000000.0, 10000000000.0, 100000000000.0, 1000000000000.0, 10000000000000.0, 100000000000000.0, 1000000000000000.0, 10000000000000000.0 };

   bool isNegative = false;
   if (value < 0.0) {
      isNegative = true;
      value = -value;
   }

   double integer    = MathFloor(value);
   string strInteger = DoubleToStr(integer +0.1, 0);

   double remainder    = MathRound((value-integer) * decimals[digits]);
   string strRemainder = "";

   for (int i=0; i < digits; i++) {
      double fraction  = MathFloor(remainder/10);
      int    digit     = MathRound(remainder - fraction*10) +0.1;    // (int) double
      strRemainder = digit + strRemainder;
      remainder    = fraction;
   }

   string result = strInteger;

   if (digits > 0)
      result = StringConcatenate(result, ".", strRemainder);

   if (isNegative)
      result = StringConcatenate("-", result);

   return(result);
}


/**
 * MetaQuotes-Alias f�r DoubleToStrEx()
 */
string DoubleToStrMorePrecision(double value, int precision) {
   return(DoubleToStrEx(value, precision));
}


// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! //
//                                                                                    //
// MQL Utility Funktionen                                                             //
//                                                                                    //
// @see http://www.forexfactory.com/showthread.php?p=2695655                          //
//                                                                                    //
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! //


/**
 * Returns a numeric value rounded to the specified number of decimals - works around a precision bug in MQL4.
 *
 * @param  double number
 * @param  int    decimals
 *
 * @return double - rounded value
 */
double MathRoundFix(double number, int decimals) {
   // TODO: Verarbeitung negativer decimals pr�fen

   double operand = MathPow(10, decimals);
   return(MathRound(number*operand + MathSign(number)*0.000000000001) / operand);
}


/**
 * Gibt das Vorzeichen einer Zahl zur�ck.
 *
 * @param  double number - Zahl
 *
 * @return int - Vorzeichen (-1, 0, +1)
 */
int MathSign(double number) {
   if (GT(number, 0)) return( 1);
   if (LT(number, 0)) return(-1);
   return(0);
}


/**
 * Repeats a string.
 *
 * @param  string input - The string to be repeated.
 * @param  int    times - Number of times the input string should be repeated.
 *
 * @return string - the repeated string
 */
string StringRepeat(string input, int times) {
   if (times < 0)
      return(_empty(catch("StringRepeat()  invalid parameter times: "+ times, ERR_INVALID_FUNCTION_PARAMVALUE)));

   if (times ==  0)           return("");
   if (StringLen(input) == 0) return("");

   string output = input;
   for (int i=1; i < times; i++) {
      output = StringConcatenate(output, input);
   }
   return(output);
}


/**
 * Formatiert einen numerischen Wert im angegebenen Format und gibt den resultierenden String zur�ck.
 * The basic mask is "n" or "n.d" where n is the number of digits to the left and d is the number of digits to the right of the decimal point.
 *
 * Mask parameters:
 *
 *   n        = number of digits to the left of the decimal point, e.g. NumberToStr(123.456, "5") => "123"
 *   n.d      = number of left and right digits, e.g. NumberToStr(123.456, "5.2") => "123.45"
 *   n.       = number of left and all right digits, e.g. NumberToStr(123.456, "2.") => "23.456"
 *    .d      = all left and number of right digits, e.g. NumberToStr(123.456, ".2") => "123.45"
 *    .d'     = all left and number of right digits plus 1 additional subpip digit, e.g. NumberToStr(123.45678, ".4'") => "123.4567'8"
 *    .d+     = + anywhere right of .d in mask: all left and minimum number of right digits, e.g. NumberToStr(123.456, ".2+") => "123.456"
 *  +n.d      = + anywhere left of n. in mask: plus sign for positive values
 *    R       = round result in the last displayed digit, e.g. NumberToStr(123.456, "R3.2") => "123.46", e.g. NumberToStr(123.7, "R3") => "124"
 *    ;       = Separatoren tauschen (Europ�isches Format), e.g. NumberToStr(123456.789, "6.2;") => "123456,78"
 *    ,       = Tausender-Separatoren einf�gen, e.g. NumberToStr(123456.789, "6.2,") => "123,456.78"
 *    ,<char> = Tausender-Separatoren einf�gen und auf <char> setzen, e.g. NumberToStr(123456.789, ", 6.2") => "123 456.78"
 *
 * @param  double number
 * @param  string mask
 *
 * @return string - formatierter String
 */
string NumberToStr(double number, string mask) {
   if (number == EMPTY_VALUE)
      number = 0.0;

   // === Beginn Maske parsen ===
   int maskLen = StringLen(mask);

   // zu allererst Separatorenformat erkennen
   bool swapSeparators = (StringFind(mask, ";")  > -1);
      string sepThousand=",", sepDecimal=".";
      if (swapSeparators) {
         sepThousand = ".";
         sepDecimal  = ",";
      }
      int sepPos = StringFind(mask, ",");
   bool separators = (sepPos  > -1);
      if (separators) if (sepPos+1 < maskLen) {
         sepThousand = StringSubstr(mask, sepPos+1, 1);  // user-spezifischen 1000-Separator auslesen und aus Maske l�schen
         mask        = StringConcatenate(StringSubstr(mask, 0, sepPos+1), StringSubstr(mask, sepPos+2));
      }

   // white space entfernen
   mask    = StringReplace(mask, " ", "");
   maskLen = StringLen(mask);

   // Position des Dezimalpunktes
   int  dotPos   = StringFind(mask, ".");
   bool dotGiven = (dotPos > -1);
   if (!dotGiven)
      dotPos = maskLen;

   // Anzahl der linken Stellen
   int char, nLeft;
   bool nDigit;
   for (int i=0; i < dotPos; i++) {
      char = StringGetChar(mask, i);
      if ('0' <= char) if (char <= '9') {    // (0 <= char && char <= 9)
         nLeft = 10*nLeft + char-'0';
         nDigit = true;
      }
   }
   if (!nDigit) nLeft = -1;

   // Anzahl der rechten Stellen
   int nRight, nSubpip;
   if (dotGiven) {
      nDigit = false;
      for (i=dotPos+1; i < maskLen; i++) {
         char = StringGetChar(mask, i);
         if ('0' <= char && char <= '9') {   // (0 <= char && char <= 9)
            nRight = 10*nRight + char-'0';
            nDigit = true;
         }
         else if (nDigit && char==39) {      // 39 => '
            nSubpip = nRight;
            continue;
         }
         else {
            if  (char == '+') nRight = MathMax(nRight+(nSubpip > 0), CountDecimals(number));
            else if (!nDigit) nRight = CountDecimals(number);
            break;
         }
      }
      if (nDigit) {
         if (nSubpip >  0) nRight++;
         if (nSubpip == 8) nSubpip = 0;
         nRight = MathMin(nRight, 8);
      }
   }

   // Vorzeichen
   string leadSign = "";
   if (number < 0) {
      leadSign = "-";
   }
   else if (number > 0) {
      int pos = StringFind(mask, "+");
      if (-1 < pos) if (pos < dotPos)        // (-1 < pos && pos < dotPos)
         leadSign = "+";
   }

   // �brige Modifier
   bool round = (StringFind(mask, "R")  > -1);
   //
   // === Ende Maske parsen ===

   // === Beginn Wertverarbeitung ===
   // runden
   if (round)
      number = MathRoundFix(number, nRight);
   string outStr = number;

   // negatives Vorzeichen entfernen (ist in leadSign gespeichert)
   if (number < 0)
      outStr = StringSubstr(outStr, 1);

   // auf angegebene L�nge k�rzen
   int dLeft = StringFind(outStr, ".");
   if (nLeft == -1) nLeft = dLeft;
   else             nLeft = MathMin(nLeft, dLeft);
   outStr = StringSubstrFix(outStr, StringLen(outStr)-9-nLeft, nLeft+(nRight>0)+nRight);

   // Dezimal-Separator anpassen
   if (swapSeparators)
      outStr = StringSetChar(outStr, nLeft, StringGetChar(sepDecimal, 0));

   // 1000er-Separatoren einf�gen
   if (separators) {
      string out1;
      i = nLeft;
      while (i > 3) {
         out1 = StringSubstrFix(outStr, 0, i-3);
         if (StringGetChar(out1, i-4) == ' ')
            break;
         outStr = StringConcatenate(out1, sepThousand, StringSubstr(outStr, i-3));
         i -= 3;
      }
   }

   // Subpip-Separator einf�gen
   if (nSubpip > 0)
      outStr = StringConcatenate(StringLeft(outStr, nSubpip-nRight), "'", StringRight(outStr, nRight-nSubpip));

   // Vorzeichen etc. anf�gen
   outStr = StringConcatenate(leadSign, outStr);

   //debug("NumberToStr(double="+ DoubleToStr(number, 8) +", mask="+ mask +")    nLeft="+ nLeft +"    dLeft="+ dLeft +"    nRight="+ nRight +"    nSubpip="+ nSubpip +"    outStr=\""+ outStr +"\"");

   if (IsError(catch("NumberToStr()")))
      return("");
   return(outStr);
}


/**
 * TODO: Es werden noch keine Limit- und TakeProfit-Orders unterst�tzt.
 *
 * Drop-in-Ersatz f�r und erweiterte Version von OrderSend(). F�ngt tempor�re Tradeserver-Fehler ab und behandelt sie entsprechend.
 *
 * @param  string   symbol      - Symbol des Instruments          (default: aktuelles Instrument)
 * @param  int      type        - Operation type: [OP_BUY|OP_SELL|OP_BUYLIMIT|OP_SELLLIMIT|OP_BUYSTOP|OP_SELLSTOP]
 * @param  double   lots        - Transaktionsvolumen in Lots
 * @param  double   price       - Preis (nur bei pending Orders)
 * @param  double   slippage    - akzeptable Slippage in Pips     (default: 0          )
 * @param  double   stopLoss    - StopLoss-Level                  (default: -kein-     )
 * @param  double   takeProfit  - TakeProfit-Level                (default: -kein-     )
 * @param  string   comment     - Orderkommentar, max. 27 Zeichen (default: -kein-     )
 * @param  int      magicNumber - MagicNumber                     (default: 0          )
 * @param  datetime expires     - G�ltigkeit der Order            (default: GTC        )
 * @param  color    markerColor - Farbe des Chartmarkers          (default: kein Marker)
 *
 * @return int - Ticket oder -1, falls ein Fehler auftrat
 */
int OrderSendEx(string symbol/*=NULL*/, int type, double lots, double price=0, double slippage=0, double stopLoss=0, double takeProfit=0, string comment="", int magicNumber=0, datetime expires=0, color markerColor=CLR_NONE) {
   // -- Beginn Parametervalidierung --
   // symbol
   if (symbol == "0")      // = NULL
      symbol = Symbol();
   int    digits         = MarketInfo(symbol, MODE_DIGITS);
   double minLot         = MarketInfo(symbol, MODE_MINLOT);
   double maxLot         = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep        = MarketInfo(symbol, MODE_LOTSTEP);

   int    pipDigits      = digits & (~1);
   int    pipPoints      = MathPow(10, digits-pipDigits) +0.1;       // (int) double
   double pip            = 1/MathPow(10, pipDigits), pips=pip;
   int    slippagePoints = MathFloor(slippage * pipPoints) +0.1;     // (int) double
   double stopDistance   = MarketInfo(symbol, MODE_STOPLEVEL)/pipPoints;
   string priceFormat    = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
   int error = GetLastError();
   if (IsError(error))                                         return(_int(-1, catch("OrderSendEx(1)   symbol=\""+ symbol +"\"", error)));
   // type
   if (!IsTradeOperation(type))                                return(_int(-1, catch("OrderSendEx(2)   invalid parameter type: "+ type, ERR_INVALID_FUNCTION_PARAMVALUE)));
   // lots
   if (LT(lots, minLot))                                       return(_int(-1, catch("OrderSendEx(3)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (MinLot="+ NumberToStr(minLot, ".+") +")", ERR_INVALID_TRADE_VOLUME)));
   if (GT(lots, maxLot))                                       return(_int(-1, catch("OrderSendEx(4)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (MaxLot="+ NumberToStr(maxLot, ".+") +")", ERR_INVALID_TRADE_VOLUME)));
   if (NE(MathModFix(lots, lotStep), 0))                       return(_int(-1, catch("OrderSendEx(5)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", ERR_INVALID_TRADE_VOLUME)));
   lots = NormalizeDouble(lots, CountDecimals(lotStep));
   // price
   if (LT(price, 0))                                           return(_int(-1, catch("OrderSendEx(6)   illegal parameter price: "+ NumberToStr(price, priceFormat), ERR_INVALID_FUNCTION_PARAMVALUE)));
   // slippage
   if (LT(slippage, 0))                                        return(_int(-1, catch("OrderSendEx(7)   illegal parameter slippage: "+ NumberToStr(slippage, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE)));
   // stopLoss
   if (LT(stopLoss, 0))                                        return(_int(-1, catch("OrderSendEx(8)   illegal parameter stopLoss: "+ NumberToStr(stopLoss, priceFormat), ERR_INVALID_FUNCTION_PARAMVALUE)));
   stopLoss = NormalizeDouble(stopLoss, digits);
   // takeProfit
   if (NE(takeProfit, 0))                                      return(_int(-1, catch("OrderSendEx(9)   submission of take-profit orders not yet implemented", ERR_FUNCTION_NOT_IMPLEMENTED)));
   takeProfit = NormalizeDouble(takeProfit, digits);
   // comment
   if (comment == "0")     // = NULL
      comment = "";
   else if (StringLen(comment) > 27)                           return(_int(-1, catch("OrderSendEx(10)   illegal parameter comment: \""+ comment +"\" (max. 27 chars)", ERR_INVALID_FUNCTION_PARAMVALUE)));
   // expires
   if (expires != 0) /*&&*/ if (expires <= TimeCurrent())      return(_int(-1, catch("OrderSendEx(11)   illegal parameter expires: "+ ifString(expires < 0, expires, TimeToStr(expires, TIME_DATE|TIME_MINUTES|TIME_SECONDS)), ERR_INVALID_FUNCTION_PARAMVALUE)));
   // markerColor
   if (markerColor < CLR_NONE || markerColor > C'255,255,255') return(_int(-1, catch("OrderSendEx(12)   illegal parameter markerColor: "+ markerColor, ERR_INVALID_FUNCTION_PARAMVALUE)));
   // -- Ende Parametervalidierung --

   int    ticket, time1, time2, firstTime1, requotes;
   double firstPrice;                                                // erster OrderPrice (falls ERR_REQUOTE auftritt)


   // Endlosschleife, bis Order ausgef�hrt wurde oder ein permanenter Fehler auftritt
   while (!IsStopped()) {
      error = NO_ERROR;

      if (IsTradeContextBusy()) {
         log("OrderSendEx()   trade context busy, retrying...");
         Sleep(300);                                                 // 0.3 Sekunden warten
      }
      else {
         // zu verwendenden OpenPrice bestimmen und ggf. StopDistance validieren
         double bid = MarketInfo(symbol, MODE_BID);
         double ask = MarketInfo(symbol, MODE_ASK);
         if      (type == OP_BUY    ) price = ask;
         else if (type == OP_SELL   ) price = bid;
         else if (type == OP_BUYSTOP) {
            if (LT(price - stopDistance*pips, ask)) return(_int(-1, catch("OrderSendEx(13)   "+ OperationTypeDescription(type) +" at "+ NumberToStr(price, priceFormat) +" too close to market ("+ NumberToStr(bid, priceFormat) +"/"+ NumberToStr(ask, priceFormat) +", stop distance="+ NumberToStr(stopDistance, ".+") +" pip)", ERR_INVALID_STOPS)));
         }
         else if (type == OP_SELLSTOP) {
            if (GT(price + stopDistance*pips, bid)) return(_int(-1, catch("OrderSendEx(14)   "+ OperationTypeDescription(type) +" at "+ NumberToStr(price, priceFormat) +" too close to market ("+ NumberToStr(bid, priceFormat) +"/"+ NumberToStr(ask, priceFormat) +", stop distance="+ NumberToStr(stopDistance, ".+") +" pip)", ERR_INVALID_STOPS)));
         }
         price = NormalizeDouble(price, digits);

         if (NE(stopLoss, 0)) {
            if (type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT) {
               if (GE(stopLoss, price))   return(_int(-1, catch("OrderSendEx(15)   illegal stoploss "+ NumberToStr(stopLoss, priceFormat) +" for "+ OperationTypeDescription(type) +" at "+ NumberToStr(price, priceFormat), ERR_INVALID_STOPS)));
            }
            else if (LE(stopLoss, price)) return(_int(-1, catch("OrderSendEx(16)   illegal stoploss "+ NumberToStr(stopLoss, priceFormat) +" for "+ OperationTypeDescription(type) +" at "+ NumberToStr(price, priceFormat), ERR_INVALID_STOPS)));
         }

         time1 = GetTickCount();
         if (firstTime1 == 0) {
            firstTime1 = time1;
            firstPrice = price;                                      // OrderPrice und Zeit der ersten Ausf�hrung merken
         }

         ticket = OrderSend(symbol, type, lots, price, slippagePoints, stopLoss, takeProfit, comment, magicNumber, expires, markerColor);
         time2  = GetTickCount();

         if (ticket > 0) {
            OrderPush("OrderSendEx(17)");
            WaitForTicket(ticket, false);
            log("OrderSendEx()   opened "+ OrderSendEx.LogMessage(ticket, type, lots, firstPrice, digits, time2-firstTime1, requotes));

            if (!IsTesting())
               PlaySound(ifString(requotes==0, "OrderOk.wav", "Blip.wav"));
            else if (!ChartMarkers.OrderCreated(ticket, digits, markerColor))
               return(_int(-1, OrderPop("OrderSendEx(18)")));

            if (IsError(catch("OrderSendEx(19)", NULL, O_POP)))
               return(-1);
            return(ticket);                                          // regular exit
         }
         error = GetLastError();

         if (error == ERR_REQUOTE) {
            if (IsTesting())
               catch("OrderSendEx(20)", error);
            requotes++;
            continue;                                                // nach ERR_REQUOTE Order schnellstm�glich wiederholen
         }
         if (IsNoError(error))
            error = ERR_RUNTIME_ERROR;
         if (!IsTemporaryTradeError(error))                          // TODO: ERR_MARKET_CLOSED abfangen und besser behandeln
            break;

         string message = StringConcatenate(Symbol(), ",", PeriodDescription(NULL), "  ", __SCRIPT__, "::OrderSendEx()   temporary trade error ", ErrorToStr(error), " after ", DoubleToStr((time2-firstTime1)/1000.0, 3), " s", ifString(requotes==0, "", StringConcatenate(" and ", requotes, " requote", ifString(requotes==1, "", "s"))), ", retrying...");
         Alert(message);                                             // nach Fertigstellung durch log() ersetzen
         if (IsTesting()) {
            ForceSound("alert.wav");
            ForceMessageBox(message, __SCRIPT__, MB_ICONERROR|MB_OK);
         }
      }
   }

   return(_int(-1, catch("OrderSendEx(21)   permanent trade error after "+ DoubleToStr((time2-firstTime1)/1000.0, 3) +" s"+ ifString(requotes==0, "", " and "+ requotes +" requote"+ ifString(requotes==1, "", "s")), error)));
}


/**
 * Generiert eine ausf�hrliche Logmessage f�r eine erfolgreich abgeschickte oder ausgef�hrte Order.
 *
 * @param  int    ticket   - Ticket-Nummer der Order
 * @param  int    type     - gew�nschter Ordertyp
 * @param  double lots     - gew�nschtes Ordervolumen
 * @param  double price    - gew�nschter Orderpreis
 * @param  int    digits   - Nachkommastellen des Ordersymbols
 * @param  int    time     - zur Orderausf�hrung ben�tigte Zeit
 * @param  int    requotes - Anzahl der aufgetretenen Requotes
 *
 * @return string - Logmessage
 */
/*private*/ string OrderSendEx.LogMessage(int ticket, int type, double lots, double price, int digits, int time, int requotes) {
   int    pipDigits   = digits & (~1);
   double pip         = 1/MathPow(10, pipDigits);
   string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));

   if (!OrderSelectByTicket(ticket, "OrderSendEx.LogMessage(1)"))
      return("");

   string strType = OperationTypeDescription(OrderType());
   if (type != OrderType())
      strType = StringConcatenate(strType, " (instead of ", OperationTypeDescription(type), ")");

   string strLots = NumberToStr(OrderLots(), ".+");
   if (NE(lots, OrderLots()))
      strLots = StringConcatenate(strLots, " (instead of ", NumberToStr(lots, ".+"), ")");

   string strPrice    = NumberToStr(OrderOpenPrice(), priceFormat);
   string strSlippage = "";
   if (type == OrderType()) {
      if (NE(price, OrderOpenPrice())) {
         strPrice = StringConcatenate(strPrice, " (instead of ", NumberToStr(price, priceFormat), ")");
         if (OrderType()==OP_BUY || OrderType()==OP_SELL) {
            strSlippage = NumberToStr(MathAbs(OrderOpenPrice()-price)/pip, ".+");
            int plus    = GT(OrderOpenPrice(), price);
            if (OrderType() == plus^1) strSlippage = StringConcatenate(" (", strSlippage, " pip slippage)");
            else                       strSlippage = StringConcatenate(" (", strSlippage, " pip positive slippage)");
         }
      }
   }

   string message = StringConcatenate("#", ticket, " ", strType, " ", strLots, " ", OrderSymbol(), " at ", strPrice);
   if (NE(OrderStopLoss(), 0))        message = StringConcatenate(message, ", sl=", NumberToStr(OrderStopLoss(), priceFormat));
   if (StringLen(OrderComment()) > 0) message = StringConcatenate(message, ", comment=\"", OrderComment(), "\"");
                                      message = StringConcatenate(message, " after ", DoubleToStr(time/1000.0, 3), " s");
   if (requotes > 0) {
      message = StringConcatenate(message, " and ", requotes, " requote");
      if (requotes > 1)
         message = StringConcatenate(message, "s");
   }

   message = StringConcatenate(message, strSlippage);

   int error = GetLastError();
   if (IsError(error))
      return(_empty(catch("OrderSendEx.LogMessage(2)", error)));
   return(message);
}


/**
 * Korrigiert die vom Terminal beim Abschicken einer Order erzeugten Chart-Marker.
 *
 * @param  int   ticket      - Ticket
 * @param  int   digits      - Nachkommastellen des Ordersymbols
 * @param  color markerColor - Farbe des Chartmarkers
 *
 * @return bool - Erfolgsstatus
 */
/*private*/ bool ChartMarkers.OrderCreated(int ticket, int digits, color markerColor) {
   if (!IsTesting())    return(true);
   if (!IsVisualMode()) return(true);

   if (!OrderSelectByTicket(ticket, "ChartMarkers.OrderCreated(1)"))
      return(false);

   static string types[] = {"buy","sell","buy limit","sell limit","buy stop","sell stop"};

   // OrderOpen-Marker nur ggf. l�schen                              // "#1 buy stop 0.10 GBPUSD at 1.52904"
   string label1 = StringConcatenate("#", ticket, " ", types[OrderType()], " ", DoubleToStr(OrderLots(), 2), " ", OrderSymbol(), " at ", DoubleToStr(OrderOpenPrice(), digits));
   if (markerColor == CLR_NONE) {
      if (ObjectFind(label1)==0) /*&&*/ if (ObjectType(label1)==OBJ_ARROW)
         ObjectDelete(label1);
   }

   // StopLoss-Marker immer l�schen                                  // "#1 buy stop 0.10 GBPUSD at 1.52904 stop loss at 1.52784"
   if (NE(OrderStopLoss(), 0)) {
      string label2 = StringConcatenate(label1, " stop loss at ", DoubleToStr(OrderStopLoss(), digits));
      if (ObjectFind(label2)==0) /*&&*/ if (ObjectType(label2)==OBJ_ARROW)
         ObjectDelete(label2);
   }

   // TakeProfit-Marker immer l�schen                                // "#1 buy stop 0.10 GBPUSD at 1.52904 take profit at 1.58000"
   if (NE(OrderTakeProfit(), 0)) {
      string label3 = StringConcatenate(label1, " take profit at ", DoubleToStr(OrderTakeProfit(), digits));
      if (ObjectFind(label3)==0) /*&&*/ if (ObjectType(label3)==OBJ_ARROW)
         ObjectDelete(label3);
   }

   return(IsNoError(catch("ChartMarkers.OrderCreated(2)")));
}


/**
 * Korrigiert die vom Terminal beim Ausf�hren einer "pending" Order erzeugten Chart-Marker.
 *
 * @param  int    ticket       - Ticket
 * @param  int    pendingType  - Ordertyp der "pending" Order
 * @param  double pendingPrice - Preis der "pending" Order
 * @param  int    digits       - Nachkommastellen des Ordersymbols
 * @param  color  markerColor  - Farbe des Chartmarkers
 *
 * @return bool - Erfolgsstatus
 */
bool ChartMarkers.OrderFilled(int ticket, int pendingType, double pendingPrice, int digits, color markerColor) {
   if (!IsTesting())            return(true);
   if (!IsVisualMode())         return(true);

   if (!OrderSelectByTicket(ticket, "ChartMarkers.OrderFilled(1)", O_PUSH))
      return(false);

   static string types[] = {"buy","sell","buy limit","sell limit","buy stop","sell stop"};

   // OrderOpen-Marker immer l�schen                                 // "#1 buy stop 0.10 GBPUSD at 1.52904"
   string label1 = StringConcatenate("#", ticket, " ", types[pendingType], " ", DoubleToStr(OrderLots(), 2), " ", OrderSymbol(), " at ", DoubleToStr(pendingPrice, digits));
   if (ObjectFind(label1)==0) /*&&*/ if (ObjectType(label1)==OBJ_ARROW)
      ObjectDelete(label1);

   // Trendline immer l�schen                                        // "#1 1.52904 -> 1.52904"
   string label2 = StringConcatenate("#", ticket, " ", DoubleToStr(pendingPrice, digits), " -> ", DoubleToStr(OrderOpenPrice(), digits));
   if (ObjectFind(label2)==0) /*&&*/ if (ObjectType(label2)==OBJ_TREND)
      ObjectDelete(label2);

   // OrderFill-Marker l�schen oder korrigieren                      // "#1 buy stop 0.10 GBPUSD at 1.52904 buy by tester at 1.52904"
   string label3 = StringConcatenate(label1, " ", types[OrderType()], " by tester at ", DoubleToStr(OrderOpenPrice(), digits));
   if (ObjectFind(label3)==0) /*&&*/ if (ObjectType(label3)==OBJ_ARROW) {
      if (markerColor == CLR_NONE) ObjectDelete(label3);
      else                         ObjectSet(label3, OBJPROP_COLOR, markerColor);
   }

   return(IsNoError(catch("ChartMarkers.OrderFilled(2)", NULL, O_POP)));
}


/**
 * Korrigiert die vom Terminal beim L�schen einer Order erzeugten Chart-Marker.
 *
 * @param  int   ticket      - Ticket
 * @param  int   digits      - Nachkommastellen des Ordersymbols
 * @param  color markerColor - Farbe des Chartmarkers
 *
 * @return bool - Erfolgsstatus
 */
/*private*/ bool ChartMarkers.OrderDeleted(int ticket, int digits, color markerColor) {
   if (!IsTesting())            return(true);
   if (!IsVisualMode())         return(true);

   if (!OrderSelectByTicket(ticket, "ChartMarkers.OrderDeleted(1)"))
      return(false);

   static string types[] = {"buy","sell","buy limit","sell limit","buy stop","sell stop"};

   // OrderOpen-Marker ggf. l�schen                                  // "#1 buy stop 0.10 GBPUSD at 1.52904"
   string label1 = StringConcatenate("#", ticket, " ", types[OrderType()], " ", DoubleToStr(OrderLots(), 2), " ", OrderSymbol(), " at ", DoubleToStr(OrderOpenPrice(), digits));
   if (markerColor == CLR_NONE) {
      if (ObjectFind(label1)==0) /*&&*/ if (ObjectType(label1)==OBJ_ARROW)
         ObjectDelete(label1);
   }

   // Trendline ggf. l�schen                                         // "#1 delete"
   string label2 = StringConcatenate("#", ticket, " delete");
   if (markerColor == CLR_NONE) {
      if (ObjectFind(label2)==0) /*&&*/ if (ObjectType(label2)==OBJ_TREND)
         ObjectDelete(label2);
   }

   // OrderClose-Marker l�schen oder korrigieren                     // "#1 buy stop 0.10 GBPUSD at 1.52904 deleted"
   string label3 = StringConcatenate(label1, " deleted");
   if (ObjectFind(label3)==0) /*&&*/ if (ObjectType(label3)==OBJ_ARROW) {
      if (markerColor == CLR_NONE) ObjectDelete(label3);
      else                         ObjectSet(label3, OBJPROP_COLOR, markerColor);
   }

   return(IsNoError(catch("ChartMarkers.OrderDeleted(2)")));
}


/**
 * Drop-in-Ersatz f�r und erweiterte Version von OrderClose(). F�ngt tempor�re Tradeserver-Fehler ab und behandelt sie entsprechend.
 *
 * @param  int    ticket      - Ticket-Nr. der zu schlie�enden Position
 * @param  double lots        - zu schlie�endes Volumen in Lots         (default: komplette Position)
 * @param  double price       - Preis                                   (wird ignoriert             )
 * @param  double slippage    - akzeptable Slippage in Pips             (default: 0                 )
 * @param  color  markerColor - Farbe des Chart-Markers                 (default: kein Marker       )
 *
 * @return bool - Erfolgsstatus
 */
bool OrderCloseEx(int ticket, double lots=0, double price=0, double slippage=0, color markerColor=CLR_NONE) {
   // -- Beginn Parametervalidierung --
   // ticket
   if (!OrderSelectByTicket(ticket, "OrderCloseEx(1)", O_PUSH)) return(false);
   if (OrderCloseTime() != 0)                                    return(_false(catch("OrderCloseEx(2)   ticket #"+ ticket +" is already closed", ERR_INVALID_TICKET, O_POP)));
   if (OrderType() > OP_SELL)                                    return(_false(catch("OrderCloseEx(3)   ticket #"+ ticket +" is not an open position", ERR_INVALID_TICKET, O_POP)));
   // lots
   int    digits  = MarketInfo(OrderSymbol(), MODE_DIGITS);
   double minLot  = MarketInfo(OrderSymbol(), MODE_MINLOT);
   double lotStep = MarketInfo(OrderSymbol(), MODE_LOTSTEP);
   int error = GetLastError();
   if (IsError(error))                                           return(_false(catch("OrderCloseEx(4)   symbol=\""+ OrderSymbol() +"\"", error, O_POP)));
   if (EQ(lots, 0)) {
      lots = OrderLots();
   }
   else if (NE(lots, OrderLots())) {
      if (LT(lots, minLot))                                      return(_false(catch("OrderCloseEx(5)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (MinLot="+ NumberToStr(minLot, ".+") +")", ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
      if (GT(lots, OrderLots()))                                 return(_false(catch("OrderCloseEx(6)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (OpenLots="+ NumberToStr(OrderLots(), ".+") +")", ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
      if (NE(MathModFix(lots, lotStep), 0))                      return(_false(catch("OrderCloseEx(7)   illegal parameter lots: "+ NumberToStr(lots, ".+") +" (LotStep="+ NumberToStr(lotStep, ".+") +")", ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   }
   lots = NormalizeDouble(lots, CountDecimals(lotStep));
   // price
   if (LT(price, 0))                                             return(_false(catch("OrderCloseEx(8)   illegal parameter price: "+ NumberToStr(price, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // slippage
   if (LT(slippage, 0))                                          return(_false(catch("OrderCloseEx(9)   illegal parameter slippage: "+ NumberToStr(slippage, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // markerColor
   if (markerColor < CLR_NONE || markerColor > C'255,255,255')   return(_false(catch("OrderCloseEx(10)   illegal parameter markerColor: "+ markerColor, ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // -- Ende Parametervalidierung --

   int    pipDigits      = digits & (~1);
   int    pipPoints      = MathPow(10, digits-pipDigits) +0.1;       // (int) double
   string priceFormat    = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
   int    slippagePoints = MathFloor(slippage * pipPoints) +0.1;     // (int) double

   int    time1, time2, firstTime1, requotes;
   double firstPrice;                                                // erster OrderPrice (falls ERR_REQUOTE auftritt)
   bool   success;


   // Endlosschleife, bis Position geschlossen wurde oder ein permanenter Fehler auftritt
   while (!IsStopped()) {
      error = NO_ERROR;

      if (IsTradeContextBusy()) {
         log("OrderCloseEx()   trade context busy, retrying...");
         Sleep(300);                                                 // 0.3 Sekunden warten
      }
      else {
         if      (OrderType() == OP_BUY ) price = MarketInfo(OrderSymbol(), MODE_BID);
         else if (OrderType() == OP_SELL) price = MarketInfo(OrderSymbol(), MODE_ASK);
         price = NormalizeDouble(price, digits);

         time1 = GetTickCount();
         if (firstTime1 == 0) {
            firstTime1 = time1;
            firstPrice = price;                                      // OrderPrice und Zeit der ersten Ausf�hrung merken
         }
         success = OrderClose(ticket, lots, price, slippagePoints, markerColor);
         time2   = GetTickCount();

         if (success) {
            WaitForTicket(ticket, false);                            // TODO: bei partiellem Close auf das resultierende Ticket warten

            // Logmessage generieren
            log("OrderCloseEx()   "+ OrderCloseEx.LogMessage(ticket, lots, firstPrice, digits, time2-firstTime1, requotes));
            if (!IsTesting())
               PlaySound(ifString(requotes==0, "OrderOk.wav", "Blip.wav"));

            return(IsNoError(catch("OrderCloseEx(11)", NULL, O_POP)));                                  // regular exit
         }
         error = GetLastError();
         if (error == ERR_REQUOTE) {
            if (IsTesting()) catch("OrderCloseEx(12)", error);
            requotes++;
            continue;                                                // nach ERR_REQUOTE Order schnellstm�glich wiederholen
         }
         if (error == NO_ERROR)
            error = ERR_RUNTIME_ERROR;
         if (!IsTemporaryTradeError(error))                          // TODO: ERR_MARKET_CLOSED abfangen und besser behandeln
            break;

         string message = StringConcatenate(Symbol(), ",", PeriodDescription(NULL), "  ", __SCRIPT__, "::OrderCloseEx()   temporary trade error ", ErrorToStr(error), " after ", DoubleToStr((time2-firstTime1)/1000.0, 3), " s", ifString(requotes==0, "", StringConcatenate(" and ", requotes, " requote", ifString(requotes==1, "", "s"))), ", retrying...");
         Alert(message);                                             // nach Fertigstellung durch log() ersetzen
         if (IsTesting()) {
            ForceSound("alert.wav");
            ForceMessageBox(message, __SCRIPT__, MB_ICONERROR|MB_OK);
         }
      }
   }
   return(_false(catch("OrderCloseEx(13)   permanent trade error after "+ DoubleToStr((time2-firstTime1)/1000.0, 3) +" s"+ ifString(requotes==0, "", " and "+ requotes +" requote"+ ifString(requotes==1, "", "s")), error, O_POP)));
}


/**
 *
 */
/*private*/ string OrderCloseEx.LogMessage(int ticket, double lots, double price, int digits, int time, int requotes) {
   int    pipDigits   = digits & (~1);
   double pip         = 1/MathPow(10, pipDigits);
   string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));

   // TODO: Logmessage bei partiellem Close anpassen (geschlossenes Volumen, verbleibendes Ticket#)

   if (!OrderSelectByTicket(ticket, "OrderCloseEx.LogMessage(1)"))
      return("");

   string strType = OperationTypeDescription(OrderType());
   string strLots = NumberToStr(OrderLots(), ".+");

   string strPrice    = NumberToStr(OrderClosePrice(), priceFormat);
   string strSlippage = "";
   if (NE(price, OrderClosePrice())) {
      strPrice    = StringConcatenate(strPrice, " (instead of ", NumberToStr(price, priceFormat), ")");
      strSlippage = NumberToStr(MathAbs(OrderClosePrice()-price)/pip, ".+");
      int plus    = GT(OrderClosePrice(), price);
      if ((OrderType() == plus)) strSlippage = StringConcatenate(" (", strSlippage, " pip slippage)");
      else                       strSlippage = StringConcatenate(" (", strSlippage, " pip positive slippage)");
   }

   string message = StringConcatenate("closed #", ticket, " ", strType, " ", strLots, " ", OrderSymbol(), " at ", strPrice, " after ", DoubleToStr(time/1000.0, 3), " s");

   if (requotes > 0) {
      message = StringConcatenate(message, " and ", requotes, " requote");
      if (requotes > 1)
         message = StringConcatenate(message, "s");
   }

   message = StringConcatenate(message, strSlippage);

   int error = GetLastError();
   if (IsError(error))
      return(_empty(catch("OrderCloseEx.LogMessage(2)", error)));
   return(message);
}


/**
 * Drop-in-Ersatz f�r und erweiterte Version von OrderCloseBy(). F�ngt tempor�re Tradeserver-Fehler ab, behandelt sie entsprechend und
 * gibt ggf. die Ticket-Nr. einer resultierenden Restposition zur�ck.
 *
 * @param  int   ticket      - Ticket-Nr. der zu schlie�enden Position
 * @param  int   opposite    - Ticket-Nr. der entgegengesetzten zu schlie�enden Position
 * @param  int   remainder[] - Array zur Aufnahme der Ticket-Nr. einer resultierenden Restposition (wenn zutreffend)
 * @param  color markerColor - Farbe des Chart-Markers (default: kein Marker)
 *
 * @return bool - Erfolgsstatus
 */
bool OrderCloseByEx(int ticket, int opposite, int& remainder[], color markerColor=CLR_NONE) {
   // -- Beginn Parametervalidierung --
   // ticket
   if (!OrderSelectByTicket(ticket, "OrderCloseByEx(1)", O_PUSH)) return(false);
   if (OrderCloseTime() != 0)                                      return(_false(catch("OrderCloseByEx(2)   ticket #"+ ticket +" is already closed", ERR_INVALID_TICKET, O_POP)));
   if (OrderType() > OP_SELL)                                      return(_false(catch("OrderCloseByEx(3)   ticket #"+ ticket +" is not an open position", ERR_INVALID_TICKET, O_POP)));
   int    ticketType     = OrderType();
   double ticketLots     = OrderLots();
   string symbol         = OrderSymbol();
   string ticketOpenTime = OrderOpenTime();
   // opposite
   if (!OrderSelectByTicket(opposite, "OrderCloseByEx(4)"))        return(_false(OrderPop("OrderCloseByEx(4)")));
   if (OrderCloseTime() != 0)                                      return(_false(catch("OrderCloseByEx(5)   opposite ticket #"+ opposite +" is already closed", ERR_INVALID_TICKET, O_POP)));
   int    oppositeType     = OrderType();
   double oppositeLots     = OrderLots();
   string oppositeOpenTime = OrderOpenTime();
   if (ticket == opposite)                                         return(_false(catch("OrderCloseByEx(6)   ticket #"+ opposite +" is not an opposite ticket to ticket #"+ ticket, ERR_INVALID_TICKET, O_POP)));
   if (ticketType != oppositeType ^ 1)                             return(_false(catch("OrderCloseByEx(7)   ticket #"+ opposite +" is not an opposite ticket to ticket #"+ ticket, ERR_INVALID_TICKET, O_POP)));
   if (symbol != OrderSymbol())                                    return(_false(catch("OrderCloseByEx(8)   ticket #"+ opposite +" is not an opposite ticket to ticket #"+ ticket, ERR_INVALID_TICKET, O_POP)));
   // markerColor
   if (markerColor < CLR_NONE || markerColor > C'255,255,255')     return(_false(catch("OrderCloseByEx(9)   illegal parameter markerColor: "+ markerColor, ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // -- Ende Parametervalidierung --

   // Tradereihenfolge analysieren und hedgende Order definieren
   int    first, hedge, firstType, hedgeType, smaller, larger;
   double firstLots, hedgeLots;
   if (ticketOpenTime < oppositeOpenTime || (ticketOpenTime==oppositeOpenTime && ticket < opposite)) {
      first = ticket;   firstType = ticketType;   firstLots = ticketLots;
      hedge = opposite; hedgeType = oppositeType; hedgeLots = oppositeLots;
   }
   else {
      first = opposite; firstType = oppositeType; firstLots = oppositeLots;
      hedge = ticket;   hedgeType = ticketType;   hedgeLots = ticketLots;
   }
   if (LE(firstLots, hedgeLots)) { smaller = first; larger = hedge; }      // Nur wenn #smaller by #larger geschlossen wird, wird im Kommentar von #remainder auf #smaller
   else                          { smaller = hedge; larger = first; }      // verwiesen. Anderenfalls existiert sp�ter in #remainder keine Referenz auf das Ausgangsticket.

   // Endlosschleife, bis Positionen geschlossen wurden oder ein permanenter Fehler auftritt
   while (!IsStopped()) {
      if (IsTradeContextBusy()) {
         log("OrderCloseByEx()   trade context busy, retrying...");
      }
      else {
         log(StringConcatenate("OrderCloseByEx()   closing #", first, " (", OperationTypeDescription(firstType), " ", NumberToStr(firstLots, ".+"), " ", symbol, ") by #", hedge, " (", OperationTypeDescription(hedgeType), " ", NumberToStr(hedgeLots, ".+"), " ", symbol, ")"));
         int time2, time1=GetTickCount();

         if (OrderCloseBy(smaller, larger, markerColor)) {
            WaitForTicket(smaller, false);
            WaitForTicket(larger, false);

            time2 = GetTickCount();
            ArrayResize(remainder, 0);
            string strRemainder = ": none";

            if (NE(firstLots, hedgeLots)) {
               // Restposition suchen und in remainder speichern
               string comment = StringConcatenate("from #", smaller);
               if (IsTesting())
                  comment = StringConcatenate("split ", comment);

               for (int i=OrdersTotal()-1; i >= 0; i--) {
                  if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))         // FALSE: w�hrend des Auslesens wurde in einem anderen Thread eine offene Order entfernt
                     continue;
                  if (OrderComment() == comment) {
                     ArrayResize(remainder, 1);
                     remainder[0] = OrderTicket();
                     break;
                  }
               }
               if (ArraySize(remainder) == 0)
                  return(_false(catch("OrderCloseByEx(10)   remainding position of close #"+ first +" ("+ NumberToStr(firstLots, ".+") +" lots) by #"+ hedge +" ("+ NumberToStr(hedgeLots, ".+") +" lots) not found", ERR_RUNTIME_ERROR, O_POP)));
               strRemainder = StringConcatenate(" #", remainder[0]);
            }
            log(StringConcatenate("OrderCloseByEx()   closed #", first, " by #", hedge, ", remainder", strRemainder, " after ", DoubleToStr((time2-time1)/1000.0, 3), " s"));
            if (!IsTesting()) PlaySound("OrderOk.wav");

            return(IsNoError(catch("OrderCloseByEx(11)", NULL, O_POP)));  // regular exit
         }
         time2     = GetTickCount();
         int error = GetLastError();
         if (IsNoError(error))
            error = ERR_RUNTIME_ERROR;
         if (!IsTemporaryTradeError(error))                                // TODO: ERR_MARKET_CLOSED abfangen und besser behandeln
            break;
                                                                           // Alert() nach Fertigstellung durch log() ersetzen
         ForceAlert(Symbol(), ",", PeriodDescription(NULL), "  ", __SCRIPT__, "::OrderCloseByEx()   temporary trade error ", ErrorToStr(error), " after ", DoubleToStr((time2-time1)/1000.0, 3), " s, retrying...");
      }
      error = NO_ERROR;
      Sleep(300);                                                          // 0.3 Sekunden warten
   }

   return(_false(catch("OrderCloseByEx(12)   permanent trade error after "+ DoubleToStr((time2-time1)/1000.0, 3) +" s", error, O_POP)));
}


/**
 * Schlie�t mehrere offene Positionen auf die effektivste Art und Weise. Mehrere offene Positionen im selben Instrument werden zuerst flat gestellt (ggf. mit Hedgeposition),
 * die Berechnung doppelter Spreads wird dadurch verhindert.
 *
 * @param  int    tickets[]   - Ticket-Nr. der zu schlie�enden Positionen
 * @param  double slippage    - zu akzeptierende Slippage in Pip (default:           0)
 * @param  color  markerColor - Farbe des Chart-Markers          (default: kein Marker)
 *
 * @return bool - Erfolgsstatus: FALSE, wenn mindestens eines der Tickets nicht geschlossen werden konnte
 */
bool OrderMultiClose(int tickets[], double slippage=0, color markerColor=CLR_NONE) {
   // (1) Beginn Parametervalidierung --
   // tickets
   int sizeOfTickets = ArraySize(tickets);
   if (sizeOfTickets == 0)                                     return(_false(catch("OrderMultiClose(1)   invalid size of parameter tickets = "+ IntArrayToStr(tickets), ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));

   OrderPush("OrderMultiClose(2)");
   for (int i=0; i < sizeOfTickets; i++) {
      if (!OrderSelectByTicket(tickets[i], "OrderMultiClose(3)", NULL, O_POP))
         return(false);
      if (OrderCloseTime() != 0)                               return(_false(catch("OrderMultiClose(3)   ticket #"+ tickets[i] +" is already closed", ERR_INVALID_TICKET, O_POP)));
      if (OrderType() > OP_SELL)                               return(_false(catch("OrderMultiClose(4)   ticket #"+ tickets[i] +" is not an open position", ERR_INVALID_TICKET, O_POP)));
   }
   // slippage
   if (LT(slippage, 0))                                        return(_false(catch("OrderMultiClose(5)   illegal parameter slippage: "+ NumberToStr(slippage, ".+"), ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // markerColor
   if (markerColor < CLR_NONE || markerColor > C'255,255,255') return(_false(catch("OrderMultiClose(6)   illegal parameter markerColor: "+ markerColor, ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // -- Ende Parametervalidierung --


   // (2) schnelles Close, wenn nur ein einziges Ticket angegeben wurde
   if (sizeOfTickets == 1)
      return(OrderCloseEx(tickets[0], NULL, NULL, slippage, markerColor) && OrderPop("OrderMultiClose(7)"));


   // Das Array tickets[] wird in der Folge modifiziert. Um �nderungen am �bergebenen Ausgangsarray zu verhindern, arbeiten wir auf einer Kopie.
   int ticketsCopy[]; ArrayResize(ticketsCopy, 0);
   ArrayCopy(ticketsCopy, tickets);


   // (3) Zuordnung der Tickets zu Symbolen ermitteln
   string symbols      []; ArrayResize(symbols, 0);
   int    ticketSymbols[]; ArrayResize(ticketSymbols, sizeOfTickets);

   for (i=0; i < sizeOfTickets; i++) {
      if (!OrderSelectByTicket(ticketsCopy[i], "OrderMultiClose(8)", NULL, O_POP))
         return(false);
      int symbolIndex = ArraySearchString(OrderSymbol(), symbols);
      if (symbolIndex == -1)
         symbolIndex = ArrayPushString(symbols, OrderSymbol())-1;
      ticketSymbols[i] = symbolIndex;
   }


   // (4) Geh�ren die Tickets zu mehreren Symbolen, Tickets jeweils eines Symbols auslesen und per Symbol schlie�en.
   int sizeOfSymbols = ArraySize(symbols);

   if (sizeOfSymbols > 1) {
      int hedgedSymbolIndices[]; ArrayResize(hedgedSymbolIndices, 0);

      for (symbolIndex=0; symbolIndex < sizeOfSymbols; symbolIndex++) {
         int perSymbolTickets[]; ArrayResize(perSymbolTickets, 0);
         for (i=0; i < sizeOfTickets; i++) {
            if (symbolIndex == ticketSymbols[i])
               ArrayPushInt(perSymbolTickets, ticketsCopy[i]);
         }
         int sizeOfPerSymbolTickets = ArraySize(perSymbolTickets);
         if (sizeOfPerSymbolTickets == 1) {
            // nur eine Position je Symbol kann sofort geschlossen werden
            if (!OrderCloseEx(perSymbolTickets[0], NULL, NULL, slippage, markerColor))
               return(_false(OrderPop("OrderMultiClose(9)")));
         }
         else {
            // Da wir hier Tickets mehrerer Symbole auf einmal schlie�en und mehrere Positionen je Symbol haben, wird zuerst nur die Gesamtposition
            // je Symbol ausgeglichen (schnellstm�gliche Variante: eine Close-Order je Symbol). Die einzelnen Teilpositionen werden erst nach Ausgleich
            // der Gesamtpositionen aller Symbole geschlossen (dies dauert ggf. etliche Sekunden).
            int hedge;
            if (!OrderMultiClose.Flatten(perSymbolTickets, hedge, slippage))
               return(_false(OrderPop("OrderMultiClose(10)")));
            if (hedge != 0) {
               sizeOfTickets = ArrayPushInt(ticketsCopy,   hedge      );
                               ArrayPushInt(ticketSymbols, symbolIndex);
            }
            ArrayPushInt(hedgedSymbolIndices, symbolIndex);                // Symbol zum sp�teren Schlie�en vormerken
         }
      }

      // jetzt die gehedgten Symbole komplett schlie�en
      int hedges = ArraySize(hedgedSymbolIndices);
      for (i=0; i < hedges; i++) {
         symbolIndex = hedgedSymbolIndices[i];
         ArrayResize(perSymbolTickets, 0);
         for (int n=0; n < sizeOfTickets; n++) {
            if (ticketSymbols[n] == symbolIndex)
               ArrayPushInt(perSymbolTickets, ticketsCopy[n]);
         }
         if (!OrderMultiClose.Hedges(perSymbolTickets, markerColor))
            return(_false(OrderPop("OrderMultiClose(11)")));
      }
      return(IsNoError(catch("OrderMultiClose(12)", NULL, O_POP)));
   }


   // (5) mehrere Tickets, die alle zu einem Symbol geh�ren
   if (!OrderMultiClose.Flatten(ticketsCopy, hedge, slippage))          // Gesamtposition ggf. hedgen...
      return(_false(OrderPop("OrderMultiClose(13)")));
   if (hedge != 0)
      sizeOfTickets = ArrayPushInt(ticketsCopy, hedge);

   if (!OrderMultiClose.Hedges(ticketsCopy, markerColor))               // ...und Gesamtposition aufl�sen
      return(_false(OrderPop("OrderMultiClose(14)")));

   return(IsNoError(catch("OrderMultiClose(15)", NULL, O_POP)));
}


/**
 * Gleicht die Gesamtposition der Tickets eines Symbols aus.
 *
 * @param  int    tickets[]   - Ticket-Nr. der zu hedgenden Positionen
 * @param  int&   hedgeTicket - Zeiger auf Variable zur Aufnahme der Ticket-Nr. der resultierenden Hedge-Position
 * @param  double slippage    - akzeptable Slippage in Pip (default: 0)
 *
 * @return bool - Erfolgsstatus
 */
/*private*/ bool OrderMultiClose.Flatten(int tickets[], int& hedgeTicket, double slippage=0) {
   int    sizeOfTickets = ArraySize(tickets);
   double totalLots;

   for (int i=0; i < sizeOfTickets; i++) {
      if (!OrderSelectByTicket(tickets[i], "OrderMultiClose.Flatten(1)"))
         return(false);
      if (OrderType() == OP_BUY) totalLots += OrderLots();           // Gesamtposition berechnen
      else                       totalLots -= OrderLots();
   }

   if (EQ(totalLots, 0)) {                                           // Gesamtposition ist bereits ausgeglichen
      hedgeTicket = 0;
   }
   else {                                                            // Gesamtposition hedgen

      // TODO: Statt OrderSend() nach M�glichkeit OrderClosePartial() verwenden (spart Margin, besser bei TradeserverLimits etc.)

      int type = ifInt(LT(totalLots, 0), OP_BUY, OP_SELL);

      string message = StringConcatenate("OrderMultiClose.Flatten()   opening ", OperationTypeDescription(type), " hedge for ", sizeOfTickets, " ", OrderSymbol(), " position");
      if (sizeOfTickets > 1)
         message = StringConcatenate(message, "s");
      log(message);

      int hedge = OrderSendEx(OrderSymbol(), type, MathAbs(totalLots), NULL, slippage);
      if (hedge == -1)
         return(false);
      hedgeTicket = hedge;
   }

   return(IsNoError(catch("OrderMultiClose.Flatten(2)")));
}


/**
 * Schlie�t die einzelnen, gehedgten Teilpositionen eines Symbols per OrderCloseBy().
 *
 * @param  int   tickets[]   - Ticket-Nr. der gehedgten Positionen
 * @param  color markerColor - Farbe des Chart-Markers (default: kein Marker)
 *
 * @return bool - Erfolgsstatus
 */
/*private*/ bool OrderMultiClose.Hedges(int tickets[], color markerColor=CLR_NONE) {
   // Das Array tickets[] wird in der Folge modifiziert. Um �nderungen am �bergebenen Ausgangsarray zu verhindern, m�ssen wir auf einer Kopie arbeiten.
   int ticketsCopy[]; ArrayResize(ticketsCopy, 0);
   ArrayCopy(ticketsCopy, tickets);

   int sizeOfTickets = ArraySize(ticketsCopy);

   if (!OrderSelectByTicket(ticketsCopy[0], "OrderMultiClose.Hedges(1)"))  // um OrderSymbol() auslesen zu k�nnen
      return(false);
   log(StringConcatenate("OrderMultiClose.Hedges()   closing ", sizeOfTickets, " hedged ", OrderSymbol(), " positions ", IntArrayToStr(ticketsCopy)));


   // alle Teilpositionen nacheinander aufl�sen
   while (sizeOfTickets > 0) {
      SortTicketsChronological(ticketsCopy);

      int hedge, first=ticketsCopy[0];
      if (!OrderSelectByTicket(first, "OrderMultiClose.Hedges(2)"))
         return(false);
      int firstType = OrderType();

      for (int i=1; i < sizeOfTickets; i++) {
         if (!OrderSelectByTicket(ticketsCopy[i], "OrderMultiClose.Hedges(3)"))
            return(false);
         if (OrderType() == firstType ^ 1) {
            hedge = ticketsCopy[i];                                  // hedgende Position ermitteln
            break;
         }
      }
      if (hedge == 0)
         return(_false(catch("OrderMultiClose.Hedges(4)   cannot find hedging position for "+ OperationTypeDescription(firstType) +" ticket #"+ first, ERR_RUNTIME_ERROR)));
      /*
      if (IsTesting()) {
         debug("OrderMultiClose.Hedges()   -----------------------------------------------------------------------------------------------------------------------------");
         debug("OrderMultiClose.Hedges()   before close #"+ first +" and #"+ hedge +" of "+ IntArrayToStr(ticketsCopy));
         debug("OrderMultiClose.Hedges()   -----------------------------------------------------------------------------------------------------------------------------");
         int entries[], trades=OrdersTotal(), history=OrdersHistoryTotal(), orders=trades + history;
         ArrayResize(entries, orders);
         for (int n=0; n < trades; n++) {
            OrderSelect(n, SELECT_BY_POS, MODE_TRADES);
            entries[n] = OrderTicket();
         }
         for (n=0; n < history; n++) {
            OrderSelect(n, SELECT_BY_POS, MODE_HISTORY);
            entries[trades + n] = OrderTicket();
         }
         ArraySort(entries);
         string PriceFormat = ".4'";
         for (n=0; n < orders; n++) {
            OrderSelectByTicket(entries[n], "OrderMultiClose.Hedges(4.1)");
            debug("OrderMultiClose.Hedges()   #"+ StringRightPad(OrderTicket(), 8, " ") +"   "+ StringRightPad(ifString(IsMyOrder(), "FTP."+ (OrderMagicNumber()>>8&0x3FFF) +"."+ (OrderMagicNumber()&0xF), OrderMagicNumber()), 11, " ") +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"   "+ NumberToStr(OrderOpenPrice(), PriceFormat) +"   "+ StringRightPad(OperationTypeDescription(OrderType()), 4, " ") +"   "+ StringRightPad(NumberToStr(OrderLots(), ".+"), 4, " ") +"   "+ ifString(OrderCloseTime()==0, "- open -           ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +"   "+ NumberToStr(OrderClosePrice(), PriceFormat) +"   "+ ifString(OrderComment()=="", "", StringConcatenate("\"", OrderComment(), "\"")));
         }
      }
      */
      int remainder[];
      if (!OrderCloseByEx(first, hedge, remainder, markerColor))     // erste und hedgende Position schlie�en
         return(false);

      if (i+1 < sizeOfTickets)                                       // hedgendes[i] Ticket l�schen
         ArrayCopy(ticketsCopy, ticketsCopy, i, i+1);
      sizeOfTickets--;
      ArrayResize(ticketsCopy, sizeOfTickets);

      ArrayShiftInt(ticketsCopy);                                    // erstes[0] Ticket l�schen
      sizeOfTickets--;

      if (ArraySize(remainder) != 0)                                 // Restposition zu verbleibenden Teilpositionen hinzuf�gen
         sizeOfTickets = ArrayPushInt(ticketsCopy, remainder[0]);
      /*
      if (IsTesting() && sizeOfTickets==0) {
         debug("OrderMultiClose.Hedges()   -----------------------------------------------------------------------------------------------------------------------------");
         debug("OrderMultiClose.Hedges()   after close");
         debug("OrderMultiClose.Hedges()   -----------------------------------------------------------------------------------------------------------------------------");
         trades  = OrdersTotal();
         history = OrdersHistoryTotal();
         orders  = trades + history;
         ArrayResize(entries, orders);
         for (n=0; n < trades; n++) {
            OrderSelect(n, SELECT_BY_POS, MODE_TRADES);
            entries[n] = OrderTicket();
         }
         for (n=0; n < history; n++) {
            OrderSelect(n, SELECT_BY_POS, MODE_HISTORY);
            entries[trades + n] = OrderTicket();
         }
         ArraySort(entries);
         for (n=0; n < orders; n++) {
            OrderSelectByTicket(entries[n], "OrderMultiClose.Hedges(4.2)");
            debug("OrderMultiClose.Hedges()   #"+ StringRightPad(OrderTicket(), 8, " ") +"   "+ StringRightPad(ifString(IsMyOrder(), "FTP."+ (OrderMagicNumber()>>8&0x3FFF) +"."+ (OrderMagicNumber()&0xF), OrderMagicNumber()), 11, " ") +"   "+ TimeToStr(OrderOpenTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) +"   "+ NumberToStr(OrderOpenPrice(), PriceFormat) +"   "+ StringRightPad(OperationTypeDescription(OrderType()), 4, " ") +"   "+ StringRightPad(NumberToStr(OrderLots(), ".+"), 4, " ") +"   "+ ifString(OrderCloseTime()==0, "- open -           ", TimeToStr(OrderCloseTime(), TIME_DATE|TIME_MINUTES|TIME_SECONDS)) +"   "+ NumberToStr(OrderClosePrice(), PriceFormat) +"   "+ ifString(OrderComment()=="", "", StringConcatenate("\"", OrderComment(), "\"")));
         }
         debug("OrderMultiClose.Hedges()   -----------------------------------------------------------------------------------------------------------------------------");
      }
      */
   }

   return(IsNoError(catch("OrderMultiClose.Hedges(5)")));
}


/**
 * Drop-in-Ersatz f�r und erweiterte Version von OrderDelete(). F�ngt tempor�re Tradeserver-Fehler ab und behandelt sie entsprechend.
 *
 * @param  int   ticket      - Ticket-Nr. der zu schlie�enden Order
 * @param  color markerColor - Farbe des Chart-Markers (default: kein Marker)
 *
 * @return bool - Erfolgsstatus
 */
bool OrderDeleteEx(int ticket, color markerColor=CLR_NONE) {
   // -- Beginn Parametervalidierung --
   // ticket
   if (!OrderSelectByTicket(ticket, "OrderDeleteEx(1)", O_PUSH)) return(false);
   if (!IsPendingTradeOperation(OrderType()))                    return(_false(catch("OrderDeleteEx(2)   ticket #"+ ticket +" is not a pending order", ERR_INVALID_TICKET, O_POP)));
   if (OrderCloseTime() != 0)                                    return(_false(catch("OrderDeleteEx(3)   ticket #"+ ticket +" is already deleted", ERR_INVALID_TICKET, O_POP)));
   // markerColor
   if (markerColor < CLR_NONE || markerColor > C'255,255,255')   return(_false(catch("OrderDeleteEx(4)   illegal parameter markerColor = "+ markerColor, ERR_INVALID_FUNCTION_PARAMVALUE, O_POP)));
   // -- Ende Parametervalidierung --

   int digits = MarketInfo(OrderSymbol(), MODE_DIGITS);                 // f�r OrderDeleteEx.LogMessage() und OrderDeleteEx.ChartMarker()
   int error = GetLastError();
   if (IsError(error)) return(_false(catch("OrderDeleteEx(5)   symbol=\""+ OrderSymbol() +"\"", error, O_POP)));

   int time1, time2;

   // Endlosschleife, bis Order gel�scht wurde oder ein permanenter Fehler auftritt
   while (!IsStopped()) {
      error = NO_ERROR;

      if (IsTradeContextBusy()) {
         log("OrderDeleteEx()   trade context busy, retrying...");
         Sleep(300);                                                    // 0.3 Sekunden warten
      }
      else {
         if (time1 == 0)
            time1 = GetTickCount();                                     // Zeit der ersten Ausf�hrung

         bool success = OrderDelete(ticket, markerColor);
         time2 = GetTickCount();

         if (success) {
            WaitForTicket(ticket, false);
            log("OrderDeleteEx()   "+ OrderDeleteEx.LogMessage(ticket, digits, time2-time1));

            if (!IsTesting())
               PlaySound("OrderOk.wav");
            else if (!ChartMarkers.OrderDeleted(ticket, digits, markerColor))
               return(_false(OrderPop("OrderDeleteEx(6)")));

            return(IsNoError(catch("OrderDeleteEx(7)", NULL, O_POP))); // regular exit
         }
         error = GetLastError();
         if (IsNoError(error))
            error = ERR_RUNTIME_ERROR;
         if (!IsTemporaryTradeError(error))                             // TODO: ERR_MARKET_CLOSED abfangen und besser behandeln
            break;

         string message = StringConcatenate(Symbol(), ",", PeriodDescription(NULL), "  ", __SCRIPT__, "::OrderDeleteEx()   temporary trade error ", ErrorToStr(error), " after ", DoubleToStr((time2-time1)/1000.0, 3), " s, retrying...");
         Alert(message);                                                // nach Fertigstellung durch log() ersetzen
         if (IsTesting()) {
            ForceSound("alert.wav");
            ForceMessageBox(message, __SCRIPT__, MB_ICONERROR|MB_OK);
         }
      }
   }

   return(_false(catch("OrderDeleteEx(8)   permanent trade error after "+ DoubleToStr((time2-time1)/1000.0, 3) +" s", error, O_POP)));
}


/**
 * Generiert eine ausf�hrliche Logmessage f�r eine erfolgreich gel�schte Order.
 *
 * @param  int ticket - Ticket der Order
 * @param  int digits - Nachkommastellen des Ordersymbols
 * @param  int time   - zur Ausf�hrung ben�tigte Zeit
 *
 * @return string - Logmessage
 */
/*private*/ string OrderDeleteEx.LogMessage(int ticket, int digits, int time) {
   if (!OrderSelectByTicket(ticket, "OrderDeleteEx.LogMessage(1)"))
      return("");

   int    pipDigits   = digits & (~1);
   string priceFormat = StringConcatenate(".", pipDigits, ifString(digits==pipDigits, "", "'"));
   string strType     = OperationTypeDescription(OrderType());
   string strLots     = NumberToStr(OrderLots(), ".+");
   string strPrice    = NumberToStr(OrderOpenPrice(), priceFormat);
   string message     = StringConcatenate("deleted #", ticket, " ", strType, " ", strLots, " ", OrderSymbol(), " at ", strPrice, " after ", DoubleToStr(time/1000.0, 3), " s");

   int error = GetLastError();
   if (IsError(error))
      return(_empty(catch("OrderDeleteEx.LogMessage(2)", error)));
   return(message);
}


// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! //


/**
 * This formats a number (int or double) into a string, performing alignment, rounding, inserting commas (0,000,000 etc), floating signs, currency symbols,
 * and so forth, according to the instructions provided in the 'mask'.
 *
 * The basic mask is "n" or "n.d" where n is the number of digits to the left of the decimal point, and d the number to the right,
 * e.g. NumberToStr(123.456,"5") will return "<space><space>123"
 * e.g. NumberToStr(123.456,"5.2") will return "<space><space>123.45"
 *
 * Other characters that may be used in the mask:
 *
 *    - Including a "-" anywhere to the left of "n.d" will cause a floating minus symbol to be included to the left of the number, if the nunber is negative; no symbol if positive
 *    - Including a "+" anywhere to the left of "n.d" will cause a floating plus or minus symbol to be included, to the left of the number
 *    - Including a "-" anywhere to the right of "n.d" will cause a minus to be included at the right of the number, e.g. NumberToStr(-123.456,"3.2-") will return "123.46-"
 *    - Including a "(" or ")" anywhere in the mask will cause any negative number to be enclosed in parentheses
 *    - Including an "R" or "r" anywhere in the mask will cause rounding, e.g. NumberToStr(123.456,"R3.2") will return "123.46"; e.g. NumberToStr(123.7,"R3") will return "124"
 *    - Including a "$", "�", "�" or "�" anywhere in the mask will cause the designated floating currency symbol to be included, to the left of the number
 *    - Including a "," anywhere in the mask will cause commas to be inserted between every 3 digits, to separate thousands, millions, etc at the left of the number, e.g. NumberToStr(123456.789,",6.3") will return "123,456.789"
 *    - Including a "Z" or "z" anywhere in the mask will cause zeros (instead of spaces) to be used to fill any unused places at the left of the number, e.g. NumberToStr(123.456,"Z5.2") will return "00123.45"
 *    - Including a "B" or "b" anywhere in the mask ("blank if zero") will cause the entire output to be blanks, if the value of the number is zero
 *    - Including a "*" anywhere in the mask will cause an asterisk to be output, if overflow occurs (the value of n in "n.d" is too small to allow the number to be output in full)
 *    - Including a "L" or "l" anywhere in the mask will cause the output to be left aligned in the output field, e.g. NumberToStr(123.456,"L5.2") will return "123.45<space><space>"
 *    - Including a "T" or "t" anywhere in the mask will cause the output to be left aligned in the output field, and trailing spaces trimmed e.g. NumberToStr(123.456,"T5.2") will return "123.45"
 *    - Including a ";" anywhere in the mask will cause decimal point and comma to be juxtaposed, e.g. NumberToStr(123456.789,";,6.3") will return "123.456,789"
 *
 * ================================================================================================================================================================================================================================
 *
 * Formats a number using a mask, and returns the resulting string
 *
 * Mask parameters:
 * n = number of digits to output, to the left of the decimal point
 * n.d = output n digits to left of decimal point; d digits to the right
 * -n.d = floating minus sign at left of output
 * n.d- = minus sign at right of output
 * +n.d = floating plus/minus sign at left of output
 * ( or ) = enclose negative number in parentheses
 * $ or � or � or � = include floating currency symbol at left of output
 * % = include trailing % sign
 * , = use commas to separate thousands
 * Z or z = left fill with zeros instead of spaces
 * R or r = round result in rightmost displayed digit
 * B or b = blank entire field if number is 0
 * * = show asterisk in leftmost position if overflow occurs
 * ; = switch use of comma and period (European format)
 * L or l = left align final string
 * T ot t = trim end result
 */
string orig_NumberToStr(double n, string mask) {
   if (MathAbs(n) == EMPTY_VALUE)
      n = 0;

   mask = StringToUpper(mask);
   int dotadj = 0;
   int dot    = StringFind(mask, ".");
   if (dot < 0) {
      dot    = StringLen(mask);
      dotadj = 1;
   }

   int nleft  = 0;
   int nright = 0;

   for (int i=0; i < dot; i++) {
      string char = StringSubstr(mask, i, 1);
      if (char >= "0" && char <= "9")
         nleft = 10*nleft + StrToInteger(char);
   }
   if (dotadj == 0) {
      for (i=dot+1; i <= StringLen(mask); i++) {
         char = StringSubstr(mask, i, 1);
         if (char >= "0" && char <= "9")
            nright = 10*nright + StrToInteger(char);
      }
   }
   nright = MathMin(nright, 7);

   if (dotadj == 1) {
      for (i=0; i < StringLen(mask); i++) {
         char = StringSubstr(mask, i, 1);
         if (char >= "0" && char <= "9") {
            dot = i;
            break;
         }
      }
   }

   string csym = "";
   if (StringFind(mask, "$") > -1) csym = "$";
   if (StringFind(mask, "�") > -1) csym = "�";
   if (StringFind(mask, "�") > -1) csym = "�";
   if (StringFind(mask, "�") > -1) csym = "�";

   string leadsign  = "";
   string trailsign = "";

   if (StringFind(mask, "+") > -1 && StringFind(mask, "+") < dot) {
      leadsign = " ";
      if (n > 0) leadsign = "+";
      if (n < 0) leadsign = "-";
   }
   if (StringFind(mask, "-") > -1 && StringFind(mask, "-") < dot) {
      if (n < 0) leadsign = "-";
      else       leadsign = " ";
   }
   if (StringFind(mask, "-") > -1 && StringFind(mask, "-") > dot) {
      if (n < 0) trailsign = "-";
      else       trailsign = " ";
   }
   if (StringFind(mask, "(") > -1 || StringFind(mask, ")") > -1) {
      leadsign  = " ";
      trailsign = " ";
      if (n < 0) {
         leadsign  = "(";
         trailsign = ")";
      }
   }
   if (StringFind(mask, "%") > -1)
      trailsign = "%" + trailsign;

   bool comma = (StringFind(mask, ",") > -1);
   bool zeros = (StringFind(mask, "Z") > -1);
   bool blank = (StringFind(mask, "B") > -1);
   bool round = (StringFind(mask, "R") > -1);
   bool overf = (StringFind(mask, "*") > -1);
   bool lftsh = (StringFind(mask, "L") > -1);
   bool swtch = (StringFind(mask, ";") > -1);
   bool trimf = (StringFind(mask, "T") > -1);

   if (round)
      n = MathRoundFix(n, nright);
   string outstr = n;

   int dleft = 0;
   for (i=0; i < StringLen(outstr); i++) {
      char = StringSubstr(outstr, i, 1);
      if (char >= "0" && char <= "9")
         dleft++;
      if (char == ".")
         break;
   }

   // Insert fill characters.......
   if (zeros) string fill = "0";
   else              fill = " ";
   if (n < 0) outstr = "-" + StringRepeat(fill, nleft-dleft) + StringSubstr(outstr, 1);
   else       outstr = StringRepeat(fill, nleft-dleft) + outstr;
   outstr = StringSubstrFix(outstr, StringLen(outstr)-9-nleft, nleft+1+nright-dotadj);

   // Insert the commas.......
   if (comma) {
      bool digflg = false;
      bool stpflg = false;
      string out1 = "";
      string out2 = "";
      for (i=0; i < StringLen(outstr); i++) {
         char = StringSubstr(outstr, i, 1);
         if (char == ".")
            stpflg = true;
         if (!stpflg && (nleft-i==3 || nleft-i==6 || nleft-i==9)) {
            if (digflg) out1 = out1 +",";
            else        out1 = out1 +" ";
         }
         out1 = out1 + char;
         if (char >= "0" && char <= "9")
            digflg = true;
      }
      outstr = out1;
   }

   // Add currency symbol and signs........
   outstr = csym + leadsign + outstr + trailsign;

   // 'Float' the currency symbol/sign.......
   out1 = "";
   out2 = "";
   bool fltflg = true;
   for (i=0; i < StringLen(outstr); i++) {
      char = StringSubstr(outstr, i, 1);
      if (char >= "0" && char <= "9")
         fltflg = false;
      if ((char==" " && fltflg) || (blank && n==0)) out1 = out1 + " ";
      else                                          out2 = out2 + char;
   }
   outstr = out1 + out2;

   // Overflow........
   if (overf && dleft > nleft)
      outstr = "*" + StringSubstr(outstr, 1);

   // Left shift.......
   if (lftsh) {
      int len = StringLen(outstr);
      outstr = StringTrimLeft(outstr);
      outstr = outstr + StringRepeat(" ", len-StringLen(outstr));
   }

   // Switch period and comma.......
   if (swtch) {
      out1 = "";
      for (i=0; i < StringLen(outstr); i++) {
         char = StringSubstr(outstr, i, 1);
         if      (char == ".") out1 = out1 +",";
         else if (char == ",") out1 = out1 +".";
         else                  out1 = out1 + char;
      }
      outstr = out1;
   }

   if (trimf)
      outstr = StringTrim(outstr);
   return(outstr);
}


/**
 * Returns the numeric value for an MQL4 color descriptor string.
 *
 *  Usage: StrToColor("Aqua")       => 16776960
 *  or:    StrToColor("0,255,255")  => 16776960  i.e. StrToColor("<red>,<green>,<blue>")
 *  or:    StrToColor("r0g255b255") => 16776960  i.e. StrToColor("r<nnn>g<nnn>b<nnn>")
 *  or:    StrToColor("0xFFFF00")   => 16776960  i.e. StrToColor("0xbbggrr")
 */
int StrToColor(string str) {
   str = StringToLower(str);

   if (str == "aliceblue"        ) return(0xFFF8F0);
   if (str == "antiquewhite"     ) return(0xD7EBFA);
   if (str == "aqua"             ) return(0xFFFF00);
   if (str == "aquamarine"       ) return(0xD4FF7F);
   if (str == "beige"            ) return(0xDCF5F5);
   if (str == "bisque"           ) return(0xC4E4FF);
   if (str == "black"            ) return(0x000000);
   if (str == "blanchedalmond"   ) return(0xCDEBFF);
   if (str == "blue"             ) return(0xFF0000);
   if (str == "blueviolet"       ) return(0xE22B8A);
   if (str == "brown"            ) return(0x2A2AA5);
   if (str == "burlywood"        ) return(0x87B8DE);
   if (str == "cadetblue"        ) return(0xA09E5F);
   if (str == "chartreuse"       ) return(0x00FF7F);
   if (str == "chocolate"        ) return(0x1E69D2);
   if (str == "coral"            ) return(0x507FFF);
   if (str == "cornflowerblue"   ) return(0xED9564);
   if (str == "cornsilk"         ) return(0xDCF8FF);
   if (str == "crimson"          ) return(0x3C14DC);
   if (str == "darkblue"         ) return(0x8B0000);
   if (str == "darkgoldenrod"    ) return(0x0B86B8);
   if (str == "darkgray"         ) return(0xA9A9A9);
   if (str == "darkgreen"        ) return(0x006400);
   if (str == "darkkhaki"        ) return(0x6BB7BD);
   if (str == "darkolivegreen"   ) return(0x2F6B55);
   if (str == "darkorange"       ) return(0x008CFF);
   if (str == "darkorchid"       ) return(0xCC3299);
   if (str == "darksalmon"       ) return(0x7A96E9);
   if (str == "darkseagreen"     ) return(0x8BBC8F);
   if (str == "darkslateblue"    ) return(0x8B3D48);
   if (str == "darkslategray"    ) return(0x4F4F2F);
   if (str == "darkturquoise"    ) return(0xD1CE00);
   if (str == "darkviolet"       ) return(0xD30094);
   if (str == "deeppink"         ) return(0x9314FF);
   if (str == "deepskyblue"      ) return(0xFFBF00);
   if (str == "dimgray"          ) return(0x696969);
   if (str == "dodgerblue"       ) return(0xFF901E);
   if (str == "firebrick"        ) return(0x2222B2);
   if (str == "forestgreen"      ) return(0x228B22);
   if (str == "gainsboro"        ) return(0xDCDCDC);
   if (str == "gold"             ) return(0x00D7FF);
   if (str == "goldenrod"        ) return(0x20A5DA);
   if (str == "gray"             ) return(0x808080);
   if (str == "green"            ) return(0x008000);
   if (str == "greenyellow"      ) return(0x2FFFAD);
   if (str == "honeydew"         ) return(0xF0FFF0);
   if (str == "hotpink"          ) return(0xB469FF);
   if (str == "indianred"        ) return(0x5C5CCD);
   if (str == "indigo"           ) return(0x82004B);
   if (str == "ivory"            ) return(0xF0FFFF);
   if (str == "khaki"            ) return(0x8CE6F0);
   if (str == "lavender"         ) return(0xFAE6E6);
   if (str == "lavenderblush"    ) return(0xF5F0FF);
   if (str == "lawngreen"        ) return(0x00FC7C);
   if (str == "lemonchiffon"     ) return(0xCDFAFF);
   if (str == "lightblue"        ) return(0xE6D8AD);
   if (str == "lightcoral"       ) return(0x8080F0);
   if (str == "lightcyan"        ) return(0xFFFFE0);
   if (str == "lightgoldenrod"   ) return(0xD2FAFA);
   if (str == "lightgray"        ) return(0xD3D3D3);
   if (str == "lightgreen"       ) return(0x90EE90);
   if (str == "lightpink"        ) return(0xC1B6FF);
   if (str == "lightsalmon"      ) return(0x7AA0FF);
   if (str == "lightseagreen"    ) return(0xAAB220);
   if (str == "lightskyblue"     ) return(0xFACE87);
   if (str == "lightslategray"   ) return(0x998877);
   if (str == "lightsteelblue"   ) return(0xDEC4B0);
   if (str == "lightyellow"      ) return(0xE0FFFF);
   if (str == "lime"             ) return(0x00FF00);
   if (str == "limegreen"        ) return(0x32CD32);
   if (str == "linen"            ) return(0xE6F0FA);
   if (str == "magenta"          ) return(0xFF00FF);
   if (str == "maroon"           ) return(0x000080);
   if (str == "mediumaquamarine" ) return(0xAACD66);
   if (str == "mediumblue"       ) return(0xCD0000);
   if (str == "mediumorchid"     ) return(0xD355BA);
   if (str == "mediumpurple"     ) return(0xDB7093);
   if (str == "mediumseagreen"   ) return(0x71B33C);
   if (str == "mediumslateblue"  ) return(0xEE687B);
   if (str == "mediumspringgreen") return(0x9AFA00);
   if (str == "mediumturquoise"  ) return(0xCCD148);
   if (str == "mediumvioletred"  ) return(0x8515C7);
   if (str == "midnightblue"     ) return(0x701919);
   if (str == "mintcream"        ) return(0xFAFFF5);
   if (str == "mistyrose"        ) return(0xE1E4FF);
   if (str == "moccasin"         ) return(0xB5E4FF);
   if (str == "navajowhite"      ) return(0xADDEFF);
   if (str == "navy"             ) return(0x800000);
   if (str == "none"             ) return(      -1);
   if (str == "oldlace"          ) return(0xE6F5FD);
   if (str == "olive"            ) return(0x008080);
   if (str == "olivedrab"        ) return(0x238E6B);
   if (str == "orange"           ) return(0x00A5FF);
   if (str == "orangered"        ) return(0x0045FF);
   if (str == "orchid"           ) return(0xD670DA);
   if (str == "palegoldenrod"    ) return(0xAAE8EE);
   if (str == "palegreen"        ) return(0x98FB98);
   if (str == "paleturquoise"    ) return(0xEEEEAF);
   if (str == "palevioletred"    ) return(0x9370DB);
   if (str == "papayawhip"       ) return(0xD5EFFF);
   if (str == "peachpuff"        ) return(0xB9DAFF);
   if (str == "peru"             ) return(0x3F85CD);
   if (str == "pink"             ) return(0xCBC0FF);
   if (str == "plum"             ) return(0xDDA0DD);
   if (str == "powderblue"       ) return(0xE6E0B0);
   if (str == "purple"           ) return(0x800080);
   if (str == "red"              ) return(0x0000FF);
   if (str == "rosybrown"        ) return(0x8F8FBC);
   if (str == "royalblue"        ) return(0xE16941);
   if (str == "saddlebrown"      ) return(0x13458B);
   if (str == "salmon"           ) return(0x7280FA);
   if (str == "sandybrown"       ) return(0x60A4F4);
   if (str == "seagreen"         ) return(0x578B2E);
   if (str == "seashell"         ) return(0xEEF5FF);
   if (str == "sienna"           ) return(0x2D52A0);
   if (str == "silver"           ) return(0xC0C0C0);
   if (str == "skyblue"          ) return(0xEBCE87);
   if (str == "slateblue"        ) return(0xCD5A6A);
   if (str == "slategray"        ) return(0x908070);
   if (str == "snow"             ) return(0xFAFAFF);
   if (str == "springgreen"      ) return(0x7FFF00);
   if (str == "steelblue"        ) return(0xB48246);
   if (str == "tan"              ) return(0x8CB4D2);
   if (str == "teal"             ) return(0x808000);
   if (str == "thistle"          ) return(0xD8BFD8);
   if (str == "tomato"           ) return(0x4763FF);
   if (str == "turquoise"        ) return(0xD0E040);
   if (str == "violet"           ) return(0xEE82EE);
   if (str == "wheat"            ) return(0xB3DEF5);
   if (str == "white"            ) return(0xFFFFFF);
   if (str == "whitesmoke"       ) return(0xF5F5F5);
   if (str == "yellow"           ) return(0x00FFFF);
   if (str == "yellowgreen"      ) return(0x32CD9A);

   int t1 = StringFind(str, ",", 0);
   int t2 = StringFind(str, ",", t1+1);

   if (t1>0 && t2>0) {
      int red   = StrToInteger(StringSubstrFix(str, 0, t1));
      int green = StrToInteger(StringSubstrFix(str, t1+1, t2-1));
      int blue  = StrToInteger(StringSubstr(str, t2+1));
      return(blue*256*256 + green*256 + red);
   }

   if (StringSubstr(str, 0, 2) == "0x") {
      string cnvstr = "0123456789abcdef";
      string seq    = "234567";
      int    retval = 0;
      for (int i=0; i < 6; i++) {
         int pos = StrToInteger(StringSubstr(seq, i, 1));
         int val = StringFind(cnvstr, StringSubstr(str, pos, 1), 0);
         if (val < 0)
            return(val);
         retval = retval * 16 + val;
      }
      return(retval);
   }

   string cclr = "", tmp = "";
   red   = 0;
   blue  = 0;
   green = 0;

   if (StringFind("rgb", StringSubstr(str, 0, 1)) >= 0) {
      for (i=0; i < StringLen(str); i++) {
         tmp = StringSubstr(str, i, 1);
         if (StringFind("rgb", tmp, 0) >= 0)
            cclr = tmp;
         else {
            if (cclr == "b") blue  = blue  * 10 + StrToInteger(tmp);
            if (cclr == "g") green = green * 10 + StrToInteger(tmp);
            if (cclr == "r") red   = red   * 10 + StrToInteger(tmp);
         }
      }
      return(blue*256*256 + green*256 + red);
   }

   return(0);
}


/**
 * Converts a timeframe string to its MT4-numeric value
 * Usage:   int x=StrToTF("M15")   returns x=15
 */
int StrToTF(string str) {
   str = StringToUpper(str);
   if (str == "M1" ) return(    1);
   if (str == "M5" ) return(    5);
   if (str == "M15") return(   15);
   if (str == "M30") return(   30);
   if (str == "H1" ) return(   60);
   if (str == "H4" ) return(  240);
   if (str == "D1" ) return( 1440);
   if (str == "W1" ) return(10080);
   if (str == "MN" ) return(43200);
   return(0);
}


/**
 * Converts a MT4-numeric timeframe to its descriptor string
 * Usage:   string s=TFToStr(15) returns s="M15"
 */
string TFToStr(int tf) {
   switch (tf) {
      case     1: return("M1" );
      case     5: return("M5" );
      case    15: return("M15");
      case    30: return("M30");
      case    60: return("H1" );
      case   240: return("H4" );
      case  1440: return("D1" );
      case 10080: return("W1" );
      case 43200: return("MN" );
   }
   return(0);
}


/**
 *
 */
string StringReverse(string str) {
   string outstr = "";
   for (int i=StringLen(str)-1; i >= 0; i--) {
      outstr = outstr + StringSubstr(str,i,1);
   }
   return(outstr);
}


/**
 *
 */
string StringLeftExtract(string str, int n, string str2, int m) {
   if (n > 0) {
      int j = -1;
      for (int i=1; i <= n; i++) {
         j = StringFind(str, str2, j+1);
      }
      if (j > 0)
         return(StringLeft(str, j+m));
   }

   if (n < 0) {
      int c = 0;
      j = 0;
      for (i=StringLen(str)-1; i >= 0; i--) {
         if (StringSubstrFix(str, i, StringLen(str2)) == str2) {
            c++;
            if (c == -n) {
               j = i;
               break;
            }
         }
      }
      if (j > 0)
         return(StringLeft(str, j+m));
   }
   return("");
}


/**
 *
 */
string StringRightExtract(string str, int n, string str2, int m) {
   if (n > 0) {
      int j = -1;
      for (int i=1; i <= n; i++) {
         j=StringFind(str,str2,j+1);
      }
      if (j > 0)
         return(StringRight(str, StringLen(str)-j-1+m));
   }

   if (n < 0) {
      int c = 0;
      j = 0;
      for (i=StringLen(str)-1; i >= 0; i--) {
         if (StringSubstrFix(str, i, StringLen(str2)) == str2) {
            c++;
            if (c == -n) {
               j = i;
               break;
            }
         }
      }
      if (j > 0)
         return(StringRight(str, StringLen(str)-j-1+m));
   }
   return("");
}


/**
 * Returns the number of occurrences of STR2 in STR
 * Usage:   int x = StringFindCount("ABCDEFGHIJKABACABB","AB")   returns x = 3
 */
int StringFindCount(string str, string str2) {
   int c = 0;
   for (int i=0; i < StringLen(str); i++) {
      if (StringSubstrFix(str, i, StringLen(str2)) == str2)
         c++;
   }
   return(c);
}


/**
 *
 */
double MathInt(double n, int d) {
   return(MathFloor(n*MathPow(10, d) + 0.000000000001) / MathPow(10, d));
}


/**
 * Converts a datetime value to a formatted string, according to the instructions in the 'mask'.
 *
 *    - A "d" in the mask will cause a 1-2 digit day-of-the-month to be inserted in the output, at that point
 *    - A "D" in the mask will cause a 2 digit day-of-the-month to be inserted in the output, at that point
 *    - A "m" in the mask will cause a 1-2 digit month number to be inserted in the output, at that point
 *    - A "M" in the mask will cause a 2 digit month number to be inserted in the output, at that point
 *    - A "y" in the mask will cause a 2 digit year to be inserted in the output, at that point
 *    - A "Y" in the mask will cause a 4 digit (Y2K compliant) year to be inserted in the output, at that point
 *    - A "W" in the mask will cause a day-of-the week ("Monday", "Tuesday", etc) description to be inserted in the output, at that point
 *    - A "w" in the mask will cause an abbreviated day-of-the week ("Mon", "Tue", etc) description to be inserted in the output, at that point
 *    - A "N" in the mask will cause a month name ("January", "February", etc) to be inserted in the output, at that point
 *    - A "n" in the mask will cause an abbreviated month name ("Jan", "Feb", etc) to be inserted in the output, at that point
 *    - A "h" in the mask will cause the hour-of-the-day to be inserted in the output, as 1 or 2 digits, at that point
 *    - A "H" in the mask will cause the hour-of-the-day to be inserted in the output, as 2 digits (with placeholding 0, if value < 10), at that point
 *    - An "I" or "i" in the mask will cause the minutes to be inserted in the output, as 2 digits (with placeholding 0, if value < 10), at that point
 *    - A "S" or "s" in the mask will cause the seconds to be inserted in the output, as 2 digits (with placeholding 0, if value < 10), at that point
 *    - An "a" in the mask will cause a 12-hour version of the time to be displayed, with "am" or "pm" at that point
 *    - An "A" in the mask will cause a 12-hour version of the time to be displayed, with "AM" or "PM" at that point
 *    - A "T" in the mask will cause "st" "nd" rd" or "th" to be inserted at that point, depending on the day of the month e.g. 13th, 22nd, etc
 *    - All other characters in the mask will be output, as is
 *
 * Examples: if date is June 04, 2009, then:
 *
 *    - DateToStr(date, "w m/d/Y") will output "Thu 6/4/2009"
 *    - DateToStr(date, "Y-MD") will output "2009-0604"
 *    - DateToStr(date, "d N, Y is a W") will output "4 June, 2009 is a Thursday"
 *    - DateToStr(date, "W D`M`y = W") will output "Thursday 04`06`09 = Thursday"
 */
string DateToStr(datetime mt4date, string mask) {
   int dd  = TimeDay(mt4date);
   int mm  = TimeMonth(mt4date);
   int yy  = TimeYear(mt4date);
   int dw  = TimeDayOfWeek(mt4date);
   int hr  = TimeHour(mt4date);
   int min = TimeMinute(mt4date);
   int sec = TimeSeconds(mt4date);
   int h12 = 12;
   if      (hr > 12) h12 = hr - 12;
   else if (hr >  0) h12 = hr;

   string ampm = "am";
   if (hr > 12)
      ampm = "pm";

   switch (dd % 10) {
      case 1: string d10 = "st"; break;
      case 2:        d10 = "nd"; break;
      case 3:        d10 = "rd"; break;
      default:       d10 = "th";
   }
   if (dd > 10 && dd < 14)
      d10 = "th";

   string mth[12] = { "January","February","March","April","May","June","July","August","September","October","November","December" };
   string dow[ 7] = { "Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday" };

   string outdate = "";

   for (int i=0; i < StringLen(mask); i++) {
      string char = StringSubstr(mask, i, 1);
      if      (char == "d")                outdate = outdate + StringTrim(NumberToStr(dd, "2"));
      else if (char == "D")                outdate = outdate + StringTrim(NumberToStr(dd, "Z2"));
      else if (char == "m")                outdate = outdate + StringTrim(NumberToStr(mm, "2"));
      else if (char == "M")                outdate = outdate + StringTrim(NumberToStr(mm, "Z2"));
      else if (char == "y")                outdate = outdate + StringTrim(NumberToStr(yy, "2"));
      else if (char == "Y")                outdate = outdate + StringTrim(NumberToStr(yy, "4"));
      else if (char == "n")                outdate = outdate + StringSubstr(mth[mm-1], 0, 3);
      else if (char == "N")                outdate = outdate + mth[mm-1];
      else if (char == "w")                outdate = outdate + StringSubstr(dow[dw], 0, 3);
      else if (char == "W")                outdate = outdate + dow[dw];
      else if (char == "h")                outdate = outdate + StringTrim(NumberToStr(h12, "2"));
      else if (char == "H")                outdate = outdate + StringTrim(NumberToStr(hr, "Z2"));
      else if (StringToUpper(char) == "I") outdate = outdate + StringTrim(NumberToStr(min, "Z2"));
      else if (StringToUpper(char) == "S") outdate = outdate + StringTrim(NumberToStr(sec, "Z2"));
      else if (char == "a")                outdate = outdate + ampm;
      else if (char == "A")                outdate = outdate + StringToUpper(ampm);
      else if (StringToUpper(char) == "T") outdate = outdate + d10;
      else                                 outdate = outdate + char;
   }
   return(outdate);
}


/**
 * Returns the base 10 version of a number in another base
 * Usage:   int x=BaseToNumber("DC",16)   returns x=220
 */
int BaseToNumber(string str, int base) {
   str = StringToUpper(str);
   string cnvstr = "0123456789ABCDEF";
   int    retval = 0;
   for (int i=0; i < StringLen(str); i++) {
      int val = StringFind(cnvstr, StringSubstr(str, i, 1), 0);
      if (val < 0)
         return(val);
      retval = retval * base + val;
   }
   return(retval);
}


/**
 * Converts a base 10 number to another base, left-padded with zeros
 * Usage:   int x=BaseToNumber(220,16,4)   returns x="00DC"
 */
string NumberToBase(int n, int base, int pad) {
   string cnvstr = "0123456789ABCDEF";
   string outstr = "";
   while (n > 0) {
      int x = n % base;
      outstr = StringSubstr(cnvstr, x, 1) + outstr;
      n /= base;
   }
   x = StringLen(outstr);
   if (x < pad)
      outstr = StringRepeat("0", pad-x) + outstr;
   return(outstr);
}
