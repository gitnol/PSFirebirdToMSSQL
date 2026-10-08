# Unit Test Conventions – PSFirebirdToMSSQL

> **Stand 2026-10-08: Pester-5-Testharness vorhanden** (Inkrement I3, Schwachstelle S10 erledigt):
> 120 Pester-5-Tests, alle grün: `tests/Unit/SQLSyncCommon.Tests.ps1` (107) – jede exportierte
> Funktion von `SQLSyncCommon.psm1` hat mindestens einen Test – und
> `tests/Unit/Setup-ScheduledTasks.Tests.ps1` (13, nur `-WhatIf`, seit I9; Übersicht in Abschnitt 5).
> Pester ist in `tests/RequiredModules.psd1` auf 5.7.1 gepinnt; `tests/pester.config.ps1` führt
> die Tests mit Code-Coverage auf `SQLSyncCommon.psm1` aus (Ziel 80 %, gemessen am 2026-10-08:
> 84,42 % von 353 Kommandos, Stand I5). Die Diskriminierung der Tests ist per Mutationsprüfung belegt
> (Modul 13 von 13, `Setup-ScheduledTasks.ps1` 8 von 8 Mutationen erkannt, siehe Abschnitt 8.6).
> Weiterhin offen: keine CI (Backlog), keine automatisierten Tests für die übrigen Einstiegsskripte
> (siehe `INTEGRATION_TESTS.md`), keine Testhelfer unter `tests/helpers/`.

Framework: Pester 5.x. Auf dem Entwicklungsrechner sind Pester 3.4.0 (Windows-Bordmittel),
5.7.1 und 6.1.0 installiert — verbindlich ist die in `tests/RequiredModules.psd1` gepinnte
Version 5.7.1, damit lokale Setups und eine spätere CI auf demselben Stand sind:

```powershell
# tests/RequiredModules.psd1
@{ Pester = @{ RequiredVersion = '5.7.1' } }

# Lokales Setup (einmalig) / im CI-Workflow vor dem Testlauf
$req = Import-PowerShellDataFile ./tests/RequiredModules.psd1
Install-Module Pester -RequiredVersion $req.Pester.RequiredVersion `
    -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module Pester -RequiredVersion $req.Pester.RequiredVersion -Force
```

---

## 1. Grundregeln

- Test-Dateien enden auf `.Tests.ps1` und liegen unter `tests/`:
  ```
  tests/
  ├── RequiredModules.psd1             # vorhanden: Pester 5.7.1 gepinnt
  ├── pester.config.ps1                # vorhanden: Lauf mit Coverage, Exit 1 bei Rot/Coverage < Ziel
  ├── coverage.xml                     # erzeugt von pester.config.ps1, gitignored
  ├── Unit/
  │   ├── SQLSyncCommon.Tests.ps1      # vorhanden: 107 Tests, alle exportierten Modulfunktionen
  │   └── Setup-ScheduledTasks.Tests.ps1  # vorhanden: 13 Tests, nur -WhatIf
  ├── Integration/                     # noch nicht vorhanden, siehe INTEGRATION_TESTS.md
  └── helpers/
      └── TestHelpers.ps1              # noch nicht vorhanden; z. B. New-TestConfigFile (JSON in $TestDrive)
  ```
- Unit-Tests laden `SQLSyncCommon.psm1` — nicht die Einstiegsskripte
  (`Sync_Firebird_MSSQL_AutoSchema.ps1` u. a. starten sofort Transcript, Treiber und DB-Verbindungen).
  Einzige Ausnahme: `Setup-ScheduledTasks.ps1`, das ausschließlich mit `-WhatIf` aufgerufen wird
  (Abschnitt 4.3).
- Jeder Test läuft isoliert — kein gemeinsamer State zwischen `It`-Blöcken. Testkonfigurationen
  werden pro Test in `$TestDrive` geschrieben, nie im Projekt-Root.
- Keine Netz-/DB-Zugriffe in Unit-Tests: Firebird, SQL Server, Credential Manager (`advapi32`)
  und der NuGet-Download werden gemockt bzw. gehören in die Integrationstests.
- **Niemals** `config.json`, `config.json.*.bak` oder echte Credential-Manager-Einträge
  (`SQLSync_Firebird`, `SQLSync_MSSQL`) in Tests lesen — sie können Klartext-Passwörter enthalten.
  Testpasswörter sind offensichtliche Dummies (`'dummy'`, `'ab;Port=1'`).

---

## 2. Pester-Installation und Ausführung

```powershell
# Verbindlicher Lauf (aus dem Repo-Root): gepinntes Pester, Coverage, Exit-Code für Gates
pwsh -NoProfile -File .\tests\pester.config.ps1

# Schnell, ohne Coverage (nutzt die zuerst gefundene Pester-Version — vorher
# Import-Module Pester -RequiredVersion 5.7.1 -Force, falls mehrere installiert sind)
Invoke-Pester ./tests

