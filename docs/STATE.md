# Aktueller Projektstatus – PSFirebirdToMSSQL

Zuletzt aktualisiert: 2026-10-09
**Initialisiert mit:** docs_template v26
**Letztes abgeschlossenes Inkrement:** I6 – Config-Schema-Validierung (2026-10-09)
**Nächster Schritt:** Reflexion (Phase 1c), danach I7 – Treiber-Integrität
**Nächste Reflexion:** bei Abschluss von I6 (siehe `KICKOFF.md` Phase 1c → `docs/REFLECTION.md` — `docs/`-Drift prüfen + Template-Backport prüfen; danach Marker um 3 erhöhen)
**Nächster Security-Sweep:** 2026-10-22 (Intervall 14 Tage; siehe `KICKOFF.md` Phase 1 Punkt 4a → `docs/principles/SECURITY_CURRENCY.md` — fällig, sobald heute ≥ diesem Datum; nach dem Sweep Marker = Sweep-Datum + 14 Tage)

---

## Nächster Schritt

**Reflexion (Phase 1c, fällig nach I6), danach I7 – Treiber-Integrität.** `Initialize-FirebirdDriver`
prüft SHA-256 bisher nur beim Download; eine vorhandene oder per `DllPath` konfigurierte DLL wird
ungeprüft geladen. Dafür den inneren Admin-Check als mockbare Modulfunktion herausziehen (macht auch
den Download-/Hash-Pfad unit-testbar).

Testumgebung für Integrationsläufe: Quelle Firebird-Testserver / Demo-Datenbank, Ziel SQL-Testserver /
`STAGING_I2TEST` (wird vom Pre-Flight bei Bedarf angelegt), Credential-Eintrag
`SQLSync_MSSQL_sqltest`, Konfigs `config_i2test_ok.json`, `config_i2test_fehler.json`,
`config_i4test_incr.json` (gitignored, Log-Rotation darin aus). Aufräumen, wenn nicht mehr
gebraucht: Datenbank `STAGING_I2TEST` auf SQL-Testserver und Test-Task `SQLSync_I2_Abnahme`.

Code-Stand: Sync-Skript v2.15 (Schema-Prüfung Fail-Fast; Typmapping mit Precision/Scale), `Setup-ScheduledTasks.ps1` parametrisiert (I9) (Exit-Codes 0/1/2/5/7/9/10/11; Identifier-Whitelist, durchgängig
gequotet/parametrisiert), optionale Konfigschlüssel `General.FailOnSanityError`,
`MSSQL.CredentialTarget`, `Firebird.CredentialTarget`; Unit-Tests unter `tests/` (130,
Coverage-Gate 80 %); keine CI.

---

## Abgeschlossene Inkremente

| # | Titel | Datum | Commit |
|---|-------|-------|--------|
| I1 | docs/ initialisiert (Stack `powershell-automation`, keine Overlays) | 2026-10-08 | a082e9d |
| I2 | Fehlschläge sichtbar machen: Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; konfigurierbare Credential-Targets | 2026-10-08 | a082e9d |
| I3 | Pester-Testharness: 74 Unit-Tests für alle exportierten Modulfunktionen, Pester 5.7.1 gepinnt, Coverage-Gate 80 % | 2026-10-08 | a082e9d |
| I4 | SQL-Identifier gehärtet: Whitelist-Validierung (Fail-Fast), `[...]`/`QUOTENAME` überall, parametrisierte Metadaten-Abfragen und SP-Aufruf | 2026-10-08 | a082e9d |
| I5 | Typmapping-Datentreue: `DECIMAL(p,s)` aus Precision/Scale; Hauptskript nutzt Modulfunktionen (Typmapping, Strategie) | 2026-10-08 | 2d1a7ef |
| I6 | Konfig gegen `config.schema.json` geprüft (Fail-Fast), gemeinsame Pfadauflösung, `-ConfigFile` für Hilfsskripte | 2026-10-09 | wird nachgetragen |
| I9 | Scheduled-Task-Setup parametrisiert (neutrale Defaults, `-WhatIf`, Dienstkonto/gMSA); keine internen Begriffe mehr im Repo | 2026-10-08 | 438dd57 |

---

## Offene Punkte

| # | Beschreibung | Priorität |
|---|-------------|-----------|
| I7 | Treiber-Integrität: SHA-256-Prüfung auch für vorhandene/konfigurierte DLL | Mittel |
| I8 | Inkrementelles Wasserzeichen mit Überlappungsfenster | Mittel |
| I10 | Doku-/Repo-Drift beheben (copilot-instructions, READMEs, Kleinigkeiten) | Niedrig |

---

## Risiken & Blocker

| Risiko / Blocker | Auswirkung | Mitigation / Nächster Schritt | Owner | Status |
|---|---|---|---|---|
| Firebird-Server < 5.0.4 von CVE-2026-34232 betroffen (unauthentifizierter Absturz, CVSS 7.5); mindestens ein intern eingesetzter Server betroffen (Hosts/Versionen nur in `docs/local/ENVIRONMENT.md`) | Jeder, der Port 3050 erreicht, kann den Firebird-Server zum Absturz bringen → ERP und Sync stehen | Firebird-Server auf ≥ 5.0.4 aktualisieren (Server-Betrieb, außerhalb dieses Repos); Port 3050 per Firewall auf nötige Hosts beschränken; Details `security/DEPENDENCY_AUDIT.md` | Betreiber Firebird-Server | offen |
| v2.12 noch nicht auf dem produktiven Sync-Server | Dort bleiben fehlgeschlagene Tabellen unbemerkt (Exit 0), Identifier ungeprüft | Branch `docs/i1-baseline` mergen und deployen (`operations/DEPLOYMENT.md`); vorher produktive Konfigs mit `Get-SQLSyncConfig` prüfen (neue Namensregeln); Tasks nur bei Bedarf neu anlegen – dann Installationsordner und Konfignamen explizit übergeben (Aufruf in `docs/local/ENVIRONMENT.md`) | Betreiber | offen |
| Neue Exit-Codes 10/11 lassen Tasks „fehlschlagen", die bisher „erfolgreich" waren | Häufige Sanity-„FEHLER" bei laufenden Schreibzugriffen in Firebird (Zählung nach dem Merge) könnten Fehlalarme auslösen | Nach Deployment Task-Historie beobachten; bei Fehlalarmen `FailOnSanityError: false` im Daily-Profil | Betreiber | offen |
| Altbestand: vor v2.14 angelegte Zieltabellen haben `DECIMAL(18,4)` und runden weiter (der Sync ändert keine bestehenden Tabellen) | Nachkommastellen > 4 im Ziel weiterhin gerundet | Nach Deployment betroffene Spalten prüfen und Zieltabellen anpassen bzw. neu aufbauen (`operations/RUNBOOK.md`) | Betreiber | offen |
| Einstiegsskripte ohne Unit-Tests | SQL-Ablauf im Hauptskript ist nur per Integrationslauf prüfbar (Typmapping/Strategie seit I5 im Modul getestet) | Integrationslauf gegen die Testumgebung; Zerlegung in Modulfunktionen im Backlog | Maintainer | offen |
| Klartext-Passwort-Fallback in `config.json` / `*.bak` | Credential-Leak bei Dateizugriff | Credential Manager nutzen (`Setup_Credentials.ps1`), Passwörter aus `config.json` entfernen; Klartext-Fallback im Code bleibt (Backlog) | Betreiber | offen |
