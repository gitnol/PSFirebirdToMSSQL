# Integration Test Conventions – PSFirebirdToMSSQL

Stack: PowerShell 7+ gegen **echte** Firebird- und SQL-Server-Testinstanzen
(Firebird 2.5+/3.x, Port 3050; SQL Server 2017+).

> **Stand 2026-10-10:** Es gibt **keine automatisierten Integrationstests**; die CI (seit I10b) führt nur Unit-Tests und PSScriptAnalyzer aus.
> Einziger vorhandener Integrations-/Smoke-Test ist das Diagnoseskript
> `Test-SQLSyncConnections.ps1`, mit `-PreDeploy` als umfassender, rein lesender Lauf
> (Abschnitt 2.1). Der Pester-5-Harness für Unit-Tests ist seit I3 vorhanden
> (`tests/Unit/`, 192 Tests, Pester 5.7.1 gepinnt in
> `tests/RequiredModules.psd1`, siehe `UNIT_TESTS.md`), deckt aber nur `SQLSyncCommon.psm1`
> ohne echte Instanzen ab. Die Struktur unten ist der Zielzustand; Integrations-Tests bauen auf
> diesem Harness auf.

---

## 1. Grundprinzip: Nicht-destruktiv by Default

Integrationstests laufen standardmäßig **ohne Schreib-, Lösch- oder Änderungsoperationen**.
Für dieses Projekt heißt das konkret:

| Seite | Standard (immer erlaubt) | Nur mit Opt-in `-EnableWriteTests` |
|---|---|---|
| Firebird (Quelle) | Lesen: Verbindung, `rdb$get_context`-/Versionsabfrage, `SELECT FIRST 1 *`, `SELECT COUNT(*)` | — (Firebird wird vom Projekt **nie** beschrieben; auch Tests schreiben dort nicht) |
| SQL Server (Ziel) | Lesen: Version, `INFORMATION_SCHEMA.TABLES`, Existenz/Parameteranzahl von `sp_Merge_Generic` | `CREATE DATABASE`, `sql_server_setup.sql` einspielen, `STG_*`/Zieltabellen anlegen, `TRUNCATE`, `SqlBulkCopy`, `MERGE`, Orphan-`DELETE` — **ausschließlich in einer Test-Ziel-DB** |

```powershell
param(
    [switch] $EnableWriteTests   # Schreibende Tests gegen die Test-Ziel-DB aktivieren
)
```

**Warum:** Ein Sync-Lauf ist auf der SQL-Server-Seite immer schreibend (Staging leeren,
MERGE, ggf. `TRUNCATE` der Zieltabelle bei Snapshot/ForceFullSync, Orphan-Cleanup). Ein Fehler
in Testkonfiguration oder Testcode darf keine produktive Staging-/Ziel-DB beschädigen.

Schreibende Tests werden ohne Opt-in übersprungen:

```powershell
It 'Ein-Tabellen-Sync legt Zieltabelle an und befüllt sie' {
    if (-not $EnableWriteTests) {
        Set-ItResult -Skipped -Because '-EnableWriteTests nicht gesetzt (SKIP)'
        return
    }
    # ... echter Sync-Lauf gegen die Test-Ziel-DB
}
```

---

## 2. Heutiger Smoke-Test: `Test-SQLSyncConnections.ps1`

Rein lesend, ohne Opt-in nutzbar — vor jedem E2E-Lauf und nach jedem Deployment ausführen:

```powershell
pwsh -NoProfile -File .\Test-SQLSyncConnections.ps1 -ConfigFile .\config.test.json
$LASTEXITCODE   # 0 = alles OK
```

Prüft: Firebird-Verbindung + Server-Version, Anzahl Tabellen, Test-`COUNT` auf die erste
konfigurierte Tabelle; SQL-Server-Verbindung + Version, Tabellen, Vorhandensein von
`sp_Merge_Generic`.

| Exit-Code | Bedeutung |
|---|---|
| 0 | alle Tests OK |
| 1 | Modul/Konfigdatei fehlt **oder** mindestens ein Test fehlgeschlagen |
| 2 | Konfiguration nicht parsebar / ungültig (inkl. Verstoß gegen `config.schema.json`) |
| 3 | Credentials nicht auflösbar |
| 4 | Treiber nicht ladbar |
| 6 | nur mit `-PreDeploy`: mindestens ein `FEHLER` (Abschnitt 2.1) |

