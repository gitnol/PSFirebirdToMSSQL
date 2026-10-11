# Threat-Model-Leitfragen

Hilfe zum Finden von Bedrohungen für `security/THREAT_MODEL.md` — beim Init und bei jeder
sicherheitsrelevanten Änderung (Trigger-Matrix `KICKOFF.md` Phase 3a).

**Diese Datei wird vom Template gepflegt und bei Template-Updates ersetzt (Kategorie A).**
Nicht lokal ändern; projektspezifische Leitfragen oder Bedrohungen gehören in `security/THREAT_MODEL.md`.

## Regeln

- Bedrohungen ausschließlich aus dem tatsächlichen Code (bzw. bei Greenfield aus der Zielarchitektur)
  ableiten — keine generischen OWASP-Listings ohne Projektbezug.
- Mindestens 3 konkrete Bedrohungen, jede mit Angriffsvektor (Modul/Zeile), Mitigation und Restrisiko.
- Jede Ja-Antwort unten ist ein Bedrohungskandidat: belegen (Code-Stelle) oder begründet verwerfen.

## Leitfragen

### Credentials & Secrets

- Wo werden Credentials gespeichert? (Datei, Env, Keychain, Hardcoded?)
- Könnte eine fehlende .gitignore Credentials in git landen lassen?
- Werden Secrets in Logs oder Fehlermeldungen ausgegeben?

### Externe Datenflüsse

- Welche Daten verlassen das System? An welche externen Services?
- Welche Daten kommen herein? Aus welcher Quelle? Werden sie validiert?
- Gibt es User-Eingaben (CLI, Web, API), die ungefiltert in Queries/Pfade/Befehle fließen?
- Fließt externer/fremder Inhalt (Dokument/OCR/VLM/RAG/Tool-Output, E-Mail) ungetrennt in einen
  LLM-Prompt? → Indirect Prompt Injection (OWASP LLM01) als konkrete Bedrohung modellieren;
  Maßnahmen-Raster im Prinzip `principles/UNTRUSTED_DOCUMENT_CONTENT.md` (nicht-agentisch / Daten-Grenze /
  Bekanntwert-Gegenprüfung / Scan+Audit).

### Persistenz & Output

- Welche Dateien enthalten personenbezogene oder sensible Daten?
- Wo werden diese Dateien gespeichert? Wer hat Zugriff?
- Werden alte Dateien akkumuliert oder überschrieben?

### Kapselung & Code-Qualität

- Gibt es direkte Zugriffe auf private Attribute von außen?
- Könnte ein Logging-Call versehentlich ein Credentials-Objekt serialisieren?
- Werden Fehler still geschluckt (leeres except/catch)?

### Berechtigungen

- Hat jede Komponente nur die minimal nötigen Rechte?
- Könnte ein kompromittierter API-Key mehr Schaden anrichten als nötig?

### Aktualität der Lage (`principles/SECURITY_CURRENCY.md`)

- Ist der reale Bestand (Deps/Tools/Versionen/SBOM) bekannt — oder wird geraten?
- Wurde die aktuelle öffentliche Lage (Best Practices, CVEs/Advisories) für
  Base+Stack web-recherchiert, datiert und gegen die real verbaute Version belegt?
