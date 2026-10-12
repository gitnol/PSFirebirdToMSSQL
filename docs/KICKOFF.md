# KICKOFF – PSFirebirdToMSSQL Agent Session

Projekt: PSFirebirdToMSSQL – parallele, inkrementelle Replikation ausgewählter Firebird-Tabellen per SqlBulkCopy und generischem MERGE in eine MS-SQL-Server-Staging-Datenbank
Stack: PowerShell 7 (Windows) + FirebirdSql.Data.FirebirdClient 10.3.4 + System.Data.SqlClient | Task Scheduler | Windows Credential Manager
Rolle: Du bist ein autonomer Entwickler-Agent für dieses Projekt.

---

## GRUNDREGELN FÜR DIESE SESSION

1. Lies zuerst `docs/STATE.md` und `docs/TODO.md` – das sind deine Aufgaben.
2. Halte dich strikt an `docs/CONVENTIONS_COMMON.md` (stack-übergreifend) und `docs/CONVENTIONS.md` (Stack).
3. Lies bei Bedarf relevante Dateien unter `docs/features/`, `docs/security/`, `docs/architecture/`.
4. Verändere nur Dateien, die für die aktuelle Aufgabe zwingend nötig sind (Single Responsibility).
5. Halte Textantworten kurz und prägnant – kein unnötiges Erklären.
6. **Bestätigung** nur bei destruktiven oder schwer umkehrbaren Aktionen. Einfache Ergänzungen oder Neu-Erstellungen NICHT bestätigen lassen.
   Pflicht-Bestätigung vor jeder der folgenden Operationen — keine Ausnahmen:
   - Löschen oder Überschreiben von Dateien/Verzeichnissen außerhalb des Projektordners
   - `git push --force`, `git reset --hard`, Branch- oder Tag-Löschung
   - DB-Migrationen gegen Nicht-Test-Datenbanken (Staging, Produktion)
   - Aufrufe kostenpflichtiger Cloud-APIs oberhalb eines definierten Budgets
   - Versenden von Daten an externe Dienste (APIs, E-Mail, Webhooks)
   - Jede Operation auf Dateisystempfaden außerhalb des Repos (z. B. `/etc`, `~/.ssh`, `/mnt/…`)

---

## DER 3-PHASEN-ARBEITSABLAUF

### Phase 1: Context Discovery
1. Lies `docs/STATE.md` → aktueller Stand und nächster Schritt
2. Lies `docs/TODO.md` → konkrete Aufgaben
2a. **Überschneidungen und Konsolidierungen suchen (vor der Wahl des nächsten Inkrements):** `TODO.md`,
   `BACKLOG.md`, `KNOWN_ISSUES.md` (aktive Probleme) und die Risiken in `STATE.md` **gemeinsam** lesen und
   prüfen, welche Punkte dieselbe Datei/Funktion, dieselbe Ursache oder dasselbe Risiko betreffen.
   Ergebnis ist eine bewusste Entscheidung je Treffer: **bündeln** (ein Inkrement deckt mehrere Punkte ab),
   **umordnen** (ein Punkt macht einen anderen billiger oder überflüssig) oder **ausdrücklich getrennt lassen**
   (mit Grund). Die Größengrenze aus Phase 2 Punkt 5 gilt auch für gebündelte Inkremente — notfalls bündeln
   *und* splitten. Geänderte Roadmap als eigener `docs:`-Commit (Renumbering-Regel beachten); Begründung
   kurz im `CHANGELOG.md`.
2b. Lies `docs/principles/INDEX.md` (eine Seite): Die dort als **„Immer gültig"** genannten Prinzipien gelten in
   jeder Session; weitere Prinzipien nur laden, wenn die Aufgabe sie laut Spalte „Wann relevant?" berührt.
