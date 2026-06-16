#!/usr/bin/env sh
# deadman — a personal dead man's switch + uptime monitor.
# Watches your services (http/tcp/command) and heartbeats (cron jobs that must
# check in). When something goes down — or comes back — it pings you on Telegram.
# Only alerts on state CHANGES, so no spam.
#
#   deadman add api https://api.example.com      # http check
#   deadman add db  db.example.com:5432          # tcp check
#   deadman add disk --cmd 'df / | awk "NR==2 && \$5+0>90{exit 1}"'
#   deadman add nightly-backup --beat 90000      # must check in every 25h
#   deadman beat nightly-backup                  # ...feed it from the cron job
#   deadman check                                # run all checks once, alert on changes
#   deadman watch --interval 60                  # loop forever
#   deadman list | rm <name> | test
#
# Telegram: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID. DEADMAN_DRY=1 prints
# alerts instead of sending them.
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
DIR="${DEADMAN_DIR:-$HOME/.deadmanswitch}"
TARGETS="$DIR/targets"
STATE="$DIR/state"
BEATS="$DIR/beats"
TIMEOUT="${DEADMAN_TIMEOUT:-10}"
TAB="$(printf '\t')"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"; RED="$(printf '\033[31m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; RED=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'deadman: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
now()  { date +%s; }

mkdir -p "$DIR"; : >> "$TARGETS"; : >> "$STATE"; : >> "$BEATS"

# ----- tiny key/value DB helpers (tab-separated files) -----------------------
db_get_target() { awk -F"$TAB" -v n="$1" '$1==n{ $1=""; sub(/^\t/,""); print; exit }' "$TARGETS"; }
db_type()       { awk -F"$TAB" -v n="$1" '$1==n{print $2; exit}' "$TARGETS"; }
db_spec()       { awk -F"$TAB" -v n="$1" '$1==n{ s=$3; for(i=4;i<=NF;i++) s=s FS $i; print s; exit }' "$TARGETS"; }
db_remove()     { grep -v "^$1$TAB" "$2" > "$2.tmp" 2>/dev/null || true; mv "$2.tmp" "$2"; }

state_get() { awk -F"$TAB" -v n="$1" '$1==n{print $2; exit}' "$STATE"; }
state_set() { db_remove "$1" "$STATE"; printf '%s%s%s%s%s\n' "$1" "$TAB" "$2" "$TAB" "$(now)" >> "$STATE"; }

# ----- telegram --------------------------------------------------------------
tg_send() {
  msg="$1"
  if [ "${DEADMAN_DRY:-0}" = "1" ]; then
    printf '%s[telegram dry]%s %s\n' "$D" "$R" "$msg"; return 0
  fi
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    warn "Telegram not configured (set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID) — alert not sent"
    return 1
  fi
  if curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    -d "parse_mode=Markdown" >/dev/null 2>&1; then
    return 0
  else
    warn "Telegram send failed"; return 1
  fi
}

# ----- per-type probes (echo up|down) ----------------------------------------
tcp_up() {
  host="$1"; port="$2"
  if have nc; then nc -z -w "$TIMEOUT" "$host" "$port" >/dev/null 2>&1
  elif have python3; then python3 -c 'import socket,sys
try:
    socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=float(sys.argv[3])).close()
except Exception: sys.exit(1)' "$host" "$port" "$TIMEOUT" 2>/dev/null
  else timeout "$TIMEOUT" sh -c "true 2>/dev/null </dev/tcp/$host/$port" 2>/dev/null
  fi
}

probe() {
  type="$1"; spec="$2"
  case "$type" in
    http) curl -fsS -o /dev/null -m "$TIMEOUT" "$spec" >/dev/null 2>&1 && echo up || echo down ;;
    tcp)  host="${spec%:*}"; port="${spec##*:}"
          tcp_up "$host" "$port" && echo up || echo down ;;
    cmd)  sh -c "$spec" >/dev/null 2>&1 && echo up || echo down ;;
    *)    echo "?" ;;   # beat is handled in check_one, never via probe
  esac
}

beat_get_for() { awk -F"$TAB" -v n="$1" '$1==n{print $2; exit}' "$BEATS"; }

# ----- commands --------------------------------------------------------------
cmd_add() {
  name="${1:-}"; shift 2>/dev/null || true
  [ -n "$name" ] || die "usage: deadman add <name> <target>|--cmd '...'|--beat <secs>"
  case "${1:-}" in
    --cmd)  shift; type=cmd;  spec="$*"; [ -n "$spec" ] || die "empty command" ;;
    --beat) type=beat; spec="${2:-3600}" ;;
    http://*|https://*) type=http; spec="$1" ;;
    *:[0-9]*) type=tcp; spec="$1" ;;
    "")     die "no target given" ;;
    *)      die "can't detect type for '$1' — use --cmd or --beat, or give an http(s):// URL / host:port" ;;
  esac
  db_remove "$name" "$TARGETS"
  printf '%s%s%s%s%s\n' "$name" "$TAB" "$type" "$TAB" "$spec" >> "$TARGETS"
  ok "added ${B}${name}${R} (${type}: ${spec})"
  [ "$type" = beat ] && info "feed it from the job with:  deadman beat ${name}"
  return 0
}

