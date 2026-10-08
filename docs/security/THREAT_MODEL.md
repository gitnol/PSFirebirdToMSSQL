# Threat Model & Mitigationen – PSFirebirdToMSSQL

Stand: 2026-10-08 (Initialisierung, Code-Stand 721d5e0). Abgeleitet ausschließlich aus dem
tatsächlichen Code im Projekt-Root (`Sync_Firebird_MSSQL_AutoSchema.ps1`, `SQLSyncCommon.psm1`,
`sql_server_setup.sql`, `Setup_Credentials.ps1`, `Setup-ScheduledTasks.ps1`,
`Manage_Config_Tables.ps1`). Schwachstellen-IDs S1–S13 und Inkrement-IDs I2–I10 entsprechen
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
| Internet (NuGet CDN) → `%ProgramData%\SQLSync\Drivers\...` | Treiber-DLL | Nur beim Download per SHA-256 geprüft |
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
- `Manage_Config_Tables.ps1` prüft `IdColumn`/`TimestampColumns` mit derselben Funktion (Exit 2) und
  übernimmt Tabellen mit ungültigem Namen nicht (Markierung im GridView).
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

**Offene Maßnahme:** **I6** (JSON-Schema-Validierung aktivieren) als zusätzliche Struktur-Prüfung.
Die GUI-Pfade in `Manage_Config_Tables.ps1` sind nicht automatisiert getestet.

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

Nur eine **frisch heruntergeladene** DLL wird gegen den SHA-256-Wert geprüft. Eine bereits
vorhandene DLL in einem der Kandidatenpfade – oder ein manipulierter `DllPath` – wird **ohne**
Hash-Prüfung geladen. Wer Schreibrechte auf `%ProgramData%\SQLSync\Drivers\...`, den Skriptordner
oder die Konfigurationsdatei hat, kann so Code im Kontext des Sync-Kontos (mit Zugriff auf beide
Datenbanken und den Credential Manager dieses Kontos) ausführen.

**Aktuelle Mitigation (im Code vorhanden):**
- Fest gepinnte Paketversion 10.3.4, Download nur über HTTPS (TLS 1.2) von `globalcdn.nuget.org`.
- SHA-256-Prüfung der heruntergeladenen `lib\net8.0`-DLL gegen
  `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05`; bei Abweichung wird das
  Verzeichnis gelöscht und nicht geladen (seit 721d5e0).
- Download nur mit Administratorrechten; `%ProgramData%`-Unterordner erbt standardmäßig
  restriktive Schreibrechte (nicht vom Code gesetzt, nicht verifiziert).
- `*.dll` und `*.nupkg` sind gitignored.

**Offene Maßnahme:** **I7** – SHA-256-Prüfung auch für bereits vorhandene und per `DllPath`
konfigurierte DLLs (Fail-Fast bei Abweichung oder dokumentierte Allowlist mehrerer Hashes).
Prüfung der aktuellen Advisories zum Treiber: `docs/security/DEPENDENCY_AUDIT.md`.

**Restrisiko:** Mittel – Ausnutzung setzt lokalen Schreibzugriff voraus, die Auswirkung ist aber
vollständige Code-Ausführung mit Datenbankzugriff.

---

## 4. Unbemerkte Fehlschläge und stiller Datenverlust (S1, S5, S6)

**Gefahr:** Integritätsbedrohung – Zieldaten werden falsch oder unvollständig, ohne dass es
jemand bemerkt:
- **S1:** Bis Version 2.10 endete `Sync_Firebird_MSSQL_AutoSchema.ps1` immer mit Exit-Code 0,
  auch wenn Tabellen den Status `Fehler` oder der Sanity Check `FEHLER` hatte; Batch-Fehler beim
  Installieren von `sql_server_setup.sql` waren nur Warnungen. Der Task Scheduler meldete Erfolg.
  Seit v2.11 (I2) im Code mitigiert, siehe unten.
- **S5:** Das Inline-Typmapping bildet `Decimal` fest auf `DECIMAL(18,4)` ab – Werte mit mehr als
  4 Nachkommastellen werden gerundet, Werte mit Precision > 18 laufen über (Fehler oder Verlust).
- **S6:** Das Wasserzeichen ist strikt `> MAX(ts)` der Zieltabelle; Sätze mit identischem
  Zeitstempel oder aus länger laufenden Firebird-Transaktionen werden bis zum nächsten Full-Lauf
  übersprungen. Fällt die `MAX`-Abfrage aus, wird `1900-01-01` verwendet (Voll-Extrakt).
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

**Offene Maßnahme:** Abnahme von **I2** durch einen echten Lauf (nicht existierende Tabelle →
Exit 10, Task Scheduler „Letztes Ergebnis" `0xA`); **I5** (DECIMAL mit Precision/Scale aus dem
Schema), **I8** (Überlappungsfenster für das Wasserzeichen). Backlog: strukturiertes
Run-Ergebnis (JSON/CSV) und Alarmierung auf `LastTaskResult`.

**Restrisiko:** Mittel – Tabellen- und Sanity-Fehler sind über den Exit-Code erkennbar (Abnahme
offen), es gibt aber keine aktive Alarmierung; S5/S6 bleiben offen und erzeugen nicht immer einen
Sanity-`FEHLER` (z. B. gerundete Nachkommastellen bei gleicher Zeilenzahl).

---

