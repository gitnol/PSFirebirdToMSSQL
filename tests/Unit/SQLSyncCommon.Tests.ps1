#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Aufruf (Repo-Root): Invoke-Pester ./tests

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\SQLSyncCommon.psm1') -Force

    function New-TableResult {
        param([string]$Status = 'Erfolg', [string]$SanityCheck = 'OK')
        [PSCustomObject]@{ Tabelle = 'T'; Status = $Status; SanityCheck = $SanityCheck }
    }
}

Describe 'Get-SyncExitCode' {
    It 'gibt 0 zurück, wenn alle Tabellen erfolgreich und Sanity OK sind' {
        $Results = @(New-TableResult), @(New-TableResult -SanityCheck 'N/A')
        Get-SyncExitCode -Results $Results | Should -Be 0
    }

    It 'gibt 10 zurück, wenn mindestens eine Tabelle den Status Fehler hat' {
        $Results = @(New-TableResult), @(New-TableResult -Status 'Fehler' -SanityCheck 'N/A')
        Get-SyncExitCode -Results $Results | Should -Be 10
    }

    It 'gibt 11 zurück bei Sanity FEHLER ohne Tabellenfehler' {
        $Results = @(New-TableResult), @(New-TableResult -SanityCheck 'FEHLER (-3)')
        Get-SyncExitCode -Results $Results | Should -Be 11
    }

    It 'bevorzugt 10 vor 11, wenn beides auftritt' {
        $Results = @(New-TableResult -SanityCheck 'FEHLER (-1)'), @(New-TableResult -Status 'Fehler')
        Get-SyncExitCode -Results $Results | Should -Be 10
    }

    It 'wertet Sanity WARNUNG nicht als Fehler' {
        $Results = @(New-TableResult -SanityCheck 'WARNUNG (+5)')
        Get-SyncExitCode -Results $Results | Should -Be 0
    }

    It 'ignoriert Sanity FEHLER, wenn FailOnSanityError deaktiviert ist' {
        $Results = @(New-TableResult -SanityCheck 'FEHLER (-3)')
        Get-SyncExitCode -Results $Results -FailOnSanityError $false | Should -Be 0
    }

    It 'gibt 10 zurück, wenn gar keine Ergebnisse vorliegen' {
        Get-SyncExitCode -Results @() | Should -Be 10
    }

    It 'gibt 10 zurück, wenn weniger Ergebnisse als erwartete Tabellen vorliegen' {
        $Results = @(New-TableResult)
        Get-SyncExitCode -Results $Results -ExpectedTableCount 2 | Should -Be 10
    }

    It 'gibt 0 zurück, wenn die Anzahl der Ergebnisse der erwarteten entspricht' {
        $Results = @(New-TableResult), @(New-TableResult)
        Get-SyncExitCode -Results $Results -ExpectedTableCount 2 | Should -Be 0
    }
}

Describe 'Get-SQLSyncConfig: FailOnSanityError' {
    BeforeAll {
        $script:ConfigPath = Join-Path $TestDrive 'config.json'
        function Write-TestConfig([hashtable]$General) {
            @{ General = $General; Firebird = @{ Server = 's'; Database = 'd' }; MSSQL = @{ Server = 's'; Database = 'd' }; Tables = @('T1') } |
                ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath
        }
    }

    It 'ist standardmäßig aktiv' {
        Write-TestConfig @{}
        (Get-SQLSyncConfig -ConfigPath $script:ConfigPath).FailOnSanityError | Should -BeExactly $true
    }

    It 'übernimmt false aus der Konfiguration' {
        Write-TestConfig @{ FailOnSanityError = $false }
        (Get-SQLSyncConfig -ConfigPath $script:ConfigPath).FailOnSanityError | Should -BeExactly $false
    }
}

