# Feature: Firebird → MS SQL Sync (Sync_Firebird_MSSQL_AutoSchema.ps1)

Hauptfeature des Projekts. Erstellt auf Basis von `features/FEATURE-template.md`.
Stand: Skriptversion 2.18 (2026-10-09), Modul `SQLSyncCommon.psm1` 1.0.0; Erstfassung auf Commit 721d5e0.

---

## Zweck

Repliziert die in der Konfigdatei gelisteten Tabellen einer Firebird-Datenbank
(z. B. ERP-Tabellen wie BKUNDE, BLIEF, BSA) parallel, inkrementell und per
`SqlBulkCopy` in eine MS-SQL-Server-Datenbank: Firebird → Staging-Tabelle
`STG_<Quelltabelle>` → MERGE in die Zieltabelle `<Prefix><Quelltabelle><Suffix>`.

---

## Technologie / Abhängigkeiten

- PowerShell 7.0+ (`ForEach-Object -Parallel`, ternärer Operator), Windows
- `FirebirdSql.Data.FirebirdClient` 10.3.4 (NuGet, net8.0; einmaliger Download
  nach `%ProgramData%\SQLSync\Drivers\...` als Admin; jede DLL wird vor dem Laden
  per SHA-256 gegen die Original-Hashes des Pakets bzw. `Firebird.DllSha256` geprüft)
- `System.Data.SqlClient` (in PowerShell 7 enthalten; von Microsoft zugunsten
  `Microsoft.Data.SqlClient` abgekündigt, Migration im Backlog)
- Firebird-Server 2.5+/3.x; MS SQL Server 2017+ (`STRING_AGG`, `CREATE OR ALTER`)
- `SQLSyncCommon.psm1`: `Get-SQLSyncConfig`, `Resolve-FirebirdCredentials`,
  `Resolve-MSSQLCredentials`, `Initialize-FirebirdDriver`,
  `New-FirebirdConnectionString`, `New-MSSQLConnectionString`
- `sql_server_setup.sql`: `dbo.sp_Merge_Generic`
- Windows Credential Manager (Targets `SQLSync_Firebird`, `SQLSync_MSSQL` oder per
  `*.CredentialTarget` konfiguriert)

---

## Parameter

| Parameter | Typ | Pflicht | Default | Validierung | Beschreibung |
|-----------|-----|---------|---------|-------------|-------------|
| `-ConfigFile` | `[string]` | Nein | `config.json` im Skriptordner | Inhalt gegen `config.schema.json` (Verstoß → exit 2); Auflösung per `Resolve-SQLSyncConfigPath`: leer → `config.json` im Skriptordner, existierender Pfad → relativ zum Skriptordner → unverändert (führt dann zu exit 2) | Pfad zur JSON-Konfigdatei = Job-Profil. Der Dateiname ohne Endung geht in den Lognamen ein. |

Kein `-WhatIf`, kein `-Verbose`-Sonderverhalten, keine Umgebungsvariablen.
Alles Weitere steuert die Konfigdatei.

### Konfigschalter (Auszug, Defaults aus `Get-SQLSyncConfig`)

Vollständige Referenz: `architecture/CONFIGURATION.md`.

