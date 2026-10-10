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
- Schema-Drift (`KNOWN_ISSUES.md` K6) — Erkennung eingeplant in I10a (`-PreDeploy`); offen bleibt `ALTER TABLE ... ADD` für Staging und Ziel vorschlagen bzw. ausführen
- Orphan-Cleanup für nicht-numerische IDs (`KNOWN_ISSUES.md` K5) — Typ der Temp-Tabelle aus der Zielspalte ableiten
- Overlay `compliance-tisax` prüfen — falls die replizierten ERP-Daten (Kunden, Lieferanten, Personen) im TISAX-Scope des Betreibers liegen

---

## Refactoring-Kandidaten

- Hauptskript in Modulfunktionen zerlegen (`Invoke-TableSync`, `Invoke-PreFlight`) — 743 Zeilen in einer Datei, Logik nur schwer testbar; Aufnahme nach I3/I5
- Ungenutzte/teilweise genutzte Exporte prüfen (nicht exportierte Helfer `Invoke-With…Connection` seit 2026-10-09 entfernt; `Write-SyncStatus`, `Close-DatabaseConnection`, `Protect-SqlString`) — werden vom Hauptskript nicht verwendet; `Protect-SqlString` seit v2.12 von keinem Skript mehr (ersetzt durch `Assert-SqlIdentifier`) — eingeplant in I10d
- Wiederholter Code in `Setup_Credentials.ps1` (Firebird/MSSQL-Blöcke identisch) in eine Funktion ziehen

---

## Technische Schuld

- Doku-Duplikate (Reflexion nach I3) — die Exit-Code-Tabelle steht in `README.md`, `README.de.md`, `features/firebird-mssql-sync.md`, `operations/MONITORING.md` und `architecture/ERROR_HANDLING.md`; jede Änderung zieht 10–15 Doku-Dateien nach sich. Single Source: `architecture/ERROR_HANDLING.md`, übrige `docs/`-Stellen nur verlinken (READMEs behalten ihre Nutzer-Tabelle). Eingeplant in I10c.
- Drei parallele ID-Systeme (S = Schwachstellen-Katalog, K = bekannte Probleme, I = Inkremente) — erhöht Pflegeaufwand; in I10c prüfen, ob S-IDs in K/I aufgehen können.

- `System.Data.SqlClient` → `Microsoft.Data.SqlClient` — Microsoft hat `System.Data.SqlClient` abgekündigt; wird teurer, sobald eine PowerShell-Version das Paket nicht mehr mitliefert
- Firebird-Treiber-Version 10.3.4 fest im Code inkl. Hash — Updates erfordern Codeänderung; Ablauf in `security/DEPENDENCY_AUDIT.md`
- PSScriptAnalyzer-Warnungen (Stand I10b, 1.25.0; blockieren die CI nicht): 156 `PSAvoidUsingWriteHost` (Konsolen-Ausgabe der Einstiegsskripte, überwiegend gewollt), 20 `PSAvoidUsingEmptyCatchBlock` (u. a. `Close()`/`Dispose()` im `finally`), 12 `PSUseBOMForUnicodeEncodedFile` (Umlaute in UTF-8 ohne BOM; relevant nur für Windows PowerShell 5.1), 6 `PSUseShouldProcessForStateChangingFunctions`, 5 `PSReviewUnusedParameter` (Tests), 3 `PSUseDeclaredVarsMoreThanAssignments`, 3 `PSUseSingularNouns`, 2 `PSAvoidUsingPlainTextForPassword` (`New-*ConnectionString`) — gezielt abbauen, wenn die Datei ohnehin geändert wird
- Bereinigung alter `config.json.*.bak`-Dateien fehlt — Backups (ggf. mit Passwörtern) sammeln sich unbegrenzt an — eingeplant in I10a

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
