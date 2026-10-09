# Erstinstallation / Setup – PSFirebirdToMSSQL

Ziel: einen Windows-Host so einrichten, dass `Sync_Firebird_MSSQL_AutoSchema.ps1`
Tabellen aus Firebird in die MS-SQL-Staging-Datenbank replizieren kann.
Fortsetzung: `operations/DEPLOYMENT.md` (Updates), `operations/TASK_SCHEDULER.md`
(Automatisierung), `operations/RUNBOOK.md` (Betrieb).

---

## Voraussetzungen

| Was | Anforderung | Prüfung |
|---|---|---|
| Betriebssystem | Windows (advapi32 CredRead/CredWrite, `cmdkey`, Task Scheduler, `Out-GridView`) | – |
| PowerShell | 7.0 oder neuer (`#Requires -Version 7.0`; `ForEach-Object -Parallel`, ternärer Operator). Windows PowerShell 5.1 reicht **nicht**. | `pwsh -v` |
| Firebird-Server | 2.5+/3.x, erreichbar auf Port 3050 (bzw. konfigurierter Port), Leserechte auf die Quelltabellen | Test-SQLSyncConnections.ps1 |
| MS SQL Server | 2017 oder neuer (`STRING_AGG`, `CREATE OR ALTER` in `sql_server_setup.sql`) | Test-SQLSyncConnections.ps1 |
| Internet (einmalig) | Zugriff auf `globalcdn.nuget.org` für den Treiber-Download – oder Treiber-DLL manuell bereitstellen (`DllPath`) | – |
| Adminrechte (einmalig) | für den Treiber-Download nach `%ProgramData%\SQLSync\Drivers\` und für `Setup-ScheduledTasks.ps1` | – |

Keine Module aus der PowerShell Gallery nötig. Einzige externe Abhängigkeit ist
der .NET-Treiber `FirebirdSql.Data.FirebirdClient` 10.3.4 (wird automatisch
geladen, siehe Schritt 4). `System.Data.SqlClient` ist in PowerShell 7 enthalten.

### Benötigte SQL-Server-Rechte (Sync-Konto)

| Recht | Wofür | Pflicht? |
|---|---|---|
| `dbcreator` (Serverrolle) | Pre-Flight legt die Ziel-DB per `CREATE DATABASE` + `RECOVERY SIMPLE` an, falls sie fehlt | nur wenn die DB nicht vorab angelegt wird |
| Zugriff auf `master` (Login/Connect) | Pre-Flight prüft `sys.databases` immer über `master` | ja |
| DDL in der Ziel-DB (`CREATE TABLE`, `ALTER TABLE`, `CREATE/ALTER PROCEDURE`, `DROP TABLE`) | Staging-/Zieltabellen, PK, `dbo.sp_Merge_Generic` | ja |
| `INSERT`/`UPDATE`/`DELETE`/`SELECT`, `TRUNCATE` (erfordert `ALTER` auf der Tabelle), `EXECUTE` | Bulk-Load, MERGE, Snapshot, Orphan-Cleanup | ja |
| Bulk-Insert-Recht (`INSERT BULK` über SqlBulkCopy) | Laden der Staging-Tabellen | ja |

Pragmatisch: `db_owner` auf der Ziel-DB, plus `dbcreator`, wenn die DB
automatisch angelegt werden soll (siehe auch README.de.md). Firebird: nur
Leserechte auf die konfigurierten Tabellen – empfohlen ist ein eigenes
Lesekonto statt `SYSDBA` (siehe „Firebird-Lesekonto anlegen“).

### Firebird-Lesekonto anlegen (Empfehlung)

Der Sync liest in Firebird nur (`SELECT`). Ein Konto mit Admin- oder DDL-Rechten
(`SYSDBA`, `CREATE FUNCTION`) ist unnötig und gefährlich: Über CVE-2026-40342
(CVSS 9.9, Firebird-Server < 5.0.4 / < 4.0.7 / < 3.0.14) kann ein Konto mit
`CREATE FUNCTION` Code als OS-Konto des Firebird-Servers ausführen – ein Leck der
Sync-Credentials würde zur Codeausführung auf dem ERP-Datenbankserver
(`security/THREAT_MODEL.md` Bedrohung 5 und 6). Deshalb zusätzlich den Server auf
≥ 5.0.4 (bzw. ≥ 4.0.7 / ≥ 3.0.14) aktualisieren.

Anlage durch den Firebird-Administrator (Firebird 3 oder neuer; Name und Passwort
frei wählbar):

```sql
-- als SYSDBA, verbunden mit der ERP-Datenbank
CREATE USER SQLSYNC_READ PASSWORD '<starkes Passwort>';
-- je konfigurierter Tabelle (Liste aus "Tables" der Konfig)
GRANT SELECT ON <TABELLE> TO USER SQLSYNC_READ;
COMMIT;
```

- Keine DDL- oder Metadatenrechte erteilen (kein `GRANT CREATE FUNCTION …`, keine
  Rolle `RDB$ADMIN`). Ob angemeldete Benutzer auf der eingesetzten Firebird-Version
  ohne explizites Recht Metadaten anlegen dürfen, hängt von Version und
  Datenbankrechten ab (nicht verifiziert) – deshalb ist das Server-Update die
  eigentliche Behebung, das Lesekonto begrenzt den Schaden.
- Neue Tabellen in `Tables` brauchen jeweils ein eigenes `GRANT SELECT`; fehlt es,
  scheitert die Tabelle im Sync (Status `Fehler`, Exit 10).
- Das Konto mit `Setup_Credentials.ps1` unter dem Task-Konto hinterlegen
  (Schritt 5); `Firebird.User` in der Konfig wird dann nicht benötigt.
- Kontrolle: `.\Test-SQLSyncConnections.ps1` (Firebird-Test-`COUNT`) und ein
  Testlauf des Syncs.

---

## Installation

### 1. Dateien bereitstellen

Alle Dateien liegen flach in einem Verzeichnis (kein Installer). Benötigt werden
mindestens:

```
Sync_Firebird_MSSQL_AutoSchema.ps1
SQLSyncCommon.psm1
sql_server_setup.sql
Setup_Credentials.ps1
Test-SQLSyncConnections.ps1
config.schema.json            (Schema-Prüfung jeder Konfig beim Laden)
config.sample.json            (Vorlage)
```

Optional: `Manage_Config_Tables.ps1`, `Get_Firebird_Schema.ps1`,
`Setup-ScheduledTasks.ps1`.

`config.schema.json` gehört zu jeder Auslieferung: Alle Skripte prüfen die
Konfig beim Laden dagegen (Verstoß → Exit 2). Fehlt die Datei, erscheint nur
die Warnung `Schema-Datei nicht gefunden …` und der Lauf geht ohne
Schema-Prüfung weiter.

```powershell
# Beispiel: Klon aus dem öffentlichen Repo oder Kopie in das Zielverzeichnis
git clone https://github.com/gitnol/PSFirebirdToMSSQL.git D:\Apps\SQLSync
```

Der Ordner `Logs\` wird beim ersten Lauf automatisch neben dem Skript angelegt.
Details zum Zielverzeichnis: `operations/DEPLOYMENT.md`.

**Nur für Entwickler-Klone (Commits ins öffentliche Repo):** Interna-Sperre aktivieren und die
lokale Denylist anlegen (`CONVENTIONS.md` 6.2):

```powershell
git config core.hooksPath tools/git-hooks
# .internal-terms (gitignored): ein interner Begriff pro Zeile, z. B. Hostnamen, Domäne, Pfade
notepad .internal-terms
```

### 2. PowerShell 7 installieren

```powershell
winget install Microsoft.PowerShell
# Prüfen
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
```

Execution Policy: Die Scheduled Tasks starten mit `-ExecutionPolicy Bypass`.
Für interaktive Aufrufe ggf. einmalig:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Aus dem Internet geladene Dateien ggf. entsperren
Get-ChildItem D:\Apps\SQLSync -Filter *.ps* | Unblock-File
```

