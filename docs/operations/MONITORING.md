# Monitoring & Betrieb – PSFirebirdToMSSQL

Ehrlicher Ist-Stand: Es gibt **kein** aktives Monitoring, keinen Alarm und
keine strukturierte Ergebnisdatei. Quellen sind das Transcript-Log je Lauf und
die Task-Scheduler-Historie. Seit Sync-Version 2.11 (Inkrement I2) ist der
Exit-Code aussagekräftig: Tabellenfehler → `10`, Sanity `FEHLER` → `11`,
Pre-Flight inkl. SP-Batch-Fehler → `9`. Ein Monitoring kann sich damit auf
`LastTaskResult` stützen; das Log bleibt die Quelle für Details (welche Tabelle,
welche Ursache). Einschränkung: Das Exit-Code-Verhalten ist per Unit-Test
geprüft, ein End-to-End-Lauf gegen echte Instanzen steht noch aus (Abnahme
offen, S1).

---

## Was es heute gibt

| Quelle | Inhalt | Ort |
|---|---|---|
| Transcript-Log | Komplette Konsolenausgabe eines Laufs (`Start-Transcript -Append`) inkl. Zusammenfassungstabelle | `<Skriptordner>\Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log` |
| Zusammenfassungstabelle | Pro Tabelle: Quelle, Ziel, Status, Sync (geladene Zeilen), Del (Orphans), FB, SQL, Sanity, Time, Info | Ende jedes Logs nach `ZUSAMMENFASSUNG` |
| Task-Scheduler-Historie | Start/Ende/LastTaskResult der Tasks | `Get-ScheduledTaskInfo`, Ereignisprotokoll `Microsoft-Windows-TaskScheduler/Operational` |
| Log-Rotation | Löscht `Sync_*.log` älter als `DeleteLogOlderThanDays` (Default 30, 0 = aus) | am Ende jedes Laufs |

Nicht vorhanden: Windows-Eventlog-Einträge, E-Mail/Teams-Benachrichtigung,
JSON/CSV-Ergebnis, Metriken, Heartbeat-Datei.

---

## Exit-Codes (Sync_Firebird_MSSQL_AutoSchema.ps1)

| Code | Bedeutung | Im Log |
|---|---|---|
| `0` | Alle Tabellen `Erfolg`, Sanity `OK` / `N/A` / `WARNUNG (+n)` | `ERGEBNIS: OK (Exit-Code 0)` |
| `1` | `SQLSyncCommon.psm1` fehlt im Skriptordner (vor Transcript-Start, daher **kein** Log) | – |
| `2` | Konfiguration nicht gefunden / nicht parsebar / ungültig (z. B. leere `Tables`) | `KRITISCH: ...` |
| `5` | Credentials nicht auflösbar | `KRITISCH: Keine ... Credentials gefunden!` |
| `7` | Firebird-Treiber fehlt, Download/Hash/Laden fehlgeschlagen | `KRITISCH: ...` |
| `9` | Pre-Flight: Ziel-DB prüfen/anlegen oder `sp_Merge_Generic` installieren fehlgeschlagen (auch ein einzelner fehlgeschlagener SQL-Batch aus `sql_server_setup.sql`) | `KRITISCH: ...` bzw. `PRE-FLIGHT CHECK (PROCEDURE) FAILED: Fehler beim Ausführen eines SQL-Batch ...` |
| `10` | Mindestens eine Tabelle `Fehler` oder weniger Ergebnisse als konfigurierte Tabellen | `ERGEBNIS: FEHLER (Exit-Code 10) - betroffene Tabellen: ...` (fehlende als `<Name> (kein Ergebnis)`) |
| `11` | Keine Tabellenfehler, aber Sanity `FEHLER (-n)`; nur mit `General.FailOnSanityError = true` (Default) | `ERGEBNIS: FEHLER (Exit-Code 11) - betroffene Tabellen: ...` |
| `0xC000013A` | Prozess abgebrochen (Strg+C / Kill) | Log endet abrupt, keine Zusammenfassung |

