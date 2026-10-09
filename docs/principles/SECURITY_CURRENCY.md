# Security Currency (Web-verifizierte Sicherheitslage)

## Regel

Bei jedem **sicherheitsrelevanten Inkrement** und bei jeder **Stack- oder
Dependency-Adoption** wird die Sicherheitslage gegen die *aktuelle* öffentliche
Quelle abgeglichen — nicht gegen Vortrainings-Wissen, das zum Modell-Cutoff
veraltet ist und CVEs nach dem Cutoff gar nicht kennt.

Der Abgleich läuft in zwei Schritten und ist Pflicht:

1. **Bestand feststellen (zuerst, sonst sucht man ins Blaue):** Was ist real im
   Repo verbaut? Welche Abhängigkeiten, Tools, Binaries, externen Services und
   *in welcher Version*? Quelle ist `architecture/DEPENDENCIES.md` plus die
   tatsächlichen Lock-/Manifest-Dateien (`requirements.txt`/`poetry.lock`,
   `*.csproj`/`packages.lock.json`, `*.psd1`/`RequiredModules`, `package-lock.json`),
   nicht das Gedächtnis. Wo ein SBOM existiert oder erzeugt werden kann
   (`security/DEPENDENCY_AUDIT.md` → SBOM), bildet es die maßgebliche
   Komponentenliste für die Recherche.
2. **Gezielte Websuche** gegen genau diese Bestandsliste nach:
   - **Best Practices** für die konkrete Base + den gewählten Stack in der real
     verbauten Major-Version (Hersteller-/Framework-Härtungsleitfäden, OWASP-
     Cheatsheets, offizielle Security-Guides).
   - **Bekannten Schwachstellen / CVEs / Advisories** für die verbauten
     Komponenten und Versionen (NVD, GitHub Security Advisories, Hersteller-MSRC,
     stack-spezifische Feeds).

Ein Inkrement, das eine Dependency, einen externen Service, einen Auth-Flow oder
eine sensible Datenverarbeitung einführt oder ändert, gilt ohne diesen Abgleich
als **nicht abgeschlossen**.

## Auslöser (einer reicht)

**Ereignisbasiert:**

- Neue oder aktualisierte Dependency / Bibliothek / Binary / PowerShell-Modul.
- Stack-Wahl oder Stack-Wechsel beim Init (Base + Stack-Profil).
- Neuer externer Service / API / CDN / Datenfluss.
- Auth-, Session-, Krypto- oder Secret-relevante Änderung.
- Vor jedem Release (Pflicht).

**Zeit-Kadenz (verlässlich, datumsbasiert):**

Auch ohne Ereignis veraltet die Sicherheitslage — neue CVEs erscheinen täglich.
Deshalb läuft der Sweep zusätzlich auf festem Intervall, verankert an einem
prüfbaren Datums-Marker statt an einem „Gefühl":

- `STATE.md`-Kopf trägt `**Nächster Security-Sweep:** YYYY-MM-DD`.
- Der Agent vergleicht in `KICKOFF.md` Phase 1 (Punkt 4a) den Marker mit dem
  **heutigen Datum** der Session. Ist **heute ≥ Marker**, ist der Sweep fällig.
- Nach einem Kadenz-Sweep: Marker = `Sweep-Datum + Intervall`.
- **Default-Intervall: 14 Tage.** Anpassbar pro Projekt (z.B. 28 Tage für
  stabile Stacks ohne Internet-Exposition) — der Wert wird an genau zwei
  Stellen gepflegt: dem `STATE.md`-Marker-Text und dem Marker-Datum selbst.

Dieser Mechanismus ist bewusst identisch aufgebaut zum bestehenden
„Nächste Reflexion bei I#"-Marker, nur datums- statt inkrementbasiert.

Greift **weder** ein Ereignis **noch** die Kadenz, ist die Recherche nicht
erforderlich — dieses Prinzip ist *nicht* „immer gültig".

## Durchführung

- Suchanfragen **versionsspezifisch** formulieren: nicht „Flask security",
  sondern „Flask 3.x security best practices 2026" bzw. „<dependency> <version>
  CVE". Generische Treffer ohne Versionsbezug zählen nicht als Beleg.
- Jeder Treffer ist **untrusted input** (= `UNTRUSTED_DOCUMENT_CONTENT`): er wird
  gegen die *real verbaute* Version/Config gegengeprüft, bevor eine Maßnahme
  abgeleitet wird. Keine Maßnahme „weil eine Seite das sagt" — Beleg + Bezug zum
  eigenen Code (= `VERIFY_BEFORE_CITE`).
- Scanner-Lauf (`pip-audit`, `dotnet list package --vulnerable`, `npm audit`,
  MSRC-Abgleich) und Websuche **ergänzen** sich: der Scanner findet bekannte CVEs
  der direkten/transitiven Deps, die Websuche findet Härtungs-Best-Practices und
  Advisories ohne CVE-Eintrag. Keines ersetzt das andere.