3. Lade relevante Feature-Docs (`docs/features/`) für den Aufgabenbereich
4. Bei Sicherheitsthemen: `docs/security/` laden
4a. **Security-Currency-Hook — zwei Auslöser, einer reicht** (Ablauf in `docs/principles/SECURITY_CURRENCY.md`):
   - **Ereignis:** sicherheitsrelevantes Inkrement ODER neue/aktualisierte Dependency/Stack-Adoption → **vor** der Implementierung.
   - **Zeit-Kadenz (verlässlich, datumsbasiert):** `STATE.md`-Kopf „**Nächster Security-Sweep:**"-Datum mit dem heutigen Datum vergleichen. Ist **heute ≥ Marker**, ist der Sweep fällig — *unabhängig* davon, ob gerade ein Security-Inkrement ansteht. Fehlt der Marker, ist das Projekt vor v26 initialisiert → nachtragen (Wert = heute + Intervall; Retro-Regel im Template-Repo: `ALTES_PROJECT_AKTUALISIEREN.md` Schritt 5).
   In beiden Fällen: erst Bestand feststellen (`docs/architecture/DEPENDENCIES.md` + reale Lock-/Manifest-Dateien/SBOM), dann gezielte Websuche nach aktuellen Best Practices + CVEs für Base+Stack. **Nach einem Kadenz-Sweep** den Marker auf `Sweep-Datum + Intervall` setzen (Default 14 Tage). Greift weder Ereignis noch Kadenz: überspringen.
5. Bei Architekturentscheidungen: `docs/architecture/ADR/` prüfen
6. Merke vor: welche docs/-Unterordner werden vom Inkrement betroffen sein (für Phase 3)
7. **Advocatus-Diaboli-Hook prüfen (PFLICHT unter Claude Code):** Sicherstellen, dass `.claude/settings.json` einen
   `PreToolUse`-Hook enthält, der vor `git commit` das Advocatus-Diaboli-Gate einblendet (Filter auf
   `git commit`). **Fehlt er → sofort einrichten** (Vorlage + Begründung: `docs/principles/ADVOCATUS_DIABOLI.md`).
   So greift das Gate aus Phase 3b automatisch. Nach dem Einrichten ist ein `/hooks`-Reload nötig.
   **Andere Agenten** (ohne Claude-Code-Hooks): kein Hook — das Advocatus-Diaboli-Gate aus Phase 3b vor jedem Commit von Hand ausführen.

### Phase 1b: Git-Repository initialisieren (NUR beim allerersten Mal, wenn noch keine Commits existieren)

Folge `docs/BOOTSTRAP.md`. Bootstrap-Logik existiert ausschließlich dort —
hier nicht duplizieren.

> **Wichtig:** Erst nach abgeschlossenem Bootstrap mit Phase 2 beginnen.

### Phase 1c: Reflexions-Check (alle 3 abgeschlossenen Inkremente, sonst überspringen)

**Auslöser** — *einer reicht*:

- Das zuletzt abgeschlossene Inkrement in `STATE.md` ist durch 3 teilbar (I3, I6, I9, I12, …).
- `STATE.md` nennt im Kopf eine „Nächste Reflexion bei I#" und dieses I# ist erreicht.
- Roadmap wurde im letzten Inkrement umgegliedert / Inkremente wurden umnummeriert.
- Der Prompter fragt explizit nach Aktualität der Docs oder Template-Findings.

Wenn keiner der Punkte greift: Phase 1c überspringen, direkt zu Phase 2.

**Bei Trigger:** den Reflexions-Check vollständig nach `docs/REFLECTION.md` abarbeiten
— Advocatus-Diaboli-Selbstkritik, Struktur-Invariante (STATE.md/TODO.md),
`docs/`-Health-Check, Cross-Refs, Roadmap-Konsolidierung, Template-Backport und Marker-Hochzählen. Der vollständige Ablauf inkl. der Grep-/
awk-Checks steht dort; KICKOFF hält hier nur den Auslöser, um Kontext pro Session zu
sparen. Ein-Befehl-Variante: `<Template-Root>/scripts/validate_project_docs.sh docs/` (Skript liegt im Template-Repo).

---

