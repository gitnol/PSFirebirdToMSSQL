# Deployment – PSFirebirdToMSSQL

Kopier-Deployment: Es gibt keinen Build, kein Paket und keine CI. Die Skripte
werden als Dateien in ein Zielverzeichnis auf dem Sync-Host kopiert.

Verbindet sich mit `operations/SETUP.md` (Erst-Setup), `operations/RUNBOOK.md`
(Betrieb), `operations/TASK_SCHEDULER.md` und `operations/SECRETS_MANAGEMENT.md`.

---

## Umgebungen

| Umgebung | Zweck | Datenquelle | Wer darf deployen |
|---|---|---|---|
| dev | Entwicklung im Git-Arbeitsverzeichnis, manuelle Läufe | Firebird-Test-/Demo-DB → eigene Staging-DB | Entwickler:in |
| prod | Sync-Host mit Scheduled Tasks | produktive Firebird-DB → produktive Staging-DB | Betreiber:in des Sync-Hosts (Adminrechte) |

Eine eigene staging/UAT-Umgebung ist nicht definiert (offen). Unterschiede
zwischen Umgebungen ausschließlich über Konfigdateien (Server, Datenbank,
`Prefix`/`Suffix`, `Tables`), siehe `architecture/CONFIGURATION.md`. Für einen
Test gegen dieselbe SQL-Instanz eine andere `MSSQL.Database` oder einen
anderen `Prefix` verwenden, damit produktive Zieltabellen nicht berührt werden.

---

## Zielverzeichnis

Beispielpfad (frei wählbar; `Setup-ScheduledTasks.ps1 -InstallDir`, Default: Ordner des Skripts):

```
D:\Apps\SQLSync\
    Sync_Firebird_MSSQL_AutoSchema.ps1
    SQLSyncCommon.psm1
    sql_server_setup.sql
    Setup_Credentials.ps1, Test-SQLSyncConnections.ps1, Get_Firebird_Schema.ps1,
    Manage_Config_Tables.ps1, Setup-ScheduledTasks.ps1, Example_Sync_Start.ps1
    config.schema.json, config.sample.json
    config_<Profil>.json           (lokal, nie im Repo)
    Logs\                          (wird automatisch angelegt)
```

Außerhalb des Zielverzeichnisses (nicht Teil des Deployments, bleiben bei
Updates erhalten):

