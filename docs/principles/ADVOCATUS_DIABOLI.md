# Advocatus Diaboli (Pre-Commit-Gate, LLM-Agent)

## Regel

**Vor jedem Commit** — nicht nur in der Reflexions-Phase — greift der Agent die
eigene Arbeit **adversarial** an: Welche meiner Aussagen/Annahmen koennten falsch sein?
**Jede pruefbare Behauptung wird mit einem echten Daten-/Code-Check belegt oder
fallengelassen.** Keine narrativen "Befunde".

Das ist die strukturelle Gegenmassnahme gegen die zwei haeufigsten Agenten-Fehler:
Hypothesen als Befunde tarnen und ueber den belegten Bedarf hinaus bauen. Sie ergaenzt
[Verify before Cite](VERIFY_BEFORE_CITE.md) (Zitate) um eine Pflichtpruefung der
eigenen *Schlussfolgerungen* und des *Scopes*.

## Die drei Standardfragen (vor jedem Commit)

- **(a) Hypothese als Befund getarnt?** Wird etwas als Tatsache formuliert, das nur
  eine plausible Annahme ist? → Mit Lese-/Such-/Lauf-Operation belegen oder als Annahme kennzeichnen.
- **(b) Feature ohne End-to-End-Konsument gebaut?** Gibt es mindestens einen realen
  Pfad/Lauf, der das Neue benutzt? Wenn nein, ist der Nutzen unbelegt.
- **(c) Ueber belegten Bedarf hinaus gebaut?** Fundament nur so weit, wie die Daten
  den Bedarf zeigen (vgl. YAGNI, `YAGNI.md`).

**Tarnformulierungen, die automatisch einen Check ausloesen:** „Das Feld wird nicht
benutzt." · „Die Aenderung ist rueckwaertskompatibel." · „Der neue Pfad wird im realen
Lauf genutzt." · „Tests gruen." (ohne Laufnachweis) · „Keine Regression." (ohne
kontrollierten Vergleich — siehe [Ceteris Paribus](CETERIS_PARIBUS.md)).

## Was ein echter Check ist

Ein gueltiger Check besteht aus drei Teilen:
**Kommando** (ausgefuehrte Operation) → **Ergebnis** (was sie zurueckgab) →
**Interpretation** (was das fuer die Behauptung bedeutet).

- **Gueltig:** Symbol-/Feldsuche im Code, Testlauf mit Ausgabe, Build/Lint-Lauf,
  CLI-/Pipeline-Lauf mit Ergebnis, Git-Diff gegen Baseline, Schema-/Config-Pruefung,
  Lauf-Trace. Bei Datei-Caches/Mounts die verlaessliche Shell nutzen (Stack-Konventionen).
- **Kausale Aussage → in der Primaerquelle pruefen, nicht im Downstream-Artefakt.** Eine
  Behauptung ueber eine *Eingabe* (warum verhaelt sich X so?) wird in **dieser Eingabe** belegt
  (Rohtext/-datei), nicht in einem nachgelagerten Artefakt, das die Eingabe bereits interpretiert
  hat (LLM-Output, extrahiertes JSON, Bericht). Downstream-Artefakte taugen als *Symptom*, nie als
  *Ursachenbeleg*. Konkreter Check: das behauptete Signal direkt im Rohtext suchen (`grep`).
- **Ungueltig (Meinung, kein Check):** „sieht so aus", „wahrscheinlich", „sollte
  funktionieren", „ich habe analysiert" — reine Plausibilitaet ohne ausgefuehrte Operation.

## Konkrete Vorgaben

- **Belegen oder fallenlassen:** Beispiel-Checks — kommt das Feld/Symbol real vor?
  benutzt ein realer Lauf das Feature? stimmt die Annahme ueber den Datenbestand?
- **Blockierende Befunde VOR dem Commit beheben.** Nicht-blockierende explizit in den
  Confidence-Block des `CHANGELOG.md`-Eintrags.
- **Generische Erkenntnis** → als neues `L<N>` in `LESSONS_LEARNED.md` ablegen.

