# Coding Conventions – PSFirebirdToMSSQL

Stack: PowerShell 7.0+ (`#Requires -Version 7.0`) | keine PowerShell-Galerie-Module; .NET-Treiber
`FirebirdSql.Data.FirebirdClient` 10.3.4 + `System.Data.SqlClient` (in PS 7 enthalten) | Windows
(Credential Manager, Task Scheduler; keine Mindestversion im Code festgelegt)

Diese Datei beschreibt die Konventionen, die **im Code tatsächlich gelebt werden**, plus die Regeln
für neuen Code. Abweichungen des Bestands sind ausdrücklich markiert („Bestand weicht ab") und im
Inkrementplan (`docs/TODO.md`) eingeplant.

---

## 1. Git & Versionierung

- Conventional Commits: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`
- Scope = Inkrement-ID oder Datei/Modul: `fix(I2): exit-code-bei-tabellenfehler`, `refactor(SQLSyncCommon): typmapping`
- Commit-Texte auf Deutsch sind erlaubt (Bestand: `fix: Passwort nicht mehr in der Kommandozeile, …`).
  Ältere Commits (`added disclaimer`, `fixed format string bug`) folgen dem Schema noch nicht — kein Rewrite der Historie.
- `git add` nur für explizit bearbeitete Dateien – niemals `git add .`
  (im Root liegen lokal `config.json` und `config.json.*.bak`, die Klartext-Passwörter enthalten können; sie sind per `.gitignore` ausgeschlossen).
- Inkremente enden mit Commit, sofern Git verfügbar ist und der Prompter Commits nicht ausdrücklich untersagt hat.
- Versionsangaben stehen im Comment-based Help (`.NOTES Version: 2.10` im Sync-Skript, `Version: 1.0.0` im Modul)
  und werden bei funktionalen Änderungen mitgezogen.

## 2. PowerShell Code-Richtlinien

### 2.1 Grundgerüst jedes Skripts

```powershell
#Requires -Version 7.0

<# .SYNOPSIS / .DESCRIPTION / .PARAMETER / .NOTES (Deutsch) #>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

$ScriptDir  = $PSScriptRoot
$ModulePath = Join-Path $ScriptDir "SQLSyncCommon.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Error "KRITISCH: SQLSyncCommon.psm1 nicht gefunden in $ScriptDir"
    exit 1
}
Import-Module $ModulePath -Force
```

- `#Requires -Version 7.0` steht in **jedem** Skript (Grund: `ForEach-Object -Parallel`, ternärer Operator `? :`, `Test-Json`).
  Skripte, die Admin brauchen, prüfen die Rechte zur Laufzeit (Exit 1) statt per `#Requires -RunAsAdministrator`,
  damit eine `-WhatIf`-Vorschau ohne Admin möglich bleibt (Vorbild: `Setup-ScheduledTasks.ps1`).
- Modul-Import immer über `Join-Path $PSScriptRoot` (bzw. `$ScriptDir`), nie relativ zum aktuellen Arbeitsverzeichnis —
  Skripte werden vom Task Scheduler mit beliebigem CWD gestartet.
- Comment-based Help auf Deutsch, mit `.LINK` auf das GitHub-Repo.

### 2.2 Benennung

