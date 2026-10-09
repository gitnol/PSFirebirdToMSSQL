# Threat Model & Mitigationen – PSFirebirdToMSSQL

Stand: 2026-10-09 (I7, Rollout-Check `-PreDeploy`; Initialisierung 2026-10-08, Code-Stand 721d5e0). Abgeleitet ausschließlich aus dem
tatsächlichen Code im Projekt-Root (`Sync_Firebird_MSSQL_AutoSchema.ps1`, `SQLSyncCommon.psm1`,
`sql_server_setup.sql`, `Setup_Credentials.ps1`, `Setup-ScheduledTasks.ps1`,
`Manage_Config_Tables.ps1`). Schwachstellen-IDs S1–S13 und Inkrement-IDs I2–I11 entsprechen
`KNOWN_ISSUES.md` bzw. `TODO.md`.

**Systemkontext in einem Satz:** Ein Windows-Host führt per Task Scheduler PowerShell 7 aus, liest
mit Credentials aus dem Windows Credential Manager ERP-Tabellen aus einer Firebird-Datenbank und
schreibt sie per `SqlBulkCopy` + `sp_Merge_Generic` in eine MS-SQL-Datenbank. Es gibt keine
Netzwerk-Schnittstelle nach außen, keine Benutzereingaben zur Laufzeit außer der Konfigurationsdatei
(`-ConfigFile`) und keine LLM-Nutzung.

**Vertrauensgrenzen:**

| Grenze | Was überquert sie | Vertrauen |
|---|---|---|
| Konfigurationsdatei (`config*.json`) → Skript | Tabellen-/Spaltennamen, Server, ggf. Klartext-Passwort | Wer Schreibrecht auf den Skriptordner hat, steuert SQL und Ziele |
| Firebird-Metadaten → `Manage_Config_Tables.ps1` → `config.json` | Tabellennamen aus `RDB$RELATIONS` | Vertrauen in den Firebird-Admin |
| Internet (NuGet CDN) → `%ProgramData%\SQLSync\Drivers\...` | Treiber-DLL | Jede DLL wird vor dem Laden per SHA-256 geprüft (Download, vorhanden, `DllPath`; seit I7) |
| Firebird → MSSQL | Nutzdaten (ERP, inkl. personenbezogener Daten) | Werte werden per `SqlBulkCopy` übertragen, nicht als SQL-Text |

**Prompt-Injection:** Im analysierten Code wurden keine Prompt-Injection- oder Anweisungstexte
gefunden. Das Projekt nutzt kein LLM; Bedrohungen nach `principles/UNTRUSTED_DOCUMENT_CONTENT.md`
treffen derzeit nicht zu.

---

## 1. SQL-Identifier-Injection über Tabellen- und Spaltennamen (S2)

**Gefahr:** Tabellen- und Spaltennamen aus der Konfiguration (`Tables`, `TableOverrides`,
`General.IdColumn`, `General.TimestampColumns`, `MSSQL.Database`, `MSSQL.Prefix`, `MSSQL.Suffix`)
und Spaltennamen aus den Firebird-Metadaten werden in SQL-Text eingesetzt (Firebird: Extrakt,
Sanity-`COUNT`; MSSQL: `TRUNCATE`, `SELECT COUNT`, `SELECT INTO`, `INSERT`, `CREATE/DROP` Staging,
Orphan-Cleanup, `CREATE TABLE` mit Spaltenliste). Bis v2.11 geschah das ungeprüft, im MSSQL-Teil
teils ohne Klammerung und als String-Literal (`INFORMATION_SCHEMA ... TABLE_NAME = '...'`,
`EXEC sp_Merge_Generic @TargetTableName = '...'`). Ein manipulierter Eintrag wie `X; DROP TABLE ...`
im Feld `Tables` oder `MSSQL.Prefix` wäre im MSSQL-Kontext des Sync-Kontos ausgeführt worden (das
DDL-Rechte in der Ziel-DB hat, siehe Bedrohung 5). Quellen der Namen: `config*.json` (manuell
gepflegt) und `Manage_Config_Tables.ps1` (übernimmt Namen aus den Firebird-Metadaten).

**Aktuelle Mitigation (im Code vorhanden, seit I4 / v2.12, 2026-10-08):**
- **Allow-List:** `Assert-SqlIdentifier` (`SQLSyncCommon.psm1`) lässt nur `^[A-Za-z0-9_$]+$`
  (case-sensitive) und höchstens 63 Zeichen (Firebird-Limit) zu. `Get-SQLSyncConfig` prüft beim
  Laden alle oben genannten Felder inkl. `TableOverrides`-Schlüssel und deren
  `IdColumn`/`TimestampColumn` (leer erlaubt für `MSSQL.Database`, `MSSQL.Prefix`/`Suffix` und
  Override-Spalten) sowie die Länge des Zieltabellennamens Prefix + Tabelle + Suffix (≤ 128 Zeichen,
  SQL-Server-Limit). Verstoß → Fail-Fast mit Exit-Code 2, bevor eine Verbindung aufgebaut wird.
