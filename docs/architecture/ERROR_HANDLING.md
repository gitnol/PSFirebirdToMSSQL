# Fehlerbehandlung – PSFirebirdToMSSQL

Wo und wie Fehler erkannt, propagiert, behandelt und gemeldet werden.
Konsolidiert Regeln, die sonst in `CONVENTIONS.md`, `principles/FAIL_FAST.md`,
`principles/CONTRACTS.md` und `principles/LOGGING.md` verstreut sind.

---

## Fehler-Modell

- Es gibt **keine** eigene Exception-Hierarchie. Fehler sind:
  - **`throw "<deutsche Meldung>"`** in `SQLSyncCommon.psm1` (String-Exceptions mit handlungsleitendem Text,
    z. B. `"Keine Firebird Credentials gefunden! Führe Setup_Credentials.ps1 aus."`),
  - **.NET-Exceptions** der Datenbanktreiber (`FbException`, `SqlException`), die als terminierende Fehler ankommen,
  - **Cmdlet-Fehler** mit `-ErrorAction Stop` (`Get-Content`, `ConvertFrom-Json`, `Invoke-WebRequest`).
- Kein globales `$ErrorActionPreference = 'Stop'`; nicht-terminierende Fehler anderer Cmdlets laufen weiter.
- Unterscheidung erfolgt **nach Phase** (welcher `try`-Block hat gefangen), nicht nach Exception-Typ.
  Daraus ergibt sich der Exit-Code.

Für neuen Code: weiterhin `throw` mit klarer deutscher Meldung im Modul; wenn Aufrufer verschiedene Ursachen
unterscheiden müssen, `ErrorRecord` mit `ErrorCategory` statt String-Parsing verwenden.

---

## Boundary vs. interne Fehler

| Ebene | Verhalten im Projekt |
|---|---|
| **Skriptgrenze** (Phasen 1–7 im Sync-Skript, Setup-/Diagnoseskripte) | `try { … } catch { Write-Error "KRITISCH: $($_.Exception.Message)"; Stop-Transcript; exit <n> }`. Keine Stacktraces, nur Meldung. |
| **Modul** (`SQLSyncCommon.psm1`) | `throw` mit deutscher Meldung, kein eigenes Logging, kein `exit`. Ausnahme: `Get-SQLSyncConfig` wandelt Parse-Fehler in eine eigene Meldung um. |
| **Tabellen-Verarbeitung** (Parallel-Block, Phase 8) | Fehler werden **pro Tabelle** gefangen, in `Status = "Fehler"` und `Info` übertragen, rot ausgegeben und per Retry wiederholt. Ein Tabellenfehler bricht den Lauf **nicht** ab, führt aber am Ende zu Exit-Code `10`. |
| **Laufende** (Abschnitt 11 im Sync-Skript) | `Get-SyncExitCode` (Modul) leitet aus den Tabellenergebnissen den Exit-Code ab; das Skript schreibt `ERGEBNIS: …`, ruft `Stop-Transcript` und beendet mit `exit $ExitCode`. |
| **Cleanup** (`finally`) | `try { $Conn.Close() } catch { }` / `Dispose()` — Fehler beim Schließen werden bewusst verschluckt. |

---

## Was geloggt und was weitergeworfen wird

- **Logging = Transcript.** `Start-Transcript` zeichnet alle `Write-Host`-/`Write-Error`-Ausgaben in
  `Logs\Sync_<ConfigName>_<yyyy-MM-dd_HHmm>.log` auf. Es gibt kein strukturiertes Log und keine Log-Level.
- **Phasen 1–7:** Meldung einmal an der Skriptgrenze (`Write-Error "KRITISCH: …"`), dann Exit.
- **Phase 8:** Jede fehlgeschlagene Tabelle erscheint als `[<Tabelle>] ERROR (Versuch n): …` (rot) und in der
  Zusammenfassungstabelle (`Status`, `Info`, `Versuche`).
- **Sanity Check:** Abweichungen sind **kein** Fehler im Sinne des Status, sondern ein Wert in der Spalte `Sanity`
  (`OK`, `WARNUNG (+n)` = Ziel hat mehr Zeilen, `FEHLER (-n)` = Ziel hat weniger Zeilen). `FEHLER` wirkt sich
  erst über den Exit-Code aus (`11`, abschaltbar per `General.FailOnSanityError`); `WARNUNG` bleibt Exit `0`.
- **Laufergebnis:** Nach Zusammenfassung und Log-Rotation steht im Log genau eine Zeile
  `ERGEBNIS: OK (Exit-Code 0)` bzw. `ERGEBNIS: FEHLER (Exit-Code N) - betroffene Tabellen: …`.
- Passwörter und Connection Strings werden in Fehlermeldungen nicht ausgegeben; Treiber-Exceptions enthalten sie
  normalerweise nicht (bei neuen Treibern prüfen).

---

## Retry-Strategie

Implementiert im Parallel-Block des Sync-Skripts (Abschnitt 8):