| Schlüssel | Default | Wirkung |
|---|---|---|
| `General.GlobalTimeout` | `7200` | Timeout in Sekunden für SQL-Befehle und BulkCopy (> 0) |
| `General.NumberOfThreads` | `4` | `-ThrottleLimit` der Parallelverarbeitung (Tabellen gleichzeitig) |
| `General.MaxRetries` / `RetryDelaySeconds` | `3` / `10` | Wiederholungen pro Tabelle (insgesamt `MaxRetries + 1` Versuche) und Wartezeit |
| `General.RecreateStagingTable` | `false` | Staging-Tabelle bei jedem Lauf droppen und aus aktuellem Firebird-Schema neu anlegen |
| `General.ForceFullSync` | `false` | Incremental → `FullMerge (Forced)`: Ziel `TRUNCATE` + Voll-Load + MERGE |
| `General.RecreateStoredProcedure` | `false` | `sp_Merge_Generic` im Pre-Flight auf jeden Fall neu installieren |
| `General.RunSanityCheck` | `true` | `COUNT(*)`-Vergleich Quelle/Ziel pro Tabelle |
| `General.FailOnSanityError` | `true` | Sanity `FEHLER` → Exit-Code `11`; `false` = nur im Log |
| `General.CleanupOrphans` | `false` | Im Ziel Zeilen löschen, deren ID in Firebird nicht mehr existiert |
| `General.OrphanCleanupBatchSize` | `50000` | BatchSize beim Laden der IDs (≥ 1000) |
| `General.IncrementalOverlapMinutes` | `10` | Überlappungsfenster des Incremental-Extrakts in Minuten (0–1440): gelesen wird ab Wasserzeichen minus Fenster |
| `General.DeleteLogOlderThanDays` | `30` | Log-Rotation, `0` = aus |
| `General.IdColumn` | `"ID"` | Standard-ID-Spalte |
| `General.TimestampColumns` | `["GESPEICHERT"]` | Kandidaten für die Timestamp-Spalte, erste vorhandene gewinnt |
| `Firebird.*` | Port `3050`, Charset `UTF8` | `Server`, `Database`, `DllPath` (optional), `DllSha256` (optional, nur für eine abweichende Treiber-DLL), `CredentialTarget` (Default `SQLSync_Firebird`), Fallback `User`/`Password` |
| `MSSQL.*` | `"Integrated Security": false`, `Prefix`/`Suffix` `""` | `Server`, `Database`, `CredentialTarget` (Default `SQLSync_MSSQL`, z. B. ein Eintrag pro Server), Fallback `Username`/`Password`; `Port` wird ignoriert |
| `Tables` | – (Pflicht, nicht leer) | Liste der Quelltabellen |
| `TableOverrides.<TAB>` | – | `IdColumn` und/oder `TimestampColumn` je Tabelle |

**Namensregeln (seit v2.12):** Tabellen- und Spaltennamen (`Tables`, `General.IdColumn`,
`General.TimestampColumns`, `TableOverrides`-Schlüssel und -Werte) sowie `MSSQL.Database`,
`MSSQL.Prefix`/`Suffix` dürfen nur `A-Z`, `a-z`, `0-9`, `_` und `$` enthalten und höchstens 63 Zeichen
lang sein; Prefix + Tabelle + Suffix höchstens 128 Zeichen. Leer erlaubt nur bei `MSSQL.Database`,
Prefix/Suffix und den Override-Spalten. Verstoß → `Ungültiger Name in '<Feld>': …`, exit 2.
Details: `architecture/CONFIGURATION.md`.

---

## Ablauf

Vorbereitung (einmal pro Lauf, sequentiell):

1. Modul `SQLSyncCommon.psm1` laden (fehlt → exit 1).
2. Konfigpfad auflösen, Transcript starten:
   `Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log`.
3. `Get-SQLSyncConfig -SchemaPath <Skriptordner>\config.schema.json`: laden, gegen das
   Schema prüfen (Typen, Pflichtfelder, Grenzen, unbekannte Schlüssel; Meldung mit JSON-Pfad je
   Verstoß), Defaults setzen, validieren inkl. Namensregeln (`Assert-SqlIdentifier`).
   Fehler → exit 2, vor jeder Datenbankverbindung. Fehlt die Schema-Datei → nur Warnung.
4. Credentials auflösen. Firebird: Credential Manager (`Firebird.CredentialTarget`,
   Default `SQLSync_Firebird`) → Konfig-Passwort (Warnung). MSSQL: Integrated
   Security → Credential Manager (`MSSQL.CredentialTarget`, Default `SQLSync_MSSQL`) →
   Konfig-Passwort (Warnung). Fehler → exit 5.
