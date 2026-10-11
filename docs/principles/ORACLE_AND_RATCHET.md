# Oracle & Ratchet (Referenz-Orakel und Sperrklinke)

## Regel

Hat ein Verhalten einen **Referenzmaßstab außerhalb des eigenen Codes** — ein
Bestandssystem, das abgelöst oder angebunden wird, ein Original-Werkzeug, dessen
Ausgabe nachgebaut wird, eine Fachvorgabe mit bekannten Ergebnissen —, dann gilt:

1. **Erst das Orakel, dann die Implementierung.** Der Prüfmaßstab ist die *Ausgabe
   des Referenzsystems*, ausführbar als Test. Nicht die eigene Erwartung, sonst
   testet der Test nur die eigenen Annahmen.
2. **Fortschritt wird gemessen, nicht geschätzt.** Jede Kennzahl hat einen
   Messbefehl. Was nicht messbar ist, steht als „nicht messbar" da — nie als
   erfundene Zahl.
3. **Erreichtes wird als Floor festgeschrieben, der nur steigen darf
   (Sperrklinke).** Ein automatischer Check schlägt fehl, sobald der Messwert
   unter den Floor fällt. Wer den Wert hebt, hebt den Floor im selben Commit.

Das ist die Gegenmaßnahme gegen den häufigsten Fehler agentengetriebener
Entwicklung bei Nachbauten und Migrationen: Ein Agent hält seine Arbeit für
fertig, weil sie in sich schlüssig ist, obwohl sie vom Original abweicht — und
Fortschrittszahlen steigen, ohne dass das fachliche Verhalten besser wird.

## Wann relevant

- Ablösung, Migration oder Synchronisation eines Bestandssystems
  (Altsystem → neues System, DB → DB, Report → Report).
- Nachbau oder Import/Export von Fremdformaten (Parser, Konverter, Renderer).
- Berechnungen mit fachlich bekanntem Ergebnis (Beträge, Abgleiche, Zuordnungen).
- Performance mit vereinbartem Budget.

Nicht relevant für reines Greenfield ohne Referenz — dort tragen
Akzeptanzkriterien und TDD (`KICKOFF.md` Phase 2).

**Begriffe:** Ein *Golden Set* ist ein Orakel mit fachlich geprüften Erwartungswerten; bei nicht-deterministischen
Schichten (LLM, OCR-Modelle) wird nicht auf Gleichheit, sondern per **Metrik + Toleranz** verglichen (Overlay
`mlops-evaluation` bzw. `document-intelligence`, falls kopiert). *Fixtures* sind die Eingabedaten dazu. Die Regeln
unter „Orakel bauen" (reproduzierbar, eingefroren und gepinnt, Prüfsumme, Daten-Hygiene, begründete Änderungen)
gelten für alle drei — diese Datei ist ihr Besitzer, die Overlays verweisen hierher.

## Orakel bauen

- **Reproduzierbar erzeugt:** Ein versioniertes Generator-Skript erzeugt die
  Referenzfälle im bzw. aus dem Referenzsystem. Handgemachte Einzelfälle sind
  erlaubt, brauchen aber eine Quellenangabe (woher, wann, welche Version).
- **Klein und fokussiert:** ein Merkmal pro Fall; der Dateiname nennt Merkmal und
  Parameter. Viele kleine Fälle schlagen wenige große, weil ein Fehlschlag dann
  die Ursache schon benennt.
- **Eingefroren und gepinnt:** Live-Systeme ändern sich (Test-DB, API,
  Software-Update). Das Orakel ist ein Snapshot mit Version/Commit und
  Prüfsumme. Ein neuer Snapshot ist eine bewusste Änderung mit eigenem Commit,
  nie ein stiller Nebeneffekt.
- **Daten-Hygiene:** keine personenbezogenen, vertraulichen oder internen Daten
  im Orakel (`security/DATA_HANDLING.md`, `CONVENTIONS_COMMON.md` 3.1). Große oder
  sensible Bestände liegen außerhalb des Repos und werden per Pin + Prüfsumme
  geholt, nicht committet.