Describe 'Credential-Targets aus der Konfiguration' {
    BeforeAll {
        # Kein echter Credential-Manager-Zugriff: Get-StoredCredential liefert pro Target einen erkennbaren Benutzer
        Mock -ModuleName SQLSyncCommon Get-StoredCredential {
            [PSCustomObject]@{ Username = "user_of_$Target"; Password = 'dummy' }
        }
    }

    It 'Resolve-MSSQLCredentials nutzt standardmäßig SQLSync_MSSQL' {
        $Raw = [PSCustomObject]@{ MSSQL = [PSCustomObject]@{ Server = 's' } }
        (Resolve-MSSQLCredentials -Config $Raw 6>$null).Username | Should -Be 'user_of_SQLSync_MSSQL'
    }

    It 'Resolve-MSSQLCredentials nutzt MSSQL.CredentialTarget, wenn gesetzt' {
        $Raw = [PSCustomObject]@{ MSSQL = [PSCustomObject]@{ Server = 's'; CredentialTarget = 'SQLSync_MSSQL_sqltest' } }
        (Resolve-MSSQLCredentials -Config $Raw 6>$null).Username | Should -Be 'user_of_SQLSync_MSSQL_sqltest'
    }

    It 'Resolve-FirebirdCredentials nutzt standardmäßig SQLSync_Firebird' {
        $Raw = [PSCustomObject]@{ Firebird = [PSCustomObject]@{ Server = 's' } }
        (Resolve-FirebirdCredentials -Config $Raw 6>$null).Username | Should -Be 'user_of_SQLSync_Firebird'
    }

    It 'Resolve-FirebirdCredentials nutzt Firebird.CredentialTarget, wenn gesetzt' {
        $Raw = [PSCustomObject]@{ Firebird = [PSCustomObject]@{ Server = 's'; CredentialTarget = 'SQLSync_Firebird_test' } }
        (Resolve-FirebirdCredentials -Config $Raw 6>$null).Username | Should -Be 'user_of_SQLSync_Firebird_test'
    }

    It 'meldet den nicht gefundenen Target-Namen in der Fehlermeldung' {
        Mock -ModuleName SQLSyncCommon Get-StoredCredential { $null }
        $Raw = [PSCustomObject]@{ MSSQL = [PSCustomObject]@{ Server = 's'; CredentialTarget = 'SQLSync_MSSQL_x' } }
        { Resolve-MSSQLCredentials -Config $Raw 6>$null } | Should -Throw '*SQLSync_MSSQL_x*'
    }
}

Describe 'Get-ConfigValue' {
    It 'liefert den Default, wenn die Sektion fehlt' {
        Get-ConfigValue $null 'X' 42 | Should -Be 42
    }
    It 'liefert den Default, wenn die Eigenschaft fehlt' {
        Get-ConfigValue ([PSCustomObject]@{ A = 1 }) 'X' 42 | Should -Be 42
    }
    It 'liefert den Default, wenn der Wert null ist' {
        Get-ConfigValue ([PSCustomObject]@{ X = $null }) 'X' 42 | Should -Be 42
    }
    It 'liefert den konfigurierten Wert, auch wenn er false ist' {
        Get-ConfigValue ([PSCustomObject]@{ X = $false }) 'X' $true | Should -BeExactly $false
    }
}