Manuell belegt am 2026-10-08/09 (Schema-Prüfung, v2.15): schemawidrige Konfig (Typfehler +
Tippfehler-Schlüssel) → Sync Exit 2 vor jeder DB-Verbindung; gültige Konfig Exit 0;
`Test-SQLSyncConnections.ps1` mit relativem `-ConfigFile` Exit 0; `Get_Firebird_Schema.ps1 -ConfigFile`
Exit 0 bzw. Exit 2 bei Schemaverstoß; `Manage_Config_Tables.ps1` mit schemawidriger Konfig Exit 2 ohne Backup.

Bekannte Einschränkung: Die Ausgabe ist für Menschen gedacht (Tabelle, Farben); maschinell
auswertbar ist nur der Exit-Code.
Im Ziel-Harness wird das Skript per Pester aufgerufen und nur der Exit-Code geprüft:

```powershell
It 'Verbindungstest ist grün' {
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'Test-SQLSyncConnections.ps1') -ConfigFile $TestConfig
    $LASTEXITCODE | Should -Be 0
}
It 'Vor-Deployment-Prüfung ohne FEHLER' {
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'Test-SQLSyncConnections.ps1') -ConfigFile $TestConfig -PreDeploy
    $LASTEXITCODE | Should -Be 0   # 6 = mindestens ein FEHLER
}
```

### 2.1 Nicht-destruktiver Integrationslauf: `-PreDeploy`

`Test-SQLSyncConnections.ps1 -PreDeploy` ist der umfassendste Integrationslauf ohne Opt-in: nur
`SELECT`s (Firebird: `RDB$RELATION_FIELDS`/`RDB$FIELDS`, SQL Server: `INFORMATION_SCHEMA.COLUMNS`),
keine DDL/DML, die Treiber-DLL wird für die Hash-Prüfung nicht geladen. Zusätzlich zum Smoke-Test
prüft er alle `config*.json` im Skriptordner gegen Schema und Namensregeln, die Treiber-DLL, die
Firebird-Serverversion gegen bekannte Server-Advisories, die Anmeldung als `SYSDBA`, Zielspalten,
die Dezimalwerte der Quelle kürzen (Altbestand), und seit I10a Schema-Drift (Abschnitt 2.2),
Klartext-Passwörter in den Konfigs und Konfig-Backups im Skriptordner. Ausgabe als Tabelle Status / Prüfung / Detail;
Exit 0 = kein `FEHLER`, 1 = Verbindungstest fehlgeschlagen, 6 = mindestens ein `FEHLER`.

Manuell belegt am 2026-10-09 gegen die Testumgebung (Firebird-Testserver → SQL-Testserver):

| Szenario | Ergebnis |
|---|---|
| Schemawidrige Testkonfig im Skriptordner | `FEHLER` für diese Konfig, Exit 6 |
| Original-Treiber-DLL | `OK` |
| Abgleich der Firebird-Serverversion mit den Advisories | Ausgabe wie erwartet (`OK` bzw. je betroffener CVE eine `WARNUNG` mit erster behobener Version); Ergebnis je Host nur in `docs/local/` |
| Anmeldung als `SYSDBA` | `WARNUNG` mit Empfehlung Lesekonto |
| Altbestand ohne Kürzung | `OK`, 42 Dezimalspalten geprüft |
| Testspalte künstlich auf `DECIMAL(18,4)` gesetzt | `WARNUNG` mit Ziel- und Quelltyp, Exit 0 |
| Korrektur per `operations/RUNBOOK.md` (`ALTER COLUMN` auf `DECIMAL(15,6)` + `ForceFullSync`) | Werte bis zur 6. Nachkommastelle wiederhergestellt; danach `-PreDeploy` wieder `OK` |

Die DDL in den letzten beiden Zeilen (Spalte verkleinern bzw. korrigieren) wurde manuell in der
Test-Ziel-DB ausgeführt, nicht von `-PreDeploy`.

