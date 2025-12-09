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
    - [Orphan-Cleanup (Löschungserkennung)](#orphan-cleanup-löschungserkennung)
    - [MSSQL Prefix \& Suffix](#mssql-prefix--suffix)
    - [JSON-Schema-Validierung (NEU)](#json-schema-validierung-neu)
  - [Modul-Architektur](#modul-architektur)
  - [Verwendung in eigenen Skripten](#verwendung-in-eigenen-skripten)
  - [Credential Management](#credential-management)
  - [Logging](#logging)
  - [Wichtige Hinweise](#wichtige-hinweise)
    - [Löschungen werden im Standard nicht synchronisiert. (CleanupOrphans Option)](#löschungen-werden-im-standard-nicht-synchronisiert-cleanuporphans-option)
    - [Task Scheduler Integration (Pfadanpassung)](#task-scheduler-integration-pfadanpassung)
  - [Architektur](#architektur)
  - [Changelog](#changelog)
    - [v2.9 (2025-12-06) - Orphan-Cleanup (Soft Deletes)](#v29-2025-12-06---orphan-cleanup-soft-deletes)
    - [v2.8 (2025-12-06) - Modul-Architektur \& Bugfixes](#v28-2025-12-06---modul-architektur--bugfixes)
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
- **NEU: Modul-Architektur**: Wiederverwendbare Funktionen in `SQLSyncCommon.psm1`.
- **NEU: JSON-Schema-Validierung**: Optionale Validierung der Konfigurationsdatei.
- **NEU: Sicheres Connection Handling**: Kein Resource Leak durch garantiertes Cleanup (try/finally).

---

## Dateistruktur

```text
SQLSync/
├── SQLSyncCommon.psm1                   # KERN-MODUL: Gemeinsame Funktionen (MUSS vorhanden sein!)
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Hauptskript (Extract -> Staging -> Merge)
├── Setup_Credentials.ps1                # Einmalig: Passwörter sicher speichern
├── Setup_ScheduledTasks.ps1             # Vorlage für Windows-Tasks (Pfade anpassen!)
├── Manage_Config_Tables.ps1             # GUI-Tool zur Tabellenverwaltung
├── Get_Firebird_Schema.ps1              # Hilfstool: Datentyp-Analyse
├── sql_server_setup.sql                 # SQL-Template für DB & SP (wird vom Hauptskript genutzt)
├── Example_Sync_Start.ps1               # Beispiel-Wrapper
├── Test-SQLSyncConnections.ps1          # Verbindungstest
├── config.json                          # Zugangsdaten & Einstellungen (git-ignoriert)
├── config.sample.json                   # Konfigurationsvorlage
├── config.schema.json                   # JSON-Schema für Validierung (optional)
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


---

## Installation

### Schritt 1: Dateien kopieren

Alle `.ps1`, `.sql`, `.json` und vor allem die `.psm1` Dateien in ein gemeinsames Verzeichnis kopieren (z.B. `E:\SQLSync_Firebird_to_MSSQL\`).

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
    "RunSanityCheck": true,
    "MaxRetries": 3,
    "RetryDelaySeconds": 10,
    "DeleteLogOlderThanDays": 30,
    "CleanupOrphans": false,
    "OrphanCleanupBatchSize": 50000
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
    "Suffix": "",
    "Port": 1433
  },
  "Tables": ["EXAMPLETABLE1", "EXAMPLETABLE2"]
}
```

_Hinweis zum MSSQL Port:_ Das Skript verwendet primär den `Server`-Parameter. Sollte ein nicht-standard Port (ungleich 1433) benötigt werden, geben Sie diesen bitte im Format `Servername,Port` im Feld `Server` an (z.B. `"SVRSQL03,1433"`).

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

### Schritt 5: Verbindung testen

```powershell
.\Test-SQLSyncConnections.ps1
```

### Schritt 6: Tabellen auswählen

Starten Sie den GUI-Manager, um Tabellen auszuwählen:

```powershell
.\Manage_Config_Tables.ps1
```

Der Manager bietet eine **Toggle-Logik**:

- Markierte Tabellen, die _nicht_ in der Config sind -> Werden **hinzugefügt**.
- Markierte Tabellen, die _schon_ in der Config sind -> Werden **entfernt**.

### Schritt 7: Automatische Aufgabenplanung (Optional)

Nutzen Sie das bereitgestellte Skript, um die Synchronisation im Windows Task Scheduler einzurichten. Das Skript erstellt Aufgaben für Daily Diff & Weekly Full.

**ACHTUNG:** Das Skript `Setup_ScheduledTasks.ps1` dient als Vorlage und enthält Beispielpfade (z.B. `E:\SQLSync_...`).

1.  Öffnen Sie `Setup_ScheduledTasks.ps1` in einem Editor.
2.  Passen Sie die Variablen `$ScriptPath`, `$WorkDir` und die Config-Namen an Ihre Umgebung an.
3.  Führen Sie es erst dann als Administrator aus.

<!-- end list -->

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
│  2. INITIALISIERUNG (Modul laden)                           │
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

| Strategie       | Bedingung                           | Verhalten                          |
| :-------------- | :---------------------------------- | :--------------------------------- |
| **Incremental** | ID + Timestamp-Spalte vorhanden     | Lädt nur Delta (schnellste Option) |
| **FullMerge**   | ID vorhanden, keine Timestamp-Spalte| Lädt alles, merged per ID          |
| **Snapshot**    | Keine ID                            | Truncate & vollständiger Insert    |

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
| `CleanupOrphans`         | `false`  | Verwaiste Datensätze im Ziel löschen                           |
| `OrphanCleanupBatchSize` | 50000    | Batch-Größe für ID-Transfer beim Cleanup                       |
| `IdColumn`               | `"ID"`   | Standard-Name der ID-Spalte für alle Tabellen                  |
| `TimestampColumns`       | `["GESPEICHERT"]` | Liste möglicher Timestamp-Spalten (erste gefundene wird verwendet) |

### Column Configuration (NEU in v2.10)

Das Skript unterstützt jetzt flexible Spalten-Konfiguration für unterschiedliche Tabellenstrukturen.

**Globale Defaults:**

```json
{
  "General": {
    "IdColumn": "ID",
    "TimestampColumns": ["GESPEICHERT", "MODIFIED_DATE", "LAST_UPDATE", "CHANGED_AT"]
  }
}
```

**Tabellenspezifische Overrides:**

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

**Logik:**

1. Prüfe ob `TableOverrides[Tabelle]` existiert → Override-Werte verwenden
2. `IdColumn`: Override → Global → "ID" (Default)
3. `TimestampColumn`: Override → Erste gefundene aus `TimestampColumns` → `null`
4. Strategie: HasId + HasTimestamp → Incremental | HasId → FullMerge | sonst → Snapshot

### Orphan-Cleanup (Löschungserkennung)

Wenn `CleanupOrphans: true` gesetzt ist, werden nach dem Sync alle Datensätze im Ziel gelöscht, die in der Quelle nicht mehr existieren.

**Ablauf:**

1.  Alle IDs aus Firebird in eine Temp-Tabelle laden (in Batches für Speichereffizienz)
2.  `DELETE FROM Ziel WHERE ID NOT IN (SELECT ID FROM #TempIDs)`
3.  Temp-Tabelle aufräumen

**Einschränkungen:**

- Funktioniert nur bei Tabellen mit `ID`-Spalte (nicht bei Snapshot-Strategie)
- Erhöht die Laufzeit, da alle IDs übertragen werden müssen
- Nicht nötig bei `ForceFullSync` (Tabelle wird eh komplett neu geladen)

**Empfehlung:**

- `CleanupOrphans: false` für tägliche Diff-Syncs (Performance)
- `CleanupOrphans: true` für wöchentliche Full-Syncs (Datenbereinigung)

### MSSQL Prefix & Suffix

Steuern die Namensgebung im Zielsystem.

- **Prefix**: `DWH_` -> Zieltabelle wird `DWH_KUNDE`
- **Suffix**: `_V1` -> Zieltabelle wird `KUNDE_V1`

### JSON-Schema-Validierung (NEU)

Die Datei `config.schema.json` kann zur Validierung verwendet werden, um Tippfehler in der Config zu vermeiden:

```powershell
$json = Get-Content "config.json" -Raw
Test-Json -Json $json -SchemaFile "config.schema.json"
```

---

## Modul-Architektur

Ab Version 2.8 verwendet SQLSync ein gemeinsames PowerShell-Modul (`SQLSyncCommon.psm1`) für wiederverwendbare Funktionen. Dieses Modul muss immer im Skriptverzeichnis liegen.

Das Modul stellt zentral folgende Funktionen bereit:

- **Credential Management:** `Get-StoredCredential`, `Resolve-FirebirdCredentials`
- **Configuration:** `Get-SQLSyncConfig` (inkl. Schema-Validierung)
- **Driver Loading:** `Initialize-FirebirdDriver`
- **Type Mapping:** `ConvertTo-SqlServerType` (.NET zu SQL Datentypen)

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

---

## Wichtige Hinweise

### Löschungen werden im Standard nicht synchronisiert. (CleanupOrphans Option)

Der inkrementelle Sync erkennt nur neue/geänderte Datensätze. Gelöschte Datensätze in Firebird bleiben im SQL Server erhalten (Historie). Um dies zu bereinigen, nutzen Sie `ForceFullSync: true` in einem regelmäßigen Wartungs-Task (z.B. Sonntags), der die Zieltabellen leert und neu aufbaut. Aktualisiert auch das Schema.
Alternativ kann `CleanupOrphans: true` genutzt werden, um IDs abzugleichen.

### Task Scheduler Integration (Pfadanpassung)

Es wird empfohlen, das Skript `Setup_ScheduledTasks.ps1` als Vorlage zu verwenden. **Wichtig:** Da das Skript Umgebungsvariablen wie `$WorkDir` und `$ScriptPath` mit Beispielwerten belegt, **muss es vor der Ausführung bearbeitet werden**, um auf Ihre tatsächliche Installation zu zeigen.

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

### v2.10 (2025-12-09) - Dynamic Column Configuration

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

- **Neu:** `Setup_ScheduledTasks.ps1` zur automatischen Einrichtung der Windows-Aufgabenplanung.

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` und `MSSQL.Suffix` implementiert.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager Integration.
