# Ceteris Paribus — eine Variable pro Test

## Regel

Wenn aus einem Test, Vergleich, Benchmark oder Bugfix eine **Schlussfolgerung**
gezogen werden soll („X hat geholfen", „Y ist die Ursache", „Z ist schneller"),
darf zwischen Baseline und Mutation **exakt eine Variable** verändert worden sein.
Alle anderen Einflussgrößen sind entweder nachweislich konstant oder als
unkontrollierbare Varianz explizit protokolliert.

**Jeder Lauf, bei dem mehr als eine Variable unkontrolliert variieren kann, trägt
keine kausale Aussage.** Er ist als Test ungültig zu kennzeichnen — kein Ergebnis
aus einem konfundierten Lauf interpretieren.

Das ist die strukturelle Gegenmaßnahme gegen den häufigsten Fehlschluss nach
Mehrfachänderungen: aus „danach war es besser/schlechter" auf *eine* Ursache zu
schließen, obwohl mehrere Dinge gleichzeitig anders waren.

## Konkrete Vorgaben

- **Eine Mutation pro Lauf.** Genau eine geänderte Größe: eine Code-Zeile, ein
  Konfig-Wert, ein Parameter, eine Abhängigkeitsversion, ein Prompt-Satz, eine
  Eingabe. Mehrere Änderungen zusammen sind nur als ausdrücklich markierter
  **Interaktionstest** zulässig — und der erlaubt keine Einzelursachen-Aussage.
- **Metrik vor dem Lauf festlegen.** Zielmetrik, Akzeptanzschwelle und erwartete
  Wirkungsrichtung stehen schriftlich fest, *bevor* der Test läuft. Nachträglich
  gewählte Metriken machen den Test ungültig (kein Ergebnis-Shopping).
- **Stabile Baseline zuerst.** Ist das System nicht-deterministisch (Nebenläufigkeit,
  Zeit, Zufall, externe Dienste, LLM/Agent), die Baseline mehrfach laufen lassen und
  prüfen, ob die Metrik unter einer vorher definierten Schwelle stabil ist. Instabile
  Baseline → erst Ursache klären, **kein** Mutations-Lauf.
- **Confounder konstant oder protokolliert.** Externe Abhängigkeiten (APIs, DB,
  Dateien, Netzwerk, Uhrzeit) entweder fixieren oder, wenn unvermeidbar variabel,
  im Befund explizit als unkontrollierte Quelle benennen.
- **Test invalidieren statt schönreden.** Stellt sich während eines Laufs heraus,
  dass eine zweite Größe mitvariiert hat (anderer Branch, andere Daten, anderer
  Seed), Lauf abbrechen, Grund protokollieren, Status `Test ungültig`.

## Prüffrage

„Wenn dieser Test ein anderes Ergebnis liefert als die Baseline — kann ich mit
Sicherheit sagen, dass **diese eine** Änderung der Grund ist, und nicht etwas
anderes, das nebenbei mitvariiert hat?"
→ Wenn NEIN: Es ist kein kausaler Befund. Variablen isolieren und erneut testen.

## Anti-Pattern

- „Ich habe A, B und C geändert, jetzt sind die Tests grün — also lag es an A."
  (Drei Variablen, keine Einzelursache belegt.)
- Baseline und Mutation gegen unterschiedliche Daten/Branches/Fixtures laufen lassen
  und das Delta der Änderung zuschreiben.
- Bei nicht-deterministischen Systemen aus **einem** Baseline- und **einem**
  Mutations-Lauf eine Verbesserung ableiten (Streuung nicht von Effekt getrennt).
- Die Erfolgsmetrik erst nach Sicht des Ergebnisses wählen.

## Verwandt

- [[ADVOCATUS_DIABOLI]] — belegt die *Schlussfolgerung* eines Laufs adversarial;
  Ceteris Paribus stellt sicher, dass der Lauf überhaupt eine kausale Aussage trägt
  („keine Regression" ohne kontrollierten Vergleich ist keine belegte Behauptung).
- [[VERIFY_BEFORE_CITE]] — verifiziert *Fakten* (Pfade, Symbole); Ceteris Paribus
  verifiziert *Kausalität* von Test-Ergebnissen.
- [[FAIL_FAST]] — konfundierten Lauf sofort abbrechen statt fragwürdig auswerten.

> **Tiefe Eval-Operationalisierung (LLM/Agenten):** Das vollständige Protokoll für
> nicht-deterministische LLM-/Agenten-Workflows — Fixture-Zwang, SHA256-Hashes über
> System-/User-Prompt/Tool-Schema, Seed-Determinismus, Baseline-3×, extended-thinking-
> Nichtdeterminismus, 8-Punkte-Selbst-Check — lebt im `mlops-evaluation`-Overlay
> (`architecture/EVALUATION.md`, Abschnitt „Ceteris-Paribus-Protokoll"; Overlay in diesem Projekt nicht kopiert). Es ist eine
> Stack-/Domänen-Konkretisierung dieses Prinzips, kein Ersatz.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele (welche Variablen typischerweise mitvariieren:
     Caches, Migrations-Stände, Seeds, Modellversionen), Mess-Setup und
     Stabilitäts-Schwellen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Variablen, die bei Sync-Läufen typischerweise unbemerkt mitvariieren:**

- **Datenstand der Quelle:** Firebird ist ein laufendes ERP — zwischen zwei Läufen ändern sich
  Zeilen. Vergleichsläufe gegen eine eingefrorene Test-/DEMO-Datenbank oder in einem
  ruhigen Zeitfenster fahren.
- **Wasserzeichen:** Der inkrementelle Lauf hängt von `MAX(<Timestamp-Spalte>)` der
  Zieltabelle ab. Wer „Fix X macht den Lauf schneller" behauptet, muss gleiches
  Wasserzeichen sicherstellen (gleicher Zielstand, gleiche Strategie).
- **Konfigflags:** `ForceFullSync`, `RecreateStagingTable`, `RecreateStoredProcedure`,
  `CleanupOrphans`, `NumberOfThreads`, `TableOverrides` — pro Vergleich genau eines ändern;
  Job-Profile (Daily Diff vs. Weekly Full) nie gegeneinander vergleichen.
- **Vorhandene Objekte:** existierende `STG_*`-/Zieltabellen und `sp_Merge_Generic` verändern den
  Ablauf (Anlegen vs. Wiederverwenden). Ausgangszustand der Test-Ziel-DB vorher festhalten.
- **Treiber/Umgebung:** geladene Treiberversion (`%ProgramData%\SQLSync\Drivers\...` vs. `DllPath`),
  PowerShell-Version, Konto (Credential-Manager-Einträge sind kontogebunden).

**Mess-Setup:** Dauer und `RowsLoaded` pro Tabelle aus der Zusammenfassung am Laufende bzw. dem
Transcript entnehmen; für Laufzeitvergleiche mindestens drei Läufe pro Variante, Streuung angeben.
Eine feste Stabilitätsschwelle ist noch nicht festgelegt (offen bis zum ersten Benchmark).
