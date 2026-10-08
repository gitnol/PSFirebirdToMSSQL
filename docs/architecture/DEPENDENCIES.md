# Externe Abhängigkeiten – PSFirebirdToMSSQL

Jede Abhängigkeit, die explizit installiert, geladen oder aufgerufen wird. Stand: 2026-10-08.

---

## PSGallery-Module (Install-Module)

Keine. Das Projekt nutzt bewusst keine Module aus der PowerShell-Galerie; alles Benötigte kommt aus PowerShell 7,
.NET und Windows bzw. aus dem einmalig heruntergeladenen Firebird-Treiber.

Nur Entwicklung, nicht Laufzeit: `Pester` 5.7.1 für die Unit-Tests unter `tests/Unit/`, gepinnt in
`tests/RequiredModules.psd1` und von `tests/pester.config.ps1` per `Import-Module -RequiredVersion` geladen,
und — geplant — `PSScriptAnalyzer` für Gate 1. Installation mit `-Scope CurrentUser` auf Entwicklerrechnern
(Befehl in `docs/testing/UNIT_TESTS.md`); auf dem Betriebsserver nicht nötig.

---

## .NET-Bibliotheken

| Bibliothek | Version | Herkunft | Zweck | Risiko bei Ausfall |
|---|---|---|---|---|
| `FirebirdSql.Data.FirebirdClient` | 10.3.4 (`lib\net8.0`) | NuGet-Paket, von `Initialize-FirebirdDriver` heruntergeladen nach `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\` | ADO.NET-Provider für Firebird (`FbConnection`, `FbCommand`, `FbDataReader`) | kein Zugriff auf die Quelle — Sync-Exit-Code 7 |
| `System.Data.SqlClient` | in PowerShell 7 enthalten | PowerShell-Installation | Verbindung zu SQL Server, `SqlBulkCopy` | kein Zugriff auf das Ziel. Von Microsoft abgekündigt zugunsten `Microsoft.Data.SqlClient` (Backlog: Migration) |
| `System.Data.Common.DbConnectionStringBuilder` | .NET | PowerShell-Installation | sicheres Bauen der Connection Strings | — |

**Treiber-Integrität:**

- Beim **Download** wird die DLL gegen SHA-256 `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05` geprüft;
  bei Abweichung wird der Ordner gelöscht und abgebrochen (seit Commit 721d5e0).
- Eine über `Firebird.DllPath` konfigurierte oder bereits in `%ProgramData%` liegende DLL wird **ohne** Hash-Prüfung
  per `Add-Type` geladen (Inkrement I7). Schreibrechte auf diese Ordner daher auf Administratoren beschränken.
- Ist die Assembly in der Session bereits geladen, wird sie wiederverwendet (keine Versionsprüfung).

**Erstinstallation (einmalig, als Administrator):**

```powershell
# Lädt, prüft und entpackt den Treiber nach %ProgramData%\SQLSync\Drivers\...
pwsh -NoProfile -File .\Test-SQLSyncConnections.ps1
# Prüfen
Get-ChildItem "$env:ProgramData\SQLSync\Drivers" -Recurse -Filter FirebirdSql.Data.FirebirdClient.dll
```

Offline-Server: NuGet-Paket 10.3.4 auf einem anderen Rechner beziehen, `lib\net8.0\FirebirdSql.Data.FirebirdClient.dll`
in den obigen Ordner kopieren und den SHA-256 manuell mit `Get-FileHash` vergleichen.

---

## Windows-Systemkomponenten (kein Install-Module nötig)

| Komponente | Zweck | Verwendet in |
|---|---|---|
| `advapi32.dll` (`CredRead`, `CredWrite`, `CredFree`) via `Add-Type` | Windows Credential Manager lesen/schreiben | `SQLSyncCommon.psm1` (`Get-StoredCredential`), `Setup_Credentials.ps1` |
| Modul `ScheduledTasks` (`Register-ScheduledTask`, `New-ScheduledTaskTrigger`, …) | Tasks anlegen | `Setup-ScheduledTasks.ps1` |
| `Out-GridView` | Tabellenauswahl | `Manage_Config_Tables.ps1` (benötigt Desktop-Sitzung; in PS 7 auf Windows verfügbar) |
| `Test-Json` | JSON-Schema-Validierung | `Get-SQLSyncConfig -SchemaPath` (alle vier Einstiegsskripte; Parameter `-Schema` mit Schema-Inhalt statt `-SchemaFile`, in allen PS-7-Versionen vorhanden) |

---

## Externe Binaries

| Binary | Pfad | Zweck | Fehler-Verhalten |
|---|---|---|---|
| `cmdkey.exe` | `%SystemRoot%\System32` (über `PATH`) | Existenzprüfung von Credential-Manager-Einträgen (`cmdkey /list`) | fehlt praktisch nie; bei Fehler gilt der Eintrag als nicht vorhanden |
| `pwsh.exe` | Pfad des laufenden Prozesses (`(Get-Process -Id $PID).Path`) | Programm der Scheduled Tasks | `Setup-ScheduledTasks.ps1` bricht unter PS < 7 mit Exit 1 ab |

---

## Externe Services / Endpunkte

| Service | Endpunkt | Zweck | Verhalten bei Ausfall |
|---|---|---|---|
| Firebird-Server | `Firebird.Server`:`Firebird.Port` (Default 3050), Datenbankdatei `Firebird.Database` | Quelle (nur lesend) | Phasen 1–7: Test-Skript Exit 1; im Sync scheitert jede Tabelle (Retry, dann Status `Fehler`) |
| MS SQL Server | `MSSQL.Server`, Datenbank `MSSQL.Database` (+ `master` für Pre-Flight) | Ziel (Staging, Zieltabellen, Prozedur) | Pre-Flight-Abbruch mit Exit 9 |
| NuGet-CDN | `https://globalcdn.nuget.org/packages/firebirdsql.data.firebirdclient.10.3.4.nupkg` | einmaliger Treiber-Download | `throw "Download fehlgeschlagen …"` → Sync-Exit-Code 7; danach nicht mehr benötigt |

