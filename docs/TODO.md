# TODO – PSFirebirdToMSSQL

Pro Inkrement: Aufgaben **und** Definition of Done. Ein Inkrement gilt erst
als erledigt, wenn alle DoD-Kriterien erfüllt sind.

Parkplatz für noch unspezifizierte Ideen: `BACKLOG.md`.
Bekannte Bugs ohne aktiven Fix: `KNOWN_ISSUES.md`.

**Gemeinsame DoD (gilt zusätzlich für jedes Inkrement):**

- [ ] Code-Änderungen abgeschlossen, kein TODO-/FIXME-Kommentar offen
- [ ] Unit-Tests grün inkl. Coverage-Ziel: `pwsh -NoProfile -File ./tests/pester.config.ps1` (Exit 0); neue Logik mit behavioralem Rot, Charakterisierungstests mit Mutationsprüfung
- [ ] Integration-Smoke-Test grün, falls DB-Logik betroffen (`.\Test-SQLSyncConnections.ps1` + Ein-Tabellen-Sync gegen Test-DB, siehe `testing/INTEGRATION_TESTS.md`)
- [ ] Security-Checkliste aus `CONVENTIONS.md` durchgegangen
- [ ] Trigger-Matrix in `KICKOFF.md` Phase 3a geprüft → alle relevanten Docs aktualisiert
  (`OVERVIEW.md`, `features/`, `architecture/`, `security/`, `GLOSSARY.md`, `KNOWN_ISSUES.md`, `LESSONS_LEARNED.md`)
- [ ] `README.md` / `README.de.md` angepasst, falls Nutzerverhalten sich ändert
- [ ] `STATE.md`: Tabellenzeile + „Nächster Schritt"-Abschnitt aktualisiert
- [ ] `CHANGELOG.md`: neuer Abschnitt mit Datum + Inkrement-Titel + Sections
  (Added / Changed / Fixed / Removed / Security / Lessons Learned)
- [ ] Commit erstellt (`<type>(<scope>): <desc>`); Commit-Hash in `STATE.md` eingetragen

---

## Niedrige Priorität

### I10d: Modul-Aufräumen

Code-Teil der bisherigen I10a; nach I10c, damit die Doku-Änderungen auf konsolidierte Stellen treffen.
Gebündelt mit den PSScriptAnalyzer-Warnungen an denselben Funktionen.

- [ ] `MSSQL.Port` (K9): in `New-MSSQLConnectionString` verwenden (`Server,Port`) oder aus Sample/Schema entfernen
- [ ] Ungenutztes `Protect-SqlString` entfernen (seit I4 ohne Aufrufer); über `Write-SyncStatus`/`Close-DatabaseConnection` (von keinem Skript genutzt) entscheiden
- [ ] Warnungen an `New-FirebirdConnectionString`/`New-MSSQLConnectionString` abbauen oder begründet unterdrücken (`PSAvoidUsingPlainTextForPassword`, `PSUseShouldProcessForStateChangingFunctions`)
- **DoD:** Unit-Test mit behavioralem Rot für den Port; exportierte Funktionsnamen unverändert (außer entfernte); CI grün; gemeinsame DoD erfüllt

---
## Abgeschlossen

