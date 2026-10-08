# Lessons Learned – PSFirebirdToMSSQL

Strukturierter Index für gelernte Patterns. Jeder Eintrag benennt Scope und
Backport-Ziel, damit die Reflexions-Phase (REFLECTION.md Schritt 3) offene
generische Patterns automatisch in `docs_template/` zurückspielen kann.

Neue Einträge entstehen aus dem „Lessons Learned"-Abschnitt der `CHANGELOG.md` —
dort kurze Beschreibung, hier der strukturierte Steckbrief.

---

## L1: Unverankerte gitignore-Muster verschlucken docs-Dateien
- Inkrement: I1
- Scope: generisch-base
- Backport-Ziel: `base/BOOTSTRAP.md` (Abschnitt `.gitignore`) bzw. `scripts/validate_project_docs.sh` (Check: `git check-ignore` gegen alle `docs/`-Dateien)
- Status: offen

Das bestehende Muster `config*` hätte unter Windows (`core.ignorecase=true`) auch
`docs/architecture/CONFIGURATION.md` ignoriert — die Datei wäre stillschweigend nie committet
worden. Muster für Root-Dateien mit `/` verankern und vor dem Init-Commit
`git check-ignore -v docs/**/*.md` prüfen.

---

## L2: Log-Rotation in Testkonfigs abschalten
- Inkrement: I2
- Scope: projekt-spezifisch
- Backport-Ziel: keiner
- Status: offen

Eine aus einer Produktivkonfig abgeleitete Testkonfig erbt `General.DeleteLogOlderThanDays` und
löscht beim ersten Lauf alte `Sync_*.log` im `Logs\`-Ordner neben dem Skript (bei der I2-Abnahme
7 Dateien in der lokalen Arbeitskopie). Testkonfigs immer mit `DeleteLogOlderThanDays: 0` anlegen;
siehe auch `testing/INTEGRATION_TESTS.md`.

---

## L3: Mutationsprüfung statt „erster Lauf rot" bei Charakterisierungstests
- Inkrement: I3
- Scope: generisch-base
- Backport-Ziel: `base/KICKOFF.md` Phase 2 Punkt 2 (TDD-Startregel) und `base/principles/` (z. B. `ADVOCATUS_DIABOLI.md` oder `VERIFY_BEFORE_CITE.md`)
- Status: offen

Die TDD-Regel „neuer Test muss behavioral rot sein, erster Lauf grün → stoppen" passt für neue
Logik, nicht für Tests, die bestehendes Verhalten festschreiben (Brownfield-Testharness) — die
sind zwangsläufig sofort grün. Ersatznachweis: pro Funktion einen gezielten Fehler in eine
*Kopie* des Codes einbauen und prüfen, dass mindestens ein Test rot wird (I3: 13/13 erkannt).
Suchmuster für Mutationen an Funktionsnamen verankern, sonst greift die Mutation still nicht.

---

## L4: Zustand der Testumgebung vor schreibenden Integrationsläufen prüfen
- Inkrement: I4
- Scope: projekt-spezifisch
- Backport-Ziel: keiner
- Status: offen

Der Pre-Flight legt eine fehlende Ziel-Datenbank stillschweigend an. Bei I4 hat ein Testlauf die
vom Nutzer bereits gelöschte `STAGING_I2TEST` dadurch ungefragt wiederhergestellt. Vor jedem
schreibenden Lauf lesend prüfen, ob Ziel-DB und Tabellen existieren (z. B. Abfrage über `master`),
und bei Abweichung vom erwarteten Zustand nachfragen bzw. den Nutzer informieren.

---

## L5: Öffentliches Repo — Firmeninterna aus Doku und Commit-Messages heraushalten
- Inkrement: zwischen I4 und I5 (2026-10-08)
- Scope: generisch-base
- Backport-Ziel: `base/CONVENTIONS.md` 3.1, `base/BOOTSTRAP.md`, `base/REFLECTION.md`, `NEUES_PROJECT_INITIALISIEREN.md`
- Status: backported v26 (unreleased, Template-Commit 7ad733e; vom Prompter vorab freigegeben)

Beim Befüllen und Fortschreiben von `docs/` landeten interne Hostnamen, Serverpfade, Credential-
Eintragsnamen und — am kritischsten — die CVE-Betroffenheit eines konkreten internen Servers in
Doku **und Commit-Messages** eines öffentlichen GitHub-Repos. Vor dem ersten Push bemerkt.
Lösung: Interna nach `docs/local/` (gitignored), öffentlich nur Rollenbezeichnungen,
Pre-Commit-/Commit-Msg-Hook gegen eine gitignored Denylist, Branch per Squash bereinigt.
`docs/` komplett zu ignorieren wurde verworfen (Doku ist versioniertes Projektgedächtnis).

---

## L6: Neue Fail-Fast-Validierung vor dem Scharfschalten gegen den Bestand prüfen
- Inkrement: I4, I6 (Reflexion nach I6, 2026-10-09)
- Scope: generisch-base
- Backport-Ziel: `base/principles/FAIL_FAST.md` (Abschnitt „Einführung neuer Prüfungen")
- Status: offen

Eine neue harte Prüfung (Identifier-Whitelist in I4, Schema-Validierung in I6) bricht jeden Lauf ab,
dessen Konfiguration oder Daten sie nicht erfüllen — auch produktive, die bisher funktionierten.
Vor dem Aktivieren alle erreichbaren Bestandsdaten gegen die neue Regel prüfen (ohne Inhalte
auszugeben) und das Ergebnis im CHANGELOG festhalten; für nicht erreichbare Installationen einen
Prüfbefehl für das Deployment dokumentieren. In I6 fiel dabei zusätzlich ein Widerspruch zwischen
zwei Regelwerken auf (Schema nur Großbuchstaben vs. Whitelist auch Kleinbuchstaben).

---

## Pflege

- Neuer „Lessons Learned"-Block im `CHANGELOG.md` → Eintrag `## L<N>:` hier anlegen.
- Mehrere Patterns aus einem Inkrement → mehrere `## L<N>:`-Einträge.
- Scope-Werte:
  - `projekt-spezifisch` — nur für dieses Projekt relevant, kein Backport nötig.
  - `generisch-stack` — gehört in `docs_template/stacks/<stack>/CONVENTIONS.md` o.ä.
  - `generisch-base` — gehört in `docs_template/base/` (Prinzip, Basis-Convention, MANIFEST).
- Status `offen` → wird bei der nächsten Reflexion (REFLECTION.md Schritt 3) abgearbeitet.
- Status `backported vN` → Backport-Commit ins Template-Repo durchgeführt, Tag vN gesetzt.
- Niemals Patterns löschen, auch wenn überholt — `Status: verworfen (<grund>)` setzen.
- Diese Datei steht in der Trigger-Matrix in `KICKOFF.md` Phase 3a.
