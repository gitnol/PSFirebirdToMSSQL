# Credential-Strategie – PSFirebirdToMSSQL

Wo und wie Credentials für die Firebird- und SQL-Server-Verbindung gespeichert und benutzt werden.
Konkretisiert `docs/operations/SECRETS_MANAGEMENT.md` für dieses Projekt.

---

## Übersicht

| Credential | Store | Target / Fundort | Angelegt durch | Gelesen durch |
|---|---|---|---|---|
| Firebird-Benutzer + Passwort | Windows Credential Manager (Generic, `Persist = LocalMachine`) | `SQLSync_Firebird` (Default; abweichend über `Firebird.CredentialTarget`) | `Setup_Credentials.ps1` | `Resolve-FirebirdCredentials` → `Get-StoredCredential` |
| SQL-Server-Login + Passwort | Windows Credential Manager (Generic, `Persist = LocalMachine`) | `SQLSync_MSSQL` (Default; abweichend über `MSSQL.CredentialTarget`) | `Setup_Credentials.ps1` (optional, nur bei SQL-Auth) | `Resolve-MSSQLCredentials` → `Get-StoredCredential` |
| SQL Server per Windows-Auth | keiner (Konto des ausführenden Prozesses) | `MSSQL."Integrated Security": true` | — | `New-MSSQLConnectionString -IntegratedSecurity` |
| Windows-Passwort des Task-Kontos | Task Scheduler (verschlüsselt) | Tasks `SQLSync_Firebird_Daily_Diff`, `SQLSync_Firebird_Weekly_Full` | `Setup-ScheduledTasks.ps1` (`Get-Credential`) | Task Scheduler |
| **Fallback (unsicher):** Passwörter im Klartext | JSON-Konfigdatei | `Firebird.Password` (+ `Firebird.User`), `MSSQL.Password` (+ `MSSQL.Username`) | manuell | Resolver, mit gelber Warnung |

Keine Credentials für externe Dienste: der NuGet-Download des Treibers ist anonym.

---

## Auflösungsreihenfolge

**Firebird** (`Resolve-FirebirdCredentials`):

1. Credential Manager, Eintrag aus `Firebird.CredentialTarget` (Default `SQLSync_Firebird`) → Ausgabe
   `[Credentials] Firebird: Credential Manager (SQLSync_Firebird)` (grün)
2. `Firebird.Password` aus der Konfigdatei (Benutzer `Firebird.User`, sonst `SYSDBA`) → `config.json (WARNUNG: unsicher!)` (gelb)
3. sonst `throw "Keine Firebird Credentials gefunden (Credential-Manager-Eintrag '…')! Führe Setup_Credentials.ps1 aus."`
   → Sync-Exit-Code 5

**SQL Server** (`Resolve-MSSQLCredentials`):

1. `"Integrated Security": true` → Windows-Authentifizierung, keine gespeicherten Credentials
2. Credential Manager, Eintrag aus `MSSQL.CredentialTarget` (Default `SQLSync_MSSQL`); Log z. B.
   `[Credentials] SQL Server: Credential Manager (SQLSync_MSSQL_sqltest)`
3. `MSSQL.Password` / `MSSQL.Username` aus der Konfigdatei (Warnung)
4. sonst `throw` → Sync-Exit-Code 5

Empfehlung: **Windows-Authentifizierung für SQL Server** (kein gespeichertes Passwort) und **Credential Manager für
Firebird**. Der Klartext-Fallback ist nur für erste Tests gedacht und sollte in Produktivkonfigurationen fehlen.

**Eigener Eintrag pro Server:** Nutzen mehrere SQL Server denselben Login mit unterschiedlichen Passwörtern (z. B. `sa`
auf Prod- und Testserver), bekommt jede Konfigdatei über `MSSQL.CredentialTarget` einen eigenen Eintrag. Ohne den
Schlüssel gilt der Default, das Verhalten ist unverändert.

---

## Speichern: `Setup_Credentials.ps1`

- Interaktiv: Benutzername per `Read-Host`, Passwort per `Read-Host -AsSecureString`.
- Eintragsnamen über `-FirebirdTarget` / `-MSSQLTarget` (Defaults `SQLSync_Firebird` / `SQLSync_MSSQL`), z. B.
  `.\Setup_Credentials.ps1 -MSSQLTarget "SQLSync_MSSQL_sqltest"`; muss zu `*.CredentialTarget` in der Konfig passen.
