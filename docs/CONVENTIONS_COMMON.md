# Übergreifende Konventionen – PSFirebirdToMSSQL

Stack-agnostische Konventionen, die für **alle** Projekte gelten. Diese Datei wird nie
überschrieben; die stack-spezifische `docs/CONVENTIONS.md` **ergänzt** sie. Beide gelten
zusammen — für Stack-Spezifika hat `docs/CONVENTIONS.md` Vorrang. Ein echter Widerspruch
zwischen beiden ist ein Template-Befund (melden, nicht still auflösen).

---

## 1. Git & Commit-Format

### Conventional Commits

Format: `<type>(<scope>): <description>`

| Element | Werte | Beispiel |
|---|---|---|
| `<type>` | `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `build`, `ci` | `feat` |
| `<scope>` | Inkrement-ID (`I#`) **oder** Modul-/Bereichsname | `I3`, `auth`, `routes/items` |
| `<description>` | Imperativ, klein, kein Punkt, ≤ 72 Zeichen | `add login route` |

**Beispiele:**

```
feat(I3): add login route + session cookie
fix(I2): chained-comparison in range validation
refactor(repo): extract Repository context manager
docs(template): Phase 1 — Prozess-Foundation
test(items): cover 404 path
chore: bump python from 3.11 to 3.12
```

### Scope-Wahl-Regeln

- **`I#`** wenn das Commit zu einem Inkrement aus `TODO.md` gehört
- **Modul-/Bereichsname** wenn das Commit außerhalb eines Inkrements steht (z.B. Tippfehler-Fix, Dependency-Update)
- **Kein Scope** nur bei wirklich übergreifenden Commits (chore-Updates, Lizenz-Änderung)

### Git-Add-Regeln

- `git add` nur für **explizit bearbeitete Dateien** — niemals `git add .`
- `.gitignore` schützt nicht vor `git add path/to/secret` — Vorsicht.

### Commit-Politik (wann committet wird)

Der **Auslöser** für Commits ist nicht hier geregelt, sondern normativ in
`KICKOFF.md` Phase 3b: **pro abgeschlossenem Inkrement ist ein Commit Pflicht**,
sofern Git verfügbar ist und der Prompter Commits nicht ausdrücklich untersagt
hat. Ohne Commit (oder dokumentierte Ausnahme) gilt das Inkrement als nicht
abgeschlossen. Diese Datei regelt ausschließlich **Format** (Conventional
Commits) und **Add-Granularität** — nicht, *ob* committet wird.

---

## 2. Datei-Encoding und Zeilenenden

- UTF-8 ohne BOM für alle Quellcode- und Doku-Dateien
- LF-Zeilenenden in Repo (`.gitattributes: * text=auto eol=lf`); Windows-Checkout kann CRLF lokal nutzen
- Eine abschließende Newline pro Datei
- Stack-begründete Ausnahmen (z. B. ein BOM, das ein Werkzeug verlangt, oder ein Format, das das Betriebssystem
  vorgibt) stehen mit Begründung in der Stack-`CONVENTIONS.md` und gelten nur dort; eine Ausnahme, die nur in einer
  anderen Datei steht, gilt nicht.

---

## 3. Doku-Style

- Sprache: Deutsch, sofern das Projekt nichts anderes festlegt (z. B. englischsprachiges Open-Source-Projekt —
  dann im Kopf von `docs/CONVENTIONS.md` vermerken)
- **Leere Listen und Tabellen:** eine Zeile „(noch keine Einträge)" statt einer stehen gelassenen Vorlagenzeile
  oder einer gelöschten Tabelle — so bleibt erkennbar, dass die Sektion geprüft wurde
- Markdown-Linting: Default sinnvoll, keine harten Regeln
- Diagramme: Mermaid (in GitHub/GitLab/VSCode nativ)
- **Platzhalter-Schreibweise** (die Prüfung in `validate_project_docs.sh` erkennt genau diese Form):
  - **Ausfüllstelle:** eckige Klammer, deren Inhalt mit einem Wort aus mindestens zwei Großbuchstaben,
    Ziffern, `_` oder `-` beginnt, optional gefolgt von Leerzeichen/Doppelpunkt/Komma und einer Erläuterung
    (etwa „DATUM" oder „ZWECK: Was macht dieses Feature?" in eckigen Klammern). Alle vor dem Commit ersetzen.
  - **Dauerhafte Muster** in Vorlagen, die im Projekt Vorlage bleiben (`features/FEATURE-template.md`,
    `architecture/ADR/ADR-000-template.md`, `prompts/PROMPT-template.md`), und Benennungsmuster
    (z. B. `feature/[name]`, `[Projekt]-[Funktion]`) stehen in gemischter Schreibweise — sie werden nicht gemeldet.
  - **Literale in Großbuchstaben** mit eckigen Klammern, die im Text stehen bleiben sollen (z. B. Log-Präfixe),
    zeilenweise in `docs/.placeholder-ignore` eintragen; eine Zeile `pfad:literal` (Pfad relativ zu `docs/`)
    gilt nur für diese Datei — so bleibt dasselbe Literal anderswo als Ausfüllstelle erkennbar.

