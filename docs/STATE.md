# Aktueller Projektstatus – PSFirebirdToMSSQL

Zuletzt aktualisiert: 2026-10-10
**Initialisiert mit:** docs_template v26
**Letztes abgeschlossenes Inkrement:** I10a – Rollout-Check-Erweiterung und Backup-Hygiene (2026-10-10)
**Nächster Schritt:** I10c – Doku-Konsolidierung
**Nächste Reflexion:** nach I10c (drei weitere Inkremente: I10b, I10a, I10c; zuletzt 2026-10-09 nach I8), vor I10d (siehe `KICKOFF.md` Phase 1c → `docs/REFLECTION.md` — `docs/`-Drift prüfen + Template-Backport prüfen; danach Marker um 3 erhöhen)
**Nächster Security-Sweep:** 2026-10-22 (Intervall 14 Tage; siehe `KICKOFF.md` Phase 1 Punkt 4a → `docs/principles/SECURITY_CURRENCY.md` — fällig, sobald heute ≥ diesem Datum; nach dem Sweep Marker = Sweep-Datum + 14 Tage)

---

## Nächster Schritt

**I10c – Doku-Konsolidierung.** Exit-Code-Tabelle mit einziger Quelle `architecture/ERROR_HANDLING.md`, S-IDs in
K-/I-IDs überführen, `.github/copilot-instructions.md` angleichen, `README_alternativ.md` zusammenführen oder
entfernen. Danach Reflexion (fällig nach I10c), dann I10d (Modul-Aufräumen). Seit I10b prüft die CI jeden Push
auf `main`; seit I10a erkennt `-PreDeploy` Schema-Drift (K6) und die stille Merge-Rückkehr ohne ID-Spalte (K10).
Offene Template-Backport-Vorschläge (Freigabe ausstehend): siehe `CHANGELOG.md` „Reflexion nach I8".
Vor jedem Deployment: `.\Test-SQLSyncConnections.ps1 -ConfigFile <Profil> -PreDeploy` (seit I11).
Testumgebung für Integrationsläufe: Quelle Firebird-Testserver / Demo-Datenbank, Ziel SQL-Testserver /
`STAGING_I2TEST` (wird vom Pre-Flight bei Bedarf angelegt), Credential-Eintrag
`SQLSync_MSSQL_sqltest`, Konfigs `config_i2test_ok.json`, `config_i2test_fehler.json`,
`config_i4test_incr.json` (gitignored, Log-Rotation darin aus). Aufräumen, wenn nicht mehr
gebraucht: Datenbank `STAGING_I2TEST` auf SQL-Testserver und Test-Task `SQLSync_I2_Abnahme`.

Code-Stand: Sync-Skript v2.18 (Incremental mit Überlappungsfenster; Treiber-DLL per SHA-256 geprüft; Schema-Prüfung Fail-Fast; Typmapping mit Precision/Scale), `Setup-ScheduledTasks.ps1` parametrisiert (I9) (Exit-Codes 0/1/2/5/7/9/10/11; Identifier-Whitelist, durchgängig
gequotet/parametrisiert), optionale Konfigschlüssel `General.FailOnSanityError`, `General.IncrementalOverlapMinutes`,
`MSSQL.CredentialTarget`, `Firebird.CredentialTarget`; Unit-Tests unter `tests/` (192,
Coverage-Gate 80 %); CI auf GitHub Actions (Pester + PSScriptAnalyzer, seit I10b).

---

## Abgeschlossene Inkremente

| # | Titel | Datum | Commit |
|---|-------|-------|--------|
| I1 | docs/ initialisiert (Stack `powershell-automation`, keine Overlays) | 2026-10-08 | a082e9d |
| I2 | Fehlschläge sichtbar machen: Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; konfigurierbare Credential-Targets | 2026-10-08 | a082e9d |
| I3 | Pester-Testharness: 74 Unit-Tests für alle exportierten Modulfunktionen, Pester 5.7.1 gepinnt, Coverage-Gate 80 % | 2026-10-08 | a082e9d |
| I4 | SQL-Identifier gehärtet: Whitelist-Validierung (Fail-Fast), `[...]`/`QUOTENAME` überall, parametrisierte Metadaten-Abfragen und SP-Aufruf | 2026-10-08 | a082e9d |
| I5 | Typmapping-Datentreue: `DECIMAL(p,s)` aus Precision/Scale; Hauptskript nutzt Modulfunktionen (Typmapping, Strategie) | 2026-10-08 | 2d1a7ef |
| I9 | Scheduled-Task-Setup parametrisiert (neutrale Defaults, `-WhatIf`, Dienstkonto/gMSA); keine internen Begriffe mehr im Repo | 2026-10-08 | 438dd57 |
| I6 | Konfig gegen `config.schema.json` geprüft (Fail-Fast), gemeinsame Pfadauflösung, `-ConfigFile` für Hilfsskripte | 2026-10-09 | c5f94f0 |
| I7 | Treiber-Integrität: SHA-256-Prüfung jeder DLL vor dem Laden, Ausnahme nur über `Firebird.DllSha256` | 2026-10-09 | e173ac2 |
| I11 | Rollout-Check: `Test-SQLSyncConnections.ps1 -PreDeploy` (Konfigs, Treiber-Hash, Firebird-CVEs/SYSDBA, `decimal`-Altbestand), rein lesend | 2026-10-09 | 89e4565 |
| I8 | Wasserzeichen mit Überlappungsfenster (`General.IncrementalOverlapMinutes`), Extrakt als Modulfunktionen, kein stiller Vollabzug | 2026-10-09 | ab1de66 |
| I10b | CI auf GitHub Actions: Pester + PSScriptAnalyzer (nur `Error` blockiert) bei Push auf `main`/PR, Action per SHA gepinnt | 2026-10-09 | f7423b3 |
| I10a | Rollout-Check-Erweiterung: `-PreDeploy` mit Schema-Drift (K6/K10), Klartext-Passwort- und `.bak`-Warnung; Backup-Rotation in `Manage_Config_Tables.ps1` | 2026-10-10 | wird nachgetragen |

