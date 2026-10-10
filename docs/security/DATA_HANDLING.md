# Datenschutz & Compliance – PSFirebirdToMSSQL

Rahmen: **DSGVO** (das Projekt repliziert ERP-Daten, die personenbezogene Daten von Kunden,
Lieferanten und Ansprechpartnern enthalten, z. B. in Tabellen wie `BKUNDE`, `BLIEF`). Ein
weitergehender formaler Rahmen (TISAX, ISO 27001) ist im Projekt nicht festgelegt. **Offen:** Prüfen,
ob die replizierten ERP-Daten im TISAX-Scope des Betreibers liegen – falls ja, das Overlay
`compliance-tisax` aus dem Doku-Template nachziehen (Backlog).

Das Werkzeug selbst ist ein Kopierwerkzeug: Es entscheidet nicht, welche Daten sinnvoll repliziert
werden. Die Verantwortung für Zweckbindung und Auswahl der Tabellen (`Tables` in der
Konfigurationsdatei) liegt beim Betreiber.

---

## 1. Lokale Verarbeitung / Datenisolation

- Verarbeitung ausschließlich im internen Netz: Firebird-Server (Port 3050) → Windows-Host mit
  PowerShell 7 → MS SQL Server. Es gibt keinen Cloud-Dienst und keine externe API.
- Einzige ausgehende Internetverbindung: einmaliger Download des Treibers
  `FirebirdSql.Data.FirebirdClient` 10.3.4 von `globalcdn.nuget.org` (`Initialize-FirebirdDriver`).
  Dabei werden keine Nutzdaten übertragen.
- Zugriff auf die Nutzdaten haben: das Sync-Konto (Task Scheduler), das Firebird-Konto aus
  `SQLSync_Firebird`, das MSSQL-Login aus `SQLSync_MSSQL` bzw. das Windows-Konto bei Integrated
  Security sowie alle Nutzer mit Leserechten auf die Ziel-DB.
- Transportverschlüsselung ist nicht im Code festgelegt (kein `Encrypt` im MSSQL-Connection-String,
  keine Wire-Crypt-Einstellung für Firebird) – abhängig von der Server-Konfiguration. Siehe
  `docs/security/THREAT_MODEL.md`, Bedrohung 2.
- Keine Air-Gap-Anforderung bekannt.

---

## 2. Minimalprinzip (Data Minimization)

- **Keine Weitergabe an externe Services oder LLMs.** Das Projekt nutzt kein LLM.
- Repliziert wird **tabellenweise 1:1** (`SELECT *`): alle Spalten jeder konfigurierten Tabelle,
  ohne Spaltenfilter, Pseudonymisierung oder Maskierung. Minimierung ist nur über die Auswahl der
  Tabellen in `Tables` möglich.
- Explizit **nicht** übertragen werden: Firebird-Systemtabellen (nur, wenn sie nicht konfiguriert
  sind – technisch wird nicht verhindert, sie einzutragen), Passwörter (werden nicht geloggt).
- Keine Limits/Truncation für sensible Felder. Backlog-Kandidat: Spalten-Ausschlussliste pro Tabelle.
- **Löschungen werden standardmäßig nicht repliziert** (K4/K5). In der Quelle gelöschte Datensätze
  bleiben in der Zieltabelle, bis `General.CleanupOrphans = true` gesetzt ist (nur Tabellen mit
  numerischer ID-Spalte) oder ein Lauf mit `ForceFullSync` die Zieltabelle neu befüllt.
  **Konsequenz für die DSGVO-Löschpflicht (Art. 17):** Eine Löschung im ERP erfüllt die Pflicht im
  Ziel nicht automatisch. Der Betreiber muss entweder `CleanupOrphans` aktivieren, regelmäßige
  Full-Läufe einplanen oder Löschungen im Ziel separat nachziehen.

---

## 3. Output-Dateien und Speicherorte

| Datei / Ort | Inhalt | Sensitivität |
|-------|--------|-------------|
| MSSQL-Zieldatenbank: Zieltabellen (Prefix + Tabelle + Suffix) | Vollständige Kopie der ERP-Tabellen inkl. personenbezogener Daten | Hoch |
| MSSQL-Zieldatenbank: Staging-Tabellen `STG_<Tabelle>` | Letztes Delta bzw. letzter Voll-Extrakt (wird pro Lauf per `TRUNCATE` ersetzt) | Hoch |
| tempdb: `#SourceIDs_<Tabelle>` | Nur ID-Werte während des Orphan-Cleanups | Niedrig |
| `Logs\Sync_<ConfigName>_<yyyy-MM-dd_HHmm>.log` (Transcript) | Server- und DB-Namen, Tabellennamen, Zeilenzahlen, Strategie, Fehlertexte von Firebird/MSSQL, Credential-**Quelle** (nicht Passwort) | Mittel (Infrastruktur-Informationen; Fehlertexte können in Einzelfällen Datenwerte enthalten, z. B. bei Konvertierungs- oder PK-Verletzungen) |
| `config*.json` im Skriptordner | Server, DB-Pfade, Tabellenliste, ggf. Klartext-Passwort (unsicherer Fallback) | Hoch, falls Passwort enthalten |
| `config.json.<yyyyMMdd_HHmmss>.bak` (von `Manage_Config_Tables.ps1`) | Kopie der Konfiguration inkl. eventueller Passwörter | Hoch, falls Passwort enthalten |
| `%ProgramData%\SQLSync\Drivers\...` | Treiber-DLL (keine Nutzdaten) | Niedrig (Integrität relevant, siehe Bedrohung 3) |