### 3.1 Öffentliche Repositories — Interna trennen

Gilt, sobald das Repository öffentlich ist oder werden kann (GitHub/GitLab public, Open-Source-Export). Als
potenziell öffentlich gilt es auch, wenn kein Remote erreichbar ist, aber eine Open-Source-Lizenz vorliegt oder ein
öffentlicher Vorgänger gleichen Namens existiert; im Zweifel wie öffentlich behandeln.
Alles Committete — Code, `docs/`, READMEs **und Commit-Messages** — ist dann öffentlich. Secrets
stehen ohnehin nie im Repo; zusätzlich:

- **Keine Firmeninterna in öffentlichen Dateien:** keine internen Hostnamen, IP-Adressen, Domänen-
  und Benutzernamen, Serverpfade, internen DB-/Tabellenpräfixe, Firmen-/Kundennamen — und **nie die
  Schwachstellen-Betroffenheit eines konkreten internen Hosts** („Server X läuft Version Y, betroffen
  von CVE Z" ist eine Angriffsanleitung).
- **Rollen statt Hosts** in öffentlichen Docs („Testserver", „Produktivserver", „Demo-Datenbank");
  Beispielwerte eindeutig fiktiv.
- **Interna nach `docs/local/`** (gitignored), z. B. `docs/local/ENVIRONMENT.md` mit Hosts, Versionen,
  Test-Artefakten; öffentliche Docs verweisen nur darauf.
- **Automatische Sperre statt Disziplin:** lokaler Pre-Commit- **und** Commit-Msg-Hook, der neue
  Zeilen, Dateinamen und die Commit-Message gegen eine gitignored Denylist (`.internal-terms`, ein
  Begriff pro Zeile, case-insensitive) prüft und bei Treffer abbricht. Hook-Skripte versioniert
  ablegen (`tools/git-hooks/`, Vorlagen im Template unter `repo-root/`) und pro Klon mit `git config core.hooksPath tools/git-hooks`
  aktivieren; fehlt die Denylist, nur warnen. Optional ergänzend `gitleaks` für echte Secrets. Hat das Projekt
  bereits einen gleichwertigen Hook (eigenes Verzeichnis, eigene lokale Denylist), bleibt er; fehlende Prüfungen
  (Commit-Message, Dateinamen) werden dort ergänzt, statt einen zweiten Hook einzuführen.
  Mit gesetztem `core.hooksPath` ignoriert Git `.git/hooks/`: projekt-eigene pre-commit-Prüfungen (z. B. die
  Quality Gates aus §5) gehören nach `tools/git-hooks/pre-commit.local` — der Interna-Hook ruft sie nach seiner
  Prüfung auf.
- **Vor dem ersten Push eines Branches** die komplette Branch-History prüfen
  (`git log -p origin/<default>..HEAD`): Commits, die vor Einführung des Hooks entstanden sind,
  sind nicht geschützt. Noch nicht gepushte Interna-Commits lokal bereinigen (Squash) statt pushen.
- **Typische Stellen für Interna** — dort besonders gegenlesen: `security/THREAT_MODEL.md`,
  `security/DEPENDENCY_AUDIT.md` (Befunde), `operations/RUNBOOK.md`, `operations/SETUP.md`,
  `operations/DEPLOYMENT.md`, Testergebnisse im `CHANGELOG.md`.
- **Die Denylist erkennt Namen, keine Aussagen:** „Zwei CVE-Warnungen und eine SYSDBA-Warnung in der
  Testumgebung" enthält keinen internen Namen, verrät aber die Betroffenheit eines internen Hosts.
  Testergebnisse mit Host-Bezug öffentlich nur generisch formulieren („erwartete Befunde, Details in
  `docs/local/`"); vor dem Commit bewusst gegenlesen, der Hook findet das nicht.
- `docs/` **nicht** komplett ignorieren — die Doku ist versioniertes Projektgedächtnis
  (STATE/TODO/CHANGELOG, Commit-Hashes, Reflexion); getrennt wird nur der interne Anteil.

---

## 4. Stack-spezifische Ergänzungen

Die Stack-Datei `docs/CONVENTIONS.md` (im Template: `stacks/<stack>/CONVENTIONS.md`) ergänzt diese Datei um:

- Code-Style-Regeln der jeweiligen Sprache (Type Hints, Naming, …)
- Stack-spezifische Security-Checklisten
- Trigger-Regeln für stack-spezifische Doku-Dateien

Die Regeln **dieser** Datei (Commit-Format, Encoding, Add-Regeln) gelten
**zusätzlich** zu den Stack-Regeln.

---

## 5. Definition of Done — Quality Gates

**Grün im Test-Runner allein ist kein Commit-Signal.** Vor jedem Commit müssen alle
zutreffenden Gates grün sein. Die Gates sind stack-agnostisch definiert; die konkreten
Befehle stehen in der Stack-Datei `docs/CONVENTIONS.md`.

1. **Gate 1 — Linter:** Stil, ungenutzte/falsch sortierte Imports, statische Lint-Regeln.
2. **Gate 2 — Formatter:** einheitliche Formatierung (Check-Modus, kein Auto-Fix im Gate).
3. **Gate 3 — statische Typ-/Analyse:** Typ-Korrektheit bzw. Compiler-/Analyzer-Warnungen als Fehler.
4. **Gate 4 — Unit-Tests:** schnelle Tests ohne Netz/DB/GPU.

**Reihenfolge:** Gate 1 → 4, die billigste deterministische Prüfung zuerst. Ein Typfehler kann ein Testergebnis
maskieren — deshalb läuft Gate 3 vor den Tests. Nach jedem grünen Stand bleibt die gesamte Gate-4-Auswahl grün,
nicht nur der neue Test (Regression-Gate).

Projektspezifische Checks (z. B. der Schichtcheck aus `docs/architecture/PROJECT_LAYOUT.md`, Lizenz- oder
Schema-Prüfungen) laufen **im selben Gate-Lauf** mit — als Test in Gate 4 oder als eigener Befehl im Abschnitt
„Quality Gates" der Stack-Datei; sie bekommen keine eigene Gate-Nummer.

Nur Gate 4 allein zu prüfen ist eine häufige Fehlerquelle: Lint- und Typfehler werden
vom Test-Runner nicht erkannt.

### Mapping pro Stack

| Stack | Gate 1 Linter | Gate 2 Formatter | Gate 3 Typ/Analyse | Gate 4 Unit-Tests |
|---|---|---|---|---|
| python (cli/api/web) | ruff | ruff format | mypy | pytest (Unit-Auswahl laut Stack) |
| powershell-automation | PSScriptAnalyzer | — | — | Pester |
| csharp (console/desktop/aspnet) | dotnet format (Gate 1+2; entfällt bei Desktop im alten Projektformat) | — | dotnet build mit Warnungen als Fehler (Compiler + Roslyn-Analyzer; altes Desktop-Format: msbuild) | dotnet test (Unit-Testprojekt laut Stack; altes Desktop-Format: vstest.console) |
| react-web | eslint | prettier | tsc | vitest |
| rust-cli | clippy | rustfmt | (Compiler, im Clippy-Lauf enthalten) | cargo test / cargo nextest |

„—" = der Stack hat für dieses Gate kein eigenständiges Werkzeug; das benachbarte Gate
deckt es mit ab. Die Tabelle nennt nur die Werkzeuge; die exakten Aufrufe (inkl. Pfade, Marker,
Test-Auswahl, Hook-/CI-Einbindung) stehen ausschließlich in der Stack-Datei `docs/CONVENTIONS.md`.

---

## 6. Parallele Agenten

Gilt, sobald mehrere Agenten-Sessions gleichzeitig im selben Repository arbeiten (Subagenten,
mehrere Terminals, Cloud-Sessions). Ein Agent sieht die halbfertigen Änderungen der anderen
nicht und hält deren kaputten Zwischenstand sonst für seinen eigenen Fehler.

- **Isolation:** eigener Git-Worktree (bzw. Branch) **und** eigenes Build-/Ausgabeverzeichnis je
  Agent (z. B. getrenntes `bin/obj`, `.venv`, `CARGO_TARGET_DIR`), damit sich Build-Sperren und
  Artefakte nicht überschneiden.
- **Dateibesitz:** Jeder Agent bearbeitet nur die Dateien seiner Aufgabe. Neue Funktionalität
  kommt in eine **neue Datei/ein neues Modul**, statt eine geteilte Datei wachsen zu lassen.
  Geteilte Dateien (Registrierungslisten, zentrale Konfiguration, `STATE.md`) nur mit kleinen,
  gezielten Änderungen und **unmittelbar vorher neu lesen**.
- **Geteilte Konfiguration atomar schreiben:** Manifeste/Projektdateien, deren Fehler *alle*
  Builds bricht, in eine Temp-Datei außerhalb des Quellbaums, aber auf demselben Dateisystem schreiben und dann in
  einem Schritt verschieben (nur dann ist das Verschieben ein atomarer Rename) — nie halbfertig im
  Baum stehen lassen.
- **Fremde Brüche nicht reparieren:** Bricht der Build durch die laufende Änderung eines anderen
  Agenten, warten und erneut versuchen; nicht dessen Dateien anfassen.
- **Docs-Konsistenz:** `STATE.md`/`TODO.md`/`CHANGELOG.md` aktualisiert nur, wer integriert
  (Merge in den Hauptzweig) — sonst entstehen doppelte oder widersprüchliche Einträge.
- **Aufräumen:** Worktrees und Build-Verzeichnisse beendeter Agenten löschen (Plattenplatz).

---

## 7. Pflege

Trigger: neue stack-übergreifende Konvention → hier eintragen. Stack-spezifische
Konvention → in `docs/CONVENTIONS.md` (Backport ins Template: `stacks/<stack>/CONVENTIONS.md`).
