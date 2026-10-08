# Changelog – PSFirebirdToMSSQL

Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/).
Einträge chronologisch absteigend (neueste oben). Jeder Eintrag entspricht
genau einem Inkrement (= einem Commit oder einer eng zusammengehörigen
Commit-Serie).

Nicht alle Sektionen sind in jedem Eintrag nötig — leere Sektionen weglassen.

Die Versionshistorie vor Einführung von `docs/` (v2.1 bis v2.10) steht im
Abschnitt „Changelog" von `README.md`.

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
