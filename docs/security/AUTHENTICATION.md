# Authentication – PSFirebirdToMSSQL

Alle Authentifizierungsmechanismen, die das Projekt verwendet. Code-Fundorte:
`SQLSyncCommon.psm1` (`Get-StoredCredential`, `Resolve-FirebirdCredentials`,
`Resolve-MSSQLCredentials`, `New-FirebirdConnectionString`, `New-MSSQLConnectionString`),
`Setup_Credentials.ps1` (`Set-StoredCredential`, `Test-StoredCredential`),
`Setup-ScheduledTasks.ps1`.

---

## Auth-Übersicht

| Ziel | Verfahren | Secret-Ablageort | Anlage |
|------|-----------|-----------------|--------|
| Firebird-Server (Quelle) | Firebird-Benutzer + Passwort im Connection-String (`User`, `Password`) | Windows Credential Manager, Target `SQLSync_Firebird` (Generic; Name per `Firebird.CredentialTarget` änderbar). Fallback: `Firebird.User`/`Firebird.Password` in `config*.json` (unsicher) | Einmalig interaktiv mit `Setup_Credentials.ps1`, als das Konto, unter dem der Task läuft |
| MS SQL Server (Ziel), Variante A | Windows-integriert (`Integrated Security=True`, Kerberos/NTLM des Task-Kontos) | Kein Secret im Projekt | Konfig: `MSSQL."Integrated Security": true`; SQL-Login für das Windows-Konto durch DBA |
| MS SQL Server (Ziel), Variante B | SQL-Authentifizierung (`User Id`, `Password`) | Windows Credential Manager, Target `SQLSync_MSSQL` (Generic; Name per `MSSQL.CredentialTarget` änderbar). Fallback: `MSSQL.Username`/`MSSQL.Password` in `config*.json` (unsicher) | Einmalig interaktiv mit `Setup_Credentials.ps1` (Frage „SQL Server Authentifizierung einrichten? J") |
| Windows Task Scheduler | Windows-Benutzer + Passwort (Logon „unabhängig von Anmeldung") | Vom Task Scheduler (LSA) gespeichert | `Setup-ScheduledTasks.ps1` fragt per `Get-Credential` das Passwort von `-RunAsUser` ab (Default: **aktueller** Benutzer) |
| Windows Task Scheduler mit gMSA | Group Managed Service Account (`-GmsaAccount`) | Kein gespeichertes Passwort; Passwort verwaltet AD | `Setup-ScheduledTasks.ps1 -GmsaAccount 'DOMAIN\name$'`; Konto braucht „Anmelden als Stapelverarbeitungsauftrag“ |
| NuGet CDN (Treiber-Download) | Keine Authentifizierung (öffentliches HTTPS) | – | – |

**Reihenfolge der Auflösung (Code):**
- Firebird: `SQLSync_Firebird` → `config.json` `Firebird.Password` (Benutzer `Firebird.User`,
  sonst `SYSDBA`) → Abbruch mit Exit-Code 5.
- MSSQL: `Integrated Security` → `SQLSync_MSSQL` → `config.json` `MSSQL.Password` → Abbruch mit
  Exit-Code 5.
- Gelesen wird der Eintrag aus `Firebird.CredentialTarget` bzw. `MSSQL.CredentialTarget` (Defaults
  `SQLSync_Firebird` / `SQLSync_MSSQL`); so kann jede Konfigdatei einen eigenen Eintrag nutzen, z. B. für
  mehrere SQL Server mit gleichem Login und unterschiedlichen Passwörtern.
- Die verwendete Quelle samt Eintragsname wird geloggt (`[Credentials] Firebird: Credential Manager (SQLSync_Firebird)`
  bzw. `config.json (WARNUNG: unsicher!)`), das Passwort nie. Die Fehlermeldung nennt den gesuchten Eintrag.

---

## 1. Windows-integrierte Authentifizierung (MSSQL)

Kein Remote-Zugriff per WinRM/`Invoke-Command` – dieser Teil des Templates trifft nicht zu.
Integrierte Authentifizierung wird nur für die **SQL-Server-Verbindung** genutzt:

```powershell
# New-MSSQLConnectionString (SQLSyncCommon.psm1), Zweig IntegratedSecurity
"Server=$Server;Database=$Database;Integrated Security=True;"
```

**Voraussetzungen:**
- Das Konto, unter dem der Scheduled Task läuft, hat ein Login auf dem SQL Server mit
  DDL- und Schreibrechten in der Ziel-DB (und `dbcreator`, falls die DB per Pre-Flight angelegt
  werden soll).
- Sync-Host und SQL Server in derselben bzw. vertrauten AD-Domain (Kerberos), sonst NTLM.

**Bei Task Scheduler:**
- Default: Der Task läuft als der Benutzer, der `Setup-ScheduledTasks.ps1` ausführt (Bedrohung 5).
  Empfohlen: dediziertes Dienstkonto (`-RunAsUser`) oder gMSA (`-GmsaAccount 'DOMAIN\name$'`);
  Einrichtung siehe `docs/operations/TASK_SCHEDULER.md`.
- Mit gMSA ist Integrated Security der passende Weg zum SQL Server: kein gespeichertes Passwort,
  weder im Task noch im Credential Manager. Grenze: Credential-Manager-Einträge sind kontogebunden;
  Firebird-Credentials müssten im Kontext des gMSA angelegt werden
  (`docs/architecture/CREDENTIAL_STRATEGY.md`, „Grenze gMSA“).
- Konfiguration: „Unabhängig von Benutzeranmeldung ausführen" (LogonType `Password`; bei
  Benutzerkonten über `-User`/`-Password` von `Register-ScheduledTask`, beim gMSA über
  `New-ScheduledTaskPrincipal`).

---

## 2. DPAPI-Credential-Dateien (Export-Clixml / Import-Clixml)

Trifft nicht zu – das Projekt verwendet keine `Export-Clixml`-Dateien. `*.clixml` ist dennoch
vorsorglich gitignored.

---

## 3. Windows Credential Manager (eigene Implementierung, kein Zusatzmodul)

Das Projekt nutzt **kein** Modul aus der PowerShell Gallery (kein `TUN.CredentialManager`), sondern
ruft die Win32-API `advapi32.dll` direkt über per `Add-Type` kompilierte C#-Klassen auf.

**Schreiben – `Set-StoredCredential` (`Setup_Credentials.ps1`, lokale Funktion):**
- Parameter `-Target`, `-Username`, `-Password` (`SecureString` aus `Read-Host -AsSecureString`).
- Ruft `CredWrite` in-process auf: `Type = 1` (Generic), `Persist = 2` (`CRED_PERSIST_LOCAL_MACHINE`).
- Das Passwort erscheint dadurch in keiner Kommandozeile. (Bis Commit 721d5e0 wurde
  `cmdkey /pass:` verwendet – das Passwort war dabei in der Prozessliste sichtbar.)
- `Test-StoredCredential` prüft die Existenz über `cmdkey /list` (exakter Target-Abgleich, ohne
  Passwort).

**Lesen – `Get-StoredCredential` (`SQLSyncCommon.psm1`, exportiert):**
- Parameter `-Target`; ruft `CredRead(target, 1, 0, out ptr)` und `CredFree` im `finally`.
- Rückgabe: `PSCustomObject` mit `Username` und `Password` (Klartext-`string`), oder `$null`, wenn
  der Eintrag fehlt.
- Namenskonflikt beachten: Ist parallel das Modul `TUN.CredentialManager` geladen, gibt es dort
  eine gleichnamige Funktion mit anderem Rückgabetyp. Das Sync-Skript importiert
  `SQLSyncCommon.psm1` explizit; in interaktiven Sitzungen auf die Modulqualifizierung achten.

```powershell
# Einrichtung (einmalig, als späteres Task-Konto, interaktiv)
.\Setup_Credentials.ps1
# mit abweichendem Eintragsnamen (passend zu MSSQL.CredentialTarget)
.\Setup_Credentials.ps1 -MSSQLTarget "SQLSync_MSSQL_sqltest"

# Prüfen, ob die Einträge existieren
cmdkey /list:SQLSync*

# Im Code (Resolve-FirebirdCredentials)
$Target = Get-ConfigValue $Config.Firebird "CredentialTarget" "SQLSync_Firebird"
$Cred = Get-StoredCredential -Target $Target
if (-not $Cred) { <# Fallback config.json oder throw #> }

# Entfernen
cmdkey /delete:SQLSync_Firebird
cmdkey /delete:SQLSync_MSSQL
```

| Target-Name | Inhalt | Scope | Anlage |
|-------------|--------|-------|--------|
| `SQLSync_Firebird` | Benutzername + Passwort des Firebird-Kontos (nur Leserechte nötig) | Pro Windows-Benutzer, `Persist = LocalMachine` (übersteht Ab-/Anmeldung, nur auf diesem Rechner, nicht roamend) | Einmalig mit `Setup_Credentials.ps1` |
| `SQLSync_MSSQL` | Benutzername + Passwort des SQL-Logins (nur bei SQL-Authentifizierung) | wie oben | Einmalig mit `Setup_Credentials.ps1`, optional |
| abweichender Name (z. B. `SQLSync_MSSQL_sqltest`) | wie oben, ein Eintrag je Server/Konfig | wie oben | `Setup_Credentials.ps1 -FirebirdTarget …` / `-MSSQLTarget …`, Name in `*.CredentialTarget` eintragen |

**Wichtig:** Generic Credentials sind an den Windows-Benutzer gebunden, der sie anlegt. Läuft der
Task unter einem anderen Konto, findet `Get-StoredCredential` nichts und der Sync fällt auf
`config.json` zurück oder bricht mit Exit-Code 5 ab. `Setup_Credentials.ps1` daher unter dem
Task-Konto ausführen (z. B. `runas /user:<Konto> pwsh`).

---

## 4. SSH-Key-Authentifizierung (Linux-Targets)

Trifft nicht zu – das Projekt verbindet sich nicht per SSH/SCP.

---

## Bekannte Lücken

| Lücke | Fundort | Maßnahme |
|---|---|---|
| Klartext-Passwort-Fallback aus Konfigurationsdatei (und deren `*.bak`-Kopien) | `Resolve-FirebirdCredentials`, `Resolve-MSSQLCredentials`, `Manage_Config_Tables.ps1` | Betrieb: Passwortfelder leer lassen; seit I10a meldet `Test-SQLSyncConnections.ps1 -PreDeploy` gesetzte Passwortfelder und vorhandene Backups als `WARNUNG`, `Manage_Config_Tables.ps1 -KeepBackups` begrenzt die Backups (Default 5); Backlog: Fallback per Schalter deaktivierbar machen (Bedrohung 2) |
| `SYSDBA` als Default-Benutzer, wenn `Firebird.User` fehlt | `Resolve-FirebirdCredentials` | Dediziertes Lesekonto verwenden (nur `SELECT` auf die konfigurierten Tabellen, keine DDL, kein `CREATE FUNCTION`). Begründung: CVE-2026-40342 (CVSS 9.9, Firebird-Server < 5.0.4 / < 4.0.7 / < 3.0.14) – mit `CREATE FUNCTION` wird ein Leck der Sync-Credentials zur Codeausführung auf dem ERP-Datenbankserver (`THREAT_MODEL.md` Bedrohung 5 und 6). Anlage: `operations/SETUP.md` |
| Task läuft per Default als interaktiver Benutzer mit gespeichertem Windows-Passwort | `Setup-ScheduledTasks.ps1` | Option vorhanden: `-RunAsUser` (Dienstkonto) bzw. `-GmsaAccount`; Umstellung ist Betriebsentscheidung |
| Kein `Encrypt=True` im MSSQL-Connection-String; Firebird-Wire-Encryption nicht explizit gesetzt | `New-MSSQLConnectionString`, `New-FirebirdConnectionString` | Server-seitig erzwingen; Backlog: konfigurierbar machen |
| Integrated-Security-Zweig baut den Connection-String per Interpolation (nicht über `DbConnectionStringBuilder`) | `New-MSSQLConnectionString` | Niedriges Risiko (Werte aus Konfig); in I4 nicht geändert, weiterhin offen |

---

## Security-Checkliste

- [ ] Kein Klartext-Passwort im Quellcode, in `config*.json` oder `*.bak`
- [ ] `SQLSync_Firebird` (und ggf. `SQLSync_MSSQL`) unter dem **Task-Konto** angelegt
- [ ] Firebird-Lesekonto statt `SYSDBA` (nur `SELECT`, kein `CREATE FUNCTION`/DDL – CVE-2026-40342); Firebird-Server ≥ 5.0.4 / 4.0.7 / 3.0.14
- [ ] MSSQL: Integrated Security bevorzugt; Login nur mit Rechten auf die Ziel-DB, `dbcreator` nur falls Auto-Create nötig
- [ ] Task Scheduler: Dediziertes Dienstkonto mit minimalen Rechten – kein lokaler Administrator ohne Notwendigkeit
- [ ] Credential-Manager-Targets eindeutig benannt (`SQLSync_*`, ggf. mit Serverzusatz) – kein generisches `"password"`
- [ ] Bei Konto-Wechsel oder Passwortrotation: `Setup_Credentials.ps1` unter dem neuen Konto erneut ausführen; bei Rotation des Windows-Passworts des Task-Kontos `Setup-ScheduledTasks.ps1` erneut ausführen oder Task-Passwort aktualisieren