# Einzelne Datei, ausführliche Ausgabe
Invoke-Pester ./tests/Unit/SQLSyncCommon.Tests.ps1 -Output Detailed
```

`tests/pester.config.ps1` endet mit Exit-Code 1, wenn ein Test fehlschlägt oder die Coverage
unter dem Ziel liegt (Details in Abschnitt 6). Die Tests brauchen keine Datenbankverbindung,
laufen aber nur unter Windows (Credential Manager, Typ-Pfade). Für die Fälle zu
`Initialize-FirebirdDriver` eine frische `pwsh`-Session ohne geladenen Firebird-Treiber
verwenden (siehe 4.2) — `-NoProfile -File` erfüllt das.

---

## 3. Grundstruktur eines Tests (Beispiele gegen reale Modulfunktionen)

```powershell
# tests/Unit/SQLSyncCommon.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $script:RepoRoot 'SQLSyncCommon.psm1') -Force
}

Describe 'ConvertTo-SqlServerType' {
    It 'mappt String mit Größe 50 auf NVARCHAR(50)' {
        ConvertTo-SqlServerType -DotNetTypeName 'String' -Size 50 | Should -Be 'NVARCHAR(50)'
    }
    It 'mappt String über 4000 Zeichen auf NVARCHAR(MAX)' {
        ConvertTo-SqlServerType -DotNetTypeName 'String' -Size 5000 | Should -Be 'NVARCHAR(MAX)'
    }
    It 'mappt Decimal mit Precision/Scale auf DECIMAL(p,s)' {
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' -Precision 15 -Scale 6 | Should -Be 'DECIMAL(15,6)'
    }
    It 'fällt bei Decimal ohne Precision/Scale auf DECIMAL(18,4) zurück' {
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' | Should -Be 'DECIMAL(18,4)'
    }
    It 'fällt bei unbekanntem Typ auf NVARCHAR(MAX) zurück' {
        ConvertTo-SqlServerType -DotNetTypeName 'Unbekannt' | Should -Be 'NVARCHAR(MAX)'
    }
}

Describe 'Get-TableColumnConfig' {
    BeforeEach {
        $script:Cfg = @{ IdColumn = 'ID'; TimestampColumns = @('GESPEICHERT'); TableOverrides = @{} }
    }
    It 'liefert Incremental bei ID- und Timestamp-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BKUNDE' -Config $script:Cfg -ActualColumns @('ID', 'NAME', 'GESPEICHERT')
        $r.SyncStrategy    | Should -Be 'Incremental'
        $r.TimestampColumn | Should -Be 'GESPEICHERT'
    }
    It 'liefert FullMerge ohne Timestamp-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BKUNDE' -Config $script:Cfg -ActualColumns @('ID', 'NAME')
        $r.SyncStrategy    | Should -Be 'FullMerge'
        $r.TimestampColumn | Should -BeNullOrEmpty
    }
    It 'liefert Snapshot ohne ID-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BSA' -Config $script:Cfg -ActualColumns @('NAME')
        $r.SyncStrategy | Should -Be 'Snapshot'
        $r.IdColumn     | Should -BeNullOrEmpty
    }
    It 'bevorzugt TableOverrides vor den globalen Defaults' {
        $script:Cfg.TableOverrides['LEGACY_ORDERS'] = @{ IdColumn = 'ORDER_ID'; TimestampColumn = 'CHANGED_AT' }
        $r = Get-TableColumnConfig -TableName 'LEGACY_ORDERS' -Config $script:Cfg -ActualColumns @('ORDER_ID', 'CHANGED_AT')
        $r.IdColumn   | Should -Be 'ORDER_ID'
        $r.IsOverride | Should -BeTrue
    }
}

