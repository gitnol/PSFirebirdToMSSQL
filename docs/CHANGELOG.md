# Changelog – PSFirebirdToMSSQL

Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/).
Einträge chronologisch absteigend (neueste oben). Jeder Eintrag entspricht
genau einem Inkrement (= einem Commit oder einer eng zusammengehörigen
Commit-Serie).

Nicht alle Sektionen sind in jedem Eintrag nötig — leere Sektionen weglassen.

Die Versionshistorie vor Einführung von `docs/` (v2.1 bis v2.10) steht im
Abschnitt „Changelog" von `README.md`.

---

## 2026-10-10 Reflexion nach I10c (I10b, I10a, I10c)

### Advocatus Diaboli
- **Positiv:** Behauptungen wurden durch Gegenproben in der Test-Datenbank belegt statt angenommen — CI rot/grün
  (I10b), jede Drift-Einstufung per echtem Sync (I10a), Skriptparameter per AST gegen die Doku (I10c). Die
  Messungen haben zwei falsche Betriebsaussagen gefunden (RUNBOOK `ALTER TABLE … ADD`) und K10 aufgedeckt.
- **Negativ:** I10a ging über die DoD hinaus (Staging-Drift); begründet durch einen gemessenen Fehlerfall, aber
  Scope-Wachstum. Der ID-Fall (K10) ist weiter nur abgeleitet. I10c lässt drei Verweisarten bestehen (K-, I-IDs,
  Bedrohungsnummern) — weniger als vorher, aber kein einheitliches System. Subagenten-Doku brauchte in jedem
  Inkrement Korrekturen (Versionsnummern, eine falsche Ablaufaussage).
- **Backport-Filter:** L11 (abgeleitete Ablaufaussagen messen) nicht zurückgespielt — durch
  `VERIFY_BEFORE_CITE` abgedeckt. L2/L4 projekt-spezifisch.

### Changed
- Struktur-Checks V1–V4, Interna-Scan, Cross-Refs, Validator: ohne Befund; BACKLOG-Zeile zu K6 auf „erledigt"
- Template-Backports (vom Prompter freigegeben) in `docs_template` eingespielt, Commit 19ba253 im offenen
  v26-Block: L1 (`base/BOOTSTRAP.md`), L5-Ergänzung (`base/CONVENTIONS.md` 3.1), L3/L8 (`base/KICKOFF.md`
  TDD-Startregel), L8/L10 (`stacks/powershell-automation/testing/UNIT_TESTS.md` 8.6), L9
  (`stacks/powershell-automation/CONVENTIONS.md`), L6 (`base/principles/FAIL_FAST.md`), Fremdprojekt-Verweis in
  `base/principles/EXTERNAL_SOURCE_ADOPTION.md` neutralisiert. Gate: `validate_template.sh` und
  `smoke_stacks.sh` Exit 0; Eval S1–S3 (base/-Änderung) ausstehend → **kein Tag**, nicht gepusht.
