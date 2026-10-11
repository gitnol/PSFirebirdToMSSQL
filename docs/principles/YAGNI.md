# YAGNI – You Aren't Gonna Need It

## Regel
Implementiere ausschließlich was in der aktuellen TODO.md gefordert ist.

## Konkrete Vorgaben

- Keine Abstraktionen für weniger als 2 konkrete Nutzer — gezählt werden Aufrufer **oder** Implementierungen;
  ein Test-Double nach [[VERTICAL_SLICE_FIRST]] zählt als Implementierung (ein Adapter-Interface nach
  [[SEPARATION_OF_CONCERNS]] mit echter Implementierung und Test-Double ist also gedeckt)
- Nicht priorisierte Ideen in `BACKLOG.md` eintragen – nicht implementieren

## Prüffrage

"Steht diese Anforderung explizit in TODO.md?"
→ Wenn NEIN: nicht implementieren.

## Verwandt

- [[SEPARATION_OF_CONCERNS]]
- [[VERTICAL_SLICE_FIRST]]
- [[ADVOCATUS_DIABOLI]]
- [[CONTEXT_DISCIPLINE]]

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
