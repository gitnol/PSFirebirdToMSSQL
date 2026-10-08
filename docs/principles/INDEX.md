# Principles Index – PSFirebirdToMSSQL

Lade nur die Dateien, die für die aktuelle Aufgabe relevant sind.
**Immer gültig:** Fail Fast, Explicit over Implicit, Context Discipline,
Verify before Cite, Advocatus Diaboli (vor jedem Commit).

| Prinzip | Datei | Wann relevant? |
|---------|-------|---------------|
| Fail Fast | FAIL_FAST.md | IMMER – Validierung, Fehlerbehandlung |
| Explicit | EXPLICIT_OVER_IMPLICIT.md | IMMER – Typen, Benennung, Rückgabewerte |
| Context Discipline | CONTEXT_DISCIPLINE.md | IMMER – LLM-Agent: welche Dateien laden, welche nicht |
| Verify before Cite | VERIFY_BEFORE_CITE.md | IMMER – LLM-Agent: nur zitieren, was nachweislich existiert |
| Advocatus Diaboli | ADVOCATUS_DIABOLI.md | IMMER vor Commit – eigene Schlüsse/Scope adversarial prüfen; Behauptung belegen oder fallenlassen |
| Ceteris Paribus | CETERIS_PARIBUS.md | Tests/Benchmarks/Bugfixes mit Schlussfolgerung – genau eine Variable pro Lauf, sonst keine kausale Aussage |
| Separation of Concerns | SEPARATION_OF_CONCERNS.md | Architekturentscheidungen, neue Module/Schichten, UI vs. Domäne |
| DRY | DRY.md | Refactoring, doppelte Logik |
| YAGNI | YAGNI.md | Architektur, Feature-Scope |
| Stdlib First | STDLIB_FIRST.md | Implementierung – sobald YAGNI grünes Licht gibt |
| Immutability | IMMUTABILITY.md | State-Management |
| Orthogonality | ORTHOGONALITY.md | Entkopplung, neue Module |
| Contracts | CONTRACTS.md | Neue Funktionen, Docstrings, Preconditions |
| Logging | LOGGING.md | Ausgabe-Strategie, Logging vs. print() |
| External Source Adoption | EXTERNAL_SOURCE_ADOPTION.md | Adoption von LLM-konvertierten/Community-Specs/generierten Schemas — Provenance + Validator-Pflicht |
| Untrusted Content | UNTRUSTED_DOCUMENT_CONTENT.md | Externer Inhalt (Dokument/OCR/VLM/RAG/Tool) fließt in einen LLM-Prompt — Prompt-Injection (OWASP LLM01): Daten/Anweisung trennen, nicht-agentisch, Bekanntwert-Gegenprüfung |
| Security Currency | SECURITY_CURRENCY.md | Sicherheitsrelevantes Inkrement oder Stack-/Dependency-Adoption — Bestand (Deps/SBOM) feststellen, dann Websuche nach aktuellen Best Practices + CVEs für Base+Stack, Treffer gegen reale Version belegen |
| Placeholder Discipline | PLACEHOLDER_DISCIPLINE.md | Jeder Scaffold/Stub im Produktionspfad muss Name, Docstring und Known-Issues-Eintrag haben |
| Vertical Slice First | VERTICAL_SLICE_FIRST.md | Erst den durchgängigen Slice als E2E-Spec; Test-Doubles im Unit-Pfad; echte Engine hinter @slow/@live |

**Projekt-Hinweise (PSFirebirdToMSSQL):**

- *Untrusted Content* betrifft hier keine LLM-Prompts (das Projekt nutzt kein LLM), sondern
  Identifier aus Firebird-Metadaten und `config.json`, die in SQL eingesetzt werden
  (S2; seit I4 per Allow-List geprüft und gequotet) — siehe Abschnitt „Projektspezifisch" in
  `UNTRUSTED_DOCUMENT_CONTENT.md`.
- *External Source Adoption* betrifft den NuGet-Treiber und `config.schema.json`.
- *Security Currency*: Sweep-Intervall 14 Tage, nächster Sweep 2026-10-22.
