# Fail Fast

## Regel
Fehler müssen so früh, so laut und so nah an der Fehlerquelle wie möglich auftreten.
Stilles Scheitern ist verboten.

## Sprach-agnostische Vorgaben

- Validiere alle Eingaben vor der Business-Logik
- Wirf spezifische, aussagekräftige Exceptions/Errors
- Nutze findOrFail-Äquivalente statt stiller null-Rückgaben
- Kein leeres catch/except ohne Re-Raise oder Logging

## Prüffrage

"Wenn hier ein ungültiger Wert übergeben wird – wann und wie deutlich wird das gemeldet?"
→ Sofort und explizit, nicht irgendwann und still.

## Einführung neuer Prüfungen

Eine neue harte Prüfung (Namens-Whitelist, Schema-Validierung) bricht jeden Lauf ab, dessen Daten sie
nicht erfüllen — auch produktive, die bisher funktionierten. Vor dem Scharfschalten alle erreichbaren
Bestandsdaten gegen die neue Regel prüfen (ohne Inhalte auszugeben), das Ergebnis im CHANGELOG
festhalten und für nicht erreichbare Installationen einen Prüfbefehl für das Deployment dokumentieren.
Dabei fallen oft Widersprüche zwischen zwei Regelwerken auf (z. B. Schema erlaubt nur Großbuchstaben,
Whitelist auch Kleinbuchstaben). (L6, aus I4/I6 dieses Projekts)

## Verwandt

- `architecture/ERROR_HANDLING.md` — konkrete Regeln (Fehler-Hierarchie, Boundary-Konvertierung, Retry) und
  „Feindliche Eingaben": Fail Fast bricht die *Operation* ab, nicht den *Prozess*.
- [[CONTRACTS]] — Preconditions am Funktionsanfang. [[LOGGING]] — wer den Fehler loggt.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
