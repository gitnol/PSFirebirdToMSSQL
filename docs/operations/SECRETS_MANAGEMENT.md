# Secrets-Management – PSFirebirdToMSSQL

Wo Secrets leben dürfen, wie sie rotiert werden, und wie sie nicht in Logs oder Repositories
landen. Konsolidiert Hinweise aus `CONVENTIONS.md`, `security/AUTHENTICATION.md` und
`security/DATA_HANDLING.md`.

Verbindet sich mit `architecture/CONFIGURATION.md` (Konfiguration vs. Secret-Quellen),
`architecture/CREDENTIAL_STRATEGY.md` und `security/THREAT_MODEL.md` (Bedrohung 2:
Credential-Exposition).

**Wichtig:** Das Repository ist öffentlich (GitHub). Jede Datei, die committet wird, ist weltweit
lesbar.

---

## Secrets dieses Projekts

| Secret | Verwendung | Ablage (Soll) |
|---|---|---|
| Firebird-Benutzer + Passwort | Lesen der Quelltabellen | Credential Manager `SQLSync_Firebird` (oder Name aus `Firebird.CredentialTarget`) |
| SQL-Server-Login + Passwort | Schreiben in die Ziel-DB (nur ohne Integrated Security) | Credential Manager `SQLSync_MSSQL` (oder Name aus `MSSQL.CredentialTarget`, z. B. ein Eintrag pro Server) |
| Windows-Passwort des Task-Kontos | Ausführung der Scheduled Tasks | Task Scheduler (LSA), eingegeben über `Setup-ScheduledTasks.ps1` |

Weitere Secrets (API-Tokens, Zertifikate, SSH-Keys, Signierschlüssel) gibt es nicht – die
entsprechenden Zeilen des Templates treffen nicht zu.

---

## Erlaubte Speicherorte pro Secret-Typ

| Secret-Typ | Erlaubter Speicherort | NICHT erlaubt |
|---|---|---|
| Firebird-/MSSQL-Passwort | Windows Credential Manager (Generic, Targets `SQLSync_Firebird`/`SQLSync_MSSQL`) unter dem Task-Konto; alternativ Integrated Security (kein Secret) | `config*.json`, `*.bak`, `config.sample.json`, Skripte, README/Doku, Tickets, Kommandozeilenargumente (`cmdkey /pass:`) |
| Windows-Passwort des Task-Kontos | Task Scheduler; besser gMSA (`Setup-ScheduledTasks.ps1 -GmsaAccount`, kein Passwort) | Skripte, Konfigdateien, Task-Argumente |
| Server-/DB-Namen, interne Pfade (kein Secret, aber vertraulich) | Lokale `config*.json` (gitignored) | `config.sample.json`, `Setup-ScheduledTasks.ps1`, Doku im öffentlichen Repo (seit I9 bereinigt; Pfade/Konfignamen beim Aufruf per Parameter übergeben) |

---

## Quellen-Präzedenz für Secrets (Code-Stand)

Im Code (`Resolve-FirebirdCredentials`, `Resolve-MSSQLCredentials` in `SQLSyncCommon.psm1`):

1. **Integrated Security** (nur MSSQL; kein Secret)
2. **Windows Credential Manager** (`SQLSync_Firebird`, `SQLSync_MSSQL` bzw. die Namen aus
   `Firebird.CredentialTarget` / `MSSQL.CredentialTarget`)
3. **Konfigurationsdatei** (`Firebird.Password`, `MSSQL.Password`) – unsicherer Fallback, wird mit
   `WARNUNG: unsicher!` geloggt

Es gibt keine Umgebungsvariablen, keine `.env`-Datei, keinen Secrets-Manager/Vault und keine
CLI-Parameter für Secrets. **Betriebsregel:** Passwortfelder in Konfigurationsdateien leer lassen
bzw. entfernen; Stufe 3 gilt als Fehlkonfiguration. Ziel (Backlog): Fallback nur per explizitem
Schalter zulassen.

---

## Rotation

