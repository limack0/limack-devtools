#!/usr/bin/env sh
# oneshot — turn a fresh VPS into an app host in one command.
# Installs Docker, stands up a Caddy reverse proxy with automatic HTTPS
# (via lucaslorentz/caddy-docker-proxy — label-driven, no Caddyfile to edit),
# then deploys your apps with one line each. Bring a domain, get a live site.
#
#   oneshot init                                   # install docker + firewall
#   oneshot host --email you@example.com           # start the auto-HTTPS proxy
#   oneshot add blog --image ghcr.io/you/blog --port 3000 --domain blog.example.com
#   oneshot status | logs <name> | rm <name>
#
# Add --dry to ANY command to print the plan and write configs without running.
# init/host need root (or sudo). Apps get HTTPS automatically once DNS points here.
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
DIR="${ONESHOT_DIR:-/opt/oneshot}"
NET="oneshot"
PROXY_IMAGE="lucaslorentz/caddy-docker-proxy:2.9-alpine"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'oneshot: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

DRY=0
for a in "$@"; do [ "$a" = "--dry" ] && DRY=1; done

run() { # echo the command; run it unless --dry
  printf '   %s$ %s%s\n' "$D" "$*" "$R"
  [ "$DRY" -eq 1 ] || eval "$*"
}

need_root() {
  [ "$(id -u)" = 0 ] && { SUDO=""; return; }
  if have sudo; then SUDO="sudo"; else die "this needs root (run as root or install sudo)"; fi
}

# strip flags, read --key value pairs into shell vars (simple parser)
arg() { # arg <name> <default> -- "$@"
  key="--$1"; def="$2"; shift 2; [ "$1" = "--" ] && shift
  while [ "$#" -gt 0 ]; do
    case "$1" in "$key") printf '%s' "${2:-}"; return ;; esac
    shift
  done
  printf '%s' "$def"
}

# ----- init: docker + firewall ----------------------------------------------
cmd_init() {
  need_root
  info "installing Docker + firewall ${DRY:+(dry)}"
  if have docker; then ok "docker already present"; else
    run "curl -fsSL https://get.docker.com | $SUDO sh"
  fi
  run "$SUDO docker network create $NET 2>/dev/null || true"
  if have ufw; then
    run "$SUDO ufw allow OpenSSH"
    run "$SUDO ufw allow 80"
    run "$SUDO ufw allow 443"
    run "$SUDO ufw --force enable"
  else
    warn "ufw not found — skipping firewall (open 22/80/443 yourself)"
  fi
  ok "init done — next: oneshot host --email you@example.com"
}

# ----- host: the Caddy auto-HTTPS reverse proxy ------------------------------
cmd_host() {
  need_root
  email="$(arg email "" -- "$@")"
  mkdir -p "$DIR" 2>/dev/null || run "$SUDO mkdir -p $DIR"
  compose="$DIR/docker-compose.yml"
  emaillabel=""
  [ -n "$email" ] && emaillabel="    labels:
      caddy.email: $email"

  info "writing proxy stack -> ${B}${compose}${R}"
  # written even in --dry so you can inspect it
  tmpc="$(mktemp)"
  cat > "$tmpc" <<EOF
# oneshot reverse proxy — auto-HTTPS via caddy-docker-proxy.
# Apps join network '$NET' and declare caddy labels; routing + TLS are automatic.
services:
  caddy:
    image: $PROXY_IMAGE
    container_name: oneshot-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - CADDY_INGRESS_NETWORKS=$NET
$emaillabel
    networks: [$NET]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - caddy_data:/data
      - caddy_config:/config

networks:
  $NET:
    name: $NET

volumes:
  caddy_data:
  caddy_config:
EOF
  if mv "$tmpc" "$compose" 2>/dev/null; then :; else $SUDO mv "$tmpc" "$compose"; fi
  ok "wrote $compose"
  run "$SUDO docker compose -f $compose up -d"
  ok "proxy is up — add apps with: oneshot add <name> --image <img> --port <p> --domain <d>"
}

# ----- add: deploy an app behind the proxy -----------------------------------
cmd_add() {
  need_root
  name="$1"; shift
  [ -n "$name" ] || die "usage: oneshot add <name> --image <img> --port <port> --domain <domain>"
  image="$(arg image "" -- "$@")"
  port="$(arg port "" -- "$@")"
  domain="$(arg domain "" -- "$@")"
  [ -n "$image" ] && [ -n "$port" ] && [ -n "$domain" ] || die "need --image, --port and --domain"

  info "deploying ${B}${name}${R} at ${B}https://${domain}${R} ${DRY:+(dry)}"
  run "$SUDO docker rm -f $name 2>/dev/null || true"
  run "$SUDO docker run -d --name $name --restart unless-stopped --network $NET \
    --label caddy=$domain \
    --label 'caddy.reverse_proxy={{upstreams $port}}' \
    $image"
  ok "deployed — point ${domain}'s DNS at this server; Caddy fetches a cert automatically"
}

cmd_rm() {
  need_root; name="${1:-}"; [ -n "$name" ] || die "usage: oneshot rm <name>"
  run "$SUDO docker rm -f $name"
  ok "removed $name"
}

cmd_status() {
  need_root
  have docker || die "docker not installed (run: oneshot init)"
  info "oneshot containers"
  $SUDO docker ps --filter "network=$NET" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || true
}

cmd_logs() {
  need_root; name="${1:-}"; [ -n "$name" ] || die "usage: oneshot logs <name>"
  $SUDO docker logs --tail 50 -f "$name"
}

case "${1:-}" in
  init)      shift; cmd_init "$@" ;;
  host)      shift; cmd_host "$@" ;;
  add)       shift; cmd_add "$@" ;;
  rm)        shift; cmd_rm "$@" ;;
  status)    shift; cmd_status ;;
  logs)      shift; cmd_logs "$@" ;;
  --version) printf 'oneshot v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'oneshot — turn a fresh VPS into an app host.\n\n'
    printf '  init                          install docker + firewall\n'
    printf '  host --email you@example.com  start the auto-HTTPS reverse proxy\n'
    printf '  add <name> --image <img> --port <p> --domain <d>   deploy an app\n'
    printf '  status | logs <name> | rm <name>\n\n'
    printf '  Add --dry to any command to preview without changing anything.\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