- Treiber: `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\`
- Credentials: Windows Credential Manager des Task-Kontos (`SQLSync_Firebird`, `SQLSync_MSSQL`)
- Scheduled Tasks: `SQLSync_Firebird_Daily_Diff`, `SQLSync_Firebird_Weekly_Full`
- In SQL Server: `dbo.sp_Merge_Generic`, `STG_*`- und Zieltabellen

Rechte: Schreibzugriff auf das Zielverzeichnis und `%ProgramData%\SQLSync`
nur für Administratoren und das Task-Konto (das Konto braucht Schreibrecht auf
`Logs\`). Wer dort schreiben darf, kann Code im Kontext des Sync-Kontos
ausführen (S4).

---

## Build

Kein Build-Schritt. Artefakt = die versionierten Dateien eines Git-Commits
bzw. Tags. Lock-Files gibt es nicht; die einzige externe Abhängigkeit (Treiber
10.3.4) ist im Code per Version und SHA-256 festgenagelt
(`SQLSyncCommon.psm1`, `Initialize-FirebirdDriver`).

Vor dem Deployment (manuell, keine CI vorhanden):

```powershell
# Syntax aller Skripte prüfen
Get-ChildItem *.ps1, *.psm1 | ForEach-Object {
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
    if ($e) { $_.Name; $e }
}
# Optional, falls installiert
Invoke-ScriptAnalyzer -Path . -Recurse
```

Unit-Tests für `SQLSyncCommon.psm1` (auf dem Entwicklungsrechner, nicht auf dem Betriebsserver):
`pwsh -NoProfile -File .\tests\pester.config.ps1` → Exit 0. Automatisierte Tests für die
Einstiegsskripte und eine CI gibt es nicht.

---

## Update-Ablauf (prod)

| Schritt | Aktion | Verifikation |
|---|---|---|
| 1. Version festhalten | Aktuellen Stand notieren: `git -C <Repo> log -1 --oneline` bzw. Tag (z. B. `git tag v2.10`) | Commit-Hash im Änderungsprotokoll |
| 2. Sicherung | Zielverzeichnis ohne `Logs\` sichern, z. B. `Compress-Archive -Path D:\Apps\SQLSync\*.ps*, D:\Apps\SQLSync\*.sql, D:\Apps\SQLSync\*.json -DestinationPath D:\Backup\SQLSync_<Datum>.zip` (enthält Konfigs – Archiv wie Secrets behandeln) | Archiv vorhanden |
| 3. Läufe pausieren | `Disable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full`; laufende Instanz abwarten (`Get-ScheduledTask ... State`) | State `Disabled`, keine `pwsh`-Sync-Prozesse |
| 4. Dateien ersetzen | Skripte, Modul, `sql_server_setup.sql`, `config.schema.json`, `config.sample.json` überschreiben. **Eigene `config_*.json` nicht überschreiben.** | Datei-Zeitstempel |
| 5. Konfig abgleichen | `config.sample.json` mit eigenen Konfigs vergleichen; neue Schlüssel haben Defaults in `Get-SQLSyncConfig`, müssen also nur bei Abweichung ergänzt werden | – |
| 6. Stored Procedure | Automatisch: Pre-Flight installiert `sp_Merge_Generic` neu, wenn sie fehlt oder nicht 4 Parameter hat. Hat sich `sql_server_setup.sql` geändert, die Parameteranzahl aber nicht → einmal mit `RecreateStoredProcedure: true` laufen lassen (Einmal-Konfig, `operations/RUNBOOK.md`) | Log: `INSTALLIERT:` bzw. `OK: ... ist aktuell (4 Parameter)`; kein `PRE-FLIGHT CHECK (PROCEDURE) FAILED` (ein fehlgeschlagener SQL-Batch bricht seit v2.11 mit Exit 9 ab) |
| 7. Schema-Änderung im Code | Wenn sich Typmapping/Staging-Aufbau geändert hat: einmal mit `RecreateStagingTable: true` laufen lassen. Zieltabellen werden nie automatisch geändert (S11) | Zusammenfassung |
| 8. Testlauf | `.\Test-SQLSyncConnections.ps1 -ConfigFile <Profil>`; danach manueller Sync-Lauf mit dem Daily-Profil | Beide Exit 0 (Sync: Zeile `ERGEBNIS: OK (Exit-Code 0)`); alle Tabellen `Erfolg`, Sanity `OK` |
| 9. Läufe aktivieren | `Enable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full` | nächster geplanter Lauf im Log prüfen |

Treiber-Update: Version und SHA-256 stehen in `Initialize-FirebirdDriver`.
Nach Code-Update auf eine neue Treiberversion lädt der erste Lauf **als
Administrator** den neuen Treiber in einen neuen Versionsordner (sonst exit 7).
Da `.ps1`-Dateien aus `git clone` oder Download kommen können:
`Get-ChildItem D:\Apps\SQLSync -Filter *.ps* | Unblock-File`.

---

## Rollback

**Bedingung:** Nach dem Update schlagen Tabellen fehl, die vorher liefen, oder
Pre-Flight/Treiber brechen ab, und ein Fix ist nicht am selben Tag möglich.

| Schritt | Befehl / Aktion |
|---|---|
| 1. Letzte stabile Version identifizieren | `git log --oneline` / `git tag` im Repo; oder Sicherungsarchiv aus Schritt 2 |
| 2. Läufe pausieren | `Disable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full` |
| 3. Dateien zurückspielen | `git checkout <hash-oder-tag> -- Sync_Firebird_MSSQL_AutoSchema.ps1 SQLSyncCommon.psm1 sql_server_setup.sql` und ins Zielverzeichnis kopieren, oder `Expand-Archive <Sicherung>.zip -DestinationPath D:\Apps\SQLSync -Force` |
| 4. Stored Procedure zurück | Einmal-Konfig mit `RecreateStoredProcedure: true` (installiert die SP aus der zurückgespielten `sql_server_setup.sql`) |
| 5. Verifikation | `Test-SQLSyncConnections.ps1`, manueller Lauf, Zusammenfassung prüfen; Tasks wieder aktivieren |

Datenstand: Der Sync hat keine Migrationen im eigentlichen Sinn. Staging-
Tabellen sind Wegwerf-Strukturen (`RecreateStagingTable`), Zieltabellen werden
nur angelegt, nie strukturell geändert. Wurde durch eine fehlerhafte Version
Inhalt falsch geschrieben, mit `ForceFullSync: true` aus Firebird neu laden
(Firebird ist die führende Quelle). Abhängige Views/Rechte auf Zieltabellen
bleiben dabei erhalten (TRUNCATE + MERGE statt DROP).

---

## Post-Deploy-Verifikation

- [ ] `Test-SQLSyncConnections.ps1` → Exit 0
- [ ] Manueller Lauf: Log enthält `ZUSAMMENFASSUNG`, alle Tabellen `Erfolg`, Sanity `OK`
- [ ] Keine `PRE-FLIGHT CHECK`-Fehlermeldung, keine `KRITISCH:`-Zeile; Zeile `ERGEBNIS: OK (Exit-Code 0)`
- [ ] Laufzeit (`GESAMTLAUFZEIT`) im üblichen Rahmen, d. h. Daily-Diff-Lauf deutlich unter 30 Minuten
- [ ] Nächster geplanter Lauf erzeugt Log und gleiche Ergebnisse
- [ ] `LastTaskResult` des nächsten geplanten Laufs `0x0` (`0xA`/`0xB` = Tabellen-/Sanity-Fehler, `operations/MONITORING.md`); Sanity `WARNUNG` zusätzlich im Log prüfen
- [ ] Beim Update auf Sync v2.11: Neuer Schlüssel `General.FailOnSanityError` (Default `true`) – bewusst entscheiden, ob Sanity `FEHLER` den Task als fehlgeschlagen melden soll
- [ ] Beim Update von `Setup-ScheduledTasks.ps1` (parametrisierte Fassung): bestehende Tasks bleiben unverändert. Erst beim Neuanlegen `-InstallDir`, `-DailyConfigFile` und `-WeeklyConfigFile` explizit übergeben und vorher mit `-WhatIf` prüfen – die Defaults (Skriptordner, `config.json`, `config_weekly_full.json`) entsprechen nicht den früher fest eingetragenen Namen

---

## Pflege

Trigger: neues Zielverzeichnis / geänderter Task-Pfad / neue Treiberversion /
neue Konfigschlüssel / geänderter Rollback-Pfad → hier und in
`operations/TASK_SCHEDULER.md` eintragen.