- **Fund → Regressionstest:** Jeder Fehler, den das Orakel aufdeckt, bekommt
  zusätzlich einen kleinen, synthetischen Test im Repo, der ohne das Orakel
  läuft und vor dem Fix rot war.
- **Diagnose statt Ja/Nein:** Ein Vergleichswerkzeug zeigt, *wo* und *wie stark*
  abgewichen wird (Feld, Zeile, Betrag, Pixel), nicht nur „ungleich". Ohne
  Diagnose rät der Agent.
- **Schwache Orakel kalibrieren:** Ist nur ein Ersatz-Orakel verfügbar
  (Vorschau, Teilausgabe, Fremdwerkzeug), dokumentieren, was ein PASS und was
  ein FAIL beweist: Ein PASS gegen ein ungenaues Orakel ist Beleg, ein FAIL kann
  auch der Fehler des Orakels sein.

## Floor und Sperrklinke

- Kennzahl und Floor stehen **im Code des Checks** (Test, Gate-Skript) — nicht
  nur in der Doku. Eine Sperrklinke ohne automatische Prüfung ist keine: Regeln,
  die nur als Text existieren, driften.
- **Floor heben:** im selben Commit wie die Verbesserung, mit Vorher→Nachher-Wert
  im `CHANGELOG.md`.
- **Floor senken:** nur als bewusste Entscheidung mit Begründung (ADR oder
  ausdrückliche Freigabe des Prompters), nie, um einen roten Check grün zu machen.
- **Baseline sauber messen:** gleiche Maschine/Umgebungsklasse, ruhige Last,
  Wiederholungen, genau eine Variable pro Lauf ([[CETERIS_PARIBUS]]). Ein Floor
  ist nur so viel wert wie die Messung, auf der er steht.
- **Streuende Werte** (LLM, OCR, Laufzeiten): Floor und Vergleich gelten für den **Mittelwert über ≥ 3 Läufe**
  mit einem **vorab** festgelegten Toleranzband (z. B. ±0,02 bei normierten Scores). Ein einzelner Lauf gegen
  einen einzelnen Lauf ist kein Vergleich; ein Wert innerhalb des Bandes ist weder Verbesserung noch Regression.

## Gemessen vs. geschätzt

- Gemessene Kennzahlen stehen in `STATE.md` → „Kennzahlen (gemessen)" mit Wert,
  Floor, Datum und Messbefehl. Schätzungen stehen getrennt davon und sind als
  Schätzung gekennzeichnet; widersprechen sie einer Messung, gilt die Messung.
- **Proxy-Kennzahlen nicht als Fortschritt ausgeben:** „Alle Endpunkte/Felder/
  Menüpunkte vorhanden" misst Abdeckung, nicht korrektes Verhalten. Eine Kennzahl,
  die steigt, während das Verhalten gleich bleibt, verdeckt den Rückstand
  (Goodhart). Proxy und Verhaltensmessung immer nebeneinander nennen.

## Anti-Patterns

- **Erwartungswerte selbst ausdenken** und als Orakel bezeichnen.
- **Gegen das Live-System testen** ohne eingefrorenen Snapshot — Ergebnisse
  ändern sich ohne Code-Änderung.
- **Floor in der Doku, aber kein Check** — wird beim ersten Druck ignoriert.
- **Floor senken, um den Build grün zu bekommen.**
- **Baseline auf einer ausgelasteten Maschine** — jeder spätere Vergleich ist wertlos.
- **„~85 % fertig"** ohne Messbefehl.

## Verwandt

- [[CETERIS_PARIBUS]] — eine Variable pro Messlauf, sonst keine kausale Aussage.
- [[VERIFY_BEFORE_CITE]] — Kennzahlen nur aus einem aktuellen Messlauf zitieren.
- [[ADVOCATUS_DIABOLI]] — „Tests grün" ohne Orakel ist bei Nachbauten eine Tarnformulierung.
- [[EXTERNAL_SOURCE_ADOPTION]] — Provenance und Re-Prüfung übernommener Referenzdaten.
- [[VERTICAL_SLICE_FIRST]] — der erste Slice bringt das erste Orakel mit.

## Projektspezifisch

<!-- Projekt-adaptierte Orakel-Quellen, Generator-Skripte, Kennzahlen und Floors hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
