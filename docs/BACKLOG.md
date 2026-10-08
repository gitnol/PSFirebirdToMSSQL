# Backlog – PSFirebirdToMSSQL

Parkplatz für Ideen, Verbesserungen und Aufgaben, die noch **nicht** für ein
konkretes Inkrement priorisiert sind.

**Abgrenzung:**

- `TODO.md` = aktuelle, priorisierte Arbeit mit Definition of Done
- `BACKLOG.md` = noch nicht eingeplant, kein DoD nötig
- `KNOWN_ISSUES.md` = bekannte Probleme mit Workaround, nicht aktiv geplant

Wenn ein Backlog-Punkt für ein Inkrement vorgesehen wird → Verschiebung von
`BACKLOG.md` nach `TODO.md` (mit DoD ergänzen).

---

## Ideen / Features

- Strukturiertes Laufergebnis (JSON/CSV je Lauf neben dem Transcript) — maschinenlesbar für Monitoring/Dashboards; heute nur `Format-Table` im Transcript
- Schema-Drift-Erkennung (`KNOWN_ISSUES.md` K6) — neue Firebird-Spalten erkennen und `ALTER TABLE ... ADD` für Staging und Ziel vorschlagen bzw. ausführen
- Orphan-Cleanup für nicht-numerische IDs (`KNOWN_ISSUES.md` K5) — Typ der Temp-Tabelle aus der Zielspalte ableiten
- CI mit GitHub Actions: PSScriptAnalyzer + Pester auf `windows-latest` — Voraussetzung (Pester-Harness, I3) erfüllt; Testlauf: `tests/pester.config.ps1`
- Overlay `compliance-tisax` prüfen — falls die replizierten ERP-Daten (Kunden, Lieferanten, Personen) im TISAX-Scope des Betreibers liegen

---

## Refactoring-Kandidaten

- Hauptskript in Modulfunktionen zerlegen (`Invoke-TableSync`, `Invoke-PreFlight`) — 743 Zeilen in einer Datei, Logik nur schwer testbar; Aufnahme nach I3/I5
- Ungenutzte/teilweise genutzte Exporte prüfen (`Write-SyncStatus`, `Close-DatabaseConnection`, `Protect-SqlString`) — werden vom Hauptskript nicht verwendet; `Protect-SqlString` seit v2.12 von keinem Skript mehr (ersetzt durch `Assert-SqlIdentifier`)
- Wiederholter Code in `Setup_Credentials.ps1` (Firebird/MSSQL-Blöcke identisch) in eine Funktion ziehen

---

## Technische Schuld

- Doku-Duplikate (Reflexion nach I3) — die Exit-Code-Tabelle steht in `README.md`, `README.de.md`, `features/firebird-mssql-sync.md`, `operations/MONITORING.md` und `architecture/ERROR_HANDLING.md`; jede Änderung zieht 10–15 Doku-Dateien nach sich. Single Source: `architecture/ERROR_HANDLING.md`, übrige `docs/`-Stellen nur verlinken (READMEs behalten ihre Nutzer-Tabelle). Kandidat für I10.
- Drei parallele ID-Systeme (S = Schwachstellen-Katalog, K = bekannte Probleme, I = Inkremente) — erhöht Pflegeaufwand; bei I10 prüfen, ob S-IDs in K/I aufgehen können.

- `System.Data.SqlClient` → `Microsoft.Data.SqlClient` — Microsoft hat `System.Data.SqlClient` abgekündigt; wird teurer, sobald eine PowerShell-Version das Paket nicht mehr mitliefert
- Firebird-Treiber-Version 10.3.4 fest im Code inkl. Hash — Updates erfordern Codeänderung; Ablauf in `security/DEPENDENCY_AUDIT.md`
- Bereinigung alter `config.json.*.bak`-Dateien fehlt — Backups (ggf. mit Passwörtern) sammeln sich unbegrenzt an

---

## Template-Evolution / Stack-Lücken

Hier landen Projekt-Charakteristiken, für die kein passender Stack/Overlay
existierte. Jeder Eintrag ist eine potenzielle Template-Erweiterung — so sind
z.B. `react-web` und die DI-Overlays entstanden.

- (keine) — Stack `powershell-automation` passt; die Datenbank-Seite (zwei DB-Systeme,
  Staging/MERGE) ist dort nur über `testing/INTEGRATION_TESTS.md` abgedeckt. Kandidat für
  das Template: conditional `architecture/DATABASE.md` auch für `powershell-automation`
  (existiert bereits für `python-cli`/`python-api`/`csharp-aspnet`) — 2026-10-08 PSFirebirdToMSSQL

---

## Verworfen (mit Begründung)

Punkte, die geprüft und bewusst nicht weiterverfolgt wurden. Bleiben als Spur
sichtbar, damit derselbe Punkt nicht in jeder Session erneut diskutiert wird.

- ~~Löschungen live per `WHEN NOT MATCHED BY SOURCE THEN DELETE` im MERGE~~ — vor 2026-10-08 (Kommentar in `sql_server_setup.sql`): im Delta-Modus enthält das Staging nur geänderte Zeilen, das MERGE würde alle übrigen Zieldaten löschen