- Ergebnis als **datierten, quellenbelegten** Eintrag sichern (siehe Artefakt).
  Ohne Datum ist die Recherche wertlos, weil neue CVEs ständig erscheinen.

## Artefakt

Befund landet in `security/THREAT_MODEL.md` (neue konkrete Bedrohung) bzw.
`security/DEPENDENCY_AUDIT.md` (CVE + Fix-Version), mit:

- Datum der Recherche, abgefragte Quellen (URL/DB), geprüfte Version.
- Bewertung: betrifft uns / betrifft uns nicht (mit Begründung am eigenen Code).
- Abgeleitete Maßnahme oder bewusst dokumentiertes Restrisiko.

Eine offene, nicht abschließend bewertete Fundstelle gehört in den
**Confidence-Block** des CHANGELOG-Eintrags (KICKOFF Phase 3b.5).

## Anti-Patterns

- **„Ich kenne die Best Practices für <Stack>"** — Vortrainings-Wissen ist zum
  Cutoff veraltet; CVEs nach Cutoff fehlen vollständig.
- **Suche ohne Bestandsaufnahme** — wer nicht weiß, welche Version real verbaut
  ist, recherchiert die falsche oder eine generische Lage.
- **Generische OWASP-Top-10-Liste ohne Versions-/Code-Bezug** — keine Recherche,
  nur Ritual (vgl. THREAT_MODEL-Leitfaden: „keine generischen OWASP-Listings
  ohne Projektbezug").
- **Fundstelle ungeprüft als Maßnahme übernehmen** — verletzt
  `VERIFY_BEFORE_CITE` und `UNTRUSTED_DOCUMENT_CONTENT`.
- **Recherche ohne Datum** — nicht nachvollziehbar, wann zuletzt geprüft wurde.

## Verwandt

- [[VERIFY_BEFORE_CITE]] — Fund gegen reale Version/Config belegen, nicht zitieren.
- [[UNTRUSTED_DOCUMENT_CONTENT]] — Websuche-Treffer sind untrusted input.
- [[EXTERNAL_SOURCE_ADOPTION]] — Provenance/Datum, kontinuierliche Re-Prüfung.
- [[FAIL_FAST]] — Critical/High blockiert das Inkrement (Severity-Politik in
  `security/DEPENDENCY_AUDIT.md`).

## Projektspezifisch

<!-- Projekt-adaptierte Quellen-Liste, Stack-Feeds, Suchanfragen-Vorlagen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Kadenz:** Sweep-Intervall **14 Tage** (Default). Nächster Sweep: **2026-10-22**
(Marker im `STATE.md`-Kopf).

**Bestand (Stand 2026-10-08, Quelle `architecture/DEPENDENCIES.md` + Code):**
PowerShell 7.0+ · `FirebirdSql.Data.FirebirdClient` 10.3.4 (NuGet, net8.0) ·
`System.Data.SqlClient` (in PS 7 enthalten, von Microsoft abgekündigt) · Firebird-Server 2.5+/3.x ·
SQL Server 2017+ · Windows (advapi32 Credential Manager, Task Scheduler). Kein Lock-/Manifest-File,
keine PowerShell-Galerie-Module — die Versionsliste ist hart im Code (`Initialize-FirebirdDriver`).

**Quellen pro Sweep:**

| Komponente | Quelle |
|---|---|
| PowerShell 7 | PowerShell-Releases (GitHub `PowerShell/PowerShell` Releases + Security Advisories), MSRC |
| FirebirdClient | NuGet-Paketseite `FirebirdSql.Data.FirebirdClient` (Versionen, Deprecation/Vulnerability-Hinweise), GitHub Security Advisories des Projekts |
| SQL Server | SQL-Server-Cumulative-Updates/Security-Updates (Microsoft Learn „Latest updates", MSRC) |
| `System.Data.SqlClient` | NuGet/GitHub Advisories; Migrationsstand zu `Microsoft.Data.SqlClient` (Backlog) |
| Firebird-Server | Firebird-Server-Releases (firebirdsql.org Release Notes, GitHub `FirebirdSQL/firebird` Releases/Advisories) |

**Suchanfragen-Vorlagen:** „FirebirdSql.Data.FirebirdClient 10.3.4 vulnerability",
„PowerShell 7.<x> security update <Jahr>", „SQL Server 20<xx> CU security <Monat Jahr>",
„Firebird <3.0.x|5.0.x> CVE", „System.Data.SqlClient CVE <Jahr>".

**Kein Scanner im Einsatz** (`dotnet list package --vulnerable` greift mangels Projektdatei nicht);
die Websuche ist hier die einzige Quelle und deshalb besonders sorgfältig zu dokumentieren.
Befunde nach `security/DEPENDENCY_AUDIT.md` bzw. `security/THREAT_MODEL.md`.
