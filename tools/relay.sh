#!/usr/bin/env sh
# relay — make intermittent connectivity a non-event.
# Most tools treat the network as binary: online, or error. relay treats it as
# *eventual*. Run any command through it — if you're offline, it's queued and
# sent automatically when the connection comes back. You keep working.
#
#   relay git push                 # offline? queued. online? runs now.
#   relay -- curl -X POST api/deploy
#   relay status                   # what's waiting
#   relay flush                    # try to send the queue now
#   relay daemon                   # auto-flush whenever the network returns
#   relay clear                    # empty the queue
#
# Optional Telegram pings on send: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID.
# Config: RELAY_CHECK_URL (connectivity probe), RELAY_TIMEOUT (default 4s).
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
DIR="${RELAY_DIR:-$HOME/.relay}"
QDIR="$DIR/queue"
FDIR="$DIR/failed"
CHECK_URL="${RELAY_CHECK_URL:-http://connectivitycheck.gstatic.com/generate_204}"
TIMEOUT="${RELAY_TIMEOUT:-4}"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'relay: %s\n' "$*" >&2; exit 1; }

is_online() { curl -fsS -m "$TIMEOUT" -o /dev/null "$CHECK_URL" 2>/dev/null; }
queue_count() { find "$QDIR" -type f 2>/dev/null | wc -l | tr -d ' '; }

notify() { # optional Telegram ping; no-op if unconfigured
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || return 0
  curl -fsS -m "$TIMEOUT" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=$1" \
    >/dev/null 2>&1 || true
}

# a job file: line 1 = cwd, lines 2.. = argv (one arg per line, exact)
enqueue() {
  mkdir -p "$QDIR"
  ts="$(date +%s%N 2>/dev/null || date +%s)"
  job="$QDIR/${ts}-$$"
  { pwd; for a in "$@"; do printf '%s\n' "$a"; done } > "$job"
}

job_desc() { # human-readable command from a job file (skip the cwd line)
  awk 'NR>1{ if(s)s=s" "; s=s $0 } END{print s}' "$1"
}

run_job() { # reconstruct argv from the job file and execute in its cwd
  jf="$1"; cwd=""; set --; n=0
  while IFS= read -r line; do
    n=$((n+1))
    if [ "$n" -eq 1 ]; then cwd="$line"; else set -- "$@" "$line"; fi
  done < "$jf"
  [ "$#" -gt 0 ] || return 0
  ( cd "$cwd" 2>/dev/null || cd / ; "$@" )
}

# ----- run-or-queue ----------------------------------------------------------
relay_run() {
  force=0
  [ "${1:-}" = "--queue" ] && { force=1; shift; }
  [ "${1:-}" = "--" ] && shift
  [ "$#" -gt 0 ] || die "nothing to run (relay <command>)"

  if [ "$force" -eq 0 ] && is_online; then
    "$@"                       # online: transparent passthrough, keep its exit code
  else
    enqueue "$@"
    if [ "$force" -eq 1 ]; then
      info "queued ($(queue_count) waiting). relay flush to send."
    else
      info "offline — queued ($(queue_count) waiting). relay daemon will auto-send."
    fi
  fi
}

# ----- flush -----------------------------------------------------------------
cmd_flush() {
  [ "$(queue_count)" -gt 0 ] || { ok "queue empty"; return 0; }
  is_online || { warn "still offline — nothing flushed ($(queue_count) waiting)"; return 1; }
  sent=0; parked=0
  for jf in $(find "$QDIR" -type f 2>/dev/null | sort); do
    [ -f "$jf" ] || continue
    desc="$(job_desc "$jf")"
    info "sending: ${B}${desc}${R}"
    if run_job "$jf"; then
      rm -f "$jf"; sent=$((sent+1)); notify "✅ relay sent: $desc"
    elif is_online; then
      mkdir -p "$FDIR"; mv "$jf" "$FDIR/"; parked=$((parked+1))
      warn "failed (not a connectivity issue) — parked in failed/: $desc"
      notify "⚠️ relay failed: $desc"
    else
      warn "went offline mid-flush — keeping the rest queued"; break
    fi
  done
  ok "sent ${sent} job(s)$([ "$parked" -gt 0 ] && printf ', %s parked as failed' "$parked")"
}

cmd_status() {
  n="$(queue_count)"; fn="$(find "$FDIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if is_online; then net="${GR}online${R}"; else net="${YE}offline${R}"; fi
  info "network: ${net}   queued: ${B}${n}${R}   failed: ${fn}"
  [ "$n" -gt 0 ] && find "$QDIR" -type f 2>/dev/null | sort | while IFS= read -r jf; do
    printf '   %s•%s %s\n' "$CY" "$R" "$(job_desc "$jf")"
  done
  [ "$fn" -gt 0 ] && find "$FDIR" -type f 2>/dev/null | sort | while IFS= read -r jf; do
    printf '   %s✗%s %s %s(failed)%s\n' "$YE" "$R" "$(job_desc "$jf")" "$D" "$R"
  done
  return 0
}

cmd_clear() {
  rm -rf "$QDIR"; ok "queue cleared"
  [ "${1:-}" = "--failed" ] && { rm -rf "$FDIR"; ok "failed cleared"; }
}

cmd_daemon() {
  interval=30
  case "${1:-}" in --interval) interval="${2:-30}" ;; [0-9]*) interval="$1" ;; esac
  info "watching — auto-flush when the network returns (every ${interval}s, Ctrl-C to stop)"
  trap 'exit 0' INT TERM
  while true; do
    if [ "$(queue_count)" -gt 0 ] && is_online; then cmd_flush || true; fi
    sleep "$interval"
  done
}

case "${1:-}" in
  status|list) shift; cmd_status ;;
  flush)       shift; cmd_flush ;;
  clear)       shift; cmd_clear "$@" ;;
  daemon|watch) shift; cmd_daemon "$@" ;;
  --version)   printf 'relay v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'relay — queue commands offline, send them when the network returns.\n\n'
    printf '  relay <command>        run now if online, else queue it\n'
    printf '  relay --queue <cmd>    always queue (batch for later)\n'
    printf '  relay status           network + what is waiting\n'
    printf '  relay flush            try to send the queue now\n'
    printf '  relay daemon [--interval N]   auto-flush when online\n'
    printf '  relay clear [--failed] empty the queue\n\n'
    printf '  Use "relay -- <cmd>" if your command starts with a dash.\n'
    ;;
  *) relay_run "$@" ;;
esac