Describe 'New-FirebirdConnectionString' {
    It 'maskiert ";" im Passwort, sodass kein weiterer Schlüssel eingeschleust wird' {
        $cs = New-FirebirdConnectionString -Server 'fbtest' -Database 'C:\db\TEST.FDB' `
              -Username 'SYSDBA' -Password 'ab;Port=1'
        $b = [System.Data.Common.DbConnectionStringBuilder]::new()
        $b.set_ConnectionString($cs)
        # get_Item statt $b['...']: der PowerShell-Adapter löst den Indexer hier nicht zuverlässig auf
        $b.get_Item('Password') | Should -Be 'ab;Port=1'
        $b.get_Item('Port')     | Should -Be '3050'
    }
}

Describe 'Protect-SqlString' {
    It 'verdoppelt einfache Anführungszeichen' {
        Protect-SqlString "O'Brien" | Should -Be "O''Brien"
    }
    It 'gibt bei leerem Input einen Leerstring zurück' {
        Protect-SqlString '' | Should -Be ''
    }
}

Describe 'Get-SQLSyncConfig' {
    BeforeEach { $script:CfgPath = Join-Path $TestDrive 'config.test.json' }

    It 'setzt Defaults (z. B. NumberOfThreads = 4)' {
        Set-Content $script:CfgPath '{"Tables":["BKUNDE"]}'
        (Get-SQLSyncConfig -ConfigPath $script:CfgPath).NumberOfThreads | Should -Be 4
    }
    It 'wirft bei leerer Tables-Liste' {
        Set-Content $script:CfgPath '{"Tables":[]}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'Keine Tabellen in der Konfiguration definiert.'
    }
    It 'wirft bei OrphanCleanupBatchSize < 1000' {
        Set-Content $script:CfgPath '{"General":{"OrphanCleanupBatchSize":500},"Tables":["BKUNDE"]}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'OrphanCleanupBatchSize muss mindestens 1000 sein.'
    }
    It 'wirft bei fehlender Datei' {
        { Get-SQLSyncConfig -ConfigPath (Join-Path $TestDrive 'fehlt.json') } |
            Should -Throw -ExpectedMessage 'Konfigurationsdatei nicht gefunden:*'
    }
}
```

---

## 4. Mock-Pattern: Credential Manager und Treiber

Alle Mocks auf Funktionen, die **innerhalb** des Moduls aufgerufen werden, brauchen
`-ModuleName SQLSyncCommon` — sonst greift der Mock nicht.

### 4.1 `Get-StoredCredential` (advapi32 via `Add-Type`)

`Get-StoredCredential` kompiliert beim ersten Aufruf per `Add-Type` einen C#-Wrapper um
`advapi32!CredRead` und liest den echten Windows Credential Manager. Das ist **nicht**
unit-testbar (Windows-only, maschinen-/kontogebunden) — die Funktion selbst gehört in die
Integrationstests. In Unit-Tests wird sie in den Aufrufern gemockt:

```powershell
Describe 'Resolve-FirebirdCredentials' {
    It 'nimmt den Credential-Manager-Eintrag vor dem config.json-Fallback' {
        Mock Get-StoredCredential -ModuleName SQLSyncCommon {
            [pscustomobject]@{ Username = 'SYNCUSER'; Password = 'dummy' }
        }
        $raw = [pscustomobject]@{ Firebird = [pscustomobject]@{ Password = 'fallback' } }
        $r = Resolve-FirebirdCredentials -Config $raw
        $r.Source | Should -Be 'CredentialManager'
        Should -Invoke Get-StoredCredential -ModuleName SQLSyncCommon -Times 1 -Exactly `
            -ParameterFilter { $Target -eq 'SQLSync_Firebird' }
    }
    It 'fällt auf config.json zurück und setzt User-Default SYSDBA' {
        Mock Get-StoredCredential -ModuleName SQLSyncCommon { $null }
        $raw = [pscustomobject]@{ Firebird = [pscustomobject]@{ Password = 'dummy' } }
        $r = Resolve-FirebirdCredentials -Config $raw
        $r.Source   | Should -Be 'ConfigFile'
        $r.Username | Should -Be 'SYSDBA'
    }
    It 'wirft ohne Credential-Manager-Eintrag und ohne Passwort' {
        Mock Get-StoredCredential -ModuleName SQLSyncCommon { $null }
        $raw = [pscustomobject]@{ Firebird = [pscustomobject]@{} }
        { Resolve-FirebirdCredentials -Config $raw } | Should -Throw '*Setup_Credentials.ps1*'
    }
}
```

Analog für `Resolve-MSSQLCredentials` (Reihenfolge: `Integrated Security` → `SQLSync_MSSQL` → config.json).
`Write-Host`-Ausgaben der Resolver stören Pester nicht; bei Bedarf `Mock Write-Host -ModuleName SQLSyncCommon {}`.

### 4.2 `Initialize-FirebirdDriver`

Die Funktion prüft geladene Assemblies, sucht Kandidatenpfade (`DllPath`,
`%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\lib\...`), lädt bei
Bedarf per `Invoke-WebRequest` von NuGet, prüft SHA-256 und ruft `Add-Type -Path` auf.
Unit-Tests dürfen **weder herunterladen noch eine DLL laden**:

- `Mock Invoke-WebRequest`, `Mock Expand-Archive`, `Mock Add-Type`, `Mock Get-FileHash`,
  `Mock Test-Path` jeweils mit `-ModuleName SQLSyncCommon`.
- Achtung: Ist der Treiber in der Test-Session bereits geladen (Schritt A,
  `[AppDomain]::CurrentDomain.GetAssemblies()`), kehrt die Funktion sofort zurück — Tests daher
  in einer frischen `pwsh`-Session laufen lassen, in der kein Firebird-Treiber geladen wurde.
- Die innere Hilfsfunktion `Test-IsAdministrator` ist **innerhalb** von `Initialize-FirebirdDriver`
  definiert und damit nicht mockbar. Der Pfad „Treiber fehlt, kein Admin → throw" ist nur
  testbar, wenn die Tests ohne Adminrechte laufen; der Download-Pfad nur mit Adminrechten.
  Für I7 vorgesehen: Admin-Check als Modulfunktion herausziehen, damit beide Pfade mockbar werden.
- Umgesetzte Unit-Fälle: (a) `DllPath` existiert → kein Download, `Add-Type` genau einmal;
  (b) ohne Adminrechte und ohne Treiber → throw, kein Download, kein `Add-Type`. Beide Fälle
  werden per `Set-ItResult -Skipped` übersprungen, wenn der Treiber in der Session schon geladen
  ist; Fall (b) zusätzlich, wenn die Tests mit Adminrechten laufen.
- Mit I7 hinzuzufügen: Hash-Mismatch nach Download → throw mit „SHA-256 … stimmt nicht",
  `Add-Type` nie aufgerufen.

```powershell
Describe 'Initialize-FirebirdDriver' {
    It 'lädt eine vorhandene DllPath-DLL ohne Download' {
        Mock Test-Path -ModuleName SQLSyncCommon { $true }
        Mock Add-Type -ModuleName SQLSyncCommon { }
        Mock Invoke-WebRequest -ModuleName SQLSyncCommon { throw 'darf nicht aufgerufen werden' }

        $p = Initialize-FirebirdDriver -DllPath 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll'
        $p | Should -Be 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll'
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 1 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 0
    }
}
```

Dieser Fall dokumentiert zugleich S4: eine vorhandene/konfigurierte DLL wird heute **ohne**
Hash-Prüfung geladen. Mit I7 kommt ein Test hinzu, der genau das verbietet (Hash-Mismatch → throw).

### 4.3 `Setup-ScheduledTasks.ps1` (nur `-WhatIf`)

Das Skript ist per `[CmdletBinding(SupportsShouldProcess)]` so geschnitten, dass `-WhatIf` alle
Task-Definitionen (Aktion, Trigger, Settings, Principal) berechnet und als Objekte ausgibt, ohne
Adminrechte zu prüfen, ohne Passwort abzufragen und ohne zu registrieren. Die Tests rufen es
deshalb ausschließlich mit `-WhatIf` auf und prüfen die zurückgegebenen Objekte:

```powershell
BeforeAll {
    $script:Script = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'Setup-ScheduledTasks.ps1'
    function Invoke-Setup { param([hashtable]$Params = @{}) & $script:Script @Params -WhatIf 6>$null }
}
Describe 'Setup-ScheduledTasks.ps1 (-WhatIf)' {
    BeforeEach {
        # Sicherheitsnetz: würde -WhatIf ignoriert, schlägt der Test fehl statt Tasks anzulegen
        Mock Register-ScheduledTask { throw 'darf unter -WhatIf nicht aufgerufen werden' }
        Mock Unregister-ScheduledTask { throw 'darf unter -WhatIf nicht aufgerufen werden' }
        Mock Get-Credential { throw 'darf unter -WhatIf nicht aufgerufen werden' }
    }
    It 'registriert nichts' {
        foreach ($t in @(Invoke-Setup)) { $t.Registered | Should -BeExactly $false }
        Should -Invoke Register-ScheduledTask -Times 0 -Exactly
        Should -Invoke Get-Credential -Times 0 -Exactly
    }
}
```

Abgedeckt: Defaults (zwei Tasks, Skriptordner als Installations- und Arbeitsverzeichnis,
`config.json`/`config_weekly_full.json`, Zeitplan Mo–Fr 06:01 alle 30 Min. für 15 h ohne
`StopAtDurationEnd`, So 05:13, `MultipleInstances IgnoreNew`, keine Registrierung), Parameter
(relative und absolute Konfigpfade, Taskname/Zeitplan/Intervall, Principal mit `-GmsaAccount` bzw.
`-RunAsUser`) und ein Repo-Hygiene-Test gegen fest eingetragene Laufwerkspfade. Nicht
unit-getestet: die Admin-Prüfung, die Passwortabfrage und der echte Registrierungslauf – ein
Lauf mit Adminrechten ist noch nicht durchgeführt (`operations/TASK_SCHEDULER.md`).

---

## 5. Was wird getestet

Ist-Stand 2026-10-08 (120 Tests, alle grün: `tests/Unit/SQLSyncCommon.Tests.ps1` 107, `tests/Unit/Setup-ScheduledTasks.Tests.ps1` 13):

| Funktion (`SQLSyncCommon.psm1`) | Unit-Test | Was geprüft wird |
|---|---|---|
| `Get-SyncExitCode` | Ja | Exit 0/10/11, Vorrang 10 vor 11, Sanity `WARNUNG`, `FailOnSanityError = false`, keine bzw. zu wenige Ergebnisse |
| `Get-SQLSyncConfig` | Ja | Defaults (u. a. `GlobalTimeout`, `FailOnSanityError`), Validierungen (`GlobalTimeout`, `Tables`, `OrphanCleanupBatchSize`, fehlende Datei, ungültiges JSON), Namensprüfung je Feld (`Tables`, `IdColumn`, `TimestampColumns`, `MSSQL.Database`, Prefix/Suffix, `TableOverrides`-Schlüssel und -Spalten → throw), Grenze Zieltabellenname 128 Zeichen, `TimestampColumns` als Array, TableOverrides, Credential-Targets aus der Konfiguration |
| `Assert-SqlIdentifier` | Ja | Gültige Namen (inkl. `_`, `$`, Ziffern, 63 Zeichen) laufen durch; ungültige werfen `Ungültiger Name in '<Feld>'`: `A"B`, `X;DROP`, `A]B`, `A'B`, Leerzeichen, `-`, leer (ohne `-AllowEmpty`), 64 Zeichen; leer mit `-AllowEmpty` erlaubt |
| `Get-ConfigValue` | Ja | Wert vorhanden, Default bei fehlendem Wert, `false` wird nicht durch den Default ersetzt |
| `Get-TableColumnConfig` | Ja | Strategiewahl Incremental / FullMerge / Snapshot, Override-Vorrang, Fallback bei fehlender Override-Spalte |
| `ConvertTo-SqlServerType` | Ja | Typmapping aller Typen inkl. `Guid`; Decimal mit Precision/Scale (`DECIMAL(15,6)`, `DECIMAL(18,0)`, `DECIMAL(38,10)`), Precision > 38 → 38, nur Scale bekannt → `DECIMAL(38,s)`, beides DBNull/fehlend → Fallback `DECIMAL(18,4)`, Precision/Scale bei Nicht-Decimal ignoriert |
| `New-FirebirdConnectionString`, `New-MSSQLConnectionString` | Ja | Maskierung von `; = ' "`, SecureString-Konvertierung, Integrated Security |
| `Protect-SqlString` | Ja | Escaping einfacher Anführungszeichen, Leerstring und `$null` |
| `Resolve-FirebirdCredentials`, `Resolve-MSSQLCredentials` | Ja, mit `Mock Get-StoredCredential -ModuleName SQLSyncCommon` | Reihenfolge, Fallback auf config.json, Integrated Security ohne Credential-Manager-Abfrage, konfigurierbares `CredentialTarget` samt Fehlermeldung |
| `Get-StoredCredential` | Ja, nur lesend (Tag `Windows`) | nicht existierender Eintrag → `$null`; echte Einträge werden nie gelesen |
| `Close-DatabaseConnection` | Ja | `$null` wird ignoriert; Close und Dispose je einmal; Dispose auch, wenn Close wirft |
| `Write-SyncStatus` | Ja, mit `Mock Write-Host` | Format `[Tabelle] Text` und Farbe je Level |
| `Initialize-FirebirdDriver` | Teilweise, mit Mocks (siehe 4.2) | `DllPath` vorhanden → kein Download; ohne Admin und ohne Treiber → throw ohne Download |
| `Setup-ScheduledTasks.ps1` | Ja, nur `-WhatIf` (Register-/Unregister-ScheduledTask, Get-Credential gemockt) | Task-Definitionen aus Defaults und Parametern, gMSA-Principal, keine Registrierung, keine festen Laufwerkspfade (Abschnitt 4.3) |
| Übrige Einstiegsskripte (`Sync_Firebird_MSSQL_AutoSchema.ps1` usw.) | Nein → Integration/E2E | Ablauf mit DB-Zugriff; Typmapping und Spalten-/Strategieermittlung nutzt der Sync seit v2.14 aus dem Modul (dort unit-getestet), die Configpfad-Auflösung ist noch dupliziert (I6) |