Describe 'Get-SQLSyncConfig' {
    BeforeEach { $script:CfgPath = Join-Path $TestDrive 'config.test.json' }

    It 'setzt die dokumentierten Defaults' {
        Set-Content $script:CfgPath '{"Tables":["BKUNDE"]}'
        $c = Get-SQLSyncConfig -ConfigPath $script:CfgPath
        $c.GlobalTimeout          | Should -Be 7200
        $c.NumberOfThreads        | Should -Be 4
        $c.MaxRetries             | Should -Be 3
        $c.RetryDelaySeconds      | Should -Be 10
        $c.DeleteLogOlderThanDays | Should -Be 30
        $c.OrphanCleanupBatchSize | Should -Be 50000
        $c.RunSanityCheck         | Should -BeExactly $true
        $c.ForceFullSync          | Should -BeExactly $false
        $c.CleanupOrphans         | Should -BeExactly $false
        $c.IdColumn               | Should -Be 'ID'
        $c.TimestampColumns       | Should -Be @('GESPEICHERT')
        $c.FBPort                 | Should -Be 3050
        $c.FBCharset              | Should -Be 'UTF8'
        $c.MSSQLPrefix            | Should -Be ''
        $c.MSSQLSuffix            | Should -Be ''
    }
    It 'liefert TimestampColumns immer als Array, auch bei einem einzelnen Wert' {
        Set-Content $script:CfgPath '{"General":{"TimestampColumns":"CHANGED_AT"},"Tables":["BKUNDE"]}'
        $c = Get-SQLSyncConfig -ConfigPath $script:CfgPath
        $c.TimestampColumns.GetType().IsArray | Should -BeExactly $true
        $c.TimestampColumns[0] | Should -Be 'CHANGED_AT'
    }
    It 'übernimmt TableOverrides als Hashtable' {
        Set-Content $script:CfgPath '{"Tables":["LEGACY"],"TableOverrides":{"LEGACY":{"IdColumn":"ORDER_ID","TimestampColumn":"CHANGED_AT"}}}'
        $c = Get-SQLSyncConfig -ConfigPath $script:CfgPath
        $c.TableOverrides['LEGACY'].IdColumn        | Should -Be 'ORDER_ID'
        $c.TableOverrides['LEGACY'].TimestampColumn | Should -Be 'CHANGED_AT'
    }
    It 'wirft bei leerer Tables-Liste' {
        Set-Content $script:CfgPath '{"Tables":[]}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'Keine Tabellen in der Konfiguration definiert.'
    }
    It 'wirft bei GlobalTimeout <= 0' {
        Set-Content $script:CfgPath '{"General":{"GlobalTimeout":0},"Tables":["BKUNDE"]}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'GlobalTimeout muss größer als 0 sein.'
    }
    It 'wirft bei OrphanCleanupBatchSize < 1000' {
        Set-Content $script:CfgPath '{"General":{"OrphanCleanupBatchSize":500},"Tables":["BKUNDE"]}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'OrphanCleanupBatchSize muss mindestens 1000 sein.'
    }
    It 'wirft bei fehlender Datei' {
        { Get-SQLSyncConfig -ConfigPath (Join-Path $TestDrive 'fehlt.json') } |
            Should -Throw -ExpectedMessage 'Konfigurationsdatei nicht gefunden:*'
    }
    It 'wirft bei ungültigem JSON' {
        Set-Content $script:CfgPath '{"Tables": [BKUNDE'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } |
            Should -Throw -ExpectedMessage 'Fehler beim Parsen der Konfiguration:*'
    }
}

Describe 'Resolve-SQLSyncConfigPath' {
    BeforeAll {
        $script:Dir = Join-Path $TestDrive 'app'
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
        Set-Content (Join-Path $script:Dir 'weekly.json') '{}'
        $script:Abs = Join-Path $TestDrive 'abs.json'
        Set-Content $script:Abs '{}'
    }
    It 'liefert config.json im Skriptordner, wenn nichts angegeben ist' {
        Resolve-SQLSyncConfigPath -ConfigFile '' -ScriptDir $script:Dir | Should -Be (Join-Path $script:Dir 'config.json')
    }
    It 'löst einen existierenden absoluten Pfad auf' {
        Resolve-SQLSyncConfigPath -ConfigFile $script:Abs -ScriptDir $script:Dir | Should -Be (Convert-Path $script:Abs)
    }
    It 'sucht einen relativen Namen im Skriptordner' {
        Push-Location $TestDrive
        try { Resolve-SQLSyncConfigPath -ConfigFile 'weekly.json' -ScriptDir $script:Dir | Should -Be (Join-Path $script:Dir 'weekly.json') }
        finally { Pop-Location }
    }
    It 'gibt einen nicht existierenden Pfad unverändert zurück (Fehler meldet Get-SQLSyncConfig)' {
        Resolve-SQLSyncConfigPath -ConfigFile 'fehlt.json' -ScriptDir $script:Dir | Should -Be 'fehlt.json'
    }
}

