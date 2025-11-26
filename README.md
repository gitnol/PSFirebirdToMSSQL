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
    - [Beispielausgabe](#beispielausgabe)
  - [Credential Management](#credential-management)
    - [Einrichtung](#einrichtung)
    - [Funktionsweise](#funktionsweise)
    - [Verwaltung](#verwaltung)
    - [Fallback-Verhalten](#fallback-verhalten)
  - [Logging](#logging)
  - [Retry-Logik](#retry-logik)
  - [Konfigurationsoptionen](#konfigurationsoptionen)
    - [Empfehlung](#empfehlung)
  - [Datentyp-Mapping](#datentyp-mapping)
  - [Fehlerbehebung](#fehlerbehebung)
    - [Keine Credentials gefunden](#keine-credentials-gefunden)
    - [Firebird-Treiber wird nicht gefunden](#firebird-treiber-wird-nicht-gefunden)
    - [Sanity Check zeigt Differenz](#sanity-check-zeigt-differenz)
    - [Task Scheduler: Credentials nicht gefunden](#task-scheduler-credentials-nicht-gefunden)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden nicht synchronisiert](#löschungen-werden-nicht-synchronisiert)
    - [Task Scheduler Integration](#task-scheduler-integration)
    - [Performance-Tipps](#performance-tipps)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.3 (2025-11-26) - Parameter \& Config Features](#v23-2025-11-26---parameter--config-features)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)
    - [v2.0 (2025-11-24) - Production Release](#v20-2025-11-24---production-release)
    - [v1.0 (2025-11-24) - Initial Release](#v10-2025-11-24---initial-release)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz mit Memory-Streaming)
- **Inkrementeller Sync**: Lädt nur geänderte Daten (Delta) basierend auf der `GESPEICHERT`-Spalte (High Watermark Pattern)
- **Multi-Config Support**: Skript akzeptiert per Parameter unterschiedliche Konfigurationsdateien (z.B. für Daily vs. Weekly Jobs).
- **Automatische Schema-Erstellung**: Erstellt Staging- und Zieltabellen automatisch mit intelligentem Datentyp-Mapping
- **Self-Healing**: Erkennt und repariert fehlende Primärschlüssel und Indizes automatisch
- **Parallelisierung**: Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`)
- **Drei Sync-Strategien**: Incremental, FullMerge oder Snapshot je nach Tabellenstruktur
- **Sichere Credentials**: Windows Credential Manager statt Klartext-Passwörter in Config-Dateien
- **Datei-Logging**: Vollständiges Transcript aller Ausgaben in `Logs\Sync_<ConfigName>_*.log`
- **Retry-Logik**: Automatische Wiederholung bei Verbindungsfehlern (konfigurierbar)
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau

---

## Dateistruktur

```text
SQLSync/
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract → Staging → Merge)
├── Setup_Credentials.ps1                 # Einmalig: Passwörter sicher speichern
├── Manage_Config_Tables.ps1              # GUI-Tool zur Tabellenverwaltung
├── Get_Firebird_Schema.ps1               # Hilfstool: Datentyp-Analyse
├── Example_Sync_Start.ps1                # Beispiel-Wrapper für verschiedene Jobs
├── sql_server_setup.sql                  # SQL Server Initialisierung
├── test_dotnet_firebird.ps1              # Verbindungstest
├── config.json                           # Zugangsdaten ohne Passwörter (git-ignoriert)
├── config.sample.json                    # Konfigurationsvorlage
├── .gitignore                            # Schützt config.json
└── Logs/                                 # Log-Dateien (automatisch erstellt)
    └── Sync_config_2025-11-24_1430.log
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

Führe `sql_server_setup.sql` auf deinem Microsoft SQL Server aus:

```sql
-- Erstellt:
-- - Datenbank "STAGING" (falls nicht vorhanden)
-- - Stored Procedure "sp_Merge_Generic" für den intelligenten Datenabgleich
```

Die Stored Procedure nutzt **Smart Update**: Nur Zeilen mit geändertem `GESPEICHERT`-Zeitstempel werden aktualisiert, was das Transaction Log massiv entlastet.

### Schritt 2: Konfiguration anlegen

Kopiere `config.sample.json` nach `config.json` und trage deine Verbindungsdaten ein.

**Empfohlen (ohne Passwörter – diese kommen in den Credential Manager):**

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
    "Integrated Security": true
  },
  "Tables": []
}
```

**Hinweis zur Authentifizierung:**

- `Integrated Security: true` → Windows-Authentifizierung (empfohlen für SQL Server)
- `Integrated Security: false` → SQL-Authentifizierung (Credentials aus Credential Manager)

### Schritt 3: Credentials sicher speichern

Führe das Setup-Skript aus, um Passwörter verschlüsselt im Windows Credential Manager zu speichern:

```powershell
.\Setup_Credentials.ps1
```

Das Skript fragt interaktiv nach:

- Firebird Benutzername (z.B. `SYSDBA`)
- Firebird Passwort
- Optional: SQL Server Credentials (nur bei SQL-Authentifizierung)

**Vorteile gegenüber Klartext in config.json:**

| Aspekt      | config.json            | Credential Manager       |
| :---------- | :--------------------- | :----------------------- |
| Speicherung | Klartext               | AES-256 verschlüsselt    |
| Zugriff     | Jeder mit Dateizugriff | Nur der Windows-Benutzer |
| Git-Risiko  | Hoch                   | Keins                    |

### Schritt 4: Verbindung testen

```powershell
.\test_dotnet_firebird.ps1
```

Erwartete Ausgabe bei Erfolg:

```text
Treiber geladen (C:\...\FirebirdSql.Data.FirebirdClient.dll)
Verbindung zu svrerp01 erfolgreich hergestellt.
Test erfolgreich! Gelesene ID aus BSA: 12345
```

### Schritt 5: Tabellen auswählen

```powershell
.\Manage_Config_Tables.ps1
```

Das GUI zeigt alle verfügbaren Firebird-Tabellen mit Metadaten:

- **Hat ID**: Primärschlüssel vorhanden (ermöglicht Merge)
- **Hat Datum**: GESPEICHERT-Spalte vorhanden (ermöglicht Delta-Sync)
- **Status**: Bereits konfiguriert oder neu

**Toggle-Logik**: Ausgewählte Tabellen werden hinzugefügt oder entfernt. Nicht ausgewählte bleiben unverändert.

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
│  1. INITIALISIERUNG                                         │
│     Config laden, Credentials aus Credential Manager holen  │
├─────────────────────────────────────────────────────────────┤
│  2. ANALYSE (pro Tabelle, parallel)                         │
│     Prüft Quell-Schema auf ID und GESPEICHERT               │
│     → Wählt Strategie: Incremental / FullMerge / Snapshot   │
├─────────────────────────────────────────────────────────────┤
│  3. SCHEMA-CHECK                                            │
│     Erstellt STG_<Tabelle> falls nicht vorhanden            │
│     Automatisches Firebird → SQL Server Type-Mapping        │
├─────────────────────────────────────────────────────────────┤
│  4. EXTRACT                                                 │
│     Lädt Daten aus Firebird (Memory-Stream via IDataReader) │
│     Bei Incremental: Nur Daten > MAX(GESPEICHERT) im Ziel   │
├─────────────────────────────────────────────────────────────┤
│  5. LOAD                                                    │
│     Bulk Insert in Staging-Tabelle via SqlBulkCopy          │
├─────────────────────────────────────────────────────────────┤
│  6. MERGE                                                   │
│     sp_Merge_Generic: Staging → Zieltabelle                 │
│     Self-Healing: Erstellt fehlende Primary Keys            │
│     NEU: Bei ForceFullSync wird vorher TRUNCATE ausgeführt  │
├─────────────────────────────────────────────────────────────┤
│  7. SANITY CHECK                                            │
│     Vergleicht Row-Counts (Quelle vs. Ziel)                 │
├─────────────────────────────────────────────────────────────┤
│  ↻ RETRY bei Fehler (bis zu 3x mit 10s Pause)              │
└─────────────────────────────────────────────────────────────┘
```

### Sync-Strategien

| Strategie       | Bedingung                      | Verhalten                          |
| :-------------- | :----------------------------- | :--------------------------------- |
| **Incremental** | ID + GESPEICHERT vorhanden     | Lädt nur Delta (schnellste Option) |
| **FullMerge**   | ID vorhanden, kein GESPEICHERT | Lädt alles, merged per ID          |
| **Snapshot**    | Keine ID                       | Truncate & vollständiger Insert    |

### Beispielausgabe

```text
--------------------------------------------------------
SQLSync STARTED at 24.11.2025 14:30:00
Config File: C:\Scripts\config.json
--------------------------------------------------------
[Credentials] Firebird: Credential Manager
[Credentials] SQL Server: Windows Authentication
Konfiguration geladen. Tabellen: 3. Retries: 3
[BLIEF] Starte Verarbeitung...
[BKUNDE] Starte Verarbeitung...
[BSA] Starte Verarbeitung...
[BLIEF] Abschluss: Erfolg (OK)
[BKUNDE] Abschluss: Erfolg (OK)
[BSA] Abschluss: Erfolg (OK)
ZUSAMMENFASSUNG
Tabelle  Status  Sync   FB      SQL     Sanity  Time   Try  Info
-------  ------  ----   --      ---     ------  ----   ---  ----
BLIEF    Erfolg  2847   125430  125430  OK      00:12  1
BKUNDE   Erfolg  156    8924    8924    OK      00:02  1
BSA      Erfolg  0      45123   45123   OK      00:00  1

GESAMTLAUFZEIT: 00:00:15
LOGDATEI: C:\Scripts\Logs\Sync_config_2025-11-24_1430.log
```

---

## Credential Management

### Einrichtung

Das Setup-Skript speichert Passwörter sicher im Windows Credential Manager:

```powershell
.\Setup_Credentials.ps1
```

**Ablauf:**

1. Firebird Benutzername eingeben (z.B. `SYSDBA`)
2. Firebird Passwort eingeben (verdeckte Eingabe)
3. Optional: SQL Server Credentials (nur bei SQL-Auth)

### Funktionsweise

Die Credentials werden unter folgenden Namen gespeichert:

| Target             | Verwendung                    |
| :----------------- | :---------------------------- |
| `SQLSync_Firebird` | Firebird Datenbankzugriff     |
| `SQLSync_MSSQL`    | SQL Server (nur bei SQL-Auth) |

### Verwaltung

**Gespeicherte Credentials anzeigen:**

```powershell
cmdkey /list:SQLSync*
```

**Credential löschen:**

```powershell
cmdkey /delete:SQLSync_Firebird
cmdkey /delete:SQLSync_MSSQL
```

### Fallback-Verhalten

Falls keine Credentials im Credential Manager gefunden werden:

1. Das Skript prüft ob `Password` in `config.json` vorhanden ist
2. Falls ja: Verwendet dieses mit **Warnung**
3. Falls nein: Bricht mit Fehler ab

---

## Logging

Alle Ausgaben werden automatisch in eine Log-Datei geschrieben:

| Aspekt          | Details                                         |
| :-------------- | :---------------------------------------------- |
| **Speicherort** | `Logs\Sync_<ConfigName>_YYYY-MM-DD_HHmm.log`    |
| **Inhalt**      | Komplettes Transcript (Konsole + Fehler)        |
| **Rotation**    | Neue Datei pro Lauf                             |
| **Ordner**      | Wird automatisch erstellt falls nicht vorhanden |

---

## Retry-Logik

Bei Verbindungsfehlern (Netzwerk-Timeout, Server nicht erreichbar) versucht das Skript automatisch erneut:

| Parameter            | Standard | Beschreibung                   |
| :------------------- | :------- | :----------------------------- |
| `$MaxRetries`        | 3        | Maximale Anzahl Wiederholungen |
| `$RetryDelaySeconds` | 10       | Wartezeit zwischen Versuchen   |

---

## Konfigurationsoptionen

Die Steuerung erfolgt über die Sektion `"General"` in der `config.json`.

| Variable               | Standard | Beschreibung                                                                      |
| :--------------------- | :------- | :-------------------------------------------------------------------------------- |
| `GlobalTimeout`        | 7200     | Timeout in Sekunden für SQL-Befehle und BulkCopy                                  |
| `RecreateStagingTable` | `false`  | `true` = Staging bei jedem Lauf neu erstellen (Schema-Update)                     |
| `ForceFullSync`        | `false`  | `true` = **Truncate** der Zieltabelle + vollständiger Neuladung (Reparatur-Modus) |
| `RunSanityCheck`       | `true`   | `false` = Überspringt COUNT-Vergleich                                             |
| `MaxRetries`           | 3        | Wiederholungsversuche bei Fehler                                                  |
| `RetryDelaySeconds`    | 10       | Wartezeit zwischen Retries                                                        |

### Empfehlung

- **Täglich (Häufig):** Inkrementeller Sync. `ForceFullSync = false`, `RecreateStagingTable = false`.
- **Wöchentlich (Wartung):** Ein separater Job mit einer eigenen Config (z.B. `config_weekly.json`), wo `ForceFullSync = true` gesetzt ist. Dies reinigt gelöschte Datensätze aus dem Zielsystem ("Leichen").

---

## Datentyp-Mapping

| Firebird (.NET Type) | SQL Server     |
| :------------------- | :------------- |
| Int16                | SMALLINT       |
| Int32                | INT            |
| Int64                | BIGINT         |
| String (≤4000)       | NVARCHAR(n)    |
| String (>4000)       | NVARCHAR(MAX)  |
| DateTime             | DATETIME2      |
| TimeSpan             | TIME           |
| Decimal              | DECIMAL(18,4)  |
| Double               | FLOAT          |
| Single               | REAL           |
| Byte[]               | VARBINARY(MAX) |
| Boolean              | BIT            |
| (Sonstige)           | NVARCHAR(MAX)  |

---

## Fehlerbehebung

### Keine Credentials gefunden

```text
KRITISCH: Keine Firebird Credentials! Führe Setup_Credentials.ps1 aus.
```

**Lösung:** `.\Setup_Credentials.ps1` ausführen.

### Firebird-Treiber wird nicht gefunden

**Lösung**: Prüfe den `DllPath` in `config.json` oder lasse das Skript die DLL automatisch suchen (Fallback auf NuGet Packages Ordner).

### Sanity Check zeigt Differenz

- **WARNUNG (+n)**: SQL Server hat mehr Zeilen → Gelöschte Datensätze in Firebird (normal bei inkrementellem Sync).
- **FEHLER (-n)**: Firebird hat mehr Zeilen → Sync unvollständig.

### Task Scheduler: Credentials nicht gefunden

Die Credentials sind an den Windows-Benutzer gebunden. Der Task muss unter **demselben Benutzer** laufen, der `Setup_Credentials.ps1` ausgeführt hat.

---

## Wichtige Hinweise

### Löschungen werden nicht synchronisiert

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten.
**Lösung:** Nutze `ForceFullSync: true` in einem regelmäßigen Wartungs-Task.

### Task Scheduler Integration

Für automatische Ausführung als geplante Aufgabe:

```text
Programm: pwsh.exe
Argumente: -ExecutionPolicy Bypass -File "C:\Scripts\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "config.json"
Starten in: C:\Scripts
Ausführen als: [Benutzer der Setup_Credentials.ps1 ausgeführt hat]
```

### Performance-Tipps

- **ThrottleLimit anpassen**: Standard ist 4. Bei langsamer Quelle/Ziel auf 2 reduzieren, bei schnellem Netzwerk auf 6-8 erhöhen.
- **Sanity Check deaktivieren**: Spart COUNT(\*)-Abfragen bei sehr großen Tabellen.

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
│  Tabelle C       │         │                  │         │  STG_C (Staging) │
│                  │         │  🔐 Cred Manager │         │                  │
│                  │         │  ↻ Retry Loop    │         │                  │
│                  │         │  📄 Transcript   │         │                  │
└──────────────────┘         └────────┬─────────┘         ├──────────────────┤
                                      │                   │                  │
                                      │ EXEC              │  sp_Merge_Generic│
                                      └─────────────────► │         ↓        │
                                                          │  A (Final)       │
                                                          │  B (Final)       │
                                                          │  C (Final)       │
                                                          └──────────────────┘
```

---

## Changelog

### v2.3 (2025-11-26) - Parameter & Config Features

- **Feature:** Neuer Parameter `-ConfigFile` erlaubt die Angabe alternativer JSON-Dateien.
- **Feature:** `ForceFullSync` Option implementiert (erzwingt Truncate + Reload).
- **Update:** `General`-Sektion in JSON steuert nun alle Sync-Parameter.
- **Log:** Log-Dateiname enthält nun den Config-Namen.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager Integration.
- `Setup_Credentials.ps1` hinzugefügt.

### v2.0 (2025-11-24) - Production Release

- Datei-Logging und Retry-Logik.
- Parallelisierte Verarbeitung und Auto-Schema.
- Detailliertes Reporting.

### v1.0 (2025-11-24) - Initial Release

- Parallelisierte Verarbeitung
- Automatisches Schema-Mapping
- Self-Healing für Indizes
