# Design by Contract

## Regel

Jede Funktion hat ein explizites Versprechen:

- **Precondition:** Was sie als Input erwartet (und ablehnt)
- **Postcondition:** Was sie als Output garantiert
- **Invariant:** Was sich durch den Aufruf niemals verändern darf

## Konkrete Vorgaben

- Schreibe für jede nicht-triviale Funktion einen Docstring mit `Args:`, `Returns:`,
  `Raises:`, optional `Invariant:`.
- Validiere Preconditions am Funktionsanfang mit `raise` (kombiniert mit Fail Fast).
- `assert`-Statements dienen ausschließlich dem Prüfen von Invarianten und Postconditions
  in Dev/Test-Umgebungen (`__debug__`). Sie dürfen **niemals** für Eingabevalidierung
  oder Produktions-Kontrollfluss genutzt werden – `assert` kann mit `-O` deaktiviert werden.

## Template

```python
def beispiel_funktion(param: str) -> str:
    """
    [Kurze Beschreibung was die Funktion tut.]

    Args:
        param: [Beschreibung. Darf None sein / darf nicht None sein.]

    Returns:
        [Beschreibung des Rückgabewerts. Garantien.]

    Raises:
        ValueError: [Wann wird dieser Fehler geworfen?]

    Invariant:
        [Was verändert sich durch diesen Aufruf NICHT?]
    """
    if not param:
        raise ValueError("param darf nicht leer sein")
    # ...
    return result
```

Eingebaute Exceptions (`ValueError`, `ArgumentException`, …) sind für **interne** Vorbedingungen gedacht, also
Programmierfehler im eigenen Code. Eingaben, die von außen kommen (CLI, HTTP, Dateien), führen zu `ValidationError`
aus der projektspezifischen Hierarchie — nur dann greift die Konvertierungstabelle in
`docs/architecture/ERROR_HANDLING.md` (Exit-Code 2 / HTTP 400) statt des Sicherheitsnetzes.

## An der Grenze umwandeln (Parse, don't validate)

Eingaben von außen (CLI-Argument, HTTP-Body, Datei, DB-Zeile, API-Antwort) werden **einmal** an der Systemgrenze
in einen Typ umgewandelt, der nur gültige Werte darstellen kann — Wertobjekt
(`docs/architecture/DOMAIN_MODEL.md`, falls vorhanden), Enum, `frozen`-Dataclass, `record`, PowerShell-Klasse. Die
Umwandlung prüft alle Vorbedingungen und wirft sonst
`ValidationError`. Danach arbeitet der Code nur mit dem geprüften Typ:

- Eine Funktion, die den geprüften Typ entgegennimmt, prüft ihn **nicht erneut** — die Vorbedingung steckt im Typ.
  „Preconditions am Funktionsanfang" (oben) gilt für Funktionen, die Rohwerte annehmen.
- Kein Rohwert (`str`, `dict`, `[hashtable]`) reist durch mehrere Schichten und wird unterwegs „zur Sicherheit"
  erneut geprüft — verteilte Prüfungen laufen auseinander.
- Ungültige Zustände nicht darstellbar machen: Enum statt `status: str` mit Prüfung; zwei Typen statt zweier
  optionaler Felder, von denen genau eines gesetzt sein muss.

```python
@dataclass(frozen=True)
class Belegnummer:
    wert: str

    def __post_init__(self) -> None:
        if not BELEGNUMMER_MUSTER.fullmatch(self.wert):
            raise ValidationError(f"ungültige Belegnummer: {self.wert!r}")
```

Hintergrund: Statische Typprüfer hätten in einer Studie mindestens rund 15 % der in JavaScript-Projekten committeten
Fehler gefunden (Gao, Bird & Barr, ICSE 2017). Die Umwandlung an der Grenze überträgt diesen Schutz auf fachliche
Werte, die der Typprüfer sonst nur als Zeichenkette kennt. Begriffe: „Parse, don't validate" (Alexis King, 2019),
„Domain Primitives" (Johnsson, Deogun, Sawano: *Secure by Design*, 2019).

## Verwandt

- [[FAIL_FAST]]

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