### 3. Konfiguration anlegen

```powershell
Copy-Item .\config.sample.json .\config.json
notepad .\config.json
```

Mindestens anzupassen: `Firebird.Server`, `Firebird.Database` (Pfad zur `.FDB`),
`MSSQL.Server`, `MSSQL.Database`, `MSSQL."Integrated Security"`, `Tables`.
Alle Schlüssel und Defaults: `architecture/CONFIGURATION.md`.

Nach dem Bearbeiten gegen das Schema prüfen (ohne Datenbankzugriff; `True` = gültig):

```powershell
Test-Json -Json (Get-Content .\config.json -Raw) -Schema (Get-Content .\config.schema.json -Raw)
```

Unbekannte Schlüssel (Tippfehler), Zahlen/Bools in Anführungszeichen oder Werte
außerhalb der Grenzen lassen jedes Skript mit Exit 2 abbrechen.

- **Passwörter NICHT in `config.json` eintragen**, sondern Schritt 5 nutzen.
  Die Felder `Password` in `config.sample.json` sind nur ein unsicherer Fallback
  (Warnung im Log) – in der eigenen `config.json` entfernen oder leer lassen.
- `MSSQL.Port` aus der Vorlage wird vom Code ignoriert (Inkrement I10a); einen
  abweichenden Port im Feld `MSSQL.Server` angeben (`host,port`).
