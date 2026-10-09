# Feature: <FEATURE-NAME>

Vorlage für Feature-Beschreibungen in PSFirebirdToMSSQL. Kopieren nach
`docs/features/<feature-name>.md`, alle Felder in spitzen Klammern ersetzen,
nicht zutreffende Abschnitte mit „trifft nicht zu" markieren. Beispiel einer
ausgefüllten Fassung: `features/firebird-mssql-sync.md`.

---

## Zweck

<Was macht dieses Feature? Welche Automatisierungsaufgabe löst es? Ein Satz reicht.>

---

## Technologie / Abhängigkeiten

- <MODUL/BIBLIOTHEK – z. B. `FirebirdSql.Data.FirebirdClient`, `System.Data.SqlClient`>
- <EXTERNE RESSOURCE – z. B. „Firebird-Server Port 3050", „SQL-Server-Ziel-DB">
- <FUNKTIONEN AUS SQLSyncCommon.psm1 – z. B. `Get-SQLSyncConfig`>

---

## Parameter

| Parameter | Typ | Pflicht | Default | Validierung | Beschreibung |
|-----------|-----|---------|---------|-------------|-------------|
| `-<Param1>` | `[string]` | Ja | – | `ValidateNotNullOrEmpty` | <BESCHREIBUNG> |
| `-<Param2>` | `[int]` | Nein | `<DEFAULT>` | `ValidateRange(1,100)` | <BESCHREIBUNG> |
| `-WhatIf` | Switch | Nein | `$false` | – | Dry-Run: keine Änderungen vornehmen (nur falls unterstützt) |

Konfigschalter (falls das Feature über die Konfigdatei gesteuert wird):

| Schlüssel | Default | Wirkung |
|---|---|---|
| `<Sektion>.<Schlüssel>` | `<DEFAULT>` | <WIRKUNG> |

---

## Ablauf

1. <SCHRITT 1>
2. <SCHRITT 2>

---

## Exit-Codes

| Code | Bedeutung |
|---|---|
| `0` | <BEDEUTUNG> |
| `<n>` | <BEDEUTUNG> |

---

## Kritische Patterns

- <PATTERN 1 – z. B. „Verbindungen im `finally` schließen und disposen">
- <PATTERN 2 – z. B. „SQL-Identifier nur über QUOTENAME bzw. eckige Klammern">

---

## Bekannte Einschränkungen

| Einschränkung | Ursache | Status |
|---------------|---------|--------|
| <EINSCHRÄNKUNG> | <URSACHE> | <Geplant in I# / Akzeptiert, Verweis docs/KNOWN_ISSUES.md> |

---

## Bekannte Fallstricke

- <FALLSTRICK 1 – z. B. „Invoke-Expression mit Benutzerpfaden vermeiden – Command-Injection-Risiko">

---

## Teststrategie

- Zugehörige Testdatei: `tests/<Feature>.Tests.ps1` (Pester 5, Harness siehe `docs/testing/UNIT_TESTS.md`)
- Pester-Beschreibung: `Describe '<FEATURE>' { ... }`
- Kritische Testfälle: <z. B. „ungültige Konfig → Exception; fehlende Tabelle → Status Fehler">

---

## Akzeptanzkriterien

- [ ] <KRITERIUM 1>
- [ ] <KRITERIUM 2>
