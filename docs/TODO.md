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

## Mittlere Priorität

### I10a: Rollout-Check-Erweiterung und Backup-Hygiene

Neu zugeschnitten (KICKOFF 2a, Roadmap nach I10b): Prüf- und Backup-Teil der bisherigen I10a, gebündelt mit der
Erkennungshälfte von K6 (Schema-Drift) — die fehlende Zeitstempelspalte ist ein Sonderfall davon. Modul-Aufräumen
(`MSSQL.Port`, `Protect-SqlString`) → I10d.

- [ ] `-PreDeploy`: Schema-Drift je konfigurierter Tabelle — Quellspalten, die in der vorhandenen Zieltabelle fehlen; fehlt die Zeitstempelspalte einer Incremental-Tabelle → `FEHLER` (Tabelle endet sonst mit Exit 10), andere fehlende Spalten → `WARNUNG` (K6); rein lesend, keine DDL
- [ ] `-PreDeploy`: `WARNUNG` bei Klartext-Passwort in einer Konfig (`Firebird.Password`/`MSSQL.Password` gesetzt) und bei vorhandenen `config*.bak`
- [ ] `Manage_Config_Tables.ps1`: Backups rotieren (nur die letzten N behalten) statt unbegrenzt anzulegen
- **DoD:** Unit-Tests mit behavioralem Rot für Drift- und Klartext-Erkennung und Rotation; Integrationslauf `-PreDeploy` gegen die Testumgebung mit künstlich entfernter Zielspalte (nur Test-Datenbank); CI grün; gemeinsame DoD erfüllt
---

## Niedrige Priorität

### I10c: Doku-Konsolidierung

Doku-Teil der bisherigen I10a; Umfang ergänzt um die Befundliste der Reflexion nach I8.

- [ ] Exit-Code-Tabelle: einzige Quelle `architecture/ERROR_HANDLING.md` (inkl. Exit-Codes von `Test-SQLSyncConnections.ps1`), übrige `docs/`-Stellen verlinken (READMEs behalten ihre Nutzer-Tabelle)
- [ ] Schwachstellen-Katalog (S-IDs) in K-/I-IDs überführen und S-Verweise ersetzen
- [ ] `.github/copilot-instructions.md` an den Code angleichen (kein `Install-Package`, Verweis auf `docs/`, Schlussfrage entfernen)
- [ ] `README_alternativ.md` zusammenführen oder entfernen
- **DoD:** Doku und Code widerspruchsfrei (Stichprobe aller Skriptparameter); eine Exit-Code-Änderung berührt höchstens 3 Dateien; gemeinsame DoD erfüllt

---

### I10d: Modul-Aufräumen

Code-Teil der bisherigen I10a; nach I10c, damit die Doku-Änderungen auf konsolidierte Stellen treffen.
Gebündelt mit den PSScriptAnalyzer-Warnungen an denselben Funktionen.

- [ ] `MSSQL.Port` (K9): in `New-MSSQLConnectionString` verwenden (`Server,Port`) oder aus Sample/Schema entfernen
- [ ] Ungenutztes `Protect-SqlString` entfernen (seit I4 ohne Aufrufer); über `Write-SyncStatus`/`Close-DatabaseConnection` (von keinem Skript genutzt) entscheiden
- [ ] Warnungen an `New-FirebirdConnectionString`/`New-MSSQLConnectionString` abbauen oder begründet unterdrücken (`PSAvoidUsingPlainTextForPassword`, `PSUseShouldProcessForStateChangingFunctions`)
- **DoD:** Unit-Test mit behavioralem Rot für den Port; exportierte Funktionsnamen unverändert (außer entfernte); CI grün; gemeinsame DoD erfüllt

---
## Abgeschlossen

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
