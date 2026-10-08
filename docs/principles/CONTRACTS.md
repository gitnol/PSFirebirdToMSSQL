# Design by Contract

## Regel

Jede Funktion hat ein explizites Versprechen:

- **Precondition:** Was sie als Input erwartet (und ablehnt)
- **Postcondition:** Was sie als Output garantiert
- **Invariant:** Was sich durch den Aufruf niemals veraendern darf

## Konkrete Vorgaben

- Schreibe fuer jede nicht-triviale Funktion einen Docstring mit `Args:`, `Returns:`,
  `Raises:`, optional `Invariant:`.
- Validiere Preconditions am Funktionsanfang mit `raise` (kombiniert mit Fail Fast).
- `assert`-Statements dienen ausschliesslich dem Pruefen von Invarianten und Postconditions
  in Dev/Test-Umgebungen (`__debug__`). Sie duerfen **niemals** fuer Eingabevalidierung
  oder Produktions-Kontrollfluss genutzt werden – `assert` kann mit `-O` deaktiviert werden.

## Template

```python
def beispiel_funktion(param: str) -> str:
    """
    [Kurze Beschreibung was die Funktion tut.]

    Args:
        param: [Beschreibung. Darf None sein / darf nicht None sein.]

    Returns:
        [Beschreibung des Rueckgabewerts. Garantien.]

    Raises:
        ValueError: [Wann wird dieser Fehler geworfen?]

    Invariant:
        [Was veraendert sich durch diesen Aufruf NICHT?]
    """
    if not param:
        raise ValueError("param darf nicht leer sein")
    # ...
    return result
```

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
