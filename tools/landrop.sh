#!/usr/bin/env sh
# landrop — share one machine's local AI model with the whole LAN.
# The strongest box in the room runs Ollama; everyone else queries it. Offline
# AI for places where the cloud is slow, metered, or absent.
#
#   landrop serve [--model llama3.2:1b]   # host the model on the LAN (run on the strong box)
#   landrop pull <model>                  # download a model into the shared server
#   landrop models                        # list available models
#   landrop ask "explique les pointeurs"  # query the server
#   landrop client                        # print what other machines should set
#
# Wraps Ollama (https://ollama.com). Clients point at the server with
# LANDROP_HOST=http://<server-ip>:11434.  Config: LANDROP_MODEL (default llama3.2:1b)
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
HOST="${LANDROP_HOST:-http://localhost:11434}"
MODEL="${LANDROP_MODEL:-llama3.2:1b}"
PORT="${LANDROP_PORT:-11434}"
DRY=0

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'landrop: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

lan_ip()  { hostname -I 2>/dev/null | awk '{print $1}' || echo "<server-ip>"; }
api_up()  { curl -fsS -m 3 "$HOST/api/tags" >/dev/null 2>&1; }
need_ollama() {
  have ollama && return 0
  die "Ollama not found. Install it once on this machine:
      curl -fsSL https://ollama.com/install.sh | sh
   (it's the engine landrop shares on the LAN)"
}

# ----- serve: host the model on the LAN --------------------------------------
cmd_serve() {
  m="$MODEL"
  case "${1:-}" in --model) m="${2:-$MODEL}" ;; esac
  need_ollama
  ip="$(lan_ip)"

  if api_up; then
    info "an Ollama server is already running — pulling ${B}${m}${R} into it"
    ollama pull "$m"
  else
    info "starting Ollama, bound to the LAN on ${B}0.0.0.0:${PORT}${R}"
    # OLLAMA_HOST=0.0.0.0 makes it reachable from other machines (default is localhost only)
    OLLAMA_HOST="0.0.0.0:${PORT}" ollama serve >/tmp/landrop-ollama.log 2>&1 &
    spid=$!
    trap 'kill "$spid" 2>/dev/null; exit 0' INT TERM
    i=0; while [ "$i" -lt 20 ]; do api_up && break; kill -0 "$spid" 2>/dev/null || { cat /tmp/landrop-ollama.log >&2; die "ollama failed to start"; }; sleep 1; i=$((i+1)); done
    info "pulling ${B}${m}${R}"
    OLLAMA_HOST="0.0.0.0:${PORT}" ollama pull "$m"
  fi

  echo
  printf '  %sserving on the LAN%s\n' "$B" "$R"
  printf '    other machines run:  %sexport LANDROP_HOST=http://%s:%s%s\n' "$GR" "$ip" "$PORT" "$R"
  printf '    then:                landrop ask "..."   (or set OLLAMA_HOST and use any Ollama client)\n\n'
  api_up && [ -z "${spid:-}" ] && { ok "ready"; return; }
  info "keeping the server in the foreground (Ctrl-C to stop)"
  wait "${spid:-$$}" 2>/dev/null || true
}

cmd_pull() {
  m="${1:-$MODEL}"; need_ollama
  info "pulling ${B}${m}${R} into ${HOST}"
  if [ "$HOST" = "http://localhost:11434" ]; then ollama pull "$m"
  else OLLAMA_HOST="${HOST#http://}" ollama pull "$m"; fi
  ok "pulled $m"
}

cmd_models() {
  api_up || die "no Ollama server reachable at $HOST (start one with: landrop serve)"
  info "models on ${HOST}"
  if have jq; then
    curl -fsS "$HOST/api/tags" | jq -r '.models[]?.name' | sed 's/^/  - /'
  else
    curl -fsS "$HOST/api/tags" | grep -oE '"name":"[^"]+"' | cut -d'"' -f4 | sed 's/^/  - /'
  fi
}

# ----- ask: query the shared model -------------------------------------------
cmd_ask() {
  case "${1:-}" in --dry) DRY=1; shift ;; esac
  prompt="$*"
  ctx=""
  if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then ctx="$(cat)"
  elif [ -z "$prompt" ] && [ ! -t 0 ]; then ctx="$(cat)"; fi
  [ -n "$prompt" ] || [ -n "$ctx" ] || die "ask what? (landrop ask \"...\")"
  user="$prompt"; [ -n "$ctx" ] && user="$(printf '%s\n\nContexte:\n%s' "$prompt" "$ctx")"

  if have jq; then
    payload="$(jq -nc --arg m "$MODEL" --arg u "$user" \
      '{model:$m, stream:false, messages:[{role:"user",content:$u}]}')"
  elif have python3; then
    payload="$(MODEL="$MODEL" U="$user" python3 -c 'import json,os;print(json.dumps({"model":os.environ["MODEL"],"stream":False,"messages":[{"role":"user","content":os.environ["U"]}]}))')"
  else die "need jq or python3"; fi

  if [ "$DRY" -eq 1 ]; then printf '%s-- dry --%s POST %s/api/chat\n%s\n' "$D" "$R" "$HOST" "$payload"; return 0; fi

  api_up || die "no Ollama server at $HOST — run 'landrop serve' here, or set LANDROP_HOST to the server"
  # don't use -f: a 4xx/5xx body carries Ollama's error message (e.g. not enough RAM)
  resp="$(curl -sS "$HOST/api/chat" -d "$payload" 2>/dev/null || true)"
  [ -n "$resp" ] || die "request failed — server unreachable at $HOST"
  if have jq; then ans="$(printf '%s' "$resp" | jq -r '.message.content // .error // "no answer"')"
  elif have python3; then ans="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("message",{}).get("content") or d.get("error","no answer"))')"
  else ans="$resp"; fi
  printf '\n%s🤖 landrop%s %s(%s @ %s)%s\n\n%s\n' "$B" "$R" "$D" "$MODEL" "$HOST" "$R" "$ans"
}

cmd_client() {
  ip="$(lan_ip)"
  printf 'Point other machines at this LAN AI server:\n\n'
  printf '  # for landrop\n  export LANDROP_HOST=http://%s:%s\n  landrop ask "..."\n\n' "$ip" "$PORT"
  printf '  # for any Ollama-compatible client / SDK\n  export OLLAMA_HOST=http://%s:%s\n' "$ip" "$PORT"
}

case "${1:-}" in
  serve)     shift; cmd_serve "$@" ;;
  pull)      shift; cmd_pull "$@" ;;
  models)    shift; cmd_models ;;
  ask)       shift; cmd_ask "$@" ;;
  client)    shift; cmd_client ;;
  --version) printf 'landrop v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'landrop — share one machine'\''s AI model across the LAN (offline AI).\n\n'
    printf '  serve [--model M]   host the model on the LAN (run on the strong box)\n'
    printf '  pull <model>        download a model into the server\n'
    printf '  models              list available models\n'
    printf '  ask "<prompt>"      query the server (LANDROP_HOST to target another box)\n'
    printf '  client              print client config for other machines\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