### 2.2 Schema-Drift / K6 (I10a, manuell)

Prüft, dass `-PreDeploy` Quellspalten erkennt, die in vorhandenen Ziel- oder Staging-Tabellen
fehlen, und dass die Einstufung (`FEHLER` / `WARNUNG`) dem tatsächlichen Verhalten des Syncs
entspricht. Ablauf in der Test-Ziel-DB: bei einer Incremental-Testtabelle in der Zieltabelle die
Zeitstempelspalte und eine weitere Spalte entfernen (`ALTER TABLE … DROP COLUMN`), in der
Staging-Tabelle eine Spalte entfernen; dann `-PreDeploy` und Gegenproben mit dem echten Sync.

Manuell belegt am 2026-10-10 gegen die Testumgebung (Firebird-Testserver → SQL-Testserver,
Test-Datenbank):

| Szenario | Ergebnis |
|---|---|
| Basislauf ohne Drift | `OK  Schema-Drift  keine Quellspalte fehlt …` (76 Spalten geprüft) |
| Zieltabelle ohne Zeitstempelspalte und ohne eine weitere Spalte, Staging ohne eine Spalte | `-PreDeploy`: `FEHLER` (Zeitstempelspalte), `WARNUNG` (andere Zielspalte), `FEHLER` (Staging-Spalte); Exit 6 |
| Gegenprobe Sync: nur Zeitstempelspalte fehlt im Ziel | 4 Versuche mit `Ungültiger Spaltenname`, Status `Fehler`, Exit 10 |
| Gegenprobe Sync: nur Staging-Spalte fehlt | BulkCopy `The given ColumnMapping does not match up with any column in the source or destination.`, Exit 10 |
| Gegenprobe Sync: nur Nicht-Schlüsselspalte fehlt im Ziel | Status `Erfolg`, Exit 0; die Spalte fehlt still im Ziel (K6) |
| Tabellen gelöscht und per Erstlauf neu aufgebaut | `-PreDeploy` wieder `OK` |

Die DDL (Spalten entfernen, Tabellen löschen) wurde manuell in der Test-Ziel-DB ausgeführt, nicht
von `-PreDeploy`. Nicht im Integrationslauf nachgestellt: fehlende ID-Spalte im Ziel (`FEHLER`; das
stille `RETURN` von `sp_Merge_Generic` ist aus `sql_server_setup.sql` abgeleitet und per Unit-Test
der Einstufung belegt) und die Ausnahmen `ForceFullSync` / `RecreateStagingTable` (Unit-Tests,
`UNIT_TESTS.md`). Die Prüfungen auf Klartext-Passwörter und Konfig-Backups sind unit-getestet.

---

## 3. Testumgebung und Credentials

- **Eigene Testkonfiguration** `config.test.json` (gitignoren!), abgeleitet aus
  `config.sample.json`, mit:
  - Firebird: Test-Server/Test-Datenbank (Kopie oder DEMO-DB, nie die Produktiv-FDB-Datei).
  - MSSQL: **eigene Test-Ziel-DB**, deren Name mit `TEST_` oder `DEV_` beginnt.
  - `Tables`: genau **eine** kleine Tabelle (siehe Abschnitt 4).
  - Keine Passwörter in der Datei (kein Klartext-Fallback in Tests).
- **Credentials:** Der Code kennt nur die festen Credential-Manager-Targets `SQLSync_Firebird`
  und `SQLSync_MSSQL` (gelesen über `Get-StoredCredential` in `SQLSyncCommon.psm1`) bzw.
  `Integrated Security` für SQL Server. Es gibt **keine** Umgebungsvariablen und keinen
  Test-Target-Namen. Integrationstests laufen deshalb auf einem Testrechner/-konto, dessen
  Einträge auf die Testinstanzen zeigen; eingerichtet mit `Setup_Credentials.ps1`
  (Details: `architecture/CREDENTIAL_STRATEGY.md`).
- **Achtung:** Auf einem Rechner, auf dem der produktive Sync läuft, zeigen dieselben Targets auf
  Produktion. Integrationstests dort **nicht** ausführen — oder SQL Server über ein separates
  Testkonto mit `Integrated Security` ansprechen.