Describe 'Get-SQLSyncConfig -SchemaPath (Fail-Fast)' {
    BeforeAll {
        $script:Schema = Join-Path $PSScriptRoot '..\..\config.schema.json'
        $script:Base = '"Firebird":{"Server":"fb","Database":"C:\\db\\test.fdb"},"MSSQL":{"Server":"sql","Database":"STAGING"}'
    }
    BeforeEach { $script:CfgPath = Join-Path $TestDrive 'config.schema-test.json' }

    It 'akzeptiert eine schemakonforme Konfiguration' {
        Set-Content $script:CfgPath ('{' + $script:Base + ',"Tables":["BKUNDE"]}')
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath $script:Schema } | Should -Not -Throw
    }
    It 'wirft bei falschem Typ und nennt den JSON-Pfad' {
        Set-Content $script:CfgPath ('{"General":{"GlobalTimeout":"abc"},' + $script:Base + ',"Tables":["BKUNDE"]}')
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath $script:Schema } | Should -Throw '*/General/GlobalTimeout*'
    }
    It 'wirft bei unbekanntem Schlüssel (Tippfehler)' {
        Set-Content $script:CfgPath ('{"General":{"GlobalTimout":7200},' + $script:Base + ',"Tables":["BKUNDE"]}')
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath $script:Schema } | Should -Throw '*GlobalTimout*'
    }
    It 'warnt nur, wenn die Schema-Datei fehlt' {
        Set-Content $script:CfgPath ('{' + $script:Base + ',"Tables":["BKUNDE"]}')
        $w = $null
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath (Join-Path $TestDrive 'kein.schema.json') -WarningVariable w -WarningAction SilentlyContinue } | Should -Not -Throw
        Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath (Join-Path $TestDrive 'kein.schema.json') -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        "$w" | Should -BeLike '*Schema*'
    }
    It 'akzeptiert im Schema dieselben Namen wie die Identifier-Whitelist (<Name>)' -TestCases @(
        @{ Name = 'b_kunde' }, @{ Name = 'RDB$X' }
    ) {
        param($Name)
        Set-Content $script:CfgPath ('{' + $script:Base + ',"Tables":["' + $Name + '"],"General":{"IdColumn":"' + $Name + '","TimestampColumns":["' + $Name + '"]},"TableOverrides":{"' + $Name + '":{"IdColumn":"' + $Name + '"}}}')
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath -SchemaPath $script:Schema } | Should -Not -Throw
    }
}

Describe 'Assert-SqlIdentifier' {
    It 'akzeptiert <Name>' -TestCases @(
        @{ Name = 'BKUNDE' }, @{ Name = 'b_kunde_2' }, @{ Name = 'RDB$X' }, @{ Name = ('A' * 63) }
    ) {
        param($Name)
        { Assert-SqlIdentifier -Name $Name -Field 'Tables' } | Should -Not -Throw
    }
    It 'lehnt "<Name>" ab' -TestCases @(
        @{ Name = 'A"B' }, @{ Name = 'X;DROP' }, @{ Name = 'A]B' }, @{ Name = "A'B" }, @{ Name = 'A B' },
        @{ Name = 'A-B' }, @{ Name = '' }, @{ Name = ('A' * 64) }
    ) {
        param($Name)
        { Assert-SqlIdentifier -Name $Name -Field 'Tables' } | Should -Throw '*Tables*'
    }
    It 'erlaubt einen Leerstring nur mit -AllowEmpty' {
        { Assert-SqlIdentifier -Name '' -Field 'MSSQL.Prefix' -AllowEmpty } | Should -Not -Throw
    }
}

Describe 'Get-SQLSyncConfig: Identifier-Validierung (Fail-Fast)' {
    BeforeEach { $script:CfgPath = Join-Path $TestDrive 'config.ident.json' }

    It 'wirft bei ungültigem Namen in <Field>' -TestCases @(
        @{ Field = 'Tables';                  Json = '{"Tables":["BKUNDE","X;DROP TABLE Y"]}' }
        @{ Field = 'General.IdColumn';        Json = '{"General":{"IdColumn":"ID]"},"Tables":["T"]}' }
        @{ Field = 'General.TimestampColumns'; Json = '{"General":{"TimestampColumns":["OK","A\"B"]},"Tables":["T"]}' }
        @{ Field = 'MSSQL.Prefix';            Json = '{"MSSQL":{"Prefix":"X]; DROP"},"Tables":["T"]}' }
        @{ Field = 'MSSQL.Suffix';            Json = '{"MSSQL":{"Suffix":"a b"},"Tables":["T"]}' }
        @{ Field = 'TableOverrides';          Json = '{"Tables":["T"],"TableOverrides":{"T;X":{"IdColumn":"ID"}}}' }
        @{ Field = 'TableOverrides.T.IdColumn'; Json = '{"Tables":["T"],"TableOverrides":{"T":{"IdColumn":"I D"}}}' }
        @{ Field = 'TableOverrides.T.TimestampColumn'; Json = '{"Tables":["T"],"TableOverrides":{"T":{"TimestampColumn":"TS'';"}}}' }
        @{ Field = 'MSSQL.Database';          Json = '{"MSSQL":{"Database":"STAGING]; DROP DATABASE X; --"},"Tables":["T"]}' }
    ) {
        param($Field, $Json)
        Set-Content $script:CfgPath $Json
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } | Should -Throw "*$Field*"
    }
    It 'wirft, wenn Prefix + Tabelle + Suffix länger als 128 Zeichen wird' {
        $Prefix = 'P' * 60
        Set-Content $script:CfgPath ('{"MSSQL":{"Prefix":"' + $Prefix + '","Suffix":"SSSSSSSSSS"},"Tables":["' + ('T' * 60) + '"]}')
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } | Should -Throw '*128*'
    }
    It 'akzeptiert eine gültige Konfiguration mit Prefix, Suffix und Overrides' {
        Set-Content $script:CfgPath '{"General":{"IdColumn":"ID","TimestampColumns":["GESPEICHERT"]},"MSSQL":{"Prefix":"AVERP_","Suffix":"_V1"},"Tables":["BKUNDE"],"TableOverrides":{"BKUNDE":{"IdColumn":"KD_ID","TimestampColumn":"CHANGED_AT"}}}'
        { Get-SQLSyncConfig -ConfigPath $script:CfgPath } | Should -Not -Throw
    }
}

