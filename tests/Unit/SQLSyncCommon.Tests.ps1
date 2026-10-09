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

Describe 'Initialize-FirebirdDriver (Integrität, I7)' {
    BeforeAll {
        $script:DriverLoaded = [bool]([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'FirebirdSql.Data.FirebirdClient' })
        # Offizielle SHA-256 der DLLs aus dem NuGet-Paket 10.3.4 (am 2026-10-09 aus dem Paket von nuget.org nachgerechnet)
        $script:HashNet8 = '7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05'
        $script:HashNetStd21 = '8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A'
        $script:Dll = 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll'
    }
    BeforeEach {
        if ($script:DriverLoaded) { Set-ItResult -Skipped -Because 'Treiber ist in dieser Session bereits geladen (frische pwsh-Session nötig)' }
        Mock -ModuleName SQLSyncCommon Add-Type { }
        Mock -ModuleName SQLSyncCommon Invoke-WebRequest { throw 'darf nicht aufgerufen werden' }
        Mock -ModuleName SQLSyncCommon Expand-Archive { }
        Mock -ModuleName SQLSyncCommon New-Item { }
        Mock -ModuleName SQLSyncCommon Remove-Item { }
    }

    It 'lädt eine vorhandene DllPath-DLL mit Original-Hash (<Name>) ohne Download' -TestCases @(
        @{ Name = 'net8.0'; Hash = '7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05' }
        @{ Name = 'netstandard2.1'; Hash = '8176C7D5BA053EF1144C61C00CC1FBD4BEFCBEE4589BD18EAD673C97614A323A' }
    ) {
        param($Name, $Hash)
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $Hash } }
        Initialize-FirebirdDriver -DllPath $script:Dll 6>$null | Should -Be $script:Dll
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 1 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'lädt eine vorhandene DLL mit falschem Hash NICHT' {
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = ('0' * 64) } }
        { Initialize-FirebirdDriver -DllPath $script:Dll 6>$null } | Should -Throw '*SHA-256*'
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'akzeptiert eine abweichende DLL nur mit explizit erwartetem Hash (-ExpectedSha256)' {
        $Custom = 'AB' * 32
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $Custom } }
        Initialize-FirebirdDriver -DllPath $script:Dll -ExpectedSha256 $Custom.ToLower() 6>$null | Should -Be $script:Dll
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 1 -Exactly
    }
    It 'lehnt mit -ExpectedSha256 auch den Original-Hash ab, wenn er nicht dem erwarteten entspricht' {
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $script:HashNet8 } }
        { Initialize-FirebirdDriver -DllPath $script:Dll -ExpectedSha256 ('AB' * 32) 6>$null } | Should -Throw '*SHA-256*'
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'wirft ohne Adminrechte, wenn der Treiber fehlt, und lädt nichts herunter' {
        Mock -ModuleName SQLSyncCommon Test-Path { $false }
        Mock -ModuleName SQLSyncCommon Test-SQLSyncIsAdministrator { $false }
        { Initialize-FirebirdDriver -DllPath '' 6>$null } | Should -Throw '*ADMINISTRATOR*'
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 0 -Exactly
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'lädt als Admin herunter und lädt die DLL bei passendem Hash' {
        $script:Downloaded = $false
        Mock -ModuleName SQLSyncCommon Test-SQLSyncIsAdministrator { $true }
        Mock -ModuleName SQLSyncCommon Invoke-WebRequest { $script:Downloaded = $true }
        Mock -ModuleName SQLSyncCommon Test-Path { $script:Downloaded }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $script:HashNet8 } }
        Initialize-FirebirdDriver -DllPath '' 6>$null | Should -BeLike '*lib\net8.0\FirebirdSql.Data.FirebirdClient.dll'
        Should -Invoke Invoke-WebRequest -ModuleName SQLSyncCommon -Times 1 -Exactly
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 1 -Exactly
    }
    It 'verwirft einen Download mit falschem Hash und lädt nichts' {
        $script:Downloaded = $false
        Mock -ModuleName SQLSyncCommon Test-SQLSyncIsAdministrator { $true }
        Mock -ModuleName SQLSyncCommon Invoke-WebRequest { $script:Downloaded = $true }
        Mock -ModuleName SQLSyncCommon Test-Path { $script:Downloaded }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = ('0' * 64) } }
        { Initialize-FirebirdDriver -DllPath '' 6>$null } | Should -Throw '*SHA-256*'
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
        Should -Invoke Remove-Item -ModuleName SQLSyncCommon -ParameterFilter { $Recurse } -Times 1
    }
}