- Projekt-Kopien `principles/FAIL_FAST.md` und `principles/EXTERNAL_SOURCE_ADOPTION.md` angeglichen
- Roadmap (2b): neues **I12** bündelt K10 und K5 (beide melden „Erfolg" trotz Fehler) mit dem Herauslösen des
  Orphan-Cleanups als Modulfunktion; Reihenfolge I12 (Mittel, Datenintegrität) → I10d (Niedrig); `Microsoft.Data.SqlClient` erst nach dem
  Security-Sweep 2026-10-22 entscheiden; Reflexions-Marker → nach drei weiteren Inkrementen

### Lessons Learned
- L11: aus dem Code abgeleitete Ablaufaussagen in Betriebsdoku vor dem Commit messen (kein Backport)

---
## 2026-10-10 I10c – Doku-Konsolidierung

### Changed
- Exit-Codes: einzige Quelle `architecture/ERROR_HANDLING.md` (alle Skripte, um Log-Zeilen je Code und
  `0xC000013A` aus `operations/MONITORING.md` ergänzt); Tabellen in `features/firebird-mssql-sync.md`,
  `operations/MONITORING.md` und `testing/INTEGRATION_TESTS.md` durch Verweise ersetzt; die Nutzer-Tabellen in
  `README.md`/`README.de.md` bleiben (gegen den Code geprüft)
- S-IDs aufgelöst: Verweise in 13 Doku-Dateien durch K-IDs bzw. Bedrohungsnummern aus `THREAT_MODEL.md` ersetzt
  (S1→K1, S2→Bedrohung 1, S3→Bedrohung 2, S4→Bedrohung 3, S5→K2, S6→K3, S7→K4/K5, S8→K8, S9→K7, S10→I3, S11→K6,
  S12→K9, S13→Bedrohung 5); der Katalog bleibt als „Historische Zuordnung" für ältere Commits/CHANGELOG-Einträge
- `.github/copilot-instructions.md` neu geschrieben: Verweis auf `docs/`, Tests/CI/`-PreDeploy`, Regeln zu
  Identifiern, Konfig-Validierung, Secrets und öffentlichem Repo; ohne `Install-Package` und ohne Schlussfrage
- Prinzipien-Notizen zu `copilot-instructions.md` (`CONTEXT_DISCIPLINE`, `EXTERNAL_SOURCE_ADOPTION`,
  `VERIFY_BEFORE_CITE`) aktualisiert

### Removed
- `README_alternativ.md` (Initial-Commit, „alternative Ansicht"): Inhalt vollständig in `README.de.md` bzw.
  `architecture/OVERVIEW.md` (Mermaid-Diagramme), dazu veraltet (ohne `-PreDeploy`, Exit-Codes, Überlappungsfenster)

### Confidence / Ungeprüft
- DoD-Stichprobe: alle 22 Parameter der 6 Skripte mit Parametern (per AST ausgelesen) kommen in `README.md`, `README.de.md`
  und in `docs/` vor; README-Exit-Code-Tabellen gegen die `exit`-Anweisungen der Skripte geprüft.
- DoD „eine Exit-Code-Änderung berührt höchstens 3 Dateien" gilt für die **Tabellen**; im Fließtext nennen
  weiterhin 13 Doku-Dateien einzelne Codes (z. B. „Exit 10" im RUNBOOK) — bewusst belassen, weil sie dort
  konkrete Abläufe beschreiben.
- S-ID-Ersetzung per Skript mit Ausnahmen (Template-Prinzipien, `REFLECTION.md`: dort bezeichnen S1–S3
  Eval-Szenarien); zwei Fehlersetzungen („K1–Bedrohung 5", Überschriften mit Selbstverweis) im Review gefunden
  und korrigiert.

---
## 2026-10-10 I10a – Rollout-Check-Erweiterung und Backup-Hygiene

### Added
- `Test-SQLSyncConnections.ps1 -PreDeploy` (v2.2): **Schema-Drift** Quelle → vorhandene Ziel-/Staging-Tabellen (Ziel
  ohne ID-Spalte oder ohne Zeitstempelspalte einer Incremental-Tabelle → `FEHLER`, bei `ForceFullSync` Zeitstempel nur
  `WARNUNG`; andere fehlende Zielspalte → `WARNUNG`; Staging ohne Quellspalte → `FEHLER`, außer
  `RecreateStagingTable`); **Klartext-Passwort** je Konfig (nur Schlüsselnamen); **Konfig-Backups** im Skriptordner
- `Manage_Config_Tables.ps1` (v2.2): `-KeepBackups` (Default 5) löscht ältere Backups der bearbeiteten Konfig
- Modulfunktionen `Find-SQLSyncSchemaDrift`, `Find-SQLSyncPlaintextPassword`, `Get-SQLSyncConfigBackup`,
  `Remove-SQLSyncConfigBackup` (`-WhatIf`); 16 Pester-Tests (192 gesamt, Coverage 96,23 %)
- `KNOWN_ISSUES.md` K10: `sp_Merge_Generic` kehrt bei fehlender ID-Spalte ohne Fehler zurück (Fix im Backlog)

### Lessons Learned
- L10: `-WhatIf`-Mutanten sind äquivalent, wenn die Funktion nur Cmdlets aufruft (`$WhatIfPreference` wird vererbt)

### Iterations-Log
- Tests zuerst: strukturell rot (15/16), mit Stubs 11 behavioral rot („Expected 1, but got 0" u. a.); die 5
  Negativtests („meldet nichts …") waren mit leeren Stubs zwangsläufig grün → per Mutation abgesichert.
  Mutationsprüfung (Dateikopie + Kindprozess nach L8): 10 Mutanten, 9 erkannt, 1 äquivalent (L10).
- Eigener Testfehler korrigiert: Erwartete Reihenfolge zweier Backups mit gleichem Zeitstempel aus verschiedenen
  Konfigs hing an der Sortierkultur — Reihenfolge jetzt je Konfig geprüft, für den Ordner nur die Menge.
- Einstufung zuerst aus dem Code abgeleitet (`SqlBulkCopy.ColumnMappings`, Spaltenlisten von `sp_Merge_Generic`
  aus `sys.columns` des Ziels), dann gegengeprüft (siehe Confidence).
- **Fixed (Doku, gemessen):** Die bisherige RUNBOOK-Anleitung „Spalte per `ALTER TABLE … ADD` ergänzen, dann
  normaler Lauf" war falsch — der Merge aktualisiert nur Zeilen mit geändertem Zeitstempel. Test-Datenbank:
  normaler Lauf füllte 0 von 33 Altzeilen, `ForceFullSync` (TRUNCATE + Neuladen) 33 von 33. Eine aus dem Code
  abgeleitete Gegenbehauptung im Doku-Entwurf („auch nach Full-Lauf `NULL`") war ebenfalls falsch; beides per
  Messung korrigiert (RUNBOOK, K6).

### Confidence / Ungeprüft
- Integration (Test-Datenbank): Basislauf Schema-Drift OK (76 Spalten); künstliche Drift an einer Testtabelle →
  `FEHLER` Zeitstempel, `WARNUNG` andere Zielspalte, `FEHLER` Staging. Gegenproben mit dem echten Sync (je nur eine
  Drift): Zeitstempelspalte fehlt → 4 Versuche „Ungültiger Spaltenname", Exit 10 (damit ist auch der I8-Fehlerpfad
  Ende-zu-Ende belegt); Staging-Spalte fehlt → BulkCopy „ColumnMapping does not match", Exit 10; andere Zielspalte
  fehlt → Erfolg, Exit 0, Spalte fehlt still. Danach Tabellen per Erstlauf neu aufgebaut, `-PreDeploy` wieder OK.
- **Nicht** Ende-zu-Ende: fehlende ID-Spalte (K10, nur aus `sql_server_setup.sql` abgeleitet); Backup-Rotation in
  `Manage_Config_Tables.ps1` (interaktiv mit `Out-GridView`, nur Modulfunktion unit-getestet); Klartext-Warnung trat
  im Integrationslauf nicht auf (keine Testkonfig mit Passwortfeld) — nur unit-getestet.
- Drift in Gegenrichtung (Zielspalte, die in der Quelle fehlt) wird nicht geprüft.
- Die Exit-6-Prüfung lief im Integrationslauf ohnehin rot wegen der absichtlich ungültigen Testkonfig aus I6.

---
## 2026-10-10 Roadmap nach I10b (KICKOFF 2a)

### Changed
- I10a neu zugeschnitten: **Rollout-Check-Erweiterung und Backup-Hygiene** — gebündelt mit der Erkennungshälfte von
  K6 (fehlende Zeitstempelspalte im Ziel ist ein Sonderfall von Schema-Drift); automatische DDL bleibt im Backlog
- Modul-Teil der bisherigen I10a (`MSSQL.Port`, `Protect-SqlString`) als **I10d** abgetrennt (Größengrenze), gebündelt
  mit den PSScriptAnalyzer-Warnungen an `New-*ConnectionString` (dieselben Funktionen wie der Port)
- Reihenfolge I10a → I10c → (Reflexion) → I10d: Doku erst konsolidieren, dann trifft I10d weniger doppelte Stellen
- Bewusst getrennt: `Microsoft.Data.SqlClient`, Zerlegung des Hauptskripts, K5, `Setup_Credentials.ps1`-Duplikate

---
## 2026-10-09 I10b – CI auf GitHub

### Added
- `.github/workflows/ci.yml`: `windows-latest`, Auslöser Push auf `main`, PRs nach `main`, `workflow_dispatch`;
  Schritte: gepinnte Module installieren → `tests/scriptanalyzer.ps1` → `tests/pester.config.ps1`
- `tests/scriptanalyzer.ps1`: PSScriptAnalyzer 1.25.0 (gepinnt in `tests/RequiredModules.psd1`), Exit 1 nur bei
  Severity `Error`; CI-Badge in beiden READMEs

### Security
- `actions/checkout` per Commit-SHA (v7.0.1) gepinnt, `permissions: contents: read`, `persist-credentials: false`,
  keine Secrets (Recherche Security-Currency: GitHub-Härtungsleitfaden, SHA-Pinning und Least Privilege);
  `THREAT_MODEL.md` Bedrohung 7, Update-Prüfung der Action in `DEPENDENCY_AUDIT.md`

### Changed
- Vier `Error`-Befunde begründet per `SuppressMessageAttribute` unterdrückt: `PSAvoidUsingUsernameAndPasswordParams`
  an `New-FirebirdConnectionString`/`New-MSSQLConnectionString` (exportierte Signatur bleibt),
  `PSAvoidUsingConvertToSecureStringWithPlainText` in den Testdaten; 207 Warnungen als Liste in `BACKLOG.md`

### Iterations-Log
- Kein klassisches TDD (Workflow-Konfiguration); Nachweis über beide Pfade: `tests/scriptanalyzer.ps1` lokal mit
  Probe-Datei rot (Exit 1) und ohne grün (Exit 0); CI-Lauf auf `main` (8ec55c4) **success** mit 0 Error,
  176/176 Tests, Coverage 95,63 %; temporärer Branch mit absichtlich rotem Test, per `workflow_dispatch`
  gestartet → Schritt Pester **failure** („Expected 2, but got 1", 176 passed / 1 failed), Lauf **failure**.

### Confidence / Ungeprüft
- Ein PR-Lauf wurde nicht ausgelöst (Integration ohne PRs); der Auslöser `pull_request` ist nur konfiguriert.
- PSGallery-Module per Version, nicht per Hash gepinnt.
- Lokal liegen Pester 5.7.1 und PSScriptAnalyzer 1.25.0 bereits vor; ein frisches Entwickler-Setup wurde nur in
  der CI (windows-latest) durchlaufen.

---
## 2026-10-09 Reflexion nach I8 (I7, I11, I8)

### Advocatus Diaboli
- **Positiv:** Nachweise per Gegenprobe statt Behauptung — I8 alt-gegen-neu bei gleicher Datenlage (Ceteris
  paribus), I11 mit künstlichem Altbestand, I7 mit manipulierter DLL; Mutationsprüfung bei jeder neuen Logik;
  der alte `catch` wurde vor dem Entfernen gelesen (Erstlauf-Fall erkannt statt wegrefaktoriert).
- **Negativ:** Default `IncrementalOverlapMinutes = 10` ist eine Annahme, keine Messung. Die CVE-Liste in
  `$script:FirebirdServerAdvisories` veraltet ohne Pflege — der Security-Sweep muss sie mitprüfen (in
  `security/DEPENDENCY_AUDIT.md` vermerkt). Drei eigene Werkzeugfehler in einem Inkrement (Here-String ohne
  Zeilenumbruch, Mutationsskript mit Schaden an der Pester-Installation, `datetime`-Parameter) — alle vor dem
  Commit gefunden, aber das Muster „Hilfsskript ohne eigene Kontrolle" ist das eigentliche Risiko (L8).
- **Über Bedarf gebaut?** `Get-SQLSyncExtractQuery` ist sehr klein; gerechtfertigt nur durch Testbarkeit des
  `>=` — beibehalten.

### Changed
- Struktur-Checks V1–V4, Interna-Scan, Cross-Refs: ohne Befund; Exit-Codes Doku ↔ Code stichprobenartig gleich
- `KICKOFF.md`: veraltete Passagen (Identifier-Regel „bis I4", I1 „diese Session"), Status der erledigten
  Inkremente im Inkrementplan, `-PreDeploy` im Quickstart
- `STATE.md`: Inkrementtabelle chronologisch nach git (I9 vor I6, I11 vor I8); Reflexions-Marker → nach I10c
- `KNOWN_ISSUES.md`: Kopf-Stand aktualisiert; ADR-001: Nachtrag zu K3 statt Änderung des Entscheidungstexts
- Roadmap (2b): I10a um `-PreDeploy`-Warnung für fehlende Zeitstempelspalten im Ziel ergänzt (neues
  Exit-10-Risiko aus I8, gleiche Datei wie die Klartext-Warnung); Reihenfolge I10b → I10a → I10c bleibt

### Template-Backport-Vorschläge (Freigabe ausstehend, nichts ins Template committet)
- **wichtig** L3 Mutationsprüfung (in I3, I11, I8 bewährt) + L8 Mutationsläufe sicher (Dateikopie,
  Kindprozess, Kontrolllauf) → `base/` TDD-Startregel bzw. `stacks/powershell-automation/` Testing
- **wichtig** L1 gitignore-Muster verankern → `base/` (Public-Repo-Abschnitt aus L5 v26)
- **sinnvoll** L5-Ergänzung: Denylist erkennt Namen, keine Aussagen → `base/` Public-Repo-Regel
- **sinnvoll** L6 Fail-Fast-Validierung vorher gegen den Bestand prüfen → `base/principles/FAIL_FAST.md`
- **sinnvoll** L9 `AddWithValue(DateTime)` = `datetime` → `stacks/powershell-automation/CONVENTIONS.md`;
  Analogon in `csharp-*`-Stacks (gleiche SqlClient-API) idiomatisch prüfen
- **sinnvoll** Template-Fund: `base/principles/EXTERNAL_SOURCE_ADOPTION.md` verweist auf ein fremdes Projekt
  („eingeführt in Inkrement I11") — in jedem initialisierten Projekt irreführend; neutralisieren
- Zu jung, nicht vorgeschlagen: keine (alle Kandidaten haben mindestens einen belegten Vorfall)

---

## 2026-10-09 Interner Datenbankname aus Beispielen entfernt

### Security
- Beispielpfad der Firebird-Datenbank in `README.md`, `README.de.md` und `config.schema.json` (`examples`)
  neutralisiert; der bisherige Wert war ein interner Datenbankname (seit dem Initial-Commit öffentlich,
  bleibt in der Git-Historie). Die lokale Interna-Denylist erfasst das Namensmuster jetzt.

---

## 2026-10-09 I8 – Wasserzeichen mit Überlappungsfenster

### Added
- Konfigschlüssel `General.IncrementalOverlapMinutes` (0..1440, Default 10) in Schema, Sample und
  `Get-SQLSyncConfig` (Bereichsprüfung, Fail-Fast)
- Modulfunktionen `Get-SQLSyncIncrementalLowerBound`, `Get-SQLSyncIncrementalWatermark`,
  `Get-SQLSyncExtractQuery` — erster Schnitt der Hauptskript-Zerlegung, Extrakt damit unit-testbar
- 19 Pester-Tests (176 gesamt, Coverage 95,63 %), 7/7 Mutationen erkannt

### Changed
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.18: Incremental liest ab `MAX(ts) − Überlappung` inklusive (`>=`)
  statt strikt `> MAX(ts)` (K3); `RowsLoaded` enthält dadurch die erneut gelesenen Zeilen des Fensters
- Wasserzeichen: fehlende bzw. leere Zieltabelle → Vollabzug mit Hinweis in der Info-Spalte; scheitert die
  `MAX`-Abfrage auf einer vorhandenen Zieltabelle → Retry, danach Status „Fehler" (Exit 10)

### Fixed
- Stiller Vollabzug ab 1900-01-01, wenn die `MAX`-Abfrage scheiterte (z. B. Zeitstempelspalte fehlt im Ziel)
- K3 weitgehend: Datensätze mit Zeitstempel ≤ Wasserzeichen, die nach dem letzten Lauf committet wurden

### Lessons Learned
- L8: Mutationsläufe — Original als Datei sichern, Testrunner im Kindprozess (ein In-Prozess-Lauf hat die
  installierte `Pester.ps1` des Benutzers überschrieben und zwei Mutanten im Modul hinterlassen; beides
  bemerkt, das Modul vor dem Commit per Diff/Mutationskontrolle wiederhergestellt)
- L9: `AddWithValue(DateTime)` vergleicht als `datetime` (3,33 ms) — im Testhilfsskript wäre sonst die
  Wasserzeichen-Zeile selbst gelöscht worden

### Iterations-Log
- Tests zuerst: strukturell rot (Funktionen fehlten), mit Stubs 18/18 behavioral rot („Expected 10, but got
  $null" u. a.), dann grün. Zwei Implementierungsfehler unterwegs: `[Nullable[datetime]]` wird von PowerShell
  entpackt (`.Value` war `$null`); `Assert-SqlIdentifier` hätte Zielnamen > 63 Zeichen abgelehnt (Ziel darf
  128) — eigener Test ergänzt, per Mutation abgesichert.
- Beim Lesen bestätigt: Der alte `catch` deckte auch den legitimen Erstlauf ab (Zieltabelle entsteht erst nach
  dem Extrakt) — deshalb Unterscheidung fehlt / leer / Fehler statt bloßem Entfernen.

### Confidence / Ungeprüft
- Integration (Test-Datenbank, Ceteris paribus — nur die Codeversion variiert): Zieldatensatz ~14 s unter dem
  Wasserzeichen gelöscht → v2.16 lädt 0 Zeilen, Datensatz fehlt, Sanity FEHLER (-1), Exit 11; v2.18 lädt 2
  Zeilen, Datensatz wieder da, OK, Exit 0. Leere Zieltabelle → Hinweis + Vollabzug; gelöschte Zieltabelle →
  Erstlauf-Hinweis, neu angelegt, Folgelauf wieder inkrementell.
- **Nicht** Ende-zu-Ende getestet: scheiternde `MAX`-Abfrage auf vorhandener Tabelle (nur Unit-Test). Folge
  beim Deployment: Zieltabellen, deren Zeitstempelspalte im Ziel fehlt, liefen bisher still als Vollabzug und
  enden jetzt mit „Fehler"/Exit 10 — `-PreDeploy` prüft das nicht.
- Annahme ungeprüft: 10 Minuten decken die realen Commit-Verzögerungen der Quelle; gemessen wurde nichts.
  Längere Transaktionen holt weiter erst der Full-Lauf.
- Volle Suite lief mit einer sauberen Pester-5.7.1-Kopie (PSGallery, Signatur gültig) statt der beschädigten
  installierten; deren Reparatur steht aus (Datei außerhalb des Repos, Bestätigung des Prompters nötig).
- Nicht gegen die produktive Umgebung gelaufen.

---

## 2026-10-09 Roadmap nach I11 (KICKOFF 2a)

### Changed
- I8 gebündelt mit dem stillen Vollabzug bei Fehler der `MAX(ts)`-Abfrage (dieselben Zeilen im Hauptskript)
- I10b (CI) vor I10a gezogen, Priorität Mittel: Integration läuft seit I11 ohne Pull Requests (lokaler Merge,
  Push auf `main`), Auslöser daher Push auf `main` und PRs; PSScriptAnalyzer scheitert nur bei Severity `Error`
- Bisherige I10a gesplittet (Größengrenze): **I10a Konfig- und Modul-Hygiene** (`MSSQL.Port`, `Protect-SqlString`,
  gebündelt mit Klartext-Passwort-Warnung in `-PreDeploy` und `.bak`-Rotation in `Manage_Config_Tables.ps1`) und
  **I10c Doku-Konsolidierung** (Exit-Code-Quelle, ID-Systeme, copilot-instructions, `README_alternativ.md`)
- Reflexion nach I8 korrigiert nur Prozess-Docs und liefert die Befundliste für I10c
- Bewusst getrennt: K5/K6 (andere Abschnitte des Hauptskripts); `Microsoft.Data.SqlClient` und Treiber-Update
  (nur Prüfung im Security-Sweep 2026-10-22, Umstellung wäre eigenes Inkrement)

---

## 2026-10-09 I11 – Rollout-Check

### Added
- `Test-SQLSyncConnections.ps1 -PreDeploy` (v2.1, rein lesend): Konfigs gegen Schema/Namensregeln, Treiber-DLL
  gegen erlaubte SHA-256 (ohne Laden), Firebird-Serverversion gegen bekannte CVEs, SYSDBA-Anmeldung,
  `decimal`-Altbestand (Zielspalte mit kleinerer Precision/Scale als die Firebird-Quelle); Tabelle
  OK/WARNUNG/FEHLER, Exit 6 bei FEHLER
- Modulfunktionen `Get-FirebirdServerAdvisory`, `Find-SQLSyncDecimalTruncation`, `Test-FirebirdDriverIntegrity`
- 13 Pester-Tests (157 gesamt, Coverage 95,29 %)

### Changed
- Treiberkonstanten (Version, URL, erlaubte Hashes) und Kandidatensuche zentral im Modul
  (`$script:FirebirdDriver`, `Get-FirebirdDriverCandidatePath`), von `Initialize-FirebirdDriver` und der neuen
  Prüfung gemeinsam genutzt; CVE-Liste zentral in `$script:FirebirdServerAdvisories`

### Fixed
- Doppelte Ausgabe der Test-Query-Zeile in `Test-SQLSyncConnections.ps1` (aus I10)

### Iterations-Log
- Tests zuerst: strukturell rot (Funktionen fehlten), mit Stubs behavioral rot („Expected 1, but got 0" u. a.),
  dann grün. Das Treiber-Refactoring ist durch die bestehenden Treibertests abgesichert (unverändert grün).
- Zwei eigene Werkzeugfehler unterwegs (Ersetzungsmuster traf echte `Assert-SqlIdentifier`-Aufrufe; verschachtelter
  Here-String im Hilfsskript) — jeweils vor dem Commit bemerkt, Modul per `git checkout` zurückgesetzt.

### Confidence / Ungeprüft
- Integration gegen die Testumgebung: schemawidrige Testkonfig → FEHLER/Exit 6; Original-DLL OK; Versions- und Konto-
  Prüfung lieferten die erwarteten Befunde (Ergebnis je Host nur in `docs/local/`); 42 Dezimalspalten ohne Kürzung. Künstlich auf `decimal(18,4)` gesetzte Testspalte (nur
  Testdatenbank) → WARNUNG, Exit 0; Korrektur nach RUNBOOK (`ALTER COLUMN` + ForceFull) stellte die Werte bis zur
  6. Nachkommastelle wieder her, danach OK.
- Rein lesend: neue Codezeilen enthalten nur `SELECT`s (geprüft per Diff).
- Nicht gegen die produktive Umgebung gelaufen — das ist der Zweck vor dem Deployment.

---

## 2026-10-09 Roadmap nach Konsolidierung (KICKOFF 2a)

### Changed
- Neu **I11 Rollout-Check** (Hoch): bündelt vier `STATE.md`-Risiken zum Deployment, die manuelle
  DEPLOYMENT-Checkliste, die Altbestands-Prozedur aus dem RUNBOOK und den I10-Punkt „doppelte Ausgabe"
  (alle betreffen `Test-SQLSyncConnections.ps1`)
- **I8** erweitert um den ersten Schnitt der Hauptskript-Zerlegung (Extrakt als Modulfunktion); K5/K6 bewusst
  getrennt (andere Schritte, Größengrenze)
- **I10** gesplittet in **I10a** Doku-/Repo-Konsolidierung (inkl. Backlog „Doku-Duplikate", „ID-Systeme",
  ungenutztes `Protect-SqlString`) und **I10b** CI
- Reihenfolge: I11 → I8 → I10a → I10b. Begründung: I11 sichert das Deployment des gemergten Stands;
  stiller Datenverlust (I8) vor Pflegeaufwand (I10). Zurückgestellt als spätere Pakete: Hauptskript-Gesamtumbau
  mit `Microsoft.Data.SqlClient`, JSON-Laufergebnis, K5/K6; Secrets-Paket (Klartext-Fallback, `.bak`)
- Remote-Branches `testing` (veralteter Zeiger, vollständig in `main`) und `docs/i1-baseline` (gemergt) gelöscht

---

## 2026-10-09 Prozess: Überschneidungen und Konsolidierungen bei der Planung

### Added
- `KICKOFF.md` Phase 1 Punkt 2a: vor der Wahl des nächsten Inkrements `TODO.md`, `BACKLOG.md`, aktive
  `KNOWN_ISSUES.md` und `STATE.md`-Risiken gemeinsam auf Überschneidungen/Konsolidierungen prüfen
- `REFLECTION.md` Schritt 2b „Roadmap-Konsolidierung"
- `LESSONS_LEARNED.md` L7; Backport ins Template (v26, unreleased)

### Changed
- PR #1 nach `main` gemergt (Merge-Commit, Commit-Hashes in `STATE.md`/`TODO.md` bleiben gültig)

---
## 2026-10-09 Übernahme aus lokalem Branch `fix/folgepunkte-doku-83-sha`

### Removed
- Ungenutzte, nicht exportierte Helfer `Invoke-WithFirebirdConnection` / `Invoke-WithMSSQLConnection` aus
  `SQLSyncCommon.psm1` (übernommen aus lokalem Commit `1ed31c6`); stattdessen Beispiel für das
  `try/finally`-Muster mit `Close-DatabaseConnection` im Modul-Kommentar

### Changed
- Entscheidung zur Treiberprüfung dokumentiert: Der zweite Commit des Branches (`73b8d6b`) prüfte nur die
  zentrale `net8.0`-DLL und ließ eine per `DllPath` konfigurierte DLL bewusst ungeprüft. **Beibehalten wird
  die strengere I7-Variante** (jede DLL wird geprüft; Ausnahme nur mit `Firebird.DllSha256`), weil
  (a) gemessen normale Benutzer im Treiberordner unter `%ProgramData%` Dateien anlegen dürfen und auch ein
  `DllPath`-Ziel fremd beschreibbar sein kann, (b) die vorhandenen Konfigs auf die Original-DLL zeigen und
  unverändert laufen, (c) eine abweichende DLL weiterhin möglich ist — als dokumentierte Entscheidung über
  den Hash statt als stille Ausnahme. `73b8d6b` wird daher nicht übernommen.

### Confidence / Ungeprüft
- 138 Pester-Tests grün; Coverage 94,04 % (gestiegen, da toter Code entfernt); kein Aufrufer der entfernten
  Funktionen im Repo (`grep`).

---

## 2026-10-09 Doku-Abgleich vor dem ersten Push

### Fixed
- Versionsangaben: `Sync_Firebird_MSSQL_AutoSchema.ps1` auf 2.16 gehoben (I7 hat das Skript geändert —
  `-ExpectedSha256` wird durchgereicht); README-Changelogs erklären, dass Versionsnummern den Repo-Stand
  bezeichnen und jedes Skript die Nummer seiner letzten Änderung trägt
- `STATE.md`-Risiko „v2.12 noch nicht deployt" auf den aktuellen Branch-Stand gebracht;
  `architecture/PROJECT_LAYOUT.md` Testzahl 117 → 125 (138 gesamt)

### Confidence / Ungeprüft
- Vor dem Push geprüft: alle Commits seit `origin/main` ohne interne Begriffe in hinzugefügten Zeilen,
  Commit-Messages und Dateinamen; keine privaten Dateien versioniert. Bereits vor I1 öffentliche Altlasten
  in der `main`-History (Beispiel-Hostnamen, interne Konfignamen/Pfade, Sample-Zugangsdaten) bleiben dort.

---

## 2026-10-09 I7 – Treiber-Integrität

### Changed
- `Initialize-FirebirdDriver`: **jede** DLL wird vor `Add-Type` per SHA-256 geprüft — frischer Download,
  bereits vorhandene DLL in `%ProgramData%` und per `Firebird.DllPath` konfigurierte DLL (vorher nur Download).
  Zulässig sind die Original-Hashes von `lib\net8.0` und `lib\netstandard2.1` aus dem NuGet-Paket 10.3.4
- Admin-Check als Modulfunktion `Test-SQLSyncIsAdministrator` (in Tests mockbar)
- `ServicePointManager.SecurityProtocol` wird nur für den Download gesetzt und danach wiederhergestellt

### Added
- Optionaler Konfigschlüssel `Firebird.DllSha256` / Parameter `-ExpectedSha256` für eine abweichende DLL
  (dann gilt nur dieser Hash); Schema-Muster `^[A-Fa-f0-9]{64}$`; alle vier Skripte reichen ihn durch
- 10 Pester-Tests (138 gesamt), darunter Download-/Admin-Pfad per Mock

### Security
- Ungeprüftes Laden einer vorhandenen/konfigurierten Treiber-DLL geschlossen (Threat Model Bedrohung 3, S4)
  — praktisch relevant: auf einem Entwicklerrechner gemessen dürfen normale Benutzer im Treiberordner unter
  `%ProgramData%` Dateien anlegen (vererbt `WD,AD`); eine dort abgelegte fremde DLL wäre bisher ungeprüft geladen
  worden. ACL-Härtung als Empfehlung in `operations/SETUP.md`.
- Security-Currency-Sweep (Ereignis-Auslöser): Treiber 10.3.4 weiterhin aktuell, kein Client-Advisory;
  **neuer Befund CVE-2026-40342** (Firebird-Server < 5.0.4, CVSS 9.9: Codeausführung über `CREATE FUNCTION`)
  — Empfehlung Server-Update und Lesekonto statt SYSDBA für den Sync (Risiko in `STATE.md`)

### Iterations-Log
- Referenz-Hashes aus dem offiziellen Paket von nuget.org nachgerechnet (Download in eigenes Scratch-Verzeichnis,
  nur gehasht): `net8.0` = bisheriger Code-Wert, `netstandard2.1` neu; beide identisch mit der lokal
  installierten Paketkopie.
- Rot: „DLL mit falschem Hash wird NICHT geladen" behavioral rot („no exception was thrown") = Lücke S4;
  übrige neue Fälle strukturell rot (Parameter/Funktion fehlten) → Grün mit Implementierung.
- Integrationslauf: Original-DLL über `DllPath` → „geladen (SHA-256 geprüft)", Exit 0; manipulierte Kopie
  (1 Byte angehängt) → Sync Exit 7 vor jeder DB-Verbindung.

### Confidence / Ungeprüft
- Echter Download-Pfad (ohne vorhandene DLL, mit Adminrechten) nicht live gelaufen — nur per Mock.
- Grenze: ist die Assembly in der Sitzung bereits geladen, wird sie ohne Prüfung weiterverwendet.
- `-ExpectedSha256` für eine andere Treiberversion nur per Unit-Test geprüft.

---

## 2026-10-09 Reflexion nach I6 (Phase 1c)

### Changed
- `STATE.md`: „Nächste Reflexion" auf den Abschluss der nächsten drei Inkremente gesetzt (I7, I8, I10 — I9 ist
  bereits vorgezogen erledigt)
- `LESSONS_LEARNED.md`: L6 (neue Fail-Fast-Prüfungen vor Aktivierung gegen den Bestand prüfen)

### Confidence / Ungeprüft
- Struktur-Checks, Health-Check (Hinweis zeigt nur auf offenes I10), Interna-Scan (0 Treffer) und
  semantische Stichprobe (Konfigschlüssel Code ↔ Schema ↔ `CONFIGURATION.md`: einzige Abweichung das
  bekannte `MSSQL.Port`, K9) sauber.
- Advocatus Diaboli: zwei unbelegte Aussagen wurden erst durch Selbstprüfung gefunden (I5-Strategiewahl,
  Subagent-Aussage zum RUNBOOK — beide nachträglich per Lauf belegt bzw. korrigiert); Messfehler
  `grep -c $'\r$'`; Testdatenbank in I4 ungefragt neu angelegt (L4); Doku-Aufwand pro Inkrement weiter
  10–20 Dateien (Backlog „Doku-Duplikate", Kandidat für I10). Der Advocatus-Diaboli-Hook ist weiterhin
  nicht eingerichtet (Freigabe beim Nutzer).
- Template-Backport **nicht durchgeführt** (vollautomatischer Lauf ohne Freigabe). Vorschläge:
  **wichtig:** L3 Mutationsprüfung für Charakterisierungs-/Strukturumbau-Tests → `base/KICKOFF.md` Phase 2
  (zweimal angewendet: I3, I9); **sinnvoll:** L6 → `base/principles/FAIL_FAST.md`; **sinnvoll:** L1
  gitignore-Muster verankern → `base/BOOTSTRAP.md`. Cross-Pollination L3/L6: alle Stacks haben ein echtes
  Analogon (Brownfield-Tests, Konfig-/Schema-Validierung) — idiomatisch prüfen.

---

## 2026-10-09 I6 – Config-Schema-Validierung + gemeinsame Configpfad-Auflösung

### Added
- `Resolve-SQLSyncConfigPath` (Modul): gemeinsame Pfadauflösung (leer → `config.json` im Skriptordner,
  existierender Pfad, Name relativ zum Skriptordner)
- `-ConfigFile` für `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1`
- 10 Pester-Tests (130 gesamt, Coverage 86,52 %)

### Changed
- `Get-SQLSyncConfig -SchemaPath`: Schema-Verstoß wirft (vorher nur Warnung) und nennt den JSON-Pfad je
  Verstoß; Prüfung über `Test-Json -Schema` (in allen PowerShell-7-Versionen verfügbar, `-SchemaFile` ist
  nicht sicher ab 7.0 belegt); fehlende Schema-Datei → nur Warnung
- Alle vier Skripte prüfen gegen `config.schema.json` (Exit 2); Sync v2.15
- `config.schema.json`: Namensmuster an die Identifier-Whitelist angeglichen (vorher nur Großbuchstaben,
  hätte gültige Namen wie `b_kunde` abgelehnt), `maxLength` 63
- `Manage_Config_Tables.ps1` v2.1: Startprüfung über `Get-SQLSyncConfig` statt eigener Whitelist-Prüfung;
  Entfernen der letzten Tabelle wird verweigert (Exit 4)

### Fixed
- `KNOWN_ISSUES.md` K7 (Schema nie geprüft) und K8 (Hilfsskripte fest auf `config.json`); `MSSQL.Port` → neu K9

### Iterations-Log
- Vorab geprüft: Alle vorhandenen lokalen Konfigs (inkl. `config.json`) bestehen das Schema → Fail-Fast
  bricht keine bestehende Konfiguration.
- Rot: `Resolve-SQLSyncConfigPath` per Stub behavioral rot; Schema-Tests „no exception was thrown";
  nach Fail-Fast wurden die Angleichungs-Tests (`b_kunde`, `RDB$X`) rot → Schema-Muster korrigiert → grün.
- Integrationsläufe: schemawidrige Konfig (Typfehler + Tippfehler-Schlüssel) → Sync Exit 2 **vor** jeder
  DB-Verbindung; gültige Konfig Exit 0; `Test-SQLSyncConnections` mit relativem `-ConfigFile` OK;
  `Get_Firebird_Schema` mit `-ConfigFile` OK bzw. Exit 2; `Manage_Config_Tables` Exit 2 ohne Backup.

### Confidence / Ungeprüft
- Nicht getestet: GUI-Pfad von `Manage_Config_Tables.ps1` (Auswahl, Sperre „letzte Tabelle"), nur Parser.
- Schema-Engine von `Test-Json` hat sich in PowerShell 7.4 geändert; geprüft nur unter 7.6.6.
- Messfehler korrigiert: `grep -c $'\r$'` zählt in dieser Shell jede Zeile — frühere Aussagen „Datei ist
  CRLF" waren falsch; tatsächliche CR-Prüfung per `tr -cd '\r' | wc -c`. Commits waren nicht betroffen
  (Diffs ohne Zeilenende-Änderungen).

---

## 2026-10-08 I5 – Typmapping-Datentreue + Modulfunktionen im Hauptskript

### Changed
- `ConvertTo-SqlServerType`: neue Parameter `-Precision`/`-Scale` (aus `NumericPrecision`/`NumericScale`
  des Firebird-Schemas, DBNull erlaubt) → `DECIMAL(p,s)`, p ≤ 38; ohne Schema-Info bisheriger Fallback
  `DECIMAL(18,4)`
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.14: Inline-Typmapping und Inline-Spalten-/Strategieermittlung
  durch `ConvertTo-SqlServerType` bzw. `Get-TableColumnConfig` ersetzt; der `-Parallel`-Block importiert
  dazu das Modul (damit auch `Guid` → `UNIQUEIDENTIFIER`)
- `Get_Firebird_Schema.ps1`: zeigt Precision/Scale und schlägt `DECIMAL(p,s)` vor

### Fixed
- Stiller Präzisionsverlust ab der 5. Nachkommastelle für neu angelegte Staging-/Zieltabellen (`KNOWN_ISSUES.md` K2)

### Iterations-Log
- Vorab-Faktencheck (lesend): Die Demo-Datenbank des Firebird-Testservers hat 915 Spalten mit Scale > 4;
  der Treiber meldet `NumericPrecision`/`NumericScale` korrekt (z. B. 15/6).
- Rot: Parameter zuerst als wirkungsloser Stub → 5 Tests „Expected 'DECIMAL(15,6)' … but … different"
  (behavioral), Grün mit Implementierung; 120/120.
- Integrationslauf Firebird-Testserver → SQL-Testserver (`STAGING_I2TEST`, vorher lesend geprüft, L4):
  Exit 0; Zieltyp `decimal(15,6)` für eine Gewichtsspalte; SUM über 62.523 Zeilen in Firebird und
  SQL Server bis zur 6. Nachkommastelle identisch, 956 Zeilen mit > 4 Nachkommastellen (vorher gerundet).

### Confidence / Ungeprüft
- Nicht geprüft: Precision > 18 (Firebird 4+ INT128) mit echten Daten — die Demo-Datenbank hat nur NUMERIC(15,x);
  nur per Unit-Test.
- **Altbestand:** Der Sync ändert keine bestehenden Tabellen. Vor v2.14 angelegte Zieltabellen behalten
  `DECIMAL(18,4)`; Korrekturprozedur in `operations/RUNBOOK.md`, Risiko in `STATE.md`.
- Strategiewahl über `Get-TableColumnConfig`: Code-Vergleich mit der alten Inline-Logik + zwei Läufe mit dem
  neuen Code — ForceFull (`FullMerge (Forced)`) und inkrementell mit `CleanupOrphans` (0 Zeilen geladen →
  Wasserzeichen greift, Exit 0). Nicht mit neuem Code gelaufen: `Snapshot` (Tabelle ohne ID) und
  `TableOverrides` gegen echte Daten — nur per Unit-Test.

---

## 2026-10-08 I9 – Scheduled-Task-Setup parametrisieren (vor I5 gezogen)

### Changed
- `Setup-ScheduledTasks.ps1`: Installationsordner (Default: Skriptordner), Konfigdateien (`config.json` /
  `config_weekly_full.json`, relativ oder absolut), Tasknamen und Zeitpläne als Parameter; fest
  eingetragene Laufwerkspfade und interne Konfignamen entfernt
- `#Requires -RunAsAdministrator` durch Laufzeitprüfung ersetzt; `SupportsShouldProcess` — `-WhatIf`
  berechnet und zeigt die Task-Definitionen ohne Adminrechte, Passwortabfrage oder Registrierung
- Ausgabe je Task als Objekt (TaskName, Action, Trigger, Settings, Principal, Registered)

### Added
- Ausführungskonto wählbar: `-RunAsUser` (Passwort wird abgefragt) oder `-GmsaAccount` (kein gespeichertes
  Passwort; Grenze: Credential-Manager-Einträge sind kontogebunden)
- `tests/Unit/Setup-ScheduledTasks.Tests.ps1` (13 Tests, nur `-WhatIf`, Registrierung gemockt) — Suite: 111

### Security
- Keine internen Begriffe mehr in versionierten Dateien (Scan aller Dateien gegen `.internal-terms`)
- Tasks können unter einem Dienstkonto/gMSA statt unter einem persönlichen Konto laufen (S13)

### Iterations-Log
- Rot zunächst überwiegend strukturell (`#Requires -RunAsAdministrator` verhinderte jeden Testlauf), nur
  der Test „keine fest eingetragenen Laufwerkspfade" war behavioral rot. Diskriminierung daher per
  Mutationsprüfung belegt: 8/8 Mutationen (Intervall, `IgnoreNew`, `StopAtDurationEnd`, gMSA, relative
  Pfade, `ShouldProcess` umgangen, Wochentag, Default-Konfig) erkannt; keine Aufgabe wurde angelegt.

### Confidence / Ungeprüft
- Kein echter Registrierungslauf mit Adminrechten (weder Benutzer- noch gMSA-Variante); geprüft sind nur die
  berechneten Definitionen unter `-WhatIf`.
- **Verhaltensänderung für bestehende Installationen:** Wer die Tasks neu anlegt, muss Installationsordner
  und Konfignamen jetzt explizit übergeben; bereits registrierte Tasks sind nicht betroffen.

---

## 2026-10-08 Repo-Hygiene – Interna aus dem öffentlichen Repository heraushalten

### Added
- `docs/local/` (gitignored) für interne Umgebungsdoku; `.internal-terms` (gitignored) als Denylist
- `tools/git-hooks/pre-commit`, `commit-msg`, `check-internal-terms.sh`: blocken Commits mit internen
  Begriffen in neuen Zeilen, Dateinamen oder Commit-Message; aktiv über `git config core.hooksPath tools/git-hooks`
- `CONVENTIONS.md` 6.2 „Öffentliches Repository — Interna trennen"; Interna-Scan in `REFLECTION.md`

### Changed
- Öffentliche Docs, READMEs, Schema, `Setup_Credentials.ps1` und Tests: interne Hostnamen, Pfade und
  Credential-Eintragsnamen durch Rollen bzw. fiktive Beispielwerte ersetzt; Versionsangaben einzelner
  interner Server aus Threat Model, Dependency-Audit und STATE entfernt
- `config.sample.json`, `config.schema.json`, READMEs: Beispielserver `SQLSERVER01` / `FIREBIRD01`, Platzhalter-Zugangsdaten
  (vorher realer Servername bzw. realistisch wirkende Werte — bereits vor I1 öffentlich auf `main`)
- Lokale Branch-History (9 Commits seit `721d5e0`, nie gepusht) zu einem bereinigten Commit zusammengefasst;
  die früheren Hashes in `STATE.md`/`TODO.md`/`KNOWN_ISSUES.md` sind durch den neuen Hash ersetzt

### Security
- Noch öffentlich (bereits vor I1 auf `main`): interne Konfignamen und Laufwerkspfade in
  `Setup-ScheduledTasks.ps1` → I9

### Lessons Learned
- Öffentliches Repo: Firmeninterna aus Doku und Commit-Messages heraushalten — Scope: generisch-base
  Backport-Ziel: `base/CONVENTIONS.md` 3.1 u. a. | Status: backported v26 (unreleased, 7ad733e)
  → Spiegel-Eintrag in `LESSONS_LEARNED.md` als `## L5:`.

---

## 2026-10-08 I4 – SQL-Identifier härten

### Added
- `Assert-SqlIdentifier` (exportiert): Whitelist `^[A-Za-z0-9_$]+$`, max. 63 Zeichen (Firebird-Limit)
- `Get-SQLSyncConfig` prüft Fail-Fast (Sync Exit 2): `Tables`, `General.IdColumn`,
  `General.TimestampColumns`, `MSSQL.Database`, `MSSQL.Prefix`/`Suffix`, `TableOverrides`
  (Schlüssel und Werte) sowie Zieltabellenname ≤ 128 Zeichen
- 24 Pester-Tests (insgesamt 98)

### Changed
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.12: alle MSSQL-Tabellennamen in `[...]`;
  `INFORMATION_SCHEMA`-/`sys.indexes`-Abfragen mit `SqlParameter` (`OBJECT_ID(QUOTENAME(@TableName))`);
  `sp_Merge_Generic` als `CommandType.StoredProcedure` mit Parametern; Spaltennamen aus den
  Firebird-Metadaten im `CREATE TABLE` mit `]`-Escaping
- `Manage_Config_Tables.ps1`: Validierung statt „testweisem" `Protect-SqlString`; ungültige
  Tabellennamen werden markiert und nicht übernommen

### Security
- SQL-Identifier-Injection über Konfig-/Metadaten-Namen geschlossen (Threat Model Bedrohung 1, S2)
- Security-Currency-Sweep (Ereignis-Auslöser, KICKOFF 4a): Best Practice Allow-List + Quoting bestätigt;
  **neuer Befund CVE-2026-34232** (Firebird-Server < 5.0.4, unauthentifizierter DoS, CVSS 7.5) —
  eingesetzte Firebird-Server prüfen (Betroffenheit einzelner Hosts nur in `docs/local/`); als Risiko in `STATE.md`, Details `security/DEPENDENCY_AUDIT.md`

### Iterations-Log
- Rot: `Get-SQLSyncConfig`-Tests „Expected an exception … but no exception was thrown" (8 Felder);
  `Assert-SqlIdentifier` erst strukturell rot (Funktion fehlt), dann mit leerem Stub behavioral rot
  („no exception was thrown") → Grün mit Implementierung. Ein Test (128-Zeichen-Grenze) war falsch
  konstruiert (Prefix allein > 63) und wurde korrigiert, nicht der Code.
- Nachgezogen: `MSSQL.Database` (beim Durchsehen gefunden: `CREATE DATABASE [{0}]` ungeprüft) —
  eigener Test, rot, dann grün.

### Confidence / Ungeprüft
- Integrationsläufe gegen Firebird-Testserver → `SQL-Testserver/STAGING_I2TEST`: ForceFull Exit 0 (parametrisierter
  SP-Aufruf mergt 33/7873 Zeilen), inkrementell mit `CleanupOrphans` Exit 0 (Temp-Tabelle
  `[#SourceIDs_*]` fehlerfrei), Fehlerkonfig Exit 10; neue PK-Prüfabfrage lesend gegengeprüft.
- Alle lokalen Konfigs (inkl. `config.json`) bestehen die neue Validierung (geprüft ohne Inhalt auszugeben).
- **Nebenwirkung:** `STAGING_I2TEST` war vom Nutzer bereits gelöscht und wurde vom ersten Testlauf
  im Pre-Flight neu angelegt (vor dem Lauf nicht geprüft).
- Nicht getestet: `Manage_Config_Tables.ps1` (GUI/Out-GridView), nur Parser-Prüfung.
- Firebird-Seite bleibt bei `"..."` ohne Escaping — abgesichert allein durch die Whitelist.

### Lessons Learned
- Vor Integrationsläufen den Zustand der Testumgebung prüfen — Scope: projekt-spezifisch
  Backport-Ziel: keiner | Status: offen
  Der Pre-Flight legt fehlende Datenbanken stillschweigend an; eine bewusst aufgeräumte Testumgebung
  wird so ungefragt wiederhergestellt. Vor jedem schreibenden Testlauf lesend prüfen, ob Ziel-DB/Tabellen
  existieren, und den Nutzer bei Abweichung informieren.
  → Spiegel-Eintrag in `LESSONS_LEARNED.md` als `## L4:`.

---

## 2026-10-08 Reflexion nach I3 (Phase 1c)

### Changed
- `STATE.md`: I3-Commit eingetragen, „Nächste Reflexion" auf I6 hochgezählt
- `BACKLOG.md`: Doku-Duplikate (Exit-Code-Tabelle an 5 Stellen) und drei ID-Systeme als technische Schuld

### Confidence / Ungeprüft
- Struktur-Checks (Verletzung 1–4), Health-Check und Cross-Refs: sauber (`validate_project_docs.sh` Exit 0;
  verbleibende Health-Hinweise zeigen auf offene I6/I10). Semantische Stichprobe: Exit-Codes
  (0/1/2/5/7/9/10/11) und Strategienamen in Doku = Code.
- Advocatus Diaboli: Scope-Erweiterung `CredentialTarget` in I2 war ungeplant, aber durch die Abnahme
  begründet; Doku-Pflegeaufwand pro Änderung zu hoch (→ Backlog).
- Template-Backport **nicht durchgeführt** (vollautomatischer Lauf ohne Freigabe, `REFLECTION.md` Schritt 3):
  Vorschläge — **wichtig:** L3 Mutationsprüfung für Charakterisierungstests → `base/KICKOFF.md` Phase 2
  (TDD-Startregel, Ausnahme „Erster-Lauf-grün"); Cross-Pollination: `python-*`/`csharp-*` haben ein
  echtes Analogon (Brownfield-Testharness), idiomatisch prüfen. **sinnvoll:** L1 gitignore-Muster
  verankern → `base/BOOTSTRAP.md` + Check `git check-ignore` in `scripts/validate_project_docs.sh`.
  **sinnvoll:** `stacks/powershell-automation` conditional `architecture/DATABASE.md` (siehe `BACKLOG.md`
  Stack-Lücken). L2 bleibt projektspezifisch. Alle drei Lessons behalten `Status: offen`.

---

## 2026-10-08 I3 – Pester-Testharness + Unit-Tests für SQLSyncCommon.psm1

### Added
- `tests/Unit/SQLSyncCommon.Tests.ps1` von 16 auf 74 Tests erweitert; jede exportierte Funktion
  des Moduls hat mindestens einen Test (inkl. `Get-StoredCredential` nur lesend und
  `Initialize-FirebirdDriver` mit Mocks für `Test-Path`/`Add-Type`/`Invoke-WebRequest`)
- `tests/RequiredModules.psd1` (Pester 5.7.1 gepinnt) und `tests/pester.config.ps1`
  (Coverage auf `SQLSyncCommon.psm1`, Ziel 80 %, Exit 1 bei rotem Test oder Unterschreitung)

### Changed
- Gemeinsame DoD in `TODO.md`: Testbefehl `pwsh -NoProfile -File ./tests/pester.config.ps1`
- Fachdoku (Unit-/Integrationstests, Konventionen, Layout, Abhängigkeiten, Threat Model S10)

### Iterations-Log
- Charakterisierungstests für bestehenden Code sind beim ersten Lauf erwartbar grün (74/74).
  Diskriminierung stattdessen per **Mutationsprüfung** belegt: 13 gezielte Fehler in einer Kopie
  des Moduls (Typmapping, Strategiewahl, Passwort-Maskierung FB/MSSQL, `Get-ConfigValue` mit
  `false`, Close ohne Dispose, Default `GlobalTimeout`, Integrated Security, Log-Farbe,
  SQL-Escaping, Admin-Check, Tables-Validierung, `CredentialTarget`) → 13/13 von mindestens einem
  Test erkannt. Zwei Mutationen griffen im ersten Anlauf wegen eines falschen Suchmusters nicht
  und wurden mit verankerten Mustern nachgeholt.
- Coverage gemessen: 82,54 % (315 Kommandos) → Ziel 80 % festgelegt.

### Confidence / Ungeprüft
- (a) Nicht getestet: Download-/Hash-Pfad von `Initialize-FirebirdDriver` (innerer Admin-Check
  nicht mockbar, ein echter Download wäre nötig) — mit I7 testbar machen; der Test „ohne Admin →
  throw" wird bei Ausführung mit Adminrechten übersprungen.
- (b) `Get-StoredCredential` liest den echten Credential Manager (nur Abfrage eines zufälligen,
  nicht existierenden Eintrags) — läuft nur unter Windows.
- (c) Einstiegsskripte haben weiterhin keine Unit-Tests (Inline-Logik, Integration).

### Lessons Learned
- Mutationsprüfung für Charakterisierungstests — Scope: generisch-base
  Backport-Ziel: `base/principles/` bzw. KICKOFF Phase 2 „TDD-Startregel" (Ausnahme „Erster-Lauf-grün")
  | Status: offen
  Tests, die bestehendes Verhalten festschreiben, sind beim ersten Lauf zwangsläufig grün; die
  Regel „erster Lauf grün → stoppen" passt dort nicht. Ersatznachweis: pro Funktion einen
  gezielten Fehler in eine Kopie einbauen und rot sehen.
  → Spiegel-Eintrag in `LESSONS_LEARNED.md` als `## L3:`.

---

## 2026-10-08 I2 abgeschlossen – Abnahme über die Aufgabenplanung

### Changed
- I2 in `TODO.md` nach „Abgeschlossen", `STATE.md` (I2 in Tabelle, nächster Schritt I3),
  `KNOWN_ISSUES.md` K1 nach „Behobene Probleme"; „Abnahme offen"-Vermerke in der Fachdoku entfernt

### Confidence / Ungeprüft
- Abnahmepunkt 3 vom Nutzer ausgeführt: Test-Task `SQLSync_I2_Abnahme` (Interactive, eigenes
  Konto) mit `config_i2test_fehler.json` → `LastTaskResult` 10 (`0xA`); Log
  `Sync_config_i2test_fehler_2026-10-08_1818.log` endet mit „ERGEBNIS: FEHLER (Exit-Code 10)".
- Nicht geprüft: Exit 11 (Sanity „FEHLER") in einem echten Lauf — nur per Unit-Test.
- Der Test-Task ist noch registriert (Aufräumen siehe `STATE.md`).

### Lessons Learned
- Log-Rotation in Testkonfigs abschalten — Scope: projekt-spezifisch
  Backport-Ziel: keiner | Status: offen
  Eine aus einer Produktivkonfig abgeleitete Testkonfig erbt `DeleteLogOlderThanDays` und löscht
  beim ersten Lauf alte Logs im Skriptordner. Testkonfigs mit `DeleteLogOlderThanDays: 0` anlegen.
  → Spiegel-Eintrag in `LESSONS_LEARNED.md` als `## L2:`.

---

## 2026-10-08 I2 (Nachtrag) – Abnahmeläufe + konfigurierbare Credential-Targets

### Added
- Optionaler Konfigschlüssel `MSSQL.CredentialTarget` / `Firebird.CredentialTarget` (Default
  `SQLSync_MSSQL` / `SQLSync_Firebird`): eigener Credential-Manager-Eintrag pro Server, nötig
  für denselben Benutzer (`sa`) mit unterschiedlichen Passwörtern auf Prod- und Testserver
- `Setup_Credentials.ps1 -MSSQLTarget <Name> / -FirebirdTarget <Name>`
- 5 Pester-Tests (insgesamt 16)

### Changed
- Log und Fehlermeldung nennen den verwendeten bzw. gesuchten Credential-Manager-Eintrag

### Confidence / Ungeprüft
- Abnahme I2 am 2026-10-08 gegen Firebird-Testserver/Demo-Datenbank → SQL-Testserver/`STAGING_I2TEST`:
  Lauf ohne Fehler Exit 0, Lauf mit nicht existierender Tabelle Exit 10 (übrige Tabellen
  synchronisiert). Nicht geprüft: „Letztes Ausführungsergebnis" in der Aufgabenplanung.
- Nebenwirkung beim ersten Testlauf: Die Log-Rotation der Testkonfig (`DeleteLogOlderThanDays: 30`)
  hat 7 alte `Sync_*.log` im lokalen `Logs\` gelöscht (gitignored, nur lokale Arbeitskopie);
  danach in den Testkonfigs auf 0 gesetzt.
- Der neue Credential-Target-Pfad ist über den echten Lauf belegt (Log:
  „Credential Manager (SQLSync_MSSQL_sqltest)"); `Setup_Credentials.ps1` mit Parameter wurde
  vom Nutzer interaktiv ausgeführt.

---

## 2026-10-08 I2 – Fehlschläge sichtbar machen (Code umgesetzt, Abnahme offen)

### Added
- `Get-SyncExitCode` in `SQLSyncCommon.psm1` (exportiert): 0 = OK, 10 = mindestens eine Tabelle
  mit Status „Fehler", keine oder zu wenige Ergebnisse (`-ExpectedTableCount`), 11 = Sanity „FEHLER" ohne Tabellenfehler
- Konfigschlüssel `General.FailOnSanityError` (Default `true`) in `Get-SQLSyncConfig`,
  `config.schema.json` und `config.sample.json`
- Erste Pester-5-Tests: `tests/Unit/SQLSyncCommon.Tests.ps1` (11 Tests)
- Exit-Code-Tabelle in `README.md` / `README.de.md` und in der Skript-Hilfe

### Changed
- `Sync_Firebird_MSSQL_AutoSchema.ps1` v2.11: endet nach Zusammenfassung, Log-Rotation und
  `Stop-Transcript` mit `exit $ExitCode` und schreibt eine Zeile „ERGEBNIS: …" mit den
  betroffenen Tabellen
- Fehler beim Ausführen eines Batches aus `sql_server_setup.sql` brechen den Pre-Flight ab
  (Exit 9) statt nur gewarnt zu werden; „Database … already exists" wird weiter ignoriert
- Fachdoku (Error-Handling, Monitoring, Runbook, Task Scheduler, Feature, Threat Model, Tests)
  an die neuen Exit-Codes angepasst

### Fixed
- Task Scheduler meldete Erfolg, obwohl Tabellen fehlgeschlagen waren (`KNOWN_ISSUES.md` K1)

### Confidence / Ungeprüft
- (a) Nicht getestet: kein Lauf gegen echte Firebird-/SQL-Server-Instanzen; insbesondere
  `exit $ExitCode` am Skriptende, der neue Pre-Flight-Abbruch und das „Letzte
  Ausführungsergebnis" in der Aufgabenplanung sind nur per Code-Review und Parser-Prüfung
  verifiziert. Getestet ist die Entscheidungslogik (`Get-SyncExitCode`) per Pester.
- (b) Annahme: `sql_server_setup.sql` enthält außer `CREATE OR ALTER PROCEDURE` nur
  auskommentierte Batches; eine Warnung, die bisher stillschweigend durchging, bricht jetzt ab.
- (b) Annahme: Sanity „FEHLER" ist in der Praxis selten; bei laufenden Schreibzugriffen in
  Firebird zwischen Merge und Zählung können Fehlalarme (Exit 11) entstehen →
  `FailOnSanityError: false` als Ausweg (Risiko in `STATE.md`).
- (c) Der Advocatus-Diaboli-Hook aus KICKOFF Phase 1 Punkt 7 ist **nicht** eingerichtet
  (Anlage von `.claude/settings.json` wurde von der Auto-Mode-Prüfung blockiert); das Gate
  wurde manuell angewendet.

---

## 2026-10-08 I1 – docs/ initialisiert

### Added
- `docs/` aus docs_template v26 (Basis-Layer + Stack `powershell-automation`, keine Overlays)
- Conditional-Dateien `operations/TASK_SCHEDULER.md` (Projekt nutzt `Register-ScheduledTask`)
  und `testing/INTEGRATION_TESTS.md` (Firebird/SQL Server als externe Systeme) übernommen
- Hauptfeature-Dokumentation `features/firebird-mssql-sync.md`
- Inkrementplan I2–I10 in `TODO.md` auf Basis der Code-Analyse (Stand `721d5e0`)

### Changed
- `.gitignore`: Muster `config*` auf das Root-Verzeichnis verankert (`/config*`), weil es
  wegen `core.ignorecase=true` sonst auch `docs/architecture/CONFIGURATION.md` ignoriert hätte;
  `*.bak`, Secret-Dateitypen, Treiber-/Paketdateien und Test-Artefakte ergänzt

### Removed
- `architecture/DOMAIN_MODEL.md` (keine fachliche Domäne über Sync-Strategien hinaus) und
  `architecture/REMOTE_EXECUTION.md` (kein `Invoke-Command`/`New-PSSession`/SSH) nach Prüfung
  der Bedingungen aus `MANIFEST.yaml` nicht übernommen

### Security
- Bei der Analyse gefunden und in `security/THREAT_MODEL.md` / `TODO.md` erfasst:
  SQL-Identifier-Interpolation (I4), Klartext-Passwort-Fallback und interne Namen im Repo (I9),
  ungeprüfte Treiber-DLL bei vorhandener Datei (I7). Keine Secrets in `docs/` übernommen;
  lokale `config.json`/`*.bak` wurden bewusst nicht gelesen.

### Confidence / Ungeprüft
- Keine Skripte ausgeführt (keine Testumgebung mit Firebird/SQL Server); alle Aussagen zum
  Laufzeitverhalten stammen aus dem Lesen des Codes.
- Präzisionsverlust bei `DECIMAL(18,4)` (K2) und Wasserzeichen-Lücke (K3) sind aus dem Code
  abgeleitet, nicht mit echten Daten reproduziert.

### Lessons Learned
- Unverankerte gitignore-Muster bei case-insensitivem Dateisystem — Scope: generisch-base
  Backport-Ziel: `base/BOOTSTRAP.md` (Abschnitt `.gitignore`) | Status: offen
  Ein Muster wie `config*` ohne führendes `/` trifft unter Windows (`core.ignorecase=true`)
  auch `docs/architecture/CONFIGURATION.md`; vor dem ersten docs-Commit `git check-ignore` laufen lassen.
  → Spiegel-Eintrag in `LESSONS_LEARNED.md` als `## L1:`.