Describe 'ConvertTo-SqlServerType' {
    It 'mappt <Type> (Size <Size>) auf <Expected>' -TestCases @(
        @{ Type = 'Int16'; Size = 0; Expected = 'SMALLINT' }
        @{ Type = 'Int32'; Size = 0; Expected = 'INT' }
        @{ Type = 'Int64'; Size = 0; Expected = 'BIGINT' }
        @{ Type = 'String'; Size = 50; Expected = 'NVARCHAR(50)' }
        @{ Type = 'String'; Size = 4000; Expected = 'NVARCHAR(4000)' }
        @{ Type = 'String'; Size = 4001; Expected = 'NVARCHAR(MAX)' }
        @{ Type = 'String'; Size = 0; Expected = 'NVARCHAR(MAX)' }
        @{ Type = 'DateTime'; Size = 0; Expected = 'DATETIME2' }
        @{ Type = 'TimeSpan'; Size = 0; Expected = 'TIME' }
        @{ Type = 'Decimal'; Size = 0; Expected = 'DECIMAL(18,4)' }   # ohne Precision/Scale: bisheriger Fallback
        @{ Type = 'Double'; Size = 0; Expected = 'FLOAT' }
        @{ Type = 'Single'; Size = 0; Expected = 'REAL' }
        @{ Type = 'Byte[]'; Size = 0; Expected = 'VARBINARY(MAX)' }
        @{ Type = 'Boolean'; Size = 0; Expected = 'BIT' }
        @{ Type = 'Guid'; Size = 0; Expected = 'UNIQUEIDENTIFIER' }
        @{ Type = 'Unbekannt'; Size = 0; Expected = 'NVARCHAR(MAX)' }
    ) {
        param($Type, $Size, $Expected)
        ConvertTo-SqlServerType -DotNetTypeName $Type -Size $Size | Should -Be $Expected
    }
}

Describe 'ConvertTo-SqlServerType: Decimal mit Precision/Scale (K2)' {
    It 'mappt Decimal(<P>,<S>) auf <Expected>' -TestCases @(
        @{ P = 15; S = 6; Expected = 'DECIMAL(15,6)' }    # z. B. Gewichte (real im Firebird-Schema)
        @{ P = 15; S = 5; Expected = 'DECIMAL(15,5)' }
        @{ P = 15; S = 2; Expected = 'DECIMAL(15,2)' }
        @{ P = 18; S = 0; Expected = 'DECIMAL(18,0)' }
        @{ P = 38; S = 10; Expected = 'DECIMAL(38,10)' }  # Firebird 4+ INT128
    ) {
        param($P, $S, $Expected)
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' -Precision $P -Scale $S | Should -Be $Expected
    }
    It 'begrenzt eine Precision über 38 auf 38' {
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' -Precision 40 -Scale 4 | Should -Be 'DECIMAL(38,4)'
    }
    It 'nutzt bei fehlender Precision, aber bekannter Scale DECIMAL(38,Scale)' {
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' -Precision ([DBNull]::Value) -Scale 6 | Should -Be 'DECIMAL(38,6)'
    }
    It 'fällt bei DBNull für beide Werte auf DECIMAL(18,4) zurück' {
        ConvertTo-SqlServerType -DotNetTypeName 'Decimal' -Precision ([DBNull]::Value) -Scale ([DBNull]::Value) | Should -Be 'DECIMAL(18,4)'
    }
    It 'ignoriert Precision/Scale bei Nicht-Decimal-Typen' {
        ConvertTo-SqlServerType -DotNetTypeName 'Int64' -Precision 18 -Scale 0 | Should -Be 'BIGINT'
    }
}

