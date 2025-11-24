USE [STAGING];
GO

-- 2. Die generische Merge-Prozedur (KORRIGIERT FÜR LANGE SPALTENLISTEN)
CREATE OR ALTER PROCEDURE [dbo].[sp_Merge_Generic]
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StagingTable NVARCHAR(128) = 'STG_' + @TableName;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @UpdateList NVARCHAR(MAX);

    -- Prüfen, ob Tabellen existieren
    IF OBJECT_ID(@TableName) IS NULL OR OBJECT_ID(@StagingTable) IS NULL
    BEGIN
        PRINT 'Fehler: Tabelle ' + @TableName + ' oder ' + @StagingTable + ' existiert nicht.';
        RETURN;
    END

    -- Spaltenliste dynamisch aufbauen (ohne ID, da wir darauf matchen)
    -- WICHTIG: CAST auf NVARCHAR(MAX) verhindert den 8000-Byte-Fehler bei vielen Spalten!
    SELECT @ColumnList = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), ', '),
           @UpdateList = STRING_AGG(CAST(QUOTENAME(c.name) + ' = Source.' + QUOTENAME(c.name) AS NVARCHAR(MAX)), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@TableName)
      AND c.name NOT IN ('ID') -- ID ist der Key, nicht updaten
      AND c.is_computed = 0;   -- Keine berechneten Spalten

    -- Dynamisches MERGE Statement bauen
    SET @SQL = '
    MERGE ' + QUOTENAME(@TableName) + ' AS Target
    USING ' + QUOTENAME(@StagingTable) + ' AS Source
    ON (Target.ID = Source.ID)
    
    WHEN MATCHED THEN
        UPDATE SET ' + @UpdateList + '
    
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ID, ' + @ColumnList + ')
        VALUES (Source.ID, ' + @ColumnList + ');';

    -- Optional: Debug-Ausgabe (kann bei sehr langen Strings im SSMS abgeschnitten wirken, ist aber intern vollständig)
    -- PRINT CAST(@SQL AS NTEXT); 

    -- Ausführen
    EXEC sp_executesql @SQL;
    
    PRINT 'Merge für ' + @TableName + ' abgeschlossen.';
END
GO