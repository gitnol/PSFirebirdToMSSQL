# SQLSync: Firebird to MSSQL High-Performance Synchronizer

Hochperformante, parallelisierte ETL-Lösung zur inkrementellen Synchronisation von Firebird-Datenbanken (z.B. AvERP) nach Microsoft SQL Server.

Ersetzt veraltete Linked-Server-Lösungen durch einen modernen PowerShell-Ansatz mit `SqlBulkCopy` und intelligentem Schema-Mapping.

---

## Inhaltsverzeichnis

- [SQLSync: Firebird to MSSQL High-Performance Synchronizer](#sqlsync-firebird-to-mssql-high-performance-synchronizer)
  - [Inhaltsverzeichnis](#inhaltsverzeichnis)
  - [Features](#features)
  - [Dateistruktur](#dateistruktur)
  - [Voraussetzungen](#voraussetzungen)
  - [Installation](#installation)
    - [Schritt 1: SQL Server vorbereiten](#schritt-1-sql-server-vorbereiten)
    - [Schritt 2: Konfiguration anlegen](#schritt-2-konfiguration-anlegen)
    - [Schritt 3: Credentials sicher speichern](#schritt-3-credentials-sicher-speichern)
    - [Schritt 4: Verbindung testen](#schritt-4-verbindung-testen)
    - [Schritt 5: Tabellen auswählen](#schritt-5-tabellen-auswählen)
  - [Nutzung](#nutzung)
    - [Sync starten (Standard)](#sync-starten-standard)
    - [Sync starten (Spezifische Config)](#sync-starten-spezifische-config)
    - [Ablauf des Sync-Prozesses](#ablauf-des-sync-prozesses)
    - [Sync-Strategien](#sync-strategien)
  - [Konfigurationsoptionen](#konfigurationsoptionen)
    - [General Sektion](#general-sektion)
    - [MSSQL Prefix \& Suffix (Neu)](#mssql-prefix--suffix-neu)
  - [Credential Management](#credential-management)
  - [Logging](#logging)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden nicht synchronisiert](#löschungen-werden-nicht-synchronisiert)
    - [Task Scheduler Integration](#task-scheduler-integration)
  - [Changelog](#changelog)
    - [v2.5 (2025-11-29) - Prefix/Suffix \& Fixes](#v25-2025-11-29---prefixsuffix--fixes)
    - [v2.4 (2025-11-26) - Config Parameter](#v24-2025-11-26---config-parameter)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)
    - [v2.0 (2025-11-24) - Production Release](#v20-2025-11-24---production-release)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz mit Memory-Streaming)
- **Inkrementeller Sync**: Lädt nur geänderte Daten (Delta) basierend auf der `GESPEICHERT`-Spalte (High Watermark Pattern)
- **Flexible Namensgebung**: Unterstützt **Prefixe** und **Suffixe** für Zieltabellen (z.B. Quelle `KUNDE` -> Ziel `DWH_KUNDE_V1`).
- **Multi-Config Support**: Skript akzeptiert per Parameter unterschiedliche Konfigurationsdateien (z.B. für Daily vs. Weekly Jobs).
- **Automatische Schema-Erstellung**: Erstellt Staging- und Zieltabellen automatisch mit intelligentem Datentyp-Mapping
- **Self-Healing**: Erkennt und repariert fehlende Primärschlüssel und Indizes automatisch
- **Parallelisierung**: Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`)
- **Drei Sync-Strategien**: Incremental, FullMerge oder Snapshot je nach Tabellenstruktur
- **Sichere Credentials**: Windows Credential Manager statt Klartext-Passwörter in Config-Dateien
- **Datei-Logging**: Vollständiges Transcript aller Ausgaben in `Logs\Sync_<ConfigName>_*.log`
- **Retry-Logik**: Automatische Wiederholung bei Verbindungsfehlern
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau

---

## Dateistruktur

```text
SQLSync/
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract → Staging → Merge)
├── Setup_Credentials.ps1                 # Einmalig: Passwörter sicher speichern
├── Manage_Config_Tables.ps1              # GUI-Tool zur Tabellenverwaltung
├── Get_Firebird_Schema.ps1               # Hilfstool: Datentyp-Analyse
├── Update_sp_Merge_Generic_V2.sql        # SQL Update für flexible Tabellennamen
├── test_dotnet_firebird.ps1              # Verbindungstest
├── config.json                           # Zugangsdaten & Einstellungen (git-ignoriert)
├── config.sample.json                    # Konfigurationsvorlage
├── .gitignore                            # Schützt config.json
└── Logs/                                 # Log-Dateien (automatisch erstellt)
    └── Sync_config_2025-11-29_1300.log
```

---

## Voraussetzungen

| Komponente             | Anforderung                                       |
| :--------------------- | :------------------------------------------------ |
| PowerShell             | Version 7.0 oder höher (zwingend für `-Parallel`) |
| Firebird .NET Provider | Wird automatisch via NuGet installiert            |
| Firebird-Zugriff       | Leserechte auf der Quelldatenbank                 |
| MSSQL-Zugriff          | `db_owner` oder `ddl_admin` auf der Zieldatenbank |

---

## Installation

### Schritt 1: SQL Server vorbereiten

Führe das SQL-Skript `Update_sp_Merge_Generic_V2.sql` auf deinem Microsoft SQL Server aus.

**WICHTIG:** Die neue Version der Stored Procedure (`sp_Merge_Generic`) ist zwingend erforderlich, da sie nun zwei Parameter (`@TargetTableName`, `@StagingTableName`) akzeptiert, um Prefixe und Suffixe zu unterstützen.

```sql
-- Erstellt oder aktualisiert:
-- PROCEDURE [dbo].[sp_Merge_Generic]
-- Akzeptiert jetzt separate Namen für Staging und Ziel.
```

### Schritt 2: Konfiguration anlegen

Kopiere `config.sample.json` nach `config.json`.

**Beispielkonfiguration:**

```json
{
  "General": {
    "GlobalTimeout": 7200,
    "RecreateStagingTable": false,
    "ForceFullSync": false,
    "RunSanityCheck": true,
    "MaxRetries": 3,
    "RetryDelaySeconds": 10
  },
  "Firebird": {
    "Server": "svrerp01",
    "Database": "D:\\DB\\LA01_ECHT.FDB",
    "Port": 3050,
    "Charset": "UTF8",
    "DllPath": "C:\\Program Files\\..."
  },
  "MSSQL": {
    "Server": "SVRSQL03",
    "Database": "STAGING",
    "Integrated Security": true,
    "Prefix": "DWH_",
    "Suffix": ""
  },
  "Tables": []
}
```

### Schritt 3: Credentials sicher speichern

Führe das Setup-Skript aus, um Passwörter verschlüsselt im Windows Credential Manager zu speichern:

```powershell
.\Setup_Credentials.ps1
```

### Schritt 4: Verbindung testen

```powershell
.\test_dotnet_firebird.ps1
```

### Schritt 5: Tabellen auswählen

Starten Sie den GUI-Manager, um Tabellen auszuwählen:

```powershell
.\Manage_Config_Tables.ps1
```

Der Manager bietet eine **Toggle-Logik**:

- Markierte Tabellen, die _nicht_ in der Config sind -> Werden **hinzugefügt**.
- Markierte Tabellen, die _schon_ in der Config sind -> Werden **entfernt**.
- Nicht markierte Tabellen -> Bleiben unverändert.

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

1.  **Initialisierung**: Config laden, Credentials aus Tresor holen.
2.  **Analyse**: Prüft Quell-Schema. Bestimmt Strategie (Incremental/Full/Snapshot).
3.  **Staging**:
    - Prüft Existenz von `STG_<OriginalName>`.
    - Erstellt Tabelle bei Bedarf neu.
4.  **Extract**: Lädt Daten aus Firebird.
    - Incremental: `WHERE GESPEICHERT > MAX(Ziel.GESPEICHERT)`
    - _Hinweis: Das MaxDatum wird jetzt korrekt aus der Zieltabelle (mit Prefix/Suffix) gelesen._
5.  **Load**: Bulk Insert in Staging.
6.  **Merge**:
    - Prüft Existenz der Zieltabelle (`Prefix + Name + Suffix`).
    - Erstellt Zieltabelle und Indizes falls nötig (Self-Healing).
    - Ruft `sp_Merge_Generic` auf.
7.  **Sanity Check**: Vergleicht Row-Counts.

### Sync-Strategien

| Strategie       | Bedingung                      | Verhalten                          |
| :-------------- | :----------------------------- | :--------------------------------- |
| **Incremental** | ID + GESPEICHERT vorhanden     | Lädt nur Delta (schnellste Option) |
| **FullMerge**   | ID vorhanden, kein GESPEICHERT | Lädt alles, merged per ID          |
| **Snapshot**    | Keine ID                       | Truncate & vollständiger Insert    |

---

## Konfigurationsoptionen

### General Sektion

| Variable               | Standard | Beschreibung                                                                      |
| :--------------------- | :------- | :-------------------------------------------------------------------------------- |
| `GlobalTimeout`        | 7200     | Timeout in Sekunden für SQL-Befehle und BulkCopy                                  |
| `RecreateStagingTable` | `false`  | `true` = Staging bei jedem Lauf neu erstellen (Schema-Update)                     |
| `ForceFullSync`        | `false`  | `true` = **Truncate** der Zieltabelle + vollständiger Neuladung (Reparatur-Modus) |
| `RunSanityCheck`       | `true`   | `false` = Überspringt COUNT-Vergleich                                             |
| `MaxRetries`           | 3        | Wiederholungsversuche bei Fehler                                                  |

### MSSQL Prefix & Suffix (Neu)

Steuern die Namensgebung im Zielsystem. Die Staging-Tabelle heißt immer `STG_<OriginalName>`.

- **Prefix**: `DWH_` -> Zieltabelle wird `DWH_KUNDE`
- **Suffix**: `_V1` -> Zieltabelle wird `KUNDE_V1`
- Beide leer -> Zieltabelle heißt wie Quelltabelle.

---

## Credential Management

Die Credentials werden im Windows Credential Manager unter folgenden Namen gespeichert:

- `SQLSync_Firebird`
- `SQLSync_MSSQL`

Verwaltung per Kommandozeile: `cmdkey /list:SQLSync*`

---

## Logging

Alle Ausgaben werden automatisch in eine Log-Datei geschrieben:
`Logs\Sync_<ConfigName>_YYYY-MM-DD_HHmm.log`

---

## Wichtige Hinweise

### Löschungen werden nicht synchronisiert

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten.
**Lösung:** Nutze `ForceFullSync: true` in einem regelmäßigen Wartungs-Task (z.B. am Wochenende).

### Task Scheduler Integration

```text
Programm: pwsh.exe
Argumente: -ExecutionPolicy Bypass -File "C:\Scripts\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "config.json"
Starten in: C:\Scripts
```

---

## Changelog

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` und `MSSQL.Suffix` in Config implementiert.
- **Fix:** Credential Manager C# Code optimiert (Compilation Error behoben).
- **SQL:** `sp_Merge_Generic` auf Version 2 aktualisiert (unterstützt getrennte Namen für Staging/Target).

### v2.4 (2025-11-26) - Config Parameter

- **Feature:** Parameter `-ConfigFile` für flexible Job-Steuerung.
- **Feature:** `ForceFullSync` Option für Wartungs-Jobs.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager Integration.

### v2.0 (2025-11-24) - Production Release

- Parallele Verarbeitung, Retry-Logik, Auto-Schema.