## 5. Übermäßige Rechte von Konto, Datenbank-Login und Ausführungsumgebung (S13)

**Gefahr:**
- **Pre-Flight** im Hauptskript legt die Zieldatenbank über `master` an (`CREATE DATABASE` +
  `RECOVERY SIMPLE`) – das MSSQL-Login braucht dafür `dbcreator`, sobald die DB fehlt.
- Der Lauf benötigt DDL in der Ziel-DB (`CREATE/DROP TABLE`, `TRUNCATE`, `CREATE OR ALTER
  PROCEDURE`, PK-Anlage) und Bulk-Insert. Zusammen mit Bedrohung 1 vergrößert das den Schaden.
- Firebird-Fallback-Benutzer ist `SYSDBA`, wenn `Firebird.User` fehlt (`Resolve-FirebirdCredentials`)
  – Vollzugriff auf die ERP-Datenbank, obwohl nur lesend gearbeitet wird.
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

**Offene Maßnahme:** Betrieb (ohne Code-Änderung umsetzbar): Tasks auf Dienstkonto oder gMSA
umstellen (Default bleibt der aufrufende Benutzer); Datenbank vorab anlegen und `dbcreator` entziehen; dediziertes
Firebird-Konto mit reinen `SELECT`-Rechten statt `SYSDBA`; MSSQL-Login auf `db_ddladmin` +
`db_datawriter` + `db_datareader` der Ziel-DB beschränken; Skriptordner nur für Admins und das
Sync-Konto beschreibbar. Details: `docs/operations/TASK_SCHEDULER.md`,
`docs/security/AUTHENTICATION.md`.

**Restrisiko:** Mittel – abhängig von der tatsächlichen Rechtevergabe beim Betreiber (nicht aus dem
Code ableitbar).

---

## 6. Denial of Service des Firebird-Servers (CVE-2026-34232)

**Gefahr:** Am 2026-10-08 (Security-Sweep, Ereignis-Auslöser) gefunden: CVE-2026-34232
(CVSS 7.5, GHSA-7jq3-6j3c-5cm2) – ein unauthentifizierter Angreifer kann den Firebird-Server über ein
präpariertes `op_response`-Paket zum Absturz bringen. Betroffen sind Firebird-Server < 5.0.4,
< 4.0.7 und < 3.0.14 (Quelle: https://nvd.nist.gov/vuln/detail/cve-2026-34232 ).
Mindestens ein intern eingesetzter Firebird-Server ist betroffen (Details nur in `docs/local/ENVIRONMENT.md`); die Version des produktiven
ERP-Firebird ist nicht bekannt. Wirkung auf dieses Projekt: Verfügbarkeit – während eines Absturzes
schlagen Extrakt und Sanity Check fehl (Exit 10), und das ERP selbst ist ebenfalls nicht verfügbar.
Die Schwachstelle liegt im Server, nicht im Sync-Code; für den Client-Treiber
`FirebirdSql.Data.FirebirdClient` 10.3.4 wurde kein CVE gefunden.

**Aktuelle Mitigation (im Code vorhanden):**
- Keine im Code möglich. Der Sync erkennt den Ausfall (Tabellenstatus `Fehler`, Exit 10) und
  wiederholt pro Tabelle (`MaxRetries`).
- Ob der Firebird-Port nur im internen Netz erreichbar ist, ist nicht aus dem Code ableitbar
  (nicht verifiziert).

**Offene Maßnahme (Betrieb):** Firebird-Server auf ≥ 5.0.4 (bzw. ≥ 4.0.7 / ≥ 3.0.14) aktualisieren,
zuerst Testserver, dann produktiven ERP-Server; produktive Version mit
`Test-SQLSyncConnections.ps1` erfassen. Bis dahin Firebird-Port per Firewall auf die benötigten
Clients beschränken. Nachverfolgung in `docs/security/DEPENDENCY_AUDIT.md`.

**Restrisiko:** Mittel – bis zum Server-Update kann jeder Host mit Netzzugang zum Firebird-Port den
Server abstürzen lassen; die Schwachstelle betrifft laut Beschreibung die Verfügbarkeit (Absturz),
nicht das Auslesen oder Verändern von Daten.

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
| S4 | Vorhandene/konfigurierte Treiber-DLL ohne Hash-Prüfung | — | I7 |
| S5 | `DECIMAL(18,4)` fest → Präzisionsverlust; Inline-Mapping ohne `Guid` | K2 | I5 |
| S6 | Wasserzeichen strikt `> MAX(ts)` | K3 | I8 |
| S7 | Löschungen nicht repliziert; Orphan-Cleanup nur numerische IDs | K4, K5 | by design / `BACKLOG.md` |
| S8 | Doppelte Logik (Typmapping, Strategie, Configpfad) | K8 | I5, I6 |
| S9 | `config.schema.json` wird nie geprüft | K7 | I6 |
| S10 | Keine automatisierten Tests | — | I3 (erledigt 2026-10-08) |
| S11 | Schema-Drift (neue Spalten) nicht behandelt | K6 | `BACKLOG.md` |
| S12 | Doku-/Repo-Drift, ungenutztes `MSSQL.Port` | K7 | I10 |
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
- Letzter Security-Sweep: 2026-10-08 (Ereignis-Auslöser I4, Ergebnis Bedrohung 1 und 6).
  Nächster Security-Sweep (Web-Advisories, `principles/SECURITY_CURRENCY.md`): 2026-10-22.
