#!/usr/bin/env sh
# fr — your francophone dev assistant in the terminal.
# Ask any dev question in French, get a concise, concrete answer tuned for the
# West-African / francophone context (limited bandwidth, local constraints).
# Stop translating your questions into English first.
#
#   fr comment annuler le dernier commit git sans perdre mes fichiers
#   fr "écris une fonction python qui lit un csv"
#   cat erreur.log | fr "c'est quoi ce problème ?"     # pipe context in
#   fr --dry "..."                                      # show the request, no API call
#
# Needs: OPENROUTER_API_KEY  (https://openrouter.ai/keys)
# Config: FR_MODEL (default anthropic/claude-3.5-haiku)
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
MODEL="${FR_MODEL:-anthropic/claude-3.5-haiku}"
API="https://openrouter.ai/api/v1/chat/completions"
DRY=0

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
die() { printf 'fr: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --version) printf 'fr v%s\n' "$VERSION"; exit 0 ;;
  -h|--help)
    printf 'Usage:\n  fr <ta question en français>\n  cat fichier | fr "<question>"\n  fr --dry "<question>"\n'
    exit 0 ;;
  --dry) DRY=1; shift ;;
esac

QUESTION="$*"

# optional context on stdin (an error log, a snippet, etc.).
# Only read when stdin is a real pipe or a redirected file, so `fr "question"`
# in a non-interactive shell never blocks waiting on an inherited stdin.
CONTEXT=""
if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
  CONTEXT="$(cat)"
elif [ -z "$QUESTION" ] && [ ! -t 0 ]; then
  CONTEXT="$(cat)"
fi
[ -n "$QUESTION" ] || [ -n "$CONTEXT" ] || die "pose une question (fr --help)"

SYS="Tu es un assistant pour développeurs francophones, en particulier en Afrique de l'Ouest (connexions souvent lentes/coûteuses, contraintes matérielles locales). Réponds TOUJOURS en français, de façon concise et concrète: va droit au but, donne les commandes ou le code exact, préfère les solutions légères et économes en bande passante. Pas de remplissage."

USER_MSG="$QUESTION"
[ -n "$CONTEXT" ] && USER_MSG="$(printf '%s\n\nContexte (fourni sur stdin):\n%s' "$QUESTION" "$CONTEXT")"

build_payload() {
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$MODEL" --arg s "$SYS" --arg u "$USER_MSG" \
      '{model:$m, messages:[{role:"system",content:$s},{role:"user",content:$u}]}'
  elif command -v python3 >/dev/null 2>&1; then
    MODEL="$MODEL" SYS="$SYS" USER_MSG="$USER_MSG" python3 -c '
import json,os
print(json.dumps({"model":os.environ["MODEL"],"messages":[
 {"role":"system","content":os.environ["SYS"]},
 {"role":"user","content":os.environ["USER_MSG"]}]}))'
  else
    die "il faut jq ou python3 pour construire la requête"
  fi
}
PAYLOAD="$(build_payload)"

if [ "$DRY" -eq 1 ]; then
  printf '%s-- dry run --%s model=%s\n%s\n' "$D" "$R" "$MODEL" "$PAYLOAD"
  exit 0
fi

[ -n "${OPENROUTER_API_KEY:-}" ] || die "définis OPENROUTER_API_KEY (https://openrouter.ai/keys)"
command -v curl >/dev/null 2>&1 || die "curl introuvable"

RESP="$(curl -fsS "$API" \
  -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/limack0/limack-devtools" \
  -H "X-Title: fr" \
  -d "$PAYLOAD")" || die "appel API échoué (clé valide ? crédit restant ?)"

if command -v jq >/dev/null 2>&1; then
  ANS="$(printf '%s' "$RESP" | jq -r '.choices[0].message.content // (.error.message // "pas de réponse")')"
elif command -v python3 >/dev/null 2>&1; then
  ANS="$(printf '%s' "$RESP" | python3 -c '
import json,sys
d=json.load(sys.stdin)
try: print(d["choices"][0]["message"]["content"])
except Exception: print(d.get("error",{}).get("message","pas de réponse"))')"
else
  ANS="$RESP"
fi

printf '\n%s🇫🇷 fr%s %s(%s)%s\n\n%s\n' "$B" "$R" "$D" "$MODEL" "$R" "$ANS"