- Pro Tabelle `while (-not $Success -and $Attempt -lt ($MaxRetries + 1))` → insgesamt bis zu `MaxRetries + 1` Versuche.
- Vor jedem Wiederholungsversuch **feste** Wartezeit `RetryDelaySeconds` (kein exponentielles Backoff, kein Jitter).
- Jeder Versuch öffnet **neue** Firebird- und SQL-Server-Verbindungen; `finally` schließt sie in jedem Fall.
- Wiederholt wird der **gesamte** Tabellenablauf (Schema → Staging → Extrakt → Bulk → Merge → Cleanup → Sanity).
  Das ist vertretbar, weil die Schritte idempotent sind: Staging wird vor dem Laden geleert, `sp_Merge_Generic` ist ein
  Upsert, das Wasserzeichen wird pro Versuch neu aus der Zieltabelle gelesen.
  Einschränkung: bei `ForceFullSync` wird die Zieltabelle vor dem Merge geleert — scheitert der Versuch danach,
  ist die Zieltabelle bis zum nächsten erfolgreichen Versuch leer.
- Es wird **nicht** zwischen transienten (Netzwerk, Deadlock, Timeout) und permanenten Fehlern (fehlende Spalte,
  Typkonflikt, Rechte) unterschieden — permanente Fehler verbrauchen alle Versuche.
- Keine Retries in den Phasen 1–7 (Konfig, Credentials, Treiber, Pre-Flight): dort Fail-Fast mit Exit-Code.

---

## Exit-Codes (Konvertierungstabelle)

### `Sync_Firebird_MSSQL_AutoSchema.ps1`

| Ursache | Exit-Code | Bemerkung |
|---|---|---|
| Alle Tabellen `Erfolg`, Sanity `OK` / `N/A` / `WARNUNG (+n)` | `0` | `ERGEBNIS: OK (Exit-Code 0)` |
| `SQLSyncCommon.psm1` fehlt | `1` | vor Transcript-Start |
| Konfiguration fehlt / ungültig (`Get-SQLSyncConfig`) | `2` | inkl. Namensprüfung (seit v2.12): `Ungültiger Name in '<Feld>': …` bei leerem, zu langem (> 63) oder nicht erlaubtem Namen (nur `A-Z`, `a-z`, `0-9`, `_`, `$`) bzw. `Ungültiger Name: Zieltabelle '…' … ist länger als 128 Zeichen.`; Abbruch vor jedem Verbindungsaufbau, Regeln in `docs/architecture/CONFIGURATION.md` |
| Keine Credentials (`Resolve-FirebirdCredentials` / `Resolve-MSSQLCredentials`) | `5` | |
| Treiber nicht ladbar (`Initialize-FirebirdDriver`, inkl. SHA-256-Abweichung, fehlende Admin-Rechte beim Erst-Download) | `7` | |
| Pre-Flight: Datenbank prüfen/anlegen über `master` fehlgeschlagen | `9` | z. B. fehlendes `dbcreator`, Server nicht erreichbar |
| Pre-Flight: `sp_Merge_Generic` prüfen/installieren fehlgeschlagen | `9` | `sql_server_setup.sql` fehlt, Verbindung scheitert oder **ein SQL-Batch** der Datei schlägt fehl (`Fehler beim Ausführen eines SQL-Batch aus 'sql_server_setup.sql': …`); nur „Database … already exists" wird ignoriert |
| Mindestens eine Tabelle mit Status `Fehler` (nach allen Retries), oder weniger Ergebnisse als konfigurierte Tabellen (z. B. Abbruch eines Parallel-Blocks außerhalb seines `try`; auch: gar keine Ergebnisse) | `10` | hat Vorrang vor `11`; fehlende Tabellen erscheinen in der `ERGEBNIS`-Zeile als `<Name> (kein Ergebnis)` |
| Keine Tabellenfehler, aber mindestens ein Sanity `FEHLER (-n)` | `11` | nur bei `General.FailOnSanityError = true` (Default); bei `false` → `0` |

Ermittlung von `0`/`10`/`11`: `Get-SyncExitCode -Results <Ergebnisse> -FailOnSanityError <bool> -ExpectedTableCount <Anzahl>` (das Skript übergibt `$Tabellen.Count`) in
`SQLSyncCommon.psm1` (reine Funktion, Unit-Tests in `tests/Unit/SQLSyncCommon.Tests.ps1`). Zusammenfassung,
Log-Rotation und `Stop-Transcript` laufen vor dem `exit`. Ein End-to-End-Lauf gegen echte Instanzen
(Exit `10` bei nicht existierender Tabelle, Task Scheduler `0xA`) wurde am 2026-10-08 gegen Firebird-Testserver → SQL-Testserver bestanden.

### `Test-SQLSyncConnections.ps1`