Task Scheduler zeigt die Codes hexadezimal: `0x9`, `0xA` (= 10), `0xB` (= 11).
Sanity `WARNUNG (+n)` (Ziel hat mehr Zeilen, z. B. nicht replizierte
Löschungen) führt bewusst **nicht** zu einem Fehlercode – dafür weiterhin das
Log prüfen. Exit-Codes der Hilfsskripte: `features/firebird-mssql-sync.md`.

---

## Erfolgsindikatoren (manuell prüfbar)

| Indikator | Erwartet | Prüfung |
|---|---|---|
| Task lief planmäßig | `LastRunTime` jünger als Intervall × 1,5 (Daily Diff: 45 Min an Werktagen 06:01–21:01; Weekly Full: 7 Tage) | `Get-ScheduledTaskInfo` |
| Task-Ergebnis | `0x0`; `0xA`/`0xB`/`0x9` = Fehler (siehe Exit-Codes) | `Get-ScheduledTaskInfo` |
| Laufergebnis im Log | Zeile `ERGEBNIS: OK (Exit-Code 0)` | `Select-String 'ERGEBNIS:'` |
| Log vorhanden und aktuell | neuestes `Sync_<Konfigname>_*.log` passt zum letzten Lauf | `Get-ChildItem .\Logs` |
| Lauf vollständig | Log enthält `ZUSAMMENFASSUNG` und `GESAMTLAUFZEIT:` | `Select-String` |
| Keine Tabellenfehler | keine Zeile mit `] ERROR (Versuch` als letztem Versuch, keine `Fehler` in Spalte Status | `Select-String` |
| Datenkonsistenz | Sanity `OK` für alle Tabellen; `FEHLER (-n)` = fehlende Zeilen | `Select-String` |
| SP-Installation sauber | keine Zeile `PRE-FLIGHT CHECK (PROCEDURE) FAILED` (sonst Exit `9`) | `Select-String` |

---

## Manuelle Checks

```powershell
$Dir = 'E:\SQLSync_Firebird_to_MSSQL'     # Installationsverzeichnis anpassen

# 1. Task-Status
Get-ScheduledTaskInfo -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full |
    Select-Object TaskName, LastRunTime, LastTaskResult, NextRunTime

# 2. Task-Scheduler-Historie (Fehler/Abbrüche), Verlauf muss in der Aufgabenplanung aktiviert sein
Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -MaxEvents 200 |
    Where-Object { $_.Message -like '*SQLSync_Firebird*' } |
    Select-Object TimeCreated, Id, LevelDisplayName, Message -First 20

# 3. Neuestes Log
$Log = Get-ChildItem "$Dir\Logs\Sync_*.log" | Sort-Object LastWriteTime | Select-Object -Last 1
$Log.FullName, $Log.LastWriteTime

# 4. Fehler, FEHLER und Warnungen im neuesten Log
Select-String -Path $Log.FullName -Pattern 'ERGEBNIS:', 'ERROR', 'FEHLER', 'Fehler', 'KRITISCH', 'FAILED' |
    Select-Object LineNumber, Line

# 5. Zusammenfassung anzeigen
$Text = Get-Content $Log.FullName
$Start = ($Text | Select-String 'ZUSAMMENFASSUNG' | Select-Object -Last 1).LineNumber
$Text[($Start - 1)..($Start + 60)]

# 6. Alle Logs der letzten 24 h mit Tabellenfehlern
Get-ChildItem "$Dir\Logs\Sync_*.log" | Where-Object LastWriteTime -gt (Get-Date).AddDays(-1) |
    Select-String -Pattern '\] Abschluss: Fehler', 'FEHLER \(' |
    Select-Object Filename, Line
```

