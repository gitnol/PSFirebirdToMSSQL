## Purpose

Short, actionable guidance for AI coding agents in the PSFirebirdToMSSQL repository. The authoritative project
documentation lives in `docs/` — start with `docs/KICKOFF.md` (workflow), `docs/STATE.md` (current state) and
`docs/TODO.md` (next increment). If this file and `docs/` disagree, `docs/` and the code win.

## High-level architecture

- **ETL runner:** `Sync_Firebird_MSSQL_AutoSchema.ps1` is the main entry point. It loads `SQLSyncCommon.psm1`,
  validates the config (`-ConfigFile`, default `config.json`) and processes tables in parallel:
  Extract (Firebird) → `STG_<Table>` (SqlBulkCopy) → target table via `sp_Merge_Generic`.
- **Shared module:** `SQLSyncCommon.psm1` holds config loading/validation, credential resolution, driver
  initialization (SHA-256 checked), type mapping, watermark/extract helpers and the `-PreDeploy` checks.
  Overview: `docs/architecture/OVERVIEW.md`.
- **Merge:** `sp_Merge_Generic` (from `sql_server_setup.sql`, installed by the pre-flight check) merges by ID and
  never deletes; deletions only via `CleanupOrphans` or `ForceFullSync`.
- **Credentials:** Windows Credential Manager (targets `SQLSync_Firebird` / `SQLSync_MSSQL`, configurable via
  `*.CredentialTarget`); plain-text passwords in a config are only a fallback. See
  `docs/architecture/CREDENTIAL_STRATEGY.md`.

## Commands

- Sync: `pwsh -NoProfile -File .\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile <config>`
- Environment check: `.\Test-SQLSyncConnections.ps1 -ConfigFile <config>`; before every deployment add
  `-PreDeploy` (read-only; exit 6 on `FEHLER`).
- Unit tests (pinned Pester, coverage gate): `pwsh -NoProfile -File .\tests\pester.config.ps1`
- Static analysis (pinned PSScriptAnalyzer, fails on severity Error): `pwsh -NoProfile -File .\tests\scriptanalyzer.ps1`
- Both run in CI (`.github/workflows/ci.yml`) on push to `main`.
- Exit codes of all scripts: `docs/architecture/ERROR_HANDLING.md`.

## Conventions to preserve

- PowerShell 7+. The module is imported with `Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force`,
  also inside the `ForEach-Object -Parallel` block (throttle = `General.NumberOfThreads`).
- Do not rename exported functions of `SQLSyncCommon.psm1`.
- Identifiers from config or metadata must pass `Assert-SqlIdentifier` and are always quoted (`[...]` / `"..."`);
  values are passed as parameters.
- Connections are closed in `try/finally` with `Close()` and `Dispose()`.
- Every config is validated fail-fast against `config.schema.json`; new keys go into schema, sample and
  `docs/architecture/CONFIGURATION.md`.
- Never read, print or commit `config.json` / `config*.json` / `*.bak` (may contain passwords). Use
  `config.sample.json`.
- Public repository: no internal host names, paths or account names in committed files or commit messages
  (`docs/CONVENTIONS.md`).
- Tests that write to a database run only against a dedicated test database (the sync creates tables and
  truncates them).

## Ask the maintainers before

- changing a public function signature in `SQLSyncCommon.psm1`,
- changing credential storage,
- changing staging/merge semantics (naming, primary keys, `sp_Merge_Generic` parameters).
