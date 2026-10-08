# ADR-001: Staging-Tabelle + generische MERGE-Prozedur statt direktem Upsert

**Status:** Akzeptiert (retrospektiv dokumentiert)
**Datum:** 2026-10-08 (Dokumentation; die Entscheidung selbst ist älter und im Code seit den frühen Versionen umgesetzt)

## 1. Kontext & Problem

Ausgewählte Firebird-Tabellen sollen regelmäßig (werktags alle 30 Minuten) in eine SQL-Server-Datenbank übertragen
werden. Die Tabellen können groß sein, die Läufe sollen schnell sein und parallel mehrere Tabellen verarbeiten.
Es muss entschieden werden, **wie** geänderte Zeilen in die Zieltabelle gelangen und wie mit in Firebird
**gelöschten** Zeilen umgegangen wird.

## 2. Betrachtete Alternativen

* **Zeilenweiser Upsert** direkt aus PowerShell (je Zeile `UPDATE`/`INSERT` bzw. `MERGE` mit Parametern) — einfach,
  aber ein Roundtrip pro Zeile; bei großen Tabellen und Full-Läufen zu langsam.
* **Bulk-Load direkt in die Zieltabelle** (`SqlBulkCopy` ins Ziel) — schnell, kann aber nur einfügen; Updates bestehender
  Zeilen und Duplikate wären nicht lösbar.
* **Staging + mengenbasierter `MERGE` in SQL Server** — Delta per `SqlBulkCopy` in eine Staging-Tabelle `STG_<Tabelle>`,
  danach ein einziger `MERGE` (Upsert) ins Ziel.
* **`MERGE` mit `WHEN NOT MATCHED BY SOURCE THEN DELETE`** zur Replikation von Löschungen — war früher (mit Zeitfenster)
  im Einsatz.
* **Change Data Capture / Trigger-basierte Änderungsprotokollierung in Firebird** — erfordert Eingriffe in die
  Quelldatenbank (ERP), die nicht gewünscht sind.

## 3. Entscheidung

Wir verwenden **Staging + generische `MERGE`-Prozedur**:

1. Delta (Zeilen mit Zeitstempel `>` Wasserzeichen) bzw. Volldaten aus Firebird per `SqlBulkCopy` in `STG_<Tabelle>`.
2. `EXEC dbo.sp_Merge_Generic @TargetTableName, @StagingTableName, @IdColumnName, @TimestampColumnName` —
   dynamisches `MERGE` über alle Spalten (Spaltenliste aus `sys.columns`, Bezeichner per `QUOTENAME`), Update nur
   bei abweichendem (oder fehlendem) Zeitstempel, falls eine Timestamp-Spalte übergeben wird; sonst immer.
3. **Kein `DELETE` im `MERGE`.** Löschungen in Firebird werden **nicht live** repliziert. Bereinigung erfolgt optional
   über `CleanupOrphans` (Abgleich aller Firebird-IDs) oder über einen wöchentlichen Full-Lauf mit `ForceFullSync`.
4. Tabellen ohne ID-Spalte werden als **Snapshot** (`TRUNCATE` + `INSERT SELECT`) übertragen.

## 4. Begründung

* Im inkrementellen Modus enthält die Staging-Tabelle nur die geänderten Zeilen. Ein `WHEN NOT MATCHED BY SOURCE THEN
  DELETE` würde daher alle übrigen Zeilen im Ziel löschen — der Kommentar in `sql_server_setup.sql` beschreibt genau
  dieses Risiko („Katastrophe") als Grund für den Verzicht.
* Echte Löschungen lassen sich mit dem performanten Delta-Verfahren technisch nicht „live" erkennen, ohne die gesamte
  Tabelle zu vergleichen. Der Vergleich ist als Option (`CleanupOrphans`) bzw. als Wochenend-Job ausgelagert.
* Verbleibende gelöschte Zeilen im Ziel sind für die Nutzung als Auswertungs-/Data-Warehouse-Quelle oft akzeptabel
  oder sogar gewünscht (Historie).
* Eine **generische** Prozedur statt tabellenspezifischem SQL hält den PowerShell-Code klein: neue Tabellen benötigen
  nur einen Eintrag in `Tables`. Seit Version 3 der Prozedur sind Ziel-/Staging-Name sowie ID- und Timestamp-Spalte
  Parameter (Prefix/Suffix, `TableOverrides`).
* `SqlBulkCopy` + mengenbasierter `MERGE` sind um Größenordnungen schneller als zeilenweise Roundtrips.
* Die Quelldatenbank (ERP) bleibt unverändert; es werden nur `SELECT`s ausgeführt.

## 5. Konsequenzen

* **Positiv:** schnelle Delta-Läufe; idempotente Wiederholung (Retry) möglich, da Staging vor jedem Laden geleert wird
  und `MERGE` ein Upsert ist; keine Änderungen an der Firebird-Datenbank; neue Tabellen ohne Codeänderung.
* **Negativ/Risiken:**
  * Gelöschte Firebird-Zeilen bleiben bis zum nächsten Orphan-Cleanup oder Full-Lauf im Ziel; der Sanity Check zeigt
    das als `WARNUNG (+n)`.
  * Korrektheit hängt am Wasserzeichen `MAX(ts)` der Zieltabelle; Zeilen mit gleichem oder älterem Zeitstempel, die
    nach dem letzten Lauf committet wurden, werden übersprungen (Inkrement I8).
  * Zusätzlicher Speicherbedarf für `STG_*`-Tabellen in der Zieldatenbank.
  * Die Prozedur muss in der Zieldatenbank vorhanden und aktuell sein (Pre-Flight-Prüfung der Parameteranzahl,
    `RecreateStoredProcedure`).
  * Tabellen- und Spaltennamen wurden beim Aufruf der Prozedur ursprünglich als String-Literal interpoliert; seit
    v2.12 (I4, 2026-10-08) erfolgt der Aufruf als Stored Procedure mit `SqlParameter`n, die Namen sind zuvor per
    Allow-List (`Assert-SqlIdentifier`) geprüft.
  * Orphan-Cleanup setzt numerische IDs voraus (Temp-Tabelle mit `BIGINT`).

Verweise: `sql_server_setup.sql`, `Sync_Firebird_MSSQL_AutoSchema.ps1` (Abschnitt 8, Schritte B–G),
`docs/architecture/OVERVIEW.md`, `docs/features/firebird-mssql-sync.md`.
