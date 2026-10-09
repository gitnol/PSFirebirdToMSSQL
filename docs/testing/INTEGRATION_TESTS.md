# Integration Test Conventions – PSFirebirdToMSSQL

Stack: PowerShell 7+ gegen **echte** Firebird- und SQL-Server-Testinstanzen
(Firebird 2.5+/3.x, Port 3050; SQL Server 2017+).

> **Stand 2026-10-08:** Es gibt **keine automatisierten Integrationstests** und keine CI.
> Einziger vorhandener Integrations-/Smoke-Test ist das Diagnoseskript
> `Test-SQLSyncConnections.ps1`. Der Pester-5-Harness für Unit-Tests ist seit I3 vorhanden
> (`tests/Unit/SQLSyncCommon.Tests.ps1`, 117 Tests, Pester 5.7.1 gepinnt in
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

Manuell belegt am 2026-10-08/09 (Schema-Prüfung, v2.15): schemawidrige Konfig (Typfehler +
Tippfehler-Schlüssel) → Sync Exit 2 vor jeder DB-Verbindung; gültige Konfig Exit 0;
`Test-SQLSyncConnections.ps1` mit relativem `-ConfigFile` Exit 0; `Get_Firebird_Schema.ps1 -ConfigFile`
Exit 0 bzw. Exit 2 bei Schemaverstoß; `Manage_Config_Tables.ps1` mit schemawidriger Konfig Exit 2 ohne Backup.

Bekannte Einschränkung (S12): die Test-Query-Zeile wird doppelt ausgegeben (Korrektur in I11).
Im Ziel-Harness wird das Skript per Pester aufgerufen und nur der Exit-Code geprüft:

```powershell
It 'Verbindungstest ist grün' {
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'Test-SQLSyncConnections.ps1') -ConfigFile $TestConfig
    $LASTEXITCODE | Should -Be 0
}
```

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
   (MERGE ist idempotent).
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
| `Manage_Config_Tables.ps1` (Out-GridView) | GUI (Auswahl, Sperre gegen das Entfernen der letzten Tabelle, Exit 4) | Manuell; die Startprüfung (Exit 2 vor GridView und Backup) ist manuell belegt |
| Treiber-Download von NuGet | Netz + Admin, einmalig | Manuell beim Einrichten; Hash-Logik per Unit-Test mit Mocks |