Querschnittlich: Edge Cases (leeres Array, `$null`, Sonderzeichen in Tabellennamen und
Passwörtern, Identifier-Allow-List `^[A-Za-z0-9_$]+$` mit Quote-, Klammer- und Semikolon-Fällen).
Nicht automatisiert getestet: die GUI-Pfade von `Manage_Config_Tables.ps1` (Markierung und
Überspringen ungültiger Tabellennamen) und die Klammerung/Parametrisierung im Hauptskript – letztere
ist durch manuelle Integrationsläufe am 2026-10-08 (Firebird-Testserver → SQL-Testserver: ForceFull, inkrementell
mit `CleanupOrphans`, Fehlerkonfig Exit 10) abgedeckt.

---

## 6. Pester-Konfiguration (`tests/pester.config.ps1`)

Kern der Datei (vollständig im Repo, `#Requires -Version 7.0`):

```powershell
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Required = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'RequiredModules.psd1')
Import-Module Pester -RequiredVersion $Required.Pester.RequiredVersion -Force

$Config = New-PesterConfiguration
$Config.Run.Path = Join-Path $PSScriptRoot 'Unit'
$Config.Run.Exit = $true
$Config.Output.Verbosity = 'Normal'
$Config.CodeCoverage.Enabled = $true
$Config.CodeCoverage.Path = Join-Path $RepoRoot 'SQLSyncCommon.psm1'
$Config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
$Config.CodeCoverage.CoveragePercentTarget = 80

Invoke-Pester -Configuration $Config
```