- **Funktionen:** `Verb-Noun` mit genehmigten Verben
  ([Liste](https://docs.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)).
  Bestand in `SQLSyncCommon.psm1`: `Get-`, `Resolve-`, `New-`, `Initialize-`, `Close-`, `Write-`, `ConvertTo-`, `Protect-`.
- **Variablen:** PascalCase (`$ConfigPath`, `$FbConn`, `$SqlConn`, `$TargetTableName`, `$SyncStrategy`).
  Fachbegriffe dürfen deutsch sein (`$Tabelle`, `$Tabellen`) — innerhalb einer Funktion konsistent bleiben.
- **Abkürzungen:** `Fb` = Firebird, `Sql` = MS SQL Server, `Stg`/`STG_` = Staging, `CS` = Connection String.
- **Skriptdateien:** Bestand ist gemischt (`Sync_Firebird_MSSQL_AutoSchema.ps1`, `Setup_Credentials.ps1` mit Unterstrich vs.
  `Test-SQLSyncConnections.ps1`, `Setup-ScheduledTasks.ps1` mit Bindestrich). **Neue** Skripte: `Verb-Noun.ps1` mit Bindestrich.
  Bestehende Dateien werden **nicht** umbenannt (Task-Scheduler-Aufrufe und READMEs referenzieren die Namen).
- **Credential-Targets:** Präfix `SQLSync_` (`SQLSync_Firebird`, `SQLSync_MSSQL`).
- **SQL-Objekte:** Staging-Tabelle `STG_<Quelltabelle>`, Zieltabelle `<Prefix><Quelltabelle><Suffix>`,
  Primärschlüssel `PK_<Tabellenname>`, Stored Procedure `dbo.sp_Merge_Generic`. Begriffe siehe `docs/GLOSSARY.md`.

### 2.3 Funktionen im Modul

- **CmdletBinding + Param:** Jede exportierte Funktion mit `[CmdletBinding()]` und `param()`-Block,
  Pflichtparameter mit `[Parameter(Mandatory)]`.
  *Bestand weicht ab:* `Get-ConfigValue` und `Protect-SqlString` haben kein `[CmdletBinding()]`.
- **Export explizit:** `Export-ModuleMember -Function @(...)` am Modulende ist eine **explizite Liste** (kein `'*'`).
  Es gibt kein Manifest (`.psd1`); kommt eins hinzu, gilt dort `FunctionsToExport` ebenfalls explizit.
  *Bestand:* `Invoke-WithFirebirdConnection` / `Invoke-WithMSSQLConnection` sind definiert, aber bewusst **nicht** exportiert
  (Kommentar im Modul: `$using:` funktioniert in normalen ScriptBlocks nicht).
- **Rückgabe:** Hashtables (`@{ Username = …; Password = …; Source = … }`) bzw. `PSCustomObject` — keine Ausgabe-Nebenprodukte.
  Wertrückgebende Aufrufe nur zur Seitenwirkung mit `[void]`/`$null =`/`| Out-Null` verwerfen
  (Bestand: `[void]$Cmd.ExecuteNonQuery()`, `New-Item … | Out-Null`). Sonst leckt die Rückgabe in den Output-Stream
  und z. B. in das Ergebnisobjekt der Parallel-Schleife.

### 2.4 Benutzerausgaben & Logging

- Ausgaben sind **deutsch** und laufen über `Write-Host` mit festen Farben; `Start-Transcript` im Sync-Skript schreibt sie
  nach `Logs\Sync_<ConfigName>_<yyyy-MM-dd_HHmm>.log`. Das ist eine bewusste Projektentscheidung (kein `Write-Log`/PSFramework).

  | Farbe | Bedeutung | Beispiel |
  |---|---|---|
  | `Green` | OK / Erfolg | `OK: Datenbank '…' ist vorhanden.` |
  | `Yellow` | Warnung, Retry, unsicherer Fallback | `[Credentials] Firebird: config.json (WARNUNG: unsicher!)` |
  | `Red` | Fehler je Tabelle | `[<Tabelle>] ERROR (Versuch n): …` |
  | `Cyan` | Info / Phasenstart | `Führe Pre-Flight Checks durch...` |
  | `Magenta` | gefährlicher Schalter aktiv | `WARNUNG: ForceFullSync ist AKTIViert …` |
  | `Gray` / `DarkGray` | Details, Treiberpfad | `[Driver] Firebird .NET Provider geladen: …` |

- Präfix in Klammern für die Quelle der Meldung: `[<Tabelle>]`, `[Credentials]`, `[Driver]`.
- Fatale Fehler an der Skriptgrenze: `Write-Error "KRITISCH: …"` (siehe `docs/architecture/ERROR_HANDLING.md`).
- `Write-Verbose` für Debug-Ausgaben in neuem Code (aktivierbar mit `-Verbose`).
- **Niemals** Passwörter oder vollständige Connection Strings ausgeben. Verbindungsinfos nur als
  `Server=…;Database=…;Port=…` ohne Credentials (Bestand im Sync-Skript, Abschnitt 6).

### 2.5 Fehlerbehandlung (Kurzfassung)

- Es gibt **kein** globales `$ErrorActionPreference = 'Stop'`. Stattdessen `-ErrorAction Stop` an den kritischen Cmdlets
  (`Get-Content`, `ConvertFrom-Json`, `Invoke-WebRequest`) und `try/catch` um alle .NET-Datenbankaufrufe
  (die ohnehin terminierende Exceptions werfen). Neuer Code hält das bei.
- Modulfunktionen `throw`en mit deutscher, handlungsleitender Meldung (`"… Führe Setup_Credentials.ps1 aus."`).
- Skripte fangen an der Grenze und beenden mit dokumentiertem Exit-Code.
- Kein leeres `catch { }` ohne Kommentar. Erlaubte Ausnahme: `try { $Conn.Close() } catch { }` im Cleanup.
  *Bestand weicht ab:* verschluckte Fehler bei PK-/Index-Anlage im Sync-Skript — siehe `ERROR_HANDLING.md`.

### 2.6 Ressourcen: Verbindungen immer in `finally` schließen

```powershell
$FbConn = $null
try {
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
    $FbConn.Open()
    # ...
}
finally {
    if ($FbConn) {
        try { $FbConn.Close() } catch { }
        try { $FbConn.Dispose() } catch { }
    }
}
```

- Außerhalb von `ForEach-Object -Parallel` alternativ `Close-DatabaseConnection -Connection $Conn` aus dem Modul.
- Innerhalb `-Parallel`: Modulfunktionen per `Import-Module $using:ModulePath` laden (Runspaces erben das Modul
  nicht) statt Logik zu kopieren; Werte nur über `$using:` hereinholen, Verbindungen pro Versuch (Retry) neu öffnen und im
  `finally` schließen; Verbindungsvariablen **vor** jedem Versuch auf `$null` setzen.
- `SqlBulkCopy`, `DataReader` und Commands, die eigene Ressourcen halten, ebenfalls schließen bzw. disposen.

### 2.7 SQL im Code

- **Firebird-Here-Strings mit `RDB$` immer literal** (`@' … '@`) und Werte per `-f` einsetzen — in einem
  expandierenden Here-String (`@" … "@`) würde PowerShell `$RELATION_NAME` als Variable auflösen:
  ```powershell
  $Cmd.CommandText = @'
      SELECT TRIM(REL.RDB$RELATION_NAME) FROM RDB$RELATIONS REL
      WHERE REL.RDB$SYSTEM_FLAG = 0 AND REL.RDB$VIEW_BLR IS NULL
        AND EXISTS (... = '{0}')
  '@ -f $IdColumn
  ```
  Achtung: geschweifte Klammern im SQL müssen bei `-f` verdoppelt werden (`{{`/`}}`).
- **Werte** (Datum, Zahlen, Strings) immer als Parameter (`FbParameter` / `SqlParameter`), nie interpoliert
  (Bestand: Wasserzeichen `@LastDate` im inkrementellen Extrakt). `Protect-SqlString` ist nur Notlösung.
- **Bezeichner** (Tabellen-/Spaltennamen) kommen aus der Konfiguration bzw. aus Firebird-Metadaten und lassen
  sich in DDL/DML nicht parametrisieren. Regel (seit I4, beide Teile Pflicht):
  1. **Nur nach Allow-List:** Jeder Name aus der Konfiguration wird vor der Verwendung mit `Assert-SqlIdentifier`
     (`^[A-Za-z0-9_$]+$`, max. 63 Zeichen) geprüft – zentral in `Get-SQLSyncConfig`; neue Konfigfelder mit Namen
     dort ergänzen. Ein Verstoß wirft (Fail-Fast), nie still korrigieren.
  2. **Immer quoten:** Firebird in `"…"`, SQL Server in `[…]` (auch Temp-Tabellen `[#…]` und `DestinationTableName`
     von `SqlBulkCopy`), in dynamischem T-SQL `QUOTENAME()`. Namen, die nicht durch die Allow-List gelaufen sind
     (z. B. Spaltennamen aus Firebird-Metadaten), zusätzlich escapen (`]` → `]]`). Klammern allein sind keine
     Absicherung.
- **Metadaten-Abfragen parametrisieren:** Wo ein Name als **Wert** gebraucht wird (`INFORMATION_SCHEMA`,
  `sys.indexes`, `OBJECT_ID`), als `SqlParameter` übergeben (`@TableName`, `@ColumnName`, `@IndexName`;
  `OBJECT_ID(QUOTENAME(@TableName))`), nie als String-Literal interpolieren. Stored Procedures mit
  `CommandType = StoredProcedure` und Parametern aufrufen (Bestand: `sp_Merge_Generic`; fehlender Wert als
  `DBNull.Value`).
- **Connection Strings** ausschließlich über `New-FirebirdConnectionString` / `New-MSSQLConnectionString`
  (`DbConnectionStringBuilder` maskiert `; = ' "`), nie per String-Konkatenation.
  *Bestand weicht ab:* der Integrated-Security-Zweig von `New-MSSQLConnectionString` konkateniert noch.
- `CommandTimeout = GlobalTimeout` an jedem SQL-Server-Command setzen.

### 2.8 JSON

- Konfiguration lesen mit `Get-Content -Raw | ConvertFrom-Json`, schreiben mit `ConvertTo-Json -Depth 10`
  (Bestand: `Manage_Config_Tables.ps1`), nie per String-Konkatenation.
- Vor dem Überschreiben einer Konfigdatei Backup `<datei>.<yyyyMMdd_HHmmss>.bak` anlegen (Bestand); `.bak` ist gitignored.

## 3. Dateiorganisation

- **Flaches Layout:** alle Skripte und das Modul liegen im Repo-Root (siehe `docs/architecture/PROJECT_LAYOUT.md`).
- **Einstiegspunkte:** je ein Skript pro Aufgabe (Sync, Setup, Diagnose, Pflege). Das Sync-Skript ist sequenziell in
  nummerierte Abschnitte gegliedert (`# 1. INITIALISIERUNG …` bis `# 10. LOG ROTATION`) — neue Phasen fügen sich in diese
  Nummerierung ein.
- **Gemeinsame Logik** gehört in `SQLSyncCommon.psm1`, sobald sie von mehr als einem Skript gebraucht wird
  (z. B. Configpfad-Auflösung `Resolve-SQLSyncConfigPath`, Laden und Prüfen `Get-SQLSyncConfig`).
- Regionen im Modul mit `#region <Thema>` / `#endregion` (Credential Manager, Credentials Resolution, Connection Strings,
  Firebird Driver, Safe Database Operations, …).
- Konfiguration als JSON im Root; `config.sample.json` und `config.schema.json` sind versioniert, alle anderen `config*`
  sind per `.gitignore` (verankert mit `/config*`) ausgeschlossen.
- Jedes Einstiegsskript, das eine Konfig liest, nimmt `-ConfigFile` (aufgelöst mit `Resolve-SQLSyncConfigPath`) und lädt
  über `Get-SQLSyncConfig -SchemaPath (Join-Path $ScriptDir 'config.schema.json')`; Verstoß → Exit 2.
- **Neue Konfigschlüssel immer auch in `config.schema.json` ergänzen** (Typ, Grenzen, Beschreibung). Das Schema hat
  `additionalProperties: false`: ein Schlüssel, der nur in Code und Sample steht, lässt jede Konfig, die ihn nutzt,
  mit Exit 2 scheitern.

## 4. Prozessweite Side-Effects — Save/Restore-Pflicht

PowerShell-Skripte/Module mutieren häufig **prozessweite** Zustände, die die gesamte Session überleben.
Bestand in diesem Projekt:

| Stelle | Mutation | Status |
|---|---|---|
| `Initialize-FirebirdDriver` | `[Net.ServicePointManager]::SecurityProtocol = Tls12` vor dem NuGet-Download | erfüllt: alter Wert in `$PreviousProtocol` gesichert, im `finally` des Download-Blocks wiederhergestellt (seit I7) |
| `Get-StoredCredential` | `Add-Type` für `CredManager.Util` | durch Typ-Existenz-Check (`'CredManager.Util' -as [type]`) gegen Doppel-Laden geschützt |
| `Initialize-FirebirdDriver` | `Add-Type -Path <DLL>` | durch Assembly-Check (`[AppDomain]::CurrentDomain.GetAssemblies()`) geschützt; nicht entladbar |
| Sync-Skript | `Start-Transcript` | muss auf **jedem** Exit-Pfad mit `Stop-Transcript` beendet werden (Bestand: ja, vor jedem `exit`) |

**Pflicht-Pattern für neue Mutationen** (TLS, `$env:`, Registry, `Set-Location`, Preference-Variablen):
alten Wert einmalig in einem `$script:`-Slot sichern, im `finally`/Teardown restaurieren, Flag-Guard gegen Mehrfachsicherung.

```powershell
if (-not $script:__OldProtocol_saved) {
    $script:__OldProtocol = [Net.ServicePointManager]::SecurityProtocol
    $script:__OldProtocol_saved = $true
}
try { <# Mutation + Arbeit #> }
finally {
    if ($script:__OldProtocol_saved) {
        [Net.ServicePointManager]::SecurityProtocol = $script:__OldProtocol
        $script:__OldProtocol_saved = $false
    }
}
```

`Set-Location` nur mit `Push-Location`/`Pop-Location`; besser gar nicht (Pfade über `$PSScriptRoot`).

## 5. Pfade & Dateisystem

- **Pfade immer mit `Join-Path`** oder `[System.IO.Path]`-Methoden — nie String-Konkatenation mit `\`.
  *Bestand weicht ab:* `"$env:ProgramData\SQLSync\Drivers\…"` in `Initialize-FirebirdDriver`.
- **Basis ist `$PSScriptRoot`**, nicht das CWD (Logs, Modul, `config.json`, `sql_server_setup.sql`).
- **Existenz prüfen vor Zugriff:** `Test-Path` vor Modul-Import, Konfig-Laden, `sql_server_setup.sql` und DLL-Laden (Bestand).
- **Keine hart codierten Umgebungspfade.** Installationsordner und Konfignamen als Parameter mit Default
  `$PSScriptRoot` (Vorbild: `Setup-ScheduledTasks.ps1 -InstallDir/-DailyConfigFile/-WeeklyConfigFile`).
- **Credentials niemals über `$env:`** — nur Windows Credential Manager (siehe `docs/architecture/CREDENTIAL_STRATEGY.md`).

## 6. Security-Checkliste vor jedem Commit

- [ ] Keine Hardcoded-Credentials; keine echten Server-/Datenbanknamen oder Zugangsdaten in `config.sample.json`, READMEs oder Skripten
- [ ] Keine Firmeninterna in `docs/`, READMEs oder Commit-Message (Abschnitt 6.2); Hook aktiv (`git config core.hooksPath` = `tools/git-hooks`)
- [ ] `config.json`, `config*.json` (außer Sample/Schema) und `*.bak` bleiben ungetrackt (`git status` prüfen)
- [ ] Kein `Invoke-Expression`; keine Interpolation von Werten in SQL (Parameter verwenden)
- [ ] Neue SQL-Bezeichner aus der Konfiguration in `"…"` (Firebird) bzw. `[…]`/`QUOTENAME` (SQL Server)
- [ ] `-ExecutionPolicy Bypass` nur im Task-Scheduler-Aufruf (`Setup-ScheduledTasks.ps1`) — nie im Quellcode
- [ ] Keine Passwörter / Connection Strings in `Write-Host`, `Write-Error` oder Exception-Messages (Transcript landet in `Logs\`)
- [ ] Treiber-Versionswechsel: `$PackageVersion`, `$DownloadUrl` **und beide** Hashes in `$KnownSha256` (`lib\net8.0`, `lib\netstandard2.1`; selbst aus dem offiziellen NuGet-Paket berechnet) in `Initialize-FirebirdDriver` gemeinsam ändern; Unit-Tests mit den Hashes anpassen; nie einen Hash aus einer Fehlermeldung übernehmen
- [ ] Neue DLL-Ladewege (`Add-Type -Path`) nur nach SHA-256-Prüfung
- [ ] Prozessweite State-Mutationen haben Save/Restore (Sektion 4)
- [ ] `Export-ModuleMember` bleibt eine **explizite Liste**

### 6.1 Sicherheits-Patterns

- **Defense-in-Depth für Konfig-Credentials:** (1) `.gitignore` mit `/config*`, `!/config.sample.json`,
  `!/config.schema.json`, `*.bak` (vorhanden); (2) Laufzeit: Klartext-Fallback aus `config.json` erzeugt eine gelbe
  Warnung (vorhanden); (3) Regressionstest `git ls-files 'config.json'` muss leer sein — noch nicht als Pester-Test umgesetzt (Pester-Harness seit I3 vorhanden).
- **`-Force`-Pattern für gefährliche Schalter:** trifft derzeit nicht zu — gefährliche Optionen (`ForceFullSync`,
  `RecreateStagingTable`, `CleanupOrphans`) sind Konfigwerte, keine Cmdlet-Schalter. Sie werden beim Start farbig
  angekündigt (`Magenta`/`Yellow`).
- **Newline-Validierung für Single-Command-APIs:** trifft nicht zu (keine Kommando-Schnittstelle).

### 6.2 Öffentliches Repository — Interna trennen

Das Repository ist öffentlich (GitHub). **Alles, was committet wird — Code, `docs/`, READMEs und
Commit-Messages — ist öffentlich.** Secrets stehen ohnehin nie im Repo (Abschnitt 6); zusätzlich gilt:

- **Keine Firmeninterna in öffentlichen Dateien:** keine internen Hostnamen, IP-Adressen,
  Domänen-/Benutzernamen, Serverpfade, internen Datenbank-/Tabellenpräfixe, Firmen-/Kundennamen,
  und **nie die Schwachstellen-Betroffenheit eines konkreten internen Hosts** (z. B. „Server X läuft
  Version Y, betroffen von CVE Z").
- **Öffentliche Docs** verwenden Rollen statt Hosts: „Firebird-Testserver", „SQL-Testserver",
  „SQL-Produktivserver", „Demo-Datenbank". Beispielwerte sind eindeutig fiktiv (`SQLSERVER01`,
  `sqltest`, `DEIN_PASSWORT`).
- **Interna** gehören nach `docs/local/` (gitignored), z. B. `docs/local/ENVIRONMENT.md` mit Hosts,
  Versionen, Test-Artefakten. Öffentliche Docs verweisen nur darauf.
- **Automatische Sperre:** `tools/git-hooks/pre-commit` und `commit-msg` blocken Commits, deren
  hinzugefügte Zeilen, Dateinamen oder Commit-Message einen Begriff aus `.internal-terms`
  (Repo-Root, gitignored, ein Begriff pro Zeile) enthalten. Einmalig pro Klon aktivieren:
  `git config core.hooksPath tools/git-hooks`. Neue interne Begriffe sofort in `.internal-terms`
  ergänzen. Fehlt die Datei, warnt der Hook nur.
- Der Hook prüft nur **neue** Zeilen; die bis dahin öffentlichen Altlasten sind mit I9 bereinigt.
  Vor dem **ersten Push** eines Branches zusätzlich die gesamte Branch-History prüfen
  (`git log -p origin/main..HEAD`), da frühere lokale Commits ohne Hook entstanden sein können.

---

## 10. REST API Clients / HATEOAS

Trifft nicht zu — das Projekt spricht keine REST-APIs an. Einzige HTTP-Verbindung ist der einmalige NuGet-Download
des Firebird-Treibers (siehe `docs/architecture/DEPENDENCIES.md`).

---

## 7. Autonomes Arbeiten & Fehlerbehebung

- Bei Fehlern: nicht sofort abbrechen. `$Error[0]`, `$_.Exception.Message` und `$_.ScriptStackTrace` lesen.
- Lokal reproduzieren mit `Test-SQLSyncConnections.ps1` (Verbindungen, SP-Existenz) bevor das Sync-Skript geändert wird.
- Nur Dateien verändern, die für das aktuelle Inkrement relevant sind.
- `config.json` und `*.bak` niemals lesen oder ausgeben (können Klartext-Passwörter enthalten); für Beispiele `config.sample.json` nutzen.
- Am Ende jedes Inkrements: `docs/TODO.md`, `docs/CHANGELOG.md`, `docs/STATE.md` aktualisieren.

---

## 8. Dokumentationspflichten (Trigger-Regeln)

### Neuer Parameter / Konfigurationsschlüssel
→ `README.md` + `README.de.md` + `config.sample.json` + `config.schema.json` (Pflicht, sonst Exit 2) + `docs/architecture/CONFIGURATION.md`
+ `docs/features/firebird-mssql-sync.md`; Default in `Get-SQLSyncConfig` eintragen.

### Neuer / geänderter Exit-Code
→ `docs/architecture/ERROR_HANDLING.md` + `docs/operations/TASK_SCHEDULER.md`

### Änderung an `sp_Merge_Generic`
→ `sql_server_setup.sql` + Parameterzahl-Prüfung im Pre-Flight des Sync-Skripts + ADR, falls sich Semantik ändert

### Neue externe Abhängigkeit (Modul, Binary, API)
→ `docs/architecture/DEPENDENCIES.md`

### STATE.md (immer nach jedem Inkrement)
1. Freitext "Letztes abgeschlossenes Inkrement: …"
2. Tabelle: neue Zeile `| I# | Titel | Datum | Commit-Hash |`

---

## 9. Quality Gates — pre-commit (Definition of Done)

Für PowerShell greifen zwei der vier Gates der Definition of Done:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning   # Gate 1 — Linter (PSScriptAnalyzer)
pwsh -NoProfile -File .\tests\pester.config.ps1           # Gate 4 — Unit-Tests (Pester 5.7.1) + Coverage
```

**Stand 2026-10-08:** Keine PSScriptAnalyzer-Settings und keine CI; Gate 1 wird manuell ausgeführt.
Gate 4 ist seit I3 vorhanden: `tests/pester.config.ps1` lädt das in `tests/RequiredModules.psd1`
gepinnte Pester 5.7.1, führt die 98 Tests unter `tests/Unit/` aus und endet mit Exit-Code 1 bei einem
roten Test oder einer Coverage von `SQLSyncCommon.psm1` unter 80 % (gemessen 84,42 %, Stand I5). Schneller Lauf
ohne Coverage: `Invoke-Pester ./tests`. Details in `docs/testing/UNIT_TESTS.md`. Die Einstiegsskripte
sind nicht unit-getestet; für sie bleibt als Minimal-Gate: `Test-SQLSyncConnections.ps1` gegen eine
Testumgebung liefert Exit-Code 0.

Gate 2 (Formatter) und Gate 3 (statische Typanalyse) haben in PowerShell kein eigenständiges Standard-Werkzeug;
PSScriptAnalyzer-Regeln decken Stilfragen mit ab.
