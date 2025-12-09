# PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer

[![de](https://img.shields.io/badge/lang-de-green.svg)](README.de.md)

High-performance, parallelized ETL solution for incremental synchronization of Firebird databases (e.g., AvERP) to Microsoft SQL Server.

Replaces outdated Linked Server solutions with a modern PowerShell approach using `SqlBulkCopy` and intelligent schema mapping.

---

## Table of Contents

- [PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer](#psfirebirdtomssql-firebird-to-mssql-high-performance-synchronizer)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [File Structure](#file-structure)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [Step 1: Copy Files](#step-1-copy-files)
    - [Step 2: Create Configuration](#step-2-create-configuration)
    - [Step 3: SQL Server Environment (Automatic)](#step-3-sql-server-environment-automatic)
    - [Step 4: Store Credentials Securely](#step-4-store-credentials-securely)
    - [Step 5: Test Connection](#step-5-test-connection)
    - [Step 6: Select Tables](#step-6-select-tables)
    - [Step 7: Automatic Task Scheduling (Optional)](#step-7-automatic-task-scheduling-optional)
  - [Usage](#usage)
    - [Start Sync (Default)](#start-sync-default)
    - [Start Sync (Specific Config)](#start-sync-specific-config)
    - [Sync Process Flow](#sync-process-flow)
    - [Sync Strategies](#sync-strategies)
  - [Configuration Options](#configuration-options)
    - [General Section](#general-section)
    - [Column Configuration (NEW in v2.10)](#column-configuration-new-in-v210)
    - [Orphan Cleanup (Deletion Detection)](#orphan-cleanup-deletion-detection)
    - [MSSQL Prefix \& Suffix](#mssql-prefix--suffix)
    - [JSON Schema Validation (NEW)](#json-schema-validation-new)
  - [Module Architecture](#module-architecture)
  - [Usage in Custom Scripts](#usage-in-custom-scripts)
  - [Credential Management](#credential-management)
  - [Logging](#logging)
  - [Important Notes](#important-notes)
    - [Deletions Are Not Synchronized by Default (CleanupOrphans Option)](#deletions-are-not-synchronized-by-default-cleanuporphans-option)
    - [Task Scheduler Integration (Path Adjustment)](#task-scheduler-integration-path-adjustment)
  - [Architecture](#architecture)
  - [Changelog](#changelog)
    - [v2.10 (2025-12-09) - Dynamic Column Configuration](#v210-2025-12-09---dynamic-column-configuration)
    - [v2.9 (2025-12-06) - Orphan Cleanup (Soft Deletes)](#v29-2025-12-06---orphan-cleanup-soft-deletes)
    - [v2.8 (2025-12-06) - Module Architecture \& Bugfixes](#v28-2025-12-06---module-architecture--bugfixes)
    - [v2.7 (2025-12-04) - Auto-Setup \& Robustness](#v27-2025-12-04---auto-setup--robustness)
    - [v2.6 (2025-12-03) - Task Automation](#v26-2025-12-03---task-automation)
    - [v2.5 (2025-11-29) - Prefix/Suffix \& Fixes](#v25-2025-11-29---prefixsuffix--fixes)
    - [v2.1 (2025-11-25) - Secure Credentials](#v21-2025-11-25---secure-credentials)

---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` for maximum write performance (staging approach with memory streaming).
- **Incremental Sync**: Loads only changed data (delta) based on the `GESPEICHERT` column (High Watermark Pattern).
- **Auto-Environment Setup**: The script checks at startup whether the target database exists. If not, it connects to `master`, **creates the database** automatically, and sets the recovery model to `SIMPLE`.
- **Auto-Install SP**: Automatically installs or updates the required stored procedure `sp_Merge_Generic` from `sql_server_setup.sql`.
- **Flexible Naming**: Supports **prefixes** and **suffixes** for target tables (e.g., source `KUNDE` -> target `DWH_KUNDE_V1`).
- **Multi-Config Support**: The `-ConfigFile` parameter allows separate jobs (e.g., Daily vs. Weekly).
- **Self-Healing**: Detects schema changes, missing primary keys, and indexes, and repairs them.
- **Parallelization**: Processes multiple tables simultaneously (PowerShell 7+ `ForEach-Object -Parallel`).
- **Secure Credentials**: Windows Credential Manager instead of plaintext passwords.
- **GUI Config Manager**: Convenient tool for table selection with metadata preview.
- **NEW: Module Architecture**: Reusable functions in `SQLSyncCommon.psm1`.
- **NEW: JSON Schema Validation**: Optional configuration file validation.
- **NEW: Secure Connection Handling**: No resource leaks through guaranteed cleanup (try/finally).

---

## File Structure

```text
SQLSync/
├── SQLSyncCommon.psm1                   # CORE MODULE: Shared functions (MUST be present!)
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Main script (Extract -> Staging -> Merge)
├── Setup_Credentials.ps1                # One-time: Store passwords securely
├── Setup_ScheduledTasks.ps1             # Template for Windows Tasks (adjust paths!)
├── Manage_Config_Tables.ps1             # GUI tool for table management
├── Get_Firebird_Schema.ps1              # Helper tool: Data type analysis
├── sql_server_setup.sql                 # SQL template for DB & SP (used by main script)
├── Example_Sync_Start.ps1               # Example wrapper
├── Test-SQLSyncConnections.ps1          # Connection test
├── config.json                          # Credentials & settings (git-ignored)
├── config.sample.json                   # Configuration template
├── config.schema.json                   # JSON schema for validation (optional)
├── .gitignore                           # Protects config.json
└── Logs/                                # Log files (created automatically)
```

---

## Prerequisites

| Component              | Requirement                                                                     |
| :--------------------- | :------------------------------------------------------------------------------ |
| PowerShell             | Version 7.0 or higher (required for `-Parallel`)                                |
| Firebird .NET Provider | Automatically installed via NuGet                                               |
| Firebird Access        | Read permissions on the source database                                         |
| MSSQL Access           | Permission to create DBs (`db_creator`) or at least `db_owner` on target DB     |

---

## Installation

### Step 1: Copy Files

Copy all `.ps1`, `.sql`, `.json`, and especially the `.psm1` files to a common directory (e.g., `E:\SQLSync_Firebird_to_MSSQL\`).

**Important:** The file `SQLSyncCommon.psm1` must be in the same directory as the scripts!

### Step 2: Create Configuration

Copy `config.sample.json` to `config.json` and adjust the values.

**Example Configuration:**

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

_Note on MSSQL Port:_ The script primarily uses the `Server` parameter. If a non-standard port (other than 1433) is needed, specify it in the format `ServerName,Port` in the `Server` field (e.g., `"SVRSQL03,1433"`).

### Step 3: SQL Server Environment (Automatic)

The main script includes a **Pre-Flight Check**.
When the script starts, the following happens automatically:

1.  Connection attempt to the `master` system database.
2.  **Create Database:** If the target DB doesn't exist, it is created and set to `RECOVERY SIMPLE`.
3.  **Install Procedure:** If `sp_Merge_Generic` is missing, it is installed from `sql_server_setup.sql`.

### Step 4: Store Credentials Securely

Run the setup script to store passwords encrypted in the Windows Credential Manager:

```powershell
.\Setup_Credentials.ps1
```

### Step 5: Test Connection

```powershell
.\Test-SQLSyncConnections.ps1
```

### Step 6: Select Tables

Start the GUI manager to select tables:

```powershell
.\Manage_Config_Tables.ps1
```

The manager offers a **toggle logic**:

- Selected tables that are _not_ in the config -> Will be **added**.
- Selected tables that are _already_ in the config -> Will be **removed**.

### Step 7: Automatic Task Scheduling (Optional)

Use the provided script to set up synchronization in the Windows Task Scheduler. The script creates tasks for Daily Diff & Weekly Full.

**WARNING:** The script `Setup_ScheduledTasks.ps1` serves as a template and contains example paths (e.g., `E:\SQLSync_...`).

1.  Open `Setup_ScheduledTasks.ps1` in an editor.
2.  Adjust the variables `$ScriptPath`, `$WorkDir`, and config names to your environment.
3.  Run it as Administrator only after making adjustments.

```powershell
# Run as Administrator!
.\Setup_ScheduledTasks.ps1
```

---

## Usage

### Start Sync (Default)

Starts the sync with the default file `config.json` in the script directory:

```powershell
.\Sync_Firebird_MSSQL_AutoSchema.ps1
```

### Start Sync (Specific Config)

For separate jobs (e.g., Daily incremental vs. Weekly Full), a configuration file can be passed:

```powershell
# Example for a Weekly job
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile "config_weekly_full.json"
```

### Sync Process Flow

```text
┌─────────────────────────────────────────────────────────────┐
│  1. PRE-FLIGHT CHECK (New in v2.7)                          │
│     Connect to 'master', Auto-Create DB, Auto-Install SP    │
├─────────────────────────────────────────────────────────────┤
│  2. INITIALIZATION (Load module)                            │
│     Load config, Get credentials from Credential Manager    │
├─────────────────────────────────────────────────────────────┤
│  3. ANALYSIS (per table, parallel)                          │
│     Check source schema for ID and GESPEICHERT              │
│     → Select strategy: Incremental / FullMerge / Snapshot   │
├─────────────────────────────────────────────────────────────┤
│  4. SCHEMA CHECK                                            │
│     Create STG_<Table> if not present                       │
├─────────────────────────────────────────────────────────────┤
│  5. EXTRACT & LOAD                                          │
│     Firebird Reader -> BulkCopy Stream -> MSSQL Staging     │
├─────────────────────────────────────────────────────────────┤
│  6. MERGE                                                   │
│     sp_Merge_Generic: Staging -> Target table (with Prefix) │
│     Self-Healing: Creates missing Primary Keys              │
├─────────────────────────────────────────────────────────────┤
│  7. SANITY CHECK & RETRY LOOP                               │
└─────────────────────────────────────────────────────────────┘
```

### Sync Strategies

| Strategy        | Condition                            | Behavior                          |
| :-------------- | :----------------------------------- | :-------------------------------- |
| **Incremental** | ID + Timestamp column present        | Loads only delta (fastest option) |
| **FullMerge**   | ID present, no timestamp column      | Loads all, merges by ID           |
| **Snapshot**    | No ID                                | Truncate & complete insert        |

---

## Configuration Options

### General Section

| Variable                 | Default  | Description                                                    |
| :----------------------- | :------- | :------------------------------------------------------------- |
| `GlobalTimeout`          | 7200     | Timeout in seconds for SQL commands and BulkCopy               |
| `RecreateStagingTable`   | `false`  | `true` = Recreate staging on each run (schema update)          |
| `ForceFullSync`          | `false`  | `true` = **Truncate** target table + complete reload           |
| `RunSanityCheck`         | `true`   | `false` = Skip COUNT comparison                                |
| `MaxRetries`             | 3        | Retry attempts on error                                        |
| `RetryDelaySeconds`      | 10       | Wait time between retries                                      |
| `DeleteLogOlderThanDays` | 30       | Automatically delete logs after X days (0 = Disabled)          |
| `CleanupOrphans`         | `false`  | Delete orphaned records in target                              |
| `OrphanCleanupBatchSize` | 50000    | Batch size for ID transfer during cleanup                      |
| `IdColumn`               | `"ID"`   | Default ID column name for all tables                          |
| `TimestampColumns`       | `["GESPEICHERT"]` | List of possible timestamp columns (first found is used) |

### Column Configuration (NEW in v2.10)

The script now supports flexible column configuration for different table structures.

**Global Defaults:**

```json
{
  "General": {
    "IdColumn": "ID",
    "TimestampColumns": ["GESPEICHERT", "MODIFIED_DATE", "LAST_UPDATE", "CHANGED_AT"]
  }
}
```

**Table-Specific Overrides:**

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

**Logic:**

1. Check if `TableOverrides[Table]` exists → Use override values
2. `IdColumn`: Override → Global → "ID" (default)
3. `TimestampColumn`: Override → First found from `TimestampColumns` → `null`
4. Strategy: HasId + HasTimestamp → Incremental | HasId → FullMerge | else → Snapshot

### Orphan Cleanup (Deletion Detection)

When `CleanupOrphans: true` is set, all records in the target that no longer exist in the source are deleted after sync.

**Process:**

1.  Load all IDs from Firebird into a temp table (in batches for memory efficiency)
2.  `DELETE FROM Target WHERE ID NOT IN (SELECT ID FROM #TempIDs)`
3.  Clean up temp table

**Limitations:**

- Only works for tables with an `ID` column (not for Snapshot strategy)
- Increases runtime as all IDs must be transferred
- Not necessary with `ForceFullSync` (table is completely reloaded anyway)

**Recommendation:**

- `CleanupOrphans: false` for daily diff syncs (performance)
- `CleanupOrphans: true` for weekly full syncs (data cleanup)

### MSSQL Prefix & Suffix

Control naming in the target system.

- **Prefix**: `DWH_` -> Target table becomes `DWH_KUNDE`
- **Suffix**: `_V1` -> Target table becomes `KUNDE_V1`

### JSON Schema Validation (NEW)

The file `config.schema.json` can be used for validation to avoid typos in the config:

```powershell
$json = Get-Content "config.json" -Raw
Test-Json -Json $json -SchemaFile "config.schema.json"
```

---

## Module Architecture

Starting with version 2.8, SQLSync uses a shared PowerShell module (`SQLSyncCommon.psm1`) for reusable functions. This module must always be in the script directory.

The module centrally provides the following functions:

- **Credential Management:** `Get-StoredCredential`, `Resolve-FirebirdCredentials`
- **Configuration:** `Get-SQLSyncConfig` (including schema validation)
- **Driver Loading:** `Initialize-FirebirdDriver`
- **Type Mapping:** `ConvertTo-SqlServerType` (.NET to SQL data types)

---

## Usage in Custom Scripts

```powershell
Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force

$Config = Get-SQLSyncConfig -ConfigPath ".\config.json"
$FbCreds = Resolve-FirebirdCredentials -Config $Config.RawConfig

$ConnStr = New-FirebirdConnectionString `
    -Server $Config.FBServer `
    -Database $Config.FBDatabase `
    -Username $FbCreds.Username `
    -Password $FbCreds.Password

# Work directly with try/finally (recommended)
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

Credentials are stored in the Windows Credential Manager under the following names:

- `SQLSync_Firebird`
- `SQLSync_MSSQL`

```powershell
# Display
cmdkey /list:SQLSync*

# Delete
cmdkey /delete:SQLSync_Firebird
cmdkey /delete:SQLSync_MSSQL
```

---

## Logging

All output is automatically written to a log file:
`Logs\Sync_<ConfigName>_YYYY-MM-DD_HHmm.log`

---

## Important Notes

### Deletions Are Not Synchronized by Default (CleanupOrphans Option)

The incremental sync only detects new/changed records. Deleted records in Firebird remain in SQL Server (history). To clean this up, use `ForceFullSync: true` in a regular maintenance task (e.g., Sundays) that empties and rebuilds the target tables. This also updates the schema.
Alternatively, `CleanupOrphans: true` can be used to compare IDs.

### Task Scheduler Integration (Path Adjustment)

It is recommended to use the script `Setup_ScheduledTasks.ps1` as a template. **Important:** Since the script uses environment variables like `$WorkDir` and `$ScriptPath` with example values, **it must be edited before execution** to point to your actual installation.

Manual call parameters for custom integrations:

```text
Program: pwsh.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Scripts\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "config.json"
Start in: C:\Scripts
```

---

## Architecture

```text
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│    Firebird      │         │   PowerShell 7   │         │   SQL Server     │
│   (Source)       │         │   ETL Engine     │         │   (Target)       │
├──────────────────┤         ├──────────────────┤         ├──────────────────┤
│                  │  Read   │                  │  Write  │                  │
│  Table A         │ ──────► │  Parallel Jobs   │ ──────► │  STG_A (Staging) │
│  Table B         │         │  (ThrottleLimit) │         │  STG_B (Staging) │
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

- **NEW:** `IdColumn` - Global configuration for ID column name (default: "ID")
- **NEW:** `TimestampColumns` - List of possible timestamp column names (first found is used)
- **NEW:** `TableOverrides` - Table-specific overrides for ID and timestamp columns
- **NEW:** `Get-TableColumnConfig` function in module for reusable column logic
- **Feature:** Automatic strategy selection based on available columns
- **Backwards compatible:** Without configuration, "ID" and "GESPEICHERT" are still used

### v2.9 (2025-12-06) - Orphan Cleanup (Soft Deletes)

- **NEW:** `CleanupOrphans` option - Detects and deletes orphaned records in target
- **NEW:** `OrphanCleanupBatchSize` - Configurable batch size for large tables
- **NEW:** "Del" column in summary shows deleted orphans
- Batch-based ID transfer for memory efficiency with >100,000 rows

### v2.8 (2025-12-06) - Module Architecture & Bugfixes

- **NEW:** `SQLSyncCommon.psm1` - Shared module for reusable functions.
- **NEW:** `config.schema.json` - JSON schema for configuration validation.
- **FIX:** Connection leak fixed - Connections are now guaranteed to close.
- **FIX:** `Get_Firebird_Schema.ps1` - Fixed missing `Get-StoredCredential` function.
- **Refactoring:** Removed duplicate code from all scripts (~60% less redundancy).

### v2.7 (2025-12-04) - Auto-Setup & Robustness

- **Feature:** Integrated Pre-Flight Check: Creates database and installs `sp_Merge_Generic` automatically (via `sql_server_setup.sql`) if missing.
- **Fix:** Improved handling of SQL comments when reading SQL files.

### v2.6 (2025-12-03) - Task Automation

- **New:** `Setup_ScheduledTasks.ps1` for automatic Windows Task Scheduler setup.

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` and `MSSQL.Suffix` implemented.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager integration.
