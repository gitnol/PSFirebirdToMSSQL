# Runbook – PSFirebirdToMSSQL

Routine-Operationen und Störungsfälle für den Firebird→MS-SQL-Sync.
Alle Befehle in PowerShell 7 (`pwsh`) im Installationsverzeichnis
(Beispiel: `D:\Apps\SQLSync`). Erst-Setup: `operations/SETUP.md`,
Überwachung: `operations/MONITORING.md`, Tasks: `operations/TASK_SCHEDULER.md`,
Ablauf im Detail: `features/firebird-mssql-sync.md`.

---

## Häufige Commands

```powershell
# Normaler Lauf mit Standard-Konfig (config.json im Skriptordner)
.\Sync_Firebird_MSSQL_AutoSchema.ps1

# Lauf mit bestimmtem Job-Profil
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile .\config_weekly_full.json

# Verbindungen, Treiber, Credentials und sp_Merge_Generic prüfen
.\Test-SQLSyncConnections.ps1 -ConfigFile .\config.json

# Spaltentypen einer Firebird-Tabelle anzeigen (liest fest config.json)
.\Get_Firebird_Schema.ps1 -TableName BKUNDE

# Tabellen in config.json hinzufügen/entfernen (Out-GridView, legt .bak an)
.\Manage_Config_Tables.ps1

# Scheduled Tasks manuell anstoßen / Status
Start-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff
Get-ScheduledTaskInfo -TaskName SQLSync_Firebird_Daily_Diff, SQLSync_Firebird_Weekly_Full |
    Select-Object TaskName, LastRunTime, LastTaskResult, NextRunTime

# Letztes Log ansehen
Get-ChildItem .\Logs\Sync_*.log | Sort-Object LastWriteTime | Select-Object -Last 1 |
    Get-Content -Tail 60
```

Es gibt **keinen** Dry-Run (`-WhatIf`) und keine weiteren CLI-Parameter als
`-ConfigFile`. Verhalten wird ausschließlich über Schalter in der Konfigdatei
gesteuert (`architecture/CONFIGURATION.md`). Für Einmal-Aktionen (z. B.
`ForceFullSync`) daher eine **Kopie** der Konfig anlegen statt das produktive
Job-Profil zu ändern:

```powershell
$cfg = Get-Content .\config.json -Raw | ConvertFrom-Json
$cfg.General.ForceFullSync = $true
$cfg | ConvertTo-Json -Depth 10 | Set-Content .\config_einmalig.json -Encoding utf8
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile .\config_einmalig.json
Remove-Item .\config_einmalig.json      # enthält ggf. Fallback-Passwörter
```

Das Muster wird unten als „Einmal-Konfig mit Schalter X" referenziert.
Hinweis: `Tables` lässt sich in der Kopie auf die betroffene Tabelle
reduzieren (`$cfg.Tables = @('BKUNDE')`), um nur diese zu bearbeiten.

---

## Routine