Describe 'Get-SQLSyncConfig: Firebird.DllSha256' {
    It 'übernimmt einen erwarteten Hash aus der Konfiguration' {
        $p = Join-Path $TestDrive 'cfg.dllhash.json'
        Set-Content $p ('{"Firebird":{"Server":"fb","Database":"C:\\db\\t.fdb","DllSha256":"' + ('AB' * 32) + '"},"MSSQL":{"Server":"s","Database":"STAGING"},"Tables":["T"]}')
        (Get-SQLSyncConfig -ConfigPath $p -SchemaPath (Join-Path $PSScriptRoot '..\..\config.schema.json')).DllSha256 | Should -Be ('AB' * 32)
    }
    It 'lehnt im Schema einen Wert ab, der kein SHA-256 ist' {
        $p = Join-Path $TestDrive 'cfg.dllhash.bad.json'
        Set-Content $p '{"Firebird":{"Server":"fb","Database":"C:\\db\\t.fdb","DllSha256":"xyz"},"MSSQL":{"Server":"s","Database":"STAGING"},"Tables":["T"]}'
        { Get-SQLSyncConfig -ConfigPath $p -SchemaPath (Join-Path $PSScriptRoot '..\..\config.schema.json') } | Should -Throw '*DllSha256*'
    }
}

Describe 'Get-FirebirdServerAdvisory (I11)' {
    It 'meldet beide CVEs für <Version>' -TestCases @(
        @{ Version = '5.0.3' }, @{ Version = '5.0.0' }, @{ Version = '4.0.6' }, @{ Version = '3.0.13' }, @{ Version = '2.5.9' }
    ) {
        param($Version)
        $r = @(Get-FirebirdServerAdvisory -EngineVersion $Version)
        $r.Id | Should -Contain 'CVE-2026-34232'
        $r.Id | Should -Contain 'CVE-2026-40342'
    }
    It 'meldet nichts für die behobene Version <Version>' -TestCases @(
        @{ Version = '5.0.4' }, @{ Version = '5.1.0' }, @{ Version = '4.0.7' }, @{ Version = '3.0.14' }, @{ Version = '6.0.0' }
    ) {
        param($Version)
        @(Get-FirebirdServerAdvisory -EngineVersion $Version).Count | Should -Be 0
    }
    It 'gibt bei unlesbarer Version einen Hinweis statt eines Fehlers' {
        $r = @(Get-FirebirdServerAdvisory -EngineVersion 'unbekannt')
        $r.Count | Should -Be 1
        $r[0].Id | Should -Be 'VERSION-UNBEKANNT'
    }
}