---

## Offene Punkte

| # | Beschreibung | Priorität |
|---|-------------|-----------|
| I10c | Doku-Konsolidierung (Exit-Code-Quelle, ID-Systeme, copilot-instructions, `README_alternativ.md`) | Niedrig |
| I10d | Modul-Aufräumen (`MSSQL.Port`, `Protect-SqlString`, Analyzer-Warnungen der Connection-String-Builder) | Niedrig |

---

## Risiken & Blocker

| Risiko / Blocker | Auswirkung | Mitigation / Nächster Schritt | Owner | Status |
|---|---|---|---|---|
| Firebird-Server < 5.0.4 von CVE-2026-34232 (unauthentifizierter Absturz, CVSS 7.5) und CVE-2026-40342 (Codeausführung über `CREATE FUNCTION`, CVSS 9.9) betroffen; mindestens ein intern eingesetzter Server betroffen (Hosts/Versionen nur in `docs/local/ENVIRONMENT.md`) | Absturz von ERP und Sync; bei Sync-Konto mit `CREATE FUNCTION`-Recht (z. B. SYSDBA) macht ein Credential-Leak Codeausführung auf dem Datenbankserver möglich | Firebird-Server auf ≥ 5.0.4 aktualisieren (Server-Betrieb); Port 3050 per Firewall einschränken; für den Sync ein reines Lesekonto statt SYSDBA anlegen (`security/THREAT_MODEL.md`) | Betreiber Firebird-Server | offen |
| Stand v2.18 (auf `main`) noch nicht auf dem produktiven Sync-Server | Dort bleiben fehlgeschlagene Tabellen unbemerkt (Exit 0), Identifier, Konfig und Treiber-DLL ungeprüft | Auf `main` gemergt (PR #1, 2026-10-09); deployen nach `operations/DEPLOYMENT.md`, Prüfungen ab I11 per `Test-SQLSyncConnections.ps1 -PreDeploy`; vorher produktive Konfigs mit `Get-SQLSyncConfig` prüfen (neue Namensregeln); Tasks nur bei Bedarf neu anlegen – dann Installationsordner und Konfignamen explizit übergeben (Aufruf in `docs/local/ENVIRONMENT.md`); seit v2.18 enden Tabellen, deren Zeitstempelspalte im Ziel fehlt, mit „Fehler" (Exit 10) statt stillem Vollabzug — erste Läufe nach dem Deployment beobachten | Betreiber | offen |
| Neue Exit-Codes 10/11 lassen Tasks „fehlschlagen", die bisher „erfolgreich" waren | Häufige Sanity-„FEHLER" bei laufenden Schreibzugriffen in Firebird (Zählung nach dem Merge) könnten Fehlalarme auslösen | Nach Deployment Task-Historie beobachten; bei Fehlalarmen `FailOnSanityError: false` im Daily-Profil | Betreiber | offen |
| Altbestand: vor v2.14 angelegte Zieltabellen haben `DECIMAL(18,4)` und runden weiter (der Sync ändert keine bestehenden Tabellen) | Nachkommastellen > 4 im Ziel weiterhin gerundet | Nach Deployment betroffene Spalten prüfen und Zieltabellen anpassen bzw. neu aufbauen (`operations/RUNBOOK.md`) | Betreiber | offen |
| Einstiegsskripte ohne Unit-Tests | SQL-Ablauf im Hauptskript ist nur per Integrationslauf prüfbar (Typmapping/Strategie seit I5, Wasserzeichen/Extrakt-Abfrage seit I8 im Modul getestet) | Integrationslauf gegen die Testumgebung; weitere Zerlegung in Modulfunktionen im Backlog | Maintainer | offen |
| Klartext-Passwort-Fallback in `config.json` / `*.bak` | Credential-Leak bei Dateizugriff | Credential Manager nutzen (`Setup_Credentials.ps1`), Passwörter aus `config.json` entfernen; seit I10a warnt `-PreDeploy` bei Klartext-Passwörtern und vorhandenen Backups, `Manage_Config_Tables.ps1` rotiert Backups (`-KeepBackups`); Klartext-Fallback im Code bleibt (Backlog) | Betreiber | offen |
