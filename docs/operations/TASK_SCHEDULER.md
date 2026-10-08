# Task Scheduler – PSFirebirdToMSSQL

Konfiguration des Windows Task Schedulers für den automatischen Sync.
Die Tasks werden von `Setup-ScheduledTasks.ps1` angelegt (kein XML im Repo).
Verbindet sich mit `architecture/CREDENTIAL_STRATEGY.md`,
`operations/MONITORING.md` und `operations/RUNBOOK.md`.

---

## Task-Definitionen (Ist-Stand aus Setup-ScheduledTasks.ps1)

Werte in der Tabelle sind die Parameter-Defaults; Namen, Pfade, Zeiten und
das Konto sind per Parameter änderbar (Abschnitt „Parameter“).

| Feld | Tageslauf (Default `SQLSync_Firebird_Daily_Diff`) | Wochenlauf (Default `SQLSync_Firebird_Weekly_Full`) |
|---|---|---|
| Beschreibung | „Firebird Sync: Inkrementell (Monday,…,Friday, alle 30 Min.)“ – aus `-DailyDays`/`-DailyIntervalMinutes` erzeugt | „Firebird Sync: Weekly Full & Repair (Sunday)“ |
| Trigger | Wöchentlich Mo–Fr 06:01, Wiederholung alle 30 Min für 15 h (letzter Start ca. 21:01), `StopAtDurationEnd = $false` | Wöchentlich So 05:13 |
| Programm | Pfad der pwsh, mit der das Setup-Skript lief (`(Get-Process -Id $PID).Path`, Fallback `pwsh.exe`) | wie links |
| Argumente | `-NoProfile -ExecutionPolicy Bypass -File "<InstallDir>\Sync_Firebird_MSSQL_AutoSchema.ps1" -ConfigFile "<InstallDir>\config.json"` | wie links, `-ConfigFile "<InstallDir>\config_weekly_full.json"` |
| Arbeitsverzeichnis | `<InstallDir>` (Default: Ordner von `Setup-ScheduledTasks.ps1`) | wie links |
| Konto | `-RunAsUser` (Default: aktueller Benutzer), Windows-Passwort per `Get-Credential` abgefragt und im Task gespeichert; alternativ `-GmsaAccount` ohne gespeichertes Passwort | wie links |
| Anmeldeart | „Unabhängig von Benutzeranmeldung“ (LogonType `Password`) | wie links |
| Höchste Privilegien | nein (kein `-RunLevel Highest`) | nein |
| Settings | `AllowStartIfOnBatteries`, `DontStopIfGoingOnBatteries`, `StartWhenAvailable`, `MultipleInstances IgnoreNew` | gleiches Settings-Objekt |
| Ausführungszeitlimit | nicht gesetzt → Windows-Default (72 h) | wie links |
| Neustart bei Fehler | nicht konfiguriert. Seit I2 endet der Sync bei Fehlern mit Exit ≠ 0, ein Neustart wäre also technisch wirksam; beim Daily Diff ersetzt aber der nächste 30-Minuten-Lauf den Neustart, und bei `0x2`/`0x5`/`0x7`/`0x9` hilft ein Neustart nicht | wie links |

Job-Profile: Das Daily-Profil ist für inkrementelle Läufe gedacht
(`ForceFullSync`/`RecreateStagingTable` aus), das Weekly-Profil als
wöchentliche Reparatur mit `RecreateStagingTable: true` und
`ForceFullSync: true` (holt übersprungene Änderungen nach, S6). Die Inhalte
dieser Konfigdateien liegen nicht im Repo.

Die Weekly-Full- und Daily-Läufe überschneiden sich mit den Defaults zeitlich
nicht (So vs. Mo–Fr). Beide Tasks sind getrennte Tasks; `IgnoreNew` verhindert
nur parallele Instanzen **desselben** Tasks. Wer `-DailyDays` und `-WeeklyDay`
überlappend wählt, muss die Startzeiten selbst entzerren.

---

## Parameter