| Wann | Aktion |
|---|---|
| Täglich (Arbeitstag) | Letztes Log des Daily-Diff-Tasks: Zusammenfassungstabelle auf `Fehler` / `FEHLER` prüfen (siehe `operations/MONITORING.md`) |
| Montag | Log des Weekly-Full-Laufs vom Sonntag prüfen; alle Tabellen Sanity `OK` erwartet |
| Nach Änderung an `Tables` | Testlauf manuell, neue Tabellen erscheinen mit Strategie und Sanity in der Zusammenfassung |
| Nach Code-Update | `operations/DEPLOYMENT.md` – Post-Deploy-Verifikation |
| Bei Passwortwechsel | `Setup_Credentials.ps1` unter dem Task-Konto erneut ausführen; bei Wechsel des Windows-Passworts des Task-Kontos `Setup-ScheduledTasks.ps1` mit denselben Parametern erneut ausführen (nicht nötig bei gMSA) |
| Monatlich | `Logs\` Größe prüfen (Rotation über `DeleteLogOlderThanDays`, Default 30 Tage); alte `config.json.*.bak` löschen |

---

## Störungsfälle

### Tabelle mit Status „Fehler" in der Zusammenfassung

Symptom: In der Tabelle `ZUSAMMENFASSUNG` steht bei einer Quelle `Status = Fehler`,
im Log `[<Tabelle>] ERROR (Versuch n): <Meldung>`. Die übrigen Tabellen laufen
weiter; der Lauf endet mit Exit-Code `10` (Task Scheduler `0xA`), die Zeile
`ERGEBNIS: FEHLER (Exit-Code 10) - betroffene Tabellen: …` nennt die Tabellen.
Erscheint dort `<Name> (kein Ergebnis)`, hat der Parallel-Block der Tabelle gar
kein Ergebnis geliefert – Log oberhalb nach `[<Name>]` durchsuchen.

```powershell
Select-String -Path .\Logs\Sync_*.log -Pattern '\] ERROR \(Versuch' | Select-Object -Last 20
```

Vorgehen:
1. Meldung lesen. Die Tabelle wurde `MaxRetries + 1` Mal versucht (Default 4,
   Abstand `RetryDelaySeconds`). Transiente Netzwerk-/Lock-Fehler erledigen sich
   meist beim nächsten Lauf.
2. Typische Ursachen und Abschnitt unten:
   - Spalte fehlt / „The given ColumnMapping does not match" / Konvertierungsfehler
     → Schema-Drift.
   - Timeout → `GlobalTimeout` (Default 7200 s) erhöhen oder Tabelle in eigenes
     Job-Profil auslagern.
   - Tabelle existiert nicht in Firebird → aus `Tables` entfernen
     (`Manage_Config_Tables.ps1`).
   - `Could not find stored procedure 'sp_Merge_Generic'` / Parameterfehler →
     Stored Procedure veraltet.
3. Einzeln nachfahren mit Einmal-Konfig, `Tables` nur mit der betroffenen Tabelle.

### Sanity „FEHLER (-n)" oder „WARNUNG (+n)"

Der Sanity Check vergleicht `COUNT(*)` in Firebird mit `COUNT(*)` der Zieltabelle.

| Anzeige | Bedeutung | Maßnahme |
|---|---|---|
| `OK` | Gleiche Zeilenzahl | – |
| `FEHLER (-n)` | Ziel hat **n Zeilen weniger** als Quelle: Datensätze fehlen (z. B. übersprungen durch striktes Wasserzeichen `> MAX(ts)`, S6; oder Lauf mit Fehler). Ohne Tabellenfehler endet der Lauf mit Exit `11` (`0xB`), sofern `General.FailOnSanityError` nicht `false` ist | Einmal-Konfig mit `ForceFullSync: true` für die Tabelle, oder Weekly Full abwarten |
| `WARNUNG (+n)` | Ziel hat **n Zeilen mehr**: in Firebird gelöschte Datensätze sind im Ziel noch vorhanden (Löschungen werden standardmäßig nicht repliziert, S7) | siehe „Löschungen in Firebird" |
| `N/A` | `RunSanityCheck` aus oder Tabelle fehlgeschlagen | – |

Kleine Abweichungen während laufender Firebird-Schreiblast sind möglich, da
`COUNT` nach dem Merge separat gelesen wird. Bleibt die Abweichung über mehrere
Läufe stehen, handeln.

### „Ungültiger Name in …" (Sync exit 2)

Log: `KRITISCH: Ungültiger Name in '<Feld>': '<Name>' (erlaubt sind nur A-Z, a-z, 0-9, _ und $).`
(bzw. `… ist länger als 63 Zeichen.`, `… leer.` oder
`Ungültiger Name: Zieltabelle '…' (MSSQL.Prefix + Tables + MSSQL.Suffix) ist länger als 128 Zeichen.`).
Der Lauf bricht beim Laden der Konfiguration ab, **bevor** eine Datenbankverbindung aufgebaut
wird; es wurde nichts geschrieben.

1. Das genannte Feld (`Tables`, `General.IdColumn`, `General.TimestampColumns`, `MSSQL.Database`,
   `MSSQL.Prefix`/`Suffix`, `TableOverrides` bzw. `TableOverrides.<Tabelle>.IdColumn`/`TimestampColumn`)
   in der Konfigdatei des Job-Profils korrigieren: nur `A-Z`, `a-z`, `0-9`, `_`, `$`, höchstens
   63 Zeichen; keine Leerzeichen, Anführungszeichen, Klammern, Semikolons oder Bindestriche.
2. Hat sich niemand bewusst an der Konfig zu schaffen gemacht, aber sie enthält Zeichen wie `;`,
   `'`, `"` oder `]`: als möglichen Manipulationsversuch behandeln (`docs/operations/INCIDENT_RESPONSE.md`)
   und Schreibrechte auf den Skriptordner prüfen.
