# Stdlib First — Implementierungs-Leiter

## Regel

> **Nicht verhandelbar:** Sicherheit, Validierung, Datenintegrität und
> Fehlerbehandlung an Trust-Boundaries sind von dieser Leiter ausgenommen —
> sie werden immer vollständig implementiert, unabhängig davon, wie kurz die
> Lösung sonst wäre.

Diese Leiter greift, sobald YAGNI grünes Licht gegeben hat. Laufe sie von
oben nach unten durch und steig aus, sobald eine Stufe greift:

1. **Stdlib kann es?** → Stdlib nutzen
2. **Natives Plattform-Feature?** → natives Feature nutzen
   (z. B. Browser-`fetch`, PowerShell-Cmdlets, .NET-LINQ, Shell-Pipes)
3. **Bereits installierte Dependency kann es?** → Dependency nutzen
4. **Geht es in einer Zeile?** → eine Zeile schreiben
5. **Erst dann:** das Minimum schreiben, das tatsächlich funktioniert

## Konkrete Vorgaben

- Datum/Zeit-Formatierung: sprachinternes Format nutzen — keine Hilfs-Bibliothek
- Text-Validierung (E-Mail, URL, …): Stdlib-Regex oder bestehende Validator-Dep —
  kein eigener Parser
- HTTP-Request: bestehende HTTP-Dep aus dem Dependency-File — kein eigener Client
- Einmalige String-Manipulation: Einzeiler inline — keine Util-Klasse
- Logik, die genau einmal an einer Stelle vorkommt: inline lassen — nicht extrahieren

## Abgrenzung zu YAGNI

| Frage | Prinzip |
|-------|---------|
| Soll diese Anforderung überhaupt implementiert werden? | YAGNI |
| Wie minimal implementiere ich sie, wenn ja? | Stdlib First |

## Prueffrage

„Habe ich die 5-Stufen-Leiter von oben nach unten durchlaufen,
bevor ich angefangen habe zu tippen?"
→ Wenn NEIN: zurück auf Stufe 1.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele und Stack-spezifische Entscheidungen
     (z. B. welche Stdlib-Module oder Deps bereits installiert sind) hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->
