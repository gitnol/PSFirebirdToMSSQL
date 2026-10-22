# REFLECTION – Phase 1c Reflexions-Check

Diese Datei enthält den **vollständigen Ablauf** des Reflexions-Checks. `KICKOFF.md`
lädt in jeder Session nur den Auslöser-Block der Phase 1c und verweist hierher;
dieser Körper wird **nur bei ausgelöstem Trigger** geladen — das spart pro
Standard-Session Kontext.

**Auslöser & Einstieg:** siehe `docs/KICKOFF.md` Phase 1c. Greift ein Auslöser, diese
Datei vollständig abarbeiten, **bevor** Phase 2 startet. Das Ergebnis kurz im Chat
zusammenfassen.

**Hintergrund:** Nach mehreren Inkrementen driften zwei Dinge zuverlässig:

1. `docs/` enthalten noch Hinweise auf inzwischen erledigte Inkremente
   („siehe I2", „(geplant: I3)", Backlog-Einträge, die bereits behoben sind).
2. Im Projekt entstandene Patterns / Lessons sind noch nicht in `docs_template/`
   zurückgespielt — die nächste Initialisierung erbt sie nicht.

---

## Vorgehen

### Selbstkritik — Advocatus Diaboli (läuft zuerst, vor allen strukturellen Checks)

Bevor strukturelle Bereinigung und Backport-Entscheidungen stattfinden, **alle seit der letzten Reflexion
abgeschlossenen Inkremente** aus der Teufelsperspektive begutachten:

> Analysiere die seit der letzten Reflexion abgeschlossenen Inkremente als Advocatus Diaboli:
>
> 1. **Positiv** — was ist solide gelöst, richtig entschieden, erhaltenswert?
> 2. **Negativ** — was ist über-engineert, zu früh abstrahiert oder weicht vom
>    erklärten Ziel ab? Welche Entscheidung würde ein erfahrener Reviewer anfechten?
> 3. **Backport-Filter** — welche LESSONS_LEARNED-Kandidaten sind noch zu jung
>    (ein Inkrement ≠ Pattern), zu projektspezifisch oder könnten in anderen
>    Stacks schaden?
>
> Ergebnis: gefilterte Backport-Kandidatenliste — bereinigt um voreilige
> Verallgemeinerungen und Over-Engineering-Artefakte.

**Belegpflicht** wie im Prinzip `docs/principles/ADVOCATUS_DIABOLI.md`: Jede Aussage zu 1–3 mit Beleg
(Datei/Zeile, Commit, Befehlsausgabe) — sonst ausdrücklich als Vermutung kennzeichnen. Ein erzählendes
Urteil ohne Beleg ist eine Meinung, kein Check.

Das Ergebnis fließt direkt in Schritt 3 (Template-Backport) ein: valide Lektionen
auf die Kandidatenliste, entlarvter Blödsinn fliegt raus.

### 0. Sektions-Invariante prüfen — STATE.md und TODO.md (strukturell)

**Invariante:** Eine Inkrement-ID erscheint in **genau einer** Sektion:
- `STATE.md`: entweder „Abgeschlossene Inkremente" (bzw. rotiert im Archiv `docs/changelog/ARCHIVE-STATE.md`) oder
  „Offene Punkte", nie beide.
- `TODO.md` führt nur Offenes: Ein abgeschlossenes Inkrement steht dort nicht mehr.