| Parameter | Default | Bedeutung |
|---|---|---|
| `-InstallDir` | Ordner des Skripts | Ordner mit `Sync_Firebird_MSSQL_AutoSchema.ps1` und den Konfigdateien; zugleich Arbeitsverzeichnis der Tasks |
| `-DailyConfigFile` | `config.json` | Konfigdatei des Tageslaufs, relativ zu `-InstallDir` oder absolut |
| `-WeeklyConfigFile` | `config_weekly_full.json` | Konfigdatei des Wochenlaufs, relativ zu `-InstallDir` oder absolut |
| `-DailyTaskName` | `SQLSync_Firebird_Daily_Diff` | Name des Tages-Tasks |
| `-DailyStart` | `06:01` | Startzeit des Tageslaufs (`HH:mm`) |
| `-DailyDays` | Monday–Friday | Wochentage des Tageslaufs (Werte von `System.DayOfWeek`) |
| `-DailyIntervalMinutes` | `30` | Wiederholungsintervall in Minuten (1–1440) |
| `-DailyDurationHours` | `15` | Dauer des Wiederholungsfensters in Stunden (1–24) |
| `-WeeklyTaskName` | `SQLSync_Firebird_Weekly_Full` | Name des Wochen-Tasks |
| `-WeeklyDay` | `Sunday` | Wochentag des Wochenlaufs |
| `-WeeklyStart` | `05:13` | Startzeit des Wochenlaufs (`HH:mm`) |
| `-RunAsUser` | aktueller Benutzer | Ausführungskonto; Windows-Passwort wird abgefragt |
| `-GmsaAccount` | – | gMSA im Format `DOMAIN\name$`; ersetzt `-RunAsUser`, kein Passwort |
| `-WhatIf` | – | nur berechnen und ausgeben: keine Adminrechte, keine Passwortabfrage, keine Registrierung |

Ausgabe: je Task ein Objekt mit `TaskName`, `Action`, `Trigger`, `Settings`,
`Principal` und `Registered` (`$false` bei `-WhatIf`).

Fehlende Dateien (Sync-Skript, Konfigdateien) werden nur als Warnung gemeldet;
die Tasks werden trotzdem angelegt. Deshalb vor dem Registrieren `-WhatIf`
ausführen und die Pfade in `Action.Arguments` prüfen.

---

## Anlegen / Neu anlegen

```powershell
# 1. Vorschau – ohne Adminrechte, ohne Passwortabfrage, ohne Registrierung
cd D:\Apps\SQLSync
.\Setup-ScheduledTasks.ps1 -WhatIf |
    Select-Object TaskName, @{n='Argumente';e={$_.Action.Arguments}}

# 2. Registrieren – PowerShell 7 "Als Administrator ausführen"
.\Setup-ScheduledTasks.ps1 -DailyConfigFile config.json -WeeklyConfigFile config_weekly_full.json
```

Ablauf des Skripts: prüft PS-Version ≥ 7 (`#Requires -Version 7.0`) und – außer
bei `-WhatIf` – Adminrechte zur Laufzeit (ohne Adminrechte Exit 1), löst die
Pfade gegen `-InstallDir` auf, warnt (ohne Abbruch) bei fehlenden Dateien,
fragt das Windows-Passwort von `-RunAsUser` ab (nicht bei `-GmsaAccount`;
Abbruch der Eingabe → Exit 1), entfernt jeden Task per
`Unregister-ScheduledTask` und registriert ihn mit `-Force` neu.
Erneutes Ausführen mit denselben Parametern ist daher idempotent und der Weg,
nach einem Passwortwechsel das gespeicherte Passwort zu aktualisieren.

Vorbereitung vor dem ersten Aufruf:

1. Konfigdateien im Installationsordner anlegen (oder Namen per
   `-DailyConfigFile`/`-WeeklyConfigFile` übergeben).
2. Unter dem Task-Konto `Setup_Credentials.ps1` ausführen – die
   Credential-Manager-Einträge sind an dieses Konto gebunden.
3. Konto braucht Schreibrecht auf `<Installationsverzeichnis>\Logs`.

**Bestehende Installationen:** Wer bisher die im Skript fest eingetragenen
Pfade und Konfignamen genutzt hat, muss beim Neuanlegen `-InstallDir`,
`-DailyConfigFile` und `-WeeklyConfigFile` explizit übergeben (vorher mit
`-WhatIf` prüfen). Bereits registrierte Tasks sind nicht betroffen, solange
das Skript nicht erneut ausgeführt wird.

