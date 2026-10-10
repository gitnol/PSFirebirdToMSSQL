# Verify Before Cite (LLM-Agent)

## Regel

Bevor ein Dateipfad, eine Funktion, eine Zeilennummer, ein Symbol oder eine
Konfigurations-Option im Chat, Commit-Text oder Doku-Eintrag zitiert wird,
muss sie in einer **aktuellen** Lese- oder Such-Operation nachweisbar sein.

Halluzination ist der haeufigste LLM-Projektfehler. Diese Regel ist die
strukturelle Gegenmassnahme.

## Konkrete Vorgaben

- Dateipfad zitieren → vorher Read/Glob bestaetigen, dass die Datei existiert.
- Funktion / Methode / Klasse zitieren → vorher Grep bestaetigen, dass der
  Name genau so vorkommt.
- Zeilennummer zitieren → aus aktuell gelesener Datei mit Zeilen-Praefix,
  nicht aus dem Gedaechtnis.
- Konfig-Schluessel oder Env-Variable zitieren → aus aktueller Konfig- oder
  Code-Lese-Operation.
- Externe API-Endpunkte zitieren → aus aktueller Doku-/Code-Lese-Operation,
  nicht aus Vortrainings-Wissen.

## Anti-Pattern

- "Wahrscheinlich existiert die Funktion `do_x()` in `module_y.py`" — verboten
  ohne vorherige Pruefung.
- "Wie ueblich liegt die Konfig in `config.yaml`" — verboten ohne Glob.
- Pfade aus dem Gedaechtnis aus frueheren Sessions wiederverwenden — verboten;
  der Status kann veraltet sein.
- Aus Code-Patterns auf Funktionsnamen schliessen ("muesste hier `validate_input`
  geben") — Vermutung, nicht Beleg.

## Prueffrage

"Wenn der Nutzer diesen Pfad / diese Funktion / diese Zeile JETZT pruefen
wuerde — finde ich die Beweisspur in meinem Tool-Verlauf der letzten paar
Schritte?"
→ Wenn NEIN: nicht zitieren. Erst pruefen.

## Eskalation bei Unsicherheit

Wenn die Pruefung nicht moeglich ist (Datei nicht zugreifbar, externe Quelle
nicht abrufbar): den Zweifel explizit benennen ("ich vermute, habe aber nicht
verifiziert") statt eine sichere Aussage zu formulieren.

## Verwandt

- [[CONTEXT_DISCIPLINE]] — gezieltes Laden statt blindes Vermuten
- [[EXPLICIT_OVER_IMPLICIT]] — explizite Belege statt implizites Wissen
- [[FAIL_FAST]] — lieber fruehzeitig anhalten und nachpruefen, als spaeter falsch sein

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Projektbeispiele für „erst prüfen, dann zitieren":**

- **Doku ist nicht Code:** `.github/copilot-instructions.md` behauptete bis I10c, `Example_Sync_Start.ps1`
  rufe `*_Prod.ps1` auf und der Treiber werde per `Install-Package` installiert — beides
  stimmte nicht (der Treiber kommt per `Invoke-WebRequest` von NuGet in `Initialize-FirebirdDriver`).
  Aussagen aus READMEs/Agent-Hinweisen vor dem Zitieren im Code gegenprüfen.
- **Konfigschlüssel:** `MSSQL.Port` steht in `config.sample.json`/`config.schema.json`, wird vom
  Code aber nicht verwendet (S12). Schlüssel nur als wirksam zitieren, wenn `Get-SQLSyncConfig`
  oder ein Skript ihn liest (`grep -n '<Schlüssel>' *.ps1 *.psm1`). Dass eine Konfig die
  Schema-Prüfung besteht (seit v2.15 aktiv), belegt nur Form und Typen, nicht die Wirkung.
- **Exit-Codes** je Skript aus dem Code belegen (`grep -n 'exit ' <Skript>`), nicht aus der README —
  die Codes unterscheiden sich zwischen Sync, `Test-SQLSyncConnections.ps1`,
  `Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1`.
- **Nie zitieren:** Inhalte aus `config.json` / `config.json.*.bak` (nicht lesen) sowie die
  Beispiel-Zugangsdaten und den internen Servernamen aus `config.sample.json` (S3) — nur
  Fundort nennen.
