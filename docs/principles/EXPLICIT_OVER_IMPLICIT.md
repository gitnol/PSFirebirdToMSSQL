# Explicit over Implicit

## Regel
Alles was das System tut, muss ohne Kontextwissen lesbar sein.

## Sprach-agnostische Vorgaben

- Vollstaendige Typ-Annotationen (Parameter + Rueckgabe)
- Keine Magic Strings – Konstanten oder Enums
- Seiteneffekte (DB schreiben, Datei speichern) im Funktionsnamen kennzeichnen

## Konfigurierbare Parameter als Default-Argumente

Funktionen lesen konfigurierbare Werte **nicht** direkt aus dem globalen Scope.
Stattdessen: Config-Konstante als Default-Argument → Aufrufer kann ueberschreiben.

**Falsch (implizit, schwer testbar):**
```python
def process(account, data):
    start = now() - timedelta(days=SOME_CONFIG_VALUE)  # versteckte Abhaengigkeit
```

**Richtig (explizit, testbar):**
```python
def process(account, data, days: int = SOME_CONFIG_VALUE):
    start = now() - timedelta(days=days)  # Abhaengigkeit sichtbar im Funktionskopf
```

Ausnahmen (direkte Nutzung globaler Konstanten ist akzeptabel):
- Technische Compile-Zeit-Konstanten (z.B. Buffer-Groessen, Protokoll-Konstanten)
- Flags die das gesamte Programm betreffen (`DEBUG`)
- Credentials – kommen ausschliesslich via Secrets-Manager, nie als Parameter

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
