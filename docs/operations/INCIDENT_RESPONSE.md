# Incident Response – PSFirebirdToMSSQL

Was zu tun ist, wenn ein Sicherheitsvorfall, ein kritischer Bug oder ein Datenverlust eintritt.
Vor Eskalation lesen, nicht erst während der Krise.

Verbindet sich mit `security/THREAT_MODEL.md`, `operations/SECRETS_MANAGEMENT.md`,
`operations/RUNBOOK.md`, `operations/MONITORING.md` und `operations/TASK_SCHEDULER.md`.

**Wichtige Vorbemerkung:** Seit Sync-Version 2.11 (Inkrement I2) endet der Sync bei mindestens
einer fehlgeschlagenen Tabelle mit Exit-Code `10` (Task Scheduler `0xA`) und bei Sanity `FEHLER`
mit `11` (`0xB`, abschaltbar per `General.FailOnSanityError`); SP-Batch-Fehler brechen den
Pre-Flight mit `9` ab. `LastTaskResult` ist damit ein brauchbares Erstsignal (abgenommen am
2026-10-08: echter Lauf mit Exit `10`, Aufgabenplanung zeigte `0xA`). Grenze: Sanity
`WARNUNG (+n)` bleibt Exit `0`. Für Ursache und betroffene Tabellen bleibt
das Log `Logs\Sync_<ConfigName>_<yyyy-MM-dd_HHmm>.log` maßgeblich (Zeile `ERGEBNIS:`,
Spalten `Status`, `Sanity`).

---

## Klassifizierung

| Stufe | Definition | Beispiele (projektbezogen) | Reaktionsfenster |
|---|---|---|---|
| **P0 – Kritisch** | Datenleck, Credential-Kompromittierung, Datenverlust im Ziel | Passwort aus `config.json`/`*.bak`/Log im öffentlichen Repo oder auf einem Share gefunden; nachweislich manipulierte Treiber-DLL in `%ProgramData%\SQLSync\Drivers\...` oder `DllPath`; Codeausführung auf dem Firebird-Server über das Sync-Konto (CVE-2026-40342); Zieltabellen geleert/gedroppt (z. B. durch manipulierte Konfig, Identifier-Injection Bedrohung 1); Zieldaten mit personenbezogenen Daten für Unbefugte lesbar | sofort |
| **P1 – Hoch** | Sync fällt für alle oder kritische Tabellen aus, oder Zieldaten nachweislich falsch | `SHA-256 der Treiber-DLL … stimmt nicht` (Exit 7) – möglicher Manipulationsversuch, bis zur Klärung als Sicherheitsvorfall behandeln (bestätigt → P0); Abbruch mit Exit-Code 2/5/7/9; Exit 10 für alle bzw. kritische Tabellen; Credential-Eintrag fehlt nach Kontowechsel (Exit 5); Task läuft nicht mehr (Windows-Passwort abgelaufen); Sanity `FEHLER` (Ziel hat weniger Zeilen als Quelle, Exit 11); Nachkommastellen gerundet (K2, Zieltabellen aus v2.13 oder älter; `operations/RUNBOOK.md`) | < 2 Stunden |
| **P2 – Mittel** | Einzelne Tabellen fehlerhaft oder verspätet, kein Sicherheitsrisiko | Einzelne Tabelle mit Status `Fehler` nach allen Retries (Exit 10); Sanity `WARNUNG` (+n, z. B. nicht replizierte Löschungen); Schema-Drift (neue Spalte in Firebird, K6); Laufzeit überschreitet 30-Minuten-Takt | < 24 Stunden |
| **P3 – Niedrig** | Kosmetisch / nicht blockierend | Veraltete Doku; Schönheitsfehler in Konsolenausgaben | Backlog |

---

## Vorgehen (5 Phasen)

### 1. Eindämmen (Contain)

Ziel: weiteren Schaden verhindern, Beweise sichern. Erst danach analysieren.

