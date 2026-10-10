# External Source Adoption

## Regel

Wenn ein Projekt eine **externe Quelle** als Single-Source-of-Truth-Derivat
übernimmt (LLM-konvertierte Spezifikation, Community-API-Schema, generierter
Code aus einer Upstream-Doku), **darf** das nur unter zwei Bedingungen passieren:

1. **Provenance ist dokumentiert** — Herkunft, Konversions-Werkzeug, Datum,
   Verifikations-Status sind im Artefakt selbst (machine-readable, z.B. als
   Vendor-Extension `x-<projekt>-meta` oder als Header-Block) UND in einer
   begleitenden README-/SCHEMA-Datei lesbar.
2. **Kontinuierliche Verifikation** läuft gegen die tatsächliche Realität —
   meist via Test-Fixtures + Schema-Validator, die bei jedem CI-Lauf jede
   Source-Drift sofort sichtbar machen. Eine externe Quelle ohne Validator
   ist Vertrauensvorschuss; mit Validator ist sie ein lebender Vertrag.

Ohne BEIDES darf die Quelle nicht ins Repo. Adoption ist ein
Architektur-Entscheidungs-Anlass (siehe `architecture/ADR/`).

## Konkretisierung

### Provenance-Block (im Artefakt selbst)

OpenAPI-/YAML-/JSON-Artefakte: ein machine-readable Block am Anfang oder als
Vendor-Extension. Pattern:

```yaml
info:
  description: |
    ...
    Provenance: Generated from <upstream> by <tool> on <date>.
    <upstream> is the source of truth; this file is the machine-readable
    derivation, kept under continuous validation (see <test path>).
  x-<projekt>:
    ingested_at: "2026-MM-DD"
    increment: "I<n>"
    source: "<beschreibung mit konvertions-werkzeug>"
    upstream_truth: "the <upstream artefact>"
    verified_against_hardware: false   # explizit, nicht implizit
```

Klartext-Doku in `docs/architecture/<spec>_SCHEMA.md`: Status-Tabelle mit
Quelle, Refresh-Workflow, bekannte Drifts.

### Vendor-Extension-Marker für jeden lokalen Patch

Sobald ein Maintainer die externe Quelle lokal patcht (Korrektur eines
LLM-Konversions-Fehlers, projekt-spezifische Anpassung, Hinzufügen eines
fehlenden Feldes), trägt der Patch eine `x-<projekt>-note`-Vendor-Extension
mit Begründung:

```yaml
properties:
  is_management_vlan:
    type: boolean
    # x-<projekt>-note (I<n>, <date>): added — present in v8 responses
    # (verified via Tests/fixtures/...), absent in the externally-ingested
    # v1 spec. Validator regresses against this.
```

Ohne diese Marker sind beim nächsten Source-Refresh die eigenen Anpassungen
nicht mehr von der externen Quelle unterscheidbar und gehen lautlos verloren.

Helper im Refresh-Workflow:
```
git diff HEAD~1 -- <spec-path> | grep -A 3 'x-<projekt>-note'
```
listet alle lokalen Patches, die manuell bewahrt oder neu angewandt werden
müssen.

### Kontinuierliche Verifikation

Test-Fixtures (Recorded oder hand-gefertigt) werden bei jedem CI-Lauf gegen
das Schema validiert. Pattern:

```powershell
# Pester
Describe 'External-source artefact vs project reality' -Tag 'Unit' {
    It "fixture <Name> validates against schema" -ForEach $cases {
        $exit = & python Tools/Validate-Fixture.py --spec <spec> --fixture $Path
        $exit | Should -Be 0
    }
}
```

Der erste Validator-Lauf nach Adoption deckt Konversions-Fehler in der externen
Quelle auf — das ist gewollt. Patch sofort, dokumentiere im CHANGELOG als
Lesson.

## Anti-Patterns

- **Adoption ohne Provenance:** „Datei ist da, wir nutzen sie." — beim
  Refresh weiß niemand, was lokal angepasst war vs. was Original ist.
- **`x-preconditions` o.ä. als Vendor-Extension, ohne Tool das es konsumiert:**
  reine Lint-Noise. Vendor-Extensions sind nur dann sinnvoll, wenn sie
  entweder (a) **gelesen** werden (eigenes Tool, Doku-Generator) oder (b)
  **strukturierte Provenance** kodieren.
- **Validator ohne Fixtures:** Schema-only-Validation ohne reale Daten findet
  triviale Strukturfehler, aber keine echten Feld-/Typ-Drifts.
- **Validator nur lokal:** wenn die Verifikation nicht in CI läuft, wird sie
  nicht gepflegt.

## Refresh-Strategien

Welcher Refresh-Pfad richtig ist, hängt vom Typ der neuen Quelle ab:

- **Pfad A — Delta-Patch aus Change-Log** (bevorzugt, wenn die neue Quelle
  ein „What's New" / „Change Log"-Kapitel mitliefert): keine Re-Konversion
  der vollständigen Quelle; stattdessen nur die im Change-Log gelisteten
  Δ-Endpoints / Schema-Updates per `x-<projekt>-note (I<n>)`-Marker
  einarbeiten. Lokale Patches bleiben automatisch erhalten. Aufwand
  typischerweise Stunden statt Tage.
- **Pfad B — Volle Re-Konversion** (nötig, wenn die neue Quelle eine
  vollständige Referenz ist und keine Change-Log-Sektion hat): wie unten
  unter „Pflege" beschrieben.

Faustregel: Change-Guide-PDFs sind oft 30–40 Seiten, Voll-Referenz-PDFs
≥ 90 Seiten. Die Methode passt sich also natürlich an die Datengröße an.

## Pflege

Beim Refresh der externen Quelle (Pfad B — Volle Re-Konversion):

1. **Vor** dem Überschreiben: alle `x-<projekt>-note`-Marker per `git diff`
   extrahieren und in einer scratch-Datei sammeln.
2. Neue externe Datei einspielen.
3. Provenance-Block manuell mit neuer Versions-/Datums-Info aktualisieren.
4. Gesammelte Patches einzeln re-anwenden, jeden mit `git add -p` review.
5. Validator-Lauf — alle Drifts adressieren wie bei der ersten Adoption.
6. CHANGELOG-Eintrag, Lesson-Index ergänzen.

## Routine-Checks nach jedem Refresh oder lokalen Patch

Diese drei Checks sind billig und decken die häufigsten stillen Bugs auf:

1. **Orphan-Check:** Jede in `components.schemas` / `components.parameters` /
   `components.responses` deklarierte Definition muss mindestens einmal per
   `$ref` referenziert werden. Andernfalls ist sie toter Code, der bei der
   nächsten Refactor-Welle vermutlich gelöscht wird, obwohl er Absichten
   trägt. Ein Snippet, das das prüft:

   ```python
   declared = set(spec["components"]["schemas"])
   referenced = set(re.findall(r'#/components/schemas/(\w+)', yaml_text))
   orphans = declared - referenced
   ```

2. **Fixture-First-Design** für neue Endpoints: bevor ein Test-Fixture mit
   einem Response-Body geschrieben wird, prüfen, ob die Spec für diese
   Operation ein **Response-Schema** definiert hat. Tut sie das nicht
   (z.B. `responses: {200: {description: OK}}`), den Spec-Eintrag zuerst
   um ein `content/application/json/schema`-Element ergänzen — danach das
   Fixture. Sonst meldet der Validator das Fixture als Drift.

3. **Cross-Referenz gegen alternative Implementierungen** (auch ältere
   oder von Dritten): selbst eine 7–8 Jahre alte Lib des gleichen
   Herstellers deckt häufig 1–3 Endpoints auf, die im aktuellen
   Referenz-PDF schlicht fehlen. Solche Funde landen als Backlog-Punkt
   „Spec-Patch via `x-<projekt>-note` nach Hardware-Recording".

Wenn diese Checks erst nach Wochen zufällig auffallen, sind die jeweils
zugehörigen lokalen Patches schwer rückverfolgbar. **Sofort nach jedem
Spec-Edit ausführen.**

## Verweise

- Beispiel-Anwendung (REST-API-Client-Projekt, nicht dieses Repo): `docs/architecture/openapi.yaml`,
  `docs/architecture/REST_API_SCHEMA.md`, `Tools/Validate-Fixture.py`,
  `Tests/unit/FixturesAgainstSchema.Tests.ps1`.
- Verbindet sich mit [[VERIFY_BEFORE_CITE]] (jede Behauptung in der externen
  Quelle wird gegen Realität geprüft) und [[FAIL_FAST]] (Drift bricht den
  CI-Lauf sofort).

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

Externe Quellen in diesem Projekt und ihr Status:

| Quelle | Provenance | Verifikation | Status |
|---|---|---|---|
| `FirebirdSql.Data.FirebirdClient` 10.3.4 (NuGet, `lib\net8.0`) | Version + Download-URL in `Initialize-FirebirdDriver` (`SQLSyncCommon.psm1`) | SHA-256 **jeder** DLL vor dem Laden (Download, vorhanden, `DllPath`) gegen die Original-Hashes `lib\net8.0`/`lib\netstandard2.1`, am 2026-10-09 aus dem offiziellen Paket von nuget.org nachgerechnet | Erledigt (I7, S4). Grenze: bereits in der Sitzung geladene Assembly wird nicht geprüft. Versionswechsel = `$PackageVersion`, `$DownloadUrl` und beide Hashes in `$KnownSha256` gemeinsam ändern; abweichende DLL nur mit `Firebird.DllSha256`. |
| `config.schema.json` (JSON-Schema-Draft, im Repo gepflegt) | Herkunft/Erstellungsweg nicht dokumentiert | `Get-SQLSyncConfig -SchemaPath` validiert jede Konfig beim Laden (`Test-Json -Schema`, Fail-Fast, Exit 2); Unit-Tests gegen das echte Schema; alle vorhandenen lokalen Konfigs am 2026-10-09 gegen das Schema geprüft | Erledigt (I6 / v2.15, S9). Namensmuster an die Identifier-Whitelist angeglichen. Bei neuen Schlüsseln Schema, Sample und `Get-SQLSyncConfig`-Defaults gemeinsam pflegen. |
| `.github/copilot-instructions.md` | Agent-Hinweise (Kurzfassung) | `docs/` und Code | Seit I10c an den Code angeglichen; bei Widerspruch gelten `docs/` und Code. |

Neue externe Artefakte (z. B. ein Typ-Mapping aus Firebird-Doku, ein Wechsel auf
`Microsoft.Data.SqlClient`) brauchen ein ADR unter `architecture/ADR/`.
