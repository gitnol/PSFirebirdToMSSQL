/*
USE [master];
GO

-- 1. Datenbank erstellen (falls nicht vorhanden)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'STAGING')
BEGIN
    CREATE DATABASE [STAGING];
    PRINT 'Datenbank STAGING erstellt.';
END
GO

ALTER DATABASE [STAGING] SET RECOVERY SIMPLE;
GO


USE [STAGING];
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
*/

/*
    Stored Procedure: sp_Merge_Generic
    Beschreibung:     Führt einen generischen MERGE (Upsert) von einer Staging-Tabelle in die Zieltabelle durch.
                      Die Prozedur analysiert dynamisch die Spalten der Zieltabelle.
    
    Voraussetzung:    - Zieltabelle (@TableName) muss existieren.
                      - Staging-Tabelle ('STG_' + @TableName) muss existieren und identische Spalten haben.
                      - Beide Tabellen müssen eine Spalte [ID] besitzen (Primary Key Match).
    
    Logik:            1. Prüft Tabellenexistenz.
                      2. Ermittelt Spalten für INSERT und UPDATE dynamisch aus sys.columns.
                      3. Baut dynamisches SQL für den MERGE Befehl.
                      4. Optimierung: Updates werden nur ausgeführt, wenn sich der Zeitstempel (GESPEICHERT) unterscheidet.

Hinweis:
Im inkrementellen Modus (Standard) enthält die Staging-Tabelle ja nur die neuen 50 Datensätze.
Wenn wir jetzt sagen würden WHEN NOT MATCHED BY SOURCE THEN DELETE, würde der SQL Server sagen: 
"Oh, in der Staging-Tabelle fehlen 1 Million Datensätze (die alten), also lösche ich die alle im Ziel!" -> Katastrophe!
Deshalb verzichten wir hier auf das Löschen von nicht mehr vorhandenen Datensätzen im Ziel. Ehemals wurde das so gemacht:
    WHEN NOT MATCHED BY SOURCE AND T.GESPEICHERT >= DATEADD(Day, @TAGE, GETDATE()) 
    THEN DELETE

Lösung (Soft Deletes vs. Hard Deletes): 
Da wir uns für den performanten Weg (Staging mit Delta) entschieden haben, 
können wir echte Löschungen (Hard Deletes) technisch nicht "live" erkennen, 
ohne die gesamte Tabelle zu vergleichen.

Empfehlung:
Täglich: Inkrementeller Sync (schnell, Updates/Inserts).
Wöchentlich (Wochenende): Ein Job, der die Tabellen leert (TRUNCATE) und einmal voll lädt (Snapshot oder $RecreateStagingTable=$true mit Datum-Reset). 
Das bereinigt die Leichen. 
ODER Du akzeptierst die Leichen im DWH (Data Warehouse), was oft sogar gewünscht ist (Historie).


    Stored Procedure: sp_Merge_Generic (Version 3 - Dynamic Columns)
    Beschreibung:     Führt einen generischen MERGE durch.
    
    Änderung V2:      Akzeptiert nun separate Namen für Target und Staging.
                      Das ermöglicht Prefixe/Suffixe auf der Zieltabelle.
    
    Änderung V3:      Akzeptiert dynamische ID- und Timestamp-Spaltennamen.
                      @IdColumnName: Name der ID-Spalte (Default: 'ID')
                      @TimestampColumnName: Name der Timestamp-Spalte (NULL = kein Timestamp-Check)
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_Merge_Generic]
    @TargetTableName NVARCHAR(128),
    @StagingTableName NVARCHAR(128),
    @IdColumnName NVARCHAR(128) = 'ID',
    @TimestampColumnName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @UpdateList NVARCHAR(MAX);
    DECLARE @HasTimestamp BIT = 0;
    DECLARE @SourceColumnList NVARCHAR(MAX);

    -- 1. Validierung
    IF OBJECT_ID(@TargetTableName) IS NULL OR OBJECT_ID(@StagingTableName) IS NULL
    BEGIN
        PRINT 'Fehler: Tabelle ' + @TargetTableName + ' oder ' + @StagingTableName + ' existiert nicht.';
        RETURN;
    END

    -- Prüfen ob ID-Spalte existiert
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@TargetTableName) AND name = @IdColumnName)
    BEGIN
        PRINT 'Fehler: ID-Spalte ' + @IdColumnName + ' existiert nicht in ' + @TargetTableName;
        RETURN;
    END

    -- 2. Metadaten-Analyse (Auf Basis der Zieltabelle)
    IF @TimestampColumnName IS NOT NULL AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@TargetTableName) AND name = @TimestampColumnName)
    BEGIN
        SET @HasTimestamp = 1;
    END

    -- Spaltenliste (ohne ID-Spalte)
    SELECT @ColumnList = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TargetTableName)
      AND c.name <> @IdColumnName
      AND c.is_computed = 0;

    -- Spaltenliste mit Source-Prefix
    SELECT @SourceColumnList = STRING_AGG(CAST('Source.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TargetTableName)
      AND c.name <> @IdColumnName
      AND c.is_computed = 0;

    -- Update Liste
    SELECT @UpdateList = STRING_AGG(CAST(QUOTENAME(c.name) + ' = Source.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TargetTableName)
      AND c.name <> @IdColumnName
      AND c.is_computed = 0;

    -- 3. MERGE SQL
    SET @SQL = 'MERGE ' + QUOTENAME(@TargetTableName) + ' AS Target ' +
               'USING ' + QUOTENAME(@StagingTableName) + ' AS Source ' +
               'ON (Target.' + QUOTENAME(@IdColumnName) + ' = Source.' + QUOTENAME(@IdColumnName) + ') ' +
               'WHEN MATCHED ';

    IF @HasTimestamp = 1
    BEGIN
        SET @SQL = @SQL + 'AND (Target.' + QUOTENAME(@TimestampColumnName) + ' <> Source.' + QUOTENAME(@TimestampColumnName) + ' OR Target.' + QUOTENAME(@TimestampColumnName) + ' IS NULL) ';
    END

    SET @SQL = @SQL + 'THEN ' +
               'UPDATE SET ' + @UpdateList + ' ' +
               'WHEN NOT MATCHED BY TARGET THEN ' +
               'INSERT (' + QUOTENAME(@IdColumnName) + ', ' + @ColumnList + ') ' +
               'VALUES (Source.' + QUOTENAME(@IdColumnName) + ', ' + @SourceColumnList + ');';

    EXEC sp_executesql @SQL;
END
GO