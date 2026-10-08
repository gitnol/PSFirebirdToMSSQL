# Immutability

## Regel
Zustaende und Daten sind standardmaessig unveraenderlich.
Mutation ist die Ausnahme und muss explizit sein.

## Sprach-agnostische Vorgaben

- Funktionen mutieren ihre Eingabeparameter nicht – arbeite auf Kopien
- Globaler State wird nur durch definierte Mutations-Mechanismen veraendert
- Mutierende Funktionen kennzeichnen: update_, set_, mutate_

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