- **Quoting zusätzlich zur Allow-List:** Im Hauptskript stehen alle MSSQL-Tabellennamen in eckigen
  Klammern (inkl. Temp-Tabelle `#SourceIDs_*` und `SqlBulkCopy`-Ziel); Firebird-Namen in `"..."`.
  Spaltennamen aus den Firebird-Metadaten werden im `CREATE TABLE` zusätzlich escaped (`]` → `]]`).
- **Parameter statt Literale:** `INFORMATION_SCHEMA`-/`sys.indexes`-Abfragen nutzen `SqlParameter`
  (`@TableName`, `@ColumnName`, `@IndexName`, `OBJECT_ID(QUOTENAME(@TableName))`);
  `sp_Merge_Generic` wird als `CommandType StoredProcedure` mit Parametern aufgerufen und baut ihr
  dynamisches `MERGE` mit `QUOTENAME`.
- **Schema als weitere Schicht (seit I6 / v2.15, 2026-10-09):** Alle vier Einstiegsskripte laden die
  Konfig über `Get-SQLSyncConfig -SchemaPath …\config.schema.json`; das Schema ist **vor** der
  Allow-List aktiv und verlangt für `Tables`, `General.IdColumn`, `General.TimestampColumns` und
  `TableOverrides.<Tabelle>.IdColumn`/`.TimestampColumn` dasselbe Muster `^[A-Za-z0-9_$]+$` (max. 63),
  für `MSSQL.Prefix`/`Suffix` `^[A-Za-z0-9_$]*$`. Zusätzlich weist es unbekannte Schlüssel und falsche
  Typen ab (`additionalProperties: false`). Verstoß → Exit 2 vor jeder Verbindung. Fehlt die
  Schema-Datei, bleibt nur die Allow-List im Code (Warnung im Log).
- `Manage_Config_Tables.ps1` (v2.1) prüft die Konfig beim Start über `Get-SQLSyncConfig` (Schema +
  Allow-List, Exit 2) und übernimmt Tabellen mit ungültigem Namen nicht (Markierung im GridView).
- Der Inkrement-Filter nutzt einen Parameter (`@LastDate`); Nutzdaten fließen ausschließlich über
  `SqlBulkCopy` (Spaltenmapping nach Name), nicht als SQL-Text.
- Unit-Tests (Pester) decken gültige/ungültige Namen (u. a. `A"B`, `X;DROP`, `A]B`, `A'B`,
  Leerzeichen, `-`, leer, 64 Zeichen), die Prüfung je Konfigurationsfeld und die 128-Zeichen-Grenze
  ab; Integrationsläufe am 2026-10-08 (ForceFull, inkrementell mit `CleanupOrphans`) mit Exit 0.
