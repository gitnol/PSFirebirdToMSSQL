# Vertical Slice First

## Regel

Bevor einzelne Schichten vertieft werden, muss ein vollständiger, ausführbarer
Slice von der Eingabe bis zur Ausgabe existieren — als durchgehende E2E-Spec,
nicht als Reihe von Unit-Tests auf isolierten Schichten.

## Vorgehen

1. **E2E-Spec zuerst:** Der erste Inkrement nach dem Skeleton baut den durchgängigen
   Slice. Alle Zwischenschichten dürfen Stubs/Test-Doubles sein, aber der Datenfluss
   endet in einem echten, verifizierbaren Ausgabe-Artefakt.

2. **Deterministisches Test-Double im Unit-Pfad:** Teure oder nicht-deterministische
   Komponenten (LLM, OCR, externe API) werden im Unit-Pfad durch ein deterministisches
   Test-Double ersetzt (`Canned*`, `Stub*`, `Mock*`). Das Double gibt ein
   vorkonfiguriertes, gültiges Ergebnis zurück — kein LLM-Aufruf, kein Netz.

3. **Echte Engine hinter `@slow` / `@live`:** Die Integration echter Engines
   (GPU, externe API, Modell-Download) erfolgt in separaten Tests, die mit
   `@slow`, `@gpu` oder `@live` markiert sind. Diese Tests laufen nicht im
   Standard-`pytest -m unit`-Lauf.

4. **Schichten danach vertiefen:** Erst wenn der Slice grün ist, werden einzelne
   Schichten (Normalisierung, Validierung, Extraktion, …) iterativ durch echte
   Implementierungen ersetzt — Double für Double.

## Vorteile

- Regressionssicherheit von Anfang an: der durchgehende Fluss ist ab Tag 1 testbar.
- Test-Doubles erzwingen klare Kontrakt-Grenzen (Input/Output je Schicht).
- Teure Integrationen können ohne Schicht-Unterbrechung nachgereicht werden.

## Anti-Pattern

```
Schicht 1 (OCR) vollständig → dann Schicht 2 (Extraktion) → dann Schicht 3 ...
```
→ Kein durchgehender Test bis zum letzten Schritt; Fehler an Schicht-Grenzen
  werden erst spät sichtbar.

## Abgrenzung

Dieses Prinzip gilt für Pipelines, Workflows und mehrschichtige Verarbeitung.
Für reine CRUD-APIs ohne Transformationspipeline ist der erste Endpunkt der
„Slice" — dasselbe Prinzip, kleinere Skala.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
