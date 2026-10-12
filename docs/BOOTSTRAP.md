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

`docs_template/NEUES_PROJECT_INITIALISIEREN.md` (Schritt 5, Template-Repo) und `docs/KICKOFF.md` (Phase 1b)
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

## Schritt 1 — `.gitignore` und `.gitattributes` anlegen

Inhalt stack-spezifisch wählen:

| Stack | Pflicht-Einträge |
|---|---|
| `python-*` | `.venv/`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `*.db`, `.env`, `*.log` |
| `powershell-automation` | `*.log`, `config.ps1`, `*.tmp`, `*.secret` |
| `csharp-*` | `bin/`, `obj/`, `*.user`, `.vs/`, `packages/`, `*.suo`, `appsettings.*.json` (außer Default) |
| `react-web` | `node_modules/`, `dist/`, `coverage/`, `.env`, `.env.local` |
| `rust-cli` | `/target/` |
| alle | `*.pfx`, `*.pem`, `*.key` (siehe `operations/SECRETS_MANAGEMENT.md`) |

Plus projektspezifische Output-Verzeichnisse und Artefakte.

**Muster für Root-Dateien mit `/` verankern** (`/config*` statt `config*`): Ein unverankertes Muster greift in
jedem Unterordner — unter Windows (`core.ignorecase=true`) hätte `config*` auch
`docs/architecture/CONFIGURATION.md` ignoriert, die Datei wäre still nie committet worden. Vor dem ersten
Doku-Commit prüfen: `git ls-files --others --ignored --exclude-standard -- docs/` darf nichts außer `docs/local/`
zeigen
(rekursiv und shell-unabhängig; `git check-ignore -v docs/**/*.md` erfasst ohne `globstar` nur eine Ebene).

**`.gitattributes` (Pflicht):** mindestens `* text=auto eol=lf` — Text-Dateien landen mit LF im Repo
(`CONVENTIONS_COMMON.md` §2), unabhängig von `core.autocrlf`; Hook-Skripte (`sh`) brechen sonst mit CRLF.
Bringt ein Bestandsrepo eine eigene `.gitattributes` mit, die per `* text=auto` LF im Repo schon sicherstellt und
für einzelne Typen bewusst CRLF im Arbeitsbaum festlegt (`eol=crlf`), bleibt sie; ergänzt wird nur, was fehlt.

**Öffentliches oder potenziell öffentliches Repository** (siehe `CONVENTIONS_COMMON.md` 3.1): zusätzlich
`/docs/local/` (interne Umgebungsdoku) und `/.internal-terms` (Denylist für den Interna-Hook)
in die `.gitignore` aufnehmen und den Hook vor dem ersten Commit aktivieren: Vorlagen aus
`<Template-Root>/repo-root/tools/git-hooks/` nach `tools/git-hooks/` kopieren, `.internal-terms` aus
`<Template-Root>/repo-root/.internal-terms.example` anlegen und befüllen, dann
`git config core.hooksPath tools/git-hooks`. Die Hook-Skripte gehören in Commit 2 (Schritt 3) und werden mit
Ausführbit gestagt (`git add --chmod=+x tools/git-hooks/pre-commit tools/git-hooks/commit-msg`) — unter Windows
fehlt es sonst, und auf Linux/macOS-Klonen laufen die Hooks still nicht. Hat das Projekt schon einen
gleichwertigen Hook: `CONVENTIONS_COMMON.md` 3.1.

**Gilt auch für ein reines docs-I1:** Wenn I1 nur die `docs/`-Struktur erzeugt
und noch keinen produktiven Code enthält, wird die `.gitignore` trotzdem in
diesem Schritt angelegt und als Erstes committet (Commit-Reihenfolge bleibt
unverändert). Bereits in I1 mindestens die später relevanten Ausschlüsse
aufnehmen — für Document-Intelligence-Projekte z. B. `.env`, `.venv/`, `data/`,
`storage/`, `artifacts/`, `models/`, OCR-Ausgaben, `*.pdf`, `*.db`. In I2 wird
sie verfeinert, nicht neu begonnen.

---

## Schritt 2 — Commit 1: ausschließlich `.gitignore` und `.gitattributes`

```
git add .gitignore .gitattributes
git commit -m "chore: add .gitignore"
```

**Begründung:** `.gitignore` muss vor allen anderen Dateien committet sein,
damit spätere `git add`-Aufrufe keine sensiblen oder generierten Dateien
versehentlich erfassen; `.gitattributes` ebenso, damit jede spätere Text-Datei
von Anfang an mit LF im Repo landet. Die Commit-Message bleibt `chore: add .gitignore`.

---

## Schritt 3 — Commit 2: `docs/` + Einstiegsdateien (+ vorhandener Quellcode)

```
git add [Dateien einzeln oder bereichsweise]
git commit -m "docs: initialize project documentation baseline (I1)"
```

Diese Commit-Message ist die **einzige verbindliche Konvention** für den
Init-Commit. `docs_template/NEUES_PROJECT_INITIALISIEREN.md` (Schritt 5) und ein etwaiger
Prompt müssen dieselbe Message verwenden — keine konkurrierenden Varianten.

- **Greenfield/docs-only I1:** Commit 2 enthält ausschließlich `docs/` und die
  Einstiegsdateien `AGENTS.md` + `CLAUDE.md` im Repo-Root (Zeiger auf `docs/KICKOFF.md`,
  `docs_template/NEUES_PROJECT_INITIALISIEREN.md` Schritt 3c) — und ggf. ein bereits angelegtes
  `.gitignore`-fremdes Skeleton-Artefakt, falls der Prompt das vorsieht. Kein produktiver Code in I1.
- **Hook-Dateien, falls angelegt:** Skripte des Interna-Hooks unter `tools/git-hooks/` (öffentliches oder
  potenziell öffentliches Repo, `CONVENTIONS_COMMON.md` 3.1) und `.claude/settings.json` mit dem
  Advocatus-Diaboli-Hook (`KICKOFF.md` Phase 1 Punkt 7) gehören ebenfalls in Commit 2.
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

Erwartung (neues Repository): diese zwei Commits in dieser Reihenfolge, optional gefolgt vom Hash-Nachtrag
`docs: record I1 commit hash` (Schritt 3). Fällt danach noch ein Fehler in der Baseline auf, folgt ein
weiterer `docs:`-Commit (kein Amend, kein anderer Typ); Code-Änderungen gehören erst in I2:

1. `chore: add .gitignore`
2. `docs: initialize project documentation baseline (I1)`

Im Bestandsrepo (Bootstrap übersprungen) ist die Folge anders, siehe `NEUES_PROJECT_INITIALISIEREN.md` Schritt 5
(Template-Repo).

Danach ist das Repository für reguläre Inkrement-Arbeit bereit.
