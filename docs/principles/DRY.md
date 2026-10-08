# DRY – Don't Repeat Yourself

## Regel
Jedes Stueck Wissen hat genau eine autoritative Repraesentation.

## Konkrete Vorgaben

- Konfigurationswerte in Config-Dateien / Env-Variablen – nicht inline
- Wiederholte Logik in Hilfsfunktionen/Services extrahieren
- Gleiche Queries in Repository/Service kapseln

## Prueffrage

"Wenn sich diese Anforderung aendert, muss ich es an mehr als einer Stelle anpassen?"
→ Wenn JA: Refaktoriere zuerst.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