- **Weitere Läufe stoppen:** beide Tasks deaktivieren –
  `Disable-ScheduledTask -TaskName SQLSync_Firebird_Daily_Diff` und
  `Disable-ScheduledTask -TaskName SQLSync_Firebird_Weekly_Full`. Laufende Instanz ggf. mit
  `Stop-ScheduledTask` beenden. (Verhindert u. a., dass der Weekly-Full-Lauf mit `ForceFullSync`
  Zieltabellen per `TRUNCATE` leert, bevor die Ursache bekannt ist.)
- **Credential-Leak:** betroffenes Firebird-/SQL-Passwort **sofort** auf dem Datenbankserver ändern
  oder Konto sperren, dann Credential-Manager-Eintrag neu setzen (siehe
  `SECRETS_MANAGEMENT.md` → Rotation). Bei Leak im Git-Repo: Rotation vor Historienbereinigung.
- **Verdacht auf manipulierte DLL oder Konfig:** Dateien nicht löschen, sondern Hash sichern
  (`Get-FileHash ... -Algorithm SHA256`) und Kopie mit Zeitstempeln wegsichern; Hash der Treiber-DLL
  mit den Sollwerten in `docs/security/DEPENDENCY_AUDIT.md` vergleichen.
- **Hash-Abweichung der Treiber-DLL** (`SHA-256 der Treiber-DLL (vorhanden) stimmt nicht …`, Exit 7):
  Der Sync hat die DLL **nicht** geladen und keine Verbindung aufgebaut – der Schutz hat gegriffen,
  die Ursache ist aber offen (P1). Die gemeldete Datei (Pfad steht in der Meldung) samt Zeitstempeln,
  Besitzer (`Get-Acl`) und Hash wegsichern, **bevor** der Treiberordner gelöscht und neu geladen wird;
  `icacls "$env:ProgramData\SQLSync\Drivers"` dokumentieren. Klären, wer Schreibzugriff hatte und
  ob eine bewusste Treiberänderung vorlag. Den erhaltenen Hash **nicht** als `Firebird.DllSha256`
  übernehmen. Wiederherstellung: `operations/RUNBOOK.md`, „SHA-256 der Treiber-DLL … stimmt nicht“.
