# Vertical Slice First

## Regel

Bevor einzelne Schichten vertieft werden, muss ein vollständiger, ausführbarer
Slice von der Eingabe bis zur Ausgabe existieren — als durchgehende E2E-Spec,
nicht als Reihe von Unit-Tests auf isolierten Schichten.

## Vorgehen

1. **E2E-Spec zuerst:** Das erste Inkrement nach dem Skeleton baut den durchgängigen
   Slice. Alle Zwischenschichten dürfen Stubs/Test-Doubles sein, aber der Datenfluss
   endet in einem echten, verifizierbaren Ausgabe-Artefakt.

2. **Deterministisches Test-Double im Unit-Pfad:** Teure oder nicht-deterministische
   Komponenten (LLM, OCR, externe API) werden im Unit-Pfad durch ein deterministisches
   Test-Double ersetzt (`Canned*`, `Stub*`, `Mock*`). Das Double gibt ein
   vorkonfiguriertes, gültiges Ergebnis zurück — kein LLM-Aufruf, kein Netz.

3. **Echte Engine hinter Markern:** Die Integration echter Engines
   (GPU, externe API, Modell-Download) erfolgt in separaten Tests mit Markern aus der
   **Kernmenge** (bzw. dem Stack-Äquivalent, z. B. Pester-Tags, xUnit-Traits):

   | Marker | Bedeutung |
   |---|---|
   | `unit` | ohne Netz, DB, GPU und echte Engine; Tests ohne Kernmarker gelten als Unit-Tests |
   | `integration` | echte lokale Infrastruktur (Datenbank, Container); ein Slice mit Test-Doubles (Punkt 2) bleibt im Unit-Pfad |
   | `slow` | lange Laufzeit (über ca. 5 s) |
   | `gpu` | benötigt eine lokale GPU |
   | `live` | echte Engine oder echter Dienst statt Test-Double (externe API, Modell, OCR-Engine, externes Werkzeug), Credentials, Kosten oder geschützte Daten; nur manuell oder in einem eigenen Job |

   Ein Test darf mehrere Marker tragen. Alles außer `unit` läuft nicht im Standard-Unit-Lauf
   (Gate 4, `CONVENTIONS_COMMON.md` §5): Der Stack registriert die Marker, die er nutzt, und schließt
   sie in Gate 4 aus. Overlays definieren keine eigene Kernmenge, nur **Zusatzmarker** für ihre
   Domäne (z. B. `llm`, `golden`); ein Zusatzmarker impliziert `live` (der Test trägt beide) und wird
   im Stack registriert.

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

## Verwandt

- [[ORACLE_AND_RATCHET]]
- [[YAGNI]]

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