cmd_beat() {
  name="${1:-}"; [ -n "$name" ] || die "usage: deadman beat <name>"
  db_remove "$name" "$BEATS"
  printf '%s%s%s\n' "$name" "$TAB" "$(now)" >> "$BEATS"
  ok "heartbeat recorded for ${name}"
}

cmd_rm() {
  name="${1:-}"; [ -n "$name" ] || die "usage: deadman rm <name>"
  db_remove "$name" "$TARGETS"; db_remove "$name" "$STATE"; db_remove "$name" "$BEATS"
  ok "removed ${name}"
}

check_one() {
  name="$1"; type="$2"; spec="$3"
  if [ "$type" = beat ]; then
    last="$(beat_get_for "$name")"
    if [ -z "$last" ]; then status=down
    else age=$(( $(now) - last )); [ "$age" -le "$spec" ] && status=up || status=down; fi
  else
    status="$(probe "$type" "$spec")"
  fi
  echo "$status"
}

cmd_check() {
  changed=0
  printf '\n  %s%-18s %-6s %s%s\n' "$B" "TARGET" "STATE" "DETAIL" "$R"
  while IFS="$TAB" read -r name type spec; do
    [ -n "$name" ] || continue
    status="$(check_one "$name" "$type" "$spec")"
    prev="$(state_get "$name" || true)"
    if [ "$status" = up ]; then col="$GR"; mark="UP"; else col="$RED"; mark="DOWN"; fi
    printf '  %-18s %s%-6s%s %s%s%s\n' "$name" "$col" "$mark" "$R" "$D" "${type}:${spec}" "$R"

    if [ -n "$prev" ] && [ "$prev" != "$status" ]; then
      changed=$((changed+1))
      if [ "$status" = down ]; then
        tg_send "🔴 *DOWN* — \`${name}\` (${type}) is not responding."
      else
        tg_send "🟢 *RECOVERED* — \`${name}\` is back up."
      fi
    fi
    state_set "$name" "$status"
  done < "$TARGETS"
  echo
  if [ "$changed" -gt 0 ]; then info "$changed state change(s) — alert(s) dispatched"; else info "no state changes"; fi
}

cmd_watch() {
  interval=60
  case "${1:-}" in --interval) interval="${2:-60}" ;; [0-9]*) interval="$1" ;; esac
  info "watching every ${interval}s (Ctrl-C to stop)"
  trap 'exit 0' INT TERM
  while true; do cmd_check; sleep "$interval"; done
}

cmd_list() {
  info "targets"
  [ -s "$TARGETS" ] || { echo "  (none — add one with: deadman add ...)"; return; }
  while IFS="$TAB" read -r name type spec; do
    [ -n "$name" ] || continue
    st="$(state_get "$name" || echo '?')"
    printf '  %-18s %s%-5s%s %s%s:%s%s\n' "$name" "$B" "$st" "$R" "$D" "$type" "$spec" "$R"
  done < "$TARGETS"
}

cmd_test() {
  info "sending a Telegram test message"
  if tg_send "✅ deadman test — your alerts are wired up correctly."; then ok "sent"; else die "not sent (see warning above)"; fi
}

case "${1:-}" in
  add)       shift; cmd_add "$@" ;;
  beat)      shift; cmd_beat "$@" ;;
  rm)        shift; cmd_rm "$@" ;;
  check)     shift; cmd_check ;;
  watch)     shift; cmd_watch "$@" ;;
  list)      shift; cmd_list ;;
  test)      shift; cmd_test ;;
  --version) printf 'deadman v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'deadman — dead man'\''s switch + uptime monitor with Telegram alerts.\n\n'
    printf '  add <name> <url|host:port>     add an http/tcp check\n'
    printf '  add <name> --cmd '\''<command>'\''  add a command check (up if exit 0)\n'
    printf '  add <name> --beat <secs>       add a heartbeat (down if not fed in time)\n'
    printf '  beat <name>                    feed a heartbeat\n'
    printf '  check                          run all checks once, alert on changes\n'
    printf '  watch [--interval N]           loop forever\n'
    printf '  list | rm <name> | test\n\n'
    printf '  Telegram: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID   (DEADMAN_DRY=1 to print)\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
