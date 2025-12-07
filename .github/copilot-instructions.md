## Purpose

This file gives concise, actionable guidance for AI coding agents to become productive in the PSFirebirdToMSSQL repository.

## High-level architecture (what to know)

- **ETL Runner:** `Sync_Firebird_MSSQL_AutoSchema.ps1` is the main entry point. It loads `SQLSyncCommon.psm1`, reads `config.json` and performs Extract -> Staging -> Merge.
- **Shared module:** `SQLSyncCommon.psm1` contains the reusable functions (credential resolution, config loading/validation, driver initialization, type mapping, connection helpers). Never remove or rename exported functions without updating call sites.
- **Staging & Merge:** Data flows Firebird -> `STG_<SourceTable>` (staging) -> target table (prefix/suffix applied). The merge is done by `sp_Merge_Generic` (installed from `sql_server_setup.sql`).
- **Credential Management:** Credentials are stored in Windows Credential Manager (`SQLSync_Firebird`, `SQLSync_MSSQL`) and resolved by `Get-StoredCredential` / `Resolve-*` helpers.

## Developer workflows & important commands

- Run a normal sync (default `config.json`):

  `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Sync_Firebird_MSSQL_AutoSchema.ps1`

- Run with a specific config file: `-ConfigFile "config_weekly_full.json"`.
- Test connections & environment: `.\Test-SQLSyncConnections.ps1` (uses `SQLSyncCommon.psm1`).
- Store credentials: `.\Setup_Credentials.ps1` (stores entries under `SQLSync_Firebird` and `SQLSync_MSSQL`).
- Setup scheduled tasks (admin): run `.\Setup-ScheduledTasks.ps1` as Administrator.
- Examine a table's mapping from Firebird to SQL: `.\Get_Firebird_Schema.ps1 -TableName "MYTABLE"`.
- Manage configured tables via GUI toggle: `.\Manage_Config_Tables.ps1` (uses Out-GridView to add/remove table names in `config.json`).

## Project-specific conventions & patterns

- PowerShell 7+ required. Scripts use `ForEach-Object -Parallel` (throttled via `-ThrottleLimit 4` in the main script).
- `SQLSyncCommon.psm1` must live in the same directory as the scripts and is imported with `Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force`.
- Config is JSON (`config.json`) and validated optionally by `config.schema.json`. Tables are uppercase names (e.g. `BKUNDE`).
- Staging table naming: `STG_<SourceTable>`; target naming uses `MSSQL.Prefix` + `<SourceTable>` + `MSSQL.Suffix`.
- Deletion/cleanup: Default is to not delete source deletions. To remove orphans enable `CleanupOrphans` or run `ForceFullSync` (truncate + reload).

## Integration points & external deps

- Firebird .NET provider: `FirebirdSql.Data.FirebirdClient` (installed via `Install-Package` if missing). `Initialize-FirebirdDriver` resolves DLL path and loads the provider via `Add-Type`.
- SQL Server: scripts require privileges to create DBs (`db_creator`) if the target DB doesn't exist; `sp_Merge_Generic` is created from `sql_server_setup.sql` during pre-flight.
- Windows-specific: uses `cmdkey` and native advapi32 credential APIs (C# `Add-Type`) — cross-platform changes must maintain these behaviors or provide alternatives.

## Code patterns for agents to preserve

- Do not change exported function names in `SQLSyncCommon.psm1` (`Get-StoredCredential`, `Get-SQLSyncConfig`, `Resolve-FirebirdCredentials`, `Resolve-MSSQLCredentials`, `Initialize-FirebirdDriver`, `New-FirebirdConnectionString`, `New-MSSQLConnectionString`, `Close-DatabaseConnection`, `ConvertTo-SqlServerType`, etc.).
- Connection handling uses try/finally and explicit Close/Dispose — preserve guaranteed cleanup and avoid introducing resource leaks.
- Bulk-loading uses `System.Data.SqlClient.SqlBulkCopy`. Keep column mapping behavior and staging-table truncate semantics.
- Schema and SQL file handling: the main script strips comments and splits on `GO` before executing `sql_server_setup.sql` batches — keep this approach when editing SQL-install logic.

## Quick checks an agent should run after changes

- Run `.\Test-SQLSyncConnections.ps1` to validate connectivity and stored-procedure presence.
- Run a single-table sync using a small `config.json` (1 table) to validate end-to-end flow. Use `Logs\` to inspect transcript output.

## Notable repo quirks / possible sources of confusion

- `Example_Sync_Start.ps1` references `Sync_Firebird_MSSQL_Prod.ps1` — the current main script is `Sync_Firebird_MSSQL_AutoSchema.ps1`. Prefer the AutoSchema script for development and ensure examples/path references stay consistent.
- `SQLSyncCommon.psm1` contains embedded C# via `Add-Type` to read Windows credentials — edits here need careful C#/PowerShell integration testing.
- Config schema `config.schema.json` is present; prefer using it when modifying config shape.

## When to ask the maintainers

- If you need to change any public function signature in `SQLSyncCommon.psm1`.
- If you must alter credential storage or migration away from Windows Credential Manager.
- If you change staging/merge semantics (naming, PK creation, or `sp_Merge_Generic` parameters).

---

If you want, I can now: (a) commit this file, (b) update `Example_Sync_Start.ps1` to call the canonical script, or (c) generate short unit/integration checks to run locally. Which should I do next?