- **Logs sichern,** bevor die nächste Log-Rotation (`DeleteLogOlderThanDays`) sie löscht:
  `Logs\` und die betroffene Konfigurationsdatei kopieren.
- **Zieldaten:** Bei Verdacht auf Datenverlust keine weiteren Full-Läufe; DB-Backup des Ziels
  durch den DB-Betrieb sichern lassen.
- Bei P0: weitere Personen benachrichtigen (siehe Eskalationspfad unten).

### 2. Bewerten (Assess)

- **Was ist betroffen?** Welche Tabellen (Zusammenfassung im Log), welche Daten (personenbezogen?),
  welche Konfigdatei/welches Job-Profil, welches Konto?
- **Wann hat es begonnen?** Logs nach Datum durchsuchen, z. B.
  `Select-String -Path .\Logs\Sync_*.log -Pattern 'Fehler|FEHLER|WARNUNG'`; Verlauf im Task
  Scheduler (Ereignisanzeige *Microsoft-Windows-TaskScheduler/Operational*).
- **Welcher Vektor?** Abgleich mit `security/THREAT_MODEL.md` (Bedrohungen 1–6) und
  `KNOWN_ISSUES.md` (K-IDs).
- **Diagnose:** `.\Test-SQLSyncConnections.ps1 -ConfigFile <Konfig>` (Exit 0 = Verbindungen und
  `sp_Merge_Generic` OK).
- **Wer muss informiert werden?** Intern (ERP-/DB-Betrieb, Nutzer der Ziel-DB), bei
  personenbezogenen Daten Datenschutz.

Output: kurzer Status (1 Absatz), an Eskalationsstelle übergeben.

### 3. Kommunizieren (Communicate)

- **Intern zuerst.** Nutzer der Ziel-DB (Reporting/BI) informieren, dass Daten ab Zeitpunkt X
  unvollständig oder veraltet sein können.
- **Faktentreu.** Was wir wissen, was wir nicht wissen, was wir gerade tun. Keine Spekulation.
- **Extern nur abgestimmt.** Bei Verletzung des Schutzes personenbezogener Daten (z. B. Ziel-DB
  mit Kunden-/Lieferantendaten für Unbefugte zugänglich): Meldepflicht innerhalb von 72 h an die
  Datenschutzbehörde (Art. 33 DSGVO) über den Datenschutzbeauftragten; siehe
  `security/DATA_HANDLING.md`.

### 4. Beheben (Eradicate & Recover)

- Wurzelursache fixen, nicht nur Symptom (Code-Fix, Konfigurations-Härtung, Rechte entziehen,
  Treiber-DLL aus offizieller Quelle neu laden – Verzeichnis löschen und Sync einmalig als Admin
  starten, damit Download + SHA-256-Prüfung greifen).
- **Wiederherstellung der Zieldaten:** Ein Lauf mit einem Full-Profil (`ForceFullSync: true`,
  ggf. `RecreateStagingTable: true`) baut Zieltabellen aus Firebird neu auf. Firebird ist die
  führende Quelle; ein Restore des Ziels ist nur nötig, wenn das Ziel zusätzliche Daten enthält.
- **Verifikation:** Sanity Check in der Zusammenfassung muss für alle Tabellen `OK` zeigen; Task
  danach wieder aktivieren (`Enable-ScheduledTask`).
- Monitoring für die nächsten 24–72 h intensivieren (`LastTaskResult` jedes Laufs prüfen, bei
  ≠ `0x0` sowie stichprobenartig bei `0x0` das Lauf-Log).

### 5. Post-Mortem

Innerhalb von 5 Werktagen nach P0/P1-Vorfall:

- **Zeitleiste:** wer hat wann was bemerkt / getan.
- **Wurzelursache:** technisch + prozessual (5-Why-Analyse). Besonders: Warum wurde es nicht
  früher bemerkt (K1; wurde `LastTaskResult` ausgewertet)?
- **Lessons Learned:** Einträge in `LESSONS_LEARNED.md` und `CHANGELOG.md`.
- **Maßnahmen:** konkrete TODO-Punkte (Inkrement-IDs in `TODO.md`) oder ADRs.
- **Update Threat Model:** falls die Bedrohung neu ist → Eintrag in `security/THREAT_MODEL.md`.

---

## Eskalationspfad

Konkrete Personen/Rollen sind im Projekt nicht hinterlegt (offen – vom Betreiber zu ergänzen).

| Vorfall-Stufe | Wer wird wann benachrichtigt |
|---|---|
| P0 | Projektverantwortlicher (Maintainer des Repos) und IT-Leitung sofort; bei personenbezogenen Daten Datenschutzbeauftragter; bei Credential-Leak zusätzlich ERP-/DB-Administration |
| P1 | Projektverantwortlicher und DB-Administration innerhalb 1 Stunde; Nutzer der Ziel-DB informieren |
| P2 | Im nächsten regulären Abstimmungstermin |
| P3 | Backlog-Eintrag, keine Sonder-Eskalation |

---

## Checkliste für die ersten 15 Minuten bei P0/P1

- [ ] Scheduled Tasks deaktiviert / laufende Instanz gestoppt?
- [ ] Bei Credential-Leak: Passwort auf DB-Server geändert / Konto gesperrt?
- [ ] Logs (`Logs\`), betroffene Konfigdatei und ggf. DLL-Hash gesichert?
- [ ] Eskalation losgeschickt?
- [ ] Zeitstempel des Beginns notiert (erster fehlerhafter Lauf-Log)?
- [ ] Aktuell aktive Personen kennen jeweils ihren Teil-Auftrag?

---

## Pflege

Trigger: nach jedem P0/P1-Vorfall Post-Mortem-Hinweis hier integrieren, falls generalisierbar
(z. B. Eskalationsweg ändert sich).
