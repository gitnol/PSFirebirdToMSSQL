# WARNING SCRIPT NOT TESTED! - Anpassungen je nach Umgebung notwendig

# Konfiguration
$FirebirdConnString = "User=SYSDBA;Password=masterkey;Database=localhost:C:\Data\DB.fdb;DataSource=localhost;Port=3050;Dialect=3;Charset=NONE;"
$SqlConnString = "Server=MeinSQLServer;Database=MeineDB;Integrated Security=True;"

# DEINE LISTE: Hier trägst du nur die Tabellennamen ein
$Tabellen = @("Kunden", "Artikel", "Rechnungen", "Lagerbestand")

# Hilfsfunktion für SQL Command (damit der Code sauber bleibt)
function Get-MaxDate ($TableName) {
    $Conn = New-Object System.Data.SqlClient.SqlConnection($using:SqlConnString)
    $Conn.Open()
    $Cmd = $Conn.CreateCommand()
    # Sicherstellen, dass wir einen sauberen Startwert haben, wenn Tabelle leer
    $Cmd.CommandText = "SELECT ISNULL(MAX(GESPEICHERT), '1900-01-01') FROM $TableName" 
    $Result = $Cmd.ExecuteScalar()
    $Conn.Close()
    return $Result
}

# Hauptschleife - Parallelisiert für Speed (gemäß deinen Guidelines)
$Tabellen | ForEach-Object -Parallel {
    $Tabelle = $_
    $FbCS = $using:FirebirdConnString
    $SqlCS = $using:SqlConnString
    
    # 1. Wo waren wir stehengeblieben? (High Watermark)
    # Da wir im Parallel-Block sind, müssen wir SQL Connection neu aufbauen oder Helper nutzen
    # Vereinfacht hier inline:
    $SqlConn = New-Object System.Data.SqlClient.SqlConnection($SqlCS)
    $SqlConn.Open()
    $Cmd = $SqlConn.CreateCommand()
    $Cmd.CommandText = "SELECT ISNULL(MAX(GESPEICHERT), '1900-01-01') FROM $Tabelle"
    $LastSyncDate = [DateTime]$Cmd.ExecuteScalar()
    
    Write-Output "Starte Sync für $Tabelle ab: $LastSyncDate"

    # 2. Firebird Daten holen (Delta)
    # Hinweis: Du brauchst die FirebirdSql.Data.FirebirdClient.dll im Pfad oder GAC
    $FbConn = New-Object FirebirdSql.Data.FirebirdClient.FbConnection($FbCS)
    $FbConn.Open()
    
    $FbCmd = $FbConn.CreateCommand()
    # Parameter verhindern SQL Injection und Format-Probleme beim Datum
    $FbCmd.CommandText = "SELECT * FROM ""$Tabelle"" WHERE ""GESPEICHERT"" > @LastDate"
    $FbCmd.Parameters.Add("@LastDate", $LastSyncDate) | Out-Null
    
    $Reader = $FbCmd.ExecuteReader()
    
    # 3. Bulk Insert in MSSQL (Staging)
    # Wir nehmen an, es gibt eine Tabelle "STG_TabellenName"
    $BulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($SqlConn)
    $BulkCopy.DestinationTableName = "STG_$Tabelle"
    $BulkCopy.BulkCopyTimeout = 600
    
    try {
        # Vorher Staging leeren
        $TruncCmd = $SqlConn.CreateCommand()
        $TruncCmd.CommandText = "TRUNCATE TABLE STG_$Tabelle"
        $TruncCmd.ExecuteNonQuery()
        
        # Reinblasen! Das ist der "Pansynchro"-Moment (Streaming)
        $BulkCopy.WriteToServer($Reader)
        
        # 4. Merge Aufruf
        # Hier rufst du deine bestehende Prozedur auf oder baust dyn. SQL
        $MergeCmd = $SqlConn.CreateCommand()
        $MergeCmd.CommandText = "EXEC sp_Merge_Generic @TableName = '$Tabelle'"
        $MergeCmd.ExecuteNonQuery()
        
        Write-Output "$Tabelle erfolgreich synchronisiert."
    }
    catch {
        Write-Error "Fehler bei $Tabelle : $_"
    }
    finally {
        $Reader.Close()
        $FbConn.Close()
        $SqlConn.Close()
    }

} -ThrottleLimit 4