- `Get-StoredCredential` selbst (advapi32 `CredRead`) wird nur hier, nicht in Unit-Tests,
  real geprüft: Eintrag vorhanden → Objekt mit `Username`/`Password`; Target unbekannt → `$null`.

---

## 4. E2E-Test: Ein-Tabellen-Konfiguration (Opt-in)

Der durchgängige Slice ist ein echter Lauf von `Sync_Firebird_MSSQL_AutoSchema.ps1` mit
einer Konfiguration, die **genau eine** kleine Quelltabelle gegen die Test-Ziel-DB synchronisiert.

Ablauf (Create → Test → Teardown):

1. **Guard:** Test-Ziel-DB-Name aus `config.test.json` lesen; beginnt er nicht mit `TEST_`/`DEV_`
   → `throw` (kein Lauf).
2. **Lauf 1 (Initial):** Sync starten. Erwartung: Zieltabelle `Prefix + Tabelle + Suffix` und
   `STG_<Tabelle>` existieren, `sp_Merge_Generic` existiert mit 4 Parametern.
3. **Prüfen:** `COUNT(*)` Firebird == `COUNT(*)` Zieltabelle (entspricht dem Sanity Check „OK").
4. **Lauf 2 (Inkrementell):** erneut starten ohne Quelländerung → Zeilenanzahl unverändert
   (MERGE ist idempotent). Seit v2.18 ist `RowsLoaded` dabei meist > 0: die Zeilen im
   Überlappungsfenster (`General.IncrementalOverlapMinutes`) werden erneut gelesen. Nicht auf
   `RowsLoaded = 0` prüfen.
5. **Teardown** im `finally`: Ziel- und Staging-Tabelle in der Test-Ziel-DB droppen (oder
   die ganze Test-DB, wenn sie vom Test angelegt wurde).

```powershell
param(
    [string] $TestConfig = (Join-Path $PSScriptRoot 'config.test.json'),
    [switch] $EnableWriteTests
)

It 'Ein-Tabellen-Sync: FB-Count == Ziel-Count' {
    if (-not $EnableWriteTests) {
        Set-ItResult -Skipped -Because '-EnableWriteTests nicht gesetzt (SKIP)'; return
    }
    $cfg = Get-Content $TestConfig -Raw | ConvertFrom-Json
    if ($cfg.MSSQL.Database -notmatch '^(TEST_|DEV_)') {
        throw "Test-Ziel-DB '$($cfg.MSSQL.Database)' ist keine Test-DB (TEST_/DEV_ erwartet)."
    }
    try {
        & pwsh -NoProfile -File (Join-Path $RepoRoot 'Sync_Firebird_MSSQL_AutoSchema.ps1') -ConfigFile $TestConfig
        $LASTEXITCODE | Should -Be 0
        # Exit 0 deckt Tabellen-Status und Sanity FEHLER ab (seit I2), nicht aber
        # Sanity WARNUNG oder abgeschaltetes FailOnSanityError — Zeilenanzahl zusätzlich vergleichen:
        Get-FbCount  -Config $cfg -Table $cfg.Tables[0] |
            Should -Be (Get-SqlCount -Config $cfg -Table $cfg.Tables[0])
    }
    finally {
        Remove-TestTargetTables -Config $cfg   # DROP Ziel + STG_ in der Test-DB
    }
}
```

`Get-FbCount`, `Get-SqlCount` und `Remove-TestTargetTables` sind Helfer in
`tests/helpers/TestHelpers.ps1` (mit den Integrationstests anzulegen; existieren noch nicht).

**Wichtig zu S1:** Seit I2 (Sync v2.11) endet der Sync bei Tabellenfehlern mit Exit `10` und
bei Sanity „FEHLER" mit `11`. Das ist bisher nur per Unit-Test (`Get-SyncExitCode`) belegt;
der folgende Negativtest ist die noch offene Abnahme von I2 und muss einmal gegen echte
Instanzen laufen. Ein E2E-Test verlässt sich trotzdem nicht allein auf den Exit-Code
(Sanity `WARNUNG` bleibt `0`).

```powershell
It 'Nicht existierende Tabelle → Exit 10' {
    if (-not $EnableWriteTests) {
        Set-ItResult -Skipped -Because '-EnableWriteTests nicht gesetzt (SKIP)'; return
    }
    $cfg = Get-Content $TestConfig -Raw | ConvertFrom-Json
    $cfg.Tables = @('GIBT_ES_NICHT_XYZ')
    $neg = Join-Path $TestDrive 'config.negative.json'
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $neg -Encoding utf8
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'Sync_Firebird_MSSQL_AutoSchema.ps1') -ConfigFile $neg
    $LASTEXITCODE | Should -Be 10
}
```

Manuell zusätzlich: denselben Lauf als Scheduled Task starten, „Letztes Ergebnis" muss `0xA`
zeigen. Achtung: Der Sync legt das Transcript-Log im Skriptordner an (`Logs\`), nicht in
`$TestDrive`.

**Nebenwirkungen eines Laufs**, die der Test kennen muss:

- Transcript-Log unter `Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log` im Skriptordner;
  Log-Rotation löscht `Sync_*.log` älter als `DeleteLogOlderThanDays` — in `config.test.json`
  `DeleteLogOlderThanDays = 0` setzen, damit Testläufe keine Betriebslogs rotieren.
- Fehlt die Test-Ziel-DB, legt der Pre-Flight Check sie über `master` an
  (`CREATE DATABASE`, `RECOVERY SIMPLE`; braucht `dbcreator`).
- Fehlt der Treiber, wird er (nur als Admin) nach `%ProgramData%\SQLSync\Drivers\...`
  heruntergeladen — Testrechner vorher einmal einrichten.

Optionale Folge-Szenarien (jeweils eigener Test, Opt-in): `ForceFullSync = true`,
`CleanupOrphans = true` (Orphan-Cleanup, nur numerische IDs — S7), Tabelle ohne ID
(Strategie Snapshot), Tabelle mit `TableOverrides`.

### 4.1 Überlappungsfenster / K3 (I8, manuell)

Prüft, dass der Incremental-Extrakt Datensätze mit Zeitstempel ≤ Wasserzeichen nachholt
(`General.IncrementalOverlapMinutes`, Default 10). Ablauf in der Test-Ziel-DB: nach einem
erfolgreichen Lauf in der Zieltabelle einen Datensatz löschen, dessen Zeitstempel knapp
(Sekunden) unter dem Wasserzeichen `MAX(<ts>)` liegt – das simuliert einen Datensatz, der
erst nach dem letzten Lauf committet wurde. Dann den Sync ohne Quelländerung starten.

Manuell belegt am 2026-10-09 gegen die Testumgebung (Firebird-Testserver → SQL-Testserver,
Incremental-Tabelle in der Test-Datenbank, gelöschter Datensatz ~14 s unter dem Wasserzeichen):

| Szenario | Ergebnis |
|---|---|
| Lauf mit v2.16 (striktes `> MAX(ts)`) | 0 Zeilen geladen, Datensatz fehlt weiter, Sanity `FEHLER (-1)`, Exit 11 |
| Lauf mit v2.18 (Fenster 10 Min, `>=`) | 2 Zeilen geladen, Datensatz wieder vorhanden, Sanity `OK`, Exit 0 |
| Läufe ohne Änderungen | je Tabelle 1 bzw. 2 Zeilen geladen (Zeilen im Fenster), Ziel inhaltlich unverändert |
| Zieltabelle geleert (`TRUNCATE`) | Info `(Kein Wasserzeichen (Zieltabelle leer oder Zeitstempel NULL) - Vollabzug)`, alle Zeilen geladen |
| Zieltabelle gelöscht (`DROP TABLE`) | Zieltabelle neu angelegt, Info `(Erstlauf (Zieltabelle fehlt) - Vollabzug)`; Folgelauf wieder inkrementell |

Die DML/DDL (Datensatz löschen, Tabelle leeren bzw. löschen) wurde manuell in der Test-Ziel-DB
ausgeführt. Nicht im Integrationslauf nachgestellt: scheiternde `MAX`-Abfrage auf eine vorhandene
Zieltabelle (→ `Fehler`, Exit 10); das ist per Unit-Test belegt (`UNIT_TESTS.md`).

---

## 5. Test-Assertions: Nie per Pipe aufrufen

Selbst geschriebene Assertion-Hilfsfunktionen (ohne Pester) haben oft **keinen**
`[Parameter(ValueFromPipeline)]`-Parameter. Pipe-Input wird dann still verworfen —
`$Value` bleibt `$null` und die Assertion schlägt fälschlicherweise fehl.

```powershell
function Assert-NotNull {
    param($Value, [string]$Because = '')
    if ($null -eq $Value) { throw "Erwartet: nicht null. $Because" }
}

# ✓ Richtig – direkter Aufruf
Assert-NotNull $myObject

# ✗ Falsch – $myObject wird NICHT übergeben ($Value = $null), Assertion schlägt fehl
$myObject | Assert-NotNull
```

**Lösung A:** Assertions immer direkt aufrufen (ohne Pipe).  
**Lösung B:** `[Parameter(ValueFromPipeline)]` in die Assertion-Funktion eintragen
              und `process {}` Block verwenden — dann funktioniert beides.

Mit Pester (`Should`-Cmdlets): kein Problem, Pester implementiert `ValueFromPipeline`
korrekt. Dieser Hinweis gilt nur für eigene Assertion-Helfer ohne Pester.

---

## 6. Skriptstruktur für Integrationstests

Zielablage: `tests/Integration/SQLSync.Integration.Tests.ps1` (existiert noch nicht). Empfohlene Parameter:

```powershell
param(
    # Testkonfiguration (zeigt auf Test-Firebird + Test-Ziel-DB, ohne Passwörter)
    [string] $TestConfig       = (Join-Path $PSScriptRoot 'config.test.json'),

    # Schreibende Tests (Sync-Lauf, DDL/DML in der Test-Ziel-DB)
    [switch] $EnableWriteTests
)

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
```

**Pfade immer `$PSScriptRoot`-basiert, nie CWD-relativ** — die Projektskripte lösen
`-ConfigFile` relativ zum Arbeitsverzeichnis **oder** zum Skriptordner auf; ein absoluter
Pfad vermeidet Überraschungen.

Aufruf:

```powershell
# nur lesend (Smoke)
Invoke-Pester ./tests/Integration -Output Detailed

# inkl. E2E-Sync gegen die Test-Ziel-DB
$c = New-PesterContainer -Path ./tests/Integration -Data @{ EnableWriteTests = $true }
Invoke-Pester -Container $c -Output Detailed
```

---

## 7. Was nicht automatisiert getestet wird

| Bereich | Grund | Alternative |
|---------|-------|-------------|
| Sync gegen Produktiv-Firebird oder produktive Staging-DB | Produktionsdaten-Schutz, Last auf dem ERP | Nur Testinstanzen; Guard auf `TEST_`/`DEV_` |
| Schreibende Tests ohne `-EnableWriteTests` | Default nicht-destruktiv | Opt-in-Switch |
| `Setup-ScheduledTasks.ps1` – echte Registrierung (Task Scheduler, Admin-Prüfung zur Laufzeit) | OS-spezifisch, Admin, fragt Windows-Passwort ab | `-WhatIf`-Pfad per Unit-Test (`UNIT_TESTS.md` 4.3); Registrierung als manueller Smoke-Test nach Deployment (`operations/TASK_SCHEDULER.md`), noch nicht durchgeführt |
| `Setup_Credentials.ps1` (interaktiv, `CredWrite`) | Interaktiv, schreibt in den Credential Manager | Manuell beim Einrichten des Testrechners |
| `Manage_Config_Tables.ps1` (Out-GridView) | GUI (Auswahl, Sperre gegen das Entfernen der letzten Tabelle, Exit 4, Backup-Rotation `-KeepBackups`) | Manuell; die Startprüfung (Exit 2 vor GridView und Backup) ist manuell belegt; die Backup-Rotation (seit I10a) nur per Unit-Test von `Remove-SQLSyncConfigBackup` |
| Treiber-Download von NuGet | Netz + Admin, einmalig | Manuell beim Einrichten; Hash-Logik per Unit-Test mit Mocks |
