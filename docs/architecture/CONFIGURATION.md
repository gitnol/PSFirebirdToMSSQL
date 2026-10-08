# Konfiguration – PSFirebirdToMSSQL

Wo Werte herkommen, in welcher Reihenfolge sie überschreiben, und wie sie
validiert werden. Verbindet sich mit den Prinzipien [[EXPLICIT_OVER_IMPLICIT]]
und [[FAIL_FAST]].

---

## Quellen-Hierarchie (Präzedenz, höchste zuerst)

1. **CLI-Argument `-ConfigFile`** (nur `Sync_Firebird_MSSQL_AutoSchema.ps1` und `Test-SQLSyncConnections.ps1`) —
   wählt **welche** JSON-Datei geladen wird, überschreibt aber keine einzelnen Schlüssel.
   Auflösung: existierender Pfad → `Convert-Path`; sonst Name relativ zum Skriptordner; sonst Pfad wie angegeben
   (führt dann zu „Konfigurationsdatei nicht gefunden"). Ohne Parameter: `config.json` im Skriptordner.
2. **Konfigurationsdatei (JSON)** — `config.json` bzw. ein Job-Profil wie `config_weekly_full.json`.
3. **Code-Defaults** in `Get-SQLSyncConfig` / `Get-ConfigValue` (`SQLSyncCommon.psm1`).

Nicht vorhanden: **Umgebungsvariablen** und **CLI-Overrides einzelner Schlüssel** gibt es nicht.
`Get_Firebird_Schema.ps1` und `Manage_Config_Tables.ps1` lesen fest `config.json` im Skriptordner (Inkrement I6).

Ein fehlender oder `null`-Schlüssel fällt auf den Code-Default zurück (`Get-ConfigValue`). Listen (`Tables`,
`TimestampColumns`) werden **ersetzt**, nicht ergänzt.

Job-Profile: Unterschiedliche Betriebsarten (z. B. „Daily Diff" alle 30 Min, „Weekly Full" mit `ForceFullSync` /
`RecreateStagingTable`) sind **eigene Konfigdateien**, die per `-ConfigFile` gewählt werden
(siehe `docs/operations/TASK_SCHEDULER.md`). Der Dateiname ohne Endung erscheint im Lognamen
`Logs\Sync_<ConfigName>_<yyyy-MM-dd_HHmm>.log`.

Credentials haben eine eigene Reihenfolge (Credential Manager vor `config.json`), siehe unten und
`docs/architecture/CREDENTIAL_STRATEGY.md`.

---

## Validierung beim Laden

`Get-SQLSyncConfig` wird einmal zu Beginn jedes Skripts aufgerufen und liefert eine Hashtable mit allen Werten
(inkl. `RawConfig` = das geparste JSON-Objekt für die Credential-Auflösung).

Tatsächlich geprüft (Fail-Fast per `throw`, im Sync-Skript → Exit-Code 2):

| Prüfung | Meldung |
|---|---|
| Datei existiert | `Konfigurationsdatei nicht gefunden: <Pfad>` |
| JSON parsebar | `Fehler beim Parsen der Konfiguration: …` |
| `General.GlobalTimeout > 0` | `GlobalTimeout muss größer als 0 sein.` |
| `Tables` vorhanden und nicht leer | `Keine Tabellen in der Konfiguration definiert.` |
| `General.OrphanCleanupBatchSize >= 1000` | `OrphanCleanupBatchSize muss mindestens 1000 sein.` |
| Namen nicht leer (außer wo leer erlaubt) | `Ungültiger Name in '<Feld>': leer.` |
| Namen höchstens 63 Zeichen (Firebird-Limit) | `Ungültiger Name in '<Feld>': '<Name>' ist länger als 63 Zeichen.` |
| Namen nur aus `A-Z`, `a-z`, `0-9`, `_`, `$` | `Ungültiger Name in '<Feld>': '<Name>' (erlaubt sind nur A-Z, a-z, 0-9, _ und $).` |
| Zieltabellenname `Prefix` + Tabelle + `Suffix` höchstens 128 Zeichen (SQL-Server-Limit) | `Ungültiger Name: Zieltabelle '<Name>' (MSSQL.Prefix + Tables + MSSQL.Suffix) ist länger als 128 Zeichen.` |

### Namensregeln (SQL-Identifier, seit v2.12)

Alle Namen, die in SQL-Text eingesetzt werden, prüft `Get-SQLSyncConfig` mit `Assert-SqlIdentifier`
(`SQLSyncCommon.psm1`) gegen die Allow-List `^[A-Za-z0-9_$]+$` (Groß-/Kleinschreibung wird exakt geprüft,
keine Umlaute, keine Leer-, Anführungs-, Klammer- oder Semikolonzeichen) und die Maximallänge 63:

| Feld | Leer erlaubt? |
|---|---|
| `Tables` (jeder Eintrag) | nein |
| `General.IdColumn` | nein |
| `General.TimestampColumns` (jeder Eintrag) | nein |
| `MSSQL.Database` | ja |
| `MSSQL.Prefix`, `MSSQL.Suffix` | ja |
| `TableOverrides`-Schlüssel (Tabellenname) | nein |
| `TableOverrides.<Tabelle>.IdColumn`, `.TimestampColumn` | ja (dann gilt der globale Wert) |

Der erste Verstoß bricht das Laden ab; das Sync-Skript endet mit Exit-Code 2, bevor eine Verbindung
aufgebaut wird. `<Feld>` in der Meldung nennt das betroffene Konfigurationsfeld (bei Overrides z. B.
`TableOverrides.BSA.IdColumn`). `Manage_Config_Tables.ps1` prüft `General.IdColumn`/`TimestampColumns`
genauso (Exit 2) und übernimmt Firebird-Tabellen mit ungültigem Namen nicht.

**Nicht geprüft** (bekannte Lücken):

- `config.schema.json` wird **nicht** ausgewertet: `Get-SQLSyncConfig` hat zwar `-SchemaPath`, kein Aufrufer übergibt ihn;
  zudem würde ein Schemafehler nur als Warnung gemeldet (Inkrement I6). Die Schema-Grenzen in der Tabelle unten sind daher
  **Soll-Werte**, keine Laufzeitprüfung.
- Pflichtfelder `Firebird.Server`, `Firebird.Database`, `MSSQL.Server`, `MSSQL.Database` werden nicht explizit geprüft —
  fehlen sie, scheitert erst der Verbindungsaufbau bzw. der Pre-Flight.
- Typen werden nicht konvertiert; ein String `"4"` statt `4` wird so weitergereicht.
- Die Hashtable ist **nicht** schreibgeschützt; das Sync-Skript kopiert die Werte jedoch nur in lokale Variablen und
  verändert sie nicht.

---

## Secrets gehören NICHT in normale Konfigurationsdateien

- Firebird- und SQL-Server-Passwörter gehören in den Windows Credential Manager (`Setup_Credentials.ps1`) oder es wird
  Windows-Authentifizierung (`MSSQL."Integrated Security": true`) genutzt.
- `Firebird.Password` / `MSSQL.Password` in der JSON-Datei sind ein **unsicherer Fallback**; bei Nutzung erscheint die
  Warnung `config.json (WARNUNG: unsicher!)`.
- `config*` (außer `config.sample.json`, `config.schema.json`) und `*.bak` sind per `.gitignore` ausgeschlossen;
  `Manage_Config_Tables.ps1` kopiert beim Backup auch ein eventuell enthaltenes Passwort mit.
- Details: `docs/operations/SECRETS_MANAGEMENT.md`, `docs/architecture/CREDENTIAL_STRATEGY.md`.

---

## Konfigurationsobjekt — Verwendung

- Das Sync-Skript lädt die Konfiguration **einmal** (Abschnitt 4) und überträgt die Werte in lokale Variablen;
  im Parallel-Block werden sie per `$using:` gelesen.
- Modulfunktionen erhalten Werte als Parameter (`New-FirebirdConnectionString -Server … -Port …`,
  `Initialize-FirebirdDriver -DllPath …`). Ausnahme: `Resolve-FirebirdCredentials` / `Resolve-MSSQLCredentials` bekommen
  das rohe JSON-Objekt (`RawConfig`).
- Werte werden zur Laufzeit nicht verändert.

---

## Konfigurations-Tabelle

Defaults aus `Get-SQLSyncConfig`; „Schema" = Grenzen aus `config.schema.json` (derzeit nicht erzwungen).
Quelle ist für alle Schlüssel die JSON-Datei (FILE); `-ConfigFile` wählt nur die Datei.

### `General`

| Schlüssel | Typ | Default | Quelle(n) | Beschreibung |
|---|---|---|---|---|
| `GlobalTimeout` | int (s) | `7200` | FILE | `CommandTimeout`/`BulkCopyTimeout` für SQL-Server-Befehle. Code: `> 0`; Schema: 60–86400 |
| `RecreateStagingTable` | bool | `false` | FILE | Staging-Tabelle `STG_<Tabelle>` vor dem Laden löschen und aus dem aktuellen Firebird-Schema neu anlegen |
| `ForceFullSync` | bool | `false` | FILE | Inkrementelle Tabellen voll laden: Zieltabelle `TRUNCATE`, danach `MERGE` aller Zeilen (Strategie „FullMerge (Forced)") |
| `RecreateStoredProcedure` | bool | `false` | FILE | `sp_Merge_Generic` im Pre-Flight immer neu aus `sql_server_setup.sql` installieren |
| `NumberOfThreads` | int | `4` | FILE | `-ThrottleLimit` der Parallel-Schleife (gleichzeitig verarbeitete Tabellen). Schema: 1–8 |
| `RunSanityCheck` | bool | `true` | FILE | Nach dem Sync `COUNT(*)` in Firebird und Ziel vergleichen (OK / WARNUNG (+n) / FEHLER (-n)) |
| `FailOnSanityError` | bool | `true` | FILE | Sanity `FEHLER (-n)` (Ziel hat weniger Zeilen) beendet den Sync mit Exit-Code `11`, sofern keine Tabelle `Fehler` hat (dann `10`). `false` = Sanity-Fehler nur im Log, Exit `0`. Ohne `RunSanityCheck` wirkungslos |
| `MaxRetries` | int | `3` | FILE | Zusätzliche Versuche pro Tabelle nach einem Fehler (insgesamt `MaxRetries + 1`). Schema: 0–10 |
| `RetryDelaySeconds` | int (s) | `10` | FILE | Wartezeit vor jedem Wiederholungsversuch. Schema: 1–300 |
| `DeleteLogOlderThanDays` | int (Tage) | `30` | FILE | Löscht `Logs\Sync_*.log` älter als n Tage; `0` = Rotation aus. Schema: 0–365 |
| `CleanupOrphans` | bool | `false` | FILE | Nach dem Merge Datensätze im Ziel löschen, deren ID in Firebird fehlt (nicht bei Snapshot / FullMerge (Forced)) |
| `OrphanCleanupBatchSize` | int | `50000` | FILE | Batchgröße beim Übertragen der Firebird-IDs in `#SourceIDs_<Tabelle>`. Code: `>= 1000`; Schema: 1000–500000 |
| `IdColumn` | string | `"ID"` | FILE | Globaler Name der ID-/Primärschlüsselspalte. Tabelle ohne diese Spalte → Strategie Snapshot. Code: Namensregeln (s. o.); Schema: `^[A-Z0-9_]+$` |
| `TimestampColumns` | string[] | `["GESPEICHERT"]` | FILE | Kandidaten für die Änderungszeitstempel-Spalte; die **erste** in der Tabelle vorhandene wird genutzt. Keine vorhanden → FullMerge. Code: Namensregeln (s. o.) |

### `Firebird`

| Schlüssel | Typ | Default | Quelle(n) | Beschreibung |
|---|---|---|---|---|
| `Server` | string | kein | FILE | Hostname/IP des Firebird-Servers (Schema: Pflicht) |
| `Database` | string | kein | FILE | Pfad zur `.FDB`-Datei auf dem Server (Schema: Pflicht, Endung `.fdb`/`.FDB`) |
| `Port` | int | `3050` | FILE | TCP-Port |
| `Charset` | string | `"UTF8"` | FILE | Verbindungs-Zeichensatz. Schema: `UTF8`, `ISO8859_1`, `WIN1252`, `NONE` |
| `DllPath` | string | kein | FILE | Optionaler Pfad zur Treiber-DLL (absolut oder relativ zum Skriptordner); hat Vorrang vor `%ProgramData%`. Wird **ohne** Hash-Prüfung geladen (Inkrement I7) |
| `User` | string | `"SYSDBA"` | FILE | Benutzer **nur** für den Klartext-Fallback (Credential Manager liefert eigenen Benutzer) |
| `Password` | string | kein | FILE | Unsicherer Fallback, wenn der Credential-Manager-Eintrag (`CredentialTarget`) nicht existiert |
| `CredentialTarget` | string | `"SQLSync_Firebird"` | FILE | Name des Credential-Manager-Eintrags, den `Resolve-FirebirdCredentials` liest; anlegen mit `Setup_Credentials.ps1 -FirebirdTarget …`. Schema: `minLength 1` |

### `MSSQL`

| Schlüssel | Typ | Default | Quelle(n) | Beschreibung |
|---|---|---|---|---|
| `Server` | string | kein | FILE | SQL-Server-Instanz (z. B. `host` oder `host\instanz`) (Schema: Pflicht) |
| `Database` | string | kein | FILE | Zieldatenbank; wird im Pre-Flight angelegt, falls sie fehlt. Code: Namensregeln (s. o.); Schema: `^[a-zA-Z_][a-zA-Z0-9_]*$` |
| `Integrated Security` | bool | `false` | FILE | `true` = Windows-Authentifizierung des ausführenden Kontos; Credentials werden dann ignoriert |
| `Username` | string | kein | FILE | SQL-Login **nur** für den Klartext-Fallback |
| `Password` | string | kein | FILE | Unsicherer Fallback, wenn der Credential-Manager-Eintrag (`CredentialTarget`) nicht existiert |
| `CredentialTarget` | string | `"SQLSync_MSSQL"` | FILE | Name des Credential-Manager-Eintrags, den `Resolve-MSSQLCredentials` liest (nur SQL-Auth); anlegen mit `Setup_Credentials.ps1 -MSSQLTarget …`. Für mehrere SQL Server mit gleichem Login, aber unterschiedlichen Passwörtern, z. B. `SQLSync_MSSQL_sqltest`. Schema: `minLength 1` |
| `Prefix` | string | `""` | FILE | Präfix des Zieltabellennamens (`<Prefix><Tabelle><Suffix>`); Staging bleibt `STG_<Tabelle>`. Code: Namensregeln (s. o.), Gesamtname ≤ 128 Zeichen; Schema: `^[a-zA-Z0-9_]*$` |
| `Suffix` | string | `""` | FILE | Suffix des Zieltabellennamens. Code: Namensregeln (s. o.); Schema: `^[a-zA-Z0-9_]*$` |
| `Port` | int | (Schema: `1433`) | — | Steht in Sample und Schema, wird vom Code **nicht** ausgewertet (Port ggf. als `host,port` in `Server` angeben; Inkrement I10) |

### Wurzelebene

| Schlüssel | Typ | Default | Quelle(n) | Beschreibung |
|---|---|---|---|---|
| `Tables` | string[] | kein (Pflicht) | FILE | Firebird-Tabellennamen, die synchronisiert werden. Leer → Abbruch. Code: Namensregeln (s. o.); Schema: `^[A-Z0-9_]+$`, eindeutig, mind. 1. Pflege per `Manage_Config_Tables.ps1` |
| `TableOverrides` | object | `{}` | FILE | Pro Tabelle abweichende Spalten: `{ "<TABELLE>": { "IdColumn": "…", "TimestampColumn": "…" } }`. Override hat Vorrang vor `General.IdColumn` / `General.TimestampColumns`. Schlüssel und Werte: Namensregeln (s. o.) |

---

## Anti-Pattern

- **Konfigwerte im Parallel-Block neu aus der Datei lesen** statt per `$using:` — erzeugt inkonsistente Läufe.
- **Konfiguration zur Laufzeit mutieren** (Ausnahme: `Manage_Config_Tables.ps1`, das die Datei bewusst mit Backup neu schreibt).
- **Magic Defaults im Code** neben `Get-SQLSyncConfig` — Bestand: `$PackageVersion`, `$ExpectedSha256` in
  `Initialize-FirebirdDriver` sind bewusst Code-Konstanten (Integrität), keine Konfigwerte.
- **Neue Schlüssel nur in `config.sample.json` ergänzen** — Default muss in `Get-SQLSyncConfig`, Grenze in `config.schema.json`.

---

## Pflege

Trigger (siehe `KICKOFF.md` Phase 3a): neue Konfig-Quelle / neuer Schlüssel / geänderter Default →
`Get-SQLSyncConfig`, `config.sample.json`, `config.schema.json`, READMEs und diese Tabelle gemeinsam aktualisieren.
