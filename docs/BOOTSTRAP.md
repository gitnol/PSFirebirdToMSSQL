# Git-Bootstrap – PSFirebirdToMSSQL

Dieser Schritt wird genau einmal pro Projekt durchgeführt: bei der ersten
Initialisierung des Repositories. Spätere Sessions überspringen ihn.

> **Projektstatus (2026-10-08):** Bootstrap **übersprungen** — das Repository hatte bei der
> docs-Initialisierung bereits 67 Commits auf `main` (letzter Code-Commit `721d5e0`).
> Die vorhandene `.gitignore` wurde in I1 überarbeitet (Muster `config*` auf Root verankert,
> siehe `LESSONS_LEARNED.md` L1) und zusammen mit `docs/` im Init-Commit
> `docs: initialize project documentation baseline (I1)` committet; der Hash wird per
> Nachtrags-Commit in `STATE.md` eingetragen. Pflicht-Ausschlüsse dieses Projekts:
> `/config*` (außer `config.sample.json`, `config.schema.json`), `*.bak`, `Logs/`, `*.log`,
> Secret-Dateitypen, `*.dll`/`*.nupkg`, Test-Artefakte, `/docs/local/` (Interna) und
> `/.internal-terms` (Denylist des Interna-Hooks, siehe `CONVENTIONS.md` 6.2).
> Nach jedem Klon einmalig: `git config core.hooksPath tools/git-hooks`.

`NEUES_PROJECT_INITIALISIEREN.md` (Schritt 5) und `docs/KICKOFF.md` (Phase 1b)
verweisen ausschließlich auf dieses Dokument — die Bootstrap-Logik existiert
nur hier.

---

## Vorbedingung — Status prüfen

```
git log --oneline -1 2>&1
```

- Es existiert bereits ein Commit → Bootstrap überspringen, direkt mit der
  regulären Inkrement-Arbeit fortfahren.
- Es existiert **kein** Commit → mit Schritt 1 fortfahren.

---

## Schritt 1 — `.gitignore` anlegen

Inhalt stack-spezifisch wählen:

| Stack | Pflicht-Einträge |
|---|---|
| `python-*` | `.venv/`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `*.db`, `.env`, `*.log` |
| `powershell-automation` | `*.log`, `config.ps1`, `*.tmp`, `*.secret` |
| `csharp-*` | `bin/`, `obj/`, `*.user`, `.vs/`, `packages/`, `*.suo`, `appsettings.*.json` (außer Default) |

Plus projektspezifische Output-Verzeichnisse und Artefakte.

**Gilt auch für ein reines docs-I1:** Wenn I1 nur die `docs/`-Struktur erzeugt
und noch keinen produktiven Code enthält, wird die `.gitignore` trotzdem in
diesem Schritt angelegt und als Erstes committet (Commit-Reihenfolge bleibt
unverändert). Bereits in I1 mindestens die später relevanten Ausschlüsse
aufnehmen — für Document-Intelligence-Projekte z. B. `.env`, `.venv/`, `data/`,
`storage/`, `artifacts/`, `models/`, OCR-Ausgaben, `*.pdf`, `*.db`. In I2 wird
sie verfeinert, nicht neu begonnen.

---

## Schritt 2 — Commit 1: ausschließlich `.gitignore`

```
git add .gitignore
git commit -m "chore: add .gitignore"
```

**Begründung:** `.gitignore` muss vor allen anderen Dateien committet sein,
damit spätere `git add`-Aufrufe keine sensiblen oder generierten Dateien
versehentlich erfassen.

---

## Schritt 3 — Commit 2: `docs/` (+ vorhandener Quellcode)

```
git add [Dateien einzeln oder bereichsweise]
git commit -m "docs: initialize project documentation baseline (I1)"
```

Diese Commit-Message ist die **einzige verbindliche Konvention** für den
Init-Commit. `NEUES_PROJECT_INITIALISIEREN.md` (Schritt 5) und ein etwaiger
Prompt müssen dieselbe Message verwenden — keine konkurrierenden Varianten.

- **Greenfield/docs-only I1:** Commit 2 enthält ausschließlich `docs/` (und
  ggf. ein bereits angelegtes `.gitignore`-fremdes Skeleton-Artefakt, falls der
  Prompt das vorsieht). Kein produktiver Code in I1.
- **Bestehende Codebase:** Commit 2 enthält zusätzlich den bewusst ausgewählten
  Quellcode.
- **Commit-Hash in `STATE.md`:** Soll der I1-Hash in `STATE.md` stehen, ist er
  vor dem Commit noch unbekannt. Sauber lösen durch einen kleinen Nachtrags-
  Commit (`docs: record I1 commit hash`) oder dokumentierte Vorgehensweise —
  niemals einen falschen/leeren Hash eintragen.

**Verbote:**

- Niemals sensible Dateien (`config.ps1`, `.env`, `*.db`, `appsettings.Production.json`)
  in Commit 2 — die `.gitignore` schützt sie nur, wenn man sie nicht explizit `add`t.
- Niemals `git add .` — Risiko ungewollter Datei-Aufnahme bleibt zu hoch,
  selbst mit `.gitignore`.

---

## Schritt 4 — Abschluss verifizieren

```
git log --oneline
```

Erwartung: genau zwei Commits, in dieser Reihenfolge:

1. `chore: add .gitignore`
2. `docs: initialize project documentation baseline (I1)`

Danach ist das Repository für reguläre Inkrement-Arbeit bereit.
