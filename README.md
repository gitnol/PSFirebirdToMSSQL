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
    - [Sync starten](#sync-starten)
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
    - [Empfehlung:](#empfehlung)
  - [Datentyp-Mapping](#datentyp-mapping)
  - [Fehlerbehebung](#fehlerbehebung)
    - [Keine Credentials gefunden](#keine-credentials-gefunden)
    - [Firebird-Treiber wird nicht gefunden](#firebird-treiber-wird-nicht-gefunden)
    - [Timeout bei großen Tabellen](#timeout-bei-großen-tabellen)
    - [Sanity Check zeigt Differenz](#sanity-check-zeigt-differenz)
    - [PowerShell 7 nicht installiert](#powershell-7-nicht-installiert)
    - [Alle Retries fehlgeschlagen](#alle-retries-fehlgeschlagen)
    - [Task Scheduler: Credentials nicht gefunden](#task-scheduler-credentials-nicht-gefunden)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden nicht synchronisiert](#löschungen-werden-nicht-synchronisiert)
    - [Task Scheduler Integration](#task-scheduler-integration)
    - [Performance-Tipps](#performance-tipps)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)
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
- **Sichere Credentials**: Windows Credential Manager statt Klartext-Passwörter in Config-Dateien
- **Datei-Logging**: Vollständiges Transcript aller Ausgaben in `Logs\Sync_*.log`
- **Retry-Logik**: Automatische Wiederholung bei Verbindungsfehlern (konfigurierbar)
- **GUI Config Manager**: Komfortables Tool zur Tabellenauswahl mit Metadaten-Vorschau

---

## Dateistruktur

```
SQLSync/
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract → Staging → Merge)
├── Setup_Credentials.ps1                 # Einmalig: Passwörter sicher speichern
├── Manage_Config_Tables.ps1              # GUI-Tool zur Tabellenverwaltung
├── sql_server_setup.sql                  # SQL Server Initialisierung
├── test_dotnet_firebird.ps1              # Verbindungstest
├── config.json                           # Zugangsdaten ohne Passwörter (git-ignoriert)
├── config.sample.json                    # Konfigurationsvorlage
├── .gitignore                            # Schützt config.json
└── Logs/                                 # Log-Dateien (automatisch erstellt)
    └── Sync_2025-11-24_1430.log
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
  "Firebird": {
    "Server": "svrerp01",
    "Database": "D:\\DB\\LA01_ECHT.FDB",
    "Port": 3050,
    "Charset": "UTF8",
    "DllPath": "C:\\Program Files\\PackageManagement\\NuGet\\Packages\\FirebirdSql.Data.FirebirdClient.10.3.1\\lib\\net6.0\\FirebirdSql.Data.FirebirdClient.dll"
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

```
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

### Sync starten

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1
```

### Ablauf des Sync-Prozesses

```
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

```
--------------------------------------------------------
SQLSync STARTED at 24.11.2025 14:30:00
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
LOGDATEI: C:\Scripts\Logs\Sync_2025-11-24_1430.log
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

Das Hauptskript lädt die Credentials automatisch beim Start:

```
[Credentials] Firebird: Credential Manager        ← Sicher
[Credentials] SQL Server: Windows Authentication  ← Empfohlen
```

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

**Über Windows GUI:**
Systemsteuerung → Benutzerkonten → Anmeldeinformationsverwaltung → Windows-Anmeldeinformationen

### Fallback-Verhalten

Falls keine Credentials im Credential Manager gefunden werden:

1. Das Skript prüft ob `Password` in `config.json` vorhanden ist
2. Falls ja: Verwendet dieses mit **Warnung**
3. Falls nein: Bricht mit Fehler ab

```
[Credentials] Firebird: config.json (WARNUNG: unsicher!)
```

**Empfehlung:** Nach dem Setup die Passwörter aus `config.json` entfernen.

---

## Logging

Alle Ausgaben werden automatisch in eine Log-Datei geschrieben:

| Aspekt          | Details                                         |
| :-------------- | :---------------------------------------------- |
| **Speicherort** | `Logs\Sync_YYYY-MM-DD_HHmm.log`                 |
| **Inhalt**      | Komplettes Transcript (Konsole + Fehler)        |
| **Rotation**    | Neue Datei pro Lauf (Datum/Uhrzeit im Namen)    |
| **Ordner**      | Wird automatisch erstellt falls nicht vorhanden |

**Tipp für Task Scheduler:** Das Logging funktioniert auch bei unbeaufsichtigter Ausführung. Fehler vom Vortag lassen sich so leicht nachvollziehen.

---

## Retry-Logik

Bei Verbindungsfehlern (Netzwerk-Timeout, Server nicht erreichbar) versucht das Skript automatisch erneut:

| Parameter            | Standard | Beschreibung                   |
| :------------------- | :------- | :----------------------------- |
| `$MaxRetries`        | 3        | Maximale Anzahl Wiederholungen |
| `$RetryDelaySeconds` | 10       | Wartezeit zwischen Versuchen   |

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

| Variable                | Standard | Beschreibung                                     |
| :---------------------- | :------- | :----------------------------------------------- |
| `$GlobalTimeout`        | 7200     | Timeout in Sekunden für SQL-Befehle und BulkCopy |
| `$RecreateStagingTable` | `$false` | `$true` = Staging bei jedem Lauf neu erstellen   |
| `$RunSanityCheck`       | `$true`  | `$false` = Überspringt COUNT-Vergleich           |
| `$MaxRetries`           | 3        | Wiederholungsversuche bei Fehler                 |
| `$RetryDelaySeconds`    | 10       | Wartezeit zwischen Retries                       |
| `-ThrottleLimit`        | 4        | Anzahl paralleler Threads                        |

### Empfehlung:
- Täglich: Inkrementeller Sync (schnell, Updates/Inserts). `$RecreateStagingTable=$false`
- Wöchentlich (Wochenende): Ein Job, der die Tabellen leert (TRUNCATE) und einmal voll lädt (Snapshot oder `$RecreateStagingTable=$true` mit Datum-Reset). 

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

```
KRITISCH: Keine Firebird Credentials! Führe Setup_Credentials.ps1 aus.
```

**Lösung:** `.\Setup_Credentials.ps1` ausführen und Passwörter eingeben.

### Firebird-Treiber wird nicht gefunden

```
KRITISCH: Firebird Treiber DLL nicht gefunden.
```

**Lösung**: Prüfe den `DllPath` in `config.json` oder lasse das Skript die DLL automatisch suchen.

**Lösung**: Prüfe den `DllPath` in `config.json` oder lasse das Skript die DLL automatisch suchen:
```powershell
Get-ChildItem -Path "C:\Program Files\PackageManagement\NuGet\Packages" `
  -Filter "FirebirdSql.Data.FirebirdClient.dll" -Recurse
```

### Timeout bei großen Tabellen

**Lösung**: Erhöhe `$GlobalTimeout` im Hauptskript (Standard: 7200 Sekunden = 2 Stunden)

### Sanity Check zeigt Differenz

- **WARNUNG (+n)**: SQL Server hat mehr Zeilen → Gelöschte Datensätze in Firebird
- **FEHLER (-n)**: Firebird hat mehr Zeilen → Sync unvollständig

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

### Task Scheduler: Credentials nicht gefunden

Die Credentials sind an den Windows-Benutzer gebunden. Der Task muss unter **demselben Benutzer** laufen, der `Setup_Credentials.ps1` ausgeführt hat.

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
Ausführen als: [Benutzer der Setup_Credentials.ps1 ausgeführt hat]
```

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

### v2.1 (2025-11-25) - Secure Credentials

**Neu:**

- Windows Credential Manager Integration (kein Klartext mehr in config.json)
- `Setup_Credentials.ps1` für sichere Passwort-Speicherung
- Fallback auf config.json mit Warnung für Übergangszeit
- Credential-Status wird beim Start angezeigt

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