- `Run.Exit = $true`: Exit-Code 1 bei einem roten Test oder Coverage unter dem Ziel — damit als
  Gate in Skripten und einer späteren CI verwendbar.
- Coverage nur auf `SQLSyncCommon.psm1`; die Einstiegsskripte gehen nicht in die Coverage ein
  (auch nicht `Setup-ScheduledTasks.ps1`, dessen Tests nur den `-WhatIf`-Pfad abdecken).
- Kalibrierung: gemessen am 2026-10-08 82,54 % (315 Kommandos, I3), nach I5 84,42 % (353), Ziel 80 %. Das Ziel wird nur
  angehoben, nie abgesenkt.
- `tests/coverage.xml` ist ein Laufartefakt und steht in `.gitignore`.

---

## 7. Pester-5-Fallstricke (häufige Ursachen für „klappt lokal nicht" / „klappt in CI nicht")

Sammlung von Stolpersteinen, die sonst pro Projekt neu entdeckt werden. Quelle:
gelernte Lessons aus realen PowerShell-Modul-Projekten.

### 7.1 `BeforeEach`/`AfterEach` brauchen `Describe`/`Context`-Scope
Top-Level-`AfterEach` (direkt im Skript, außerhalb eines `Describe`) wirft in
Pester 5: **„Each test Teardown is not supported in root (directly in the block
container)"**. Cleanup-Logik immer **innerhalb** des Describe-Blocks platzieren,
in dem sie greift.