Credentials für Firebird/SQL Server: siehe `docs/architecture/CREDENTIAL_STRATEGY.md`.
Verbindungen sind derzeit **nicht** explizit verschlüsselt konfiguriert (kein `Encrypt`/`WireCrypt` im Connection String;
es gelten Treiber-/Server-Defaults) — offen, siehe `docs/security/THREAT_MODEL.md`.

---

## Systemabhängigkeiten

| Ressource | Mindestversion / Pfad | Zweck |
|---|---|---|
| Windows | keine Mindestversion im Code festgelegt; Credential Manager + Task Scheduler erforderlich | advapi32-Credential-API, Scheduled Tasks |
| PowerShell | ≥ 7.0 (`#Requires -Version 7.0`) | `ForEach-Object -Parallel`, ternärer Operator, `Test-Json`; Treiber `net8.0` setzt eine PS-7-Version auf .NET 8 voraus (PS 7.4+) |
| Firebird-Server | nicht festgelegt (vom Code nicht geprüft; Mindestversion ergibt sich aus der Treiber-Kompatibilität von FirebirdClient 10.x — offen) | Quelle |
| MS SQL Server | 2017+ (`STRING_AGG`, `CREATE OR ALTER` in `sp_Merge_Generic`) | Ziel |
| Dateisystem | `%ProgramData%\SQLSync\Drivers\` | Treiberablage (Schreiben nur beim Erst-Download, Admin) |
| Dateisystem | `<Skriptordner>\Logs\` | Transcript-Logs (Schreibrecht für das Task-Konto) |

---

## Upgrade-Hinweise

- **FirebirdClient:** `$PackageVersion`, Download-URL und `$ExpectedSha256` in `Initialize-FirebirdDriver` **gemeinsam** ändern;
  neuer Zielordner entsteht automatisch (versionierter Pfad). Typzuordnung (`GetSchemaTable().DataType`) nach Upgrade mit
  `Get_Firebird_Schema.ps1` gegenprüfen; bei Major-Versionen kann sich das minimale .NET-Target ändern.
- **System.Data.SqlClient → Microsoft.Data.SqlClient:** Namespace und Default `Encrypt=True` (ab 4.0) ändern sich —
  Connection-String-Builder und Zertifikatsvertrauen prüfen (Backlog).
- **PowerShell:** Bei Wechsel der PS-7-Version prüfen, ob die enthaltene .NET-Runtime zur Treiber-DLL (`net8.0`) passt.
- **SQL Server:** `sp_Merge_Generic` nutzt `STRING_AGG` (2017+); ältere Versionen werden nicht unterstützt.
- **Windows:** keine versionsgebundenen Features bekannt.
