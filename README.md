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
    - [Schritt 3: Verbindung testen](#schritt-3-verbindung-testen)
    - [Schritt 4: Tabellen auswählen](#schritt-4-tabellen-auswählen)
  - [Nutzung](#nutzung)
    - [Sync starten](#sync-starten)
    - [Ablauf des Sync-Prozesses](#ablauf-des-sync-prozesses)
    - [Sync-Strategien](#sync-strategien)
    - [Beispielausgabe](#beispielausgabe)
  - [Logging](#logging)
  - [Retry-Logik](#retry-logik)
  - [Konfigurationsoptionen](#konfigurationsoptionen)
    - [Empfehlung:](#empfehlung)
  - [Datentyp-Mapping](#datentyp-mapping)
  - [Fehlerbehebung](#fehlerbehebung)
    - [Firebird-Treiber wird nicht gefunden](#firebird-treiber-wird-nicht-gefunden)
    - [Timeout bei großen Tabellen](#timeout-bei-großen-tabellen)
    - [Sanity Check zeigt Differenz](#sanity-check-zeigt-differenz)
    - [PowerShell 7 nicht installiert](#powershell-7-nicht-installiert)
    - [Alle Retries fehlgeschlagen](#alle-retries-fehlgeschlagen)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden nicht synchronisiert](#löschungen-werden-nicht-synchronisiert)
    - [Task Scheduler Integration](#task-scheduler-integration)
    - [Performance-Tipps](#performance-tipps)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.0 (2025-11-24) - Production Release](#v20-2025-11-24---production-release)
    - [v1.0 (2025-11-24) - Initial Release](#v10-2025-11-24---initial-release)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz mit Memory-Streaming)
- **Inkrementeller Sync**: Lädt nur geänderte Daten (Delta) basierend auf der `GESPEICHERT`-Spalte (High Watermark Pattern)
- **Automatische Schema-Erstellung**: Erstellt Staging- und Zieltabellen automatisch mit intelligentem Datentyp-Mapping
- **Self-Healing**: Erkennt und repariert fehlende Primärschlüssel und Indizes automatisch
- **Parallelisierung**: Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`)
- **Drei Sync-Strategien**: Incremental, FullMerge oder Snapshot je nach Tabellenstruktur
- **Datei-Logging**: Vollständiges Transcript aller Ausgaben in `Logs\Sync_*.log`
- **Retry-Logik**: Automatische Wiederholung bei Verbindungsfehlern (konfigurierbar)
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau

---

## Dateistruktur

```
SQLSync/
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract → Staging → Merge)
├── Manage_Config_Tables.ps1              # GUI-Tool zur Tabellenverwaltung
├── sql_server_setup.sql                  # SQL Server Initialisierung
├── test_dotnet_firebird.ps1              # Verbindungstest
├── config.json                           # Zugangsdaten (git-ignoriert)
├── config.sample.json                    # Konfigurationsvorlage
├── .gitignore                            # Schützt config.json und ignoriert den Log Ordner und grundsätzliche alle *.log Dateien
└── Logs/                                 # Log-Dateien (automatisch erstellt)
    └── Sync_2025-11-24_1430.log
```

---

## Voraussetzungen

| Komponente | Anforderung |
|:-----------|:------------|
| PowerShell | Version 7.0 oder höher (zwingend für `-Parallel`) |
| Firebird .NET Provider | Wird automatisch via NuGet installiert |
| Firebird-Zugriff | Leserechte auf der Quelldatenbank |
| MSSQL-Zugriff | `db_owner` oder `ddl_admin` auf der Zieldatenbank |

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

Kopiere `config.sample.json` nach `config.json` und trage deine Verbindungsdaten ein:

```json
{
  "Firebird": {
    "Server": "svrerp01",
    "Password": "dein_passwort",
    "Database": "D:\\DB\\LA01_ECHT.FDB",
    "Port": 3050,
    "Charset": "UTF8",
    "DllPath": "C:\\Pfad\\Zur\\FirebirdSql.Data.FirebirdClient.dll"
  },
  "MSSQL": {
    "Server": "SVRSQL03",
    "Integrated Security": true,
    "Database": "STAGING"
  },
  "Tables": []
}
```

**Hinweis zur Authentifizierung:**  
- `Integrated Security: true` → Windows-Authentifizierung (empfohlen)  
- `Integrated Security: false` → SQL-Authentifizierung mit `Username` und `Password`

### Schritt 3: Verbindung testen

```powershell
.\test_dotnet_firebird.ps1
```

Erwartete Ausgabe bei Erfolg:
```
Treiber geladen (C:\...\FirebirdSql.Data.FirebirdClient.dll)
Verbindung zu svrerp01 erfolgreich hergestellt.
Test erfolgreich! Gelesene ID aus BSA: 12345
```

### Schritt 4: Tabellen auswählen

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

### Sync starten

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1
```

### Ablauf des Sync-Prozesses

```
┌─────────────────────────────────────────────────────────────┐
│  1. INITIALISIERUNG                                         │
│     Config laden, Treiber prüfen, Logging starten           │
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
├─────────────────────────────────────────────────────────────┤
│  7. SANITY CHECK                                            │
│     Vergleicht Row-Counts (Quelle vs. Ziel)                 │
├─────────────────────────────────────────────────────────────┤
│  ↻ RETRY bei Fehler (bis zu 3x mit 10s Pause)               │
└─────────────────────────────────────────────────────────────┘
```

### Sync-Strategien

| Strategie | Bedingung | Verhalten |
|:----------|:----------|:----------|
| **Incremental** | ID + GESPEICHERT vorhanden | Lädt nur Delta (schnellste Option) |
| **FullMerge** | ID vorhanden, kein GESPEICHERT | Lädt alles, merged per ID |
| **Snapshot** | Keine ID | Truncate & vollständiger Insert |

### Beispielausgabe

```
--------------------------------------------------------
SQLSync STARTED at 24.11.2025 14:30:00
--------------------------------------------------------
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
LOGDATEI: C:\Scripts\Logs\Sync_2025-11-24_1430.log
```

---

## Logging

Alle Ausgaben werden automatisch in eine Log-Datei geschrieben:

| Aspekt | Details |
|:-------|:--------|
| **Speicherort** | `Logs\Sync_YYYY-MM-DD_HHmm.log` |
| **Inhalt** | Komplettes Transcript (Konsole + Fehler) |
| **Rotation** | Neue Datei pro Lauf (Datum/Uhrzeit im Namen) |
| **Ordner** | Wird automatisch erstellt falls nicht vorhanden |

**Beispiel-Log:**

```
**********************
Windows PowerShell transcript start
Start time: 20251124143000
**********************
Transcript started, output file is C:\Scripts\Logs\Sync_2025-11-24_1430.log
--------------------------------------------------------
SQLSync STARTED at 24.11.2025 14:30:00
--------------------------------------------------------
Konfiguration geladen. Tabellen: 3. Retries: 3
[BLIEF] Starte Verarbeitung...
...
```

**Tipp für Task Scheduler:** Das Logging funktioniert auch bei unbeaufsichtigter Ausführung. Fehler vom Vortag lassen sich so leicht nachvollziehen.

---

## Retry-Logik

Bei Verbindungsfehlern (Netzwerk-Timeout, Server nicht erreichbar) versucht das Skript automatisch erneut:

| Parameter | Standard | Beschreibung |
|:----------|:---------|:-------------|
| `$MaxRetries` | 3 | Maximale Anzahl Wiederholungen |
| `$RetryDelaySeconds` | 10 | Wartezeit zwischen Versuchen |

**Ablauf bei Fehler:**

```
[BLIEF] Starte Verarbeitung...
[BLIEF] ERROR (Versuch 1): Connection timeout expired
[BLIEF] Warnung: Versuch 2 von 4... (Warte 10s)
[BLIEF] ERROR (Versuch 2): Connection timeout expired
[BLIEF] Warnung: Versuch 3 von 4... (Warte 10s)
[BLIEF] Abschluss: Erfolg (OK)   ← Beim 3. Versuch erfolgreich
```

**Bei dauerhaftem Fehler:**

Nach Ausschöpfung aller Versuche wird der Status auf "Fehler" gesetzt und die nächste Tabelle verarbeitet. Die Spalte "Try" in der Zusammenfassung zeigt die Anzahl der benötigten Versuche.

---

## Konfigurationsoptionen

Im Hauptskript können folgende Parameter angepasst werden:

| Variable | Standard | Beschreibung |
|:---------|:---------|:-------------|
| `$GlobalTimeout` | 7200 | Timeout in Sekunden für SQL-Befehle und BulkCopy |
| `$RecreateStagingTable` | `$false` | `$true` = Staging bei jedem Lauf neu erstellen |
| `$RunSanityCheck` | `$true` | `$false` = Überspringt COUNT-Vergleich |
| `$MaxRetries` | 3 | Wiederholungsversuche bei Fehler |
| `$RetryDelaySeconds` | 10 | Wartezeit zwischen Retries |
| `-ThrottleLimit` | 4 | Anzahl paralleler Threads (Zeile 372) |

### Empfehlung:
- Täglich: Inkrementeller Sync (schnell, Updates/Inserts). `$RecreateStagingTable=$false`
- Wöchentlich (Wochenende): Ein Job, der die Tabellen leert (TRUNCATE) und einmal voll lädt (Snapshot oder `$RecreateStagingTable=$true` mit Datum-Reset). 

---

## Datentyp-Mapping

| Firebird (.NET Type) | SQL Server |
|:---------------------|:-----------|
| Int16 | SMALLINT |
| Int32 | INT |
| Int64 | BIGINT |
| String (≤4000) | NVARCHAR(n) |
| String (>4000) | NVARCHAR(MAX) |
| DateTime | DATETIME2 |
| TimeSpan | TIME |
| Decimal | DECIMAL(18,4) |
| Double | FLOAT |
| Single | REAL |
| Byte[] | VARBINARY(MAX) |
| Boolean | BIT |
| (Sonstige) | NVARCHAR(MAX) |

---

## Fehlerbehebung

### Firebird-Treiber wird nicht gefunden

```
KRITISCH: Firebird Treiber DLL nicht gefunden.
```

**Lösung**: Prüfe den `DllPath` in `config.json` oder lasse das Skript die DLL automatisch suchen:
```powershell
Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" `
  -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse
```

### Timeout bei großen Tabellen

**Lösung**: Erhöhe `$GlobalTimeout` im Hauptskript (Standard: 7200 Sekunden = 2 Stunden)

### Sanity Check zeigt Differenz

- **WARNUNG (+n)**: SQL Server hat mehr Zeilen → Wahrscheinlich gelöschte Datensätze in Firebird
- **FEHLER (-n)**: Firebird hat mehr Zeilen → Sync unvollständig, prüfe Log-Datei

### PowerShell 7 nicht installiert

```powershell
# Installation über winget
winget install Microsoft.PowerShell

# Oder Download von:
# https://github.com/PowerShell/PowerShell/releases
```

### Alle Retries fehlgeschlagen

Prüfe die Log-Datei auf die genaue Fehlermeldung. Häufige Ursachen:

- Firebird-Server nicht erreichbar
- SQL Server Authentifizierungsproblem
- Netzwerk-Firewall blockiert Verbindung
- Datenbank exklusiv gesperrt (Backup läuft?)

---

## Wichtige Hinweise

### Löschungen werden nicht synchronisiert

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten. Für eine vollständige Bereinigung:

1. Zieltabelle truncaten
2. Sync mit `$RecreateStagingTable = $true` ausführen

### Task Scheduler Integration

Für automatische Ausführung als geplante Aufgabe:

```
Programm: pwsh.exe
Argumente: -ExecutionPolicy Bypass -File "C:\Scripts\Sync_Firebird_MSSQL_AutoSchema.ps1"
Starten in: C:\Scripts
```

Die Log-Dateien ermöglichen die Fehleranalyse auch ohne Konsolenfenster.

### Performance-Tipps

- **ThrottleLimit anpassen**: Bei langsamer Quelle/Ziel auf 2 reduzieren, bei schnellem Netzwerk auf 6-8 erhöhen
- **Sanity Check deaktivieren**: `$RunSanityCheck = $false` spart COUNT(*)-Abfragen
- **Staging-Recreate vermeiden**: `$RecreateStagingTable = $false` nutzt schnelleres TRUNCATE

---

## Architektur

```
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│    Firebird      │         │   PowerShell 7   │         │   SQL Server     │
│   (Quelle)       │         │   ETL Engine     │         │   (Ziel)         │
├──────────────────┤         ├──────────────────┤         ├──────────────────┤
│                  │  Read   │                  │  Write  │                  │
│  Tabelle A       │ ──────► │  Parallel Jobs   │ ──────► │  STG_A (Staging) │
│  Tabelle B       │         │  (ThrottleLimit) │         │  STG_B (Staging) │
│  Tabelle C       │         │                  │         │  STG_C (Staging) │
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

### v2.0 (2025-11-24) - Production Release

**Neu:**
- Datei-Logging mit `Start-Transcript` in `Logs\Sync_*.log`
- Retry-Logik bei Verbindungsfehlern (konfigurierbar: `$MaxRetries`, `$RetryDelaySeconds`)
- Saubere Verbindungsschließung vor Retry-Versuchen
- Neue Spalte "Try" in der Zusammenfassung zeigt Anzahl der Versuche
- Automatische Erstellung des Log-Ordners
- Verbesserte Fehlerbehandlung mit JSON-Validierung

**Verbessert:**
- Übersichtlichere Konsolenausgabe
- Robustere Treiber-Suche mit Fallback

### v1.0 (2025-11-24) - Initial Release

- Parallelisierte Verarbeitung
- Automatisches Schema-Mapping
- Self-Healing für Indizes
- GUI Config Manager
- Drei Sync-Strategien (Incremental, FullMerge, Snapshot)