- Best-Practice-Abgleich am 2026-10-08: Allow-List plus `QUOTENAME`/Klammern; Klammern allein
  gelten als unzureichend (Quellen:
  https://www.sqlservercentral.com/articles/why-quotename-is-important ,
  https://sqlstudies.com/2017/05/11/dynamic-sql-and-the-joys-of-quotename/ ). Firebird-Bezeichner
  max. 63 Zeichen (Quelle:
  https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref50/fblangref50-structure-identifiers.html ).

**Offene Maßnahme:** Die GUI-Pfade in `Manage_Config_Tables.ps1` (Auswahl, Sperre gegen das Entfernen
der letzten Tabelle) sind nicht automatisiert getestet.

**Restrisiko:** Niedrig – Namen mit Quote-, Klammer-, Semikolon- oder Leerzeichen werden vor jedem
SQL-Aufruf abgewiesen, und die Namen werden zusätzlich gequotet bzw. als Parameter übergeben. Wer
Schreibzugriff auf die Konfiguration hat, kann weiterhin *gültige* fremde Tabellennamen eintragen
(z. B. eine bestehende Zieltabelle per Prefix/Suffix überschreiben); das ist eine Rechte-, keine
Injection-Frage (Bedrohung 5).

---

## 2. Credential-Exposition und Klartext-Fallback (S3)

**Gefahr:**
- `Resolve-FirebirdCredentials` und `Resolve-MSSQLCredentials` (`SQLSyncCommon.psm1`) fallen auf
  `Firebird.Password` bzw. `MSSQL.Password` aus der Konfigurationsdatei zurück, wenn kein Eintrag
  im Credential Manager existiert. Das Passwort liegt dann im Klartext auf der Platte.
- `Manage_Config_Tables.ps1` legt bei jeder Änderung `config.json.<yyyyMMdd_HHmmss>.bak` an – ein
  enthaltenes Klartext-Passwort wird damit vervielfältigt und nie aufgeräumt.
- `config.sample.json` (Sektion `MSSQL`) enthält realistisch wirkende Beispielzugangsdaten und einen
  internen Servernamen im öffentlichen Repository; `Setup-ScheduledTasks.ps1` enthält interne Pfade
  und DB-Kürzel. Werte werden hier bewusst nicht zitiert.
- `Get-StoredCredential` liefert das Passwort als `string` zurück; es lebt bis Prozessende im
  Speicher des Sync-Prozesses (inkl. aller `-Parallel`-Runspaces).
- Die MSSQL-Verbindung setzt weder `Encrypt` noch `TrustServerCertificate`
  (`New-MSSQLConnectionString`); bei SQL-Authentifizierung hängt der Schutz des Login-Vorgangs und
  der Nutzdaten von der Server-Konfiguration ab (Force Encryption). Ob die Firebird-Verbindung
  Wire-Encryption nutzt, ist nicht im Code festgelegt (Treiber-/Server-Default, nicht verifiziert).

**Aktuelle Mitigation (im Code vorhanden):**
- Credential Manager ist erste Quelle; der Klartext-Fallback wird mit `WARNUNG: unsicher!` geloggt.
- `Setup_Credentials.ps1` schreibt per `CredWrite` in-process (Typ Generic, Persist LocalMachine).
  Früher stand das Passwort per `cmdkey /pass:` in der Kommandozeile – seit Commit 721d5e0 behoben.
- `New-FirebirdConnectionString` / `New-MSSQLConnectionString` bauen die Strings mit
  `System.Data.Common.DbConnectionStringBuilder`; Sonderzeichen (`;`, `=`, `'`, `"`) im Passwort
  können keine weiteren Schlüssel einschleusen.
- Logs (Transcript) enthalten nur Server, Datenbank und Credential-Quelle, nie Passwort oder
  vollständigen Connection-String.
- `.gitignore` schließt `/config*` (außer Sample/Schema), `*.bak`, `Logs/`, `*.clixml`, `.env` aus.

- `config.sample.json` enthält nur Platzhalterwerte; `Setup-ScheduledTasks.ps1` enthält keine
  internen Pfade oder Konfignamen mehr (Parameter mit generischen Defaults, I9).

**Offene Maßnahme:** Backlog: Klartext-Fallback
standardmäßig abschalten (Opt-in-Schalter), `.bak`-Rotation, `Encrypt=True` für MSSQL konfigurierbar
machen. Betrieb: siehe `docs/operations/SECRETS_MANAGEMENT.md`.

**Restrisiko:** Mittel – solange der Fallback existiert und die Beispielkonfiguration
realistische Werte zeigt, hängt der Schutz an Betriebsdisziplin.

---

## 3. Treiber-Supply-Chain und DLL-Hijacking (S4)

**Gefahr:** `Initialize-FirebirdDriver` (`SQLSyncCommon.psm1`) lädt
`FirebirdSql.Data.FirebirdClient.dll` per `Add-Type -Path` in den Sync-Prozess. Kandidatenreihenfolge:
1. `Firebird.DllPath` aus der Konfiguration (absolut oder relativ zum Skriptordner),
2. `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\lib\net8.0\...`,
3. `...\lib\netstandard2.1\...`.

Vor I7 (Repo-Stand bis v2.15) wurde nur eine **frisch heruntergeladene** DLL gegen den SHA-256-Wert geprüft; eine
bereits vorhandene DLL in einem der Kandidatenpfade – oder ein manipulierter `DllPath` – wurde
**ungeprüft** geladen. Wer Schreibrechte auf `%ProgramData%\SQLSync\Drivers\...`, den Skriptordner
oder die Konfigurationsdatei hat, hätte so Code im Kontext des Sync-Kontos (mit Zugriff auf beide
Datenbanken und den Credential Manager dieses Kontos) ausführen können. Seit I7 (2026-10-09)
mitigiert, siehe unten.

**Aktuelle Mitigation (im Code vorhanden):**
- Fest gepinnte Paketversion 10.3.4, Download nur über HTTPS (TLS 1.2) von `globalcdn.nuget.org`.
  `ServicePointManager.SecurityProtocol` wird nur für den Download gesetzt und danach
  wiederhergestellt (seit I7).
- **Seit I7 (2026-10-09):** `Initialize-FirebirdDriver` prüft **jede** DLL vor `Add-Type` per
  SHA-256 – frischer Download, bereits vorhandene DLL in `%ProgramData%\SQLSync\Drivers\…` und per
  `Firebird.DllPath` konfigurierte DLL. Zulässig sind nur die Original-Hashes aus dem NuGet-Paket
  10.3.4 (am 2026-10-09 aus dem offiziellen Paket von nuget.org nachgerechnet):
  - `lib\net8.0`: `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05`
  - `lib\netstandard2.1`: `8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A`
- Abweichung → `throw` „SHA-256 der Treiber-DLL (vorhanden|Download) stimmt nicht … Treiber wurde
  NICHT geladen“ → Sync Exit 7 (`Test-SQLSyncConnections.ps1` 4, `Get_Firebird_Schema.ps1` und
  `Manage_Config_Tables.ps1` 3), **vor** jeder Datenbankverbindung. Bei einer Download-Abweichung
  wird der Ordner verworfen.
- Abweichende DLL (andere Treiberversion) nur mit explizit erwartetem Hash: Konfigschlüssel
  `Firebird.DllSha256` (Schema `^[A-Fa-f0-9]{64}$`) bzw. Parameter `-ExpectedSha256`; dann gilt
  ausschließlich dieser Hash. Alle vier Skripte reichen ihn durch.
- Download nur mit Administratorrechten (`Test-SQLSyncIsAdministrator`); `%ProgramData%`-Unterordner
  erbt standardmäßig restriktive Schreibrechte (nicht vom Code gesetzt; Prüfung per `icacls` in
  `docs/operations/SETUP.md`).
- Unit-Tests: Download-, Admin- und Hash-Pfad per Mock (8 Treiber-Fälle). Echter Lauf am
  2026-10-09: Original-DLL über `DllPath` → „geladen (SHA-256 geprüft)“, Exit 0; manipulierte Kopie
  (1 Byte angehängt) → Exit 7 vor jeder DB-Verbindung.
- Erkennung vor dem Deployment (seit 2026-10-09): `Test-SQLSyncConnections.ps1 -PreDeploy` prüft die
  DLL mit `Test-FirebirdDriverIntegrity` gegen dieselben Kandidatenpfade und Hashes, ohne sie zu
  laden; eine nicht erlaubte DLL ergibt `FEHLER` und Exit 6. Konstanten zentral in
  `$script:FirebirdDriver` (eine Stelle für Version, URL und Hashes).
- `*.dll` und `*.nupkg` sind gitignored.

**Offene Maßnahme / Grenze:** Ist die Assembly `FirebirdSql.Data.FirebirdClient` in der Sitzung
bereits geladen (z. B. durch ein anderes Modul im selben PowerShell-Prozess), wird sie **ohne**
Prüfung weiterverwendet. Im Task-Scheduler-Betrieb (`pwsh -NoProfile`, frischer Prozess) tritt das
nicht auf. Wer Schreibzugriff auf die Konfiguration hat, kann über `Firebird.DllSha256` einen
eigenen Hash vorgeben – das ist eine Rechte-Frage (Bedrohung 5, Skriptordner nur für Admins und das
Sync-Konto beschreibbar). Prüfung der aktuellen Advisories zum Treiber:
`docs/security/DEPENDENCY_AUDIT.md`.

**Restrisiko:** Niedrig – eine ausgetauschte DLL in `%ProgramData%` oder hinter `DllPath` wird nicht
mehr geladen (Fail-Fast, Exit 7). Code-Ausführung über den Treiber verlangt jetzt Schreibzugriff
auf die Konfiguration **und** einen Ablageort der DLL oder eine in der Sitzung vorgeladene Assembly;
beides setzt bereits weitgehende lokale Rechte voraus.

---

## 4. Unbemerkte Fehlschläge und stiller Datenverlust (S1, S5, S6)

**Gefahr:** Integritätsbedrohung – Zieldaten werden falsch oder unvollständig, ohne dass es
jemand bemerkt:
- **S1:** Bis Version 2.10 endete `Sync_Firebird_MSSQL_AutoSchema.ps1` immer mit Exit-Code 0,
  auch wenn Tabellen den Status `Fehler` oder der Sanity Check `FEHLER` hatte; Batch-Fehler beim
  Installieren von `sql_server_setup.sql` waren nur Warnungen. Der Task Scheduler meldete Erfolg.
  Seit v2.11 (I2) im Code mitigiert, siehe unten.
- **S5:** Bis Version 2.13 bildete das Typmapping im Sync-Skript `Decimal` fest auf `DECIMAL(18,4)`
  ab – Werte mit mehr als 4 Nachkommastellen wurden gerundet, Werte mit Precision > 18 liefen über
  (Fehler oder Verlust). Seit v2.14 (I5) für neu angelegte Tabellen mitigiert, siehe unten;
  bestehende Zieltabellen behalten ihren Typ.
- **S6:** Bis Version 2.16 war das Wasserzeichen strikt `> MAX(ts)` der Zieltabelle; Sätze mit
  identischem Zeitstempel oder aus länger laufenden Firebird-Transaktionen wurden bis zum nächsten
  Full-Lauf übersprungen. Fiel die `MAX`-Abfrage aus, wurde still `1900-01-01` verwendet
  (Voll-Extrakt). Seit v2.18 (I8) weitgehend mitigiert, siehe unten.
- Löschungen werden standardmäßig nicht repliziert (S7, by design; `CleanupOrphans` optional).

**Aktuelle Mitigation (im Code vorhanden):**
- Sanity Check (`RunSanityCheck`, Default an) vergleicht `COUNT` Firebird vs. Ziel und markiert
  `WARNUNG`/`FEHLER` in der Zusammenfassung und im Transcript-Log.
- Retry-Schleife pro Tabelle (`MaxRetries`, `RetryDelaySeconds`).
- `sp_Merge_Generic` ist idempotent (MERGE auf ID); der wöchentliche Full-Lauf
  (`SQLSync_Firebird_Weekly_Full`) korrigiert Lücken aus S6.
- Abbruch mit Exit-Codes 1/2/5/7/9 bei Modul-, Konfig-, Credential-, Treiber- und
  Pre-Flight-Fehlern; seit I2 bricht auch ein fehlgeschlagener SQL-Batch aus
  `sql_server_setup.sql` den Pre-Flight ab (Exit 9).
- Seit I2: Laufende mit Exit-Code `10` bei mindestens einer Tabelle mit Status `Fehler` (oder
  fehlendem Ergebnis) und `11` bei Sanity `FEHLER` (abschaltbar per `General.FailOnSanityError`),
  ermittelt durch `Get-SyncExitCode` (Unit-Tests vorhanden). `LastTaskResult` im Task Scheduler
  zeigt damit `0xA`/`0xB`. Sanity `WARNUNG (+n)` bleibt Exit 0.
- Seit v2.14 (I5): `ConvertTo-SqlServerType` übernimmt `NumericPrecision`/`NumericScale` aus dem
  Firebird-Schema (`DECIMAL(p,s)`, p höchstens 38; Fallback `DECIMAL(18,4)` nur ohne
  Schema-Info); der Sync nutzt die Modulfunktion statt einer eigenen Kopie. Unit-Tests vorhanden;
  Integrationslauf am 2026-10-08: `decimal(15,6)` im Ziel, Summe über 62.523 Zeilen bis zur 6.
  Nachkommastelle identisch mit Firebird. Der Sync ändert keine bestehenden Tabellen –
  Zieltabellen aus v2.13 oder älter runden weiter, bis sie migriert sind
  (`operations/RUNBOOK.md`, „Nachkommastellen im Ziel gerundet“).
- Erkennung des S5-Altbestands (seit 2026-10-09): `Test-SQLSyncConnections.ps1 -PreDeploy` vergleicht
  rein lesend die Dezimalspalten der konfigurierten Tabellen (Firebird-Metadaten) mit den
  Zieltabellen (`Find-SQLSyncDecimalTruncation`) und meldet jede Zielspalte mit kleinerer Precision
  oder Scale als `WARNUNG`. In der Testumgebung erprobt: künstlich verkleinerte Spalte erkannt,
  Korrektur per RUNBOOK stellte die Werte wieder her.
- Seit v2.18 (I8): Der Incremental-Extrakt liest ab Wasserzeichen minus Überlappungsfenster
  (`General.IncrementalOverlapMinutes`, Default 10 Min, 0–1440), inklusive (`>= @LastDate`). Spät
  committete Sätze mit Zeitstempel ≤ Wasserzeichen werden nachgeholt, solange die Verzögerung
  kleiner als das Fenster ist. Scheitert die `MAX`-Abfrage auf eine vorhandene Zieltabelle, endet
  die Tabelle nach den Retries mit `Fehler` (Exit 10) statt still voll zu laden. Unit-Tests
  vorhanden; Integrationslauf am 2026-10-09: ein im Ziel gelöschter Satz knapp unter dem
  Wasserzeichen wurde mit v2.18 wiederhergestellt (Sanity `OK`), mit v2.16 nicht (Sanity `FEHLER`).

**Offene Maßnahme:** (I2 abgenommen 2026-10-08: echter Lauf Exit 10, Aufgabenplanung `0xA`.) Migration von Zieltabellen aus v2.13 oder
älter je Installation (S5-Altbestand; Erkennung per `-PreDeploy`, Korrektur bleibt Betriebsaufgabe). Backlog: strukturiertes
Run-Ergebnis (JSON/CSV) und Alarmierung auf `LastTaskResult`.

**Restrisiko:** Mittel – Tabellen- und Sanity-Fehler sind über den Exit-Code erkennbar (Abnahme
offen), es gibt aber keine aktive Alarmierung; von S6 bleiben nur Commit-Verzögerungen länger als das
Überlappungsfenster offen (bis zum Weekly Full), ebenso S5 für nicht migrierte
Zieltabellen aus v2.13 oder älter – beides erzeugt nicht immer einen Sanity-`FEHLER` (z. B.
gerundete Nachkommastellen bei gleicher Zeilenzahl).

---

## 5. Übermäßige Rechte von Konto, Datenbank-Login und Ausführungsumgebung (S13)

**Gefahr:**
- **Pre-Flight** im Hauptskript legt die Zieldatenbank über `master` an (`CREATE DATABASE` +
  `RECOVERY SIMPLE`) – das MSSQL-Login braucht dafür `dbcreator`, sobald die DB fehlt.
- Der Lauf benötigt DDL in der Ziel-DB (`CREATE/DROP TABLE`, `TRUNCATE`, `CREATE OR ALTER
  PROCEDURE`, PK-Anlage) und Bulk-Insert. Zusammen mit Bedrohung 1 vergrößert das den Schaden.
- Firebird-Fallback-Benutzer ist `SYSDBA`, wenn `Firebird.User` fehlt (`Resolve-FirebirdCredentials`)
  – Vollzugriff auf die ERP-Datenbank, obwohl nur lesend gearbeitet wird. Seit CVE-2026-40342
  (Bedrohung 6) wiegt das schwerer: Ein Konto mit `CREATE FUNCTION` (z. B. `SYSDBA`) kann auf einem
  ungepatchten Firebird-Server Code als OS-Konto des Servers ausführen; ein Leck der
  Sync-Credentials würde damit zur Codeausführung auf dem ERP-Datenbankserver.
- `Setup-ScheduledTasks.ps1` registriert die Tasks per Default unter dem **aktuellen interaktiven
  Benutzer** mit gespeichertem Windows-Passwort (`Register-ScheduledTask -User ... -Password ...`)
  und startet `pwsh -NoProfile -ExecutionPolicy Bypass`. Die Credential-Manager-Einträge sind an
  genau dieses Konto gebunden.

**Aktuelle Mitigation (im Code vorhanden):**
- `Setup-ScheduledTasks.ps1` prüft Adminrechte zur Laufzeit nur für die Registrierung (Exit 1 ohne
  Adminrechte; `-WhatIf` zeigt die Task-Definitionen ohne Adminrechte und ohne Passwortabfrage);
  der Task selbst wird ohne erhöhten Run-Level registriert.
- Ausführungskonto wählbar: `-RunAsUser` (dediziertes Dienstkonto) oder `-GmsaAccount` (gMSA,
  kein gespeichertes Passwort). Grenze: Credential-Manager-Einträge sind kontogebunden, mit gMSA
  ist daher vor allem Integrated Security für SQL Server praktikabel; Firebird-Credentials müssten
  im Kontext des gMSA angelegt werden (`docs/architecture/CREDENTIAL_STRATEGY.md`).
- `-ExecutionPolicy Bypass` betrifft nur den einen Prozess; die Skripte werden aus einem lokalen
  Ordner gestartet.
- `MultipleInstances IgnoreNew` verhindert parallele Läufe desselben Tasks.
- Integrated Security für MSSQL wird unterstützt (kein gespeichertes SQL-Passwort nötig).
- Erkennung (seit 2026-10-09): `Test-SQLSyncConnections.ps1 -PreDeploy` meldet eine Firebird-Anmeldung
  als `SYSDBA` als `WARNUNG` mit Empfehlung eines Lesekontos. Weitere Rechte (`dbcreator`,
  `CREATE FUNCTION` eines anderen Kontos, Task-Konto) prüft es nicht.

**Offene Maßnahme:** Betrieb (ohne Code-Änderung umsetzbar): Tasks auf Dienstkonto oder gMSA
umstellen (Default bleibt der aufrufende Benutzer); Datenbank vorab anlegen und `dbcreator` entziehen; dediziertes
Firebird-**Lesekonto** statt `SYSDBA` (nur `SELECT` auf die konfigurierten Tabellen, keine DDL,
kein `CREATE FUNCTION` – Begründung CVE-2026-40342, Anleitung `docs/operations/SETUP.md`); MSSQL-Login auf `db_ddladmin` +
`db_datawriter` + `db_datareader` der Ziel-DB beschränken; Skriptordner nur für Admins und das
Sync-Konto beschreibbar. Details: `docs/operations/TASK_SCHEDULER.md`,
`docs/security/AUTHENTICATION.md`.

**Restrisiko:** Mittel – abhängig von der tatsächlichen Rechtevergabe beim Betreiber (nicht aus dem
Code ableitbar).

---

## 6. Schwachstellen des Firebird-Servers (CVE-2026-34232, CVE-2026-40342)

**Gefahr:** Am 2026-10-08 (Security-Sweep, Ereignis-Auslöser) gefunden: CVE-2026-34232
(CVSS 7.5, GHSA-7jq3-6j3c-5cm2) – ein unauthentifizierter Angreifer kann den Firebird-Server über ein
präpariertes `op_response`-Paket zum Absturz bringen. Betroffen sind Firebird-Server < 5.0.4,
< 4.0.7 und < 3.0.14 (Quelle: https://nvd.nist.gov/vuln/detail/cve-2026-34232 ).
Mindestens ein intern eingesetzter Firebird-Server ist betroffen (Details nur in `docs/local/ENVIRONMENT.md`); die Version des produktiven
ERP-Firebird ist nicht bekannt. Wirkung auf dieses Projekt: Verfügbarkeit – während eines Absturzes
schlagen Extrakt und Sanity Check fehl (Exit 10), und das ERP selbst ist ebenfalls nicht verfügbar.
Die Schwachstelle liegt im Server, nicht im Sync-Code; für den Client-Treiber
`FirebirdSql.Data.FirebirdClient` 10.3.4 wurde kein CVE gefunden (erneut geprüft 2026-10-09).

**Neu am 2026-10-09 (Security-Sweep, Ereignis-Auslöser I7):** CVE-2026-40342 (CVSS 9.9) – ein
**authentifizierter** Benutzer mit dem Recht `CREATE FUNCTION` kann über einen präparierten
`ENGINE`-Namen (Path Traversal) eine beliebige Bibliothek laden und damit Code als OS-Konto des
Firebird-Servers ausführen. Betroffen sind ebenfalls Firebird-Server < 5.0.4, < 4.0.7 und
< 3.0.14 (Quellen: https://nvd.nist.gov/vuln/detail/CVE-2026-40342 ,
https://osv.dev/vulnerability/CVE-2026-40342 ). Bezug zum Projekt: Das Sync-Konto hat Zugangsdaten
zum Firebird-Server (Credential Manager oder Klartext-Fallback, Bedrohung 2). Ist es `SYSDBA` oder
hat es `CREATE FUNCTION`, wird ein Credential-Leak zur Codeausführung auf dem ERP-Datenbankserver
(Vertraulichkeit, Integrität und Verfügbarkeit).

**Aktuelle Mitigation (im Code vorhanden):**
- Keine im Code möglich. Der Sync erkennt den Ausfall (Tabellenstatus `Fehler`, Exit 10) und
  wiederholt pro Tabelle (`MaxRetries`).
- Der Sync liest nur (`SELECT`); er braucht weder DDL noch `CREATE FUNCTION` in Firebird – ein
  Lesekonto ist ohne Code-Änderung möglich (`Firebird.CredentialTarget` bzw. `Firebird.User`).
- Ob der Firebird-Port nur im internen Netz erreichbar ist, ist nicht aus dem Code ableitbar
  (nicht verifiziert).
- Erkennung (seit 2026-10-09): `Test-SQLSyncConnections.ps1 -PreDeploy` liest die Serverversion und
  gleicht sie mit `Get-FirebirdServerAdvisory` gegen die im Code gepflegte Liste
  (`$script:FirebirdServerAdvisories`) ab; jede betroffene CVE erscheint als `WARNUNG` mit der ersten
  behobenen Version, eine nicht auswertbare Version als Hinweis zur manuellen Prüfung. Die Liste ist
  nur so aktuell wie der letzte Sweep (`docs/security/DEPENDENCY_AUDIT.md`).

**Offene Maßnahme (Betrieb):** Firebird-Server auf ≥ 5.0.4 (bzw. ≥ 4.0.7 / ≥ 3.0.14) aktualisieren –
behebt beide CVEs –, zuerst Firebird-Testserver, dann produktiven ERP-Server; produktive Version mit
`Test-SQLSyncConnections.ps1 -PreDeploy` erfassen und bewerten. Für den Sync ein reines Firebird-Lesekonto statt `SYSDBA`
einrichten (nur `SELECT` auf die konfigurierten Tabellen, keine DDL, kein `CREATE FUNCTION`;
Bedrohung 5, `docs/operations/SETUP.md`). Bis zum Update Firebird-Port per Firewall auf die
benötigten Clients beschränken. Nachverfolgung in `docs/security/DEPENDENCY_AUDIT.md`.

**Restrisiko:** Hoch, solange der Server ungepatcht ist **und** der Sync `SYSDBA` (oder ein Konto
mit `CREATE FUNCTION`) nutzt – dann reicht ein Leck der Sync-Credentials für Codeausführung auf
dem ERP-Datenbankserver (CVE-2026-40342). Mit Lesekonto sinkt es auf Mittel: CVE-2026-34232 erlaubt
weiterhin jedem Host mit Netzzugang zum Firebird-Port, den Server abstürzen zu lassen
(Verfügbarkeit). Nach dem Server-Update: Niedrig.

---

## 7. CI-Workflow auf GitHub Actions (seit I10b)

**Gefahr:** Der Workflow führt fremden Code aus (Action `actions/checkout`, Module aus der PSGallery) und
bekommt ein `GITHUB_TOKEN`. Ein kompromittiertes Tag einer Action oder ein Workflow mit Schreibrechten
könnte das öffentliche Repo verändern.

**Maßnahmen:** `actions/checkout` per vollständigem Commit-SHA gepinnt (Tag nur als Kommentar);
`permissions: contents: read` für den ganzen Workflow; `persist-credentials: false` (Token bleibt nicht im
Arbeitsverzeichnis); keine Secrets, kein `pull_request_target`; Pester und PSScriptAnalyzer mit fester
Version aus `tests/RequiredModules.psd1`. Die CI berührt weder Datenbanken noch den Betriebsserver.

**Restrisiko:** Niedrig. Die PSGallery-Module sind per Version, nicht per Hash gepinnt; die
Update-Prüfung der Action steht in `DEPENDENCY_AUDIT.md`.

---

## Schwachstellen-Katalog (S-IDs)

Die Kürzel `S1`–`S13` werden in `docs/features/`, `docs/operations/`, `docs/security/` und
`docs/testing/` als stabile Referenz auf die bei der Initialisierung (I1, Code-Stand `721d5e0`)
gefundenen Schwachstellen verwendet. Zuordnung:

| S-ID | Kurzbeschreibung | Bekanntes Problem | Inkrement |
|---|---|---|---|
| S1 | Sync endet mit Exit 0 trotz Tabellenfehlern; SP-Batch-Fehler nur Warnung | K1 | I2 (erledigt, abgenommen 2026-10-08) |
| S2 | SQL-Identifier ungeprüft in SQL interpoliert | — | I4 (erledigt 2026-10-08) |
| S3 | Klartext-Passwort-Fallback, `*.bak`, interne Namen/Beispielwerte im Repo | — | I9 (interne Namen/Beispielwerte erledigt 2026-10-08); Klartext-Fallback und `*.bak` offen (`BACKLOG.md`) |
| S4 | Vorhandene/konfigurierte Treiber-DLL ohne Hash-Prüfung | — | I7 (erledigt 2026-10-09) |
| S5 | `DECIMAL(18,4)` fest → Präzisionsverlust; Mapping im Sync-Skript ohne `Guid` | K2 | I5 (erledigt; Altbestand: Erkennung per `Test-SQLSyncConnections.ps1 -PreDeploy`, Korrektur siehe RUNBOOK) |
| S6 | Wasserzeichen strikt `> MAX(ts)` | K3 | I8 (erledigt 2026-10-09: Überlappungsfenster; Rest: Verzögerungen länger als das Fenster → Weekly Full) |
| S7 | Löschungen nicht repliziert; Orphan-Cleanup nur numerische IDs | K4, K5 | by design / `BACKLOG.md` |
| S8 | Doppelte Logik (Typmapping, Strategie, Configpfad) | K8 | I5/I6 (erledigt: Typmapping/Strategie I5 2026-10-08, Configpfad `Resolve-SQLSyncConfigPath` I6 2026-10-09) |
| S9 | `config.schema.json` wird nie geprüft | K7 | I6 (erledigt 2026-10-09; Fail-Fast in allen vier Skripten) |
| S10 | Keine automatisierten Tests | — | I3 (erledigt 2026-10-08) |
| S11 | Schema-Drift (neue Spalten) nicht behandelt | K6 | `BACKLOG.md` |
| S12 | Doku-/Repo-Drift, ungenutztes `MSSQL.Port` | K7, K9 | I10a (Port), I10c (Doku) |
| S13 | Tasks als interaktiver Benutzer mit gespeichertem Passwort, breite DB-Rechte | — | I9 (Option Dienstkonto/gMSA vorhanden 2026-10-08; Umstellung und DB-Rechte sind Betrieb) |

Hinweis: `S1`–`S3` in `docs/REFLECTION.md` bezeichnen dagegen die
Eval-Szenarien des Template-Repos, nicht diese Schwachstellen.

---

## Nicht zutreffende Bedrohungsklassen

| Klasse | Begründung |
|---|---|
| Remote-Ausführung (WinRM, `Invoke-Command`, SSH) | Trifft nicht zu – das Projekt nutzt keine Remote-Sessions. |
| Web-/API-Angriffsfläche | Trifft nicht zu – kein Listener, keine HTTP-Schnittstelle. |
| Indirect Prompt Injection (LLM01) | Trifft nicht zu – keine LLM-Nutzung, keine Anweisungstexte im Code gefunden. |
| DPAPI-Dateien (`Export-Clixml`) | Trifft nicht zu – Credentials liegen im Windows Credential Manager. |

---

## Hinweise

- Dieses Dokument wird bei jeder neuen Funktion geprüft, die externe Eingaben verarbeitet
  oder auf sensible Ressourcen zugreift (neue Konfigurationsschlüssel, neue SQL-Statements,
  neue Downloads).
- Neue Bedrohungen als ADR dokumentieren, wenn sie eine Architekturentscheidung auslösen.
- Letzter Security-Sweep: 2026-10-09 (Ereignis-Auslöser I7 – Treiber-Integrität; Ergebnis:
  FirebirdClient 10.3.4 weiterhin aktuell ohne Client-Advisory, neu CVE-2026-40342 in Bedrohung 6,
  Lesekonto-Empfehlung in Bedrohung 5). Vorheriger Sweep: 2026-10-08 (I4, Bedrohung 1 und 6).
  Nächster Security-Sweep (Web-Advisories, `principles/SECURITY_CURRENCY.md`): 2026-10-22.
