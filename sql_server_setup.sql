USE [STAGING];
GO

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

    -- 1. Validierung
    IF OBJECT_ID(@TableName) IS NULL OR OBJECT_ID(@StagingTable) IS NULL
    BEGIN
        PRINT 'Fehler: Tabelle ' + @TableName + ' oder ' + @StagingTable + ' existiert nicht.';
        RETURN;
    END

    -- 2. Prüfen, ob 'GESPEICHERT' Spalte existiert (für die Optimierung)
    IF EXISTS (SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@TableName) AND name = 'GESPEICHERT')
    BEGIN
        SET @HasGespeichert = 1;
    END

    -- 3. Spaltenliste für INSERT bauen
    -- Nutzung von CAST(... AS NVARCHAR(MAX)), um 8000-Byte-Limit zu umgehen
    SELECT @ColumnList = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TableName)
        AND c.name NOT IN ('ID')
        AND c.is_computed = 0;

    -- 4. Spaltenliste für UPDATE bauen
    SELECT @UpdateList = STRING_AGG(CAST(QUOTENAME(c.name) + ' = Source.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TableName)
        AND c.name NOT IN ('ID')
        AND c.is_computed = 0;

    -- 5. MERGE Statement zusammenbauen
    SET @SQL = 'MERGE ' + QUOTENAME(@TableName) + ' AS Target ' +
               'USING ' + QUOTENAME(@StagingTable) + ' AS Source ' +
               'ON (Target.ID = Source.ID) ' +
               
               'WHEN MATCHED ';

    -- OPTIMIERUNG: Nur updaten, wenn der Zeitstempel abweicht (Verhindert unnötige Writes)
    IF @HasGespeichert = 1
    BEGIN
        SET @SQL = @SQL + 'AND (Target.GESPEICHERT <> Source.GESPEICHERT OR Target.GESPEICHERT IS NULL) ';
    END

    SET @SQL = @SQL + 'THEN ' +
               'UPDATE SET ' + @UpdateList + ' ' +
               
               'WHEN NOT MATCHED BY TARGET THEN ' +
               'INSERT (ID, ' + @ColumnList + ') ' +
               'VALUES (Source.ID, ' + @ColumnList + ');';

    -- Debugging (optional)
    -- PRINT CAST(@SQL AS NTEXT);

    -- 6. Ausführen
    EXEC sp_executesql @SQL;

-- PRINT 'Smart-Merge für ' + @TableName + ' abgeschlossen.';
END
GO