Describe 'Get-TableColumnConfig' {
    BeforeEach {
        $script:Cfg = @{ IdColumn = 'ID'; TimestampColumns = @('GESPEICHERT', 'CHANGED_AT'); TableOverrides = @{} }
    }
    It 'liefert Incremental bei ID- und Timestamp-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BKUNDE' -Config $script:Cfg -ActualColumns @('ID', 'NAME', 'GESPEICHERT')
        $r.SyncStrategy    | Should -Be 'Incremental'
        $r.IdColumn        | Should -Be 'ID'
        $r.TimestampColumn | Should -Be 'GESPEICHERT'
        $r.IsOverride      | Should -BeExactly $false
    }
    It 'nimmt die erste vorhandene Spalte aus TimestampColumns' {
        $r = Get-TableColumnConfig -TableName 'T' -Config $script:Cfg -ActualColumns @('ID', 'CHANGED_AT')
        $r.TimestampColumn | Should -Be 'CHANGED_AT'
    }
    It 'liefert FullMerge ohne Timestamp-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BKUNDE' -Config $script:Cfg -ActualColumns @('ID', 'NAME')
        $r.SyncStrategy    | Should -Be 'FullMerge'
        $r.TimestampColumn | Should -BeNullOrEmpty
    }
    It 'liefert Snapshot ohne ID-Spalte' {
        $r = Get-TableColumnConfig -TableName 'BSA' -Config $script:Cfg -ActualColumns @('NAME', 'GESPEICHERT')
        $r.SyncStrategy | Should -Be 'Snapshot'
        $r.IdColumn     | Should -BeNullOrEmpty
    }
    It 'bevorzugt TableOverrides vor den globalen Defaults' {
        $script:Cfg.TableOverrides['LEGACY_ORDERS'] = @{ IdColumn = 'ORDER_ID'; TimestampColumn = 'CHANGED_AT' }
        $r = Get-TableColumnConfig -TableName 'LEGACY_ORDERS' -Config $script:Cfg -ActualColumns @('ORDER_ID', 'GESPEICHERT', 'CHANGED_AT')
        $r.IdColumn        | Should -Be 'ORDER_ID'
        $r.TimestampColumn | Should -Be 'CHANGED_AT'
        $r.SyncStrategy    | Should -Be 'Incremental'
        $r.IsOverride      | Should -BeExactly $true
    }
    It 'fällt auf FullMerge zurück, wenn die Override-Timestamp-Spalte nicht existiert' {
        $script:Cfg.TableOverrides['T'] = @{ IdColumn = $null; TimestampColumn = 'FEHLT' }
        $r = Get-TableColumnConfig -TableName 'T' -Config $script:Cfg -ActualColumns @('ID', 'GESPEICHERT')
        $r.SyncStrategy | Should -Be 'FullMerge'
    }
}