- Schreibt **in-process** per `CredWrite` (advapi32, via `Add-Type`), Typ `CRED_TYPE_GENERIC`, `CRED_PERSIST_LOCAL_MACHINE`.
  Das Passwort wird über einen BSTR übergeben und danach mit `ZeroFreeBSTR` gelöscht.
  (Früher `cmdkey /pass:…` — dabei stand das Passwort in der Prozess-Kommandozeile; behoben mit Commit 721d5e0.)
- Existenzprüfung per `cmdkey /list` (nur Target-Namen, keine Passwörter); bestehende Einträge werden nur nach
  Rückfrage (`J`) überschrieben.
- Pflege manuell: `cmdkey /list`, `cmdkey /delete:SQLSync_Firebird`, `cmdkey /delete:SQLSync_MSSQL` (bzw. die gewählten
  Namen; die Lösch-Hinweise am Ende des Skripts nennen sie).

**Kontobindung:** Credential-Manager-Einträge gehören dem Windows-Benutzer, der `Setup_Credentials.ps1` ausführt.
`Setup_Credentials.ps1` muss deshalb **unter demselben Konto** laufen wie die geplanten Tasks
(`Setup-ScheduledTasks.ps1` registriert sie unter dem aktuellen Benutzer). Bei Kontowechsel: Setup erneut ausführen.

---

## Laufzeit-Handhabung

- `Get-StoredCredential` liest per `CredRead` und gibt Benutzer und Passwort als **Klartext-String** zurück
  (`PSCustomObject` mit `Username`, `Password`); der native Speicher wird mit `CredFree` freigegeben.
- Die Resolver geben eine Hashtable `@{ Username; Password; Source }` zurück; `Source` (`CredentialManager`,
  `ConfigFile`, `WindowsAuth`) wird nur für die Ausgabe genutzt.
- `New-FirebirdConnectionString` / `New-MSSQLConnectionString` akzeptieren String **oder** `SecureString` und bauen den
  Connection String per `DbConnectionStringBuilder` (korrektes Maskieren von `; = ' "` in Passwörtern).
- Connection Strings werden per `$using:` in die Parallel-Runspaces gereicht.
- Es werden **nie** Passwörter oder vollständige Connection Strings ausgegeben; die Verbindungsinfo im Log enthält nur
  Server, Datenbank, Port und `IntegratedSecurity`.

Bekannte Einschränkung: Das Passwort liegt ab dem Lesen als normaler .NET-String im Prozessspeicher (nicht als
`SecureString`). Für ein Batch-Werkzeug, das ohnehin einen Klartext-Connection-String an den Treiber übergeben muss,
ist das akzeptiert; eine Umstellung brächte wenig Gewinn.

---

## Service-Account-Strategie

| Szenario | Ist-Zustand | Empfehlung |
|---|---|---|
| Manueller Lauf / Test | interaktiver Benutzer | ok |
| Task Scheduler | Default: aktueller Benutzer mit gespeichertem Windows-Passwort (`Register-ScheduledTask -User … -Password …`); wählbar per `Setup-ScheduledTasks.ps1 -RunAsUser` (Dienstkonto, Passwort wird abgefragt) oder `-GmsaAccount` (gMSA, Principal mit LogonType `Password`, kein gespeichertes Passwort) | dediziertes Dienstkonto oder gMSA mit Least Privilege; mit persönlichem Konto bricht ein Passwortwechsel die Tasks |
| SQL-Server-Rechte | je nach Konto (nicht dokumentiert) | in der Zieldatenbank: DDL (`CREATE TABLE`, `ALTER TABLE`, `CREATE OR ALTER PROCEDURE`), `TRUNCATE`, Lesen/Schreiben/Löschen, Bulk-Insert (`SqlBulkCopy`), `EXECUTE` auf `sp_Merge_Generic`; `dbcreator` nur, wenn die Datenbank automatisch angelegt werden soll. Ein minimaler Rollensatz ist nicht verifiziert (offen) |
| Firebird-Rechte | häufig `SYSDBA` (Beispiel im Setup) | eigener Firebird-Benutzer mit reinem Leserecht auf die konfigurierten Tabellen und Systemtabellen (`RDB$…`) |

