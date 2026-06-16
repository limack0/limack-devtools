#!/usr/bin/env sh
# peek — the antidote to `curl | sh`.
# Inspect a remote install script: score its risk, show the dangerous lines,
# then ask before running. The trust layer the whole `| sh` culture is missing.
#
#   peek https://example.com/install.sh      # fetch, analyze, prompt
#   curl -fsSL https://example.com/i.sh | peek   # analyze from stdin
#   peek --print https://example.com/i.sh    # just show the analysis, never run
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
PRINT_ONLY=0
SOURCE=""

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  RED="$(printf '\033[31m')"; YE="$(printf '\033[33m')"; GR="$(printf '\033[32m')"
  CY="$(printf '\033[36m')"
else R=""; D=""; B=""; RED=""; YE=""; GR=""; CY=""; fi

die() { printf 'peek: %s\n' "$*" >&2; exit 1; }

for a in "$@"; do
  case "$a" in
    --print)   PRINT_ONLY=1 ;;
    --version) printf 'peek v%s\n' "$VERSION"; exit 0 ;;
    -h|--help)
      printf 'Usage: peek [--print] <url>   |   curl ... | peek\n'
      exit 0 ;;
    -*) die "unknown option: $a" ;;
    *)  SOURCE="$a" ;;
  esac
done

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

if [ -n "$SOURCE" ]; then
  case "$SOURCE" in
    http://*|https://*)
      command -v curl >/dev/null 2>&1 || die "curl not found"
      curl -fsSL "$SOURCE" -o "$TMP" || die "could not fetch $SOURCE" ;;
    *)
      [ -f "$SOURCE" ] || die "not a URL and not a file: $SOURCE"
      cat "$SOURCE" > "$TMP" ;;
  esac
elif [ ! -t 0 ]; then
  cat > "$TMP"                       # read piped script from stdin
  SOURCE="(stdin)"
else
  die "no input — pass a URL or pipe a script in"
fi

LINES=$(wc -l < "$TMP" | tr -d ' ')
SCORE=0
FINDINGS=""

# flag <regex> <weight> <label> : count matches, add to score, remember finding
flag() {
  pat="$1"; weight="$2"; label="$3"
  n=$(grep -nE "$pat" "$TMP" 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] || return 0
  SCORE=$((SCORE + weight * n))
  FINDINGS="${FINDINGS}${weight}|${n}|${label}|${pat}
"
}

# --- heuristics: what makes a remote script dangerous ------------------------
flag '\bsudo\b|\bdoas\b'                          3 "runs commands as root (sudo/doas)"
flag 'rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r' 4 "recursive force delete (rm -rf)"
flag 'curl|wget|\bnc\b|/dev/tcp'                  2 "makes its own network calls"
flag 'base64[[:space:]]+-?-?d|xxd[[:space:]]+-r|\beval\b' 4 "obfuscation / eval (hidden payload)"
flag '>[[:space:]]*/etc/|>[[:space:]]*/usr/|>[[:space:]]*/bin/|>[[:space:]]*/lib' 3 "writes into system directories"
flag 'chmod[[:space:]]+[0-7]*777'                 2 "world-writable permissions (chmod 777)"
flag 'crontab|systemctl[[:space:]]+enable|launchctl' 3 "installs background services / persistence"
flag 'of=/dev/sd|of=/dev/nvme|mkfs'               5 "writes to raw disk (can destroy data)"
flag '~/\.ssh|id_rsa|\.aws/credentials|\.env'     4 "touches credentials / secrets"

# --- verdict -----------------------------------------------------------------
if   [ "$SCORE" -ge 12 ]; then LV="${RED}${B}HIGH RISK${R}"
elif [ "$SCORE" -ge 5 ];  then LV="${YE}${B}REVIEW${R}"
else                           LV="${GR}${B}LOW RISK${R}"; fi

printf '\n%s peek%s  source: %s   %s lines\n' "$B" "$R" "$SOURCE" "$LINES"
printf '  risk score: %s%s%s   verdict: %s\n\n' "$B" "$SCORE" "$R" "$LV"

if [ -n "$FINDINGS" ]; then
  printf '  %sfindings%s\n' "$B" "$R"
  printf '%s' "$FINDINGS" | while IFS='|' read -r w n label pat; do
    [ -n "$label" ] || continue
    printf '   %s•%s %s %s(x%s)%s\n' "$YE" "$R" "$label" "$D" "$n" "$R"
  done
  printf '\n  %sdangerous lines%s\n' "$B" "$R"
  # show the actual offending lines with numbers
  printf '%s' "$FINDINGS" | while IFS='|' read -r w n label pat; do
    [ -n "$pat" ] || continue
    grep -nE "$pat" "$TMP" 2>/dev/null | head -3 | while IFS= read -r ln; do
      printf '   %s%s%s\n' "$D" "$ln" "$R"
    done
  done
  printf '\n'
else
  printf '  %sno dangerous patterns matched.%s still your call.\n\n' "$GR" "$R"
fi

[ "$PRINT_ONLY" -eq 1 ] && exit 0

# refuse to auto-run HIGH RISK without an explicit extra confirmation
printf '  view full script before deciding? [y/N] '
read -r v < /dev/tty 2>/dev/null || v="n"
case "$v" in y|Y) ${PAGER:-less} "$TMP" < /dev/tty || cat "$TMP" ;; esac

printf '  run this script now? [y/N] '
read -r ans < /dev/tty 2>/dev/null || ans="n"
case "$ans" in
  y|Y)
    if [ "$SCORE" -ge 12 ]; then
      printf '  %sHIGH RISK%s — type the word RUN to confirm: ' "$RED" "$R"
      read -r c < /dev/tty 2>/dev/null || c=""
      [ "$c" = "RUN" ] || { printf '  aborted.\n'; exit 1; }
    fi
    printf '  running...\n\n'
    sh "$TMP"
    ;;
  *) printf '  not run. (script was at %s)\n' "$TMP"; trap - EXIT ;;
esac
