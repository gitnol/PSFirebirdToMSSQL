# Task Scheduler – PSFirebirdToMSSQL

Konfiguration des Windows Task Schedulers für den automatischen Sync.
Die Tasks werden von `Setup-ScheduledTasks.ps1` angelegt (kein XML im Repo).
Verbindet sich mit `architecture/CREDENTIAL_STRATEGY.md`,
`operations/MONITORING.md` und `operations/RUNBOOK.md`.

---

## Task-Definitionen (Ist-Stand aus Setup-ScheduledTasks.ps1)

| Feld | SQLSync_Firebird_Daily_Diff | SQLSync_Firebird_Weekly_Full |
|---|---|---|
| Beschreibung | „Firebird Sync: Inkrementell (Mo-Fr, alle 30 Min)" | „Firebird Sync: Weekly Full & Repair (Sonntag)" |
| Trigger | Wöchentlich Mo–Fr 06:01, Wiederholung alle 30 Min für 15 h (letzter Start ca. 21:01), `StopAtDurationEnd = $false` | Wöchentlich So 05:13 |
| Programm | Pfad der pwsh, mit der das Setup-Skript lief (`(Get-Process -Id $PID).Path`, Fallback `pwsh.exe`) | wie links |
| Argumente | `-NoProfile -ExecutionPolicy Bypass -File "E:\SQLSync_Firebird_to_MSSQL\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "E:\SQLSync_Firebird_to_MSSQL\config_<DB-KÜRZEL>_DIFF_ONLY.json"` | wie links, `-ConfigFile "E:\SQLSync_Firebird_to_MSSQL\config_<DB-KÜRZEL>_RecreateTable_ForceFullSync.json"` |
| Arbeitsverzeichnis | `E:\SQLSync_Firebird_to_MSSQL` | wie links |
| Konto | aktueller Benutzer beim Ausführen des Setups (`WindowsIdentity.GetCurrent()`), Windows-Passwort per `Get-Credential` abgefragt und im Task gespeichert | wie links |
| Anmeldeart | „Unabhängig von Benutzeranmeldung" (implizit durch `-Password`) | wie links |
| Höchste Privilegien | nein (kein `-RunLevel Highest`) | nein |
| Settings | `AllowStartIfOnBatteries`, `DontStopIfGoingOnBatteries`, `StartWhenAvailable`, `MultipleInstances IgnoreNew` | gleiches Settings-Objekt |
| Ausführungszeitlimit | nicht gesetzt → Windows-Default (72 h) | wie links |
| Neustart bei Fehler | nicht konfiguriert. Seit I2 endet der Sync bei Fehlern mit Exit ≠ 0, ein Neustart wäre also technisch wirksam; beim Daily Diff ersetzt aber der nächste 30-Minuten-Lauf den Neustart, und bei `0x2`/`0x5`/`0x7`/`0x9` hilft ein Neustart nicht | wie links |

Job-Profile: Das Daily-Profil ist für inkrementelle Läufe gedacht
(`ForceFullSync`/`RecreateStagingTable` aus), das Weekly-Profil laut Dateiname
mit `RecreateStagingTable: true` und `ForceFullSync: true` als wöchentliche
Reparatur (holt übersprungene Änderungen nach, S6). Die Inhalte dieser
Konfigdateien liegen nicht im Repo.

Die Weekly-Full- und Daily-Läufe überschneiden sich zeitlich nicht (So vs.
Mo–Fr). Beide Tasks sind getrennte Tasks; `IgnoreNew` verhindert nur parallele
Instanzen **desselben** Tasks.

---

## Anlegen / Neu anlegen

```powershell
# PowerShell 7 "Als Administrator ausführen" (#Requires -RunAsAdministrator)
cd E:\SQLSync_Firebird_to_MSSQL
.\Setup-ScheduledTasks.ps1
```

Ablauf des Skripts: prüft PS-Version ≥ 7 und Adminrechte, warnt (ohne Abbruch),
wenn das Sync-Skript unter dem hart codierten Pfad fehlt, fragt das
Windows-Passwort des **aktuellen** Benutzers ab, entfernt Task 1 per
`Unregister-ScheduledTask` und registriert beide Tasks mit `-Force` neu.
Erneutes Ausführen ist daher idempotent und der Weg, nach einem
Passwortwechsel das gespeicherte Passwort zu aktualisieren.

Vorbereitung vor dem ersten Aufruf:

1. Im Skriptkopf (`# KONFIGURATION`) `$ScriptPath`, `$WorkDir`, `$ConfigPath1`,
   `$ConfigPath2` an den eigenen Installationspfad und die eigenen
   Konfignamen anpassen.
2. Unter demselben Konto `Setup_Credentials.ps1` ausführen – die
   Credential-Manager-Einträge sind an dieses Konto gebunden.
3. Konto braucht Schreibrecht auf `<Installationsverzeichnis>\Logs`.

Kontrolle:

```powershell
Get-ScheduledTask -TaskName SQLSync_Firebird_* |
    Select-Object TaskName, State, @{n='Konto';e={$_.Principal.UserId}}
(Get-ScheduledTask SQLSync_Firebird_Daily_Diff).Actions | Format-List Execute, Arguments, WorkingDirectory
(Get-ScheduledTask SQLSync_Firebird_Daily_Diff).Triggers.Repetition
```

---

## Schwachstellen (geplant in I9)

| Punkt | Auswirkung | Bezug |
|---|---|---|
| Pfade `E:\SQLSync_Firebird_to_MSSQL\...` und Konfignamen hart codiert | Skript muss vor jeder Nutzung editiert werden; Fehlkonfiguration wird nur als Warnung gemeldet, Tasks werden trotzdem angelegt | I9 |
| Interne Konfignamen/DB-Kürzel im öffentlichen Repo | Informationsabfluss über Betriebsinterna | S3, I9 |
| Persönliches Benutzerkonto mit gespeichertem Windows-Passwort statt Dienstkonto/gMSA | Passwortwechsel bricht die Tasks; Kopplung an eine Person; Credential-Manager-Einträge hängen am selben Konto | S13, I9 |
| Kein `ExecutionTimeLimit` | hängender Lauf blockiert per `IgnoreNew` alle Folgeläufe bis zu 72 h | `operations/RUNBOOK.md` „Task hängt" |
| `-ExecutionPolicy Bypass` | Skriptsignatur wird nicht geprüft; Integrität hängt allein an den Dateirechten des Installationsordners | S4 |

Sollzustand nach I9: Pfade und Konfignamen als Parameter von
`Setup-ScheduledTasks.ps1` (Default = Skriptordner), Option für Dienstkonto/gMSA,
keine internen Namen im Repo, optional `ExecutionTimeLimit`.

---

## Typische Fallen

| Symptom | Ursache | Fix |
|---|---|---|
| Task läuft nicht mehr nach Passwortwechsel | gespeichertes Windows-Passwort veraltet | `Setup-ScheduledTasks.ps1` erneut als Admin ausführen |
| `LastTaskResult` `0x41301` | Task läuft gerade (bzw. hängt) | `operations/RUNBOOK.md` „Task hängt" |
| `0x80070005` Access Denied | Konto ohne Rechte auf Skript-/Logordner | ACLs prüfen |
| `LastTaskResult` `0x1`, kein Log | `SQLSyncCommon.psm1` fehlt oder Pfad im Task falsch | Dateien/Task-Aktion prüfen |
| `LastTaskResult` `0x5` | Credentials nicht gefunden – Einträge unter anderem Konto angelegt | `Setup_Credentials.ps1` unter dem Task-Konto |
| `LastTaskResult` `0x7` | Treiber fehlt; Task läuft ohne Adminrechte und kann nicht nachladen | einmalig als Admin `Test-SQLSyncConnections.ps1` |
| `LastTaskResult` `0x9` | Pre-Flight fehlgeschlagen: Ziel-DB nicht erreichbar/anlegbar oder `sp_Merge_Generic` nicht installierbar (auch ein einzelner SQL-Batch) | Log `PRE-FLIGHT`, `operations/RUNBOOK.md` „Stored Procedure" |
| `LastTaskResult` `0xA` (10) | mindestens eine Tabelle mit Status `Fehler` oder ohne Ergebnis | Zeile `ERGEBNIS:` im Log, `operations/RUNBOOK.md` „Tabelle mit Status Fehler" |
| `LastTaskResult` `0xB` (11) | Sanity `FEHLER` (Ziel hat weniger Zeilen), keine Tabellenfehler | ForceFullSync für betroffene Tabellen; abschaltbar per `General.FailOnSanityError` |
| `LastTaskResult` `0x0`, aber Daten weichen ab | Sanity `WARNUNG (+n)` (z. B. Löschungen) führt bewusst nicht zu Exit ≠ 0 | Log prüfen, `operations/MONITORING.md` |
| Daily-Läufe fallen aus | vorheriger Lauf hängt, `IgnoreNew` verwirft Starts | hängenden Lauf beenden |

---

## Monitoring

| Quelle | Was prüfen |
|---|---|
| `Get-ScheduledTaskInfo -TaskName SQLSync_Firebird_Daily_Diff` | `LastRunTime`, `LastTaskResult`, `NextRunTime` |
| Event-Log `Microsoft-Windows-TaskScheduler/Operational` | Start, Ende, verworfene Starts (Verlauf muss aktiviert sein) |
| `<Installationsverzeichnis>\Logs\Sync_<Konfigname>_*.log` | Zeile `ERGEBNIS:`, Zusammenfassung, Status, Sanity – Details zu einem `LastTaskResult` ≠ `0x0` |

Alarmierung ist nicht eingerichtet; Details und manuelle Checks:
`operations/MONITORING.md`.

---

## Pflege

Trigger: neuer Task / Trigger-Änderung / Konto-Wechsel / Pfadänderung →
`Setup-ScheduledTasks.ps1` anpassen, diese Datei aktualisieren und ggf.
`architecture/CREDENTIAL_STRATEGY.md` nachziehen.