**Blockierend (vor Commit beheben):** Test/Build schlaegt fehl · behaupteter Datenbefund
nicht belegbar · neue Logik ohne realen Aufrufer · Changelog mit unbelegten Aussagen ·
Scope-Erweiterung ohne Bedarf · toter Code · produktiver Schreibzugriff, obwohl nur
Scratch erlaubt · Gate-Report fehlt/unvollstaendig.
**Nicht-blockierend (→ Confidence-Block):** Randbeobachtung ohne Einfluss aufs
Commit-Ziel · theoretische Optimierung · bewusst dokumentierte Annahme · Folgeidee
ausserhalb des Scopes. Einen Blocker nicht zum Nicht-Blocker umdeklarieren, ohne den
Befund zu beheben.

## Gate-Report (vor jedem Commit; fehlt er oder hat er offene Blocker: kein Commit)

```text
ADVOCATUS-DIABOLI-GATE
Commit-Ziel:        [ein Satz]
Gepruefte Behauptungen:
  1. Behauptung: …  Kommando: …  Ergebnis: …  Bewertung: belegt | fallengelassen | Annahme
End-to-End-Konsument: Nachweis: …  Bewertung: vorhanden | fehlt → nicht committen | nicht relevant (Begruendung)
Scope-Pruefung:     Bedarf: …  Gebaute Aenderung: …  Bewertung: passend | zu breit → was wird zurueckgestellt
Blocker:            [keiner] | [konkrete Blocker]
```

## Automatische Durchsetzung (empfohlen): PreToolUse-Hook