Erledigte Inkremente stehen als Zeile mit Commit-Hash in `STATE.md` „Abgeschlossene Inkremente" — eine zweite
Liste in `TODO.md` gibt es nicht (Altformat „Abgeschlossen": Schritt 5a).
**Kein Strikethrough (`~~`) für Inkrement-IDs** — Abschluss wird durch die STATE-Zeile, das Datum und
git/CHANGELOG belegt. Leere Sektionen nach dem Cleanup vollständig entfernen.

> Strikethrough für andere Zwecke bleibt erlaubt (z. B. verworfene Einträge in
> `BACKLOG.md` „Verworfen"). Der Check unten trifft solche Einträge nicht, weil
> sie kein direktes `~~I[0-9]+`-Muster erzeugen.

**Source-of-Truth-Hierarchie (absteigend autoritativ):**
1. `git log` — maßgeblich für Commit-Hashes, Reihenfolge, tatsächliche Durchführung
2. `docs/CHANGELOG.md` — narrative Quelle für Umfang und Inhalt jedes Inkrements
3. `docs/STATE.md` — für den Inkrement-Stand abgeleitete Sicht (Tabelle + Nächster Schritt; ältere Zeilen im
   Archiv `docs/changelog/ARCHIVE-STATE.md`); kein Inkrement-Inhalt, der nicht aus git/CHANGELOG ableitbar ist.
   Daneben führt STATE.md eigenständig die Kopf-Marker, „Risiken & Blocker" und ggf. „Kennzahlen (gemessen)"
   (Trigger-Matrix KICKOFF 3a)
4. `docs/TODO.md` — abgeleitete Sicht: nur offene Aufgaben und DoD

> **Ein-Befehl-Variante:** Falls die Template-Skripte vorliegen, führt
> `<Template-Root>/scripts/validate_project_docs.sh docs/` die vier Struktur-Checks (Verletzung 1–4)
> plus den Health-Check (Schritt 1) gebündelt aus — statt vier einzelner Greps.
> Die expliziten Befehle unten bleiben die verbindliche Spezifikation/Fallback.

**Andere ID-Schemata:** Die Befehle unten sind für `I#` geschrieben. Nummeriert das Projekt anders (z. B. `P-04a`,
`H2`), nennt der `STATE.md`-Kopf die Präfixe: `**ID-Muster:** P-|H` (alle verwendeten, mit `|` getrennt; ohne
Zeile gilt `I`). `validate_project_docs.sh` liest die Zeile; in den Befehlen unten `I` durch `(P-|H)` ersetzen.
Nach dem Präfix folgen Zahl, optional Buchstabe und Unterpunkte (`P-04a`, `P-03.1.1`, `I49.2`).

**Strukturelle Checks (alle ausführen):**
```
# Verletzung 1 – ~~I# irgendwo in docs/ → muss 0 Treffer ergeben
grep -rnE "~~I[0-9]+" docs/

# Abgeschlossene Inkremente = STATE.md „Abgeschlossene Inkremente" plus rotiertes Archiv (Schritt 5a);
#   Verletzung 2 und 4 lesen beides, sonst verlieren archivierte IDs die Abdeckung.
abgeschlossen() {
  awk '/^## / { sec = $0 } /^\| I[0-9]+/ && sec ~ /Abgeschlossene/' docs/STATE.md
  cat docs/changelog/ARCHIVE-STATE*.md 2>/dev/null | grep -E '^\| I[0-9]+'
}

# Verletzung 2 – dieselbe Inkrement-ID abgeschlossen UND in STATE.md „Offene Punkte"
#   (sektionssensitiv: „Offene Punkte" enthält by design `| I# |`-Zeilen —
#    ein simples grep "^\| I[0-9]+" würde diese fälschlich als Treffer melden).
#   Muss 0 Zeilen ausgeben.
abgeschlossen | awk '
  FILENAME == "-"     { done[$2] = 1; next }
  /^## /              { sec = $0 }
  /^\| I[0-9]+/ && sec ~ /Offene/ && ($2 in done) {
                        print "Verletzung 2: " $2 " steht abgeschlossen und in Offene Punkte" }
' - docs/STATE.md

# Verletzung 3 – ~~I# als Abschnittsüberschrift in TODO.md → muss 0 Treffer ergeben
grep -nE "^### ~~I[0-9]+" docs/TODO.md

# Verletzung 4 – I# abgeschlossen (STATE.md oder Archiv), aber noch als offener
#   Abschnitt (### I#:) in TODO.md → muss 0 Zeilen ausgeben.
abgeschlossen | awk '
  FILENAME == "-"     { done[$2] = 1; next }
  /^### I[0-9]/ {
    id = $2; sub(/:$/, "", id)
    if (id in done) print "Verletzung 4: " id " abgeschlossen, aber noch offen in TODO.md"
  }
' - docs/TODO.md
```
Treffer auf Verletzung 1/3: Strikethrough um Inkrement-ID entfernen.
Treffer auf Verletzung 2: Die ID gehört in **genau eine** Sektion. Ist das
Inkrement abgeschlossen → Zeile aus „Offene Punkte" entfernen und einen dort genannten offenen Rest nach
KICKOFF.md Phase 3b (TODO-Bereinigung, „Bleibt ein Rest offen") übernehmen (neue ID oder BACKLOG-Eintrag, nicht streichen); ist es noch
offen → Zeile aus „Abgeschlossene Inkremente" entfernen.
Treffer auf Verletzung 4: Den betreffenden Abschnitt (`### I#:`) aus der offenen Sektion entfernen (KICKOFF.md Phase 3b, TODO-Bereinigung).

**Optional – Hash-Backfill:** Fehlende Commit-Hashes (`—`) in STATE.md
„Abgeschlossene Inkremente" aus `git log --oneline` ergänzen. Autoritativer
Hash = der Haupt-`feat(I#)`-Commit des Inkrements (git ist Source of Truth).

**ZUSÄTZLICH – semantischer Konsistenz-Check (Stichprobe):** Dokumentierte
Enum-Werte (Status-Codes, Outcome-Typen, Fehler-Taxonomien) mit den echten
Enum-Definitionen im Code abgleichen (z. B. Python `grep -rn "class.*StrEnum" src/`, C#/PowerShell `enum`).
Abweichung → Docs korrigieren (Code ist Source of Truth).

### 1. `docs/`-Health-Check

Suche nach abgeschlossenen Inkrement-IDs, die in anderen Docs noch als offen
formuliert sind:

```
grep -rnE "siehe I[0-9]+|[Gg]eplant(:| in) I[0-9]+|wird in I[0-9]+ behoben|\(Hoch, I[0-9]+\)|TBD in I[0-9]+|\bab I[0-9]+|\bbis I[0-9]+|in I[0-9]+ (festlegen|festgelegt|befüllen|finalisieren|klären)" docs/
```

Relevant sind nur Treffer auf **bereits abgeschlossene** IDs (Verweise auf künftige Inkremente sind legitim);
`validate_project_docs.sh` filtert das automatisch. Treffer auf „mitigiert in I#" / „abgeschlossen in I#"
umstellen oder ganz entfernen, wenn der Eintrag durch das Inkrement obsolet wurde (z.B. Backlog-Punkte).
Formulierungen, deren Korrektur Wissen über den Code verlangt („TBD in I2" → was gilt jetzt?), gehören nach
Schritt 4 auf die Liste für den Prompter.

**Fakten-Drift in Querschnitts-Docs:** Der Grep oben findet veraltete *Verweise*, nicht veraltete *Aussagen*. Für
jedes seit der letzten Reflexion geänderte Verhalten (neuer Retry, neue Konfigurationsquelle, anderes Logging,
geänderte Suchlogik) gezielt nach der **alten Formulierung** in `docs/` suchen — etwa „kein automatisches Retry"
oder den alten Cmdlet-/Optionsnamen. Die Drift sitzt erfahrungsgemäß in Querschnitts-Docs, die ein Inkrement nur
indirekt berührt (`architecture/ERROR_HANDLING.md`, `architecture/CONFIGURATION.md`, `operations/RUNBOOK.md`,
Prinzipien), und besonders nach Inkrementen, die als Bugfix oder Refactoring durchgingen und deshalb keine Zeile
der Trigger-Matrix auslösten.

**Interna-Scan (öffentliches Repo, `CONVENTIONS.md` 6.2):** alle versionierten Dateien gegen die
lokale Denylist prüfen — Treffer nach `docs/local/` verschieben bzw. durch Rollenbezeichnungen ersetzen:

```
grep -v '^#' .internal-terms > /tmp/terms.txt
git ls-files | xargs grep -HinF -f /tmp/terms.txt
```

Die Denylist vergleicht Teilzeichenketten. Kurze interne Namen, die in gewöhnlichen Wörtern vorkommen (etwa ein
Kürzel aus drei Buchstaben), stehen deshalb nicht darin — sie zusätzlich mit Wortgrenzen suchen:
`git grep -nwi -e <NAME>` (die Liste solcher Namen lokal in `docs/local/` führen, `CONVENTIONS_COMMON.md` 3.1).

**Pflegerückstand in BACKLOG und KNOWN_ISSUES:** Eingeplante Backlog-Punkte wandern nach `TODO.md` — `~~…~~`
steht nur unter „Verworfen", nie als „erledigt in I#". `KNOWN_ISSUES.md` „Behobene Probleme" ist eine Spur bis zur
nächsten Aufräum-Iteration und wird dann geleert (Historie steht in CHANGELOG und Git). `validate_project_docs.sh`
meldet beides als Hinweis (`~~…~~` außerhalb „Verworfen"; mehr als 10 behobene Einträge) — jetzt aufräumen.

**Refactoring-Kandidaten (Hotspots):** Dateien, die oft geändert werden **und** groß sind, tragen die meisten Fehler
(relative Änderungsmenge sagt Fehlerdichte voraus, Nagappan & Ball, ICSE 2005; Hotspot-Analyse nach Tornhill).
Die zehn meistgeänderten Code-Dateien seit der vorherigen Reflexion mit Größe:

```
git log --since=<Datum der vorherigen Reflexion> --format= --name-only -- . ':(exclude)docs' |
  grep -v '^$' | sort | uniq -c | sort -rn | head -10 |
  while read -r n f; do [ -f "$f" ] && printf '%4d Commits  %5d Zeilen  %s\n' "$n" "$(wc -l < "$f")" "$f"; done
```

Die Zahlen sind ein Hinweis, kein Urteil: Manifeste, Versionsdateien, README und Konfiguration ändern sich mit jedem
Release und sind keine Kandidaten (bei Bedarf als weitere `':(exclude)…'` anhängen). Für die übrigen Treffer die Datei
lesen — ist sie schwer zu ändern (lange Funktionen, verschachtelte Bedingungen, wiederholte Logik — `docs/principles/DRY.md`), kommt sie
mit beiden Zahlen nach `BACKLOG.md` „Refactoring-Kandidaten"; dort stehende Kandidaten werden zugleich gesichtet:
behoben → löschen, inzwischen schmerzhaft → nach `TODO.md` als Inkrement (Regeln: `KICKOFF.md` Phase 2, Punkt 3).

**Testgüte:** Mutationsprüfung für die seit der vorherigen Reflexion geänderten Dateien der Kern-Schicht nach
`docs/principles/TEST_EFFECTIVENESS.md` (Werkzeug und Aufruf: `docs/testing/UNIT_TESTS.md`). Überlebende Mutanten
werden in dieser Reflexion mit Tests geschlossen oder als äquivalent begründet; ist das zu groß, kommt es als
offener Punkt nach `TODO.md`.

### 2. Cross-Refs konsistent

Alle I-Nummern in `docs/` zeigen auf existierende Inkremente in `STATE.md` oder im Archiv
`docs/changelog/ARCHIVE-STATE.md` (kein Renumbering-Loch).

### 2b. Roadmap-Konsolidierung

Offene Inkremente (`TODO.md`), `BACKLOG.md`, aktive `KNOWN_ISSUES.md` und `STATE.md`-Risiken gemeinsam
auf Überschneidungen (gleiche Datei/Funktion, gleiche Ursache, gleiches Risiko) und Konsolidierungen
prüfen — inklusive Backlog-Punkten, die durch erledigte Inkremente inzwischen billig oder obsolet sind.
Ergebnis: priorisierte Liste der nächsten drei Inkremente mit Begründung je Bündelung/Umordnung;
Übernahme in `TODO.md` als eigener `docs:`-Commit. Ablauf wie KICKOFF Phase 1 Punkt 2a.

### 3. Template-Backport

**Queue-Abbau:** Alle Einträge in `docs/LESSONS_LEARNED.md` mit
`Scope: generisch-*` und `Status: offen` abarbeiten — Backport ins
`Backport-Ziel` einspielen (Mechanik unten), dann `Status: backported vN@<commit>` setzen.

**Freigabe-Disziplin:** Ein Backport ist eine ausdrückliche Entscheidung des Prompters.
Ohne Freigabe — insbesondere in **autonomen Läufen** — generische Lessons
(`Scope: generisch-*`, `Status: offen`) **nur als Backport-Vorschlag melden, nie selbst
ins Template committen oder taggen**. `Status: offen` bleibt unverändert, bis die Freigabe
vorliegt; erst dann Backport einspielen und `Status: backported vN@<commit>` setzen.

Was wurde in den letzten Inkrementen gelernt, das ein generisches Pattern
darstellt? Typische Kandidaten:
- Neue Regel oder Anti-Pattern → `docs_template/stacks/<stack>/CONVENTIONS.md`
- Fehlende Manifest-Einträge → `docs_template/MANIFEST.yaml`
- Wiederkehrende Architektur-Erkenntnis → `docs_template/base/principles/`
  (neues Prinzip: die 5-Stellen-Checkliste in `docs_template/README.md` →
  „Template-Pflege" → „Neues Prinzip anlegen" befolgen — Datei + MANIFEST + INDEX +
  README-Zähler + Changelog in **einem** Commit, sonst wird es nicht ausgeliefert)

**Cross-Pollination-Check (nur Kandidaten melden, keine Auto-Edits):** Für jede Lehre,
die nach `base/` wandert (Genericity-Test bestanden, Definition in `evals/STRATEGY.md`),
einmal explizit fragen: *„Welche anderen Stacks haben für diese Lehre ein echtes,
nicht erzwungenes Analogon?"* Diese Stacks als **Review-Vorschlag** auflisten — die
idiomatisch korrekte Formulierung pro Sprache ist Tier-3-Arbeit (Mensch), **nicht**
ein Copy-Paste der Ausgangs-Lehre.

> **Warum nur Vorschlag:** Eine Python-Lesson erzeugt keinen guten C#-Rat per Kopie.
> Wer die generische Lehre 1:1 in jeden Stack schreibt, baut genau die per-Stack-Idiom-
> Duplikate, die das Tier-Modell verbietet (`evals/STRATEGY.md`, Tier 3). Der Backport
> nach `base/` macht das Prinzip für **alle** Stacks verfügbar; die stack-spezifische
> Ausformulierung passiert erst, wenn ein konkretes Projekt dort sie tatsächlich braucht.

Den Vorschlag in Schritt 4 mit auf die priorisierte Liste nehmen (als
`sinnvoll: <stack-x>, <stack-y> haben Analogon zu <Lehre> — idiomatisch prüfen`).

> **Hinweis (Backport-Mechanik):** Das Template lebt als Git-Repo (Versionen = Git-Tags).
> **Vor der ersten Änderung** prüfen, ob das lokale Template auf dem Stand seines Remotes ist — andere Projekte
> spielen ebenfalls Backports ein; wer auf einem veralteten Stand ändert, merkt es erst beim abgelehnten Push und
> arbeitet in vermeidbare Konflikte:
> ```bash
> <Template-Root>/scripts/check_template_current.sh   # git fetch + Vergleich mit dem Upstream
> ```
> Exit 0 (aktuell oder nur eigene lokale Commits) → weiter. Exit 1: `ZURUECK` → erst `git pull --ff-only`;
> `AUSEINANDER` → erst zusammenführen — per **Merge**, sobald ein Projekt schon auf einen lokalen Commit verweist
> (Stempel `vN@<commit>`), sonst wäre der Verweis nach einem Rebase ungültig; `GEÄNDERT` → fremde Änderungen klären.
> Exit 2 (offline, ZIP-Export, kein Upstream) → im Bericht vermerken; Backports dann nur lokal und vor dem Push erneut
> prüfen. Danach Backports einspielen und explizit stagen — **kein `git add -A`**, da im
> Template-Repo Arbeitskopien, Editor-Artefakte oder Projekt-Exporte liegen können:
> **Projektspezifisch (PSFirebirdToMSSQL):** Template-Repo liegt unter
> `D:\GIT\gitnol\docs_template` (Git-Bash: `/d/GIT/gitnol/docs_template`); dieses Projekt
> wurde mit `VERSION` 26 initialisiert. Backports betreffen typischerweise
> `stacks/powershell-automation/` oder `base/`.
> ```bash
> cd /d/GIT/gitnol/docs_template
> git status --short          # Überblick, welche Dateien geändert wurden
> git add stacks/powershell-automation/CONVENTIONS.md base/BOOTSTRAP.md   # nur tatsächlich geänderte Template-Dateien
> cat VERSION                 # steht schon auf N+1 (unreleased)? Dann nicht erneut erhöhen
> echo "N" > VERSION          # nur bei der ersten Änderung nach dem letzten Tag hochziehen
> git add VERSION TEMPLATE_CHANGELOG.md
> git commit -m "feat(template): backport from PSFirebirdToMSSQL (I#-Reflexion)"   # bzw. fix/docs
> ```
> Versionspraxis: `VERSION` wird mit der **ersten** Änderung nach einem Tag auf die nächste Nummer gesetzt; alle
> weiteren Änderungen bis zum Tag sammeln sich im Block `[vN] … (unreleased)` von `TEMPLATE_CHANGELOG.md`; der
> Tag folgt erst nach dem Gate (Schritt 3b). Projekte notieren deshalb Version + Commit (`vN@<commit>`).
> `git tag` wird erst in Schritt 3b gesetzt — **nicht** hier.

### 3b. Pre-Tag Gate — BLOCKER (**kein `git tag` ohne diesen PASS**)

Dieser Schritt ist ein harter Blocker. `git tag vN` darf **nur** ausgeführt werden,
wenn die für den Änderungsumfang geforderten Prüfungen bestanden sind. **Kein
Überspringen, kein Vorziehen des Tags.**

1. **Struktur-Validator (immer Pflicht, jede Version):**
   ```bash
   <Template-Root>/scripts/validate_template.sh   # statisch: MANIFEST ↔ Disk, Encoding, Oberflächen
   <Template-Root>/scripts/smoke_stacks.sh        # dynamisch: init_docs.sh je Stack + Pflichtdatei-Check
   ```
   Beide Exit 0 erforderlich. Bei Fehler: Befund beheben, Commit ergänzen, erneut prüfen.
   Der Smoke deckt die **Nicht-`python-cli`-Stacks** ab, die S1–S3 nicht berühren —
   deshalb ist er gerade für reine Stack-Änderungen (Tabelle unten) die tragende Prüfung.

2. **Change-Surface bestimmen** — was wurde seit dem letzten Tag tatsächlich angefasst?
   ```bash
   git diff --name-only "$(git describe --tags --abbrev=0)"..HEAD
   ```
   Die geänderten Pfade gegen die Tabelle halten. Das **Eval-Gate** ist *scoped*: S1–S3
   nur laufen lassen, wenn die Änderung sie überhaupt berühren kann. Bei gemischtem
   Changeset gewinnt die **strengste zutreffende Zeile**. (Begründung der Tier-Logik
   hinter dieser Tabelle: `evals/STRATEGY.md`.)

   | Geänderte Pfade (seit letztem Tag) | Eval-Gate |
   |---|---|
   | `base/**`, `scripts/**`, `evals/**`, `repo-root/**`, `SKILL.md`, `NEUES_PROJECT_INITIALISIEREN.md`, `ALTES_PROJECT_AKTUALISIEREN.md`, oder die Stack-/Overlay-**Listen** in `MANIFEST.yaml` | **S1–S3 = 2×3/3 PASS** (Prozess wird wirklich getestet — die Agenten lesen und befolgen diese Dateien; immer der volle Lauf, Teilläufe übersehen Wechselwirkungen) |
   | `stacks/python-cli/**` | **S1–S3 = 2×3/3 PASS** — die Szenarien laden genau diesen Stack |
   | **nur** `stacks/<x>/**` (x ≠ `python-cli`) und/oder `overlays/<y>/**` | **kein S1–S3** — kein Szenario lädt diesen Stack (null Signal); stattdessen Struktur-Validator (oben, inkl. `smoke_stacks.sh --stack <x>` für den geänderten Stack) + manuelles Inhalts-Review |
   | nur `README.md`, `TEMPLATE_CHANGELOG.md` und/oder `handbuch/**` | **kein S1–S3** — Struktur-Validator (inkl. Check 8) genügt |

   > **Sicherheits-Invariante:** S1–S3 nutzen ausschließlich den `python-cli`-Stack
   > (verifiziert in `evals/scenarios/*/SCENARIO.md` + `EXPECTED.md`). Solange das gilt,
   > kann eine Änderung an einem anderen Stack ihr Ergebnis nicht beeinflussen — das
   > Auslassen ist **sicher**, nicht nur billig. Wird je ein Szenario auf einen anderen
   > Stack umgestellt (oder ein stack-spezifisches S4+ ergänzt), ist diese Tabelle
   > zwingend anzupassen.

3. **Eval-Gate (nur ausführen, wenn die Tabelle in 2 es fordert):**
   ```bash
   evals/run_eval.sh S1   # → evals/score_eval.sh S1 <arbeitsdir>
   evals/run_eval.sh S2   # → evals/score_eval.sh S2 <arbeitsdir>
   evals/run_eval.sh S3   # → evals/score_eval.sh S3 <arbeitsdir>
   ```
   Ablauf in `evals/README.md`; ohne Aufsicht: `evals/run_headless.sh --model <id> --effort <stufe>`.
   **Zwei Durchgänge mit jeweils 3/3 PASS erforderlich** (Agentenläufe streuen; ein PASS ist eine Stichprobe).
   Bei FAIL: **kein Tag** — Befund als Backlog-/Issue-Eintrag erfassen, Kandidat nachbessern.
   `evals/` lebt nur im Template-Repo — für einen Backport arbeitet man ohnehin dort.

4. **Audit-Eintrag im `TEMPLATE_CHANGELOG.md` (immer, ehrlich):** festhalten, *welches*
   Gate gelaufen ist — damit nachvollziehbar bleibt, was tatsächlich geprüft wurde
   (Lehre aus dem veralteten `csharp-desktop`-„ENTWURF"-Kommentar in `MANIFEST.yaml`).
   - Voller Lauf: `Eval: 2×3/3 PASS (S1 …, S2 …, S3 …, <modell>, Effort <stufe>)`
   - Scoped: z. B. `Gate: validate_template.sh + Inhalts-Review (Stack-only: csharp-desktop), S1–S3 n/a (kein Prozess-/python-cli-Change)`

4a. **Handbuch nachziehen (Template-Repo):** `handbuch/` auf den Stand vN bringen — letzter Commit vor dem Tag,
   löst kein Eval aus (Tabelle in 2); Ablauf und Ablage der PDF-/PPTX-Fassung in `handbuch/README.md`.

5. **Tag setzen (NUR nach bestandenem Gate laut 1–3):** unmittelbar davor
   `<Template-Root>/scripts/check_template_current.sh` — Exit 0 nötig, sonst liegt der Tag auf einem Stand ohne die
   inzwischen gepushten Backports anderer Projekte (dann zusammenführen und Gate 1 wiederholen).
   ```bash
   git tag vN
   git push && git push origin vN
   <Template-Root>/scripts/check_template_current.sh --require-pushed   # Exit 0: Branch und Tag sind draußen
   # Optional: git archive --format=zip -o docs_template_vN.zip vN
   ```
   Nutzt der Skill einen Git-Worktree auf dem letzten Release-Tag (abgekoppelter HEAD), ihn danach auf `vN` ziehen
   (`git -C <Skill-Verzeichnis> checkout vN`); `check_template_current.sh` im Worktree meldet einen veralteten Tag
   als `RELEASE-ALT` (Exit 1).

### 4. Bei Treffern

**Direkt umsetzen** (durch den Reflexions-Auftrag gedeckt, ohne Rückfrage): die mechanischen
Korrekturen aus Schritt 0–2 — Sektions-Invariante, veraltete Verweise auf abgeschlossene
Inkremente, Cross-Refs — und danach den Marker aus Schritt 5; offene Entscheidungspunkte halten
den Marker nicht auf. Separater Commit `docs: I#-reflection refresh` (Projekt-Docs).

**Vorlegen und Entscheidung einholen:** was Code-Wissen, Inhalt oder Roadmap betrifft (z. B.
widersprüchliche Angaben, die nur der Code klärt) sowie Template-Backports — als kurze,
priorisierte Liste (`sinnvoll/wichtig/dringend`). Backport nach Freigabe:
`<feat|fix|docs>(template): backport from <projekt> (I#-Reflexion)` (Template-Repo, dann Schritt 3b durchlaufen).
In autonomen Läufen ohne erreichbaren Prompter: diese Liste nur **vorschlagen**, keinen
Template-Commit/Tag setzen (siehe Freigabe-Disziplin in Schritt 3).

**Checks mit Fehlalarmen reparieren, nicht notieren:** Liefert ein Check dieser Reflexion (Grep, Validator,
projekt-eigener Drift-Check) Treffer, die als „bekannter Fehlalarm" übergangen werden, wird er in derselben
Reflexion repariert — z. B. Namenssuche statt Zeilenmuster — und mit einem provozierten echten Treffer
gegengeprüft. Ein Check, dessen Treffer man routinemäßig übergeht, prüft nichts.

### 5. Nach Abschluss der Reflexion

In `STATE.md` den „Nächste Reflexion bei I#"-Marker um 3 erhöhen (z.B. I6 → I9).

### 5a. Rotation großer Dateien (`docs/principles/CONTEXT_DISCIPLINE.md`, Regel c)

- `STATE.md` „Abgeschlossene Inkremente" (**bei jeder Reflexion**): Aktiv bleiben die Zeilen der Inkremente, die
  diese Reflexion begutachtet hat (seit der vorherigen Reflexion abgeschlossen, bei 3er-Kadenz 3–6 Zeilen),
  mindestens die letzte Zeile. Alle Zeilen darüber unverändert ans Ende von `docs/changelog/ARCHIVE-STATE.md`
  anhängen — eine Datei, neue Zeilen nur unten, bestehende nie ändern. Fehlt sie, mit diesem Kopf anlegen:
  ```markdown
  # Archiv – Abgeschlossene Inkremente aus STATE.md

  Rotiert aus `docs/STATE.md` (`REFLECTION.md` Schritt 5a). Neue Zeilen nur unten anhängen, bestehende nie ändern.

  ## Abgeschlossene Inkremente

  | # | Titel | Datum | Commit |
  |---|-------|-------|--------|
  ```
  `validate_project_docs.sh` liest das Archiv mit (Verletzung 2/4, Health-Check, Commit-Hashes).
- **Altformat (Projekte vor v28), einmalig:** Hat `TODO.md` noch einen Abschnitt „Abgeschlossen" mit Kurzzeilen,
  ihn samt Trennlinie entfernen — Nachweis ist die STATE-Zeile mit Hash; vorher prüfen, dass jede dort genannte ID
  in `STATE.md` oder im Archiv steht (fehlende Zeile nachtragen, Hash aus `git log`). Danach die STATE-Tabelle wie
  oben rotieren, auch wenn sie dutzende Zeilen hat.
- `CHANGELOG.md` über ~500 Zeilen: ältere Einträge in eine datierte Archivdatei unter `docs/changelog/` verschieben
  (Name z. B. `ARCHIVE-I01-I20.md`); die aktive Datei behält die letzten Inkremente und einen Verweis aufs Archiv.
- `LESSONS_LEARNED.md`: nur Einträge mit Endzustand (`backported …`, `verworfen …`, `projekt-intern`) archivieren —
  Einträge mit `Status: offen` bleiben stehen, bis Schritt 3 sie abgebaut hat.
- Archivierte LESSONS-Einträge nach `docs/changelog/LESSONS_ARCHIVE.md` — der Validator behandelt nur `changelog/`
  als Verlauf (tote Verweise in alten Einträgen sind dort Geschichte). Bereiche im Archivkopf mit Strich schreiben
  („I01–I41"), nicht „bis I41" — der Health-Check liest „bis I#" als offenen Verweis.
- **Erst Interna bereinigen, dann rotieren:** Der Interna-Hook prüft hinzugefügte Zeilen und kann verschobenen Bestand
  nicht von neuem Text unterscheiden — enthält der alte Teil Denylist-Treffer, blockiert er den Rotations-Commit.
  `--no-verify` ist keine Option.
- Wandert eine Fundstelle mit, die `docs/.placeholder-ignore` **dateibezogen** freigibt (Form `CHANGELOG.md:<Literal>`),
  den Eintrag auf die Archivdatei umstellen — sonst meldet der Validator sie dort als Platzhalter. Projektweite
  Einträge für historische Fundstellen gleich dateibezogen setzen, damit echte ungefüllte Platzhalter auffallen.
- Eigener Commit `docs: rotate state/changelog/lessons (I#)`; Git und Archiv bleiben die volle Wahrheit. Gegenprobe:
  keine nichtleere Zeile verloren (alter Stand gegen aktive Datei plus Archiv vergleichen), danach
  `validate_project_docs.sh` Exit 0.

---

> Diese Phase ist **nicht** Teil des aktuellen Inkrement-DoD — sie ist eine
> eigenständige, kurze Wartungsphase, die *vor* dem nächsten Inkrement passiert.
> Wenn nichts zu tun ist: explizit „Reflexion durchgeführt, keine Drift gefunden"
> festhalten und den Marker hochzählen.
