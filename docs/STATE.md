# Aktueller Projektstatus – PSFirebirdToMSSQL

Zuletzt aktualisiert: 2026-10-08
**Initialisiert mit:** docs_template v26
**Letztes abgeschlossenes Inkrement:** I4 – SQL-Identifier gehärtet (2026-10-08)
**Nächster Schritt:** I5 – Typmapping-Datentreue + Modulfunktionen im Hauptskript
**Nächste Reflexion:** bei Abschluss von I6 (siehe `KICKOFF.md` Phase 1c → `docs/REFLECTION.md` — `docs/`-Drift prüfen + Template-Backport prüfen; danach Marker um 3 erhöhen)
**Nächster Security-Sweep:** 2026-10-22 (Intervall 14 Tage; siehe `KICKOFF.md` Phase 1 Punkt 4a → `docs/principles/SECURITY_CURRENCY.md` — fällig, sobald heute ≥ diesem Datum; nach dem Sweep Marker = Sweep-Datum + 14 Tage)

---

## Nächster Schritt

**I5 – Typmapping-Datentreue.** `NUMERIC`/`DECIMAL` wird heute fest als `DECIMAL(18,4)` angelegt
(K2). `ConvertTo-SqlServerType` bekommt Precision/Scale aus dem Firebird-Schema, und das
Hauptskript nutzt `ConvertTo-SqlServerType` und `Get-TableColumnConfig` statt eigener
Inline-Logik (dafür das Modul im `-Parallel`-Block importieren). Tests zuerst; danach
Integrationslauf gegen die Testumgebung mit einer Tabelle mit `NUMERIC(x,y>4)`-Spalte.

Testumgebung für Integrationsläufe: Quelle Firebird-Testserver / Demo-Datenbank, Ziel SQL-Testserver /
`STAGING_I2TEST` (wird vom Pre-Flight bei Bedarf angelegt), Credential-Eintrag
`SQLSync_MSSQL_sqltest`, Konfigs `config_i2test_ok.json`, `config_i2test_fehler.json`,
`config_i4test_incr.json` (gitignored, Log-Rotation darin aus). Aufräumen, wenn nicht mehr
gebraucht: Datenbank `STAGING_I2TEST` auf SQL-Testserver und Test-Task `SQLSync_I2_Abnahme`.

Code-Stand: Sync-Skript v2.12 (Exit-Codes 0/1/2/5/7/9/10/11; Identifier-Whitelist, durchgängig
gequotet/parametrisiert), optionale Konfigschlüssel `General.FailOnSanityError`,
`MSSQL.CredentialTarget`, `Firebird.CredentialTarget`; Unit-Tests unter `tests/` (98,
Coverage-Gate 80 %); keine CI.

---

## Abgeschlossene Inkremente

| # | Titel | Datum | Commit |
|---|-------|-------|--------|
| I1 | docs/ initialisiert (Stack `powershell-automation`, keine Overlays) | 2026-10-08 | a082e9d |
| I2 | Fehlschläge sichtbar machen: Exit-Codes 10/11, Pre-Flight-Abbruch bei SP-Fehlern; konfigurierbare Credential-Targets | 2026-10-08 | a082e9d |
| I3 | Pester-Testharness: 74 Unit-Tests für alle exportierten Modulfunktionen, Pester 5.7.1 gepinnt, Coverage-Gate 80 % | 2026-10-08 | a082e9d |
| I4 | SQL-Identifier gehärtet: Whitelist-Validierung (Fail-Fast), `[...]`/`QUOTENAME` überall, parametrisierte Metadaten-Abfragen und SP-Aufruf | 2026-10-08 | a082e9d |

---

## Offene Punkte

| # | Beschreibung | Priorität |
|---|-------------|-----------|
| I5 | Typmapping-Datentreue (DECIMAL-Präzision) + Hauptskript nutzt Modulfunktionen | Hoch |
| I6 | Config-Schema-Validierung aktiv (Fail-Fast) + gemeinsame Configpfad-Auflösung | Mittel |
| I7 | Treiber-Integrität: SHA-256-Prüfung auch für vorhandene/konfigurierte DLL | Mittel |
| I8 | Inkrementelles Wasserzeichen mit Überlappungsfenster | Mittel |
| I9 | Scheduled-Task-Setup parametrisieren, interne Namen/Beispielwerte aus dem Repo entfernen | Mittel |
| I10 | Doku-/Repo-Drift beheben (copilot-instructions, READMEs, Kleinigkeiten) | Niedrig |

---

## Risiken & Blocker

| Risiko / Blocker | Auswirkung | Mitigation / Nächster Schritt | Owner | Status |
|---|---|---|---|---|
| Firebird-Server < 5.0.4 von CVE-2026-34232 betroffen (unauthentifizierter Absturz, CVSS 7.5); mindestens ein intern eingesetzter Server betroffen (Hosts/Versionen nur in `docs/local/ENVIRONMENT.md`) | Jeder, der Port 3050 erreicht, kann den Firebird-Server zum Absturz bringen → ERP und Sync stehen | Firebird-Server auf ≥ 5.0.4 aktualisieren (Server-Betrieb, außerhalb dieses Repos); Port 3050 per Firewall auf nötige Hosts beschränken; Details `security/DEPENDENCY_AUDIT.md` | Betreiber Firebird-Server | offen |
| v2.12 noch nicht auf dem produktiven Sync-Server | Dort bleiben fehlgeschlagene Tabellen unbemerkt (Exit 0), Identifier ungeprüft | Branch `docs/i1-baseline` mergen und deployen (`operations/DEPLOYMENT.md`); vorher produktive Konfigs mit `Get-SQLSyncConfig` prüfen (neue Namensregeln) | Betreiber | offen |
| Neue Exit-Codes 10/11 lassen Tasks „fehlschlagen", die bisher „erfolgreich" waren | Häufige Sanity-„FEHLER" bei laufenden Schreibzugriffen in Firebird (Zählung nach dem Merge) könnten Fehlalarme auslösen | Nach Deployment Task-Historie beobachten; bei Fehlalarmen `FailOnSanityError: false` im Daily-Profil | Betreiber | offen |
| Stiller Präzisionsverlust bei NUMERIC/DECIMAL mit Scale > 4 | Falsche Beträge/Mengen im Ziel ohne Fehlermeldung | I5; bis dahin betroffene Spalten per `Get_Firebird_Schema.ps1` prüfen | Maintainer | offen |
| Einstiegsskripte ohne Unit-Tests | Inline-Logik im Hauptskript (Typmapping, Strategie, SQL) ist nur per Integrationslauf prüfbar | I5/I6 ziehen Logik ins Modul; bis dahin Integrationslauf gegen die Testumgebung | Maintainer | offen |
| Klartext-Passwort-Fallback in `config.json` / `*.bak` | Credential-Leak bei Dateizugriff | Credential Manager nutzen (`Setup_Credentials.ps1`), Passwörter aus `config.json` entfernen; I9 | Betreiber | offen |