### Dienstkonto / gMSA

```powershell
# gMSA: kein gespeichertes Passwort; das Konto braucht "Anmelden als Stapelverarbeitungsauftrag"
.\Setup-ScheduledTasks.ps1 -GmsaAccount 'EXAMPLE\svc-sqlsync$' -WhatIf
.\Setup-ScheduledTasks.ps1 -GmsaAccount 'EXAMPLE\svc-sqlsync$'

# klassisches Dienstkonto: Passwort wird einmalig abgefragt
.\Setup-ScheduledTasks.ps1 -RunAsUser 'EXAMPLE\svc-sqlsync'
```

Grenze beim gMSA: Die Credential-Manager-Einträge (`SQLSync_Firebird`,
`SQLSync_MSSQL`) sind an das Konto gebunden, das sie anlegt. Ein gMSA kann
sich nicht interaktiv anmelden, `Setup_Credentials.ps1` lässt sich also nicht
einfach unter ihm ausführen. Praktikabel ist daher vor allem
`MSSQL."Integrated Security": true` (Windows-Authentifizierung des gMSA am SQL
Server). Firebird-Credentials müssten im Kontext des gMSA angelegt werden
(z. B. über einen einmaligen Task unter dem gMSA); fehlen sie, endet der Sync
mit Exit 5. Details: `architecture/CREDENTIAL_STRATEGY.md`.

Kontrolle:

```powershell
Get-ScheduledTask -TaskName SQLSync_Firebird_* |
    Select-Object TaskName, State, @{n='Konto';e={$_.Principal.UserId}}
(Get-ScheduledTask SQLSync_Firebird_Daily_Diff).Actions | Format-List Execute, Arguments, WorkingDirectory
(Get-ScheduledTask SQLSync_Firebird_Daily_Diff).Triggers.Repetition
```

Ein echter Registrierungslauf mit Adminrechten ist für die parametrisierte
Fassung bisher nicht durchgeführt; die Unit-Tests decken nur `-WhatIf` ab
(`testing/UNIT_TESTS.md`). Nach dem ersten Registrieren die Kontrolle oben
ausführen.

---

## Schwachstellen

| Punkt | Auswirkung | Status |
|---|---|---|
| Pfade und Konfignamen hart codiert | Skript musste vor jeder Nutzung editiert werden | erledigt (I9): Parameter mit Default Skriptordner, Vorschau per `-WhatIf` |
| Interne Konfignamen/DB-Kürzel im öffentlichen Repo | Informationsabfluss über Betriebsinterna | erledigt (S3, I9): generische Defaults |
| Persönliches Benutzerkonto mit gespeichertem Windows-Passwort | Passwortwechsel bricht die Tasks; Kopplung an eine Person; Credential-Manager-Einträge hängen am selben Konto | Option vorhanden (S13): `-RunAsUser` (Dienstkonto) bzw. `-GmsaAccount`; Default bleibt der aktuelle Benutzer |
| Fehlende Dateien nur als Warnung | Tasks werden auch mit falschen Pfaden angelegt | offen; Gegenmittel `-WhatIf` vor dem Registrieren |
| Kein `ExecutionTimeLimit` | hängender Lauf blockiert per `IgnoreNew` alle Folgeläufe bis zu 72 h | offen; `operations/RUNBOOK.md` „Task hängt" |
| `-ExecutionPolicy Bypass` | Skriptsignatur wird nicht geprüft; Integrität hängt allein an den Dateirechten des Installationsordners | offen (S4) |

---

## Typische Fallen

| Symptom | Ursache | Fix |
|---|---|---|
| Task läuft nicht mehr nach Passwortwechsel | gespeichertes Windows-Passwort veraltet | `Setup-ScheduledTasks.ps1` mit denselben Parametern erneut als Admin ausführen |
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

Trigger: Konto-Wechsel / Pfadänderung / anderer Zeitplan →
`Setup-ScheduledTasks.ps1` mit passenden Parametern neu ausführen (vorher
`-WhatIf`). Neuer Task, neuer Parameter oder geänderte Defaults → Skript und
diese Datei aktualisieren, ggf. `architecture/CREDENTIAL_STRATEGY.md` nachziehen.