Hinweis zu `Select-String`: Standard ist case-insensitiv – `'Fehler'` findet
auch `FEHLER`. Die Zeile `[<Tabelle>] Abschluss: <Status> (<Sanity>)` steht
pro Tabelle genau einmal und ist das robusteste Grep-Ziel.

---

## Bekannte Warnsignale

| Signal | Mögliche Ursache | Maßnahme (`operations/RUNBOOK.md`) |
|---|---|---|
| `Abschluss: Fehler` | Tabelle nach allen Retries fehlgeschlagen | Störungsfall „Tabelle mit Status Fehler" |
| Sanity `FEHLER (-n)` | Zeilen fehlen im Ziel (Wasserzeichen S6, Fehler) | ForceFullSync für Tabelle |
| Sanity `WARNUNG (+n)` | Löschungen nicht repliziert (S7) | CleanupOrphans / ForceFullSync |
| `Warnung: Versuch n von m` | Transiente Fehler, Retry lief | beobachten; dauerhaft → Ursache klären |
| `Cleanup-Fehler:` in Info | Orphan-Cleanup gescheitert (z. B. nicht-numerische ID) | Störungsfall „Löschungen" |
| `PK Err:` in Info | PK auf Zieltabelle nicht anlegbar (Duplikate/NULL in ID) | Daten/ID-Spalte prüfen, `TableOverrides` |
| `PRE-FLIGHT CHECK (PROCEDURE) FAILED: Fehler beim Ausführen eines SQL-Batch` (Exit `9`) | SP-Installation fehlgeschlagen, Lauf abgebrochen | Störungsfall „Stored Procedure" |
| Kein neues Log, Task „läuft" seit Stunden | Lauf hängt, Folgestarts werden ignoriert (IgnoreNew) | Störungsfall „Task hängt" |
| Kein Log trotz Task-Start, Ergebnis `0x1` | Modul fehlt (exit 1 vor Transcript) oder pwsh-Pfad falsch | Dateien/Task-Aktion prüfen |
| `LastTaskResult` `0x2`/`0x5`/`0x7`/`0x9` | siehe Exit-Codes oben | Log `KRITISCH:` lesen |
| `LastTaskResult` `0xA` | mindestens eine Tabelle fehlgeschlagen bzw. ohne Ergebnis | `ERGEBNIS:`-Zeile lesen, Störungsfall „Tabelle mit Status Fehler" |
| `LastTaskResult` `0xB` | Sanity `FEHLER` (Ziel hat weniger Zeilen) | ForceFullSync für die genannten Tabellen |
| `[Credentials] ...: config.json (WARNUNG: unsicher!)` | Fallback-Passwort in Konfig im Einsatz (S3) | Credential Manager nutzen |

---

## Scheduling

```
Trigger:          Daily Diff: Mo–Fr ab 06:01 alle 30 Min für 15 h
                  Weekly Full: So 05:13
Ausführung:       Unabhängig von Benutzeranmeldung (gespeichertes Windows-Passwort)
Konto:            Benutzer, der Setup-ScheduledTasks.ps1 ausgeführt hat (kein Dienstkonto, S13)
Protokollierung:  <Skriptordner>\Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log
```

Details: `operations/TASK_SCHEDULER.md`.

---

## Ausbau

- Umgesetzt und abgenommen (I2, 2026-10-08): Exit-Code ≠ 0 bei Tabellenfehlern (`10`),
  Sanity `FEHLER` (`11`) und SP-Batch-Fehlern (`9`); `LastTaskResult` ist damit
  als Alarmquelle nutzbar. Ein Alarm darauf (z. B. Ereignis-Trigger auf
  `Microsoft-Windows-TaskScheduler/Operational`) ist nicht eingerichtet.
- Backlog: strukturiertes Run-Ergebnis (JSON/CSV) je Lauf als Quelle für
  ein externes Monitoring/Alarmierung; optional Windows-Eventlog-Eintrag als
  Heartbeat.

Bis dahin gilt: **Erfolg nur über die Log-Prüfung feststellen**, nicht über den
Task-Status.