- `config.json` und `config.json.*.bak` sind per `.gitignore` ausgeschlossen –
  niemals committen.
- Für mehrere Job-Profile (z. B. Daily Diff / Weekly Full) je Profil eine
  eigene Konfigdatei anlegen und per `-ConfigFile` übergeben.

### 4. Treiber einmalig als Administrator laden

Der Firebird-Treiber wird beim ersten Lauf von NuGet geladen, per SHA-256
geprüft und nach
`%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\` entpackt.
Ohne Adminrechte bricht das Skript mit „Bitte einmalig als ADMINISTRATOR
ausführen" ab (Sync exit 7, Test-Skript exit 4).

```powershell
# PowerShell 7 "Als Administrator ausführen", dann:
cd D:\Apps\SQLSync
.\Test-SQLSyncConnections.ps1     # lädt den Treiber und testet gleich die Verbindungen
```

**Hash-Prüfung:** Jede DLL wird vor dem Laden per SHA-256 geprüft – der frische
Download ebenso wie eine bereits in `%ProgramData%` liegende oder per
`Firebird.DllPath` konfigurierte DLL. Zulässig sind nur die Original-DLLs aus dem
NuGet-Paket 10.3.4 (`lib\net8.0` bzw. `lib\netstandard2.1`; Hashes in
`architecture/DEPENDENCIES.md`). Bei Abweichung bricht der Lauf vor jeder
Datenbankverbindung ab (`SHA-256 der Treiber-DLL … stimmt nicht … Treiber wurde
NICHT geladen`, Sync Exit 7, Test-Skript Exit 4) – Vorgehen in
`operations/RUNBOOK.md`. Erfolgreich: `[Driver] Firebird .NET Provider geladen
(SHA-256 geprüft): …`.

Alternative ohne Internet: Original-DLL (net8.0) aus dem offiziellen NuGet-Paket
10.3.4 manuell ablegen und `Firebird.DllPath` setzen – sie wird genauso geprüft.
Eine **andere** Treiberversion nur mit `Firebird.DllSha256` (erwarteter Hash,
selbst aus dem offiziellen Paket berechnet); dann gilt ausschließlich dieser Hash
(`architecture/CONFIGURATION.md`).

**NTFS-Rechte prüfen:** `%ProgramData%\SQLSync\Drivers` darf nur für
Administratoren (und `SYSTEM`) beschreibbar sein; normale Benutzer und das
Task-Konto brauchen nur Lesen/Ausführen. Die Hash-Prüfung verhindert das Laden
einer ausgetauschten DLL, die Rechte verhindern den Austausch.

```powershell
icacls "$env:ProgramData\SQLSync\Drivers"
# Erwartet: Schreib-/Vollzugriff (F, M, W) nur für BUILTIN\Administrators und NT AUTHORITY\SYSTEM;
# BUILTIN\Users bzw. das Task-Konto höchstens (RX)
```

Hinweis (am 2026-10-09 auf einem Entwicklerrechner gemessen): Die Standardrechte von `%ProgramData%` vererben `BUILTIN\Users`
das Anlegen neuer Dateien und Ordner (`(WD,AD,WEA,WA)`). Zeigt `icacls` das, die
Vererbung für den Treiberordner brechen und die Rechte explizit setzen (als
Administrator; SIDs statt Namen, damit es sprachunabhängig ist):

```powershell
icacls "$env:ProgramData\SQLSync\Drivers" /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX"
```

Gleiches gilt für den Skriptordner und einen per `DllPath` genutzten Ordner.

### 5. Credentials hinterlegen

```powershell
.\Setup_Credentials.ps1
```

Das Skript fragt interaktiv Benutzer/Passwort ab und speichert sie im Windows
Credential Manager (Typ Generic) unter den Targets `SQLSync_Firebird` und
`SQLSync_MSSQL` (letzteres nur, wenn SQL-Authentifizierung gewählt wird; bei
`"Integrated Security": true` nicht nötig).

Andere Eintragsnamen per `-FirebirdTarget` / `-MSSQLTarget`, z. B. ein eigener Eintrag
je SQL Server bei gleichem Login mit unterschiedlichen Passwörtern:

```powershell
.\Setup_Credentials.ps1 -MSSQLTarget "SQLSync_MSSQL_sqltest"
```

Den Namen dann in der Konfigdatei unter `MSSQL.CredentialTarget` (bzw.
`Firebird.CredentialTarget`) eintragen. Ohne diese Schlüssel gelten die Defaults.

**Wichtig:** Credential-Manager-Einträge gehören dem Windows-Konto, unter dem
`Setup_Credentials.ps1` läuft. Es muss **dasselbe Konto** sein, unter dem später
die Scheduled Tasks laufen (`-RunAsUser`/`-GmsaAccount` von
`Setup-ScheduledTasks.ps1`, S13). Details: `architecture/CREDENTIAL_STRATEGY.md`,
`operations/SECRETS_MANAGEMENT.md`.

```powershell
cmdkey /list:SQLSync*      # Kontrolle (zeigt keine Passwörter)
```

### 6. Verbindungen testen

```powershell
.\Test-SQLSyncConnections.ps1                         # nutzt config.json
.\Test-SQLSyncConnections.ps1 -ConfigFile .\config_weekly_full.json
```

Geprüft werden: Firebird-Version, Anzahl Tabellen, Test-`COUNT` auf die erste
konfigurierte Tabelle; SQL-Server-Version, vorhandene Tabellen, ob
`sp_Merge_Generic` existiert. Exit-Codes: 0 OK, 1 Modul/Config fehlt oder ein
Test fehlgeschlagen, 2 Config ungültig (Parse, Schema, Namen), 3 Credentials, 4 Treiber,
6 Vor-Deployment-Prüfung mit mindestens einem `FEHLER`.

Vor der Inbetriebnahme zusätzlich die rein lesende Vor-Deployment-Prüfung ausführen:

```powershell
.\Test-SQLSyncConnections.ps1 -ConfigFile .\config.json -PreDeploy
```

Sie prüft alle `config*.json` im Ordner gegen Schema und Namensregeln, die
Treiber-DLL gegen die erlaubten SHA-256, die Firebird-Serverversion gegen
bekannte Server-Advisories, ob der Sync als `SYSDBA` angemeldet ist (Empfehlung:
„Firebird-Lesekonto anlegen“) und ob
bestehende Zieltabellen Dezimalwerte kürzen würden. Ausgabe als Tabelle
Status / Prüfung / Detail; Exit 6 bei mindestens einem `FEHLER`, `WARNUNG`en
lassen Exit 0 zu. Details: `operations/DEPLOYMENT.md`, „Vor-Deployment-Prüfung“.

Hinweis: Fehlt `sp_Merge_Generic`, ist das beim Erst-Setup normal – der erste
Sync-Lauf installiert sie automatisch aus `sql_server_setup.sql`.

### 7. Tabellen auswählen (optional)

```powershell
.\Manage_Config_Tables.ps1                                   # bearbeitet config.json
.\Manage_Config_Tables.ps1 -ConfigFile .\config_weekly_full.json
```

Liest die Tabellenliste aus Firebird und zeigt sie in `Out-GridView`
(Desktop-Sitzung nötig). Markierte Tabellen werden in `Tables` hinzugefügt bzw.
entfernt; vorher wird `<Konfigdatei>.<yyyyMMdd_HHmmss>.bak` angelegt. Ohne
`-ConfigFile` wird `config.json` bearbeitet. Vor dem GridView prüft das Skript
die Konfig (Schema + Namensregeln, Verstoß → Exit 2, kein Backup); eine Auswahl,
die alle Tabellen entfernen würde, wird mit Exit 4 abgelehnt. Die `.bak`-Dateien
enthalten ggf. dieselben Fallback-Passwörter wie die Konfig – aufräumen.

Spaltentypen einer Tabelle vorab prüfen:

```powershell
.\Get_Firebird_Schema.ps1 -TableName BKUNDE                      # Verbindung aus config.json
.\Get_Firebird_Schema.ps1 -TableName BKUNDE -ConfigFile .\config_weekly_full.json
```

### 8. Erster Lauf

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1                  # config.json
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile .\config.json
```

