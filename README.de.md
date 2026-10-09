# PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer

[![en](https://img.shields.io/badge/lang-en-red.svg)](README.md)

Hochperformante, parallelisierte ETL-Lösung zur inkrementellen Synchronisation von Firebird-Datenbanken (z.B. AvERP) nach Microsoft SQL Server.

Ersetzt veraltete Linked-Server-Lösungen durch einen modernen PowerShell-Ansatz mit `SqlBulkCopy` und intelligentem Schema-Mapping.

---

## Inhaltsverzeichnis

- [PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer](#psfirebirdtomssql-firebird-to-mssql-high-performance-synchronizer)
  - [Inhaltsverzeichnis](#inhaltsverzeichnis)
  - [Features](#features)
  - [Dateistruktur](#dateistruktur)
  - [Voraussetzungen](#voraussetzungen)
    - [Firebird-Treiber (Integritätsprüfung)](#firebird-treiber-integritätsprüfung)
  - [Installation](#installation)
    - [Schritt 1: Dateien kopieren](#schritt-1-dateien-kopieren)
    - [Schritt 2: Konfiguration anlegen](#schritt-2-konfiguration-anlegen)
    - [Schritt 3: SQL Server Umgebung (Automatisch)](#schritt-3-sql-server-umgebung-automatisch)
    - [Schritt 4: Credentials sicher speichern](#schritt-4-credentials-sicher-speichern)
    - [Schritt 5: Verbindung testen](#schritt-5-verbindung-testen)
    - [Schritt 6: Tabellen auswählen](#schritt-6-tabellen-auswählen)
    - [Schritt 7: Automatische Aufgabenplanung (Optional)](#schritt-7-automatische-aufgabenplanung-optional)
  - [Nutzung](#nutzung)
    - [Sync starten (Standard)](#sync-starten-standard)
    - [Sync starten (Spezifische Config)](#sync-starten-spezifische-config)
    - [Ablauf des Sync-Prozesses](#ablauf-des-sync-prozesses)
    - [Sync-Strategien](#sync-strategien)
  - [Konfigurationsoptionen](#konfigurationsoptionen)
    - [General Sektion](#general-sektion)
    - [Spalten-Konfiguration (NEU in v2.10)](#spalten-konfiguration-neu-in-v210)
    - [Orphan-Cleanup (Löschungserkennung)](#orphan-cleanup-löschungserkennung)
    - [MSSQL Prefix \& Suffix](#mssql-prefix--suffix)
    - [Namensregeln (seit v2.12)](#namensregeln-seit-v212)
    - [JSON-Schema-Validierung](#json-schema-validierung)
  - [Modul-Architektur](#modul-architektur)
  - [Verwendung in eigenen Skripten](#verwendung-in-eigenen-skripten)
  - [Credential Management](#credential-management)
  - [Logging](#logging)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden im Standard nicht synchronisiert (CleanupOrphans Option)](#löschungen-werden-im-standard-nicht-synchronisiert-cleanuporphans-option)
    - [Task Scheduler Integration (Pfadanpassung)](#task-scheduler-integration-pfadanpassung)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.10 (2025-12-09) - Dynamische Spalten-Konfiguration](#v210-2025-12-09---dynamische-spalten-konfiguration)
    - [v2.9 (2025-12-06) - Orphan-Cleanup (Soft Deletes)](#v29-2025-12-06---orphan-cleanup-soft-deletes)
    - [v2.8 (2025-12-06) - Modul-Architektur \& Bugfixes](#v28-2025-12-06---modul-architektur--bugfixes)
    - [v2.7 (2025-12-04) - Auto-Setup \& Robustness](#v27-2025-12-04---auto-setup--robustness)
    - [v2.6 (2025-12-03) - Task Automation](#v26-2025-12-03---task-automation)
    - [v2.5 (2025-11-29) - Prefix/Suffix \& Fixes](#v25-2025-11-29---prefixsuffix--fixes)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)
  - [⚖ Haftungsausschluss (Disclaimer)](#-haftungsausschluss-disclaimer)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz mit Memory-Streaming).
- **Inkrementeller Sync**: Lädt nur geänderte Daten (Delta) basierend auf konfigurierbaren Timestamp-Spalten (High Watermark Pattern).
- **Dynamische Spalten-Konfiguration**: Flexible ID- und Timestamp-Spaltennamen - funktioniert mit jeder Tabellenstruktur, nicht nur `ID`/`GESPEICHERT`.
- **Auto-Environment Setup**: Das Skript prüft beim Start, ob die Ziel-Datenbank existiert. Falls nicht, verbindet es sich mit `master`, **erstellt die Datenbank** automatisch und setzt das Recovery Model auf `SIMPLE`.
- **Auto-Installation SP**: Installiert oder aktualisiert die benötigte Stored Procedure `sp_Merge_Generic` automatisch aus der `sql_server_setup.sql`.
- **Flexible Namensgebung**: Unterstützt **Prefixe** und **Suffixe** für Zieltabellen (z.B. Quelle `KUNDE` -> Ziel `DWH_KUNDE_V1`).
- **Multi-Config Support**: Parameter `-ConfigFile` erlaubt getrennte Jobs (z.B. Daily vs. Weekly).
- **Self-Healing**: Erkennt Schema-Änderungen, fehlende Primärschlüssel und Indizes und repariert diese.
- **Parallelisierung**: Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`).
- **Sichere Credentials**: Windows Credential Manager statt Klartext-Passwörter.
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau.
- **Modul-Architektur**: Wiederverwendbare Funktionen in `SQLSyncCommon.psm1`.
- **JSON-Schema-Validierung**: Jedes Skript prüft die Konfiguration beim Laden gegen `config.schema.json` (Fail-Fast, Exit-Code 2).
- **Sicheres Connection Handling**: Kein Resource Leak durch garantiertes Cleanup (try/finally).

---

## Dateistruktur

```text
PSFirebirdToMSSQL/
├── SQLSyncCommon.psm1                   # KERN-MODUL: Gemeinsame Funktionen (MUSS vorhanden sein!)
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract -> Staging -> Merge)
├── Setup_Credentials.ps1                # Einmalig: Passwörter sicher speichern
├── Setup-ScheduledTasks.ps1             # Legt die Windows-Tasks an (Parameter, -WhatIf-Vorschau)
├── Manage_Config_Tables.ps1             # GUI-Tool zur Tabellenverwaltung
├── Get_Firebird_Schema.ps1              # Hilfstool: Datentyp-Analyse
├── sql_server_setup.sql                 # SQL-Template für DB & SP (wird vom Hauptskript genutzt)
├── Example_Sync_Start.ps1               # Beispiel-Wrapper
├── Test-SQLSyncConnections.ps1          # Verbindungstest
├── config.json                          # Zugangsdaten & Einstellungen (git-ignoriert)
├── config.sample.json                   # Konfigurationsvorlage
├── config.schema.json                   # JSON-Schema, bei jedem Laden der Config geprüft
├── .gitignore                           # Schützt config.json
└── Logs/                                # Log-Dateien (automatisch erstellt)
```

---

## Voraussetzungen

| Komponente             | Anforderung                                                                    |
| :--------------------- | :----------------------------------------------------------------------------- |
| PowerShell             | Version 7.0 oder höher (zwingend für `-Parallel`)                              |
| Firebird .NET Provider | Wird automatisch via NuGet installiert                                         |
| Firebird-Zugriff       | Leserechte auf der Quelldatenbank                                              |
| MSSQL-Zugriff          | Berechtigung, DBs zu erstellen (`db_creator`) oder min. `db_owner` auf Ziel-DB |

### Firebird-Treiber (Integritätsprüfung)

Beim ersten Lauf (als Administrator) lädt `Initialize-FirebirdDriver` das Paket `FirebirdSql.Data.FirebirdClient` 10.3.4 von NuGet nach `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\`. **Jede** DLL wird vor dem Laden per SHA-256 geprüft – der frische Download, eine bereits in `%ProgramData%` liegende DLL und eine per `Firebird.DllPath` konfigurierte DLL. Zulässig sind nur die Original-DLLs aus dem NuGet-Paket 10.3.4:

| DLL | SHA-256 |
|---|---|
| `lib\net8.0` | `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05` |
| `lib\netstandard2.1` | `8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A` |

Bei Abweichung bricht das Skript vor jeder Datenbankverbindung ab (`SHA-256 der Treiber-DLL ... stimmt nicht ... Treiber wurde NICHT geladen`, Sync-Exit-Code 7). Den gemeldeten Hash **nicht** einfach in die Konfiguration übernehmen – die Datei aus dem offiziellen Paket neu beziehen (Treiberordner löschen und einmal als Administrator ausführen). Für eine bewusst andere Treiberversion deren erwarteten Hash in `Firebird.DllSha256` eintragen (64 Hex-Zeichen, selbst aus dem offiziellen Paket berechnet); dann gilt nur dieser Hash. Schreibrechte auf `%ProgramData%\SQLSync\Drivers` sollten auf Administratoren beschränkt sein (Prüfung: `icacls "$env:ProgramData\SQLSync\Drivers"`).

**Firebird-Konto:** Statt `SYSDBA` ein eigenes Lesekonto verwenden (nur `SELECT` auf die konfigurierten Tabellen, keine DDL, kein `CREATE FUNCTION`) und den Firebird-Server auf 5.0.4 / 4.0.7 / 3.0.14 oder neuer halten. Hintergrund: CVE-2026-40342 (CVSS 9.9) erlaubt einem angemeldeten Benutzer mit `CREATE FUNCTION` auf älteren Versionen Codeausführung als OS-Konto des Firebird-Servers.

---

## Installation

### Schritt 1: Dateien kopieren

Alle `.ps1`, `.sql`, `.json` und vor allem die `.psm1` Dateien in ein gemeinsames Verzeichnis kopieren (z.B. `C:\Scripts\PSFirebirdToMSSQL\`).

**Wichtig:** Die Datei `SQLSyncCommon.psm1` muss zwingend im selben Verzeichnis wie die Skripte liegen!

### Schritt 2: Konfiguration anlegen

Kopiere `config.sample.json` nach `config.json` und passe die Werte an.

**Beispielkonfiguration:**

```json
{
  "General": {
    "GlobalTimeout": 7200,
    "RecreateStagingTable": false,
    "ForceFullSync": false,
    "NumberOfThreads": 4,
    "RunSanityCheck": true,
    "MaxRetries": 3,
    "RetryDelaySeconds": 10,
    "DeleteLogOlderThanDays": 30,
    "CleanupOrphans": false,
    "OrphanCleanupBatchSize": 50000,
    "IdColumn": "ID",
    "TimestampColumns": ["GESPEICHERT", "MODIFIED_DATE", "LAST_UPDATE"]
  },
  "Firebird": {
    "Server": "FIREBIRD01",
    "Database": "D:\\DB\\LA01_ECHT.FDB",
    "Port": 3050,
    "Charset": "UTF8"
  },
  "MSSQL": {
    "Server": "SQLSERVER01",
    "Integrated Security": true,
    "Database": "STAGING",
    "Prefix": "FB_",
    "Suffix": ""
  },
  "Tables": ["BKUNDE", "BLIEF", "BSA"],
  "TableOverrides": {
    "LEGACY_ORDERS": {
      "IdColumn": "ORDER_ID",
      "TimestampColumn": "CHANGED_AT"
    }
  }
}
```

_Hinweis zum MSSQL Port:_ Das Skript verwendet primär den `Server`-Parameter. Sollte ein nicht-standard Port (ungleich 1433) benötigt werden, geben Sie diesen bitte im Format `Servername,Port` im Feld `Server` an (z.B. `"SQLSERVER01,1433"`).

### Schritt 3: SQL Server Umgebung (Automatisch)

Das Hauptskript verfügt über einen **Pre-Flight Check**.
Wenn das Skript gestartet wird, passiert Folgendes automatisch:

1.  Verbindungsversuch zur Systemdatenbank `master`.
2.  **Datenbank erstellen:** Falls die Ziel-DB nicht existiert, wird sie erstellt und auf `RECOVERY SIMPLE` gesetzt.
3.  **Prozedur installieren:** Falls `sp_Merge_Generic` fehlt, wird sie aus der `sql_server_setup.sql` installiert.

### Schritt 4: Credentials sicher speichern

Führe das Setup-Skript aus, um Passwörter verschlüsselt im Windows Credential Manager zu speichern:

```powershell
.\Setup_Credentials.ps1
```

Abweichende Eintragsnamen (z. B. einer pro SQL Server): siehe [Credential Management](#credential-management).

### Schritt 5: Verbindung testen

```powershell
.\Test-SQLSyncConnections.ps1
```

Vor dem ersten produktiven Lauf und vor jedem Update zusätzlich die rein lesende Vor-Deployment-Prüfung ausführen (nur `SELECT`s, keine DDL/DML; die Treiber-DLL wird geprüft, nicht geladen):

```powershell
.\Test-SQLSyncConnections.ps1 -ConfigFile .\config.json -PreDeploy
```

Zusätzlich zum Verbindungstest prüft sie:

- alle `config*.json` im Skriptordner (außer `config.schema.json` / `config.sample.json`) gegen Schema und Namensregeln → `OK` / `FEHLER` (fehlende Schema-Datei → `WARNUNG`)
- die Treiber-DLL gegen die erlaubten SHA-256 → `OK` / `FEHLER` (noch keine DLL → `WARNUNG`); bei `FEHLER` sofortiger Abbruch mit Exit-Code 6
- die Firebird-Serverversion gegen bekannte Server-Advisories (CVE-2026-34232, CVE-2026-40342) → `WARNUNG`
- Anmeldung als `SYSDBA` → `WARNUNG` (Lesekonto verwenden)
- Altbestand: Dezimalspalten der konfigurierten Tabellen, deren Precision oder Scale im Ziel kleiner ist als in Firebird → `WARNUNG` mit Ziel- und Quelltyp (Korrektur: `docs/operations/RUNBOOK.md`)

Beispielausgabe (fiktive Namen und Version):

```text
...
========================================
  Vor-Deployment-Prüfung (-PreDeploy, nur lesend)
========================================
  OK       Konfig config.json         Schema und Namensregeln erfüllt
  OK       Konfig config_weekly_full.json Schema und Namensregeln erfüllt
  OK       Treiber-DLL                SHA-256 entspricht der erlaubten Liste: C:\ProgramData\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\lib\net8.0\FirebirdSql.Data.FirebirdClient.dll
  WARNUNG  Firebird-Version           Firebird 4.0.5: CVE-2026-34232 (CVSS 7.5, unauthentifizierter Server-Absturz (op_response)) – behoben ab 3.0.14 / 4.0.7 / 5.0.4
  WARNUNG  Firebird-Version           Firebird 4.0.5: CVE-2026-40342 (CVSS 9.9, Codeausführung über CREATE FUNCTION (ENGINE-Pfad)) – behoben ab 3.0.14 / 4.0.7 / 5.0.4
  WARNUNG  Firebird-Konto             Sync meldet sich als SYSDBA an – reines Lesekonto empfohlen (docs/operations/SETUP.md)
  WARNUNG  Altbestand DECIMAL         DWH_ARTICLES.WEIGHT: Ziel DECIMAL(18,4) < Quelle NUMERIC(15,6) – Korrektur siehe docs/operations/RUNBOOK.md
```

| Exit-Code | Bedeutung |
|---|---|
| 0 | Alle Tests erfolgreich; mit `-PreDeploy`: kein `FEHLER` (`WARNUNG` erlaubt) |
| 1 | Modul/Konfig fehlt oder ein Verbindungstest fehlgeschlagen |
| 2 | Konfiguration ungültig (Parsefehler, Schema, Namensregeln) |
| 3 | Credentials nicht gefunden |
| 4 | Treiber nicht ladbar (inkl. SHA-256-Abweichung) |
| 6 | `-PreDeploy` hat mindestens einen `FEHLER` gefunden – nicht deployen |

### Schritt 6: Tabellen auswählen

Starten Sie den GUI-Manager, um Tabellen auszuwählen:

```powershell
.\Manage_Config_Tables.ps1
# anderes Job-Profil:
.\Manage_Config_Tables.ps1 -ConfigFile .\config_weekly_full.json
```

Der Manager bietet eine **Toggle-Logik**:

- Markierte Tabellen, die _nicht_ in der Config sind -> Werden **hinzugefügt**.
- Markierte Tabellen, die _schon_ in der Config sind -> Werden **entfernt**.

Vor dem GridView wird die Konfiguration geprüft (Schema + Namensregeln; Verstoß → Exit 2, kein Backup). Eine Auswahl, die die letzte Tabelle entfernen würde, wird abgelehnt (Exit 4) – eine Config ohne Tabellen wird nie geschrieben. Auch `Get_Firebird_Schema.ps1 -TableName <Tabelle>` versteht `-ConfigFile`.

### Schritt 7: Automatische Aufgabenplanung (Optional)

Nutzen Sie das bereitgestellte Skript, um die Synchronisation im Windows Task Scheduler einzurichten. Das Skript erstellt Aufgaben für Daily Diff & Weekly Full.

**ACHTUNG:** Pfade und Config-Namen sind Parameter – das Skript muss nicht mehr bearbeitet werden. Defaults: Installationsordner = Ordner des Skripts, `config.json` (täglich) und `config_weekly_full.json` (wöchentlich). Das Ergebnis immer zuerst mit `-WhatIf` prüfen: Fehlende Dateien erzeugen nur eine Warnung, die Tasks würden trotzdem angelegt.

| Parameter | Default |
|---|---|
| `-InstallDir` | Ordner des Skripts |
| `-DailyConfigFile` / `-WeeklyConfigFile` | `config.json` / `config_weekly_full.json` (relativ zu `-InstallDir` oder absolut) |
| `-DailyTaskName` / `-WeeklyTaskName` | `SQLSync_Firebird_Daily_Diff` / `SQLSync_Firebird_Weekly_Full` |
| `-DailyStart`, `-DailyDays`, `-DailyIntervalMinutes`, `-DailyDurationHours` | `06:01`, Montag–Freitag, `30`, `15` |
| `-WeeklyDay`, `-WeeklyStart` | `Sunday`, `05:13` |
| `-RunAsUser` | aktueller Benutzer (Windows-Passwort wird abgefragt) |
| `-GmsaAccount` | – (gMSA als `DOMAIN\name$`, kein gespeichertes Passwort) |

```powershell
# 1. Vorschau: keine Adminrechte, keine Passwortabfrage, nichts wird registriert
.\Setup-ScheduledTasks.ps1 -InstallDir D:\Apps\SQLSync -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json -WhatIf

# 2. Registrieren (als Administrator ausführen!)
.\Setup-ScheduledTasks.ps1 -InstallDir D:\Apps\SQLSync -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json

# Optional: als gMSA statt als aktueller Benutzer
.\Setup-ScheduledTasks.ps1 -GmsaAccount 'EXAMPLE\svc-sqlsync$'
```

Hinweis zu gMSA: Credential-Manager-Einträge sind an das Konto gebunden, das sie anlegt. Mit einem gMSA für SQL Server vor allem `"Integrated Security": true` verwenden; Firebird-Credentials müssten im Kontext des gMSA angelegt werden.

**Bestehende Installationen:** Wer die bisher im Skript fest eingetragenen Pfade und Config-Namen genutzt hat, übergibt beim Neuanlegen der Tasks `-InstallDir`, `-DailyConfigFile` und `-WeeklyConfigFile` explizit (vorher mit `-WhatIf` prüfen). Bereits registrierte Tasks sind nicht betroffen.

---

## Nutzung

### Sync starten (Standard)

Startet den Sync mit der Standard-Datei `config.json` im Skriptverzeichnis:

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1
```

### Sync starten (Spezifische Config)

Für getrennte Jobs (z.B. Täglich inkrementell vs. Wöchentlich Full) kann eine Konfigurationsdatei übergeben werden:

```powershell
# Beispiel für einen Weekly-Job
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile "config_weekly_full.json"
```

### Ablauf des Sync-Prozesses

```text
┌─────────────────────────────────────────────────────────────┐
│  1. PRE-FLIGHT CHECK                                        │
│     Verbindung zu 'master', Auto-Create DB, Auto-Install SP │
├─────────────────────────────────────────────────────────────┤
│  2. INITIALISIERUNG (Modul laden)                           │
│     Config laden, Credentials aus Credential Manager holen  │
├─────────────────────────────────────────────────────────────┤
│  3. ANALYSE (pro Tabelle, parallel)                         │
│     Prüft Quell-Schema auf ID- und Timestamp-Spalten        │
│     → Wählt Strategie: Incremental / FullMerge / Snapshot   │
├─────────────────────────────────────────────────────────────┤
│  4. SCHEMA-CHECK                                            │
│     Erstellt STG_<Tabelle> falls nicht vorhanden            │
├─────────────────────────────────────────────────────────────┤
│  5. EXTRACT & LOAD                                          │
│     Firebird Reader -> BulkCopy Stream -> MSSQL Staging     │
├─────────────────────────────────────────────────────────────┤
│  6. MERGE                                                   │
│     sp_Merge_Generic: Staging -> Zieltabelle (mit Prefix)   │
│     Self-Healing: Erstellt fehlende Primary Keys            │
├─────────────────────────────────────────────────────────────┤
│  7. SANITY CHECK & RETRY LOOP                               │
└─────────────────────────────────────────────────────────────┘
```

### Sync-Strategien

| Strategie       | Bedingung                            | Verhalten                          |
| :-------------- | :----------------------------------- | :--------------------------------- |
| **Incremental** | ID + Timestamp-Spalte vorhanden      | Lädt nur Delta (schnellste Option) |
| **FullMerge**   | ID vorhanden, keine Timestamp-Spalte | Lädt alles, merged per ID          |
| **Snapshot**    | Keine ID                             | Truncate & vollständiger Insert    |

---

## Konfigurationsoptionen

### General Sektion

| Variable                 | Standard          | Beschreibung                                                       |
| :----------------------- | :---------------- | :----------------------------------------------------------------- |
| `GlobalTimeout`          | 7200              | Timeout in Sekunden für SQL-Befehle und BulkCopy                   |
| `RecreateStagingTable`   | `false`           | `true` = Staging bei jedem Lauf neu erstellen (Schema-Update)      |
| `ForceFullSync`          | `false`           | `true` = **Truncate** der Zieltabelle + vollständige Neuladung     |
| `NumberOfThreads`        | 4                 | Anzahl paralleler Threads für Tabellen-Sync                        |
| `RunSanityCheck`         | `true`            | `false` = Überspringt COUNT-Vergleich                              |
| `FailOnSanityError`      | `true`            | `false` = Sanity `FEHLER` führt nicht zu Exit-Code 11          |
| `IncrementalOverlapMinutes` | 10             | Incremental: liest ab `MAX(Zeitstempel)` im Ziel minus X Minuten (0–1440) |
| `MaxRetries`             | 3                 | Wiederholungsversuche bei Fehler                                   |
| `RetryDelaySeconds`      | 10                | Wartezeit zwischen Retries                                         |
| `DeleteLogOlderThanDays` | 30                | Löscht Logs automatisch nach X Tagen (0 = Deaktiviert)             |
| `CleanupOrphans`         | `false`           | Verwaiste Datensätze im Ziel löschen                               |
| `OrphanCleanupBatchSize` | 50000             | Batch-Größe für ID-Transfer beim Cleanup                           |
| `IdColumn`               | `"ID"`            | Standard-Name der ID-Spalte für alle Tabellen                      |
| `TimestampColumns`       | `["GESPEICHERT"]` | Liste möglicher Timestamp-Spalten (erste gefundene wird verwendet) |

### Spalten-Konfiguration (NEU in v2.10)

Das Skript unterstützt jetzt flexible Spalten-Konfiguration für unterschiedliche Tabellenstrukturen. Dadurch ist es mit jeder Firebird-Datenbank kompatibel, nicht nur AvERP.

**Globale Defaults:**

```json
{
  "General": {
    "IdColumn": "ID",
    "TimestampColumns": [
      "GESPEICHERT",
      "MODIFIED_DATE",
      "LAST_UPDATE",
      "CHANGED_AT"
    ]
  }
}
```

- `IdColumn`: Der Standard-Primärschlüssel-Spaltenname für MERGE-Operationen
- `TimestampColumns`: Eine Liste möglicher Timestamp-Spaltennamen. Das Skript prüft jede Spalte der Reihe nach und verwendet die erste, die in der Quelltabelle gefunden wird.

**Tabellenspezifische Überschreibungen:**

Für Tabellen mit nicht-standardisierten Spaltennamen verwenden Sie `TableOverrides`:

```json
{
  "TableOverrides": {
    "LEGACY_ORDERS": {
      "IdColumn": "ORDER_ID",
      "TimestampColumn": "CHANGED_AT"
    },
    "AUDIT_LOG": {
      "IdColumn": "LOG_ID"
    }
  }
}
```

**Auflösungs-Logik:**

1. Prüfe ob `TableOverrides[Tabellenname]` existiert → Override-Werte verwenden
2. `IdColumn`: Override → Globale `IdColumn` → `"ID"` (Default)
3. `TimestampColumn`: Override → Erste gefundene aus `TimestampColumns`-Liste → `null`
4. Strategiewahl: HasId + HasTimestamp → Incremental | HasId → FullMerge | sonst → Snapshot

**Rückwärtskompatibilität:**

Ohne jegliche Konfiguration verwendet das Skript `"ID"` und `"GESPEICHERT"` als Defaults und bleibt damit vollständig rückwärtskompatibel mit bestehenden Setups.

### Orphan-Cleanup (Löschungserkennung)

Wenn `CleanupOrphans: true` gesetzt ist, werden nach dem Sync alle Datensätze im Ziel gelöscht, die in der Quelle nicht mehr existieren.

**Ablauf:**

1.  Alle IDs aus Firebird in eine Temp-Tabelle laden (in Batches für Speichereffizienz)
2.  `DELETE FROM Ziel WHERE ID NOT IN (SELECT ID FROM #TempIDs)`
3.  Temp-Tabelle aufräumen

**Einschränkungen:**

- Funktioniert nur bei Tabellen mit ID-Spalte (nicht bei Snapshot-Strategie)
- Erhöht die Laufzeit, da alle IDs übertragen werden müssen
- Nicht nötig bei `ForceFullSync` (Tabelle wird eh komplett neu geladen)

**Empfehlung:**

- `CleanupOrphans: false` für tägliche Diff-Syncs (Performance)
- `CleanupOrphans: true` für wöchentliche Full-Syncs (Datenbereinigung)

### MSSQL Prefix & Suffix

Steuern die Namensgebung im Zielsystem.

- **Prefix**: `DWH_` -> Zieltabelle wird `DWH_KUNDE`
- **Suffix**: `_V1` -> Zieltabelle wird `KUNDE_V1`

### Namensregeln (seit v2.12)

Tabellen- und Spaltennamen (`Tables`, `General.IdColumn`, `General.TimestampColumns`, `TableOverrides`-Schlüssel und -Werte) sowie `MSSQL.Database`, `MSSQL.Prefix` und `MSSQL.Suffix` dürfen nur `A-Z`, `a-z`, `0-9`, `_` und `$` enthalten und höchstens 63 Zeichen lang sein (Firebird-Limit). Prefix + Tabelle + Suffix dürfen 128 Zeichen nicht überschreiten (SQL-Server-Limit). Leer erlaubt nur bei `MSSQL.Database`, Prefix/Suffix und den Override-Spalten.

Ein Verstoß bricht den Sync beim Laden der Konfiguration ab (Exit-Code 2; Meldung der Schema-Prüfung `Konfiguration verletzt das Schema …` bzw. `Ungültiger Name in '<Feld>': …` aus der Code-Prüfung), bevor eine Datenbankverbindung geöffnet wird. `Manage_Config_Tables.ps1` bietet Firebird-Tabellen mit ungültigem Namen nicht zur Übernahme an.

### JSON-Schema-Validierung

Seit v2.15 prüft jedes Skript (`Sync_Firebird_MSSQL_AutoSchema.ps1`, `Test-SQLSyncConnections.ps1`, `Get_Firebird_Schema.ps1`, `Manage_Config_Tables.ps1`) die Konfiguration beim Laden gegen `config.schema.json` (`Get-SQLSyncConfig -SchemaPath`). Jeder Verstoß beendet das Skript mit Exit-Code 2, bevor eine Datenbankverbindung geöffnet wird, z. B.:

```
Konfiguration verletzt das Schema (config.schema.json): ... bei "/General/GlobalTimeout"; ...
```

Jeder Verstoß nennt seinen JSON-Pfad. Erkannt werden falsche Typen (`"7200"` statt `7200`), fehlende Pflichtfelder, Werte außerhalb der Grenzen und **unbekannte Schlüssel** (Tippfehler wie `ForceFulSync`, da das Schema `additionalProperties: false` verwendet). Neue Konfigurationsschlüssel müssen deshalb immer auch im Schema ergänzt werden.

`config.schema.json` gehört zu jeder Installation. Fehlt die Datei, erscheint nur eine Warnung und der Lauf geht ohne Schema-Prüfung weiter.

Eine Konfiguration manuell prüfen (z. B. vor einem Update), ohne Datenbankzugriff:

```powershell
Test-Json -Json (Get-Content .\config.json -Raw) -Schema (Get-Content .\config.schema.json -Raw)
```

---

## Modul-Architektur

PSFirebirdToMSSQL verwendet ein gemeinsames PowerShell-Modul (`SQLSyncCommon.psm1`) für wiederverwendbare Funktionen. Dieses Modul muss immer im Skriptverzeichnis liegen.

Das Modul stellt zentral folgende Funktionen bereit:

- **Credential Management:** `Get-StoredCredential`, `Resolve-FirebirdCredentials`
- **Configuration:** `Get-SQLSyncConfig` (inkl. Schema-Validierung, Fail-Fast), `Resolve-SQLSyncConfigPath` (gemeinsame Auflösung von `-ConfigFile`)
- **Spalten-Konfiguration:** `Get-TableColumnConfig` (ermittelt ID/Timestamp-Spalten pro Tabelle)
- **Driver Loading:** `Initialize-FirebirdDriver`, `Test-FirebirdDriverIntegrity` (Hash-Prüfung ohne Laden; Konstanten in `$script:FirebirdDriver`)
- **Rollout-Check:** `Get-FirebirdServerAdvisory` (Serverversion gegen bekannte CVEs in `$script:FirebirdServerAdvisories`), `Find-SQLSyncDecimalTruncation` (Ziel-`DECIMAL`-Spalten kleiner als die Quelle); genutzt von `Test-SQLSyncConnections.ps1 -PreDeploy`
- **Type Mapping:** `ConvertTo-SqlServerType` (.NET zu SQL Datentypen; `Decimal` mit Precision/Scale aus dem Firebird-Schema). Seit v2.14 importiert der Parallel-Block des Syncs das Modul und nutzt `ConvertTo-SqlServerType` und `Get-TableColumnConfig` direkt

---

## Verwendung in eigenen Skripten

```powershell
Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force

$Config = Get-SQLSyncConfig -ConfigPath ".\config.json"
$FbCreds = Resolve-FirebirdCredentials -Config $Config.RawConfig

$ConnStr = New-FirebirdConnectionString `
    -Server $Config.FBServer `
    -Database $Config.FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password

# Direkt mit try/finally arbeiten (empfohlen)
$FbConn = $null
try {
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($ConnStr)
    $FbConn.Open()

    $cmd = $FbConn.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM MYTABLE"
    $cmd.ExecuteScalar()
}
finally {
    Close-DatabaseConnection -Connection $FbConn
}
```

---

## Credential Management

Die Credentials werden im Windows Credential Manager unter folgenden Namen gespeichert:

- `SQLSync_Firebird`
- `SQLSync_MSSQL`

Das sind die Defaults. Die optionalen Schlüssel `Firebird.CredentialTarget` und `MSSQL.CredentialTarget` wählen einen anderen Eintrag, z. B. wenn mehrere SQL Server denselben Login (etwa `sa`) mit unterschiedlichen Passwörtern nutzen. Den Eintrag mit dem passenden Parameter anlegen:

```powershell
.\Setup_Credentials.ps1 -MSSQLTarget "SQLSync_MSSQL_sqltest"   # analog: -FirebirdTarget
```

```json
"MSSQL": { "Server": "sqltest", "Database": "STAGING", "CredentialTarget": "SQLSync_MSSQL_sqltest" }
```

Das Log nennt den verwendeten Eintrag, z. B. `[Credentials] SQL Server: Credential Manager (SQLSync_MSSQL_sqltest)`. Die Einträge bleiben an das Windows-Konto gebunden, unter dem `Setup_Credentials.ps1` lief.

```powershell
# Anzeigen
cmdkey /list:SQLSync*

# Löschen
cmdkey /delete:SQLSync_Firebird
cmdkey /delete:SQLSync_MSSQL
```

---

## Logging

Alle Ausgaben werden automatisch in eine Log-Datei geschrieben:
`Logs\Sync_<ConfigName>_YYYY-MM-DD_HHmm.log`

### Exit-Codes

| Code | Bedeutung |
|---|---|
| 0 | Alle Tabellen erfolgreich synchronisiert |
| 1 | `SQLSyncCommon.psm1` nicht gefunden |
| 2 | Konfigurationsfehler (inkl. Schema-Verstoß und ungültiger Tabellen-/Spaltennamen) |
| 5 | Credentials nicht gefunden |
| 7 | Firebird-Treiber nicht ladbar (inkl. SHA-256-Abweichung der Treiber-DLL) |
| 9 | Pre-Flight (Datenbank / `sp_Merge_Generic`) fehlgeschlagen |
| 10 | Mindestens eine Tabelle fehlgeschlagen |
| 11 | Sanity Check `FEHLER` (Ziel hat weniger Zeilen als Quelle); abschaltbar über `FailOnSanityError` |

Die Aufgabenplanung zeigt den Code als *Letztes Ausführungsergebnis* (z. B. `0xA` = 10).

---

## Wichtige Hinweise

### Löschungen werden im Standard nicht synchronisiert (CleanupOrphans Option)

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten (Historie). Um dies zu bereinigen, nutzen Sie `ForceFullSync: true` in einem regelmäßigen Wartungs-Task (z.B. Sonntags), der die Zieltabellen leert und neu aufbaut. Aktualisiert auch das Schema.
Alternativ kann `CleanupOrphans: true` genutzt werden, um IDs abzugleichen.

### Task Scheduler Integration (Pfadanpassung)

Es wird empfohlen, die Tasks mit `Setup-ScheduledTasks.ps1` anzulegen (siehe Schritt 7). Installationsordner und Config-Namen werden als Parameter übergeben (`-InstallDir`, `-DailyConfigFile`, `-WeeklyConfigFile`); `-WhatIf` zeigt die resultierenden Task-Definitionen, ohne etwas zu registrieren.

Manuelle Aufruf-Parameter für eigene Integrationen:

```text
Programm: pwsh.exe
Argumente: -ExecutionPolicy Bypass -File "C:\Scripts\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "config.json"
Starten in: C:\Scripts
```

---

## Architektur

```text
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│    Firebird      │         │   PowerShell 7   │         │   SQL Server     │
│   (Quelle)       │         │   ETL Engine     │         │   (Ziel)         │
├──────────────────┤         ├──────────────────┤         ├──────────────────┤
│                  │  Read   │                  │  Write  │                  │
│  Tabelle A       │ ──────► │  Parallel Jobs   │ ──────► │  STG_A (Staging) │
│  Tabelle B       │         │  (ThrottleLimit) │         │  STG_B (Staging) │
│                  │         │                  │         │                  │
│                  │         │  SQLSyncCommon   │         │                  │
│                  │         │  🔐 Cred Manager │         │                  │
│                  │         │  ↻ Retry Loop    │         │                  │
│                  │         │  📄 Transcript   │         │                  │
└──────────────────┘         └────────┬─────────┘         ├──────────────────┤
                                      │                   │                  │
                                      │ EXEC SP           │  sp_Merge_Generic│
                                      └─────────────────► │         ↓        │
                                                          │  Prefix_A_Suffix │
                                                          │  Prefix_B_Suffix │
                                                          └──────────────────┘
```

---

## Changelog

Die Versionsnummern bezeichnen den Stand des Repositorys. Jedes Skript trägt die Nummer der letzten Version, die es geändert hat (`Sync_Firebird_MSSQL_AutoSchema.ps1`: 2.18 – v2.13 und v2.17 betrafen nur andere Dateien; `Test-SQLSyncConnections.ps1`: 2.1).

### v2.18 (2026-10-09) - Überlappungsfenster im Incremental
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.18: Der inkrementelle Extrakt liest ab dem Wasserzeichen (`MAX(Zeitstempel)` der Zieltabelle) **minus Überlappungsfenster**, inklusive (`>= @LastDate`; bis v2.16 strikt `> MAX(ts)`). Datensätze mit Zeitstempel ≤ Wasserzeichen, die erst nach dem letzten Lauf committet wurden, werden nachgeholt, sofern die Verzögerung kleiner als das Fenster ist (bekannte Einschränkung K3). Längere Verzögerungen holt weiterhin erst der wöchentliche Full-Lauf (`ForceFullSync`)
- Neuer optionaler Konfigschlüssel `General.IncrementalOverlapMinutes` (Ganzzahl 0–1440, Default 10; 0 = ab dem Wasserzeichen selbst, inklusive). Werte außerhalb des Bereichs weisen Schema und `Get-SQLSyncConfig` ab
- `RowsLoaded` enthält jetzt auch die im Fenster erneut gelesenen Zeilen und ist daher auch ohne Quelländerung oft > 0 (der MERGE ist idempotent, keine Duplikate)
- Scheitert die `MAX`-Abfrage auf eine vorhandene Zieltabelle (z. B. Zeitstempelspalte fehlt im Ziel, Timeout), läuft die Tabelle durch die Retry-Schleife und endet mit Status `Fehler` (Exit-Code 10); bis v2.16 folgte daraus still ein Vollabzug ab 1900-01-01. Fehlende oder leere Zieltabelle → Vollabzug mit Info `(Erstlauf (Zieltabelle fehlt) - Vollabzug)` bzw. `(Kein Wasserzeichen (Zieltabelle leer oder Zeitstempel NULL) - Vollabzug)`
- Neue Modulfunktionen `Get-SQLSyncIncrementalLowerBound`, `Get-SQLSyncIncrementalWatermark` und `Get-SQLSyncExtractQuery` (erster Schnitt der Zerlegung des Hauptskripts; der Extrakt ist damit unit-getestet); 176 Pester-Tests

### v2.17 (2026-10-09) - Rollout-Check (`-PreDeploy`)
- `Test-SQLSyncConnections.ps1` v2.1: neuer Schalter `-PreDeploy`, rein lesend (nur `SELECT`s). Prüft alle `config*.json` im Skriptordner gegen Schema und Namensregeln, die Treiber-DLL gegen die erlaubten SHA-256 (ohne sie zu laden), die Firebird-Serverversion gegen bekannte Server-Advisories, eine Anmeldung als `SYSDBA` und Altbestand-Zielspalten, deren `DECIMAL`-Typ Quellwerte kürzt. Ausgabe als Tabelle Status/Prüfung/Detail; Exit-Code 6 bei mindestens einem `FEHLER` (`WARNUNG` lässt Exit-Code 0 zu)
- Neue Modulfunktionen `Get-FirebirdServerAdvisory`, `Find-SQLSyncDecimalTruncation` und `Test-FirebirdDriverIntegrity` (Status `OK` / `FEHLER` / `FEHLT`, lädt die DLL nicht)
- Treiberkonstanten (Version, Download-URL, erlaubte Hashes) liegen jetzt an einer Stelle (`$script:FirebirdDriver`); `Initialize-FirebirdDriver` und `Test-FirebirdDriverIntegrity` nutzen dieselbe Kandidatensuche. Bekannte Firebird-Server-CVEs stehen in `$script:FirebirdServerAdvisories`
- `Test-SQLSyncConnections.ps1` gibt die Test-Query-Zeile nicht mehr doppelt aus
- `Sync_Firebird_MSSQL_AutoSchema.ps1` unverändert (2.16); 157 Pester-Tests

### v2.16 (2026-10-09) - Integritätsprüfung des Treibers
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.16: reicht `Firebird.DllSha256` an die Treiberprüfung durch
- `Initialize-FirebirdDriver` prüft **jede** DLL vor `Add-Type` per SHA-256: frischer Download, bereits in `%ProgramData%\SQLSync\Drivers\...` vorhandene DLL und per `Firebird.DllPath` konfigurierte DLL (vorher nur der Download). Zulässig: Original-Hashes von `lib\net8.0` und `lib\netstandard2.1` aus dem NuGet-Paket 10.3.4. Abweichung → `SHA-256 der Treiber-DLL (vorhanden|Download) stimmt nicht ... Treiber wurde NICHT geladen`, Sync-Exit-Code 7 (`Test-SQLSyncConnections.ps1` 4, `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1` 3); ein abweichender Download-Ordner wird verworfen
- Neuer optionaler Konfigschlüssel `Firebird.DllSha256` (Schema `^[A-Fa-f0-9]{64}$`) bzw. Parameter `-ExpectedSha256` für eine abweichende Treiber-DLL; dann gilt nur dieser Hash. Alle vier Skripte reichen ihn durch
- `ServicePointManager.SecurityProtocol` wird nur für den Download gesetzt und danach wiederhergestellt
- Admin-Check ist jetzt die Modulfunktion `Test-SQLSyncIsAdministrator` (nicht exportiert), dadurch ist der Download-/Hash-Pfad unit-getestet (138 Pester-Tests)
- Grenze: Ist die Assembly in der Sitzung bereits geladen (z. B. durch ein anderes Modul), wird sie ohne Prüfung weiterverwendet
- Sicherheitshinweis: Firebird-Server-CVE-2026-40342 (CVSS 9.9, < 5.0.4 / < 4.0.7 / < 3.0.14) – Firebird-Lesekonto statt `SYSDBA` verwenden und Server aktualisieren

### v2.15 (2026-10-09) - Schema-Prüfung aktiv
- `Get-SQLSyncConfig -SchemaPath` prüft jetzt Fail-Fast gegen `config.schema.json` (`Test-Json -Schema`, in allen PowerShell-7-Versionen verfügbar): Fehler `Konfiguration verletzt das Schema (config.schema.json): …` mit JSON-Pfad je Verstoß; unbekannte Schlüssel (Tippfehler) werden erkannt. Fehlt die Schema-Datei, erscheint nur eine Warnung
- Alle vier Skripte übergeben `-SchemaPath`; ein Verstoß beendet sie mit Exit-Code 2 vor jeder Datenbankverbindung (`Manage_Config_Tables.ps1` zusätzlich vor GridView und Backup)
- Neue Modulfunktion `Resolve-SQLSyncConfigPath` ersetzt die kopierte `-ConfigFile`-Auflösung in Sync- und Testskript
- `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1` haben den neuen Parameter `-ConfigFile` (vorher fest `config.json`). `Manage_Config_Tables.ps1` v2.1 prüft beim Start über `Get-SQLSyncConfig` und verweigert das Entfernen der letzten Tabelle (Exit 4)
- `config.schema.json`: Namensmuster an die Identifier-Whitelist angeglichen (`Tables`, `IdColumn`, `TimestampColumns`, Override-Spalten `^[A-Za-z0-9_$]+$`, max. 63; Prefix/Suffix `^[A-Za-z0-9_$]*$`)
- **Bestehende Installationen:** `config.schema.json` mit ausliefern und vor dem Update jede produktive Config prüfen: `Test-Json -Json (Get-Content <cfg> -Raw) -Schema (Get-Content config.schema.json -Raw)`

### v2.14 (2026-10-08) - Precision/Scale für DECIMAL
- `ConvertTo-SqlServerType` hat neue Parameter `-Precision`/`-Scale` (Werte `NumericPrecision`/`NumericScale` aus `GetSchemaTable`, DBNull erlaubt): `Decimal` wird zu `DECIMAL(p,s)`; Precision > 38 wird auf 38 begrenzt; Precision fehlt, Scale bekannt → `DECIMAL(38,s)`; beides fehlt → bisheriger Fallback `DECIMAL(18,4)`. Andere Typen unverändert
- `Sync_Firebird_MSSQL_AutoSchema.ps1`: doppeltes Inline-Typmapping und Inline-Spalten-/Strategieermittlung entfernt; der Parallel-Block importiert das Modul und nutzt `ConvertTo-SqlServerType` (damit auch `Guid` → `UNIQUEIDENTIFIER`) und `Get-TableColumnConfig`. Strategiewahl unverändert
- `Get_Firebird_Schema.ps1`: Ausgabe um Spalten `Precision`/`Scale` erweitert; der Typvorschlag berücksichtigt sie
- **Bestehende Installationen:** Der Sync ändert keine bestehenden Tabellen. Zieltabellen, die mit v2.13 oder älter angelegt wurden, behalten `DECIMAL(18,4)` und runden Werte mit mehr als 4 Nachkommastellen weiter – auch wenn die Staging-Tabelle neu angelegt wird. Betroffene Spalten prüfen (`Get_Firebird_Schema.ps1 -TableName <Tabelle>`) und per `ALTER TABLE ... ALTER COLUMN ... DECIMAL(p,s)` korrigieren oder Zieltabelle löschen und einmal mit `RecreateStagingTable: true` + `ForceFullSync: true` laufen lassen

### v2.13 (2026-10-08) - Parametrisierte Aufgabenplanung
- `Setup-ScheduledTasks.ps1` enthält keine fest eingetragenen Pfade oder Config-Namen mehr: neue Parameter `-InstallDir` (Default: Ordner des Skripts), `-DailyConfigFile` (`config.json`), `-WeeklyConfigFile` (`config_weekly_full.json`), Tasknamen, Zeitplan (`-DailyStart`, `-DailyDays`, `-DailyIntervalMinutes`, `-DailyDurationHours`, `-WeeklyDay`, `-WeeklyStart`) und Konto (`-RunAsUser`)
- `-WhatIf` berechnet und gibt die Task-Definitionen aus – ohne Adminrechte, Passwortabfrage und Registrierung; Ausgabe je Task ein Objekt (`TaskName`, `Action`, `Trigger`, `Settings`, `Principal`, `Registered`)
- Neue Option `-GmsaAccount` (`DOMAIN\name$`): Tasks laufen als gMSA ohne gespeichertes Passwort
- Admin-Prüfung zur Laufzeit (Exit 1) statt `#Requires -RunAsAdministrator`; abgebrochene Passworteingabe → Exit 1
- **Bestehende Installationen:** beim Neuanlegen der Tasks `-InstallDir`, `-DailyConfigFile` und `-WeeklyConfigFile` explizit übergeben; bereits registrierte Tasks sind nicht betroffen

### v2.12 (2026-10-08) - SQL-Identifier-Härtung
- Neue Modulfunktion `Assert-SqlIdentifier`: Tabellen-/Spaltennamen, `MSSQL.Database`, Prefix/Suffix und `TableOverrides` werden beim Laden der Konfiguration gegen `^[A-Za-z0-9_$]+$` (max. 63 Zeichen) geprüft; Zieltabellenname max. 128 Zeichen; Verstoß → Exit 2
- Alle SQL-Server-Tabellennamen in eckigen Klammern; Metadaten-Abfragen (`INFORMATION_SCHEMA`, `sys.indexes`) mit Parametern; `sp_Merge_Generic` wird als Stored Procedure mit Parametern aufgerufen
- `Manage_Config_Tables.ps1` prüft `IdColumn`/`TimestampColumns` (Exit 2) und überspringt Firebird-Tabellen mit ungültigem Namen

### v2.11 (2026-10-08) - Exit-Codes
- Sync endet jetzt mit 10 (Tabellenfehler) bzw. 11 (Sanity `FEHLER`) statt immer mit 0
- Fehler beim Einspielen von `sql_server_setup.sql` brechen den Pre-Flight ab (Exit 9) statt nur zu warnen
- Neue Option `General.FailOnSanityError` (Default `true`)
- Neue Optionen `Firebird.CredentialTarget` / `MSSQL.CredentialTarget` (Name des Credential-Manager-Eintrags, Defaults `SQLSync_Firebird` / `SQLSync_MSSQL`); `Setup_Credentials.ps1` erhält `-FirebirdTarget` / `-MSSQLTarget`

### v2.10 (2025-12-09) - Dynamische Spalten-Konfiguration

- **NEU:** `IdColumn` - Globale Konfiguration der ID-Spalte (Standard: "ID")
- **NEU:** `TimestampColumns` - Liste möglicher Timestamp-Spalten (erste gefundene wird verwendet)
- **NEU:** `TableOverrides` - Tabellenspezifische Überschreibungen für ID- und Timestamp-Spalten
- **NEU:** `Get-TableColumnConfig` Funktion im Modul für wiederverwendbare Spalten-Logik
- **Feature:** Automatische Strategiewahl basierend auf vorhandenen Spalten
- **Rückwärtskompatibel:** Ohne Konfiguration werden weiterhin "ID" und "GESPEICHERT" verwendet

### v2.9 (2025-12-06) - Orphan-Cleanup (Soft Deletes)

- **NEU:** `CleanupOrphans` Option - Erkennt und löscht verwaiste Datensätze im Ziel
- **NEU:** `OrphanCleanupBatchSize` - Konfigurierbarer Batch-Size für große Tabellen
- **NEU:** "Del" Spalte in Zusammenfassung zeigt gelöschte Orphans an
- Batch-basierter ID-Transfer für Memory-Effizienz bei >100.000 Zeilen

### v2.8 (2025-12-06) - Modul-Architektur & Bugfixes

- **NEU:** `SQLSyncCommon.psm1` - Gemeinsames Modul für wiederverwendbare Funktionen.
- **NEU:** `config.schema.json` - JSON-Schema für Konfigurationsvalidierung.
- **FIX:** Connection Leak behoben - Connections werden jetzt garantiert geschlossen.
- **FIX:** `Get_Firebird_Schema.ps1` - Fehlende `Get-StoredCredential` Funktion behoben.
- **Refactoring:** Duplizierter Code in alle Skripte entfernt (~60% weniger Redundanz).

### v2.7 (2025-12-04) - Auto-Setup & Robustness

- **Feature:** Integrierter Pre-Flight Check: Erstellt Datenbank und installiert `sp_Merge_Generic` automatisch (via `sql_server_setup.sql`), falls fehlend.
- **Fix:** Verbesserte Behandlung von SQL-Kommentaren beim Einlesen von SQL-Dateien.

### v2.6 (2025-12-03) - Task Automation

- **Neu:** `Setup-ScheduledTasks.ps1` zur automatischen Einrichtung der Windows-Aufgabenplanung.

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` und `MSSQL.Suffix` implementiert.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager Integration.

---

<a id="-haftungsausschluss-disclaimer"></a>
## ⚖ Haftungsausschluss (Disclaimer)

**Firebird ist eine eingetragene Marke der Firebird Foundation.**
Dieses Tool ist Open-Source-Software und ist **nicht** mit der Firebird Foundation verbunden, von ihr unterstützt oder assoziiert.