$ScriptDir = $PSScriptRoot

# Execute the synchronization script with the specified configuration files
& (Join-Path $ScriptDir "Sync_Firebird_MSSQL_AutoSchema.ps1") -ConfigFile "config.json"

# Weekly full sync with recreation of staging table and then merging everything to the production table
& (Join-Path $ScriptDir "Sync_Firebird_MSSQL_AutoSchema.ps1") -ConfigFile "config_weekly_full.json"