Niemals Domänen-Admin als Task-Konto.

**Grenze gMSA:** Credential-Manager-Einträge sind an das Konto gebunden, das sie anlegt. Ein gMSA kann sich nicht
interaktiv anmelden, `Setup_Credentials.ps1` lässt sich also nicht einfach unter ihm ausführen. Mit gMSA eignet sich
daher vor allem `MSSQL."Integrated Security": true` (das gMSA braucht ein SQL-Server-Login). Firebird kennt keine
Windows-Authentifizierung im Sync; die Firebird-Credentials müssten im Kontext des gMSA angelegt werden (z. B. über
einen einmaligen Task unter dem gMSA), sonst endet der Sync mit Exit 5. Ein klassisches Dienstkonto (`-RunAsUser`)
hat diese Einschränkung nicht, bringt aber wieder ein gespeichertes Passwort mit.

---

## Nicht verwendete Muster (trifft nicht zu)

- **DPAPI-Dateien (`ConvertFrom-SecureString`) / `Export-Clixml`:** nicht verwendet — Credential Manager deckt den Bedarf.
- **`Microsoft.PowerShell.SecretManagement`:** nicht verwendet (keine Galerie-Module gewünscht).
- **SSH-Keys, API-Tokens, OAuth:** keine.

---

## Anti-Pattern

```powershell
# Verboten: Klartext-Passwort im Skript oder in versionierten Dateien
$FbPass = "…"

# Verboten: Passwort in einer Prozess-Kommandozeile (in Prozesslisten/Ereignisprotokoll sichtbar)
cmdkey /generic:SQLSync_Firebird /user:SYSDBA /pass:…

# Verboten: Connection String ausgeben oder in Exception-Text aufnehmen
Write-Host "Verbinde mit $FirebirdConnString"

# Verboten: Connection String per Konkatenation (bricht bei ';' im Passwort, Injection von Schlüsseln)
$cs = "User=$User;Password=$Pass;Database=$Db"
```

`config.sample.json` und `Setup-ScheduledTasks.ps1` dürfen keine realistisch wirkenden Zugangsdaten, internen
Servernamen oder Konfignamen enthalten (seit I9 neutralisiert: Platzhalterwerte bzw. generische Parameter-Defaults).

---

## Logging-Regeln

- Nur die **Quelle** des Credentials loggen (`Credential Manager`, `config.json (WARNUNG: unsicher!)`,
  `Windows Authentication`), nie Benutzer-Passwort-Kombinationen.
- Bei Authentifizierungsfehlern genügt die Treiber-Meldung (z. B. „Login failed for user …"); keine Connection Strings anhängen.
- Transcript-Logs in `Logs\` können Benutzernamen enthalten → Ordner-ACL auf Task-Konto und Administratoren beschränken.

---

## Rotation

| Credential | Intervall | Vorgehen |
|---|---|---|
| Firebird-Passwort | nach Betreiber-Vorgabe; außerplanmäßig bei Leak-Verdacht oder Personalwechsel | Passwort in Firebird ändern, dann `Setup_Credentials.ps1` unter dem Task-Konto erneut ausführen (Überschreiben mit `J`) |
| SQL-Login-Passwort | wie oben (entfällt bei Windows-Auth) | wie oben, Target `SQLSync_MSSQL` bzw. `MSSQL.CredentialTarget` (`-MSSQLTarget`) |
| Windows-Passwort des Task-Kontos | bei jeder Änderung | `Setup-ScheduledTasks.ps1` erneut ausführen (Tasks werden neu registriert); mit gMSA entfällt das |
| Klartext-Fallback in Konfigdatei | sofort entfernen | Passwort aus JSON löschen, alte `*.bak`-Dateien löschen |

Konkrete Intervalle sind im Projekt nicht festgelegt (offen).

---

## Pflege

Trigger: neue Verbindung / neue Credential-Quelle / Änderung an `Setup_Credentials.ps1` oder den Resolvern /
Rotation durchgeführt → hier eintragen und in `docs/operations/SECRETS_MANAGEMENT.md` referenzieren.
