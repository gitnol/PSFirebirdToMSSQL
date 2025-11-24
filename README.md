# SQLSync: Firebird to MSSQL High-Performance Synchronizer

Dieses Projekt stellt eine hochperformante, parallelisierte ETL-Lösung bereit, um Daten inkrementell aus einer Firebird-Datenbank (z.B. AvERP) in einen Microsoft SQL Server zu synchronisieren.

Es ersetzt veraltete Linked-Server-Lösungen durch einen modernen PowerShell-Ansatz, der `SqlBulkCopy` und intelligentes Schema-Mapping nutzt.

## 🚀 Features

* **High-Speed Transfer:** Nutzt .NET `SqlBulkCopy` für maximale Schreibgeschwindigkeit (Staging-Ansatz).
* **Inkrementeller Sync:** Lädt nur geänderte Daten (Delta) basierend auf der `GESPEICHERT`-Spalte ("High Watermark").
* **Automatische Schema-Erstellung:** Erstellt Staging- und Zieltabellen im SQL Server automatisch basierend auf dem Firebird-Schema (inkl. Datentyp-Mapping).
* **Self-Healing:** Erkennt fehlende Primärschlüssel oder Indizes auf der Zielseite und repariert diese automatisch.
* **Parallelisierung:** Verarbeitet mehrere Tabellen gleichzeitig (PowerShell 7+ `ForEach-Object -Parallel`).
* **GUI Config Manager:** Komfortables Tool (`Out-GridView`) zum Auswählen der zu synchronisierenden Tabellen.

## 📂 Dateistruktur

| Datei | Beschreibung |
| :--- | :--- |
| **`Sync_Firebird_MSSQL_AutoSchema.ps1`** | **Das Hauptskript.** Führt den Synchronisationsprozess durch (Extrakt -> Staging -> Merge). |
| **`Manage_Config_Tables.ps1`** | Interaktives GUI-Tool zum Verwalten der Tabellenliste in der `config.json`. Liest Metadaten aus Firebird. |
| **`sql_server_setup.sql`** | SQL-Skript zur Initialisierung der Ziel-Datenbank (`STAGING`) und der generischen Merge-Prozedur. |
| **`config.json`** | Enthält Zugangsdaten und die Liste der Tabellen (wird von Git ignoriert). |
| **`config.sample.json`** | Vorlage für die Konfiguration. |
| **`test_dotnet_firebird.ps1`** | Einfaches Diagnoseskript zum Testen der Firebird-Verbindung und des Treibers. |
| **`.gitignore`** | Stellt sicher, dass `config.json` (mit Passwörtern) nicht ins Repository gelangt. |

## 🛠️ Voraussetzungen

1.  **PowerShell 7+**: Zwingend erforderlich für die Parallelverarbeitung (`-Parallel`).
2.  **Firebird .NET Provider**: Das Skript versucht, diesen via NuGet automatisch zu installieren.
3.  **Zugriff**:
    * Leserechte auf der Firebird-Quelldatenbank.
    * `db_owner` oder `ddl_admin` Rechte auf der MSSQL-Zieldatenbank (zum Erstellen von Tabellen/Prozeduren).

## ⚙️ Installation & Einrichtung

### 1. Datenbank vorbereiten
Führe das Skript `sql_server_setup.sql` auf deinem Microsoft SQL Server aus.
* Erstellt die Datenbank `STAGING` (falls nicht vorhanden).
* Erstellt die Stored Procedure `sp_Merge_Generic`, die für den intelligenten Datenabgleich (Merge) zuständig ist.

### 2. Konfiguration anlegen
Kopiere die `config.sample.json` zu `config.json` und trage deine Verbindungsdaten ein:

```json
{
  "Firebird": {
    "Server": "svrerp01",
    "Database": "D:\\DB\\LA01_ECHT.FDB",
    "User": "SYSDBA",
    ...
  },
  "MSSQL": {
    "Server": "SVRSQL03",
    "Database": "STAGING",
    ...
  },
  "Tables": [] 
}
```

### 3. Tabellen auswählen
Starte das Management-Skript, um festzulegen, welche Tabellen synchronisiert werden sollen:

```powershell
.\Manage_Config_Tables.ps1
```
* Das Skript lädt alle verfügbaren Tabellen aus Firebird.
* **GUI-Bedienung:**
    * Markiere Tabellen, die du **hinzufügen** oder **entfernen** willst.
    * Logik: Ist eine Tabelle schon in der Config und du wählst sie aus -> **Löschen**. Ist sie neu -> **Hinzufügen**.
* Es wird automatisch ein Backup der alten Config erstellt.

## ▶️ Nutzung (Der Sync-Prozess)

Starte den Synchronisationslauf manuell oder per Task Scheduler:

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1
```

**Ablauf des Skripts:**
1.  **Analyse:** Prüft für jede Tabelle, ob `ID` (PK) und `GESPEICHERT` (Datum) vorhanden sind.
    * *Mit ID & Datum:* **Inkrementeller Sync** (Schnell).
    * *Ohne Datum:* **Full Merge** (Langsamer, lädt alles).
    * *Ohne ID:* **Snapshot** (Truncate & Insert).
2.  **Schema-Check:** Prüft, ob die Staging-Tabelle existiert. Falls nein (oder bei Schema-Änderungen), wird sie basierend auf Firebird-Metadaten neu erstellt.
3.  **Bulk Load:** Lädt Daten via Firebird-Reader direkt in den SQL Server (Memory-to-Memory Streaming).
4.  **Merge:** Ruft `sp_Merge_Generic` auf, um die Daten aus Staging in die finale Tabelle zu überführen.
5.  **Index-Pflege:** Stellt sicher, dass auf der Zieltabelle immer ein Primary Key auf `[ID]` existiert (Performance-kritisch!).

## ⚠️ Wichtige Hinweise

* **Timeout:** Für sehr große Tabellen ist im Skript ein `GlobalTimeout` von 7200 Sekunden (2 Stunden) vorkonfiguriert.
* **Datentypen:** Das Skript mappt Firebird-Typen automatisch (z.B. `TimeSpan` -> `TIME`, `Blob-Text` -> `NVARCHAR(MAX)`).
* **Löschungen:** Da der Sync inkrementell arbeitet (nur `> LetztesDatum`), werden **gelöschte** Datensätze in Firebird standardmäßig *nicht* im SQL Server gelöscht (außer im Snapshot-Modus). Für eine vollständige Bereinigung sollte gelegentlich ein Full-Sync (leeren der Zieltabellen) durchgeführt werden.
