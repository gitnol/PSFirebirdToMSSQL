# Test Effectiveness (Testgüte)

## Regel

Ein Test ist so viel wert wie die Fehler, die er bemerkt. Code-Abdeckung zeigt nur, welcher Code *ausgeführt*
wurde — nicht, ob ein Test eine Abweichung *erkennt*. Deshalb:

1. **Testgüte wird gemessen** — per Mutationsprüfung, nicht über die Abdeckung.
2. **Eingabe-verarbeitender Code wird mit erzeugten Eingaben geprüft** — per Eigenschaftstest, nicht nur mit
   ausgedachten Beispielen.
3. **Abdeckung ist ein Hinweis auf ungetesteten Code, kein Qualitätsziel.** Steigt sie, während die Mutationsprüfung
   gleich bleibt, ist das kein Fortschritt ([[ORACLE_AND_RATCHET]], „Proxy-Kennzahlen").

Zuständigkeit: Diese Datei regelt *wann* und *wofür*. Werkzeug und Aufruf stehen in `docs/testing/UNIT_TESTS.md`
des Stacks; die Mutationsprüfung von Hand für Charakterisierungs- und Negativtests (Ersatz für das Rot) steht in
`docs/KICKOFF.md` Phase 2; *was* richtig ist, legt [[ORACLE_AND_RATCHET]] fest.

## Mutationsprüfung

Ein Werkzeug baut kleine Fehler in den Code ein (Operator, Grenze, Rückgabewert, entfernter Aufruf). Bleiben die
Tests grün, hat der Mutant „überlebt": Es fehlt ein Test, oder ein Test prüft zu schwach (z. B. nur „nicht null").

- **Wann:** nicht in jedem Commit (zu langsam). In der Reflexion (`docs/REFLECTION.md` Schritt 1) für die seit der
  vorherigen Reflexion geänderten Dateien der deterministischen Kern-Schicht (Einsatzgrenze: `docs/KICKOFF.md`
  Phase 2), außerdem nachdem ein Agent eine Testsuite für bestehenden Code geschrieben hat.
- **Umgang mit Überlebenden:** Test ergänzen oder den Mutanten begründet als äquivalent ausweisen (Verhalten
  tatsächlich unverändert). Nie den Test an den Mutanten anpassen und nie Mutanten pauschal ausschließen.
- **Werkzeug kalibrieren:** Vor dem ersten Vertrauen in den Score einen Test vorübergehend entfernen — der Score
  muss sinken. Ein Werkzeug, das jeden Mutanten als erkannt zählt, liefert sonst einen Schein-Erfolg.
- **Kennzahl:** Der Anteil erkannter Mutanten darf als Floor mit Sperrklinke geführt werden ([[ORACLE_AND_RATCHET]]).

Belege: Die Erkennung von Mutanten korreliert mit der Erkennung echter Fehler, unabhängig von der Abdeckung
(Just et al., FSE 2014: 357 echte Fehler in fünf Projekten). Abdeckung korreliert dagegen nur schwach bis mäßig
mit der Wirksamkeit einer Testsuite, sobald ihre Größe herausgerechnet ist (Inozemtseva & Holmes, ICSE 2014).
Google setzt Mutationsprüfung inkrementell auf geänderten Code im Review ein (Petrović et al., IEEE TSE 2021).

## Eigenschaftstests (property-based testing)

Statt einzelner Beispiele erzeugt das Werkzeug viele Eingaben und prüft eine **Eigenschaft**; schlägt sie fehl,
verkleinert es die Eingabe auf ein minimales Gegenbeispiel.

- **Pflicht für:** Parser, Konverter, Serialisierer, Validatoren, Berechnungen mit festen Rechenregeln.
- **Typische Eigenschaften:**
  - Round-Trip: `parse(serialisiere(x)) == x`
  - Invariante: Summe der Positionen = Gesamtbetrag; sortierte Ausgabe bleibt sortiert
  - Robustheit: beliebige Eingabe → Ergebnis oder dokumentierte Ausnahme, nie Absturz oder Hänger
  - Vergleich mit einer einfachen, offensichtlich richtigen Referenzumsetzung
- **Reproduzierbar:** fester Seed oder der vom Werkzeug ausgegebene Seed steht im Fehlerbericht ([[CETERIS_PARIBUS]]).
- **Gegenbeispiel → fester Test:** Jedes gefundene Gegenbeispiel wird zusätzlich als Beispieltest festgeschrieben.
- Ergänzt Beispieltests mit Orakel-Werten, ersetzt sie nicht.

Belege: QuickCheck (Claessen & Hughes, ICFP 2000) begründete die Methode; in der Industrie fanden aus Spezifikationen
abgeleitete Eigenschaftstests über 200 Abweichungen in AUTOSAR-Software für Volvo Cars (Hughes 2016,
Erfahrungsbericht, kein Experiment).

## Prüffrage

„Würde ein Test rot, wenn ich in dieser Funktion `<` durch `<=` ersetze?"
→ Wenn das niemand belegen kann: Mutationsprüfung laufen lassen.

## Verwandt

- [[ORACLE_AND_RATCHET]] — was richtig ist (Referenz); diese Datei — ob die Tests Abweichungen bemerken.
- [[CETERIS_PARIBUS]] — eine Variable pro Lauf, Seed festhalten.
- [[VERTICAL_SLICE_FIRST]] — Test-Doubles im Unit-Pfad; Mutationsprüfung läuft auf diesem Pfad.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
