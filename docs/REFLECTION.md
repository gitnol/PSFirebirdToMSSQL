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

Bevor strukturelle Bereinigung und Backport-Entscheidungen stattfinden, das Inkrement
aus der Teufelsperspektive begutachten:

> Analysiere das abgeschlossene Inkrement als Advocatus Diaboli:
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

Das Ergebnis fließt direkt in Schritt 3 (Template-Backport) ein: valide Lektionen
auf die Kandidatenliste, entlarvter Blödsinn fliegt raus.

### 0. Sektions-Invariante prüfen — STATE.md und TODO.md (strukturell)

**Invariante:** Eine Inkrement-ID erscheint in **genau einer** Sektion:
- `STATE.md`: entweder „Abgeschlossene Inkremente" oder „Offene Punkte", nie beide.
- `TODO.md`: entweder „Abgeschlossen" oder einem offenen Abschnitt, nie beide.

Erledigte Inkremente werden als Klartext-Kurzzeile mit `[ABGESCHLOSSEN datum]` eingetragen.
**Kein Strikethrough (`~~`) für Inkrement-IDs** — Abschluss wird durch die Sektion,
das Datum und git/CHANGELOG belegt. Leere Sektionen nach dem Cleanup vollständig entfernen.

> Strikethrough für andere Zwecke bleibt erlaubt (z. B. verworfene Einträge in
> `BACKLOG.md` „Verworfen"). Der Check unten trifft solche Einträge nicht, weil
> sie kein direktes `~~I[0-9]+`-Muster erzeugen.

**Source-of-Truth-Hierarchie (absteigend autoritativ):**
1. `git log` — maßgeblich für Commit-Hashes, Reihenfolge, tatsächliche Durchführung
2. `docs/CHANGELOG.md` — narrative Quelle für Umfang und Inhalt jedes Inkrements
3. `docs/STATE.md` — abgeleitete Sicht: nur Tabelle + Nächster-Schritt; kein
   Inhalt, der nicht aus git/CHANGELOG ableitbar ist
4. `docs/TODO.md` — abgeleitete Sicht: offene Aufgaben und DoD; „Abgeschlossen"
   ist eine Klartext-Kurzliste, kein Duplikat des CHANGELOG

> **Ein-Befehl-Variante:** Falls die Template-Skripte vorliegen, führt
> `scripts/validate_project_docs.sh docs/` die vier Struktur-Checks (Verletzung 1–4)
> plus den Health-Check (Schritt 1) gebündelt aus — statt vier einzelner Greps.
> Die expliziten Befehle unten bleiben die verbindliche Spezifikation/Fallback.

**Strukturelle Checks (alle ausführen):**
```
# Verletzung 1 – ~~I# irgendwo in docs/ → muss 0 Treffer ergeben
grep -rnE "~~I[0-9]+" docs/

# Verletzung 2 – dieselbe Inkrement-ID in ZWEI Sektionen von STATE.md
#   (sektionssensitiv: „Offene Punkte" enthält by design `| I# |`-Zeilen —
#    ein simples grep "^\| I[0-9]+" würde diese fälschlich als Treffer melden).
#   Verletzung = eine ID steht gleichzeitig in „Abgeschlossene Inkremente"
#   UND in „Offene Punkte". Muss 0 Zeilen ausgeben.
awk '
  /^## /              { sec = $0 }
  /^\| I[0-9]+/       { id = $2;
                        if (sec ~ /Abgeschlossene/) done[id] = 1;
                        else if (sec ~ /Offene/)    open[id] = 1 }
  END { for (i in done) if (i in open)
          print "Verletzung 2: " i " steht in beiden Sektionen" }
' docs/STATE.md

# Verletzung 3 – ~~I# als Abschnittsüberschrift in TODO.md → muss 0 Treffer ergeben
grep -nE "^### ~~I[0-9]+" docs/TODO.md

# Verletzung 4 – I# in STATE.md „Abgeschlossene Inkremente" aber noch als offener
#   Abschnitt (### I#:) in TODO.md → muss 0 Zeilen ausgeben.
awk '
  FNR == NR {
    if (/^## /)         sec = $0
    if (/^\| I[0-9]/ && sec ~ /Abgeschlossene/) done[$2] = 1
    next
  }
  /^### I[0-9]/ {
    id = $2; sub(/:$/, "", id)
    if (id in done) print "Verletzung 4: " id " in STATE.md abgeschlossen, aber noch offen in TODO.md"
  }
' docs/STATE.md docs/TODO.md
```
Treffer auf Verletzung 1/3: Strikethrough um Inkrement-ID entfernen.
Treffer auf Verletzung 2: Die ID gehört in **genau eine** Sektion. Ist das
Inkrement abgeschlossen → Zeile aus „Offene Punkte" entfernen; ist es noch
offen → Zeile aus „Abgeschlossene Inkremente" entfernen.
Treffer auf Verletzung 4: Den betreffenden Abschnitt (`### I#:`) aus der offenen Sektion entfernen und als Klartext-Kurzzeile in „Abgeschlossen" verschieben (drei Schritte laut KICKOFF.md Phase 3b).

**Optional – Hash-Backfill:** Fehlende Commit-Hashes (`—`) in STATE.md
„Abgeschlossene Inkremente" aus `git log --oneline` ergänzen. Autoritativer
Hash = der Haupt-`feat(I#)`-Commit des Inkrements (git ist Source of Truth).

**ZUSÄTZLICH – semantischer Konsistenz-Check (Stichprobe):** Dokumentierte
Enum-Werte (Status-Codes, Outcome-Typen, Fehler-Taxonomien) mit den echten
`StrEnum`-Definitionen im Code abgleichen (`grep -rn "class.*StrEnum" src/`).
Abweichung → Docs korrigieren (Code ist Source of Truth).

### 1. `docs/`-Health-Check

Suche nach abgeschlossenen Inkrement-IDs, die in anderen Docs noch als offen
formuliert sind:

```
grep -rnE "siehe I[0-9]+|geplant: I[0-9]+|wird in I[0-9]+ behoben|\(Hoch, I[0-9]+\)" docs/
```

Treffer auf „mitigiert in I#" / „abgeschlossen in I#" umstellen oder ganz entfernen,
wenn der Eintrag durch das Inkrement obsolet wurde (z.B. Backlog-Punkte).

**Interna-Scan (öffentliches Repo, `CONVENTIONS.md` 6.2):** alle versionierten Dateien gegen die
lokale Denylist prüfen — Treffer nach `docs/local/` verschieben bzw. durch Rollenbezeichnungen ersetzen:

```
grep -v '^#' .internal-terms > /tmp/terms.txt
git ls-files | xargs grep -HinF -f /tmp/terms.txt
```

### 2. Cross-Refs konsistent

Alle I-Nummern in `docs/` zeigen auf existierende Inkremente in `STATE.md`
(kein Renumbering-Loch).

### 2b. Roadmap-Konsolidierung

Offene Inkremente (`TODO.md`), `BACKLOG.md`, aktive `KNOWN_ISSUES.md` und `STATE.md`-Risiken gemeinsam
auf Überschneidungen (gleiche Datei/Funktion, gleiche Ursache, gleiches Risiko) und Konsolidierungen
prüfen — inklusive Backlog-Punkten, die durch erledigte Inkremente inzwischen billig oder obsolet sind.
Ergebnis: priorisierte Liste der nächsten drei Inkremente mit Begründung je Bündelung/Umordnung;
Übernahme in `TODO.md` als eigener `docs:`-Commit. Ablauf wie KICKOFF Phase 1 Punkt 2a.

### 3. Template-Backport

**Queue-Abbau:** Alle Einträge in `docs/LESSONS_LEARNED.md` mit
`Scope: generisch-*` und `Status: offen` abarbeiten — Backport ins
`Backport-Ziel` einspielen (Mechanik unten), dann `Status: backported vN` setzen.

**Freigabe-Disziplin:** Ein Backport ist eine ausdrückliche Entscheidung des Prompters.
Ohne Freigabe — insbesondere in **autonomen Läufen** — generische Lessons
(`Scope: generisch-*`, `Status: offen`) **nur als Backport-Vorschlag melden, nie selbst
ins Template committen oder taggen**. `Status: offen` bleibt unverändert, bis die Freigabe
vorliegt; erst dann Backport einspielen und `Status: backported vN` setzen.

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
> Freigegebene Backports einspielen, dann explizit stagen — **kein `git add -A`**, da im
> Template-Repo Arbeitskopien, Editor-Artefakte oder Projekt-Exporte liegen können:
> **Projektspezifisch (PSFirebirdToMSSQL):** Template-Repo liegt unter
> `D:\GIT\gitnol\docs_template` (Git-Bash: `/d/GIT/gitnol/docs_template`); dieses Projekt
> wurde mit `VERSION` 26 initialisiert. Backports betreffen typischerweise
> `stacks/powershell-automation/` oder `base/`.
> ```bash
> cd /d/GIT/gitnol/docs_template
> git status --short          # Überblick, welche Dateien geändert wurden
> git add stacks/powershell-automation/CONVENTIONS.md base/BOOTSTRAP.md   # nur tatsächlich geänderte Template-Dateien
> echo "27" > VERSION         # VERSION synchron zur neuen Tag-Nummer hochziehen (vN ↔ VERSION=N)
> git add VERSION TEMPLATE_CHANGELOG.md
> git commit -m "template: backport from PSFirebirdToMSSQL (I3-Reflexion)"
> ```
> `TEMPLATE_CHANGELOG.md` erhält den neuen Versionsblock (neueste Version oben).
> `git tag` wird erst in Schritt 3b gesetzt — **nicht** hier.

### 3b. Pre-Tag Gate — BLOCKER (**kein `git tag` ohne diesen PASS**)

Dieser Schritt ist ein harter Blocker. `git tag vN` darf **nur** ausgeführt werden,
wenn die für den Änderungsumfang geforderten Prüfungen bestanden sind. **Kein
Überspringen, kein Vorziehen des Tags.**

1. **Struktur-Validator (immer Pflicht, jede Version):**
   ```bash
   scripts/validate_template.sh   # statisch: MANIFEST ↔ Disk, Encoding, Oberflächen
   scripts/smoke_stacks.sh        # dynamisch: init_docs.sh je Stack + Pflichtdatei-Check
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
   | `base/**`, `scripts/**`, `evals/**`, `KICKOFF.md`, `REFLECTION.md`, oder die Stack-/Overlay-**Listen** in `MANIFEST.yaml` | **S1–S3 = 3/3 PASS** (Prozess wird wirklich getestet) |
   | `stacks/python-cli/**` | **S1–S3 = 3/3 PASS** — die Szenarien laden genau diesen Stack |
   | **nur** `stacks/<x>/**` (x ≠ `python-cli`) und/oder `overlays/<y>/**` | **kein S1–S3** — kein Szenario lädt diesen Stack (null Signal); stattdessen Struktur-Validator (oben, inkl. `smoke_stacks.sh --stack <x>` für den geänderten Stack) + manuelles Inhalts-Review |
   | nur Doku-Surfaces (`README.md`, `SKILL.md`, `NEUES_PROJECT_INITIALISIEREN.md`, `ALTES_PROJECT_AKTUALISIEREN.md`, `TEMPLATE_CHANGELOG.md`) | **kein S1–S3** — Struktur-Validator (inkl. Check 8) genügt |

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
   Ablauf in `evals/README.md`. **3/3 PASS erforderlich.**
   Bei FAIL: **kein Tag** — Befund als Backlog-/Issue-Eintrag erfassen, Kandidat nachbessern.
   `evals/` lebt nur im Template-Repo — für einen Backport arbeitet man ohnehin dort.

4. **Audit-Eintrag im `TEMPLATE_CHANGELOG.md` (immer, ehrlich):** festhalten, *welches*
   Gate gelaufen ist — damit nachvollziehbar bleibt, was tatsächlich geprüft wurde
   (Lehre aus dem veralteten `csharp-desktop`-„ENTWURF"-Kommentar in `MANIFEST.yaml`).
   - Voller Lauf: `Eval: 3/3 PASS (S1 …, S2 …, S3 …, <modell>)`
   - Scoped: z. B. `Gate: validate_template.sh + Inhalts-Review (Stack-only: csharp-desktop), S1–S3 n/a (kein Prozess-/python-cli-Change)`

5. **Tag setzen (NUR nach bestandenem Gate laut 1–3):**
   ```bash
   git tag vN
   # Optional: git archive --format=zip -o docs_template_vN.zip vN
   ```

### 4. Bei Treffern

Dem Prompter eine kurze, priorisierte Liste vorlegen (`sinnvoll/wichtig/dringend`),
Entscheidung einholen, dann separater Commit `docs: I#-reflection refresh`
(Projekt-Docs) bzw. `docs(template): backport from I#` (Template-Repo, dann Schritt 3b durchlaufen).
In autonomen Läufen ohne erreichbaren Prompter: Liste nur **vorschlagen**, keinen
Template-Commit/Tag setzen (siehe Freigabe-Disziplin in Schritt 3).

### 5. Nach Abschluss der Reflexion

In `STATE.md` den „Nächste Reflexion bei I#"-Marker um 3 erhöhen (z.B. I6 → I9).

---

> Diese Phase ist **nicht** Teil des aktuellen Inkrement-DoD — sie ist eine
> eigenständige, kurze Wartungsphase, die *vor* dem nächsten Inkrement passiert.
> Wenn nichts zu tun ist: explizit „Reflexion durchgeführt, keine Drift gefunden"
> festhalten und den Marker hochzählen.
