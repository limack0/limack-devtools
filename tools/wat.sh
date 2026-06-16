#!/usr/bin/env sh
# wat — paste an error, get a plain-French explanation and a fix.
# Built for francophone devs: stop copy-pasting cryptic stack traces into Google.
#
#   macommande 2>&1 | wat            # explain whatever failed
#   wat -- npm run build             # run it, explain only if it fails
#   wat --dry -- ls /nope            # show the request, don't call the API
#
# Needs: OPENROUTER_API_KEY  (get one at https://openrouter.ai/keys)
# Config: WAT_MODEL (default anthropic/claude-3.5-haiku), WAT_LANG (default fr)
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
MODEL="${WAT_MODEL:-anthropic/claude-3.5-haiku}"
LANG_OUT="${WAT_LANG:-fr}"
API="https://openrouter.ai/api/v1/chat/completions"
DRY=0
CONTEXT=""

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
die() { printf 'wat: %s\n' "$*" >&2; exit 1; }

# ----- gather the error text -------------------------------------------------
RUN_MODE=0
case "${1:-}" in
  --version) printf 'wat v%s\n' "$VERSION"; exit 0 ;;
  -h|--help)
    printf 'Usage:\n  cmd 2>&1 | wat\n  wat -- <command>\n  wat --dry -- <command>\n'
    exit 0 ;;
  --dry) DRY=1; shift ;;
esac
if [ "${1:-}" = "--dry" ]; then DRY=1; shift; fi
if [ "${1:-}" = "--" ]; then RUN_MODE=1; shift; fi

if [ "$RUN_MODE" -eq 1 ]; then
  [ "$#" -gt 0 ] || die "nothing to run after --"
  printf '%s==>%s running: %s\n' "$CY" "$R" "$*" >&2
  OUT="$("$@" 2>&1)" && { printf '%s' "$OUT"; printf '\n%s  ok%s exit 0 — nothing to explain\n' "$GR" "$R" >&2; exit 0; }
  CODE=$?
  printf '%s\n' "$OUT" >&2
  CONTEXT="$(printf 'Command: %s\nExit code: %s\nOutput:\n%s' "$*" "$CODE" "$OUT")"
elif [ ! -t 0 ]; then
  CONTEXT="$(cat)"
else
  die "no input — pipe an error in, or use: wat -- <command>"
fi
[ -n "$CONTEXT" ] || die "empty input"

# ----- build the request (jq preferred, python3 fallback) --------------------
SYS="Tu es un assistant pour développeurs. On te donne la sortie d'erreur d'une commande. Réponds en ${LANG_OUT}, de façon concise et concrète: 1) ce que l'erreur signifie, 2) la cause probable, 3) la commande ou correction exacte à appliquer. Pas de blabla."

build_payload() {
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$MODEL" --arg s "$SYS" --arg u "$CONTEXT" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$u}]}'
  elif command -v python3 >/dev/null 2>&1; then
    MODEL="$MODEL" SYS="$SYS" CONTEXT="$CONTEXT" python3 -c '
import json,os
print(json.dumps({"model":os.environ["MODEL"],"messages":[
 {"role":"system","content":os.environ["SYS"]},
 {"role":"user","content":os.environ["CONTEXT"]}]}))'
  else
    die "need jq or python3 to build the request"
  fi
}
PAYLOAD="$(build_payload)"

if [ "$DRY" -eq 1 ]; then
  printf '%s-- dry run --%s model=%s lang=%s\n' "$D" "$R" "$MODEL" "$LANG_OUT"
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

[ -n "${OPENROUTER_API_KEY:-}" ] || die "set OPENROUTER_API_KEY (https://openrouter.ai/keys)"
command -v curl >/dev/null 2>&1 || die "curl not found"

RESP="$(curl -fsS "$API" \
  -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/limack0/limack-devtools" \
  -H "X-Title: wat" \
  -d "$PAYLOAD")" || die "API call failed (key valid? credit left?)"

# extract the answer
if command -v jq >/dev/null 2>&1; then
  ANS="$(printf '%s' "$RESP" | jq -r '.choices[0].message.content // (.error.message // "no answer")')"
elif command -v python3 >/dev/null 2>&1; then
  ANS="$(printf '%s' "$RESP" | python3 -c '
import json,sys
d=json.load(sys.stdin)
try: print(d["choices"][0]["message"]["content"])
except Exception: print(d.get("error",{}).get("message","no answer"))')"
else
  ANS="$RESP"
fi

printf '\n%s wat%s %s(%s)%s\n\n%s\n' "$B" "$R" "$D" "$MODEL" "$R" "$ANS"