| Secret | Empfohlenes Intervall | Auslöser einer außerplanmäßigen Rotation |
|---|---|---|
| Firebird-Passwort | Nach Policy des ERP-Betriebs (mind. jährlich) | Passwort in Konfig/Backup/Log/Repo gefunden, Personalwechsel, Verdacht auf Kompromittierung |
| SQL-Server-Login-Passwort | Nach Policy (mind. jährlich) | wie oben |
| Windows-Passwort Task-Konto | Nach AD-Policy (entfällt bei gMSA) | Verdacht auf Kompromittierung |

**Rotations-Schritte (Firebird/MSSQL):**

1. Neues Passwort auf dem Datenbankserver setzen (bzw. neues Konto anlegen und berechtigen).
2. Als **Task-Konto** anmelden bzw. `runas /user:<Konto> pwsh` und `.\Setup_Credentials.ps1`
   ausführen (bei abweichendem Eintragsnamen mit `-FirebirdTarget` / `-MSSQLTarget`, passend zu
   `*.CredentialTarget`); vorhandenen Eintrag mit „J" überschreiben.
3. `.\Test-SQLSyncConnections.ps1 -ConfigFile <Konfig>` ausführen → Exit-Code 0 erwartet.
4. Nächsten Lauf im Log `Logs\Sync_<ConfigName>_<Zeitstempel>.log` prüfen: Zeile
   `[Credentials] ...: Credential Manager (<Eintrag>)` (nicht `config.json`).
5. Altes Konto/Passwort deaktivieren, sobald ein Lauf erfolgreich war.

**Rotation Windows-Passwort des Task-Kontos:** Passwort im Task Scheduler für beide Tasks
(`SQLSync_Firebird_Daily_Diff`, `SQLSync_Firebird_Weekly_Full`) aktualisieren oder
`Setup-ScheduledTasks.ps1` erneut ausführen. Sonst schlagen die Tasks mit Anmeldefehler fehl.
Details: `docs/operations/TASK_SCHEDULER.md`.

---

## Was niemals in Logs landen darf

- Passwörter (auch nicht teilweise) und vollständige Connection-Strings mit Passwort.
- Das ist im aktuellen Code eingehalten: Das Transcript-Log enthält nur Server, Datenbank, Port,
  `IntegratedSecurity`-Flag und die Credential-**Quelle**. Connection-Strings werden mit
  `DbConnectionStringBuilder` gebaut und nicht ausgegeben.
- Bei neuen Ausgaben: keine `Write-Host`/`Write-Verbose`-Ausgabe von `$FbCreds`, `$SqlCreds`,
  `$Config.Firebird` oder `$Config.MSSQL` als Ganzes (würde das Passwort-Feld serialisieren).
- Achtung `Start-Transcript`: Alles, was in die Konsole geschrieben wird, landet im Log – auch
  Fehlertexte von Treibern. Exceptions vor dem Weiterreichen nicht um Connection-Strings ergänzen.

---

## Was niemals committet werden darf

- `config*.json` außer `config.sample.json` / `config.schema.json` (`.gitignore`: `/config*`)
- `config.json.<Zeitstempel>.bak` (`.gitignore`: `*.bak`)
- `Logs/`, `*.log`
- `*.secret`, `*.key`, `*.pem`, `*.pfx`, `*.clixml`, `.env`
- Echte Server-, Datenbank-, Benutzernamen oder Passwörter in `config.sample.json`, Skripten oder
  Doku. `config.sample.json` enthält nur Platzhalter, `Setup-ScheduledTasks.ps1` nur generische
  Parameter-Defaults (seit I9).

Vor jedem Commit: `git status` prüfen; bei Verdacht `git diff --cached | Select-String -Pattern 'Password'`.
Wurde ein Secret committet: Vorgehen nach `docs/operations/INCIDENT_RESPONSE.md` (P0) – Rotation
zuerst, Historienbereinigung danach.

---

## Pflege

Trigger (siehe `KICKOFF.md` Phase 3a): neues Secret eingeführt, rotiert, Speicherort geändert oder
Logging-Pfad ergänzt → diese Datei eintragen.