Describe 'Find-SQLSyncDecimalTruncation (I11)' {
    BeforeAll {
        function Col($T, $C, $P, $S) { [PSCustomObject]@{ Table = $T; Column = $C; Precision = $P; Scale = $S } }
    }
    It 'findet eine Zielspalte mit weniger Nachkommastellen als die Quelle' {
        $src = @(Col 'BANF' 'GEWICHT' 15 6), (Col 'BANF' 'PREIS' 15 2)
        $tgt = @(Col 'ERP_BANF' 'GEWICHT' 18 4), (Col 'ERP_BANF' 'PREIS' 18 4)
        $r = @(Find-SQLSyncDecimalTruncation -SourceColumns $src -TargetColumns $tgt -Prefix 'ERP_' -Suffix '')
        $r.Count | Should -Be 1
        $r[0].Table  | Should -Be 'BANF'
        $r[0].Target | Should -Be 'ERP_BANF'
        $r[0].Column | Should -Be 'GEWICHT'
        $r[0].Source | Should -Be 'NUMERIC(15,6)'
        $r[0].TargetType | Should -Be 'DECIMAL(18,4)'
    }
    It 'findet auch eine zu kleine Precision' {
        $r = @(Find-SQLSyncDecimalTruncation -SourceColumns @(Col 'T' 'X' 18 2) -TargetColumns @(Col 'T' 'X' 15 2) -Prefix '' -Suffix '')
        $r.Count | Should -Be 1
    }
    It 'meldet nichts bei passenden oder größeren Zieltypen und ignoriert fehlende Zieltabellen' {
        $src = @(Col 'T' 'A' 15 2), (Col 'T' 'B' 15 6), (Col 'NEU' 'C' 15 6)
        $tgt = @(Col 'T_V1' 'A' 15 2), (Col 'T_V1' 'B' 18 6)
        @(Find-SQLSyncDecimalTruncation -SourceColumns $src -TargetColumns $tgt -Prefix '' -Suffix '_V1').Count | Should -Be 0
    }
    It 'vergleicht Tabellen- und Spaltennamen ohne Groß-/Kleinschreibung' {
        $r = @(Find-SQLSyncDecimalTruncation -SourceColumns @(Col 'banf' 'gewicht' 15 6) -TargetColumns @(Col 'BANF' 'GEWICHT' 18 4) -Prefix '' -Suffix '')
        $r.Count | Should -Be 1
    }
}

Describe 'Test-FirebirdDriverIntegrity (I11)' {
    BeforeAll {
        $script:Dll = 'C:\nicht\real\FirebirdSql.Data.FirebirdClient.dll'
        $script:HashNet8 = '7DB04371004AE2BAB2EB3BE48454C605FC3171A3D73ED3B80C90DCD7E86CBC05'
    }
    BeforeEach { Mock -ModuleName SQLSyncCommon Add-Type { throw 'darf nicht geladen werden' } }
    It 'meldet OK für eine Original-DLL und lädt sie nicht' {
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $script:HashNet8 } }
        $r = Test-FirebirdDriverIntegrity -DllPath $script:Dll
        $r.Status | Should -Be 'OK'
        $r.Path   | Should -Be $script:Dll
        Should -Invoke Add-Type -ModuleName SQLSyncCommon -Times 0 -Exactly
    }
    It 'meldet FEHLER bei falschem Hash' {
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = ('0' * 64) } }
        (Test-FirebirdDriverIntegrity -DllPath $script:Dll).Status | Should -Be 'FEHLER'
    }
    It 'meldet FEHLT, wenn keine DLL vorhanden ist' {
        Mock -ModuleName SQLSyncCommon Test-Path { $false }
        (Test-FirebirdDriverIntegrity -DllPath '').Status | Should -Be 'FEHLT'
    }
    It 'beachtet -ExpectedSha256' {
        Mock -ModuleName SQLSyncCommon Test-Path { $true }
        Mock -ModuleName SQLSyncCommon Get-FileHash { [PSCustomObject]@{ Hash = $script:HashNet8 } }
        (Test-FirebirdDriverIntegrity -DllPath $script:Dll -ExpectedSha256 ('AB' * 32)).Status | Should -Be 'FEHLER'
    }
}