- I10c Doku-Konsolidierung: Exit-Codes nur noch in `architecture/ERROR_HANDLING.md` (plus Nutzer-Tabellen der READMEs), S-IDs durch K-IDs/Bedrohungsnummern ersetzt (historische Zuordnung in `THREAT_MODEL.md`), `.github/copilot-instructions.md` an Code und `docs/` angeglichen, `README_alternativ.md` entfernt — [ABGESCHLOSSEN 2026-10-10] (Commit 6d93b9b)
- I10a Rollout-Check-Erweiterung und Backup-Hygiene: `-PreDeploy` erkennt Schema-Drift Quelle → Ziel/Staging (ID-/Zeitstempelspalte und Staging `FEHLER`, sonst `WARNUNG`; K6-Erkennung), warnt bei Klartext-Passwort und `config*.bak`; `Manage_Config_Tables.ps1 -KeepBackups` rotiert Backups — [ABGESCHLOSSEN 2026-10-10] (Commit 1299c5e)
- I10b CI auf GitHub: `.github/workflows/ci.yml` (windows-latest; Push auf `main`, PRs, manuell) mit `tests/scriptanalyzer.ps1` (PSScriptAnalyzer 1.25.0, nur Severity `Error` blockiert) und `tests/pester.config.ps1`; Action per SHA gepinnt, `contents: read` — [ABGESCHLOSSEN 2026-10-09] (Commit f7423b3)
- I8 Wasserzeichen mit Überlappungsfenster: `General.IncrementalOverlapMinutes` (Default 10), Extrakt ab `MAX(ts) − Überlappung` inklusive, Wasserzeichen/Untergrenze/Abfrage als Modulfunktionen; kein stiller Vollabzug mehr (fehlende/leere Zieltabelle mit Hinweis, MAX-Fehler → Retry/Fehler) — [ABGESCHLOSSEN 2026-10-09] (Commit ab1de66)
- I11 Rollout-Check: `Test-SQLSyncConnections.ps1 -PreDeploy` (rein lesend) prüft Konfigs gegen Schema/Namensregeln, Treiber-Hash, Firebird-Version gegen CVEs, SYSDBA-Anmeldung und `decimal`-Altbestand; Exit 6 bei FEHLER — [ABGESCHLOSSEN 2026-10-09] (Commit 89e4565)
- I7 Treiber-Integrität: SHA-256-Prüfung für jede DLL vor dem Laden (Download, vorhanden, `DllPath`), Original-Hashes net8.0 + netstandard2.1, Ausnahme nur über `Firebird.DllSha256`; Admin-Check mockbar, `SecurityProtocol` wird wiederhergestellt — [ABGESCHLOSSEN 2026-10-09] (Commit e173ac2)
- I6 Konfig gegen `config.schema.json` geprüft (Fail-Fast, Exit 2; Schema-Muster an die Namens-Whitelist angeglichen), gemeinsame Pfadauflösung `Resolve-SQLSyncConfigPath`, `-ConfigFile` für `Get_Firebird_Schema.ps1`/`Manage_Config_Tables.ps1` — [ABGESCHLOSSEN 2026-10-09] (Commit c5f94f0)
- I5 Typmapping-Datentreue: `DECIMAL(p,s)` aus Precision/Scale des Firebird-Schemas, Hauptskript nutzt `ConvertTo-SqlServerType` und `Get-TableColumnConfig` (Modul im Parallel-Block); Integrationslauf mit Werten bis zur 6. Nachkommastelle identisch — [ABGESCHLOSSEN 2026-10-08] (Commit 2d1a7ef)
- I9 Scheduled-Task-Setup parametrisiert (Installationsordner, Konfigdateien, Tasknamen, Zeitpläne als Parameter mit neutralen Defaults; `-WhatIf` ohne Adminrechte; Option `-RunAsUser`/`-GmsaAccount`); keine internen Begriffe mehr in versionierten Dateien — [ABGESCHLOSSEN 2026-10-08] (Commit 438dd57)
- I4 SQL-Identifier gehärtet (Whitelist-Validierung in `Get-SQLSyncConfig` inkl. `MSSQL.Database` und 128-Zeichen-Grenze, `[...]`/`QUOTENAME` überall, Metadaten-Abfragen und `sp_Merge_Generic` parametrisiert, `Manage_Config_Tables.ps1` markiert ungültige Namen) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
- I3 Pester-Testharness + Unit-Tests für `SQLSyncCommon.psm1` (74 Tests, alle exportierten Funktionen, Coverage 82,54 % bei Ziel 80 %, 13/13 Mutationen erkannt) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
- I2 Fehlschläge sichtbar machen (Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; dazu konfigurierbare Credential-Targets) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d; Abnahme gegen Firebird-Testserver → SQL-Testserver inkl. Aufgabenplanung `0xA`)
- I1 docs/ initialisiert (docs_template v26, Stack `powershell-automation`) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
