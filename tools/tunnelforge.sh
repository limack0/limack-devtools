#!/usr/bin/env sh
# tunnelforge — expose a local port to the internet in one command.
# Wraps cloudflared: no ngrok account, no rate limits, no signup.
#
#   tunnelforge 3000                 # quick: instant https://<random>.trycloudflare.com
#   tunnelforge 3000 demo            # named: stable https://demo.limackcorp.online (your domain)
#   tunnelforge https://localhost:8443 api   # expose a full origin URL
#   tunnelforge list                 # list your named (tf-*) tunnels
#   tunnelforge rm demo              # delete a named tunnel
#
# Quick mode needs nothing. Named mode needs a cloudflared origin cert
# (~/.cloudflared/cert.pem from `cloudflared tunnel login`).
# Config: TUNNELFORGE_DOMAIN (default limackcorp.online)
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
DOMAIN="${TUNNELFORGE_DOMAIN:-limackcorp.online}"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'tunnelforge: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# checked only when actually opening/managing a tunnel, so --version/--help work anywhere
need_cf() { have cloudflared || die "cloudflared not found — install it: https://developers.cloudflare.com/cloudflared/"; }

# turn "3000" into http://localhost:3000 ; pass full URLs through unchanged
as_target() {
  case "$1" in
    http://*|https://*) printf '%s' "$1" ;;
    *[!0-9]*)           die "not a port or URL: $1" ;;
    *)                  printf 'http://localhost:%s' "$1" ;;
  esac
}

# warn (don't block) if nothing is listening on a localhost port
check_listening() {
  port="$1"
  case "$port" in *[!0-9]*) return 0 ;; esac
  if have ss; then
    ss -ltn 2>/dev/null | grep -qE "[:.]${port}\b" || warn "nothing seems to be listening on :${port} yet"
  fi
}

big_url() {
  printf '\n  %s%s  %s  %s\n\n' "$B$GR" "your tunnel is live:" "$1" "$R"
}

# ----- QUICK MODE ------------------------------------------------------------
cmd_quick() {
  need_cf
  target="$(as_target "$1")"
  case "$1" in *[!0-9]*) : ;; *) check_listening "$1" ;; esac
  log="$(mktemp)"
  info "opening a quick tunnel to ${B}${target}${R} ${D}(Ctrl-C to stop)${R}"

  # --config /dev/null: ignore any global ~/.cloudflared/config.yml, whose
  # ingress rules would otherwise override --url and 404 every request.
  cloudflared tunnel --config /dev/null --no-autoupdate --url "$target" >"$log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null; rm -f "$log"; exit 0' INT TERM

  url=""; i=0
  while [ "$i" -lt 30 ]; do
    url="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$log" 2>/dev/null | head -1 || true)"
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || { warn "cloudflared exited early:"; cat "$log" >&2; rm -f "$log"; exit 1; }
    sleep 1; i=$((i+1))
  done
  [ -n "$url" ] || { warn "no URL after 30s — cloudflared log:"; cat "$log" >&2; kill "$pid" 2>/dev/null; exit 1; }

  big_url "$url"
  info "forwarding ${url}  ->  ${target}"
  wait "$pid"
}

# ----- NAMED MODE ------------------------------------------------------------
cmd_named() {
  need_cf
  port_or_url="$1"; sub="$2"; dry="${3:-}"
  target="$(as_target "$port_or_url")"
  host="${sub}.${DOMAIN}"
  name="tf-${sub}"
  [ -f "$HOME/.cloudflared/cert.pem" ] || die "named mode needs ~/.cloudflared/cert.pem (run: cloudflared tunnel login)"

  plan() { printf '   %s$ %s%s\n' "$D" "$*" "$R"; }
  if [ "$dry" = "--dry" ]; then
    info "DRY — would expose ${B}${target}${R} at ${B}https://${host}${R}"
    plan "cloudflared tunnel create ${name}   # if missing"
    plan "cloudflared tunnel route dns --overwrite-dns <id> ${host}"
    plan "cloudflared tunnel --url ${target} run ${name}"
    exit 0
  fi

  # create the tunnel if it doesn't exist yet
  id="$(cloudflared tunnel list 2>/dev/null | awk -v n="$name" '$2==n{print $1; exit}')"
  if [ -z "$id" ]; then
    info "creating tunnel ${B}${name}${R}"
    cloudflared tunnel create "$name" >/dev/null 2>&1 || die "tunnel create failed"
    id="$(cloudflared tunnel list 2>/dev/null | awk -v n="$name" '$2==n{print $1; exit}')"
    [ -n "$id" ] || die "could not resolve new tunnel id"
  else
    ok "reusing tunnel ${name} (${id})"
  fi

  info "routing DNS ${B}${host}${R} -> ${name}"
  cloudflared tunnel route dns --overwrite-dns "$id" "$host" >/dev/null 2>&1 \
    || warn "DNS route may have failed — check the dashboard"

  big_url "https://${host}"
  info "forwarding https://${host}  ->  ${target}  ${D}(Ctrl-C to stop)${R}"
  trap 'exit 0' INT TERM
  # --config /dev/null keeps the global config's ingress from hijacking routing;
  # credentials resolve from ~/.cloudflared/<id>.json by tunnel name.
  cloudflared tunnel --config /dev/null --no-autoupdate --cred-file "$HOME/.cloudflared/${id}.json" --url "$target" run "$name"
}

cmd_list() {
  need_cf
  info "your named tunnels (tf-*)"
  cloudflared tunnel list 2>/dev/null | awk 'NR==1 || $2 ~ /^tf-/'
}

cmd_rm() {
  need_cf
  sub="${1:-}"; [ -n "$sub" ] || die "usage: tunnelforge rm <subdomain>"
  name="tf-${sub}"
  info "deleting tunnel ${name}"
  cloudflared tunnel cleanup "$name" >/dev/null 2>&1 || true
  cloudflared tunnel delete "$name" && ok "deleted ${name}"
  warn "the DNS record ${sub}.${DOMAIN} is not auto-removed — delete it in the Cloudflare dashboard if unused"
}

case "${1:-}" in
  list)      cmd_list ;;
  rm)        shift; cmd_rm "$@" ;;
  --version) printf 'tunnelforge v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'tunnelforge — expose a local port in one command.\n\n'
    printf '  tunnelforge <port>              quick ephemeral URL (trycloudflare.com)\n'
    printf '  tunnelforge <port> <sub>        stable URL <sub>.%s\n' "$DOMAIN"
    printf '  tunnelforge <port> <sub> --dry  show the plan, do nothing\n'
    printf '  tunnelforge list                list your tf-* tunnels\n'
    printf '  tunnelforge rm <sub>            delete a named tunnel\n'
    ;;
  *)
    # first arg is a port or origin URL
    if [ "$#" -ge 2 ] && [ "$2" != "--dry" ]; then
      cmd_named "$1" "$2" "${3:-}"
    else
      cmd_quick "$1"
    fi
    ;;
esac