Beim ersten Lauf werden ggf. Ziel-DB, `dbo.sp_Merge_Generic`, alle
`STG_<Tabelle>`- und Zieltabellen angelegt und vollständig geladen. Danach die
Zusammenfassungstabelle am Ende der Ausgabe bzw. im Log
`Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log` prüfen: Jede Tabelle muss
Status `Erfolg` und Sanity `OK` haben. Der Sync meldet das Ergebnis auch über
den Exit-Code (`$LASTEXITCODE` nach dem Aufruf): `0` OK, `10` mindestens eine
Tabelle fehlgeschlagen, `11` Sanity `FEHLER`, `9` Pre-Flight; die letzte
Logzeile vor dem Transcript-Ende lautet `ERGEBNIS: …`. Beim Erst-Setup trotzdem
die Tabelle lesen (Sanity `WARNUNG` ergibt Exit 0; Exit-Code-Verhalten noch
nicht in einem echten Lauf abgenommen).

### 9. Automatisierung (optional)

```powershell
# Vorschau: Pfade/Konfignamen prüfen (ohne Adminrechte, nichts wird registriert)
.\Setup-ScheduledTasks.ps1 -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json -WhatIf

# Registrieren: PowerShell 7 als Administrator, fragt das Windows-Passwort ab
.\Setup-ScheduledTasks.ps1 -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json
```

