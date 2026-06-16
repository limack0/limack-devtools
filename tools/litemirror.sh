#!/usr/bin/env sh
# litemirror — turn one machine into a LAN package cache.
# One good connection in the room feeds everyone else. Download a package once,
# install it on N machines with no extra bandwidth. Built for slow/metered links.
#
#   litemirror pull pip <pkgs...>    # download wheels into the shared cache
#   litemirror pull apt <pkgs...>    # download .deb into the shared cache
#   litemirror serve [--port 8919]   # serve the cache over the LAN
#   litemirror client                # print what other machines should set
#
# Other machines then:
#   pip install --no-index --find-links http://<this-ip>:8919/pip <pkg>
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
DIR="${LITEMIRROR_DIR:-$HOME/.litemirror}"
PORT="${LITEMIRROR_PORT:-8919}"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'litemirror: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

lan_ip() { hostname -I 2>/dev/null | awk '{print $1}' || echo "<this-host>"; }

cmd_pull() {
  kind="${1:-}"; shift 2>/dev/null || true
  [ -n "$kind" ] || die "usage: litemirror pull pip|apt <pkgs...>"
  [ "$#" -gt 0 ] || die "no packages given"
  case "$kind" in
    pip)
      have pip || have pip3 || die "pip not found"
      pipbin="$(command -v pip || command -v pip3)"
      mkdir -p "$DIR/pip"
      info "downloading wheels for: $*"
      "$pipbin" download "$@" -d "$DIR/pip"
      ok "cached $(ls -1 "$DIR/pip" | wc -l | tr -d ' ') files in $DIR/pip"
      ;;
    apt)
      have apt-get || die "apt-get not found"
      mkdir -p "$DIR/apt"
      info "downloading .deb for: $*"
      ( cd "$DIR/apt" && apt-get download "$@" ) \
        || die "apt-get download failed (some packages need 'apt-get install --reinstall -d')"
      ok "cached $(ls -1 "$DIR/apt"/*.deb 2>/dev/null | wc -l | tr -d ' ') .deb in $DIR/apt"
      ;;
    *) die "unknown kind: $kind (pip|apt)" ;;
  esac
}

cmd_serve() {
  # allow: serve --port N  or  serve N
  case "${1:-}" in
    --port) PORT="${2:-$PORT}" ;;
    [0-9]*) PORT="$1" ;;
  esac
  have python3 || die "python3 needed to serve (python3 -m http.server)"
  mkdir -p "$DIR/pip" "$DIR/apt"
  ip="$(lan_ip)"
  info "serving ${B}$DIR${R} on ${B}http://${ip}:${PORT}${R}  (Ctrl-C to stop)"
  echo
  printf '  %sclients on the LAN:%s\n' "$B" "$R"
  printf '    pip:  pip install --no-index --find-links http://%s:%s/pip <pkg>\n' "$ip" "$PORT"
  printf '    apt:  add to a machine -> echo "deb [trusted=yes] http://%s:%s/apt ./" | sudo tee /etc/apt/sources.list.d/litemirror.list\n' "$ip" "$PORT"
  echo
  # build an apt index if dpkg-scanpackages is around (optional, best-effort)
  if have dpkg-scanpackages && ls "$DIR/apt"/*.deb >/dev/null 2>&1; then
    ( cd "$DIR/apt" && dpkg-scanpackages . /dev/null 2>/dev/null | gzip -9c > Packages.gz ) \
      && ok "apt Packages.gz index built"
  fi
  cd "$DIR"
  exec python3 -m http.server "$PORT"
}

cmd_client() {
  ip="$(lan_ip)"
  printf 'Point other machines at this mirror:\n\n'
  printf '  # pip (per-command)\n'
  printf '  pip install --no-index --find-links http://%s:%s/pip <pkg>\n\n' "$ip" "$PORT"
  printf '  # pip (persistent)\n'
  printf '  export PIP_FIND_LINKS=http://%s:%s/pip\n\n' "$ip" "$PORT"
  printf '  # apt\n'
  printf '  echo "deb [trusted=yes] http://%s:%s/apt ./" | sudo tee /etc/apt/sources.list.d/litemirror.list\n' "$ip" "$PORT"
  printf '  sudo apt-get update\n'
}

case "${1:-}" in
  pull)      shift; cmd_pull   "$@" ;;
  serve)     shift; cmd_serve  "$@" ;;
  client)    shift; cmd_client "$@" ;;
  --version) printf 'litemirror v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'litemirror — turn one machine into a LAN package cache.\n\n'
    printf '  pull pip <pkgs...>     download wheels into the shared cache\n'
    printf '  pull apt <pkgs...>     download .deb into the shared cache\n'
    printf '  serve [--port N]       serve the cache over the LAN (default %s)\n' "$PORT"
    printf '  client                 print client config for other machines\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
