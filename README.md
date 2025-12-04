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
    - [Schritt 1: Konfiguration anlegen](#schritt-1-konfiguration-anlegen)
    - [Schritt 2: SQL Server Umgebung (Automatisch)](#schritt-2-sql-server-umgebung-automatisch)
    - [Schritt 3: Credentials sicher speichern](#schritt-3-credentials-sicher-speichern)
    - [Schritt 4: Verbindung testen](#schritt-4-verbindung-testen)
    - [Schritt 5: Tabellen auswählen](#schritt-5-tabellen-auswählen)
    - [Schritt 6: Automatische Aufgabenplanung (Optional)](#schritt-6-automatische-aufgabenplanung-optional)
  - [Nutzung](#nutzung)
    - [Sync starten (Standard)](#sync-starten-standard)
    - [Sync starten (Spezifische Config)](#sync-starten-spezifische-config)
    - [Ablauf des Sync-Prozesses](#ablauf-des-sync-prozesses)
    - [Sync-Strategien](#sync-strategien)
  - [Konfigurationsoptionen](#konfigurationsoptionen)
    - [General Sektion](#general-sektion)
    - [MSSQL Prefix \& Suffix](#mssql-prefix--suffix)
  - [Credential Management](#credential-management)
  - [Logging](#logging)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden nicht synchronisiert](#löschungen-werden-nicht-synchronisiert)
    - [Task Scheduler Integration](#task-scheduler-integration)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.7 (2025-12-04) - Auto-Setup \& Robustness](#v27-2025-12-04---auto-setup--robustness)
    - [v2.6 (2025-12-03) - Task Automation](#v26-2025-12-03---task-automation)
    - [v2.5 (2025-11-29) - Prefix/Suffix \& Fixes](#v25-2025-11-29---prefixsuffix--fixes)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz mit Memory-Streaming).
- **Inkrementeller Sync**: Lädt nur geänderte Daten (Delta) basierend auf der `GESPEICHERT`-Spalte (High Watermark Pattern).
- **Auto-Environment Setup**: Das Skript prüft beim Start, ob die Ziel-Datenbank existiert. Falls nicht, verbindet es sich mit `master`, **erstellt die Datenbank** automatisch und setzt das Recovery Model auf `SIMPLE`.
- **Auto-Installation SP**: Installiert oder aktualisiert die benötigte Stored Procedure `sp_Merge_Generic` automatisch aus der `sql_server_setup.sql`.
- **Flexible Namensgebung**: Unterstützt **Prefixe** und **Suffixe** für Zieltabellen (z.B. Quelle `KUNDE` -> Ziel `DWH_KUNDE_V1`).
- **Multi-Config Support**: Parameter `-ConfigFile` erlaubt getrennte Jobs (z.B. Daily vs. Weekly).
- **Self-Healing**: Erkennt Schema-Änderungen, fehlende Primärschlüssel und Indizes und repariert diese.
- **Parallelisierung**: Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`).
- **Sichere Credentials**: Windows Credential Manager statt Klartext-Passwörter.
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau.

---

## Dateistruktur

```text
SQLSync/
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract -> Staging -> Merge)
├── Setup_Credentials.ps1                # Einmalig: Passwörter sicher speichern
├── Setup_ScheduledTasks.ps1             # Richtet autom. die Windows-Tasks ein
├── Manage_Config_Tables.ps1             # GUI-Tool zur Tabellenverwaltung
├── Get_Firebird_Schema.ps1              # Hilfstool: Datentyp-Analyse
├── sql_server_setup.sql                 # SQL-Template für DB & SP (wird vom Hauptskript genutzt)
├── Example_Sync_Start.ps1               # Beispiel-Wrapper
├── test_dotnet_firebird.ps1             # Verbindungstest
├── config.json                          # Zugangsdaten & Einstellungen (git-ignoriert)
├── config.sample.json                   # Konfigurationsvorlage
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

Hinweis für die Installation unter Windows Server Betriebssystemen: 
  - Sollte mit `Install-Package FirebirdSql.Data.FirebirdClient` (über NuGet) das Paket nicht installiert werden bzw. hängen bleiben, bitte unter Windows 11 installieren. 
  - Dann die installierten Pakete von `C:\Program Files\PackageManagement\NuGet\Packages` in das jeweilige Verzeichnis auf dem Server kopieren.

---

## Installation

### Schritt 1: Konfiguration anlegen

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
    "Integrated Security": true,
    "Username": "satest",
    "Password": "123456",
    "Database": "STAGING",
    "Prefix": "DWH_",
    "Suffix": ""
  },
  "Tables": ["EXAMPLETABLE1", "EXAMPLETABLE2"]
}
```

### Schritt 2: SQL Server Umgebung (Automatisch)

Das Hauptskript (`Sync_Firebird_MSSQL_AutoSchema.ps1`) verfügt nun über einen **Pre-Flight Check**.

1.  Stellen Sie sicher, dass die Datei `sql_server_setup.sql` im selben Ordner wie das Skript liegt.
2.  Wenn das Skript gestartet wird (siehe "Nutzung"), passiert Folgendes automatisch:
    - Verbindungsversuch zur Systemdatenbank `master`.
    - Prüfung, ob die in `config.json` definierte Datenbank (z.B. `STAGING`) existiert.
    - **Falls nein:** Datenbank wird erstellt (`CREATE DATABASE`) und auf `RECOVERY SIMPLE` gesetzt.
    - Prüfung, ob die Prozedur `sp_Merge_Generic` existiert.
    - **Falls nein:** Der Inhalt von `sql_server_setup.sql` wird eingelesen (Kommentare entfernt, Batches gesplittet) und ausgeführt.

_Manueller Fallback (nur nötig bei Fehlern):_
Führen Sie den Inhalt von `sql_server_setup.sql` manuell im SQL Management Studio aus.

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

### Schritt 6: Automatische Aufgabenplanung (Optional)

Nutzen Sie das bereitgestellte Skript, um die Synchronisation im Windows Task Scheduler einzurichten. Das Skript erstellt automatisch zwei Aufgaben (Daily Diff & Weekly Full) und fragt sicher nach dem Windows-Passwort.

```powershell
# Als Administrator ausführen!
.\Setup_ScheduledTasks.ps1
```

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
│  1. PRE-FLIGHT CHECK (Neu in v2.7)                          │
│     Verbindung zu 'master', Auto-Create DB, Auto-Install SP │
├─────────────────────────────────────────────────────────────┤
│  2. INITIALISIERUNG                                         │
│     Config laden, Credentials aus Credential Manager holen  │
├─────────────────────────────────────────────────────────────┤
│  3. ANALYSE (pro Tabelle, parallel)                         │
│     Prüft Quell-Schema auf ID und GESPEICHERT               │
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

| Strategie       | Bedingung                      | Verhalten                          |
| :-------------- | :----------------------------- | :--------------------------------- |
| **Incremental** | ID + GESPEICHERT vorhanden     | Lädt nur Delta (schnellste Option) |
| **FullMerge**   | ID vorhanden, kein GESPEICHERT | Lädt alles, merged per ID          |
| **Snapshot**    | Keine ID                       | Truncate & vollständiger Insert    |

---

## Konfigurationsoptionen

### General Sektion

| Variable                 | Standard | Beschreibung                                                   |
| :----------------------- | :------- | :------------------------------------------------------------- |
| `GlobalTimeout`          | 7200     | Timeout in Sekunden für SQL-Befehle und BulkCopy               |
| `RecreateStagingTable`   | `false`  | `true` = Staging bei jedem Lauf neu erstellen (Schema-Update)  |
| `ForceFullSync`          | `false`  | `true` = **Truncate** der Zieltabelle + vollständige Neuladung |
| `RunSanityCheck`         | `true`   | `false` = Überspringt COUNT-Vergleich                          |
| `MaxRetries`             | 3        | Wiederholungsversuche bei Fehler                               |
| `RetryDelaySeconds`      | 10       | Wartezeit zwischen Retries                                     |
| `DeleteLogOlderThanDays` | 30       | Löscht Logs automatisch nach X Tagen (0 = Deaktiviert)         |

### MSSQL Prefix & Suffix

Steuern die Namensgebung im Zielsystem. Die Staging-Tabelle heißt intern immer `STG_<OriginalName>`, das Zielsystem kann aber angepasst werden.

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

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten (Historie). Um dies zu bereinigen, nutzen Sie `ForceFullSync: true` in einem regelmäßigen Wartungs-Task (z.B. Sonntags), der die Zieltabellen leert und neu aufbaut.

### Task Scheduler Integration

Es wird empfohlen, das Skript `Setup_ScheduledTasks.ps1` zu verwenden.
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

### v2.7 (2025-12-04) - Auto-Setup & Robustness

- **Feature:** Integrierter Pre-Flight Check: Erstellt Datenbank und installiert `sp_Merge_Generic` automatisch (via `sql_server_setup.sql`), falls fehlend.
- **Fix:** Verbesserte Behandlung von SQL-Kommentaren beim Einlesen von SQL-Dateien.
- **Cleanup:** `Initialize_SQL_Environment.ps1` entfernt (Logik im Hauptskript integriert).

### v2.6 (2025-12-03) - Task Automation

- **Neu:** `Setup_ScheduledTasks.ps1` zur automatischen Einrichtung der Windows-Aufgabenplanung.

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` und `MSSQL.Suffix` implementiert.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager Integration.
