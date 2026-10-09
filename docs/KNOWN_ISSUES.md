# Bekannte Probleme – PSFirebirdToMSSQL

Bugs, Quirks und Einschränkungen, die **nicht** akut behoben werden, aber
dokumentiert sein müssen, damit niemand zweimal darüber stolpert.

**Abgrenzung:**

- `TODO.md` = Arbeit, die in einem priorisierten Inkrement aufgeräumt wird
- `KNOWN_ISSUES.md` = bekannt, akzeptiert oder verschoben; mit Workaround
- `BACKLOG.md` = noch unpriorisierte Ideen, keine konkreten Probleme

Stand: Code `721d5e0`, aus Code-Analyse abgeleitet (nicht alle Punkte mit echten Daten reproduziert).

---

## Aktive Probleme

| # | Beschreibung | Reproduktion | Workaround | Akzeptanzgrund | Geplant für |
|---|---|---|---|---|---|
| K3 | Inkrementelles Wasserzeichen ist strikt `> MAX(ts)` der Zieltabelle: Datensätze mit gleichem Zeitstempel, die nach dem letzten Lauf committet wurden, oder lange Firebird-Transaktionen mit älterem Zeitstempel werden bis zum nächsten Full-Lauf übersprungen | Zwei Datensätze mit identischem Zeitstempel in zwei Transaktionen schreiben, dazwischen synchronisieren | Wöchentlicher Full-Lauf (`ForceFullSync`) holt die Lücken nach | Full-Lauf deckt den Fall ab | `I8` |
| K4 | Löschungen in Firebird werden im Standardbetrieb nicht repliziert (bewusstes Design, siehe `sql_server_setup.sql`) | Datensatz in Firebird löschen, Incremental-Lauf → bleibt im Ziel | `CleanupOrphans: true` oder Weekly-Full-Lauf mit `ForceFullSync` | Design-Entscheidung (Performance, DWH-Historie) | „nie" (by design) |
| K5 | Orphan-Cleanup legt die ID-Spalte der Temp-Tabelle `#SourceIDs_<Tabelle>` als `BIGINT` an → bei nicht-numerischen IDs schlägt der Cleanup fehl; der Fehler erscheint nur in der Info-Spalte, Status bleibt „Erfolg" | Tabelle mit `VARCHAR`-ID und `CleanupOrphans: true` | `CleanupOrphans` für diese Tabelle nicht nutzen; Full-Lauf | selten genutzte Option | offen (`BACKLOG.md`) |
| K6 | Schema-Drift: neue Spalten in Firebird werden weder in Staging noch Ziel automatisch ergänzt → BulkCopy-Fehler oder Spalte fehlt im Ziel | Spalte in Firebird hinzufügen, Incremental-Lauf | `RecreateStagingTable: true` (Staging) und Zieltabelle manuell per `ALTER TABLE` ergänzen | Automatische DDL am Ziel ist riskant | offen (`BACKLOG.md`) |
| K9 | `MSSQL.Port` aus Sample/Schema wird vom Code ignoriert (Verbindung nutzt nur `MSSQL.Server`) | Abweichenden Port eintragen → keine Wirkung | Port als `Server,Port` in `MSSQL.Server` angeben | — | `I10` |

---

## Behobene Probleme

Letzte Einträge behalten bis zur nächsten Aufräum-Iteration (Spur für
Lessons Learned). Danach archivieren oder löschen.

| # | Beschreibung | Behoben in | Commit |
|---|---|---|---|
| ~~K7~~ | `config.schema.json` wurde nie geprüft | `I6` (2026-10-09) | c5f94f0 |
| ~~K8~~ | `Get_Firebird_Schema.ps1`/`Manage_Config_Tables.ps1` arbeiteten fest mit `config.json` | `I6` (2026-10-09) | c5f94f0 |
| ~~K2~~ | `NUMERIC`/`DECIMAL` wurde fest als `DECIMAL(18,4)` angelegt (Rundung ab der 5. Nachkommastelle); Inline-Mapping ohne `Guid`. Altbestand: vorher angelegte Zieltabellen behalten den alten Typ (`operations/RUNBOOK.md`) | `I5` (2026-10-08) | 2d1a7ef |
| ~~K1~~ | Sync endete immer mit Exit-Code 0, auch bei fehlgeschlagenen Tabellen; SP-Batch-Fehler nur als Warnung | `I2` (2026-10-08) | a082e9d |

---

## Pflege

- Neuer Bug ohne sofortigen Fix → Eintrag hier; TODO-Punkt **nur**, wenn
  priorisiert wird.
- Eintrag wird behoben → in „Behobene Probleme" verschieben, in der nächsten
  Aufräum-Iteration löschen.
- Diese Datei steht in der Trigger-Matrix in `KICKOFF.md` Phase 3a.