3. Firebird-Tabelle heißt tatsächlich anders (z. B. mit Sonderzeichen): sie kann nicht
   synchronisiert werden – aus `Tables` entfernen. `Manage_Config_Tables.ps1` bietet solche Tabellen
   gar nicht erst zur Übernahme an (Markierung „UNGÜLTIGER NAME").
4. Lauf manuell wiederholen (`.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile <Konfig>`), Exit 0 prüfen.

### Firebird-Treiber fehlt / lässt sich nicht laden (Sync exit 7)

Log: `Der Firebird-Treiber fehlt in C:\ProgramData\SQLSync\Drivers\... Bitte einmalig als ADMINISTRATOR ausführen.`
oder `SHA-256 der heruntergeladenen Treiber-DLL stimmt nicht ...` oder
`Fehler beim Laden der Assembly`.

```powershell
# Ist der Treiber da?
Get-ChildItem "$env:ProgramData\SQLSync\Drivers" -Recurse -Filter FirebirdSql.Data.FirebirdClient.dll

# Einmalig in einer Administrator-pwsh nachladen
.\Test-SQLSyncConnections.ps1
```

- SHA-256-Fehler: Download manipuliert oder Proxy liefert andere Datei – **nicht**
  umgehen; Netzwerk/Proxy klären, Ordner
  `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4` löschen,
  erneut als Admin ausführen.
- Kein Internet: DLL manuell bereitstellen und `Firebird.DllPath` setzen (wird
  ohne Hash-Prüfung geladen, S4/I7).

### Credential fehlt (Sync exit 5)

Log: `Keine Firebird Credentials gefunden! Führe Setup_Credentials.ps1 aus.` bzw.
`Keine SQL Server Credentials gefunden! ...`

Ursache fast immer: Einträge wurden unter einem anderen Windows-Konto angelegt als
dem, unter dem der Task läuft (Credential Manager ist pro Benutzer).

```powershell
# Als Task-Konto anmelden bzw. runas, dann:
cmdkey /list:SQLSync*
.\Setup_Credentials.ps1
.\Test-SQLSyncConnections.ps1
```

Login fehlgeschlagen (falsches Passwort) zeigt sich dagegen als Tabellenfehler
bzw. Pre-Flight-Fehler (exit 9) – Lösung ebenfalls `Setup_Credentials.ps1`
(„Überschreiben? J").

### Pre-Flight schlägt fehl (Sync exit 9)

- `Fehler beim Prüfen/Erstellen der Datenbank`: SQL Server nicht erreichbar,
  kein Zugriff auf `master` oder fehlendes `dbcreator` bei nicht existierender
  Ziel-DB → DB vorab durch DBA anlegen lassen oder Recht vergeben.
- `PRE-FLIGHT CHECK (PROCEDURE) FAILED`: `sql_server_setup.sql` fehlt im
  Skriptordner oder keine Verbindung zur Ziel-DB.

### Stored Procedure veraltet / defekt

Der Pre-Flight installiert `dbo.sp_Merge_Generic` automatisch neu, wenn sie fehlt
oder nicht genau 4 Parameter hat. Ist sie vorhanden, aber inhaltlich veraltet
(gleiche Parameteranzahl) oder defekt:

```powershell
# Einmal-Konfig mit General.RecreateStoredProcedure = true
$cfg = Get-Content .\config.json -Raw | ConvertFrom-Json
$cfg.General.RecreateStoredProcedure = $true
$cfg | ConvertTo-Json -Depth 10 | Set-Content .\config_sp.json -Encoding utf8
.\Sync_Firebird_MSSQL_AutoSchema.ps1 -ConfigFile .\config_sp.json
Remove-Item .\config_sp.json
```

Schlägt beim Installieren ein SQL-Batch aus `sql_server_setup.sql` fehl, bricht
der Pre-Flight ab: Log `PRE-FLIGHT CHECK (PROCEDURE) FAILED: Fehler beim Ausführen
eines SQL-Batch aus 'sql_server_setup.sql': <Meldung>`, Exit-Code `9`, keine
Tabelle wird verarbeitet (nur „Database … already exists" wird ignoriert).
Meldung beheben (Rechte, SQL-Server-Version, Datei beschädigt) und erneut laufen
lassen; Ergebnis in SSMS prüfen: `EXEC sp_help 'dbo.sp_Merge_Generic'`.

### Schema-Drift (neue/geänderte Spalten in Firebird)

Symptom: Tabellenfehler beim BulkCopy (Spaltenzuordnung), Typkonvertierung oder
MERGE; oder neue Spalte kommt im Ziel nicht an. Ursache: Staging wird nur beim
Anlegen bzw. mit `RecreateStagingTable` neu aufgebaut, die Zieltabelle wird nie
automatisch erweitert (S11).

```powershell
# 1. Neue Struktur ansehen
.\Get_Firebird_Schema.ps1 -TableName BKUNDE

# 2. Staging neu aufbauen: Einmal-Konfig mit
#    General.RecreateStagingTable = true (optional zusätzlich ForceFullSync = true)
```

3. Zieltabelle anpassen – eine der beiden Varianten:
   - Spalte manuell per `ALTER TABLE <Prefix><Tabelle><Suffix> ADD <Spalte> <Typ>`
     in SSMS ergänzen (Typ wie in der neuen `STG_<Tabelle>`), dann normaler Lauf.
   - Zieltabelle löschen (`DROP TABLE`), nächster Lauf legt sie aus Staging neu an
     und lädt voll. Nur, wenn niemand auf der Tabelle Abhängigkeiten (Views,
     Rechte) hat.

Das Job-Profil Weekly Full (Default `config_weekly_full.json`)
baut Staging wöchentlich neu, erweitert aber die Zieltabelle ebenfalls nicht.

### Nachkommastellen im Ziel gerundet

Symptom: Dezimalwerte im Ziel haben höchstens 4 Nachkommastellen, in Firebird mehr
(z. B. Gewichte, Umrechnungsfaktoren); Summen weichen ab, Sanity bleibt `OK`.
Ursache: Bis v2.13 wurde jedes `Decimal` als `DECIMAL(18,4)` angelegt (S5). Seit v2.14
übernimmt der Sync Precision/Scale aus Firebird (`DECIMAL(p,s)`) – aber nur beim
**Anlegen** von Tabellen. Der Sync ändert keine bestehenden Tabellen: Zieltabellen aus
v2.13 oder älter behalten `DECIMAL(18,4)` und runden weiter, auch wenn
`STG_<Tabelle>` neu und korrekt angelegt wird, weil der MERGE in die alten Zieltypen
schreibt.

1. Betroffene Spalten im Ziel finden (SSMS, Zieldatenbank):

   ```sql
   SELECT TABLE_NAME, COLUMN_NAME
   FROM INFORMATION_SCHEMA.COLUMNS
   WHERE DATA_TYPE = 'decimal' AND NUMERIC_PRECISION = 18 AND NUMERIC_SCALE = 4;
   ```

2. Mit dem Firebird-Schema abgleichen – nur Spalten mit Scale > 4 oder Precision > 18
   sind betroffen (Spalten `Precision`/`Scale`, `Vorschlag SQL`):

   ```powershell
   .\Get_Firebird_Schema.ps1 -TableName BKUNDE   # liest fest config.json
   ```

3. Korrigieren – eine der beiden Varianten:
   - Spalte im Ziel ändern (Typ aus `Vorschlag SQL`, Nullbarkeit wie bisher; Indizes oder
     ein PK auf der Spalte müssen vorher entfernt werden):

     ```sql
     ALTER TABLE [<Ziel>] ALTER COLUMN [<Spalte>] DECIMAL(15,6) NULL;  -- bzw. NOT NULL
     ```

     Bereits gerundete Werte bleiben gerundet, bis die Zeilen neu geladen werden:
     danach einmal mit `ForceFullSync: true` laufen lassen (Einmal-Konfig).
   - Zieltabelle löschen (`DROP TABLE`) und einmal mit Einmal-Konfig
     `RecreateStagingTable: true` + `ForceFullSync: true` laufen lassen: Staging wird mit
     den neuen Typen angelegt, das Ziel per `SELECT * INTO` daraus neu erzeugt und voll
     geladen. Nur, wenn niemand auf der Tabelle Abhängigkeiten (Views, Rechte) hat.
4. Prüfen: Abfrage aus Schritt 1 liefert die Spalte nicht mehr; Stichprobe
   `SUM(<Spalte>)` in Firebird und im Ziel bis zur letzten Nachkommastelle vergleichen.

### Löschungen in Firebird fehlen im Ziel

Standardmäßig werden Löschungen nicht repliziert (Sanity `WARNUNG (+n)`).

- Dauerhaft: `General.CleanupOrphans = true` im Job-Profil. Lädt pro Lauf alle IDs
  aus Firebird in `#SourceIDs_<Tabelle>` und löscht im Ziel per `NOT IN`. Kostet
  Laufzeit bei großen Tabellen; funktioniert nur mit numerischer ID-Spalte (Temp-
  Tabelle ist `BIGINT`, S7) – Fehler erscheinen nur in der Spalte `Info`
  (`Cleanup-Fehler: ...`), nicht als Tabellenfehler.
- Einmalig: Einmal-Konfig mit `ForceFullSync: true` (TRUNCATE Ziel + Voll-Load).
  Hinweis: bei 0 geladenen Zeilen wird das Ziel **nicht** geleert.

### Inkrementelle Änderungen fehlen, Sanity aber OK

Geänderte (nicht neue) Datensätze mit Zeitstempel ≤ letztem Wasserzeichen
(gleicher Zeitstempel, späterer Commit, Uhrenabweichung) werden übersprungen
(S6, I8). Abhilfe: Einmal-Konfig mit `ForceFullSync: true` für die Tabelle;
regulär repariert der Weekly-Full-Lauf.

### Tabelle ohne passende ID-/Timestamp-Spalte

Zusammenfassung zeigt Strategie `Snapshot` (keine ID) oder `FullMerge` (kein
Zeitstempel) – jeder Lauf lädt dann die ganze Tabelle. Spalten per
`TableOverrides` festlegen:

```json
"TableOverrides": { "LEGACY_ORDERS": { "IdColumn": "ORDER_ID", "TimestampColumn": "CHANGED_AT" } }
```

### Task hängt / läuft nicht mehr

Beide Tasks verwenden `MultipleInstances IgnoreNew`: Hängt ein Lauf, werden alle
folgenden Starts **still ignoriert**, bis er endet. Es gibt kein Ausführungs-
Zeitlimit im Skript außer `GlobalTimeout` pro SQL-Befehl/BulkCopy.

```powershell
Get-ScheduledTask -TaskName SQLSync_Firebird_* | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName SQLSync_Firebird_Daily_Diff | Select-Object LastRunTime, LastTaskResult

# Hängenden Lauf beenden
Stop-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff
# Falls pwsh weiterläuft:
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
    Where-Object CommandLine -like '*Sync_Firebird_MSSQL_AutoSchema*' |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

Danach im letzten Log prüfen, an welcher Tabelle er stand (letzte Zeilen
`[<Tabelle>] Starte Verarbeitung` ohne `Abschluss`). Abgebrochene Läufe sind
unkritisch: Staging wird beim nächsten Lauf geleert, der MERGE ist idempotent.
Ausnahme: Abbruch nach `TRUNCATE` der Zieltabelle (ForceFullSync/Snapshot) –
dann die Tabelle erneut laufen lassen.

### Task läuft manuell, aber nicht geplant

- Konto-Passwort geändert → `Setup-ScheduledTasks.ps1` mit denselben
  Parametern erneut ausführen (registriert beide Tasks mit neuem Passwort;
  entfällt bei `-GmsaAccount`).
- `LastTaskResult` `0x41301` = läuft gerade; `0x80070005` = Rechte auf
  Skript-/Logordner fehlen.
- Pfade im Task stimmen nicht → `(Get-ScheduledTask <Name>).Actions` prüfen,
  `Setup-ScheduledTasks.ps1 -InstallDir … -DailyConfigFile … -WeeklyConfigFile … -WhatIf`
  zur Kontrolle, dann ohne `-WhatIf` neu registrieren (`operations/TASK_SCHEDULER.md`).

### Execution Policy blockiert interaktiven Aufruf

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem . -Filter *.ps* | Unblock-File
```

---

## Deployment-Checkliste (Kurzform)

Ausführlich: `operations/SETUP.md` und `operations/DEPLOYMENT.md`.

- [ ] PowerShell 7 auf dem Host
- [ ] Treiber einmalig als Administrator geladen
- [ ] Konfigdateien je Job-Profil angelegt, keine Passwörter darin
- [ ] `Setup_Credentials.ps1` unter dem Task-Konto ausgeführt
- [ ] `Test-SQLSyncConnections.ps1` endet mit Exit 0
- [ ] Manueller Lauf: alle Tabellen `Erfolg` / Sanity `OK`
- [ ] Scheduled Tasks angelegt, erster geplanter Lauf im Log geprüft
