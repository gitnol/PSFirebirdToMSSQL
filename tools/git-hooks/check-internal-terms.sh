#!/bin/sh
# Prüft Text auf interne Begriffe aus .internal-terms (Repo-Root, gitignored).
# Aufruf: check-internal-terms.sh staged      -> hinzugefügte Zeilen + Dateinamen des Index
#         check-internal-terms.sh msg <datei> -> Commit-Message
# Exit 1 bei Treffer (Commit wird abgebrochen), sonst 0.
# Aktivierung (einmalig pro Klon): git config core.hooksPath tools/git-hooks

ROOT=$(git rev-parse --show-toplevel)
TERMS="$ROOT/.internal-terms"

if [ ! -f "$TERMS" ]; then
    echo "WARNUNG: $TERMS fehlt - Prüfung auf interne Begriffe übersprungen." >&2
    echo "         Vorlage: docs/CONVENTIONS.md, Abschnitt 'Öffentliches Repository'." >&2
    exit 0
fi

check() {
    # stdin: Zeilen im Format "<quelle>\t<text>"; gibt Treffer aus, Exit 1 bei Treffer
    awk -F '\t' -v termsfile="$TERMS" '
        BEGIN {
            while ((getline line < termsfile) > 0) {
                sub(/\r$/, "", line)
                if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
                terms[++n] = tolower(line)
            }
        }
        {
            text = tolower($2)
            for (i = 1; i <= n; i++) {
                if (index(text, terms[i]) > 0) {
                    printf "  %s: \"%s\" (Begriff: %s)\n", $1, substr($2, 1, 120), terms[i]
                    found = 1
                    break
                }
            }
        }
        END { exit found ? 1 : 0 }
    '
}

case "$1" in
    staged)
        {
            git diff --cached --name-only --diff-filter=ACMR | awk '{ printf "Dateiname\t%s\n", $0 }'
            git diff --cached -U0 --no-color --diff-filter=ACMR | awk '
                /^\+\+\+ b\// { file = substr($0, 7); next }
                /^@@/        { split($3, a, ","); ln = substr(a[1], 2); next }
                /^\+/        { printf "%s:%s\t%s\n", file, ln, substr($0, 2); ln++ }
            '
        } | check
        rc=$?
        ;;
    msg)
        awk '!/^#/ { printf "Commit-Message:%d\t%s\n", NR, $0 }' "$2" | check
        rc=$?
        ;;
    *)
        echo "Aufruf: $0 staged | msg <datei>" >&2
        exit 2
        ;;
esac

if [ "$rc" -ne 0 ]; then
    echo "" >&2
    echo "ABGEBROCHEN: interne Begriffe gefunden (siehe oben). Öffentliches Repository!" >&2
    echo "Interna gehören nach docs/local/ (gitignored); öffentlich nur generische Bezeichnungen." >&2
    exit 1
fi
exit 0