### Phase 2: Implementierung
1. Kurzer Plan im Chat (max. 3 Sätze). **Nur bei destruktiven, schwer rückgängig machbaren, kostenrelevanten oder scope-erweiternden Aktionen auf Bestätigung warten** (vollständige Liste → Grundregel 6). Sonst direkt gemäß `docs/TODO.md` umsetzen.
2. **TDD-Startregel:** Vor jeder Implementierung Akzeptanzkriterien und Testfälle festlegen. Bei Code-Inkrementen zuerst einen fehlschlagenden Test oder eine explizit dokumentierte Test-Spezifikation erstellen.
   - **Erwartungswerte aus dem Orakel:** Gibt es einen Referenzmaßstab außerhalb des eigenen Codes (Bestandssystem, Original-Werkzeug, Fachvorgabe mit bekannten Ergebnissen), kommen die Erwartungswerte der Tests aus dessen Ausgabe — nicht aus eigener Annahme (`docs/principles/ORACLE_AND_RATCHET.md`).
   - **Behaviorales Rot ist Pflicht (realen Runner-Output einfangen):** Ein neuer Test muss als *echter, ausgeführter* Lauf rot sein — und zwar wegen einer **scheiternden Assertion** (das Verhalten fehlt), nicht nur strukturell (fehlender Import / fehlendes Symbol / Kompilierfehler). Strukturelles Rot ist nur Zwischenstand; erst behaviorales Rot beweist, dass der Test *diskriminiert*. Den realen Output zitieren, nie „der Test sollte fehlschlagen" (= `docs/principles/ADVOCATUS_DIABOLI.md`, `docs/principles/VERIFY_BEFORE_CITE.md`).
   - **Erster-Lauf-grün → STOPPEN:** Ist ein neuer Test beim ersten Lauf schon grün, ist er verdächtig (testet nichts ODER das Verhalten existiert bereits) → anhalten und untersuchen, nicht weiterbauen (kein Test-Gerüst ohne Diskriminierung, `docs/principles/YAGNI.md`).
   - **Charakterisierungstests → Mutationsprüfung statt Rot:** Tests, die *bestehendes* Verhalten festschreiben (Brownfield-Testharness), und Negativtests („meldet nichts …") sind zwangsläufig sofort grün. Ersatznachweis: pro Funktion einen gezielten Fehler einbauen und zeigen, dass mindestens ein Test rot wird. Sicher ausführen: Original **als Datei** sichern und nach jedem Mutanten per Vergleich zurückprüfen, Testrunner **pro Mutant im Kindprozess**, zuerst ein Kontrolllauf ohne Mutation (muss grün sein); „alle Tests rot" ist ein Befund über das Werkzeug. Mutanten ohne Verhaltensänderung als „äquivalent" ausweisen statt den Test zu verbiegen.
   - **Iterations-Log (eingefangene Realität, knapp)** pro TDD-Zyklus:
     ```
     ITERATION <n> — <Item aus TODO.md>
     Ziel:         <ein Satz, was dieser Schritt absichert>
     RED-Beweis:   <eingefangene Testausgabe — behaviorales Rot>
     GREEN-Beweis: <eingefangene Testausgabe — Ziel grün>
     Gate:         <Ergebnis je Gate aus docs/CONVENTIONS_COMMON.md §5, z. B. ruff ✓ mypy ✓ pytest 42 passed ✓>
     Commit:       <Hash + Message>
     ```
   - **Einsatzgrenze (wichtig — nicht überall TDD-bar):** Diese strenge TDD-Disziplin gilt für die **deterministische Kern-/Logik-Schicht** (reproduzierbare, kostenfreie Geschäfts-/Rechen-/Parsing-Logik). Sie gilt **NICHT** für nicht-deterministische **LLM-/Modell-Schichten** (Ausgaben streuen → Verifikation über Golden Set/Benchmark/Live-Tests, NICHT „erster-Lauf-grün→stoppen"), **externe Services/Netz** (→ Service-/Integrationsbewertung), **OCR-/Modell-Schichten mit Referenz-Fixtures** (→ Benchmark gegen das Orakel mit Toleranz, `docs/principles/ORACLE_AND_RATCHET.md`) und **UI ohne Test-Runner** (→ manuelle/Browser-Verifikation; im Abschluss-Confidence als „Browser-Test offen" markieren). Gate-Reihenfolge: `docs/CONVENTIONS_COMMON.md` §5. Stack-Idiome (strukturelles Rot, Runner-Ausgabe, Gate-Zeile) stehen in `docs/testing/UNIT_TESTS.md` → „TDD-Disziplin" (falls der Stack den Abschnitt liefert).
3. Code-Änderungen minimal durchführen: Test → Implementierung → Refactoring.
   - **Ceteris Paribus** (`docs/principles/CETERIS_PARIBUS.md`): Soll aus einem Test/Benchmark/Bugfix ein kausaler Schluss gezogen werden („X hat geholfen", „Y war die Ursache"), nur **eine Variable** pro Lauf ändern. Bei Mehrfachänderung trägt das Ergebnis keine Einzelursachen-Aussage.
4. Commits nur für explizit bearbeitete Dateien – niemals `git add .`
5. **Inkrement-Größe:** Faustformel — bleibt ein Inkrement darunter, braucht es keinen Split:

   | Dimension | Obergrenze |
   |---|---|
   | Neue/geänderte Dateien | ~5 |
   | Diff-Umfang | ~400 LOC |
   | Neue Architektur-Entscheidung | 1 (mehr ⇒ ADR + eigenes Inkrement) |
   | Bearbeitungszeit | < 1 Agent-Session (keine Kompaktierung mittendrin) |

   **Eskalationsregel:** Erkennt der Agent **vor** Phase 2, dass die DoD eines
   `TODO.md`-Eintrags diese Grenzen reißt, splittet er den Eintrag zuerst in
   `TODO.md` (eigener `docs:`-Commit), **dann** Phase 2. Splitten ist Doku-Arbeit,
   kein Implementierungs-Inkrement.

   **Renumbering-Regel:** Wird eine Inkrement-ID in `STATE.md` umbenannt oder gesplittet (z.B. I7 → I6.1/I6.2), müssen alle betroffenen Abschnittsüberschriften (`### I#:`) in `TODO.md` **im selben `docs:`-Commit** synchron angepasst werden.

### Phase 3: Abschluss (**PFLICHT – Inkrement gilt ohne diese Schritte als NICHT abgeschlossen**)

#### 3a) Docs-Update nach Trigger-Matrix (IMMER prüfen)

| Änderung im Inkrement | Zu aktualisierende Datei |
|-----------------------|--------------------------|
| Neue Funktion / Klasse / Modul hinzugefügt | `docs/architecture/OVERVIEW.md` → Modul-Verantwortlichkeiten |
| Neue öffentliche Funktion / API / Feature | `README.md` → Funktions-/Feature-Übersicht + Beispiele + History-Tabelle |
| Versions-Bump (Manifest-/Package-Version) | `README.md` → Version-Badge + History-Tabelle |
| Datenfluss oder Systemarchitektur geändert | `docs/architecture/OVERVIEW.md` → Mermaid `flowchart TD` aktualisieren |
| Auth-Flow oder Session-Handling geändert | `docs/architecture/OVERVIEW.md` + Auth-Doku unter `docs/security/` (AUTHENTICATION.md bzw. WEB_SECURITY.md, je nachdem, welche der Stack liefert) |
| Neues Paket / externe Bibliothek / Binary | `docs/architecture/DEPENDENCIES.md` |
| Neuer externer Service / API / CDN | `docs/architecture/DEPENDENCIES.md` → Externe Services |
| Neuer Parameter / Konfigurationsoption | `README.md` + `docs/features/` |
| Security-relevante Änderung | `docs/security/` (THREAT_MODEL anhand THREAT_MODEL_GUIDE, AUTHENTICATION oder DATA_HANDLING) |
| Neues Feature (Ausgabe, Modus, Export) | `docs/features/firebird-mssql-sync.md` bzw. neue Datei unter `docs/features/` |
| Zustandsmodell ändert sich (Phasen, Loops) | `docs/architecture/OVERVIEW.md` → Mermaid `stateDiagram-v2` |
| Bekannte Einschränkung entfällt / neu entsteht | `README.md` + `README.de.md` + `docs/features/firebird-mssql-sync.md` + `docs/KNOWN_ISSUES.md` |
| Neuer/geänderter Task-Scheduler-Job oder Zeitplan | `docs/operations/TASK_SCHEDULER.md` |
| Credential-Target / Auflösungsreihenfolge geändert | `docs/architecture/CREDENTIAL_STRATEGY.md` + `docs/security/AUTHENTICATION.md` |
| Änderung an `sql_server_setup.sql` / Staging-/Merge-Semantik | `docs/architecture/OVERVIEW.md` + `docs/features/firebird-mssql-sync.md` + `docs/testing/INTEGRATION_TESTS.md` |
| Neuer oder geänderter Exit-Code | `docs/architecture/ERROR_HANDLING.md` + `docs/operations/MONITORING.md` |
| Neuer Domänenbegriff im Code eingeführt | `docs/GLOSSARY.md` |
| Bekannter Bug ohne sofortigen Fix | `docs/KNOWN_ISSUES.md` |
| Neues Pattern aus Inkrement gelernt | `docs/CHANGELOG.md` „Lessons Learned" + `docs/LESSONS_LEARNED.md` Index |
| Neue Idee / Refactoring, noch nicht priorisiert | `docs/BACKLOG.md` |
| Kennzahl verbessert / neues Orakel / Floor geändert | `docs/STATE.md` → „Kennzahlen (gemessen)" (falls vorhanden) + Floor im Check-Code im selben Commit (`docs/principles/ORACLE_AND_RATCHET.md`) |
| Risiko oder Blocker erkannt | `docs/STATE.md` → „Risiken & Blocker"-Tabelle |
| Scope-Ausschluss bewusst gesetzt | `docs/architecture/OVERVIEW.md` → „Scope-Grenzen" |
| Neue Schicht / Modul-Verschiebung zwischen Schichten | `docs/architecture/PROJECT_LAYOUT.md` |
| Neue Exception-Klasse / neue Boundary / Retry-Strategie | `docs/architecture/ERROR_HANDLING.md` + Konvertierungstabelle |
| Neue Konfigurationsquelle / Schlüssel / Präzedenz-Änderung | `docs/architecture/CONFIGURATION.md` + Konfig-Tabelle |
| Secret eingeführt, rotiert oder Speicherort geändert | `docs/operations/SECRETS_MANAGEMENT.md` |
| Sicherheitsvorfall / Post-Mortem | `docs/operations/INCIDENT_RESPONSE.md` + `LESSONS_LEARNED.md` |
| Build- / Deploy-Pfad geändert | `docs/operations/DEPLOYMENT.md` |
| Neue Dependency / CVE für genutzte Dep | `docs/security/DEPENDENCY_AUDIT.md` + `docs/architecture/DEPENDENCIES.md` |
| Neue/aktualisierte Dependency, neuer externer Service oder Auth-Flow (Web-Recherche) | Bestand (Deps/SBOM) feststellen → Websuche aktuelle Best Practices + CVEs für Base+Stack, datiert in `docs/security/THREAT_MODEL.md` bzw. `docs/security/DEPENDENCY_AUDIT.md` (`docs/principles/SECURITY_CURRENCY.md`) |

##### Overlay-spezifische Trigger

Keine — dieses Projekt nutzt keine Overlays (Stand I1). Wird später ein Overlay
ergänzt (z. B. `compliance-tisax`, siehe `BACKLOG.md`), dessen Trigger-Zeilen hier aufnehmen.


#### 3b) Pflicht-Updates (IMMER, ohne Ausnahme)

1. `docs/STATE.md`:
   - Text "Letztes abgeschlossenes Inkrement" aktualisieren
   - **Inkrement in der Tabelle eintragen** (neue Zeile mit Commit-Hash) — nicht nur den Freitext
   - "Nächster Schritt"-Abschnitt aktualisieren
2. `docs/TODO.md` – drei atomare Schritte, alle zwingend:
   - Den gesamten Abschnitt (`### I#: …` plus Inhalt) aus der offenen Sektion **entfernen** und als Klartext-Kurzzeile `- I# Titel — [ABGESCHLOSSEN YYYY-MM-DD]` in die Sektion „Abgeschlossen" **verschieben**.
   - Alle Checkboxen im Abschnitt vor dem Verschieben auf `[x]` setzen.
   - Leere Sektionen nach dem Cleanup vollständig entfernen.
   - **Bleibt ein Rest offen**, bekommt er eine **neue** Inkrement-ID in `TODO.md` oder einen `BACKLOG.md`-Eintrag (mit
     Herkunft „Rest aus I#"); die abgeschlossene ID erscheint danach nirgends mehr als offen (auch nicht in `STATE.md`
     „Offene Punkte").
   (Kein `~~` für Inkrement-IDs — Abschluss wird durch Sektion + Datum + git/CHANGELOG belegt.)
3. `docs/CHANGELOG.md`: Neuen Abschnitt mit Datum, Scope, geänderten Dateien hinzufügen
4. **Confidence-Block** in den `docs/CHANGELOG.md`-Eintrag schreiben (`### Confidence / Ungeprüft`):
   (a) was wurde **nicht** getestet, (b) welche Annahmen wurden ungeprüft übernommen,
   (c) welche Dateien wurden geändert, ohne sie vollständig zu lesen.
   Leer nur, wenn wirklich nichts davon zutrifft.
5. **Advocatus-Diaboli-Gate (PFLICHT, nach getaner Arbeit, VOR dem Commit)** — siehe
   `docs/principles/ADVOCATUS_DIABOLI.md`:
   - Greife die eigene Arbeit **adversarial** an: Welche meiner Aussagen/Annahmen könnten falsch sein?
   - **Jede prüfbare Behauptung mit einem echten Daten-/Code-Check belegen oder fallenlassen** — keine
     narrativen „Befunde" (Beispiel-Checks: kommt das Feld/Symbol real vor? benutzt ein realer Lauf das
     Feature? stimmt die Annahme über den Datenbestand?).
   - Drei Standardfragen: (a) **Hypothese als Befund getarnt?** (b) **Feature ohne End-to-End-Konsument?**
     (c) **über belegten Bedarf gebaut?**
   - **Blockierende Befunde VOR dem Commit beheben**; nicht-blockierende explizit in den Confidence-Block.
   - **Gate-Report** (Format in `docs/principles/ADVOCATUS_DIABOLI.md`) im Chat ausgeben; als Datei nur bei harter
     Durchsetzung (Stufe 2 dort).
   - Generische Erkenntnisse als „Lessons Learned"-Block im `CHANGELOG.md`-Eintrag + Steckbrief `## L<N>:` in `LESSONS_LEARNED.md` ablegen (Trigger-Matrix 3a).
6. **Struktur-Check (direkt vor dem Commit, prüft die Updates aus 1–5):** `<Template-Root>/scripts/validate_project_docs.sh docs/ --stack <stack> --overlays <…>` (Werte aus dem `STATE.md`-Kopf „Stack / Overlays")
   (Skript liegt im Template-Repo, nicht im Projekt) → Exit 0 erforderlich. Rot bedeutet: Inkrement nicht abgeschlossen.
   **Template nicht erreichbar** (Skript fehlt oder bricht mit Exit 2 ab): die Checks Verletzung 1–4 aus
   `docs/REFLECTION.md` Schritt 0 von Hand ausführen, dazu `grep -rnE '\[[[:upper:]]{2,}' docs/` (offene
   Platzhalter nach `CONVENTIONS_COMMON.md` §3, Treffer einzeln beurteilen) und `grep -rn '<!--[[:space:]]AGENT-ANWEISUNG' docs/`;
   im Confidence-Block vermerken: „Struktur-Check manuell, ohne Template-Skript".
7. **Git-Commit PFLICHT**, sofern Git verfügbar ist und der Prompter Commits nicht ausdrücklich untersagt hat: `<type>(<scope>): Beschreibung` (Typen und Scope-Regeln: `docs/CONVENTIONS_COMMON.md` §1)
   Ohne Commit oder dokumentierte Ausnahme ist das Inkrement nicht abgeschlossen.

---

## PROJEKT-QUICKSTART

### Wichtige Dateipfade

| Datei | Zweck |
|-------|-------|
| `Sync_Firebird_MSSQL_AutoSchema.ps1` | Haupt-Einstiegspunkt (Pre-Flight, parallele Tabellenverarbeitung, Zusammenfassung, Log-Rotation) |
| `SQLSyncCommon.psm1` | Gemeinsames Modul: Konfig, Credentials, Connection-Strings, Treiber, Typmapping |
| `sql_server_setup.sql` | `sp_Merge_Generic` (wird im Pre-Flight automatisch installiert/aktualisiert) |
| `config.sample.json` / `config.schema.json` | Konfigvorlage / JSON-Schema (lokale `config*.json` sind gitignored) |
| `Setup_Credentials.ps1` | Credentials im Windows Credential Manager ablegen |
| `Setup-ScheduledTasks.ps1` | Aufgabenplanung (Daily Diff, Weekly Full) anlegen |
| `Test-SQLSyncConnections.ps1` | Verbindungs-/Umgebungs-Smoke-Test; mit `-PreDeploy` rein lesender Rollout-Check vor jedem Deployment |
| `Get_Firebird_Schema.ps1` / `Manage_Config_Tables.ps1` | Typanalyse einer Tabelle / Tabellenauswahl per GridView |
| `Logs/` | Transcript-Logs je Lauf (gitignored) |

### Kritische Patterns (IMMER beachten)

- **Niemals `config.json` oder `config*.bak` lesen, ausgeben oder committen** — können Klartext-Passwörter enthalten. Nur `config.sample.json`/`config.schema.json` verwenden.
- **Exportierte Funktionsnamen in `SQLSyncCommon.psm1` nicht umbenennen** — alle Skripte importieren das Modul per `Import-Module (Join-Path $PSScriptRoot "SQLSyncCommon.psm1") -Force`.
- **Verbindungen immer in `try/finally` mit `Close()` + `Dispose()`** schließen (auch im `ForEach-Object -Parallel`-Block, der keine Modulfunktionen sieht, solange das Modul dort nicht importiert wird).
- **Keine Löschungen im MERGE** (`WHEN NOT MATCHED BY SOURCE`): Staging enthält im Incremental-Modus nur das Delta. Löschungen nur über `CleanupOrphans` oder `ForceFullSync`.
- **Here-Strings mit `RDB$`-Referenzen als Literal (`@'...'@`) + `-f`** — doppelte Anführungszeichen würden `$RELATION_NAME` als Variable interpretieren.
- **Identifier aus Konfig/Metadaten nie ungeprüft in SQL einsetzen** (Whitelist `Assert-SqlIdentifier` bzw. Validierung in `Get-SQLSyncConfig`, zusätzlich immer in `[...]` bzw. `"..."` quoten); Werte immer als Parameter.
- **Schreibende Tests nur gegen eine Test-Ziel-DB** — der Sync legt Datenbanken, Tabellen und Primärschlüssel an und leert Tabellen per `TRUNCATE`.

---

## INKREMENTPLAN (Priorisierte Aufgaben)

Der Inkrementplan steht **ausschließlich** in `docs/TODO.md` (Aufgaben, Priorität, DoD); `docs/STATE.md`
„Offene Punkte" führt nur die IDs für die Struktur-Checks. Hier nicht duplizieren — eine zweite Kopie veraltet.

---

## LINKS ZU DETAIL-DOCS

- Architektur: `docs/architecture/OVERVIEW.md`
- Features: `docs/features/`
- Sicherheit: `docs/security/`
- Prinzipien: `docs/principles/INDEX.md`
- Begriffe / Ubiquitous Language: `docs/GLOSSARY.md`
- Backlog (unpriorisiert): `docs/BACKLOG.md`
- Bekannte Probleme: `docs/KNOWN_ISSUES.md`
- Gelernte Patterns (Index): `docs/LESSONS_LEARNED.md`
- Git-Bootstrap (nur Initialaufsetzen): `docs/BOOTSTRAP.md`

### Optionale Docs (je nach Projekttyp laden)

| Datei | Wann relevant? |
|-------|---------------|
| `docs/features/firebird-mssql-sync.md` | Jede Änderung am Sync-Ablauf, an Strategien oder Konfigschaltern |
| `docs/architecture/CONFIGURATION.md` | Neuer/geänderter Konfigschlüssel |
| `docs/architecture/CREDENTIAL_STRATEGY.md` | Änderungen an Credential-Auflösung / Credential Manager |
| `docs/architecture/ERROR_HANDLING.md` | Exit-Codes, Retry, Fehlerbehandlung |
| `docs/operations/TASK_SCHEDULER.md` | Aufgabenplanung, Zeitpläne, Ausführungskonto |
| `docs/operations/RUNBOOK.md` | Störungsbehebung im Betrieb |
| `docs/testing/UNIT_TESTS.md` | Pester-Tests (ab I3) |
| `docs/testing/INTEGRATION_TESTS.md` | Tests gegen Firebird/SQL Server |
| `docs/architecture/ADR/` | Architekturentscheidungen (Vorlage `ADR-000-template.md`) |
