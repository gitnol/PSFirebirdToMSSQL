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

## Aktuell (Hohe Priorität)

### I5: Typmapping-Datentreue + Modulfunktionen nutzen

Bezug: `KNOWN_ISSUES.md` K2.

**Aufgaben:**

- [ ] `ConvertTo-SqlServerType` um `NumericPrecision`/`NumericScale` erweitern (`DECIMAL(p,s)`, Fallback `DECIMAL(38,s)`)
- [ ] Inline-Typmapping im Hauptskript durch `ConvertTo-SqlServerType` ersetzen (inkl. `Guid`)
- [ ] Inline-Spalten-/Strategieermittlung durch `Get-TableColumnConfig` ersetzen (Hinweis: Modul im `-Parallel`-Block importieren)
- [ ] Hinweis in `RUNBOOK.md`: bestehende Staging-/Zieltabellen müssen für korrigierte Typen neu angelegt werden (`RecreateStagingTable` + Ziel-Neuaufbau)

**Definition of Done:**

- [ ] Unit-Test: `NUMERIC(18,6)` → `DECIMAL(18,6)`, `NUMERIC(15,2)` → `DECIMAL(15,2)`
- [ ] Keine doppelte Typmapping-/Strategie-Logik mehr im Hauptskript
- [ ] Gemeinsame DoD erfüllt

---

## Mittlere Priorität

### I6: Config-Schema-Validierung aktiv + gemeinsame Configpfad-Auflösung

- [ ] Alle Skripte übergeben `-SchemaPath (Join-Path $PSScriptRoot 'config.schema.json')`; Schema-Verstoß → `throw` statt `Write-Warning`
- [ ] Neue Modulfunktion für die Configpfad-Auflösung (heute in `Sync_Firebird_MSSQL_AutoSchema.ps1` und `Test-SQLSyncConnections.ps1` kopiert)
- [ ] `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1` erhalten `-ConfigFile` (heute fest `config.json`)
- **DoD:** fehlerhafte Konfig (z. B. `GlobalTimeout: "abc"`) bricht mit Exit 2 und verständlicher Meldung ab; Unit-Tests grün; gemeinsame DoD erfüllt

### I7: Treiber-Integrität für vorhandene/konfigurierte DLL

- [ ] `Initialize-FirebirdDriver` prüft SHA-256 auch, wenn die DLL bereits in `%ProgramData%\SQLSync\Drivers\...` liegt oder per `DllPath` konfiguriert ist (Abweichung → Abbruch mit Exit 7, Ausnahme nur über expliziten Konfig-Schalter mit eigenem erwarteten Hash)
- [ ] NTFS-Rechte auf den Treiberordner in `operations/SETUP.md` dokumentieren (nur Administratoren schreibend)
- **DoD:** manipulierte DLL (ein Byte geändert) wird nicht geladen; gemeinsame DoD erfüllt

### I8: Inkrementelles Wasserzeichen mit Überlappungsfenster

Bezug: `KNOWN_ISSUES.md` K3.

- [ ] Neuer Konfigschlüssel `General.IncrementalOverlapMinutes` (Default z. B. 10); Extrakt mit `ts >= MAX(ts) - Overlap` (MERGE ist idempotent)
- [ ] Schema, Sample, README und `architecture/CONFIGURATION.md` ergänzen
- **DoD:** Integrationstest: Datensatz mit identischem Zeitstempel wie das Wasserzeichen wird übernommen; gemeinsame DoD erfüllt

### I9: Scheduled-Task-Setup parametrisieren, interne Namen entfernen

- [ ] `Setup-ScheduledTasks.ps1`: Pfade, Konfigdateinamen und Zeitpläne als Parameter (Defaults neutral), Option für Dienstkonto/gMSA
- [ ] Interne Konfignamen/Pfade (Laufwerkspfade wie `E:\…`, interne Konfignamen) aus `Setup-ScheduledTasks.ps1` entfernen — `config.sample.json`, `config.schema.json` und READMEs sind seit 2026-10-08 neutralisiert (`SQLSERVER01`, Platzhalter-Zugangsdaten)
- **DoD:** Skript läuft ohne Codeänderung auf einem frischen Server; `git grep` findet keine internen Hostnamen/Kürzel; gemeinsame DoD erfüllt

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

- I4 SQL-Identifier gehärtet (Whitelist-Validierung in `Get-SQLSyncConfig` inkl. `MSSQL.Database` und 128-Zeichen-Grenze, `[...]`/`QUOTENAME` überall, Metadaten-Abfragen und `sp_Merge_Generic` parametrisiert, `Manage_Config_Tables.ps1` markiert ungültige Namen) — [ABGESCHLOSSEN 2026-10-08] (Commit f2e8736)
- I3 Pester-Testharness + Unit-Tests für `SQLSyncCommon.psm1` (74 Tests, alle exportierten Funktionen, Coverage 82,54 % bei Ziel 80 %, 13/13 Mutationen erkannt) — [ABGESCHLOSSEN 2026-10-08] (Commit dd4a202)
- I2 Fehlschläge sichtbar machen (Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; dazu konfigurierbare Credential-Targets) — [ABGESCHLOSSEN 2026-10-08] (Commits 9dd12b5, ce9345b; Abnahme gegen Firebird-Testserver → SQL-Testserver inkl. Aufgabenplanung `0xA`)
- I1 docs/ initialisiert (docs_template v26, Stack `powershell-automation`) — [ABGESCHLOSSEN 2026-10-08] (Commit b1e53a9)
