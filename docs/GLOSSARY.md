# Glossar – PSFirebirdToMSSQL

Ubiquitous Language für dieses Projekt. Jeder Begriff hat genau eine Bedeutung.
Synonyme oder doppelt belegte Begriffe schaffen Drift und werden vermieden.

LLM-Agenten konsultieren dieses Glossar, **bevor** sie Begriffe im Code, in
Commit-Messages oder in Doku verwenden.

---

## Begriffe

| Begriff | Bedeutung | Wo verwendet | Nicht zu verwechseln mit |
|---|---|---|---|
| Lauf | Ein Aufruf von `Sync_Firebird_MSSQL_AutoSchema.ps1` mit genau einer Konfigdatei, inkl. Pre-Flight, Tabellenverarbeitung, Zusammenfassung und Log-Rotation | Hauptskript, Logdateiname `Sync_<cfg>_<ts>.log` | Versuch (Retry einer einzelnen Tabelle) |
| Versuch | Ein Durchgang der Retry-Schleife für eine Tabelle (max. `MaxRetries + 1`) | Hauptskript, Ergebnisfeld `Versuche` | Lauf |
| Job-Profil | Eine Konfigdatei für einen bestimmten Zweck (z. B. Daily Diff, Weekly Full), aufgerufen per `-ConfigFile` | `Setup-ScheduledTasks.ps1`, `Example_Sync_Start.ps1` | Konfiguration im Allgemeinen |
| Quelltabelle | Tabelle in der Firebird-Datenbank, wie in `Tables` eingetragen (Großschreibung, z. B. `BKUNDE`) | `config.json` `Tables`, Variable `$Tabelle` | Zieltabelle |
| Staging-Tabelle | SQL-Server-Tabelle `STG_<Quelltabelle>`, wird pro Lauf geleert und per SqlBulkCopy befüllt | Hauptskript Schritt B/D | Temp-Tabelle |
| Zieltabelle | SQL-Server-Tabelle `<Prefix><Quelltabelle><Suffix>`, in die per MERGE bzw. Snapshot geschrieben wird | Hauptskript Schritt E, `$TargetTableName` | Staging-Tabelle |
| Temp-Tabelle | Ausschließlich `#SourceIDs_<Quelltabelle>` beim Orphan-Cleanup | Hauptskript Schritt G | Staging-Tabelle |
| Sync-Strategie | Pro Tabelle und Lauf ermittelte Verarbeitungsart: `Incremental`, `FullMerge`, `FullMerge (Forced)`, `Snapshot` | Hauptskript, `Get-TableColumnConfig` | — |
| Incremental | ID- und Timestamp-Spalte vorhanden: nur Zeilen mit Zeitstempel > Wasserzeichen werden geladen und gemergt | Hauptskript | FullMerge |
| FullMerge | ID vorhanden, keine Timestamp-Spalte: alle Zeilen laden und mergen; `FullMerge (Forced)` = durch `ForceFullSync` erzwungen (Ziel wird vorher geleert) | Hauptskript | Snapshot |
| Snapshot | Keine ID-Spalte: Zieltabelle wird geleert und komplett neu befüllt | Hauptskript | FullMerge |
| ID-Spalte | Primärschlüssel-Spalte für MERGE und PK, global `IdColumn` oder per `TableOverrides` | `Get-SQLSyncConfig`, `sp_Merge_Generic` | — |
| Timestamp-Spalte | Änderungszeitstempel einer Tabelle; erste vorhandene aus `TimestampColumns` oder `TableOverrides.<T>.TimestampColumn` | `Get-SQLSyncConfig`, `Get-TableColumnConfig` | Wasserzeichen |
| Wasserzeichen | `MAX(<Timestamp-Spalte>)` der Zieltabelle zu Beginn des Laufs; Untergrenze für den Incremental-Extrakt (Default `1900-01-01`) | Hauptskript Schritt C | Timestamp-Spalte |
| TableOverrides | Tabellenspezifische Abweichungen für ID- und Timestamp-Spalte | `config.json`, `Get-SQLSyncConfig` | — |
| Orphan | Datensatz in der Zieltabelle, dessen ID in der Quelltabelle nicht mehr existiert | Hauptskript Schritt G | — |
| Orphan-Cleanup | Optionales Löschen von Orphans (`CleanupOrphans`) über einen ID-Abgleich | Hauptskript Schritt G | Full-Lauf |
| Sanity Check | Vergleich `COUNT(*)` Quelltabelle vs. Zieltabelle nach dem Merge: `OK`, `WARNUNG (+n)`, `FEHLER (-n)` | Hauptskript Schritt H | Pre-Flight Check |
| Pre-Flight Check | Prüfung/Anlage der Ziel-Datenbank und von `sp_Merge_Generic` vor der Tabellenverarbeitung | Hauptskript Abschnitt 7 | Sanity Check |
| `sp_Merge_Generic` | Generische Stored Procedure für das MERGE Staging → Ziel (4 Parameter) | `sql_server_setup.sql` | — |
| Credential-Target | Name eines Eintrags im Windows Credential Manager; Defaults `SQLSync_Firebird`, `SQLSync_MSSQL`, konfigurierbar über `Firebird.CredentialTarget` / `MSSQL.CredentialTarget` und `Setup_Credentials.ps1 -FirebirdTarget` / `-MSSQLTarget` | `SQLSyncCommon.psm1`, `Setup_Credentials.ps1`, Konfigdatei | Benutzername |
| Treiber | Firebird-.NET-Provider `FirebirdSql.Data.FirebirdClient` (10.3.4) | `Initialize-FirebirdDriver` | ODBC-Treiber |

---

## Verbotene Synonyme

Begriffe, die im Projekt-Kontext **nicht** mehr verwendet werden dürfen,
auch wenn sie umgangssprachlich gleichbedeutend wirken:

| Verbotener Begriff | Korrekt | Grund |
|---|---|---|
| Spiegel / Mirror / Kopie-Tabelle | Zieltabelle | Ziel ist kein exakter Spiegel (Löschungen standardmäßig nicht repliziert) |
| Temp-Tabelle (für `STG_`) | Staging-Tabelle | „Temp-Tabelle" ist für `#SourceIDs_*` belegt |
| Delta-Tabelle | Staging-Tabelle | Staging enthält bei FullMerge/Snapshot den Vollbestand |
| Job (für eine Konfigdatei) | Job-Profil | „Job" meint in der Doku die geplante Aufgabe im Task Scheduler |
| Soft Delete | Orphan-Cleanup | Es wird physisch gelöscht, nicht markiert |

---

## Pflege

- Neuer Domänenbegriff im Code → **vor dem Commit** hier ergänzen.
- Begriff wird umbenannt → alter Eintrag bleibt mit Vermerk „ersetzt durch <neu>"
  stehen (mindestens eine Inkrement-Generation als Übergangsphase).
- Begriff entfällt → Eintrag mit „deprecated <Datum>" markieren, nicht löschen.
- Diese Datei steht in der Trigger-Matrix in `KICKOFF.md` Phase 3a.
