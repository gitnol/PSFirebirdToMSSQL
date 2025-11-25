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

*/
CREATE OR ALTER PROCEDURE [dbo].[sp_Merge_Generic]
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StagingTable NVARCHAR(128) = 'STG_' + @TableName;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @UpdateList NVARCHAR(MAX);
    DECLARE @HasGespeichert BIT = 0;

    -- ---------------------------------------------------------
    -- 1. Validierung: Existieren Quelle und Ziel?
    -- ---------------------------------------------------------
    IF OBJECT_ID(@TableName) IS NULL OR OBJECT_ID(@StagingTable) IS NULL
    BEGIN
        PRINT 'Fehler: Tabelle ' + @TableName + ' oder ' + @StagingTable + ' existiert nicht.';
        RETURN;
    END

    -- ---------------------------------------------------------
    -- 2. Metadaten-Analyse
    -- ---------------------------------------------------------

    -- Prüfen, ob 'GESPEICHERT' Spalte existiert (für Performance-Optimierung beim Update)
    IF EXISTS (SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@TableName) AND name = 'GESPEICHERT')
    BEGIN
        SET @HasGespeichert = 1;
    END

    -- Spaltenliste für INSERT bauen (Alle Spalten außer ID)
    -- Hinweis: CAST(... AS NVARCHAR(MAX)) verhindert Fehler bei Tabellen mit sehr vielen Spalten (> 8000 Zeichen String)
    SELECT @ColumnList = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TableName)
        AND c.name NOT IN ('ID') -- ID wird explizit behandelt
        AND c.is_computed = 0;
    -- Keine berechneten Spalten übernehmen

    -- Spaltenliste für UPDATE bauen (Zuwelsung Target.Col = Source.Col)
    SELECT @UpdateList = STRING_AGG(CAST(QUOTENAME(c.name) + ' = Source.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TableName)
        AND c.name NOT IN ('ID')
        AND c.is_computed = 0;

    -- ---------------------------------------------------------
    -- 3. MERGE Statement zusammenbauen
    -- ---------------------------------------------------------
    SET @SQL = 'MERGE ' + QUOTENAME(@TableName) + ' AS Target ' +
               'USING ' + QUOTENAME(@StagingTable) + ' AS Source ' +
               'ON (Target.ID = Source.ID) ' +
               
               'WHEN MATCHED ';

    -- OPTIMIERUNG: "Smart Update"
    -- Wir updaten nur, wenn sich der Zeitstempel unterscheidet. 
    -- Das reduziert Transaction-Log-Writes massiv, da identische Zeilen ignoriert werden.
    IF @HasGespeichert = 1
    BEGIN
        SET @SQL = @SQL + 'AND (Target.GESPEICHERT <> Source.GESPEICHERT OR Target.GESPEICHERT IS NULL) ';
    END

    SET @SQL = @SQL + 'THEN ' +
               'UPDATE SET ' + @UpdateList + ' ' +
               
               'WHEN NOT MATCHED BY TARGET THEN ' +
               'INSERT (ID, ' + @ColumnList + ') ' +
               'VALUES (Source.ID, ' + @ColumnList + ');';

    -- Debugging: Einkommentieren, um das generierte SQL zu sehen
    -- PRINT CAST(@SQL AS NTEXT);

    -- ---------------------------------------------------------
    -- 4. Ausführung
    -- ---------------------------------------------------------
    EXEC sp_executesql @SQL;

-- Optional: Erfolgsmeldung (kann bei vielen Aufrufen das Log fluten, daher auskommentiert)
-- PRINT 'Smart-Merge für ' + @TableName + ' abgeschlossen.';
END
GO