5. Treiber laden (`Initialize-FirebirdDriver -DllPath … -ExpectedSha256 …`): bereits
   geladene Assembly weiterverwenden (ohne Prüfung), sonst DLL suchen (`DllPath`,
   `%ProgramData%\…\lib\net8.0`, `…\lib\netstandard2.1`), fehlt sie → als Admin von
   NuGet laden; **jede** DLL vor `Add-Type` per SHA-256 prüfen (Original-Hashes
   `lib\net8.0`/`lib\netstandard2.1` des Pakets 10.3.4, oder nur `Firebird.DllSha256`).
   Abweichung, fehlende Adminrechte oder Ladefehler → exit 7, vor jeder
   Datenbankverbindung.
6. Pre-Flight: Ziel-DB über `master` prüfen und ggf. mit `RECOVERY SIMPLE`
   anlegen; `sp_Merge_Generic` neu installieren, wenn sie fehlt, nicht genau 4
   Parameter hat oder `RecreateStoredProcedure` gesetzt ist. Fehler → exit 9
   (auch der Fehler eines einzelnen SQL-Batches; nur „Database … already
   exists" wird ignoriert).

Pro Tabelle (parallel, `ThrottleLimit = NumberOfThreads`, mit Retry-Schleife;
jeder Versuch öffnet eigene Verbindungen und schließt sie im `finally`):

- **A – Analyse:** Der Parallel-Block importiert zuerst das Modul
  (`Import-Module $using:ModulePath`), weil Runspaces von `ForEach-Object -Parallel`
  es nicht erben. `SELECT FIRST 1 *` mit `SchemaOnly` liest die Spalten;
  `Get-TableColumnConfig` bestimmt ID-Spalte (`TableOverrides.<TAB>.IdColumn` oder
  `IdColumn`), Timestamp-Spalte (Override oder erste vorhandene aus
  `TimestampColumns`) und daraus die Strategie.
- **B – Staging:** `STG_<Tabelle>` anlegen, falls sie fehlt oder
  `RecreateStagingTable` gesetzt ist (Typmapping per `ConvertTo-SqlServerType`, siehe
  „Typmapping“, ID-Spalte `NOT NULL`).
- **C – Extrakt:** Incremental: Wasserzeichen = `MAX(<ts>)` der Zieltabelle
  (`Get-SQLSyncIncrementalWatermark`; Zieltabelle fehlt → Info
  `(Erstlauf (Zieltabelle fehlt) - Vollabzug)`, Zieltabelle leer → Info
  `(Kein Wasserzeichen (Zieltabelle leer oder Zeitstempel NULL) - Vollabzug)`, jeweils ab `1900-01-01`; scheitert die
  `MAX`-Abfrage auf eine vorhandene Zieltabelle → Exception, Retry, ggf. Status
  `Fehler`). Untergrenze `@LastDate` = Wasserzeichen minus
  `General.IncrementalOverlapMinutes` (`Get-SQLSyncIncrementalLowerBound`),
  Firebird-Abfrage `WHERE <ts> >= @LastDate` (inklusive, parametrisiert; bis v2.16
  strikt `> MAX(ts)`). Sonst `SELECT *`. Beide Abfragen liefert
  `Get-SQLSyncExtractQuery`.
- **D – Load:** Staging `TRUNCATE` (entfällt bei frisch angelegter Staging),
  `SqlBulkCopy` mit Spaltenzuordnung nach Namen.
- **E – Merge/Struktur:** Zieltabelle per `SELECT * INTO ... WHERE 1=0` aus
  Staging anlegen, falls sie fehlt; PK auf ID-Spalte nachrüsten (Ziel und
  Staging). Nur wenn Staging Zeilen enthält: Snapshot → `TRUNCATE` Ziel +
  `INSERT ... SELECT *`; sonst (bei ForceFullSync vorher `TRUNCATE` Ziel)
  `sp_Merge_Generic` als Stored-Procedure-Aufruf mit `SqlParameter`n (ohne
  Timestamp-Spalte wird `DBNull.Value` übergeben; Update nur bei abweichendem
  Zeitstempel, Insert neuer IDs, **kein** Delete).
- **G – Orphan-Cleanup** (nur `CleanupOrphans`, mit ID-Spalte, nicht bei
  Snapshot/FullMerge (Forced)): alle Firebird-IDs per BulkCopy in die
  Temp-Tabelle `#SourceIDs_<Tabelle>` (ID als `BIGINT`), dann
  `DELETE ... WHERE <id> NOT IN (...)`. Fehler landen nur in der Spalte Info.
- **H – Sanity** (nur `RunSanityCheck`): `COUNT(*)` Firebird vs. Ziel →
  `OK` / `WARNUNG (+n)` (Ziel hat mehr) / `FEHLER (-n)` (Ziel hat weniger).

(Ein Schritt F existiert im Code nicht.)

Abschluss: Zusammenfassungstabelle (`Format-Table`), Log-Rotation
`Sync_*.log` älter als `DeleteLogOlderThanDays`, dann `Get-SyncExitCode`
(Exit-Code aus den Tabellenergebnissen), Zeile `ERGEBNIS: OK (Exit-Code 0)`
bzw. `ERGEBNIS: FEHLER (Exit-Code N) - betroffene Tabellen: …`,
`Stop-Transcript`, `exit $ExitCode`.

### Sync-Strategien

| Strategie | Bedingung | Extrakt | Schreiben ins Ziel | Löschungen |
|---|---|---|---|---|
| `Incremental` | ID- **und** Timestamp-Spalte vorhanden | nur `ts >= MAX(ts) − IncrementalOverlapMinutes` im Ziel | MERGE (Upsert) | nein (nur mit CleanupOrphans) |
| `FullMerge` | ID vorhanden, keine Timestamp-Spalte | alle Zeilen | MERGE (Upsert, jede Zeile wird aktualisiert) | nein (nur mit CleanupOrphans) |
| `FullMerge (Forced)` | wäre Incremental, aber `ForceFullSync = true` | alle Zeilen | `TRUNCATE` Ziel + MERGE | implizit ja (Ziel wird neu befüllt) |
| `Snapshot` | keine ID-Spalte | alle Zeilen | `TRUNCATE` Ziel + `INSERT SELECT *` | implizit ja |

Hinweise: Bei `ForceFullSync` wird auch eine `FullMerge`-Tabelle vor dem MERGE
geleert (Label bleibt `FullMerge`). Liefert der Extrakt 0 Zeilen, wird das Ziel
bei keiner Strategie geleert.

### Ergebnis pro Tabelle

Objekt mit `Tabelle`, `Target`, `Status` (`Erfolg`/`Fehler`), `Strategie`,
`RowsLoaded`, `OrphansDeleted`, `FbTotal`, `SqlTotal`, `SanityCheck`,
`Duration`, `Speed`, `Info`, `Versuche`. Wird nur als Tabelle ins Transcript
ausgegeben, nicht als Datei persistiert.

### Typmapping

`ConvertTo-SqlServerType` (Modul) bildet beim Anlegen von `STG_<Tabelle>` jede Spalte
aus `GetSchemaTable` ab (`DataType`, `ColumnSize`, `NumericPrecision`, `NumericScale`).
Die Zieltabelle entsteht per `SELECT * INTO … WHERE 1=0` aus der Staging-Tabelle und
übernimmt deren Typen.

| .NET-Typ | SQL-Server-Typ |
|---|---|
| `Int16` / `Int32` / `Int64` | `SMALLINT` / `INT` / `BIGINT` |
| `String` | `NVARCHAR(n)` bei 1–4000 Zeichen, sonst `NVARCHAR(MAX)` |
| `DateTime` / `TimeSpan` | `DATETIME2` / `TIME` |
| `Decimal` | `DECIMAL(p,s)` aus Precision/Scale; p > 38 → 38; Precision fehlt, Scale bekannt → `DECIMAL(38,s)`; beides fehlt → Fallback `DECIMAL(18,4)` |
| `Double` / `Single` | `FLOAT` / `REAL` |
| `Byte[]` | `VARBINARY(MAX)` |
| `Boolean` | `BIT` |
| `Guid` | `UNIQUEIDENTIFIER` |
| sonstige | `NVARCHAR(MAX)` |

Belegt am 2026-10-08: Der Firebird-Provider meldet `NumericPrecision`/`NumericScale`
korrekt (z. B. 15/6); die Demo-Datenbank hat 915 Spalten mit Scale > 4. Im
Integrationslauf Firebird-Testserver → SQL-Testserver wurde eine Gewichtsspalte als
`decimal(15,6)` angelegt; die Summe über 62.523 Zeilen war in Firebird und SQL Server
bis zur 6. Nachkommastelle identisch, 956 Zeilen mit mehr als 4 Nachkommastellen wären
mit v2.13 gerundet worden.

**Migration bestehender Zieltabellen:** Der Sync ändert keine bestehenden Tabellen.
Zieltabellen, die mit v2.13 oder älter angelegt wurden, behalten `DECIMAL(18,4)` und
runden weiter – auch wenn die Staging-Tabelle mit korrektem Typ neu angelegt wird, denn
der MERGE schreibt in die alten Zieltypen. Prüfung und Korrektur je Tabelle:
`operations/RUNBOOK.md`, Störung „Nachkommastellen im Ziel gerundet“.

---

## Exit-Codes

`Sync_Firebird_MSSQL_AutoSchema.ps1`:

| Code | Bedeutung |
|---|---|
| `0` | Alle Tabellen `Erfolg`; Sanity `OK`, `N/A` oder `WARNUNG (+n)` |
| `1` | `SQLSyncCommon.psm1` fehlt (kein Log, Transcript noch nicht gestartet) |
| `2` | Konfiguration fehlt / ungültig (Parsefehler, Schema-Verstoß `Konfiguration verletzt das Schema (config.schema.json): …`, Namensregeln) |
| `5` | Credentials nicht auflösbar |
| `7` | Firebird-Treiber fehlt / Download, Hash oder Laden fehlgeschlagen |
| `9` | Pre-Flight (Ziel-DB oder Stored Procedure, inkl. fehlgeschlagener SQL-Batch aus `sql_server_setup.sql`) fehlgeschlagen |
| `10` | Mindestens eine Tabelle mit Status `Fehler`, oder weniger Ergebnisse als konfigurierte Tabellen (in der `ERGEBNIS`-Zeile als `<Name> (kein Ergebnis)`); Vorrang vor `11` |
| `11` | Keine Tabellenfehler, aber Sanity `FEHLER (-n)`; nur mit `General.FailOnSanityError = true` (Default) |

Seit Version 2.11 (Inkrement I2). Unit-getestet (`Get-SyncExitCode`); ein
End-to-End-Abnahme am 2026-10-08 bestanden (Exit 0 ohne Fehler, Exit 10 bei nicht existierender Tabelle, Task Scheduler `0xA`).

Hilfsskripte:

| Skript | Exit-Codes |
|---|---|
| `Test-SQLSyncConnections.ps1` | 0 OK (mit `-PreDeploy`: kein `FEHLER`, `WARNUNG`en zulässig), 1 Modul/Config fehlt oder ein Verbindungstest fehlgeschlagen, 2 Config ungültig (Parse, Schema, Namen), 3 Credentials, 4 Treiber, 6 `-PreDeploy` mit mindestens einem `FEHLER` |
| `Get_Firebird_Schema.ps1` | 0 OK, 1 Modul/Konfigdatei fehlt, 2 Config ungültig (Parse, Schema, Namen), 3 Treiber, 4 Analysefehler, 5 Credentials |
| `Manage_Config_Tables.ps1` | 0 sonst, 1 Modul/Config fehlt, 2 Config ungültig (Schema, Namen; vor GridView und Backup) oder FB-Metadaten nicht lesbar, 3 Treiber, 4 letzte Tabelle würde entfernt oder Backup fehlgeschlagen, 5 Credentials |

Achtung: Die Codes sind zwischen den Skripten **nicht** einheitlich (Treiber
= 7 / 4 / 3). I2 hat nur den Sync um die Codes `10`/`11` ergänzt; eine
Vereinheitlichung der Hilfsskripte ist nicht umgesetzt.

---

## Kritische Patterns

- Verbindungen pro Versuch neu öffnen und im `finally` schließen + disposen
  (kein Leak bei Retries).
- Firebird-Wasserzeichen als Parameter `@LastDate` übergeben, nicht als String.
- SQL-Identifier: nur Namen, die `Assert-SqlIdentifier` bestanden haben (Prüfung beim
  Laden der Konfig), und immer gequotet – MSSQL in eckigen Klammern (auch `#SourceIDs_*` und
  `SqlBulkCopy`-Ziel), Firebird in `"..."`; Spaltennamen aus Firebird-Metadaten im
  `CREATE TABLE` mit `]` → `]]` escaped. Metadaten-Abfragen (`INFORMATION_SCHEMA`,
  `sys.indexes`) und der `sp_Merge_Generic`-Aufruf nutzen `SqlParameter` statt String-Literale.
- Passwörter nur über `DbConnectionStringBuilder` in Connection-Strings
  (`New-FirebirdConnectionString`/`New-MSSQLConnectionString`), Log zeigt nur
  Server/DB/Port.
- MERGE ist idempotent: abgebrochene oder wiederholte Läufe sind unkritisch,
  solange kein `TRUNCATE` des Ziels dazwischen lag.
- Staging ist reine Wegwerf-Struktur, führende Quelle ist immer Firebird.

---

## Bekannte Einschränkungen

Details, Reproduktion und Workarounds: `docs/KNOWN_ISSUES.md`; Planung:
`docs/TODO.md`.

| Einschränkung | Ursache | Status |
|---------------|---------|--------|
| Exit-Code 0 trotz Tabellenfehlern/Sanity FEHLER; SP-Batch-Fehler nur Warnung | früher kein Exit-Code-Mapping am Skriptende (S1) | behoben in I2 (Exit 10/11/9), abgenommen 2026-10-08 |
| ~~Tabellen-/Spaltennamen, Prefix/Suffix ungeprüft in SQL interpoliert, teils ohne `[]`~~ | früher fehlende Identifier-Validierung (S2) | behoben in I4 / v2.12 (Allow-List + Klammerung + Parameter), Integrationsläufe 2026-10-08 bestanden |
| ~~`DECIMAL(18,4)` fest: NUMERIC mit Scale > 4 oder Precision > 18 verliert Stellen/überläuft~~ | früher Typmapping ohne Precision/Scale (S5) | behoben in I5 / v2.14 für neu angelegte Tabellen, Integrationslauf 2026-10-08 bestanden; Zieltabellen aus v2.13 oder älter behalten `DECIMAL(18,4)` → Erkennung per `Test-SQLSyncConnections.ps1 -PreDeploy` (`WARNUNG` „Altbestand DECIMAL“), Migration per `operations/RUNBOOK.md` |
| ~~Typmapping und Spaltenermittlung doppelt (Sync-Skript und Modul), Guid fehlte im Sync~~ | früher Logik-Duplikat (S8) | behoben in I5 / v2.14 (Parallel-Block nutzt `ConvertTo-SqlServerType`/`Get-TableColumnConfig`); Configpfad-Duplikat behoben in I6 / v2.15 (`Resolve-SQLSyncConfigPath`) |
| ~~`config.schema.json` wird nie geprüft~~ | früher wurde `-SchemaPath` nicht übergeben (S9) | behoben in I6 / v2.15: alle vier Skripte prüfen Fail-Fast gegen das Schema (Exit 2), Integrationsläufe 2026-10-09 bestanden |
| ~~Bereits vorhandene oder per `DllPath` konfigurierte Treiber-DLL ohne Hash-Prüfung~~ | früher Prüfung nur beim Download (S4) | behoben in I7 (2026-10-09): jede DLL wird vor dem Laden geprüft, Abweichung → Exit 7; echter Lauf mit manipulierter Kopie bestanden. Grenze: eine in der Sitzung bereits geladene Assembly wird ohne Prüfung weiterverwendet |
| ~~Änderungen mit Zeitstempel ≤ Wasserzeichen werden übersprungen (gleicher ts, späte Commits, Uhrabweichung)~~ | früher striktes `> MAX(ts)` (S6) | weitgehend behoben in I8 / v2.18: Extrakt ab Wasserzeichen minus `General.IncrementalOverlapMinutes` (Default 10), inklusive; Integrationslauf 2026-10-09 bestanden. Rest: Commit-Verzögerungen länger als das Fenster holt erst der Weekly Full (`ForceFullSync`) |
| `RowsLoaded` ist bei Incremental auch ohne Quelländerung oft > 0 | Überlappungsfenster liest Zeilen erneut (I8) | by design; MERGE idempotent, keine Duplikate |
| Löschungen nicht repliziert; Orphan-Cleanup nur für numerische IDs | by design / `BIGINT`-Temp-Tabelle (S7) | Akzeptiert / Backlog |
| Neue Firebird-Spalten erreichen das Ziel nicht automatisch; `sp_Merge_Generic` nutzt die Spalten der **Zieltabelle** | keine Schema-Drift-Erkennung (S11) | Backlog |
| `MSSQL.Port` wird ignoriert | nicht implementiert (S12) | geplant in I10d |
| Einstiegsskripte ohne automatisierte Tests | nur `SQLSyncCommon.psm1` ist unit-getestet; der Ablauf der Skripte braucht DB-Zugriff | Integrationstests offen; Typmapping und Strategiewahl (seit I5) sowie Configpfad-Auflösung und Schema-Prüfung (seit I6) und der Incremental-Extrakt (seit I8) liegen im Modul (unit-getestet) |
| `sp_Merge_Generic` meldet fehlende Tabellen/ID-Spalte nur per `PRINT` und kehrt ohne Fehler zurück | Prozedurdesign | offen |

---

## Bekannte Fallstricke

- Produktive Job-Profile nicht für Einmal-Aktionen (`ForceFullSync`,
  `RecreateStagingTable`) umstellen – Kopie der Konfig verwenden
  (`operations/RUNBOOK.md`).
- Credential-Manager-Einträge sind pro Windows-Konto: `Setup_Credentials.ps1`
  unter dem Task-Konto ausführen. Bei Tasks unter einem gMSA
  (`Setup-ScheduledTasks.ps1 -GmsaAccount`) ist das nicht direkt möglich – dort
  für SQL Server Integrated Security verwenden (`operations/TASK_SCHEDULER.md`).
- Der erste Lauf auf einem neuen Host muss als Administrator laufen (Treiber).
- `Snapshot`- und `FullMerge (Forced)`-Tabellen sind während des Laufs kurz leer
  (`TRUNCATE` vor dem Befüllen, keine Transaktion um beide Schritte).
- `Manage_Config_Tables.ps1` und `Get_Firebird_Schema.ps1` nehmen ohne
  `-ConfigFile` die `config.json`; für andere Job-Profile `-ConfigFile` angeben.
- Neue Konfigschlüssel müssen in `config.schema.json` stehen, sonst bricht jeder
  Lauf mit dieser Konfig mit Exit 2 ab (`additionalProperties: false`).
- `config.schema.json` gehört zur Auslieferung; fehlt sie, läuft der Sync nur mit
  Warnung und ohne Schema-Prüfung.

---

## Teststrategie

Unit-Tests (seit I3, Schwachstelle S10 erledigt): `tests/Unit/SQLSyncCommon.Tests.ps1`
mit 163 Pester-5-Tests (insgesamt 176 mit `Setup-ScheduledTasks.Tests.ps1`); jede exportierte Funktion von `SQLSyncCommon.psm1` hat mindestens
einen Test. Pester 5.7.1 ist in `tests/RequiredModules.psd1` gepinnt. Aufruf
`pwsh -NoProfile -File .\tests\pester.config.ps1` (mit Coverage, Ziel 80 %, gemessen 95,63 % am 2026-10-09)
oder schnell `Invoke-Pester ./tests`. Die Diskriminierung der Tests ist per
Mutationsprüfung belegt (13 von 13 Mutationen erkannt; für den Incremental-Extrakt aus I8
weitere 7 von 7). Seit I8 ist der Extrakt (Wasserzeichen, Untergrenze, Abfrage) im Modul
und damit unit-getestet. Die Einstiegsskripte werden
weiterhin manuell verifiziert über `Test-SQLSyncConnections.ps1` (vor Deployments mit
`-PreDeploy`, rein lesend) und die Zusammenfassungstabelle eines Laufs; eine CI gibt es nicht.

- Details zu Konventionen, Testumfang und Konfiguration: `testing/UNIT_TESTS.md`.
- Integration gegen echte Firebird-/SQL-Server-Instanzen:
  `testing/INTEGRATION_TESTS.md`.
- Kritische Testfälle: leere `Tables` → Exception; fehlende Konfig → exit 2;
  schemawidrige Konfig (falscher Typ, unbekannter Schlüssel) → Exception mit JSON-Pfad;
  Strategie-Ermittlung (ID+TS → Incremental, nur ID → FullMerge, keine ID →
  Snapshot, ForceFullSync → FullMerge (Forced)); `TableOverrides` haben Vorrang;
  Sonderzeichen in Passwörtern werden im Connection-String maskiert;
  Tabellenfehler → Exit 10, Sanity `FEHLER` → Exit 11 (Unit-Test vorhanden,
  E2E offen).

---

## Akzeptanzkriterien

- [ ] Ein Lauf mit gültiger Konfig legt fehlende Ziel-DB, `sp_Merge_Generic`,
      `STG_<Tabelle>` und Zieltabellen selbständig an.
- [ ] Jede Tabelle in `Tables` erscheint genau einmal in der Zusammenfassung mit
      Strategie, Status, Zeilenzahlen und Sanity.
- [ ] Nach einem fehlerfreien Lauf mit `ForceFullSync` haben alle Tabellen
      Sanity `OK`.
- [ ] Ein zweiter Incremental-Lauf ohne Änderungen in Firebird lädt nur die Zeilen
      im Überlappungsfenster erneut (seit I8; mit `IncrementalOverlapMinutes = 0` nur
      die Zeilen mit Zeitstempel = Wasserzeichen) und verändert das Ziel inhaltlich nicht.
- [ ] Ein Datensatz, der im Ziel fehlt und dessen Zeitstempel innerhalb des
      Überlappungsfensters unter dem Wasserzeichen liegt, erscheint nach dem nächsten
      Incremental-Lauf wieder im Ziel (K3, Integrationslauf 2026-10-09 bestanden).
- [ ] In Firebird geänderte Zeilen mit neuerem Zeitstempel erscheinen nach dem
      nächsten Incremental-Lauf aktualisiert im Ziel.
- [ ] Ein Fehler in einer Tabelle bricht die anderen Tabellen nicht ab; Retries
      erfolgen gemäß `MaxRetries`.
- [ ] Keine Passwörter im Log oder auf der Konsole.
- [ ] Fehlende Credentials / Treiber / Konfig / Pre-Flight-Fehler enden mit
      dem dokumentierten Exit-Code (5 / 7 / 2 / 9).
- [ ] Tabellenfehler führen zu Exit-Code 10, Sanity `FEHLER` zu 11 (im Code
      seit I2; Abnahme per Lauf mit nicht existierender Tabelle und Task
      Scheduler „Letztes Ergebnis" `0xA` offen).
