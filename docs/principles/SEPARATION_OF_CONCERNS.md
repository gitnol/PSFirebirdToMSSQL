# Separation of Concerns

## Regel

Jede Schicht hat genau eine Verantwortung und kennt nur die Schicht direkt
unter ihr. Praesentation kennt keine Datenbank; Persistenz kennt keine HTTP-Codes.

## Sprach-agnostische Vorgaben

- Schichten als gerichteter Graph — keine zyklischen Abhaengigkeiten zwischen Schichten
- Geschaeftsregeln leben in der Domaenen-/Service-Schicht, nicht in Controllern,
  Views oder Repositories
- Persistenz-Details (SQL-Eigenheiten, ORM-Spezifika) bleiben in Repositories —
  die Service-Schicht arbeitet auf Domaenenobjekten, nicht auf ORM-Entities
- UI/View-Code (Jinja-Templates, Razor-Views, Streamlit-Layout) enthaelt KEINE
  Business-Logik — nur Praesentation
- Externe Services (HTTP-Clients, LLM-APIs) werden ueber eine Adapterschicht
  gekapselt — Domaene arbeitet gegen ein Interface, nicht gegen ein konkretes SDK

## Typische Schichten

| Schicht | Verantwortung | Darf kennen |
|---|---|---|
| Praesentation | Eingabe entgegennehmen, Ausgabe formatieren | Anwendung |
| Anwendung (Services) | Use Cases orchestrieren, Transaktionsgrenzen | Domaene, Adapter |
| Domaene | Geschaeftsregeln, Invarianten | (nichts ausserhalb der Domaene) |
| Infrastruktur (Adapter, Repositories) | Externe Welt anbinden, persistieren | Domaene |

## Prueffragen

- "Wenn ich die Datenbank austausche, welche Module muss ich anfassen?"
  → Nur Persistenzschicht. Domaene + Anwendungsschicht bleiben unveraendert.

- "Wenn ich von CLI auf Web-UI wechsle, welche Module muss ich anfassen?"
  → Nur die Praesentation. Anwendungs- und Domaenenschicht bleiben unveraendert.

- "Wenn ich diese Geschaeftsregel aendere, muss ich sie an mehreren Stellen anpassen?"
  → Wenn JA: die Regel lebt nicht in der Domaene, sondern dupliziert in UI + API.
    Refaktorieren.

## Verwandt

- [[ORTHOGONALITY]] — gleiche Stossrichtung auf Modulebene, eine Ebene granularer
- [[DRY]] — Schichtung verhindert duplizierte Geschaeftslogik in UI und API
- [[YAGNI]] — nicht zu viele Schichten einfuehren, wenn 2 reichen

## Projektspezifisch

<!-- Projekt-adaptierte Beispiele, Stage-Tabellen, Modul-Referenzen hier einfügen.
     Maßgeblich für die Update-Klassifizierung ist der Vergleich gegen die alte
     Template-Version (ALTES_PROJECT_AKTUALISIEREN.md, Schritt 2c/3): Solange diese
     Datei byte-identisch zum Template ist, gilt sie als Kategorie A (sicher
     überschreibbar). Jede lokale Anpassung — hier oder im Fließtext oben — macht
     sie zu Kategorie C: nur Drei-Wege-Merge, kein Blanket-Overwrite. -->

**Schichten im Ist-Zustand:**

| Schicht | Datei / Funktion | Verantwortung |
|---|---|---|
| Einstieg / Orchestrierung | `Sync_Firebird_MSSQL_AutoSchema.ps1` | Ablauf, Pre-Flight, Parallelisierung, Retry, Zusammenfassung, Exit-Code |
| Gemeinsame Infrastruktur | `SQLSyncCommon.psm1` | Config laden + validieren, Credentials, Connection-Strings, Treiber, Typmapping, Strategieermittlung |
| Datenbanklogik (SQL Server) | `sql_server_setup.sql` → `dbo.sp_Merge_Generic` | generisches MERGE (Upsert, kein DELETE) |
| Werkzeuge | `Setup_Credentials.ps1`, `Setup-ScheduledTasks.ps1`, `Test-SQLSyncConnections.ps1`, `Get_Firebird_Schema.ps1`, `Manage_Config_Tables.ps1` | Einrichtung, Diagnose, Konfigpflege |

**Bekannte Verletzungen:** keine offenen aus dem Katalog. Seit v2.15 lösen alle vier Einstiegsskripte den
Configpfad über `Resolve-SQLSyncConfigPath` auf und laden über `Get-SQLSyncConfig -SchemaPath` (früher kopiert
bzw. in den Hilfsskripten fest auf `config.json`, S8). Neue Logik gehört
ins Modul (testbar, siehe `testing/UNIT_TESTS.md`), das Hauptskript bleibt Orchestrierung. Vorbild:
Seit v2.14 importiert der `-Parallel`-Block das Modul (`Import-Module $using:ModulePath`) und nutzt
`ConvertTo-SqlServerType`/`Get-TableColumnConfig`, statt Typmapping und Strategieermittlung zu kopieren.
