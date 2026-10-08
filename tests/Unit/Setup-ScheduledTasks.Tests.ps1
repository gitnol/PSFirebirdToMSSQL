#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Testet Setup-ScheduledTasks.ps1 ausschließlich mit -WhatIf: keine Adminrechte, keine Passwortabfrage,
# keine Registrierung in der Aufgabenplanung. Register-/Unregister-ScheduledTask sind zusätzlich gemockt.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Script = Join-Path $script:RepoRoot 'Setup-ScheduledTasks.ps1'

    function Invoke-Setup {
        param([hashtable]$Params = @{})
        & $script:Script @Params -WhatIf 6>$null
    }
}

Describe 'Setup-ScheduledTasks.ps1 (-WhatIf)' {
    BeforeEach {
        Mock Register-ScheduledTask { throw 'darf unter -WhatIf nicht aufgerufen werden' }
        Mock Unregister-ScheduledTask { throw 'darf unter -WhatIf nicht aufgerufen werden' }
        Mock Get-Credential { throw 'darf unter -WhatIf nicht aufgerufen werden' }
    }

    Context 'Defaults' {
        BeforeAll { $script:Tasks = @(Invoke-Setup) }

        It 'liefert genau zwei Task-Definitionen' {
            $script:Tasks.Count | Should -Be 2
            $script:Tasks.TaskName | Should -Be @('SQLSync_Firebird_Daily_Diff', 'SQLSync_Firebird_Weekly_Full')
        }
        It 'nutzt den Skriptordner als Installations- und Arbeitsverzeichnis' {
            foreach ($t in $script:Tasks) {
                $t.Action.WorkingDirectory | Should -Be $script:RepoRoot
                $t.Action.Arguments | Should -BeLike "*-File `"$script:RepoRoot\Sync_Firebird_MSSQL_AutoSchema.ps1`"*"
            }
        }
        It 'verwendet config.json (täglich) und config_weekly_full.json (wöchentlich)' {
            $script:Tasks[0].Action.Arguments | Should -BeLike "*-ConfigFile `"$script:RepoRoot\config.json`"*"
            $script:Tasks[1].Action.Arguments | Should -BeLike "*-ConfigFile `"$script:RepoRoot\config_weekly_full.json`"*"
        }
        It 'plant den Tageslauf Mo–Fr ab 06:01 alle 30 Minuten für 15 Stunden ohne harten Abbruch' {
            $tr = $script:Tasks[0].Trigger
            ([datetime]$tr.StartBoundary).ToString('HH:mm') | Should -Be '06:01'
            $tr.DaysOfWeek | Should -Be 62   # Mo(2)+Di(4)+Mi(8)+Do(16)+Fr(32)
            $tr.Repetition.Interval | Should -Be 'PT30M'
            $tr.Repetition.Duration | Should -Be 'PT15H'
            $tr.Repetition.StopAtDurationEnd | Should -BeExactly $false
        }
        It 'plant den Wochenlauf sonntags um 05:13' {
            $tr = $script:Tasks[1].Trigger
            ([datetime]$tr.StartBoundary).ToString('HH:mm') | Should -Be '05:13'
            $tr.DaysOfWeek | Should -Be 1     # So(1)
        }
        It 'startet keine zweite Instanz, solange eine läuft' {
            foreach ($t in $script:Tasks) { "$($t.Settings.MultipleInstances)" | Should -Be 'IgnoreNew' }
        }
        It 'registriert nichts' {
            foreach ($t in $script:Tasks) { $t.Registered | Should -BeExactly $false }
            Should -Invoke Register-ScheduledTask -Times 0 -Exactly
            Should -Invoke Get-Credential -Times 0 -Exactly
        }
    }

    Context 'Parameter' {
        It 'löst relative Konfignamen gegen -InstallDir auf' {
            $Tasks = @(Invoke-Setup @{ InstallDir = 'D:\Apps\SQLSync'; DailyConfigFile = 'cfg_daily.json'; WeeklyConfigFile = 'cfg_full.json' })
            $Tasks[0].Action.Arguments | Should -BeLike '*-File "D:\Apps\SQLSync\Sync_Firebird_MSSQL_AutoSchema.ps1"*'
            $Tasks[0].Action.Arguments | Should -BeLike '*-ConfigFile "D:\Apps\SQLSync\cfg_daily.json"*'
            $Tasks[1].Action.Arguments | Should -BeLike '*-ConfigFile "D:\Apps\SQLSync\cfg_full.json"*'
            $Tasks[0].Action.WorkingDirectory | Should -Be 'D:\Apps\SQLSync'
        }
        It 'übernimmt absolute Konfigpfade unverändert' {
            $Tasks = @(Invoke-Setup @{ InstallDir = 'D:\Apps\SQLSync'; DailyConfigFile = 'X:\cfg\daily.json' })
            $Tasks[0].Action.Arguments | Should -BeLike '*-ConfigFile "X:\cfg\daily.json"*'
        }
        It 'übernimmt Taskname, Zeitplan und Intervall' {
            $Tasks = @(Invoke-Setup @{ DailyTaskName = 'T_Daily'; DailyStart = '07:15'; DailyIntervalMinutes = 60; DailyDurationHours = 10; WeeklyDay = 'Saturday'; WeeklyStart = '22:00' })
            $Tasks[0].TaskName | Should -Be 'T_Daily'
            ([datetime]$Tasks[0].Trigger.StartBoundary).ToString('HH:mm') | Should -Be '07:15'
            $Tasks[0].Trigger.Repetition.Interval | Should -Be 'PT1H'
            $Tasks[0].Trigger.Repetition.Duration | Should -Be 'PT10H'
            ([datetime]$Tasks[1].Trigger.StartBoundary).ToString('HH:mm') | Should -Be '22:00'
            $Tasks[1].Trigger.DaysOfWeek | Should -Be 64    # Sa(64)
        }
        It 'legt mit -GmsaAccount einen Principal ohne gespeichertes Passwort an' {
            $Tasks = @(Invoke-Setup @{ GmsaAccount = 'CONTOSO\svc_sqlsync$' })
            foreach ($t in $Tasks) {
                $t.Principal.UserId | Should -Be 'CONTOSO\svc_sqlsync$'
                "$($t.Principal.LogonType)" | Should -Be 'Password'
            }
        }
        It 'nutzt ohne -GmsaAccount den angegebenen bzw. aktuellen Benutzer' {
            $Tasks = @(Invoke-Setup @{ RunAsUser = 'CONTOSO\svc_sync' })
            $Tasks[0].Principal.UserId | Should -Be 'CONTOSO\svc_sync'
        }
    }

    Context 'Keine internen Werte im Skript' {
        It 'enthält keine fest eingetragenen Laufwerkspfade' {
            Get-Content $script:Script -Raw | Should -Not -Match '[A-Za-z]:\\\\?SQLSync'
        }
    }
}