Describe 'Connection-String-Builder' {
    BeforeAll {
        function Read-ConnectionString([string]$Cs) {
            $b = [System.Data.Common.DbConnectionStringBuilder]::new()
            $b.set_ConnectionString($Cs)
            # get_Item statt $b['...']: der PowerShell-Adapter löst den Indexer nicht zuverlässig auf
            , $b
        }
    }

    Context 'New-FirebirdConnectionString' {
        It 'maskiert ";" im Passwort, sodass kein weiterer Schlüssel eingeschleust wird' {
            $b = Read-ConnectionString (New-FirebirdConnectionString -Server 'fb' -Database 'C:\db\T.FDB' -Username 'SYSDBA' -Password 'ab;Port=1')
            $b.get_Item('Password') | Should -Be 'ab;Port=1'
            $b.get_Item('Port')     | Should -Be '3050'
        }
        It 'maskiert Anführungszeichen und "=" im Passwort' {
            $Pw = "a'b" + '"c=d'
            $b = Read-ConnectionString (New-FirebirdConnectionString -Server 'fb' -Database 'D' -Username 'U' -Password $Pw)
            $b.get_Item('Password') | Should -Be $Pw
        }
        It 'akzeptiert ein SecureString-Passwort' {
            $Sec = ConvertTo-SecureString 'geheim;1' -AsPlainText -Force
            $b = Read-ConnectionString (New-FirebirdConnectionString -Server 'fb' -Database 'D' -Username 'U' -Password $Sec)
            $b.get_Item('Password') | Should -Be 'geheim;1'
        }
        It 'setzt Server, Datenbank, Port, Dialect und Charset' {
            $b = Read-ConnectionString (New-FirebirdConnectionString -Server 'fb' -Database 'D' -Username 'U' -Password 'p' -Port 3051 -Charset 'WIN1252')
            $b.get_Item('DataSource') | Should -Be 'fb'
            $b.get_Item('Database')   | Should -Be 'D'
            $b.get_Item('Port')       | Should -Be '3051'
            $b.get_Item('Dialect')    | Should -Be '3'
            $b.get_Item('Charset')    | Should -Be 'WIN1252'
        }
    }

    Context 'New-MSSQLConnectionString' {
        It 'nutzt bei Integrated Security kein Passwort' {
            $b = Read-ConnectionString (New-MSSQLConnectionString -Server 'sql' -Database 'STAGING' -IntegratedSecurity $true)
            $b.get_Item('Integrated Security') | Should -Be 'True'
            $b.ContainsKey('Password')         | Should -BeExactly $false
        }
        It 'maskiert ";" im SQL-Passwort' {
            $b = Read-ConnectionString (New-MSSQLConnectionString -Server 'sql' -Database 'STAGING' -Username 'sa' -Password 'x;Database=master')
            $b.get_Item('Password') | Should -Be 'x;Database=master'
            $b.get_Item('Database') | Should -Be 'STAGING'
            $b.get_Item('User Id')  | Should -Be 'sa'
        }
        It 'akzeptiert ein SecureString-Passwort' {
            $Sec = ConvertTo-SecureString 'geheim' -AsPlainText -Force
            $b = Read-ConnectionString (New-MSSQLConnectionString -Server 'sql' -Database 'D' -Username 'sa' -Password $Sec)
            $b.get_Item('Password') | Should -Be 'geheim'
        }
    }
}

Describe 'Protect-SqlString' {
    It 'verdoppelt einfache Anführungszeichen' {
        Protect-SqlString "O'Brien" | Should -Be "O''Brien"
    }
    It 'gibt bei leerem Input einen Leerstring zurück' {
        Protect-SqlString '' | Should -Be ''
    }
    It 'gibt bei $null einen Leerstring zurück' {
        Protect-SqlString $null | Should -Be ''
    }
}