### 7.2 `System.Uri` normalisiert Default-Ports weg
Sobald ein Mock-Parameter den Typ `[Uri]` hat (typisch bei
`Mock Invoke-WebRequest`, weil `-Uri` im echten Cmdlet `[Uri]`-typisiert ist),
strippt .NET die Default-Ports 443 (HTTPS) und 80 (HTTP) aus der URL. Tests,
die den Port-Aufbau prüfen sollen, müssen **Nicht-Standard-Ports** stubben
(z.B. 4443 / 8080) — sonst lässt sich der erwartete URI-String nicht treffen.

### 7.3 Pester-5-Coverage-API: `CommandsExecuted` + `CommandsMissed`
`$result.CodeCoverage.CommandsAnalyzed` ist in Pester 5 **`$null`**. Per-File-
Coverage rechnet man auf der Vereinigung von `CommandsExecuted` und
`CommandsMissed`, üblicherweise via `Group-Object File`:

```powershell
$all = @($cov.CommandsExecuted) + @($cov.CommandsMissed)
$all | Group-Object File | ForEach-Object {
    $exec = ($_.Group | Where-Object { $_ -in $cov.CommandsExecuted }).Count
    [pscustomobject]@{ File = $_.Name; Coverage = [math]::Round(100*$exec/$_.Count,1) }
}
```

### 7.4 `-SessionVariable` lässt sich nicht mocken
Cmdlets, die `-SessionVariable arubasw` (oder analog) nutzen und dann in eigenem
Code `$arubasw.Cookies.Add(...)` aufrufen, brechen unter `Mock`: das Mock-Replacement
führt den `-SessionVariable`-Mechanismus nicht aus, also bleibt `$arubasw = $null`
und der Folgecode wirft `NullReferenceException`. End-to-End-Tests solcher Pfade
brauchen entweder einen lokalen HTTP-Listener-Helper (`System.Net.HttpListener`,
~50 Zeilen) oder eine eigene Test-Mode-Tür im Cmdlet — Mocken allein reicht
nicht.

### 7.5 `Should -BeOfType [object[]]` via Pipeline prüft Element-Typen
`$array | Should -BeOfType [object[]]` testet **jedes Element** gegen `object[]`,
nicht die Collection. Für „ist das ein Array?"-Checks:
```powershell
($value -is [Array]) | Should -BeTrue
```
ohne Pipeline.

### 7.6 PowerShell-Dateien mit Nicht-ASCII brauchen UTF-8 **mit BOM** — oder besser: ASCII bleiben
Sonst löst PSScriptAnalyzer `PSUseBOMForUnicodeEncodedFile` aus, und CI mit
`failOnWarnings: true` bricht ab. Klassische Stolper-Quellen in `.ps1`-Code:

- **Umlaute in Comments / Strings** (`Verfügbar`, `Größe`, …) — typischerweise
  unvermeidbar in deutschen Test-Dateien.
- **Em-dash / En-dash** (`—` U+2014, `–` U+2013) in Comment-based Help. Auf
  englischer Tastatur leicht aus Autokorrektur reingerutscht; PSSA flaggt es
  in `.ps1` genauso wie einen Umlaut.