Damit das Gate nicht vergessen wird, blendet ein `PreToolUse`-Hook in
`.claude/settings.json` die Erinnerung vor jedem `git commit` ein (nicht-blockierend,
nur Kontext). Matcher auf die Shell-Tools, Filter auf `git commit`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "shell": "powershell",
            "timeout": 15,
            "statusMessage": "Advocatus-Diaboli-Gate",
            "command": "$j=[Console]::In.ReadToEnd()|ConvertFrom-Json; if($j.tool_input.command -match 'git commit'){'{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Advocatus-Diaboli-Gate: vor dem Commit jede pruefbare Behauptung mit echtem Daten-/Code-Check belegen oder fallenlassen. Drei Fragen: (a) Hypothese als Befund getarnt? (b) Feature ohne End-to-End-Konsument? (c) ueber belegten Bedarf gebaut? Blockierende Befunde zuerst beheben.\"}}'}"
          }
        ]
      }
    ]
  }
}
```

> Auf POSIX-only-Umgebungen den `shell`-Wert und den Matcher an die genutzten
> Tool-Namen anpassen; der Filter `git commit` bleibt gleich. Nach dem Einrichten
> ist ein `/hooks`-Reload (bzw. Session-Neustart) noetig, damit der Hook greift.

> **Robustere Variante:** Inline-PowerShell mit verschachteltem JSON ist anfaellig fuer
> Quote-/Escaping-Fehler. Stabiler ist ein externes Skript
> (`.claude/hooks/advocatus-diaboli-precommit.ps1`, auf POSIX `.sh`), das per `-File`
> aufgerufen wird und den `additionalContext` als JSON ausgibt. Optionale **Stufe 2**
> (harte Durchsetzung): ein separater Hook gibt `permissionDecision: "deny"` zurueck,
> wenn keine Gate-Report-Datei vorliegt — erst aktivieren, wenn die nicht-blockierende
> Stufe stabil laeuft, sonst entstehen unnoetige Agent-Schleifen.

## Anti-Pattern

- "Ich habe X analysiert und festgestellt, dass Y" — ohne dass eine Operation Y zeigt.
- Ein neues Modul/Feature committen, das kein realer Aufrufer benutzt ("baue ich schon mal").
- Mehrere Fundament-Inkremente ohne ein einziges, das das eigentliche Ziel adressiert.

## Wann relevant?

IMMER vor einem Commit. Greift zusammen mit der Reflexions-Selbstkritik
(`REFLECTION.md`, alle 3 Inkremente) — diese ist der periodische, das Gate der
**pro-Commit** Mechanismus.

## Verwandt

- [[VERIFY_BEFORE_CITE]] — verifiziert die *Fakten* (Pfade, Symbole, Zeilen); das Gate
  verifiziert zusaetzlich die *Schlussfolgerungen* und den *Scope*.
- [[CETERIS_PARIBUS]] — eine „keine Regression"/„Tests gruen"-Behauptung ist nur belegt,
  wenn der zugrunde liegende Vergleich kontrolliert war (genau eine Variable).
- [[YAGNI]] — Standardfrage (c): nicht ueber den belegten Bedarf hinaus bauen.

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele (typische Tarnformulierungen aus echten Befunden,
     stack-spezifische Check-Kommandos, Pfad der Hook-Skripte) hier einfuegen.
     Massgeblich fuer die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     ueberschreibbar). Jede lokale Anpassung — hier oder im Fliesstext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Typische Tarnformulierungen in diesem Projekt und der passende Check:**

| Behauptung | Check (belegen oder fallenlassen) |
|---|---|
| „Der Sync ist durchgelaufen, also ist alles synchron." | Seit I2 heißt Exit-Code 0: keine Tabelle `Fehler`, kein Sanity `FEHLER` (sofern `FailOnSanityError` aktiv) — aber nicht: Sanity `WARNUNG` ausgeschlossen, Nachkommastellen korrekt (S5: Zieltabellen aus v2.13 oder älter runden weiter), nichts übersprungen (S6). Exit-Code und Zeile `ERGEBNIS:` im Transcript `Logs\Sync_<cfg>_<ts>.log` nennen, bei Datenaussagen `COUNT(*)` Firebird vs. Zieltabelle vergleichen. |
| „Die Typen werden korrekt gemappt." | Seit v2.14 nur noch `ConvertTo-SqlServerType` (Modul, unit-getestet); `Decimal` → `DECIMAL(p,s)` aus dem Firebird-Schema. Gilt aber nur für neu angelegte Tabellen: der Sync ändert keine bestehenden. Tatsächlichen Zieltyp per `INFORMATION_SCHEMA.COLUMNS` belegen und mit `Get_Firebird_Schema.ps1` (Spalten `Precision`/`Scale`) abgleichen. |
| „Die Config wird gegen das Schema validiert." | Seit v2.15 übergeben alle vier Einstiegsskripte `-SchemaPath` (per `grep -n SchemaPath *.ps1` belegen), Verstoß → Exit 2. Aber: fehlt `config.schema.json` im Skriptordner, läuft der Sync nur mit Warnung `Schema-Datei nicht gefunden …` weiter — im Log prüfen; und „Schema bestanden" heißt nicht, dass jeder erlaubte Schlüssel wirkt (`MSSQL.Port`, S12). |
| „Der Treiber ist integritätsgeprüft." | Nur der frische Download (seit 721d5e0); vorhandene/konfigurierte DLL wird ohne Hash geladen (S4). |
| „Gelöschte Datensätze werden entfernt." | Nur mit `CleanupOrphans = true`, nur mit ID, nicht bei Snapshot/Forced (S7). |
| „Getestet." | Automatisierte Tests gibt es nur für `SQLSyncCommon.psm1` (`tests/Unit/SQLSyncCommon.Tests.ps1`, 98 Tests); die Einstiegsskripte und echte Instanzen sind nicht automatisiert getestet. Konkret benennen: welcher Lauf, gegen welche Instanz, welcher Output — sonst als „nicht live getestet" in den Confidence-Block. |

Stack-Check-Kommandos: `Invoke-ScriptAnalyzer -Path <Datei> -Severity Warning`,
`.\Test-SQLSyncConnections.ps1 -ConfigFile <Testkonfig>` (Exit 0 = OK),
`pwsh -NoProfile -File .\tests\pester.config.ps1` (Unit-Tests für `SQLSyncCommon.psm1` mit Coverage; schnell: `Invoke-Pester ./tests`). Ein Hook-Skript für das Gate ist in diesem Repo nicht
eingerichtet (kein `.claude/`-Ordner) — das Gate wird manuell vor jedem Commit angewendet.