| Ursache | Exit-Code |
|---|---|
| Alle Tests erfolgreich | `0` |
| Modul oder Konfigdatei fehlt, oder ein Verbindungstest fehlgeschlagen | `1` |
| Konfiguration nicht parsebar / ungültig | `2` |
| Keine Credentials | `3` |
| Treiber nicht ladbar | `4` |

### `Get_Firebird_Schema.ps1`

| Ursache | Exit-Code |
|---|---|
| Erfolg | `0` (implizit) |
| Modul oder `config.json` fehlt | `1` |
| Konfiguration ungültig | `2` |
| Treiber nicht ladbar | `3` |
| Analysefehler (Verbindung, Tabelle nicht vorhanden) | `4` |
| Keine Credentials | `5` |

### `Manage_Config_Tables.ps1`

| Ursache | Exit-Code |
|---|---|
| Erfolg oder Abbruch durch Benutzer (keine Auswahl, keine Änderung) | `0` |
| Modul oder `config.json` fehlt | `1` |
| Firebird-Metadaten nicht lesbar, oder `General.IdColumn`/`TimestampColumns` verletzen die Namensregeln (`Ungültiger Name in '<Feld>': …`) | `2` |
| Treiber nicht ladbar | `3` |
| Backup/Schreiben der Konfiguration fehlgeschlagen | `4` |
| Keine Credentials | `5` |

Firebird-Tabellen mit ungültigem Namen führen nicht zum Abbruch: Sie erscheinen im GridView als
„UNGÜLTIGER NAME … wird nicht übernommen" (Aktion „Keine (ungültiger Name)") und werden beim Hinzufügen mit
`[!] Übersprungen: Ungültiger Name in 'Tables': …` übergangen.

### Weitere Skripte

- `Setup-ScheduledTasks.ps1`: PowerShell < 7 per `#Requires -Version 7.0` abgewiesen; ohne Admin-Rechte `exit 1` (Prüfung zur Laufzeit, entfällt bei `-WhatIf`); abgebrochene Passworteingabe `exit 1`. Fehlende Sync-Skript- oder Konfigdateien nur als Warnung.
- `Setup_Credentials.ps1`: keine Exit-Codes; Speicherfehler werden nur rot ausgegeben.

Die Codes sind **nicht** zwischen den Skripten vereinheitlicht (z. B. Credentials = 5 im Sync, 3 im Test-Skript).
Inkrement I2 hat nur die Sync-Codes `10`/`11` ergänzt; eine Vereinheitlichung über alle Skripte ist nicht umgesetzt.

---

## Bekannte Schwächen (verschluckte oder abgeschwächte Fehler)

| Stelle | Verhalten | Folge | Inkrement |
|---|---|---|---|
| Wasserzeichen `SELECT MAX(ts)` | `catch { $LastSyncDate = 1900-01-01 }` ohne Meldung | stiller Voll-Extrakt (langsam, aber durch MERGE korrekt) | offen (nicht Teil von I2) |
| Zieltabelle: ID-Spalte auf `NOT NULL` ändern | `try { … } catch { }` | nachfolgende PK-Anlage scheitert; nur als `(PK Err: …)` in `Info` | offen (nicht Teil von I2) |
| Staging-PK anlegen | leeres `catch { }` | Merge ohne Index (Performance) | offen (nicht Teil von I2) |
| Orphan-Cleanup | Fehler nur in `Info` (`Cleanup-Fehler: …`), Status bleibt `Erfolg` | z. B. nicht-numerische IDs (Temp-Tabelle `BIGINT`) werden nie bereinigt | Backlog |
| `Get-SQLSyncConfig` mit `-SchemaPath` | Schemafehler nur als `Write-Warning` | kein Fail-Fast (Pfad wird derzeit ohnehin nie übergeben) | I6 |
| Log-Rotation | Fehler nur als Warnung | unkritisch | — |

---

## Anti-Pattern

- **Leeres `catch { }` außerhalb von Close/Dispose** — jede bewusste Unterdrückung braucht Kommentar und mindestens
  eine Meldung in `Info` bzw. `Write-Host … -ForegroundColor Yellow`.
- **Erfolgsmeldung nach Teilfehlern** (früher: Pre-Flight „INSTALLIERT … erfolgreich" trotz Batch-Warnungen; seit I2 behoben).
- **`exit` im Modul** — das Modul wirft nur; Exit-Codes vergibt ausschließlich das Skript.
- **`exit` ohne vorheriges `Stop-Transcript`** im Sync-Skript — sonst bleibt die Logdatei offen bzw. unvollständig.
- **Retry von permanenten Fehlern** ohne Unterscheidung — kostet `MaxRetries × RetryDelaySeconds` pro Tabelle.

---

## Pflege

Trigger (siehe `KICKOFF.md` Phase 3a): neuer Exit-Code / neue Fehlerphase / neue Retry-Stelle / neue bewusst
unterdrückte Fehlerquelle → diese Datei, Exit-Code-Tabellen und `docs/operations/TASK_SCHEDULER.md` aktualisieren.