Describe 'Get-SQLSyncIncrementalLowerBound (I8)' {
    It 'liefert 1900-01-01 ohne Wasserzeichen (Erstlauf/leere Tabelle)' {
        Get-SQLSyncIncrementalLowerBound -Watermark $null -OverlapMinutes 10 | Should -Be ([datetime]'1900-01-01')
    }
    It 'zieht das Überlappungsfenster vom Wasserzeichen ab' {
        Get-SQLSyncIncrementalLowerBound -Watermark ([datetime]'2026-10-09 12:00:00') -OverlapMinutes 10 |
            Should -Be ([datetime]'2026-10-09 11:50:00')
    }
    It 'liefert bei Überlappung 0 das Wasserzeichen selbst' {
        Get-SQLSyncIncrementalLowerBound -Watermark ([datetime]'2026-10-09 12:00:00.123') -OverlapMinutes 0 |
            Should -Be ([datetime]'2026-10-09 12:00:00.123')
    }
    It 'wirft bei negativer Überlappung' {
        { Get-SQLSyncIncrementalLowerBound -Watermark ([datetime]'2026-10-09') -OverlapMinutes -1 } | Should -Throw
    }
}

Describe 'Get-SQLSyncIncrementalWatermark (I8)' {
    BeforeAll {
        # Nachbildung von SqlConnection/SqlCommand: protokolliert Abfragen, Antworten je Abfragetyp
        function New-FakeSqlConnection {
            param([int]$TableCount = 1, [object]$MaxValue = [DBNull]::Value, [switch]$MaxThrows)
            $Conn = [PSCustomObject]@{ Log = [System.Collections.Generic.List[object]]::new(); TableCount = $TableCount; MaxValue = $MaxValue; MaxThrows = [bool]$MaxThrows }
            $Conn | Add-Member ScriptMethod CreateCommand {
                $Owner = $this
                $Params = [PSCustomObject]@{ Items = @{} }
                $Params | Add-Member ScriptMethod AddWithValue { param($n, $v) $this.Items[$n] = $v }
                $Cmd = [PSCustomObject]@{ CommandText = ''; CommandTimeout = 0; Parameters = $Params; Owner = $Owner }
                $Cmd | Add-Member ScriptMethod ExecuteScalar {
                    $this.Owner.Log.Add([PSCustomObject]@{ Sql = $this.CommandText; Params = $this.Parameters.Items; Timeout = $this.CommandTimeout })
                    if ($this.CommandText -like '*INFORMATION_SCHEMA.TABLES*') { return $this.Owner.TableCount }
                    if ($this.Owner.MaxThrows) { throw "Invalid column name 'GESPEICHERT'." }
                    return $this.Owner.MaxValue
                }
                return $Cmd
            }
            return $Conn
        }
    }

    It 'meldet Erstlauf und fragt MAX nicht ab, wenn die Zieltabelle fehlt' {
        $Conn = New-FakeSqlConnection -TableCount 0
        $r = Get-SQLSyncIncrementalWatermark -Connection $Conn -TargetTableName 'DWH_T1' -TimestampColumn 'GESPEICHERT' -Timeout 30
        $r.Watermark | Should -BeNullOrEmpty
        $r.Reason    | Should -BeLike '*Zieltabelle fehlt*'
        @($Conn.Log | Where-Object Sql -like '*MAX(*').Count | Should -Be 0
    }
    It 'meldet eine leere Zieltabelle ohne Wasserzeichen' {
        $r = Get-SQLSyncIncrementalWatermark -Connection (New-FakeSqlConnection -MaxValue ([DBNull]::Value)) -TargetTableName 'DWH_T1' -TimestampColumn 'GESPEICHERT' -Timeout 30
        $r.Watermark | Should -BeNullOrEmpty
        $r.Reason    | Should -BeLike '*leer*'
    }
    It 'liefert MAX(ts) als Wasserzeichen ohne Hinweis' {
        $r = Get-SQLSyncIncrementalWatermark -Connection (New-FakeSqlConnection -MaxValue ([datetime]'2026-10-09 12:00')) -TargetTableName 'DWH_T1' -TimestampColumn 'GESPEICHERT' -Timeout 30
        $r.Watermark | Should -Be ([datetime]'2026-10-09 12:00')
        $r.Reason    | Should -BeNullOrEmpty
    }
    It 'wirft, wenn die MAX-Abfrage auf eine vorhandene Tabelle scheitert (kein stiller Vollabzug)' {
        { Get-SQLSyncIncrementalWatermark -Connection (New-FakeSqlConnection -MaxThrows) -TargetTableName 'DWH_T1' -TimestampColumn 'GESPEICHERT' -Timeout 30 } |
            Should -Throw '*GESPEICHERT*'
    }
    It 'übergibt den Tabellennamen als Parameter, quotet die Namen in MAX und setzt das Timeout' {
        $Conn = New-FakeSqlConnection -MaxValue ([datetime]'2026-10-09')
        $null = Get-SQLSyncIncrementalWatermark -Connection $Conn -TargetTableName 'DWH_T1' -TimestampColumn 'GESPEICHERT' -Timeout 77
        $Conn.Log[0].Params['@TableName'] | Should -Be 'DWH_T1'
        $Conn.Log[1].Sql | Should -Be 'SELECT MAX([GESPEICHERT]) FROM [DWH_T1]'
        $Conn.Log.Timeout | Should -Be @(77, 77)
    }
    It 'akzeptiert Zielnamen über 63 Zeichen (Prefix + Tabelle + Suffix, bis 128)' {
        $Long = 'P' * 70
        $r = Get-SQLSyncIncrementalWatermark -Connection (New-FakeSqlConnection -MaxValue ([datetime]'2026-10-09')) -TargetTableName $Long -TimestampColumn 'GESPEICHERT' -Timeout 30
        $r.Watermark | Should -Be ([datetime]'2026-10-09')
    }
    It 'lehnt ungültige Namen ab, bevor SQL ausgeführt wird' {
        $Conn = New-FakeSqlConnection
        { Get-SQLSyncIncrementalWatermark -Connection $Conn -TargetTableName 'T];DROP' -TimestampColumn 'GESPEICHERT' -Timeout 30 } | Should -Throw
        $Conn.Log.Count | Should -Be 0
    }
}