Installationsordner (`-InstallDir`, Default: Ordner des Skripts), Konfignamen,
Tasknamen, Zeitplan und Konto sind Parameter; mit `-GmsaAccount` laufen die
Tasks unter einem gMSA ohne gespeichertes Passwort. Parameter-Tabelle und
gMSA-Grenzen: `operations/TASK_SCHEDULER.md`.

---

## Wichtige Commands

```powershell
# Sync mit Standard-Konfig (config.json im Skriptordner)
.\Sync_Firebird_MSSQL_AutoSchema.ps1

# Sync mit bestimmtem Job-Profil (absolut oder relativ zum Skriptordner)
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile config_weekly_full.json

# Diagnose
.\Test-SQLSyncConnections.ps1 -ConfigFile config.json

# Vor-Deployment-Prüfung (rein lesend; Exit 6 = mindestens ein FEHLER)
.\Test-SQLSyncConnections.ps1 -ConfigFile config.json -PreDeploy

# Beispiel für zwei Läufe hintereinander
.\Example_Sync_Start.ps1
```

Nicht vorhanden: `-WhatIf`/Dry-Run, `-Verbose`-Ausgabe über das Transcript
hinaus, Versionsschalter, automatisierte Tests für die Einstiegsskripte (Unit-Tests gibt es nur
für `SQLSyncCommon.psm1`, siehe `docs/testing/UNIT_TESTS.md`).

---

## Credentials / Konfiguration

| Eintrag | Beschreibung | Fundort |
|---|---|---|
| `SQLSync_Firebird` | Firebird-Benutzer + Passwort (Fallback-Benutzer `SYSDBA`, Fallback-Passwort `Firebird.Password` in der Konfig mit Warnung) | Windows Credential Manager des Sync-Kontos; anlegen mit `Setup_Credentials.ps1` |
| `SQLSync_MSSQL` | SQL-Login + Passwort, nur ohne Integrated Security | wie oben |
| `Firebird.CredentialTarget` / `MSSQL.CredentialTarget` | optional: abweichender Name des Credential-Manager-Eintrags (Defaults `SQLSync_Firebird` / `SQLSync_MSSQL`); anlegen mit `-FirebirdTarget` / `-MSSQLTarget` | Konfigdatei |
| `MSSQL."Integrated Security"` | `true` = Windows-Authentifizierung des ausführenden Kontos, dann kein `SQLSync_MSSQL` nötig | Konfigdatei |
| Windows-Passwort des Task-Kontos | wird von `Setup-ScheduledTasks.ps1` per `Get-Credential` abgefragt und im Task Scheduler gespeichert | Task Scheduler |

Zugangsdaten bezieht man beim Betreiber der Firebird- bzw. SQL-Server-Instanz.

> **Niemals Passwörter in `config.json` committen.** `config.json`,
> `config.json.*.bak` und `Logs/` müssen in `.gitignore` stehen.
