# Fail Fast

## Regel
Fehler muessen so frueh, so laut und so nah an der Fehlerquelle wie moeglich auftreten.
Stilles Scheitern ist verboten.

## Sprach-agnostische Vorgaben

- Validiere alle Eingaben vor der Business-Logik
- Wirf spezifische, aussagekraeftige Exceptions/Errors
- Nutze findOrFail-Aequivalente statt stiller null-Rueckgaben
- Kein leeres catch/except ohne Re-Raise oder Logging

## Prueffrage

"Wenn hier ein ungueltiger Wert uebergeben wird – wann und wie deutlich wird das gemeldet?"
→ Sofort und explizit, nicht irgendwann und still.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