Im **Test-File** (mit deutschen `It`-Strings) ist BOM die richtige Lösung:

```powershell
$utf8bom = [System.Text.UTF8Encoding]::new($true)
[System.IO.File]::WriteAllText($path, [System.IO.File]::ReadAllText($path), $utf8bom)
```

In **Module-Source** (`Public/*.ps1`, `Private/*.ps1`) ist die *bessere* Lösung:
**bei ASCII bleiben** (em-dash → `--`, Umlaute vermeiden). BOM-Pflicht verkompliziert
Tools/Heredocs/Datei-Vergleiche und sollte sich auf Test-Files mit echten
Lokalisierungs-Strings beschränken.

### 7.7 PSGallery braucht TLS 1.2 — Windows PowerShell 5.1 startet mit TLS 1.0
Vor jedem `Install-Module` / `Find-Module` auf Desktop in CI-Schritten:
```powershell
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
```

### 7.8 `Install-Module -SkipPublisherCheck` für Pester 5.x
Windows PowerShell 5.1 liefert Pester 3.4.0 vorinstalliert; die Signatur-Publisher
unterscheiden sich von Pester 5. Ohne `-SkipPublisherCheck` schlägt der Install
fehl. Außerdem: nach Install **explizit** `Import-Module Pester -RequiredVersion 5.x.x -Force`,
sonst lädt PS 5.1 weiterhin die eingebaute 3.4.0.

### 7.9 PSSA-Suppress-Attribute in Test-Dateien brauchen einen `Param()`-Block
`[Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]` ohne nachfolgendes
`Param()` (oder ohne Funktion) wird von PSScriptAnalyzer ignoriert — das Finding
bleibt und CI bricht. In Pester-Test-Dateien ist der saubere Weg, einen leeren
`Param()`-Block am Datei-Anfang einzuziehen, an dem das Attribut hängt:

```powershell
# Häufiger Bedarf in Tests: Dummy-SecureString, der den interaktiven
# Get-Credential-Prompt unterdrückt. PSAvoidUsingConvertToSecureStringWithPlainText
# würde sonst als Error feuern.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
Param()

BeforeAll {
    $secure = ConvertTo-SecureString 'pw' -AsPlainText -Force
    $script:DummyCred = [pscredential]::new('dummy', $secure)
}
```

Gleiches Pattern für `PSAvoidUsingEmptyCatchBlock` etc., wenn ein bewusst leerer
`catch {}` semantisch korrekt ist (z.B. Test prüft Warnungen, der spätere `throw`
ist erwartet und uninteressant).

### 7.10 `SuppressMessageAttribute`-Argumente sind String-**Konstanten** — Single-Quote-Pflicht

Ein scheinbar harmloses Detail mit harten Konsequenzen: Argumente an
`SuppressMessageAttribute` (`category`, `checkId`, `justification`) müssen
**String-Konstanten** sein. Eine Double-Quote-Justification wie
`Justification = "...$global:Foo ist..."` wird vom PowerShell-Parser als
**String-Interpolation** gewertet und damit nicht als Konstante akzeptiert.
PSScriptAnalyzer bricht dann mit:

> All the arguments of the Suppress Message Attribute should be string constants.

und das Attribut **greift nicht** — die Finding bleibt, CI bricht.

**Fix:** in Suppress-Attribut-Strings immer Single-Quotes verwenden:

```powershell
# Falsch (Parser sieht Interpolation):
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "",
    Justification = "Zugriff auf $global:DefaultFooConnection ist API.")]

# Richtig (Single-Quote = echte Konstante):
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
    Justification = 'Zugriff auf die globale DefaultFooConnection ist Teil der API.')]
```

Die gleiche Falle gibt's bei `[Parameter(...)]`, `[ValidateSet(...)]` und allen
anderen PowerShell-Attributen — sobald `$` in einem Double-Quote-Argument
auftaucht, wird daraus eine Interpolation und das Attribut wird invalid.

---

## 8. TDD-Disziplin (Iterations-Log + Gate-Reihenfolge)

Konkretisierung der TDD-Startregel aus `KICKOFF.md` Phase 2 für diesen Stack
(PowerShell-Modul/-Script + Pester 5). Verwandte Prinzipien: `principles/ADVOCATUS_DIABOLI.md`,
`principles/CETERIS_PARIBUS.md`, `principles/VERIFY_BEFORE_CITE.md`, `principles/YAGNI.md`.

### 8.1 Behaviorales Rot ist Pflicht (realen Pester-Output einfangen)

Ein neuer Test muss als **echter `Invoke-Pester`-Lauf** rot sein — wegen einer **scheiternden
Assertion** (`Should -Be …`), nicht nur weil die Funktion noch fehlt (`CommandNotFoundException`)
oder ein Symbol nicht existiert. Letzteres ist nur **strukturelles** Rot; erst behaviorales Rot
beweist, dass der Test *diskriminiert*. Den realen Output zitieren („`Expected 2, but got 3`"),
nie „der Test sollte fehlschlagen". Praxis: die Funktion zuerst als leere Hülle (oder mit
falschem Rückgabewert) anlegen, damit der Test bis zur **Assertion** läuft und dort rot wird.