Describe 'Resolve-*Credentials: Reihenfolge und Fallback' {
    It 'Firebird: nimmt den Credential-Manager-Eintrag vor dem config.json-Fallback' {
        Mock -ModuleName SQLSyncCommon Get-StoredCredential { [PSCustomObject]@{ Username = 'SYNCUSER'; Password = 'dummy' } }
        $Raw = [PSCustomObject]@{ Firebird = [PSCustomObject]@{ Password = 'fallback' } }
        (Resolve-FirebirdCredentials -Config $Raw 6>$null).Source | Should -Be 'CredentialManager'
    }
    It 'Firebird: fällt auf config.json zurück und setzt User-Default SYSDBA' {
        Mock -ModuleName SQLSyncCommon Get-StoredCredential { $null }
        $Raw = [PSCustomObject]@{ Firebird = [PSCustomObject]@{ Password = 'dummy' } }
        $r = Resolve-FirebirdCredentials -Config $Raw 6>$null
        $r.Source   | Should -Be 'ConfigFile'
        $r.Username | Should -Be 'SYSDBA'
    }
    It 'MSSQL: fragt bei Integrated Security den Credential Manager nicht ab' {
        Mock -ModuleName SQLSyncCommon Get-StoredCredential { throw 'darf nicht aufgerufen werden' }
        $Raw = [PSCustomObject]@{ MSSQL = [PSCustomObject]@{ 'Integrated Security' = $true } }
        $r = Resolve-MSSQLCredentials -Config $Raw 6>$null
        $r.IntegratedSecurity | Should -BeExactly $true
        $r.Source             | Should -Be 'WindowsAuth'
        Should -Invoke Get-StoredCredential -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'MSSQL: fällt auf Username/Password aus config.json zurück' {
        Mock -ModuleName SQLSyncCommon Get-StoredCredential { $null }
        $Raw = [PSCustomObject]@{ MSSQL = [PSCustomObject]@{ Username = 'u'; Password = 'dummy' } }
        $r = Resolve-MSSQLCredentials -Config $Raw 6>$null
        $r.Source   | Should -Be 'ConfigFile'
        $r.Username | Should -Be 'u'
    }
}

Describe 'Get-StoredCredential' -Tag 'Windows' {
    It 'liefert $null für einen nicht existierenden Eintrag (nur lesend)' {
        Get-StoredCredential -Target "SQLSync_UnitTest_$([guid]::NewGuid())" | Should -BeNullOrEmpty
    }
}

Describe 'Close-DatabaseConnection' {
    BeforeEach {
        $script:Conn = [PSCustomObject]@{ Closed = 0; Disposed = 0 }
        $script:Conn | Add-Member ScriptMethod Close { $this.Closed++ }
        $script:Conn | Add-Member ScriptMethod Dispose { $this.Disposed++ }
    }
    It 'ignoriert $null' {
        { Close-DatabaseConnection -Connection $null } | Should -Not -Throw
    }
    It 'ruft Close und Dispose je einmal auf' {
        Close-DatabaseConnection -Connection $script:Conn
        $script:Conn.Closed   | Should -Be 1
        $script:Conn.Disposed | Should -Be 1
    }
    It 'ruft Dispose auch auf, wenn Close wirft' {
        $script:Conn | Add-Member ScriptMethod Close { throw 'kaputt' } -Force
        { Close-DatabaseConnection -Connection $script:Conn } | Should -Not -Throw
        $script:Conn.Disposed | Should -Be 1
    }
}

Describe 'Write-SyncStatus' {
    It 'schreibt "[Tabelle] Text" in der Farbe zu Level <Level>' -TestCases @(
        @{ Level = 'Info'; Color = 'Gray' }
        @{ Level = 'Success'; Color = 'Green' }
        @{ Level = 'Warning'; Color = 'Yellow' }
        @{ Level = 'Error'; Color = 'Red' }
    ) {
        param($Level, $Color)
        Mock -ModuleName SQLSyncCommon Write-Host { }
        Write-SyncStatus -TableName 'BKUNDE' -Message 'Hallo' -Level $Level
        Should -Invoke Write-Host -ModuleName SQLSyncCommon -Times 1 -Exactly -ParameterFilter {
            $Object -eq '[BKUNDE] Hallo' -and $ForegroundColor -eq $Color
        }
    }
}

Describe 'Initialize-FirebirdDriver' {
    BeforeAll {
        $script:DriverLoaded = [bool]([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'FirebirdSql.Data.FirebirdClient' })
        $script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    It 'lädt eine vorhandene DllPath-DLL ohne Download' {
        if ($script:DriverLoaded) { Set-ItResult -Skipped -Because 'Treiber ist in dieser Session bereits geladen (frische pwsh-Session nötig)'; return }
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Add-Type { }
        Mock -ModuleName SQLSyncCommon Invoke-WebRequest { throw 'darf nicht aufgerufen werden' }
        $p = Initialize-FirebirdDriver -DllPath 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll' 6>$null
        $p | Should -Be 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll'
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 1 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'wirft ohne Adminrechte, wenn der Treiber fehlt, und lädt nichts herunter' {
        if ($script:DriverLoaded) { Set-ItResult -Skipped -Because 'Treiber ist in dieser Session bereits geladen'; return }
        # Der innere Admin-Check ist nicht mockbar (docs/testing/UNIT_TESTS.md 4.2); als Admin liefe der Download-Pfad.
        if ($script:IsAdmin) { Set-ItResult -Skipped -Because 'läuft mit Adminrechten – Download-Pfad nicht unit-testbar'; return }
        Mock -ModuleName SQLSyncCommon Test-Path { $false }
        Mock -ModuleName SQLSyncCommon Add-Type { }
        Mock -ModuleName SQLSyncCommon Invoke-WebRequest { throw 'darf nicht aufgerufen werden' }
        { Initialize-FirebirdDriver -DllPath '' 6>$null } | Should -Throw '*ADMINISTRATOR*'
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 0 -Exactly
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
}
