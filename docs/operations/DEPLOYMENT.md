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
    config.schema.json             (Pflicht: Schema-Prüfung beim Laden; fehlt sie → nur Warnung)
    config.sample.json
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
`Logs\`). Wer in den Skriptordner schreiben darf, kann Code im Kontext des
Sync-Kontos ausführen. Eine ausgetauschte Treiber-DLL in `%ProgramData%` oder
hinter `DllPath` wird seit I7 per SHA-256 erkannt und nicht geladen (Exit 7);
die Rechte bleiben trotzdem die erste Schutzschicht (Prüfung per `icacls`,
`operations/SETUP.md` Schritt 4).

---

## Build

Kein Build-Schritt. Artefakt = die versionierten Dateien eines Git-Commits
bzw. Tags. Lock-Files gibt es nicht; die einzige externe Abhängigkeit (Treiber
10.3.4) ist im Code per Version, Download-URL und den SHA-256-Werten beider
Original-DLLs (`lib\net8.0`, `lib\netstandard2.1`) festgenagelt
(`SQLSyncCommon.psm1`, zentral in `$script:FirebirdDriver`); geprüft wird bei jedem Laden.

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

### Vor-Deployment-Prüfung (`-PreDeploy`)

Zentraler Prüfschritt vor jedem Erst- oder Update-Deployment, im Zielverzeichnis
und mit dem Konto, unter dem der Sync läuft:

```powershell
.\Test-SQLSyncConnections.ps1 -ConfigFile <Profil> -PreDeploy
```

Der Schalter ist rein lesend (nur `SELECT`s, keine DDL/DML) und ersetzt die
früheren Einzelschritte (`Test-Json` je Konfig, Hash-Vergleich der DLL,
Versionsabgleich, `INFORMATION_SCHEMA`-Suche nach Altbestand). Zusätzlich zum
normalen Verbindungstest prüft er:

| Prüfung | Ergebnis |
|---|---|
| Alle `config*.json` im Skriptordner (außer `config.schema.json`, `config.sample.json`) gegen Schema und Namensregeln | `OK` / `FEHLER`; fehlende `config.schema.json` → `WARNUNG` |
| Treiber-DLL gegen die erlaubten SHA-256 (`Test-FirebirdDriverIntegrity`, lädt nicht) | `OK` / `FEHLER`; keine DLL vorhanden → `WARNUNG`. Bei `FEHLER` sofortige Ausgabe und Exit 6 |
| Firebird-Serverversion gegen bekannte Server-Advisories (`Get-FirebirdServerAdvisory`) | `WARNUNG` je betroffener CVE; nicht auswertbare Version → Hinweis zur manuellen Prüfung |
| Anmeldung als `SYSDBA` | `WARNUNG` mit Empfehlung eines reinen Lesekontos |
| Altbestand: Dezimalspalten der konfigurierten Tabellen (Firebird-Metadaten) gegen die Zieltabellen (`Find-SQLSyncDecimalTruncation`) | `WARNUNG` je Zielspalte mit kleinerer Precision oder Scale als die Quelle, mit Ziel- und Quelltyp |
| Schema-Drift (seit v2.19): Spalten der konfigurierten Tabellen (`RDB$RELATION_FIELDS`) gegen vorhandene Ziel- und Staging-Tabellen (`INFORMATION_SCHEMA.COLUMNS`, `Find-SQLSyncSchemaDrift`); nicht vorhandene Tabellen werden übersprungen | `FEHLER`: ID-Spalte fehlt im Ziel, Zeitstempelspalte einer Incremental-Tabelle fehlt im Ziel (bei `ForceFullSync: true` nur `WARNUNG`), Quellspalte fehlt in `STG_<Tabelle>` (nicht bei `RecreateStagingTable: true`); `WARNUNG`: andere Quellspalte fehlt im Ziel (K6); sonst `OK` mit Anzahl geprüfter Spalten |
| Klartext-Passwörter je `config*.json` (`Find-SQLSyncPlaintextPassword`, seit v2.19) | `WARNUNG` mit den gesetzten Schlüsseln (`Firebird.Password`, `MSSQL.Password`), nie mit Werten |
| Konfig-Backups `<Konfig>.<yyyyMMdd_HHmmss>.bak` im Skriptordner (`Get-SQLSyncConfigBackup`, seit v2.19) | `WARNUNG` mit Anzahl und bis zu drei Dateinamen (können Klartext-Passwörter enthalten); keine → `OK` |

Ausgabe als Tabelle Status / Prüfung / Detail. **Exit 6 (mindestens ein
`FEHLER`) blockiert das Deployment**: erst die Ursache beheben
(`operations/RUNBOOK.md`), dann erneut prüfen. Exit 1 = ein Verbindungstest ist
fehlgeschlagen. Exit 0 mit `WARNUNG`en ist zulässig; jede Warnung wird bewusst
bewertet (Altbestand: `operations/RUNBOOK.md`, „Nachkommastellen im Ziel
gerundet“; CVE: Firebird-Server aktualisieren, `security/DEPENDENCY_AUDIT.md`;
Schema-Drift, Klartext-Passwort, Konfig-Backups: `operations/RUNBOOK.md`, „Befund
‚Schema-Drift‘ aus `-PreDeploy` beheben“ bzw. „Klartext-Passwort oder Konfig-Backups gemeldet“).

---

## Update-Ablauf (prod)

| Schritt | Aktion | Verifikation |
|---|---|---|
| 1. Version festhalten | Aktuellen Stand notieren: `git -C <Repo> log -1 --oneline` bzw. Tag (z. B. `git tag v2.10`) | Commit-Hash im Änderungsprotokoll |
| 2. Sicherung | Zielverzeichnis ohne `Logs\` sichern, z. B. `Compress-Archive -Path D:\Apps\SQLSync\*.ps*, D:\Apps\SQLSync\*.sql, D:\Apps\SQLSync\*.json -DestinationPath D:\Backup\SQLSync_<Datum>.zip` (enthält Konfigs – Archiv wie Secrets behandeln) | Archiv vorhanden |
| 3. Läufe pausieren | `Disable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full`; laufende Instanz abwarten (`Get-ScheduledTask ... State`) | State `Disabled`, keine `pwsh`-Sync-Prozesse |
| 4. Dateien ersetzen | Skripte, Modul, `sql_server_setup.sql`, `config.schema.json`, `config.sample.json` überschreiben. **Eigene `config_*.json` nicht überschreiben.** | Datei-Zeitstempel |
| 5. Konfig abgleichen | `config.sample.json` mit eigenen Konfigs vergleichen; neue Schlüssel haben Defaults in `Get-SQLSyncConfig`, müssen also nur bei Abweichung ergänzt werden. Danach die Vor-Deployment-Prüfung: `.\Test-SQLSyncConnections.ps1 -ConfigFile <Profil> -PreDeploy` (prüft alle Konfigs im Ordner gegen das neue Schema, Treiber-DLL, Serverversion, Konto und Altbestand, seit v2.19 auch Schema-Drift, Klartext-Passwörter und Konfig-Backups; seit v2.15 bricht ein Schemaverstoß den Sync mit Exit 2 ab) | Exit 0, alle Konfigs `OK`; bei Exit 6 die `FEHLER`-Zeilen beheben (z. B. `operations/RUNBOOK.md`, „Konfiguration verletzt das Schema“), **bevor** die Tasks wieder aktiviert werden; `WARNUNG`en bewerten |
| 6. Stored Procedure | Automatisch: Pre-Flight installiert `sp_Merge_Generic` neu, wenn sie fehlt oder nicht 4 Parameter hat. Hat sich `sql_server_setup.sql` geändert, die Parameteranzahl aber nicht → einmal mit `RecreateStoredProcedure: true` laufen lassen (Einmal-Konfig, `operations/RUNBOOK.md`) | Log: `INSTALLIERT:` bzw. `OK: ... ist aktuell (4 Parameter)`; kein `PRE-FLIGHT CHECK (PROCEDURE) FAILED` (ein fehlgeschlagener SQL-Batch bricht seit v2.11 mit Exit 9 ab) |
| 7. Schema-Änderung im Code | Wenn sich Typmapping/Staging-Aufbau geändert hat: einmal mit `RecreateStagingTable: true` laufen lassen. Zieltabellen werden nie automatisch geändert (S11) | Zusammenfassung |
| 8. Testlauf | `.\Test-SQLSyncConnections.ps1 -ConfigFile <Profil> -PreDeploy` (falls seit Schritt 5 etwas geändert wurde); danach manueller Sync-Lauf mit dem Daily-Profil | Beide Exit 0 (Sync: Zeile `ERGEBNIS: OK (Exit-Code 0)`); alle Tabellen `Erfolg`, Sanity `OK` |
| 9. Läufe aktivieren | `Enable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full` | nächster geplanter Lauf im Log prüfen |

Treiber-Update: Version, Download-URL und beide SHA-256-Werte stehen zentral in
`$script:FirebirdDriver` (`SQLSyncCommon.psm1`) und werden gemeinsam geändert
(`CONVENTIONS.md` 6); `Initialize-FirebirdDriver` und `Test-FirebirdDriverIntegrity`
lesen beide von dort.
Nur eine DLL tauschen, ohne den Code zu ändern, geht ausschließlich mit
`Firebird.DllSha256` (Hash selbst aus dem offiziellen Paket berechnen).
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

- [ ] `Test-SQLSyncConnections.ps1 -ConfigFile <Profil> -PreDeploy` → Exit 0 (kein `FEHLER`), verbleibende `WARNUNG`en bewertet
- [ ] Manueller Lauf: Log enthält `ZUSAMMENFASSUNG`, alle Tabellen `Erfolg`, Sanity `OK`
- [ ] Keine `PRE-FLIGHT CHECK`-Fehlermeldung, keine `KRITISCH:`-Zeile; Zeile `ERGEBNIS: OK (Exit-Code 0)`
- [ ] Laufzeit (`GESAMTLAUFZEIT`) im üblichen Rahmen, d. h. Daily-Diff-Lauf deutlich unter 30 Minuten
- [ ] Nächster geplanter Lauf erzeugt Log und gleiche Ergebnisse
- [ ] `LastTaskResult` des nächsten geplanten Laufs `0x0` (`0xA`/`0xB` = Tabellen-/Sanity-Fehler, `operations/MONITORING.md`); Sanity `WARNUNG` zusätzlich im Log prüfen
- [ ] Beim Update auf Sync v2.11: Neuer Schlüssel `General.FailOnSanityError` (Default `true`) – bewusst entscheiden, ob Sanity `FEHLER` den Task als fehlgeschlagen melden soll
- [ ] Beim Update von `Setup-ScheduledTasks.ps1` (parametrisierte Fassung): bestehende Tasks bleiben unverändert. Erst beim Neuanlegen `-InstallDir`, `-DailyConfigFile` und `-WeeklyConfigFile` explizit übergeben und vorher mit `-WhatIf` prüfen – die Defaults (Skriptordner, `config.json`, `config_weekly_full.json`) entsprechen nicht den früher fest eingetragenen Namen
- [ ] Beim Update auf v2.19 (`Test-SQLSyncConnections.ps1` und `Manage_Config_Tables.ps1` 2.2, Sync unverändert 2.18): `-PreDeploy` kann bei bestehenden Installationen erstmals `FEHLER` „Schema-Drift“ melden (Exit 6) – vorhandene Ziel-/Staging-Tabellen, denen Quellspalten fehlen, die der Sync bisher still ignoriert hat oder an denen er scheitert; beheben nach `operations/RUNBOOK.md`. `Manage_Config_Tables.ps1` löscht beim nächsten Speichern ältere Backups über die neuesten 5 hinaus (`-KeepBackups`)
- [ ] Beim Update auf Sync v2.18: Ohne Konfigänderung gilt das Überlappungsfenster `General.IncrementalOverlapMinutes` = 10 Minuten. Erwartet im ersten Lauf: `RowsLoaded` (Spalte Sync) bei Incremental-Tabellen auch ohne Quelländerung oft > 0 (Zeilen im Fenster werden erneut gelesen, MERGE idempotent) – Monitoring-Schwellen auf „0 geladene Zeilen“ anpassen. Incremental-Tabellen, deren vorhandene Zieltabelle die Zeitstempelspalte nicht hat, enden jetzt mit `Fehler` (Exit 10) statt still voll zu laden (`operations/RUNBOOK.md`, „Zeitstempelspalte fehlt in der Zieltabelle“). Wer den Schlüssel setzt, muss die neue `config.schema.json` mit ausliefern, sonst Exit 2 (unbekannter Schlüssel)
- [ ] Beim Update auf Sync v2.15: `config.schema.json` liegt im Zielverzeichnis (fehlt sie, meldet der Lauf nur `Schema-Datei nicht gefunden …` und prüft ohne Schema). Vorher alle produktiven Konfigs mit `-PreDeploy` prüfen (Update-Schritt 5): unbekannte Schlüssel (Tippfehler), Werte als String statt Zahl/Bool oder Werte außerhalb der Schema-Grenzen (z. B. `GlobalTimeout` < 60) führen sonst zu Exit 2. `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1` kennen jetzt `-ConfigFile`
- [ ] Beim Update auf Sync v2.14: Altbestand prüfen. Der Sync ändert keine bestehenden Tabellen – Zieltabellen aus v2.13 oder älter behalten `DECIMAL(18,4)` und runden Werte mit mehr als 4 Nachkommastellen weiter. Betroffene Spalten meldet `-PreDeploy` als `WARNUNG` „Altbestand DECIMAL“ mit Ziel- und Quelltyp; korrigieren (`operations/RUNBOOK.md`, „Nachkommastellen im Ziel gerundet“)

---

## Pflege

Trigger: neues Zielverzeichnis / geänderter Task-Pfad / neue Treiberversion /
neue Konfigschlüssel / geänderter Rollback-Pfad → hier und in
`operations/TASK_SCHEDULER.md` eintragen.
