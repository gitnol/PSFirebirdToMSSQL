# Logging Strategy

## Regel

Logs sind das einzige Fenster in den Systemzustand eines laufenden Prozesses.
Jeder Log-Eintrag muss ohne Kontextwissen verstaendlich und filterbar sein.

## Konkrete Vorgaben

- **Level DEBUG:** Detaillierter Datenfluss (z.B. "Datei X gelesen, Hash: Y")
- **Level INFO:** Fachliche Meilensteine (z.B. "Dokument X erfolgreich verarbeitet")
- **Level WARNING:** Erwartete, aber behandelte Probleme (z.B. "Service Timeout, Versuch 1/3")
- **Level ERROR:** Unerwartete Fehler – muss zwingend den Stacktrace enthalten (`exc_info=True`)
- **Kontext:** Jeder Eintrag muss IDs, Dateinamen oder Bezeichner enthalten.
  "Verarbeitung fehlgeschlagen" ist verboten.
  "Verarbeitung fuer Datei 'X.pdf' fehlgeschlagen" ist korrekt.
- Konsolenausgaben ueber `print()` sind fuer interaktive CLI-Tools akzeptabel.
  Bei automatisiertem Betrieb (Scheduler, Service) muss das Logging-Framework verwendet werden.

## Projektspezifisch

<!-- Hier beim Befüllen ersetzen. Maßgeblich für die Update-Klassifizierung ist
     der Vergleich gegen die alte Template-Version (ALTES_PROJECT_AKTUALISIEREN.md,
     Schritt 2c/3): LOGGING.md ist konstruktionsbedingt immer Kategorie C. -->


- **Mechanismus:** Kein Logging-Framework, kein `Write-EventLog`. Ausgaben per `Write-Host`
  (farbcodiert, u. a. `Write-SyncStatus -Level Info|Success|Warning|Error` in `SQLSyncCommon.psm1`)
  und `Write-Warning`; das Hauptskript `Sync_Firebird_MSSQL_AutoSchema.ps1` schreibt alles per
  `Start-Transcript` mit. Grund: einfacher Betrieb als geplanter Task ohne Zusatzmodule.
  Abweichung von der Regel oben (Logging-Framework bei Scheduler-Betrieb) ist bewusst; die
  Transcript-Datei ist das Betriebslog.
- **DEBUG-Modus:** nicht vorhanden. Es gibt keinen Schalter für ausführlichere Ausgaben.
- **Nicht loggen:** Passwörter und vollständige Connection-Strings. Ausgegeben werden nur
  Server/Datenbank/Port bzw. `IntegratedSecurity` sowie die Credential-Quelle
  („Credential Manager" / „config.json (WARNUNG: unsicher!)"). Die ERP-Tabellen können
  Personendaten (Kunden/Lieferanten) enthalten — Datenzeilen werden nicht geloggt, nur Zähler.
- **Ziel:** Konsole + Transcript-Datei `Logs\Sync_<Konfigname>_<yyyy-MM-dd_HHmm>.log` im
  Skriptordner; Rotation über `DeleteLogOlderThanDays` (Default 30, 0 = aus). Kein Event Log,
  kein strukturiertes Ergebnis (JSON/CSV) für Monitoring (Backlog). Seit I2 sind fehlgeschlagene
  Tabellen auch am Exit-Code erkennbar (`10`, Sanity `FEHLER` → `11`); das Log nennt sie in der
  abschließenden Zeile `ERGEBNIS: FEHLER (Exit-Code N) - betroffene Tabellen: …` und bleibt die
  Quelle für Ursachen.
