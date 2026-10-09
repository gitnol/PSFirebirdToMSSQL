# Dependency-Audit – PSFirebirdToMSSQL

Wann und wie Abhängigkeiten auf bekannte Schwachstellen geprüft werden.
Verbindet sich mit `architecture/DEPENDENCIES.md` (Was ist drin?) und
`security/THREAT_MODEL.md` (Bedrohung 3: Treiber-Supply-Chain).

---

## Bestand (Stand 2026-10-09)

| Abhängigkeit | Version / Fundort | Quelle | Bemerkung |
|---|---|---|---|
| PowerShell | ≥ 7.0 (`#Requires -Version 7.0`); auf dem Entwicklungsrechner 7.6.6 gemessen | Microsoft (MSI/winget) | Produktiver Sync-Host: Version dort mit `$PSVersionTable` erfassen (offen) |
| .NET Runtime | durch PowerShell 7 mitgeliefert | Microsoft | Treiber nutzt `lib\net8.0` → PowerShell-Version mit .NET ≥ 8 nötig |
| FirebirdSql.Data.FirebirdClient | 10.3.4; SHA-256 `lib\net8.0` `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05`, `lib\netstandard2.1` `8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A` | NuGet, Download in `Initialize-FirebirdDriver` (`SQLSyncCommon.psm1`) nach `%ProgramData%\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\` | Version, URL + beide Hashes fest im Code, zentral in `$script:FirebirdDriver`; seit I7 wird **jede** DLL vor dem Laden geprüft (Download, vorhanden, `DllPath`), Abweichung → Exit 7. Andere Version nur mit `Firebird.DllSha256` |
| System.Data.SqlClient | in PowerShell 7 enthalten (auf dem Entwicklungsrechner Assembly-Version 4.6.1.6) | Microsoft | **Von Microsoft abgekündigt** zugunsten `Microsoft.Data.SqlClient`; nur noch Sicherheitsfixes, kein Feature-Support. Migration im Backlog |
| Windows-APIs | `advapi32.dll` `CredRead`/`CredWrite`/`CredFree` per `Add-Type`-C#; `cmdkey.exe`; Task Scheduler (ScheduledTasks-Modul); `Out-GridView` | Betriebssystem | Patchstand über Windows Update |
| Firebird-Server | 2.5+ / 3.x laut README; eingesetzte Versionen je Host: nur in `docs/local/ENVIRONMENT.md` (nicht öffentlich), mit `Test-SQLSyncConnections.ps1 -PreDeploy` auslesen und gegen die bekannten Advisories abgleichen | Betreiber | **Versionen < 5.0.4 / < 4.0.7 / < 3.0.14 sind von CVE-2026-34232 (DoS) und CVE-2026-40342 (CVSS 9.9, Codeausführung über `CREATE FUNCTION` / `ENGINE`-Path-Traversal) betroffen** (siehe Sweep-Protokoll) → Update auf ≥ 5.0.4 empfohlen (bzw. ≥ 4.0.7 / ≥ 3.0.14); für den Sync ein reines Lesekonto statt `SYSDBA`. Firebird 2.5 ist End-of-Life – falls im Einsatz, als Risiko führen |
| MS SQL Server | 2017+ nötig (`STRING_AGG`, `CREATE OR ALTER` in `sql_server_setup.sql`); Version mit `Test-SQLSyncConnections.ps1` auslesen | Betreiber | Support-Lebenszyklus der eingesetzten Version prüfen |

Zur Laufzeit keine Module aus der PowerShell Gallery, keine Python-/Node-/NuGet-Projektdateien.
Einzige Entwicklungsabhängigkeit ist Pester für `tests/Unit/`, gepinnt auf 5.7.1 in `tests/RequiredModules.psd1`
(nicht auf dem Betriebsserver nötig). Ein Versionswechsel erfolgt nur durch Änderung dieser Datei.

---

## Server-Advisories im Code

Bekannte Schwachstellen des **Firebird-Servers** sind im Modul als Liste
`$script:FirebirdServerAdvisories` (`SQLSyncCommon.psm1`) gepflegt: je Eintrag CVE-ID, CVSS,
Kurzbeschreibung und die erste behobene Version je Hauptversion. `Get-FirebirdServerAdvisory
-EngineVersion <Version>` liefert die Einträge, von denen eine Serverversion betroffen ist;
`Test-SQLSyncConnections.ps1 -PreDeploy` zeigt sie als `WARNUNG`. Regeln der Auswertung: Versionen
unter 3 gelten als betroffen, Hauptversionen über 5 als nicht betroffen, eine nicht auswertbare
Version ergibt einen Hinweis zur manuellen Prüfung.

Aktueller Inhalt:

| CVE | CVSS | Wirkung | Behoben ab |
|---|---|---|---|
| CVE-2026-34232 | 7.5 | unauthentifizierter Server-Absturz (`op_response`) | 3.0.14 / 4.0.7 / 5.0.4 |
| CVE-2026-40342 | 9.9 | Codeausführung über `CREATE FUNCTION` (`ENGINE`-Pfad) | 3.0.14 / 4.0.7 / 5.0.4 |

**Pflege:** Findet ein Sweep eine neue Server-CVE, wird sie in `$script:FirebirdServerAdvisories`
ergänzt (und mit einem Unit-Test für eine betroffene und eine behobene Version belegt), zusätzlich
im Sweep-Protokoll unten und in `THREAT_MODEL.md` Bedrohung 6. Die Liste ist nur so aktuell wie der
letzte Sweep; ein `OK` von `-PreDeploy` ersetzt den Sweep nicht.

---

## Sweep-Protokoll

### 2026-10-09 – Ereignis-Auslöser (I7, Treiber-Integrität)

| Prüfgegenstand | Ergebnis | Quelle |
|---|---|---|
| FirebirdSql.Data.FirebirdClient 10.3.4 | Weiterhin aktuelle stabile Version; kein Client-Advisory gefunden | https://www.nuget.org/packages/FirebirdSql.Data.FirebirdClient |
| Original-Hashes der Treiber-DLLs | Aus dem offiziellen Paket 10.3.4 von nuget.org nachgerechnet: `lib\net8.0` `7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05`, `lib\netstandard2.1` `8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A`. Beide sind die einzigen eingebauten zulässigen Werte in `Initialize-FirebirdDriver` | https://www.nuget.org/packages/FirebirdSql.Data.FirebirdClient |
| Firebird-Server | **Neuer Befund:** CVE-2026-40342 (CVSS 9.9) – ein authentifizierter Benutzer mit `CREATE FUNCTION` kann über einen präparierten `ENGINE`-Namen (Path Traversal) eine beliebige Bibliothek laden → Codeausführung als OS-Konto des Firebird-Servers; betroffen < 5.0.4 / < 4.0.7 / < 3.0.14. Bezug: Ist das Sync-Konto `SYSDBA` oder hat es `CREATE FUNCTION`, wird ein Credential-Leak zur Codeausführung auf dem ERP-Datenbankserver. Empfehlung: Server ≥ 5.0.4 (behebt auch CVE-2026-34232) und ein reines Lesekonto (nur `SELECT` auf die konfigurierten Tabellen, keine DDL/`CREATE FUNCTION`) statt `SYSDBA`. Bewertung: `THREAT_MODEL.md` Bedrohung 5 und 6 | https://nvd.nist.gov/vuln/detail/CVE-2026-40342 , https://osv.dev/vulnerability/CVE-2026-40342 |

Offen aus diesem Sweep: Server-Update (Schweregrad Critical) und Umstellung auf ein
Firebird-Lesekonto beim Betreiber anstoßen.

### 2026-10-08 – Ereignis-Auslöser (I4, SQL-Identifier-Härtung)

| Prüfgegenstand | Ergebnis | Quelle |
|---|---|---|
| Best Practice Identifier in dynamischem SQL (SQL Server) | Bestätigt: Allow-List **und** `QUOTENAME`/eckige Klammern; Klammern allein unzureichend. Umgesetzt in I4 (`Assert-SqlIdentifier`, Klammerung, Parameter) | https://www.sqlservercentral.com/articles/why-quotename-is-important , https://sqlstudies.com/2017/05/11/dynamic-sql-and-the-joys-of-quotename/ |
| Firebird-Bezeichner-Länge | Max. 63 Zeichen (UTF8) – als Grenze in `Assert-SqlIdentifier` übernommen | https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref50/fblangref50-structure-identifiers.html |
| Firebird-Server | **Neuer Befund:** CVE-2026-34232 (CVSS 7.5, GHSA-7jq3-6j3c-5cm2) – unauthentifizierter Server-Absturz (DoS) über präpariertes `op_response`-Paket; betroffen < 5.0.4 / < 4.0.7 / < 3.0.14. Betroffenheit einzelner Hosts nur in `docs/local/ENVIRONMENT.md`. Empfehlung: Update auf ≥ 5.0.4; bis dahin Firebird-Port per Firewall einschränken. Bewertung: `THREAT_MODEL.md` Bedrohung 6 | https://nvd.nist.gov/vuln/detail/cve-2026-34232 |
| FirebirdSql.Data.FirebirdClient 10.3.4 | Kein Treiber-/Client-CVE gefunden | GitHub Advisory Database, NVD |

Offen aus diesem Sweep: Version des produktiven ERP-Firebird erfassen; Server-Update beim Betreiber
anstoßen (Schweregrad High → innerhalb des aktuellen Inkrements klären).

---

## Wann auditieren

| Auslöser | Pflicht? |
|---|---|
| Vor jedem Release / Tag | Ja |
| Bei Änderung der Treiber-Version (`Version`, `DownloadUrl` und `KnownSha256` in `$script:FirebirdDriver`) oder bei Nutzung von `Firebird.DllSha256` | Ja, inkl. neuer Hashes aus offizieller Quelle |
| Nach Sicherheitsmeldung (CVE/Advisory) für PowerShell, .NET, SqlClient, FirebirdClient, Firebird- oder SQL-Server | Ja, sofort |
| Web-Advisory-/Best-Practice-Sweep für Base+Stack | Auf Zeit-Kadenz (Default 14 Tage, Marker im `STATE.md`-Kopf; nächster: 2026-10-22) + Pflicht vor Release — `principles/SECURITY_CURRENCY.md` |
| Regelmäßiger Sweep | Empfohlen: monatlich |

---

## Audit-Befehle (PowerShell-Stack)

| Prüfgegenstand | Befehl | Output | Bemerkung |
|---|---|---|---|
| PowerShell-Version | `$PSVersionTable.PSVersion` bzw. `pwsh -v` | Versionsnummer | Gegen aktuelle Releases/Advisories auf `github.com/PowerShell/PowerShell` abgleichen |
| .NET-Runtime | `[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription` | z. B. `.NET 9.0.x` | Gegen .NET-Security-Releases abgleichen |
| SqlClient | `[System.Data.SqlClient.SqlConnection].Assembly.GetName().Version` | Assembly-Version | Abkündigung beachten |
| Treiber-Integrität | `Get-FileHash "$env:ProgramData\SQLSync\Drivers\FirebirdSql.Data.FirebirdClient.10.3.4\lib\net8.0\FirebirdSql.Data.FirebirdClient.dll" -Algorithm SHA256` | Hash | Muss `7DB04371…CBC05` (`lib\net8.0`) bzw. `8176C7D5…A323A` (`lib\netstandard2.1`) entsprechen (volle Werte oben); der Sync prüft das seit I7 bei jedem Laden selbst, `Test-SQLSyncConnections.ps1 -PreDeploy` ohne zu laden – der Befehl dient der manuellen Gegenprobe |
| Treiber-Advisories | GitHub Advisory Database (`github.com/advisories?query=FirebirdSql.Data.FirebirdClient`) und NuGet-Paketseite (Hinweis „vulnerable" / „deprecated") | Advisory-Liste | Kein lokales Projekt → `dotnet list package --vulnerable` nicht anwendbar |
| Firebird-/MSSQL-Serverversion | `.\Test-SQLSyncConnections.ps1 -ConfigFile <Konfig> -PreDeploy` | Versionszeilen beider Server; Firebird zusätzlich als `OK`/`WARNUNG` gegen `$script:FirebirdServerAdvisories` | Neue Advisories zuerst in die Liste aufnehmen; MSSQL gegen Microsoft-Lifecycle prüfen |
| Statische Analyse (Härtung) | `Invoke-ScriptAnalyzer -Path . -Recurse` (PSScriptAnalyzer) | Regelverletzungen | Kein CVE-Scanner, aber Best-Practice-Ergänzung; seit I10b in der CI (`tests/scriptanalyzer.ps1`, Severity `Error` blockiert) |
| CI-Actions | `gh api repos/actions/checkout/releases/latest` gegen den SHA in `.github/workflows/ci.yml` | Release + Commit-SHA | Bei neuem Release: Release Notes/Advisories prüfen, SHA und Tag-Kommentar gemeinsam aktualisieren |

> Ergebnis als Artefakt sichern (`docs/audits/<YYYY-MM-DD>-deps.txt`; Ordner bei erstem Audit
> anlegen), damit die Historie nachvollziehbar bleibt.

---

## Schweregrad-Politik

| Severity | Reaktion |
|---|---|
| Critical | Sofort patchen (innerhalb 24h) oder Mitigation (Scheduled Tasks deaktivieren) |
| High | Innerhalb des aktuellen Inkrements |
| Medium | Im nächsten regulären Inkrement |
| Low | Backlog; bei nächstem Major-Upgrade mitziehen |

Mitigation kann auch sein: Nutzung der verwundbaren Funktion entfernen, falls Update nicht möglich
ist. Bei einem Treiber-Update gilt: neue Version, Download-URL **und** beide SHA-256-Werte gemeinsam in
`$script:FirebirdDriver` ändern, die Hashes aus dem offiziellen NuGet-Paket selbst berechnen und im Commit dokumentieren.

---

## SBOM (optional)

Für dieses Projekt ist kein Build-Werkzeug vorhanden, das eine SBOM erzeugt. Bei Bedarf manuell
als CycloneDX/SPDX aus der Bestandstabelle oben erstellen (PowerShell, .NET, SqlClient,
FirebirdClient inkl. Hash). SBOM gehört in `docs/audits/` – nicht in den Quellbaum als rotierende
Datei.

---

## Was nicht ausreicht

- **„Wir nutzen nur populäre Bibliotheken"** — populär ≠ sicher (siehe `event-stream`,
  `colors.js`, `xz-utils`).
- **GitHub Dependabot allein** — erkennt hier nichts: Der Treiber wird zur Laufzeit per URL geladen,
  nicht über eine Paketdatei deklariert.
- **SHA-256-Prüfung allein** — schützt (seit I7 für jede geladene DLL) gegen manipulierte Downloads
  und nachträglich ausgetauschte DLLs, nicht aber gegen bekannte Schwachstellen in genau dieser
  Version und nicht gegen eine in der Sitzung bereits geladene Assembly.
- **Einmaliger Audit beim Projektstart** — Audits müssen wiederholt werden, weil neue CVEs ständig
  erscheinen.
- **Scanner-Lauf allein** — findet keine Härtungs-Best-Practices und keine Advisories ohne
  CVE-Eintrag. Web-Recherche nach `principles/SECURITY_CURRENCY.md` ergänzt den Scanner, ersetzt
  ihn nicht (und umgekehrt).

---

## Pflege

Trigger (siehe `KICKOFF.md` Phase 3a): neue Dependency hinzugefügt / Treiber-Version geändert /
CVE-Meldung erhalten / Audit-Tool geändert → diese Datei + Audit-Artefakt aktualisieren.