Describe 'Get-SQLSyncExtractQuery (I8)' {
    It 'liest inkrementell inklusive Untergrenze (>=)' {
        Get-SQLSyncExtractQuery -TableName 'BKUNDE' -TimestampColumn 'GESPEICHERT' -Incremental |
            Should -BeExactly 'SELECT * FROM "BKUNDE" WHERE "GESPEICHERT" >= @LastDate'
    }
    It 'liest ohne -Incremental die ganze Tabelle' {
        Get-SQLSyncExtractQuery -TableName 'BKUNDE' | Should -BeExactly 'SELECT * FROM "BKUNDE"'
    }
    It 'verlangt bei -Incremental eine Zeitstempelspalte' {
        { Get-SQLSyncExtractQuery -TableName 'BKUNDE' -Incremental } | Should -Throw
    }
    It 'lehnt ungültige Namen ab' {
        { Get-SQLSyncExtractQuery -TableName 'B"KUNDE' } | Should -Throw
    }
}

Describe 'Get-SQLSyncConfig: IncrementalOverlapMinutes (I8)' {
    BeforeAll {
        $script:OverlapPath = Join-Path $TestDrive 'config.overlap.json'
        function Write-OverlapConfig([hashtable]$General) {
            @{ General = $General; Tables = @('T1') } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:OverlapPath
        }
    }
    It 'ist standardmäßig 10 Minuten' {
        Write-OverlapConfig @{}
        (Get-SQLSyncConfig -ConfigPath $script:OverlapPath).IncrementalOverlapMinutes | Should -Be 10
    }
    It 'übernimmt 0 aus der Konfiguration' {
        Write-OverlapConfig @{ IncrementalOverlapMinutes = 0 }
        (Get-SQLSyncConfig -ConfigPath $script:OverlapPath).IncrementalOverlapMinutes | Should -Be 0
    }
    It 'wirft bei Werten außerhalb 0..1440' -TestCases @(@{ V = -1 }, @{ V = 1441 }) {
        Write-OverlapConfig @{ IncrementalOverlapMinutes = $V }
        { Get-SQLSyncConfig -ConfigPath $script:OverlapPath } | Should -Throw '*IncrementalOverlapMinutes*'
    }
}
