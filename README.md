# PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer

[![de](https://img.shields.io/badge/lang-de-green.svg)](README.de.md)
[![CI](https://github.com/gitnol/PSFirebirdToMSSQL/actions/workflows/ci.yml/badge.svg)](https://github.com/gitnol/PSFirebirdToMSSQL/actions/workflows/ci.yml)

High-performance, parallelized ETL solution for incremental synchronization of Firebird databases (e.g., AvERP) to Microsoft SQL Server.

Replaces outdated Linked Server solutions with a modern PowerShell approach using `SqlBulkCopy` and intelligent schema mapping.

---

## Table of Contents

- [PSFirebirdToMSSQL: Firebird to MSSQL High-Performance Synchronizer](#psfirebirdtomssql-firebird-to-mssql-high-performance-synchronizer)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [File Structure](#file-structure)
  - [Prerequisites](#prerequisites)
    - [Firebird Driver (Integrity Check)](#firebird-driver-integrity-check)
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
    - [Naming Rules (since v2.12)](#naming-rules-since-v212)
    - [JSON Schema Validation](#json-schema-validation)
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
  - [⚖ Disclaimer](#-disclaimer)
---

## Features

- **High-Speed Transfer**: .NET `SqlBulkCopy` for maximum write performance (staging approach with memory streaming).
- **Incremental Sync**: Loads only changed data (delta) based on configurable timestamp columns (High Watermark Pattern).
- **Dynamic Column Configuration**: Flexible ID and timestamp column names - works with any table structure, not just `ID`/`GESPEICHERT`.
- **Auto-Environment Setup**: The script checks at startup whether the target database exists. If not, it connects to `master`, **creates the database** automatically, and sets the recovery model to `SIMPLE`.
- **Auto-Install SP**: Automatically installs or updates the required stored procedure `sp_Merge_Generic` from `sql_server_setup.sql`.
- **Flexible Naming**: Supports **prefixes** and **suffixes** for target tables (e.g., source `KUNDE` -> target `DWH_KUNDE_V1`).
- **Multi-Config Support**: The `-ConfigFile` parameter allows separate jobs (e.g., Daily vs. Weekly).
- **Self-Healing**: Detects schema changes, missing primary keys, and indexes, and repairs them.
- **Parallelization**: Processes multiple tables simultaneously (PowerShell 7+ `ForEach-Object -Parallel`).
- **Secure Credentials**: Windows Credential Manager instead of plaintext passwords.
- **GUI Config Manager**: Convenient tool for table selection with metadata preview.
- **Module Architecture**: Reusable functions in `SQLSyncCommon.psm1`.
- **JSON Schema Validation**: Every script checks the configuration against `config.schema.json` when loading (fail-fast, exit code 2).
- **Secure Connection Handling**: No resource leaks through guaranteed cleanup (try/finally).

---

## File Structure

```text
PSFirebirdToMSSQL/
├── SQLSyncCommon.psm1                   # CORE MODULE: Shared functions (MUST be present!)
├── Sync_Firebird_MSSQL_AutoSchema.ps1   # Main script (Extract -> Staging -> Merge)
├── Setup_Credentials.ps1                # One-time: Store passwords securely
├── Setup-ScheduledTasks.ps1             # Creates the Windows Tasks (parameters, -WhatIf preview)
├── Manage_Config_Tables.ps1             # GUI tool for table management
├── Get_Firebird_Schema.ps1              # Helper tool: Data type analysis
├── sql_server_setup.sql                 # SQL template for DB & SP (used by main script)
├── Example_Sync_Start.ps1               # Example wrapper
├── Test-SQLSyncConnections.ps1          # Connection test
├── config.json                          # Credentials & settings (git-ignored)
├── config.sample.json                   # Configuration template
├── config.schema.json                   # JSON schema, checked on every config load
├── .gitignore                           # Protects config.json
└── Logs/                                # Log files (created automatically)
```

---

## Prerequisites

| Component              | Requirement                                                                 |
| :--------------------- | :-------------------------------------------------------------------------- |
| PowerShell             | Version 7.0 or higher (required for `-Parallel`)                            |
| Firebird .NET Provider | Automatically installed via NuGet                                           |
| Firebird Access        | Read permissions on the source database                                     |
| MSSQL Access           | Permission to create DBs (`db_creator`) or at least `db_owner` on target DB |

### Firebird Driver (Integrity Check)

On the first run (as administrator) `Initialize-FirebirdDriver` downloads `FirebirdSql.Data.FirebirdClient` 10.3.4 from NuGet to `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\`. **Every** DLL is checked by SHA-256 before it is loaded - the fresh download, a DLL already present in `%ProgramData%` and a DLL configured via `Firebird.DllPath`. Only the original DLLs from the NuGet package 10.3.4 are accepted:

| DLL | SHA-256 |
|---|---|
| `lib\net8.0` | `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05` |
| `lib\netstandard2.1` | `8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A` |

On a mismatch the script stops before any database connection (`SHA-256 der Treiber-DLL ... stimmt nicht ... Treiber wurde NICHT geladen`, sync exit code 7). Do **not** simply copy the reported hash into the configuration - fetch the file again from the official package (delete the driver folder and run once as administrator). To use a different driver version on purpose, set its expected hash in `Firebird.DllSha256` (64 hex characters, computed yourself from the official package); then only this hash is accepted. Write access to `%ProgramData%\SQLSync\Drivers` should be limited to administrators (check with `icacls "$env:ProgramData\SQLSync\Drivers"`).

**Firebird account:** use a dedicated read-only account (only `SELECT` on the configured tables, no DDL, no `CREATE FUNCTION`) instead of `SYSDBA`, and keep the Firebird server at 5.0.4 / 4.0.7 / 3.0.14 or later. Background: CVE-2026-40342 (CVSS 9.9) lets an authenticated user with `CREATE FUNCTION` execute code as the OS account of the Firebird server on older versions.

---

## Installation

### Step 1: Copy Files

Copy all `.ps1`, `.sql`, `.json`, and especially the `.psm1` files to a common directory (e.g., `C:\Scripts\PSFirebirdToMSSQL\`).

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
    "Database": "D:\\DB\\ERP.FDB",
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

_Note on MSSQL Port:_ The script primarily uses the `Server` parameter. If a non-standard port (other than 1433) is needed, specify it in the format `ServerName,Port` in the `Server` field (e.g., `"SQLSERVER01,1433"`).

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

Different entry names (e.g. one per SQL Server): see [Credential Management](#credential-management).

### Step 5: Test Connection

```powershell
.\Test-SQLSyncConnections.ps1
```

Before the first productive run and before every update, run the read-only pre-deployment check (only `SELECT` statements, no DDL/DML; the driver DLL is hashed, not loaded):

```powershell
.\Test-SQLSyncConnections.ps1 -ConfigFile .\config.json -PreDeploy
```

In addition to the connection test it checks:

- every `config*.json` in the script folder (except `config.schema.json` / `config.sample.json`) against the schema and naming rules → `OK` / `FEHLER` (missing schema file → `WARNUNG`)
- the driver DLL against the allowed SHA-256 values → `OK` / `FEHLER` (no DLL yet → `WARNUNG`); on `FEHLER` the check stops immediately with exit code 6
- the Firebird server version against known server advisories (CVE-2026-34232, CVE-2026-40342) → `WARNUNG`
- login as `SYSDBA` → `WARNUNG` (use a read-only account)
- legacy target tables: decimal columns of the configured tables whose target precision or scale is smaller than in Firebird → `WARNUNG` with target and source type (fix: `docs/operations/RUNBOOK.md`)

Example output (fictional names and version; messages are in German):

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

| Exit code | Meaning |
|---|---|
| 0 | All tests passed; with `-PreDeploy`: no `FEHLER` (`WARNUNG` allowed) |
| 1 | Module/config missing or a connection test failed |
| 2 | Configuration invalid (parse error, schema, naming rules) |
| 3 | Credentials not found |
| 4 | Driver could not be loaded (incl. SHA-256 mismatch) |
| 6 | `-PreDeploy` found at least one `FEHLER` – do not deploy |

### Step 6: Select Tables

Start the GUI manager to select tables:

```powershell
.\Manage_Config_Tables.ps1
# another job profile:
.\Manage_Config_Tables.ps1 -ConfigFile .\config_weekly_full.json
```

The manager offers a **toggle logic**:

- Selected tables that are _not_ in the config -> Will be **added**.
- Selected tables that are _already_ in the config -> Will be **removed**.

Before the GridView opens, the configuration is validated (schema + naming rules; violation → exit 2, no backup). A selection that would remove the last table is rejected (exit 4), so a config without tables is never written. `Get_Firebird_Schema.ps1 -TableName <table>` also accepts `-ConfigFile`.

### Step 7: Automatic Task Scheduling (Optional)

Use the provided script to set up synchronization in the Windows Task Scheduler. The script creates tasks for Daily Diff & Weekly Full.

**WARNING:** Paths and config names are parameters – the script no longer needs to be edited. Defaults: installation folder = folder of the script, `config.json` (daily) and `config_weekly_full.json` (weekly). Always check the result with `-WhatIf` first: missing files only produce a warning, the tasks would still be created.

| Parameter | Default |
|---|---|
| `-InstallDir` | folder of the script |
| `-DailyConfigFile` / `-WeeklyConfigFile` | `config.json` / `config_weekly_full.json` (relative to `-InstallDir` or absolute) |
| `-DailyTaskName` / `-WeeklyTaskName` | `SQLSync_Firebird_Daily_Diff` / `SQLSync_Firebird_Weekly_Full` |
| `-DailyStart`, `-DailyDays`, `-DailyIntervalMinutes`, `-DailyDurationHours` | `06:01`, Monday–Friday, `30`, `15` |
| `-WeeklyDay`, `-WeeklyStart` | `Sunday`, `05:13` |
| `-RunAsUser` | current user (Windows password is prompted) |
| `-GmsaAccount` | – (gMSA as `DOMAIN\name$`, no stored password) |

```powershell
# 1. Preview: no admin rights, no password prompt, nothing is registered
.\Setup-ScheduledTasks.ps1 -InstallDir D:\Apps\SQLSync -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json -WhatIf

# 2. Register (run as Administrator!)
.\Setup-ScheduledTasks.ps1 -InstallDir D:\Apps\SQLSync -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json

# Optional: run as gMSA instead of the current user
.\Setup-ScheduledTasks.ps1 -GmsaAccount 'EXAMPLE\svc-sqlsync$'
```

Note on gMSA: Credential Manager entries are bound to the account that creates them. With a gMSA, use mainly `"Integrated Security": true` for SQL Server; Firebird credentials would have to be created in the context of the gMSA.

**Existing installations:** If you used the paths and config names previously hard-coded in the script, pass `-InstallDir`, `-DailyConfigFile` and `-WeeklyConfigFile` explicitly when re-creating the tasks (check with `-WhatIf` first). Tasks that are already registered are not affected.

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
│  1. PRE-FLIGHT CHECK                                        │
│     Connect to 'master', Auto-Create DB, Auto-Install SP    │
├─────────────────────────────────────────────────────────────┤
│  2. INITIALIZATION (Load module)                            │
│     Load config, Get credentials from Credential Manager    │
├─────────────────────────────────────────────────────────────┤
│  3. ANALYSIS (per table, parallel)                          │
│     Check source schema for ID and timestamp columns        │
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

| Strategy        | Condition                       | Behavior                          |
| :-------------- | :------------------------------ | :-------------------------------- |
| **Incremental** | ID + Timestamp column present   | Loads only delta (fastest option) |
| **FullMerge**   | ID present, no timestamp column | Loads all, merges by ID           |
| **Snapshot**    | No ID                           | Truncate & complete insert        |

---

## Configuration Options

### General Section

| Variable                 | Default           | Description                                              |
| :----------------------- | :---------------- | :------------------------------------------------------- |
| `GlobalTimeout`          | 7200              | Timeout in seconds for SQL commands and BulkCopy         |
| `RecreateStagingTable`   | `false`           | `true` = Recreate staging on each run (schema update)    |
| `ForceFullSync`          | `false`           | `true` = **Truncate** target table + complete reload     |
| `NumberOfThreads`        | 4                 | Number of parallel threads for table sync                |
| `RunSanityCheck`         | `true`            | `false` = Skip COUNT comparison                          |
| `FailOnSanityError`      | `true`            | `false` = Sanity `FEHLER` does not cause exit code 11   |
| `IncrementalOverlapMinutes` | 10             | Incremental: read from `MAX(timestamp)` in target minus X minutes (0–1440) |
| `MaxRetries`             | 3                 | Retry attempts on error                                  |
| `RetryDelaySeconds`      | 10                | Wait time between retries                                |
| `DeleteLogOlderThanDays` | 30                | Automatically delete logs after X days (0 = Disabled)    |
| `CleanupOrphans`         | `false`           | Delete orphaned records in target                        |
| `OrphanCleanupBatchSize` | 50000             | Batch size for ID transfer during cleanup                |
| `IdColumn`               | `"ID"`            | Default ID column name for all tables                    |
| `TimestampColumns`       | `["GESPEICHERT"]` | List of possible timestamp columns (first found is used) |

### Column Configuration (NEW in v2.10)

The script now supports flexible column configuration for different table structures. This makes it compatible with any Firebird database, not just AvERP.

**Global Defaults:**

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

- `IdColumn`: The default primary key column name used for MERGE operations
- `TimestampColumns`: A list of possible timestamp column names. The script checks each column in order and uses the first one found in the source table.

**Table-Specific Overrides:**

For tables with non-standard column names, use `TableOverrides`:

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

**Resolution Logic:**

1. Check if `TableOverrides[TableName]` exists → Use override values
2. `IdColumn`: Override → Global `IdColumn` → `"ID"` (default)
3. `TimestampColumn`: Override → First found from `TimestampColumns` list → `null`
4. Strategy selection: HasId + HasTimestamp → Incremental | HasId → FullMerge | else → Snapshot

**Backwards Compatibility:**

Without any configuration, the script uses `"ID"` and `"GESPEICHERT"` as defaults, maintaining full backwards compatibility with existing setups.

### Orphan Cleanup (Deletion Detection)

When `CleanupOrphans: true` is set, all records in the target that no longer exist in the source are deleted after sync.

**Process:**

1.  Load all IDs from Firebird into a temp table (in batches for memory efficiency)
2.  `DELETE FROM Target WHERE ID NOT IN (SELECT ID FROM #TempIDs)`
3.  Clean up temp table

**Limitations:**

- Only works for tables with an ID column (not for Snapshot strategy)
- Increases runtime as all IDs must be transferred
- Not necessary with `ForceFullSync` (table is completely reloaded anyway)

**Recommendation:**

- `CleanupOrphans: false` for daily diff syncs (performance)
- `CleanupOrphans: true` for weekly full syncs (data cleanup)

### MSSQL Prefix & Suffix

Control naming in the target system.

- **Prefix**: `DWH_` -> Target table becomes `DWH_KUNDE`
- **Suffix**: `_V1` -> Target table becomes `KUNDE_V1`

### Naming Rules (since v2.12)

Table and column names (`Tables`, `General.IdColumn`, `General.TimestampColumns`, `TableOverrides` keys and values) as well as `MSSQL.Database`, `MSSQL.Prefix` and `MSSQL.Suffix` may only contain `A-Z`, `a-z`, `0-9`, `_` and `$`, with at most 63 characters (Firebird limit). Prefix + table + suffix must not exceed 128 characters (SQL Server limit). Empty values are allowed only for `MSSQL.Database`, Prefix/Suffix and the override columns.

Violations stop the sync while loading the configuration (exit code 2; message from the schema check `Konfiguration verletzt das Schema …`, or `Ungültiger Name in '<field>': …` from the code check) before any database connection is opened. `Manage_Config_Tables.ps1` does not offer Firebird tables with invalid names.

### JSON Schema Validation

Since v2.15 every script (`Sync_Firebird_MSSQL_AutoSchema.ps1`, `Test-SQLSyncConnections.ps1`, `Get_Firebird_Schema.ps1`, `Manage_Config_Tables.ps1`) validates the configuration against `config.schema.json` when loading it (`Get-SQLSyncConfig -SchemaPath`). Any violation stops the script with exit code 2 before a database connection is opened, e.g.:

```
Konfiguration verletzt das Schema (config.schema.json): ... bei "/General/GlobalTimeout"; ...
```

Each violation names its JSON path. Wrong types (`"7200"` instead of `7200`), missing required fields, values outside the limits and **unknown keys** (typos such as `ForceFulSync`, because the schema uses `additionalProperties: false`) are detected. New configuration keys must therefore always be added to the schema as well.

`config.schema.json` is part of every installation. If it is missing, only a warning is shown and the run continues without the schema check.

Check a configuration manually (e.g. before an update), without database access:

```powershell
Test-Json -Json (Get-Content .\config.json -Raw) -Schema (Get-Content .\config.schema.json -Raw)
```

---

## Module Architecture

PSFirebirdToMSSQL uses a shared PowerShell module (`SQLSyncCommon.psm1`) for reusable functions. This module must always be in the script directory.

The module centrally provides the following functions:

- **Credential Management:** `Get-StoredCredential`, `Resolve-FirebirdCredentials`
- **Configuration:** `Get-SQLSyncConfig` (including fail-fast schema validation), `Resolve-SQLSyncConfigPath` (shared `-ConfigFile` resolution)
- **Column Configuration:** `Get-TableColumnConfig` (resolves ID/timestamp columns per table)
- **Driver Loading:** `Initialize-FirebirdDriver`, `Test-FirebirdDriverIntegrity` (hash check without loading; constants in `$script:FirebirdDriver`)
- **Rollout Check:** `Get-FirebirdServerAdvisory` (server version vs. known CVEs in `$script:FirebirdServerAdvisories`), `Find-SQLSyncDecimalTruncation` (target `DECIMAL` columns smaller than the source); used by `Test-SQLSyncConnections.ps1 -PreDeploy`
- **Type Mapping:** `ConvertTo-SqlServerType` (.NET to SQL data types; `Decimal` with precision/scale from the Firebird schema). Since v2.14 the parallel sync block imports the module and uses `ConvertTo-SqlServerType` and `Get-TableColumnConfig` directly

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

These are the defaults. The optional keys `Firebird.CredentialTarget` and `MSSQL.CredentialTarget` select a different entry, e.g. when several SQL Servers use the same login (such as `sa`) with different passwords. Store the entry with the matching parameter:

```powershell
.\Setup_Credentials.ps1 -MSSQLTarget "SQLSync_MSSQL_sqltest"   # also: -FirebirdTarget
```

```json
"MSSQL": { "Server": "sqltest", "Database": "STAGING", "CredentialTarget": "SQLSync_MSSQL_sqltest" }
```

The log names the entry used, e.g. `[Credentials] SQL Server: Credential Manager (SQLSync_MSSQL_sqltest)`. Entries remain bound to the Windows account that ran `Setup_Credentials.ps1`.

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

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | All tables synchronized successfully |
| 1 | `SQLSyncCommon.psm1` not found |
| 2 | Configuration error (incl. schema violation and invalid table/column names) |
| 5 | Credentials not found |
| 7 | Firebird driver could not be loaded (incl. SHA-256 mismatch of the driver DLL) |
| 9 | Pre-flight (database / `sp_Merge_Generic`) failed |
| 10 | At least one table failed |
| 11 | Sanity check `FEHLER` (target has fewer rows than source); disable via `FailOnSanityError` |

Task Scheduler shows the code as *Last Run Result* (e.g. `0xA` = 10).

---

## Important Notes

### Deletions Are Not Synchronized by Default (CleanupOrphans Option)

The incremental sync only detects new/changed records. Deleted records in Firebird remain in SQL Server (history). To clean this up, use `ForceFullSync: true` in a regular maintenance task (e.g., Sundays) that empties and rebuilds the target tables. This also updates the schema.
Alternatively, `CleanupOrphans: true` can be used to compare IDs.

### Task Scheduler Integration (Path Adjustment)

It is recommended to create the tasks with `Setup-ScheduledTasks.ps1` (see Step 7). The installation folder and config names are passed as parameters (`-InstallDir`, `-DailyConfigFile`, `-WeeklyConfigFile`); `-WhatIf` shows the resulting task definitions without registering anything.

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

Version numbers refer to the repository state. Each script keeps the number of the last version that changed it (`Sync_Firebird_MSSQL_AutoSchema.ps1`: 2.18 — v2.13 and v2.17 changed other files only; `Test-SQLSyncConnections.ps1`: 2.1).

### v2.18 (2026-10-09) - Incremental Overlap Window
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.18: the incremental extract reads from the watermark (`MAX(timestamp)` of the target table) **minus an overlap window**, inclusive (`>= @LastDate`; up to v2.16 strictly `> MAX(ts)`). Records with a timestamp ≤ watermark that were committed only after the previous run are now picked up, as long as the commit delay is shorter than the window (known issue K3). Longer delays are still only caught by the weekly full run (`ForceFullSync`)
- New optional config key `General.IncrementalOverlapMinutes` (integer 0–1440, default 10; 0 = from the watermark itself, inclusive). Values outside the range are rejected by the schema and by `Get-SQLSyncConfig`
- `RowsLoaded` now includes the rows re-read inside the window, so it is often > 0 even without source changes (the MERGE is idempotent, no duplicates)
- If the `MAX` query on an existing target table fails (e.g. timestamp column missing in the target, timeout), the table now goes through the retry loop and ends with status `Fehler` (exit code 10); up to v2.16 this silently fell back to a full extract from 1900-01-01. Missing or empty target table → full extract with info `(Erstlauf (Zieltabelle fehlt) - Vollabzug)` or `(Kein Wasserzeichen (Zieltabelle leer oder Zeitstempel NULL) - Vollabzug)`
- New module functions `Get-SQLSyncIncrementalLowerBound`, `Get-SQLSyncIncrementalWatermark` and `Get-SQLSyncExtractQuery` (first step of splitting up the main script; the extract is now unit-tested); 176 Pester tests

### v2.17 (2026-10-09) - Rollout Check (`-PreDeploy`)
- `Test-SQLSyncConnections.ps1` v2.1: new switch `-PreDeploy`, read-only (only `SELECT` statements). Checks all `config*.json` in the script folder against schema and naming rules, the driver DLL against the allowed SHA-256 values (without loading it), the Firebird server version against known server advisories, a login as `SYSDBA`, and legacy target columns whose `DECIMAL` type truncates source values. Output as a table status/check/detail; exit code 6 if at least one `FEHLER` was found (`WARNUNG` keeps exit code 0)
- New module functions `Get-FirebirdServerAdvisory`, `Find-SQLSyncDecimalTruncation` and `Test-FirebirdDriverIntegrity` (status `OK` / `FEHLER` / `FEHLT`, does not load the DLL)
- Driver constants (version, download URL, allowed hashes) are now kept in one place (`$script:FirebirdDriver`); `Initialize-FirebirdDriver` and `Test-FirebirdDriverIntegrity` share the candidate search. Known Firebird server CVEs are kept in `$script:FirebirdServerAdvisories`
- `Test-SQLSyncConnections.ps1` no longer prints the test query line twice
- `Sync_Firebird_MSSQL_AutoSchema.ps1` unchanged (2.16); 157 Pester tests

### v2.16 (2026-10-09) - Driver Integrity Check
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.16: passes `Firebird.DllSha256` to the driver check
- `Initialize-FirebirdDriver` checks **every** DLL by SHA-256 before `Add-Type`: fresh download, DLL already present in `%ProgramData%\SQLSync\Drivers\...` and DLL configured via `Firebird.DllPath` (previously only the download). Accepted: original hashes of `lib\net8.0` and `lib\netstandard2.1` from the NuGet package 10.3.4. Mismatch → `SHA-256 der Treiber-DLL (vorhanden|Download) stimmt nicht ... Treiber wurde NICHT geladen`, sync exit code 7 (`Test-SQLSyncConnections.ps1` 4, `Get_Firebird_Schema.ps1` and `Manage_Config_Tables.ps1` 3); a mismatching download folder is discarded
- New optional config key `Firebird.DllSha256` (schema `^[A-Fa-f0-9]{64}$`) / parameter `-ExpectedSha256` for a different driver DLL; then only this hash is accepted. All four scripts pass it through
- `ServicePointManager.SecurityProtocol` is only changed for the download and restored afterwards
- Admin check is now the module function `Test-SQLSyncIsAdministrator` (not exported), so the download/hash path is unit-tested (138 Pester tests)
- Limitation: if the assembly is already loaded in the session (e.g. by another module), it is reused without a check
- Security note: Firebird server CVE-2026-40342 (CVSS 9.9, < 5.0.4 / < 4.0.7 / < 3.0.14) - use a read-only Firebird account instead of `SYSDBA` and update the server

### v2.15 (2026-10-09) - Schema Validation Active
- `Get-SQLSyncConfig -SchemaPath` now validates fail-fast against `config.schema.json` (`Test-Json -Schema`, available in all PowerShell 7 versions): error `Konfiguration verletzt das Schema (config.schema.json): …` with the JSON path of each violation; unknown keys (typos) are detected. If the schema file is missing, only a warning is shown
- All four scripts pass `-SchemaPath`; a violation ends them with exit code 2 before any database connection (`Manage_Config_Tables.ps1` also before GridView and backup)
- New module function `Resolve-SQLSyncConfigPath` replaces the copied `-ConfigFile` resolution in the sync and test scripts
- `Get_Firebird_Schema.ps1` and `Manage_Config_Tables.ps1` have a new `-ConfigFile` parameter (previously fixed to `config.json`). `Manage_Config_Tables.ps1` v2.1 validates via `Get-SQLSyncConfig` on start and refuses to remove the last table (exit 4)
- `config.schema.json`: name patterns aligned with the identifier whitelist (`Tables`, `IdColumn`, `TimestampColumns`, override columns `^[A-Za-z0-9_$]+$`, max. 63; Prefix/Suffix `^[A-Za-z0-9_$]*$`)
- **Existing installations:** deploy `config.schema.json` and check every productive config before the update: `Test-Json -Json (Get-Content <cfg> -Raw) -Schema (Get-Content config.schema.json -Raw)`

### v2.14 (2026-10-08) - Precision/Scale for DECIMAL
- `ConvertTo-SqlServerType` has new parameters `-Precision`/`-Scale` (values `NumericPrecision`/`NumericScale` from `GetSchemaTable`, DBNull allowed): `Decimal` becomes `DECIMAL(p,s)`; precision > 38 is capped at 38; precision missing but scale known → `DECIMAL(38,s)`; both missing → previous fallback `DECIMAL(18,4)`. Other types unchanged
- `Sync_Firebird_MSSQL_AutoSchema.ps1`: the duplicated inline type mapping and inline column/strategy detection were removed; the parallel block imports the module and uses `ConvertTo-SqlServerType` (now also `Guid` → `UNIQUEIDENTIFIER`) and `Get-TableColumnConfig`. Strategy selection is unchanged
- `Get_Firebird_Schema.ps1`: output has new columns `Precision`/`Scale`; the type proposal takes them into account
- **Existing installations:** the sync never alters existing tables. Target tables created with v2.13 or older keep `DECIMAL(18,4)` and keep rounding values with more than 4 decimal places, even when the staging table is recreated. Check affected columns (`Get_Firebird_Schema.ps1 -TableName <table>`) and fix them with `ALTER TABLE ... ALTER COLUMN ... DECIMAL(p,s)` or by dropping the target table and running once with `RecreateStagingTable: true` + `ForceFullSync: true`

### v2.13 (2026-10-08) - Parameterized Task Setup
- `Setup-ScheduledTasks.ps1` no longer contains hard-coded paths or config names: new parameters `-InstallDir` (default: folder of the script), `-DailyConfigFile` (`config.json`), `-WeeklyConfigFile` (`config_weekly_full.json`), task names, schedule (`-DailyStart`, `-DailyDays`, `-DailyIntervalMinutes`, `-DailyDurationHours`, `-WeeklyDay`, `-WeeklyStart`) and account (`-RunAsUser`)
- `-WhatIf` computes and outputs the task definitions without admin rights, password prompt or registration; output is one object per task (`TaskName`, `Action`, `Trigger`, `Settings`, `Principal`, `Registered`)
- New option `-GmsaAccount` (`DOMAIN\name$`): tasks run as a gMSA without a stored password
- Admin check at runtime (exit 1) instead of `#Requires -RunAsAdministrator`; cancelled password prompt exits with 1
- **Existing installations:** pass `-InstallDir`, `-DailyConfigFile` and `-WeeklyConfigFile` explicitly when re-creating the tasks; already registered tasks are not affected

### v2.12 (2026-10-08) - SQL Identifier Hardening
- New module function `Assert-SqlIdentifier`: table/column names, `MSSQL.Database`, Prefix/Suffix and `TableOverrides` are checked against `^[A-Za-z0-9_$]+$` (max. 63 characters) when the configuration is loaded; target table name max. 128 characters; violations exit with 2
- All SQL Server table names are bracket-quoted; metadata queries (`INFORMATION_SCHEMA`, `sys.indexes`) use parameters; `sp_Merge_Generic` is called as a stored procedure with parameters
- `Manage_Config_Tables.ps1` validates `IdColumn`/`TimestampColumns` (exit 2) and skips Firebird tables with invalid names

### v2.11 (2026-10-08) - Exit Codes
- Sync now exits with 10 (table failed) or 11 (sanity `FEHLER`) instead of always 0
- Errors while installing `sql_server_setup.sql` abort the pre-flight (exit 9) instead of only warning
- New option `General.FailOnSanityError` (default `true`)
- New options `Firebird.CredentialTarget` / `MSSQL.CredentialTarget` (Credential Manager entry name, defaults `SQLSync_Firebird` / `SQLSync_MSSQL`); `Setup_Credentials.ps1` gains `-FirebirdTarget` / `-MSSQLTarget`

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

- **New:** `Setup-ScheduledTasks.ps1` for automatic Windows Task Scheduler setup.

### v2.5 (2025-11-29) - Prefix/Suffix & Fixes

- **Feature:** `MSSQL.Prefix` and `MSSQL.Suffix` implemented.

### v2.1 (2025-11-25) - Secure Credentials

- Windows Credential Manager integration.

---

<a id="-disclaimer"></a>

## ⚖ Disclaimer

**Firebird is a registered trademark of the Firebird Foundation.**
This tool is open-source software and is **not** affiliated with, endorsed by, or associated with the Firebird Foundation.
