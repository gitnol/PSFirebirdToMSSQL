# Context Discipline (LLM-Agent)

## Regel

Lade nur die Dateien, die du für die aktuelle Aufgabe nachweislich brauchst.
Mehr Kontext bedeutet mehr Halluzinationsrisiko, langsamere Iterationen und
höheren Token-Verbrauch.

## Konkrete Vorgaben

- Vor dem Laden einer Datei: nenne den konkreten Grund ("brauche ich, weil...").
- Lade nicht "auf Verdacht" — wenn unklar ist, ob eine Datei relevant ist,
  erst per Grep/Glob zielgerichtet prüfen.
- Wenn eine Datei sehr gross ist (Richtwert > 500 Zeilen): nur den relevanten
  Bereich lesen (`offset` + `limit`), nicht die ganze Datei.
- Verweise auf Dateien in Doku oder Antworten NIEMALS aus Erinnerung, sondern
  aus aktueller Lese-Operation.
- Wenn der Inkrement-Scope klein ist: max. 3–5 Dateien aktiv im Kontext halten.
- `principles/INDEX.md` zeigt, welche Prinzipien zu laden sind — nicht alle.

## Prüffragen

- "Wenn ich diese Datei nicht lade — fehlt mir Information, die ich aus
  `STATE.md`, `architecture/OVERVIEW.md` oder dem Inkrement-Beschrieb nicht
  ableiten kann?"
  → Wenn NEIN: nicht laden.

- "Habe ich diese Datei in der letzten ~5 Schritten tatsächlich gelesen,
  oder erinnere ich mich nur an sie?"
  → Wenn nur Erinnerung: prüfen, dass sie noch existiert und unverändert ist.

## Wachsende Append-Docs

Einige Docs (CHANGELOG, LESSONS_LEARNED, die Tabelle „Abgeschlossene Inkremente" in STATE) wachsen
unbegrenzt durch Anhängen. Sie kosten bei Full-Load überproportional Token und verdünnen den aktuellen Stand,
ohne dem laufenden Inkrement zu nützen.

- **(a) Default-Lesescope ausschließen:** CHANGELOG und LESSONS_LEARNED sind kein
  Pflicht-Lesekontext für normale Inkremente — erst laden, wenn konkret benötigt.
- **(b) Write-only anhängen:** Nur den Kopf der Datei lesen (Format-Check, max. 20–30 Zeilen),
  dann neuen Eintrag oben voranstellen (prepend) — nie die gesamte Datei laden.
- **(c) Rotation an Reflexions-Kadenz:** An der 3-Inkremente-Reflexion wandert älterer
  Inhalt in Archivdateien unter `docs/changelog/` (z. B. `ARCHIVE-I01-I20.md` für CHANGELOG,
  `ARCHIVE-STATE.md` für die STATE-Tabelle — sie behält nur die Inkremente seit der vorherigen Reflexion).
  Git + Archiv = volle Wahrheit; aktive Datei bleibt token-gebunden. Ablauf: `REFLECTION.md` Schritt 5a.

## Anti-Pattern

- "Sicherheitshalber lade ich noch X.py" — verboten ohne konkreten Grund.
- "Ich lese die ganze Datei, um den Kontext zu verstehen" bei einer Datei,
  von der nur eine Funktion relevant ist — verboten; gezielt lesen.
- Mehrere Dateien parallel laden, ohne im Anschluss zu erklären, warum jede
  davon nötig war.

## Verwandt

- [[VERIFY_BEFORE_CITE]] — Disziplin beim Zitieren, nicht nur beim Laden
- [[YAGNI]] — Vorausschauendes Laden ist YAGNI für Kontext
- [[EXPLICIT_OVER_IMPLICIT]] — expliziter Lade-Grund statt implizites Vermuten

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Lade-Landkarte für dieses Repo (flaches Layout, alles im Root):**

| Aufgabe | Laden | Nicht laden |
|---|---|---|
| Sync-Ablauf, Strategien, Retry | `Sync_Firebird_MSSQL_AutoSchema.ps1` (744 Z. → gezielt per `offset`/`limit`) | READMEs (teils veraltet) |
| Config, Credentials, Connection-Strings, Treiber, Typmapping | `SQLSyncCommon.psm1` (932 Z. → relevante Region) | — |
| MERGE-Logik | `sql_server_setup.sql` | — |
| Konfigschlüssel | `config.sample.json`, `config.schema.json`, `architecture/CONFIGURATION.md` | **`config.json`, `config.json.*.bak` — nie lesen** (können Klartext-Passwörter enthalten) |
| Scheduled Tasks | `Setup-ScheduledTasks.ps1`, `operations/TASK_SCHEDULER.md` | — |
| Laufergebnisse | einzelnes Log aus `Logs/` gezielt (grep auf „Fehler"/„FEHLER") | nicht den ganzen `Logs/`-Ordner |

`.github/copilot-instructions.md` ist seit I10c eine Kurzfassung mit Verweisen auf `docs/` — Fakten aus `docs/` und dem Code laden, nicht aus dieser Datei.
