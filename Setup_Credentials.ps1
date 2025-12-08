<#
.SYNOPSIS
    Speichert Zugangsdaten sicher im Windows Credential Manager.
    
.DESCRIPTION
    Einmalig ausführen, um Firebird- und SQL Server-Passwörter sicher zu hinterlegen.
    Die Credentials sind an den Windows-Benutzer UND den Computer gebunden.
    
.NOTES
    Nach Ausführung können die Passwörter aus config.json entfernt werden.

.LINK
    https://github.com/gitnol/PSFirebirdToMSSQL
#>

# -----------------------------------------------------------------------------
# CREDENTIAL TARGETS (Namen unter denen die Secrets gespeichert werden)
# -----------------------------------------------------------------------------
$TargetFirebird = "SQLSync_Firebird"
$TargetMSSQL = "SQLSync_MSSQL"

# -----------------------------------------------------------------------------
# FUNKTIONEN
# -----------------------------------------------------------------------------

function Set-StoredCredential {
    param(
        [string]$Target,
        [string]$Username,
        [securestring]$Password
    )
    
    # Nutzt cmdkey.exe (in Windows eingebaut)
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    $Result = cmdkey /generic:$Target /user:$Username /pass:$PlainPassword
    
    # Passwort aus Speicher löschen
    $PlainPassword = $null
    [System.GC]::Collect()
    
    return $LASTEXITCODE -eq 0
}

function Test-StoredCredential {
    param([string]$Target)
    
    return [bool]((cmdkey /list) -match $Target)
}

# -----------------------------------------------------------------------------
# HAUPTLOGIK
# -----------------------------------------------------------------------------

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SQLSync - Credential Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Die Zugangsdaten werden im Windows Credential Manager gespeichert."
Write-Host "Sie sind verschlüsselt und nur für DIESEN Benutzer auf DIESEM Computer abrufbar."
Write-Host ""

# --- FIREBIRD ---
Write-Host "--- Firebird Datenbank ---" -ForegroundColor Yellow

if (Test-StoredCredential -Target $TargetFirebird) {
    Write-Host "Credential '$TargetFirebird' existiert bereits." -ForegroundColor DarkGray
    $Overwrite = Read-Host "Überschreiben? [J/N]"
    if ($Overwrite -ne "J") {
        Write-Host "Übersprungen." -ForegroundColor DarkGray
    }
    else {
        $FbUser = Read-Host "Firebird Benutzername (z.B. SYSDBA)"
        $FbPass = Read-Host "Firebird Passwort" -AsSecureString
        
        if (Set-StoredCredential -Target $TargetFirebird -Username $FbUser -Password $FbPass) {
            Write-Host "Firebird Credential gespeichert." -ForegroundColor Green
        }
        else {
            Write-Host "Fehler beim Speichern!" -ForegroundColor Red
        }
    }
}
else {
    $FbUser = Read-Host "Firebird Benutzername (z.B. SYSDBA)"
    $FbPass = Read-Host "Firebird Passwort" -AsSecureString
    
    if (Set-StoredCredential -Target $TargetFirebird -Username $FbUser -Password $FbPass) {
        Write-Host "Firebird Credential gespeichert." -ForegroundColor Green
    }
    else {
        Write-Host "Fehler beim Speichern!" -ForegroundColor Red
    }
}

Write-Host ""

# --- MSSQL (nur wenn SQL Auth verwendet wird) ---
Write-Host "--- Microsoft SQL Server ---" -ForegroundColor Yellow
Write-Host "Hinweis: Bei 'Integrated Security' (Windows Auth) wird kein Passwort benötigt."
$UseSqlAuth = Read-Host "SQL Server Authentifizierung einrichten? [J/N]"

if ($UseSqlAuth -eq "J") {
    if (Test-StoredCredential -Target $TargetMSSQL) {
        Write-Host "Credential '$TargetMSSQL' existiert bereits." -ForegroundColor DarkGray
        $Overwrite = Read-Host "Überschreiben? [J/N]"
        if ($Overwrite -ne "J") {
            Write-Host "Übersprungen." -ForegroundColor DarkGray
        }
        else {
            $SqlUser = Read-Host "SQL Server Benutzername"
            $SqlPass = Read-Host "SQL Server Passwort" -AsSecureString
            
            if (Set-StoredCredential -Target $TargetMSSQL -Username $SqlUser -Password $SqlPass) {
                Write-Host "SQL Server Credential gespeichert." -ForegroundColor Green
            }
            else {
                Write-Host "Fehler beim Speichern!" -ForegroundColor Red
            }
        }
    }
    else {
        $SqlUser = Read-Host "SQL Server Benutzername"
        $SqlPass = Read-Host "SQL Server Passwort" -AsSecureString
        
        if (Set-StoredCredential -Target $TargetMSSQL -Username $SqlUser -Password $SqlPass) {
            Write-Host "SQL Server Credential gespeichert." -ForegroundColor Green
        }
        else {
            Write-Host "Fehler beim Speichern!" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "SQL Server Auth übersprungen (Windows Auth wird verwendet)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup abgeschlossen!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Gespeicherte Credentials anzeigen:" -ForegroundColor Gray
Write-Host "  cmdkey /list:SQLSync*" -ForegroundColor White
Write-Host ""
Write-Host "Credential löschen:" -ForegroundColor Gray
Write-Host "  cmdkey /delete:SQLSync_Firebird" -ForegroundColor White
Write-Host "  cmdkey /delete:SQLSync_MSSQL" -ForegroundColor White
Write-Host ""
Write-Host "WICHTIG: Entferne jetzt die Passwörter aus config.json!" -ForegroundColor Yellow