- Konfigurationsdateien, Backups und Logs gehören auf den Sync-Host in den Skriptordner mit
  restriktiven NTFS-Rechten (Admins + Sync-Konto). Nicht auf Netzlaufwerke oder in Tickets kopieren.
- `.gitignore` erfasst: `/config*` (außer `config.sample.json`, `config.schema.json`), `*.bak`,
  `Logs/`, `**/*.log`, `*.secret`, `*.key`, `*.pem`, `*.pfx`, `*.clixml`, `.env`, `*.dll`, `*.nupkg`.

---

## 4. Zugriffsschutz

- **Firebird:** Konto aus `SQLSync_Firebird`, benötigt nur Leserechte auf die konfigurierten
  Tabellen. Fallback `SYSDBA` (wenn `Firebird.User` fehlt) vermeiden.
- **MSSQL:** Login braucht DDL + Schreibrechte in der Ziel-DB; `dbcreator` nur, wenn die Ziel-DB
  automatisch angelegt werden soll (Pre-Flight). Empfehlung: DB vorab anlegen, `dbcreator` entziehen.
- **Leser der Ziel-DB:** Zugriff auf Zieltabellen mit personenbezogenen Daten nach dem gleichen
  Berechtigungskonzept wie im ERP vergeben (Staging-Tabellen nicht für Endnutzer freigeben).
- **Sync-Host:** Skriptordner, Logs und `%ProgramData%\SQLSync` nur für Admins und das Sync-Konto
  beschreibbar.
- Secret-Speicherung und Rotation: siehe `docs/operations/SECRETS_MANAGEMENT.md`.

---

## 5. Datenhaltung / Retention

- **Zieltabellen:** akkumulieren; Datensätze werden per MERGE aktualisiert, aber ohne
  `CleanupOrphans` nie gelöscht (siehe Abschnitt 2). Bei `Snapshot`-Strategie (Tabellen ohne ID)
  und `ForceFullSync` wird die Zieltabelle pro Lauf neu befüllt.
- **Staging-Tabellen:** werden pro Lauf überschrieben (`TRUNCATE` bzw. Neuanlage mit
  `RecreateStagingTable`); enthalten danach den letzten Extrakt bis zum nächsten Lauf.
- **Logs:** Rotation am Ende jedes Laufs: `Sync_*.log` älter als `General.DeleteLogOlderThanDays`
  (Default 30, `0` = keine Rotation) werden gelöscht.
- **`*.bak`-Backups:** seit I10a (`Manage_Config_Tables.ps1` v2.2) behält das Skript nach dem
  Speichern nur die neuesten `-KeepBackups` Backups je Konfig (Default 5); bis dahin akkumulierten sie
  unbegrenzt. `Test-SQLSyncConnections.ps1 -PreDeploy` meldet vorhandene Backups als `WARNUNG`.
  Verantwortlich für das Aufräumen der verbleibenden Backups: Betreiber des Sync-Hosts (manuell).
- **Datensicherung der Ziel-DB:** Pre-Flight legt eine neue DB mit `RECOVERY SIMPLE` an; Backup und
  Aufbewahrungsfristen der Ziel-DB regelt der DB-Betrieb, nicht dieses Projekt.

---

## 6. Compliance-Checkliste für neue Features

- [ ] Keine neuen persistenten Speicher ohne Retention-Konzept
- [ ] Kein Logging von sensiblen Inhalten (Passwörter, Nutzdaten, PII) – auch nicht beispielhafte
      Datensätze bei Fehlern
- [ ] Externe Services nur nach Compliance-Prüfung einführen
- [ ] Neue Tabellen in `Tables`: Enthält die Tabelle personenbezogene Daten? Zweck und Leserkreis
      im Ziel geklärt?
- [ ] Löschpfad geklärt: `CleanupOrphans` oder periodischer Full-Lauf für Tabellen mit
      personenbezogenen Daten
- [ ] Keine echten Server-, DB- oder Benutzernamen in `config.sample.json`, Skripten oder Doku
      (öffentliches Repository)
- [ ] TISAX-Relevanz der replizierten Daten geprüft (Overlay `compliance-tisax`)
