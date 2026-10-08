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

### I7: Treiber-Integrität für vorhandene/konfigurierte DLL

- [ ] `Initialize-FirebirdDriver` prüft SHA-256 auch, wenn die DLL bereits in `%ProgramData%\SQLSync\Drivers\...` liegt oder per `DllPath` konfiguriert ist (Abweichung → Abbruch mit Exit 7, Ausnahme nur über expliziten Konfig-Schalter mit eigenem erwarteten Hash)
- [ ] NTFS-Rechte auf den Treiberordner in `operations/SETUP.md` dokumentieren (nur Administratoren schreibend)
- **DoD:** manipulierte DLL (ein Byte geändert) wird nicht geladen; gemeinsame DoD erfüllt

### I8: Inkrementelles Wasserzeichen mit Überlappungsfenster

Bezug: `KNOWN_ISSUES.md` K3.

- [ ] Neuer Konfigschlüssel `General.IncrementalOverlapMinutes` (Default z. B. 10); Extrakt mit `ts >= MAX(ts) - Overlap` (MERGE ist idempotent)
- [ ] Schema, Sample, README und `architecture/CONFIGURATION.md` ergänzen
- **DoD:** Integrationstest: Datensatz mit identischem Zeitstempel wie das Wasserzeichen wird übernommen; gemeinsame DoD erfüllt

---

## Niedrige Priorität

### I10: Doku-/Repo-Drift beheben

- [ ] `.github/copilot-instructions.md` an den Code angleichen (kein `Install-Package`, `Example_Sync_Start.ps1` ruft bereits das AutoSchema-Skript; Schlussfrage des Agenten entfernen; Verweis auf `docs/`)
- [ ] `Test-SQLSyncConnections.ps1`: doppelte Ausgabe der Test-Query-Zeile entfernen
- [ ] `MSSQL.Port`: im Connection-String verwenden oder aus Sample/Schema entfernen
- [ ] `README_alternativ.md`: zusammenführen oder entfernen
- **DoD:** Doku und Code widerspruchsfrei (Stichprobe aller Skriptparameter); gemeinsame DoD erfüllt

---

## Abgeschlossen

- I6 Konfig gegen `config.schema.json` geprüft (Fail-Fast, Exit 2; Schema-Muster an die Namens-Whitelist angeglichen), gemeinsame Pfadauflösung `Resolve-SQLSyncConfigPath`, `-ConfigFile` für `Get_Firebird_Schema.ps1`/`Manage_Config_Tables.ps1` — [ABGESCHLOSSEN 2026-10-09] (Commit siehe `STATE.md`)
- I5 Typmapping-Datentreue: `DECIMAL(p,s)` aus Precision/Scale des Firebird-Schemas, Hauptskript nutzt `ConvertTo-SqlServerType` und `Get-TableColumnConfig` (Modul im Parallel-Block); Integrationslauf mit Werten bis zur 6. Nachkommastelle identisch — [ABGESCHLOSSEN 2026-10-08] (Commit 2d1a7ef)
- I9 Scheduled-Task-Setup parametrisiert (Installationsordner, Konfigdateien, Tasknamen, Zeitpläne als Parameter mit neutralen Defaults; `-WhatIf` ohne Adminrechte; Option `-RunAsUser`/`-GmsaAccount`); keine internen Begriffe mehr in versionierten Dateien — [ABGESCHLOSSEN 2026-10-08] (Commit 438dd57)
- I4 SQL-Identifier gehärtet (Whitelist-Validierung in `Get-SQLSyncConfig` inkl. `MSSQL.Database` und 128-Zeichen-Grenze, `[...]`/`QUOTENAME` überall, Metadaten-Abfragen und `sp_Merge_Generic` parametrisiert, `Manage_Config_Tables.ps1` markiert ungültige Namen) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
- I3 Pester-Testharness + Unit-Tests für `SQLSyncCommon.psm1` (74 Tests, alle exportierten Funktionen, Coverage 82,54 % bei Ziel 80 %, 13/13 Mutationen erkannt) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
- I2 Fehlschläge sichtbar machen (Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; dazu konfigurierbare Credential-Targets) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d; Abnahme gegen Firebird-Testserver → SQL-Testserver inkl. Aufgabenplanung `0xA`)
- I1 docs/ initialisiert (docs_template v26, Stack `powershell-automation`) — [ABGESCHLOSSEN 2026-10-08] (Commit a082e9d)
