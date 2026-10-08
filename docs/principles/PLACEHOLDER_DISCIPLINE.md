# Placeholder Discipline

## Regel

Ein Scaffold-Adapter oder Test-Double darf nicht als fertiges Feature erscheinen.
Platzhalter müssen ihren Status durch **Namen** und **Docstring** explizit machen
und als Known Limitation sichtbar sein.

## Konventionen

- **Namenspräfix:** Platzhalter-Klassen und -Funktionen tragen `Canned`, `Stub`,
  `Mock`, `Fake` oder `Dummy` im Namen — nie ein fachlicher Name ohne Qualifikation.
  Beispiel: `CannedAdapter`, `StubOcrEngine`, nicht `InvoiceAdapter`.
- **Docstring-Zeile 1:** Beschreibt explizit, was die echte Implementierung tun
  würde und warum sie noch fehlt. Format:
  ```python
  class CannedAdapter:
      """Test-Double / Dev-Stub — gibt vorkonfiguriertes Ergebnis zurück.
      Kein LLM-Aufruf, kein OCR. Echte Extraktion (LangExtract) noch nicht gebaut.
      """
  ```
- **Known Limitation:** Jeder Platzhalter, der in Produktionscode verdrahtet ist
  (auch Demo-Pfad), erhält einen Eintrag in `docs/KNOWN_ISSUES.md`. Der Eintrag
  beschreibt, was fehlt, was stattdessen passiert, und für welches Inkrement die
  echte Implementierung vorgesehen ist.
- **Keine Vernebelung:** Integrationstests oder Demo-Flows, die Platzhalter
  verwenden, kommentieren dies explizit. Kein Ausgabe-Format, das suggeriert,
  echte Daten würden verarbeitet.

## Anti-Pattern

```python
# Schlecht — fachlicher Name, kein Hinweis auf Platzhalter-Status:
class InvoiceExtractionAdapter:
    def extract(self, doc):
        return {"invoice_number": "RE-2024-001", "total": 100.0}  # hardcoded

# Gut — Name + Docstring + Known-Issues-Eintrag:
class CannedAdapter:
    """Test-Double: gibt vorkonfiguriertes Ergebnis zurück. Kein LLM-Aufruf.
    Echte Extraktion (LangExtract-Adapter) → KNOWN_ISSUES.md K4.
    """
    def extract(self, doc):
        return {"invoice_number": "RE-2024-001", "total": 100.0}
```

## Opt-in-Regel für echte Adapter (B4)

Der Offline-/Demo-Adapter ist **immer** der sichere Default. Der echte Adapter
(LLM-Aufruf, externe API, GPU-Inferenz) wird ausschließlich über expliziten
Opt-in aktiviert — niemals als Default.

**Konvention:**

```python
# config.py
extraction_adapter: Literal["canned", "llm"] = "canned"  # Default: Offline/Demo
```

```python
# Verdrahtung in der Factory / DI-Provider:
if settings.extraction_adapter == "llm":
    return LLMExtractionAdapter(HttpxLLMClient(...))  # echter Adapter, Opt-in
return CannedAdapter(demo_result)                      # Default, kein Netzwerk
```

**Warum Default = Offline:**
- Verhindert unbeabsichtigte externe Aufrufe (API-Kosten, Datenlecks, DSGVO-Risiko)
  in neuen Deployments, CI-Runs oder Test-Setups ohne explizite Konfiguration.
- Deployment ohne Env-Var → Offline-Modus, keine stillen Fehler durch fehlendes
  LLM-Backend.
- Opt-in-Flag macht die Absicht sichtbar und dokumentierbar (`.env.example`,
  `CONFIGURATION.md`).

**Known-Issues-Eintrag Pflicht:** Solange der echte Adapter nicht Default ist,
muss ein K#-Eintrag in `KNOWN_ISSUES.md` beschreiben, was fehlt und wie man
den echten Adapter aktiviert.

## Warum

Ein Scaffold, der nicht erkennbar als Scaffold markiert ist, führt zu:
- falschen Vertrauensurteilen in Demo und Review
- Tests, die grün sind, obwohl kein echter Pfad geprüft wird
- Known Limitations, die nie in die Docs finden, weil der Platzhalter „ja läuft"

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