### 8.2 Erster-Lauf-grün → STOPPEN (und falsch-grün)

Ist ein neuer Test beim ersten Lauf schon grün, ist er verdächtig (testet nichts ODER das
Verhalten existiert bereits) → anhalten und untersuchen. Gleiches gilt für **falsch-grün**:
eine Assertion wie `$result -ne $null` kann grün sein, obwohl sie nichts beweist — z.B. wenn ein
Nebeneffekt Output in die Pipeline leckt (siehe `CONVENTIONS.md` „Bare-Aufruf … Output-Stream").
Exakt prüfen (`Count -eq 1`, erwarteter Typ/Wert), nicht „irgendetwas kam zurück".

### 8.3 Gate-Reihenfolge pro Code-Inkrement (Definition of Done)

In dieser Reihenfolge, jede Stufe grün, bevor committet wird:

1. **Gate 1 — Linter:** `Invoke-ScriptAnalyzer -Path <geänderte Dateien> -Severity Warning`.
   Projektweit bewusst akzeptierte Findings (dokumentieren, z.B. Ressourcen-Plurale bei
   `PSUseSingularNouns`) sind kein Stopp; neue Findings zuerst beheben.
2. **Gate 4 — Unit-Tests:** `pwsh -NoProfile -File .\tests\pester.config.ps1` → Exit 0 (0 Failed, Coverage ≥ Ziel).
3. **Integrationstests (nicht-destruktiv):** falls vorhanden, gegen echte Instanz → Exit 0;
   **kein `-EnableWriteTests`** ohne ausdrückliche Freigabe (siehe `INTEGRATION_TESTS.md`).

### 8.4 Iterations-Log

Pro TDD-Zyklus im `CHANGELOG.md`-Eintrag kurz festhalten: **Rot** (welche Assertion, realer
Output) → **Grün** (minimale Implementierung) → **Refactor**. Kausale Aussagen
(„Fix X behebt Fehler Y") nur unter **Ceteris Paribus** (eine Variable pro Lauf), sonst trägt
das Ergebnis keine Einzelursachen-Aussage.

### 8.5 Einsatzgrenze — was hier TDD-bar ist und was nicht

| Schicht | TDD-Disziplin | Verifikation |
|---|---|---|
| Deterministische Kern-Logik (Body-/URL-Aufbau, Parsing, Filter, Mapping) | **Ja** — Pester mit gemocktem Transport-Wrapper (siehe Abschnitt 4) | rot→grün, exakte Assertions |
| Echte externe API/Dienste (HTTP, DB, Netz) | Nein (extern/nicht-deterministisch) | nicht-destruktive Integrationstests |
| Schreibende/destruktive Operationen | Nein | `-WhatIf`/`SupportsShouldProcess` + explizite Freigabe; im Confidence-Block als „nicht live geschrieben" markieren |

Praxis: Public-Funktionen so schneiden, dass die Logik gegen **einen einzigen gemockten
Transport-Wrapper** (den HTTP-/Plattform-Einstiegspunkt) unit-testbar ist — der Netz-/
Schreibteil bleibt den Integrationstests vorbehalten.

### 8.6 Charakterisierungstests: Diskriminierung per Mutationsprüfung

Tests, die bestehendes Verhalten festschreiben (Charakterisierungstests), sind beim ersten Lauf
zwangsläufig grün — die Regel aus 8.1/8.2 (behaviorales Rot) greift dort nicht. Projektpraxis:
die Diskriminierung stattdessen per **Mutationsprüfung** belegen. Dazu in einer **Kopie** des
Moduls (nie im Arbeitsstand) gezielt je eine Verhaltensänderung einbauen, die Tests gegen die
Kopie laufen lassen und festhalten, welcher Test rot wird. Jede Mutation muss von mindestens
einem Test erkannt werden; eine überlebende Mutation zeigt eine Testlücke.

Angewendet in I3 auf `SQLSyncCommon.psm1` mit 13 Mutationen, alle erkannt: u. a. Typmapping,
Strategiewahl, Passwort-Maskierung (Firebird und SQL Server), `Get-ConfigValue` mit `false`,
`Close-DatabaseConnection` ohne Dispose, Default `GlobalTimeout`, ignorierte Integrated Security,
Farbe in `Write-SyncStatus`, Escaping in `Protect-SqlString`, entfernter Admin-Check, entfernte
`Tables`-Validierung, ignoriertes `CredentialTarget`.

Angewendet in I9 auf `Setup-ScheduledTasks.ps1` mit 8 Mutationen (in einer Kopie, nie im
Arbeitsstand), alle erkannt. Ein echter Registrierungslauf mit Adminrechten ersetzt das nicht.
