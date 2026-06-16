#!/usr/bin/env sh
# Lim@ck DevTools — one entry, a menu of offline-first dev tools.
# Source of truth: https://github.com/limack0/limack-devtools
# Run:  curl -fsSL get.limackcorp.online | sh
#
# This hub is the MAS pattern: ONE URL, ONE repo, ONE reputation.
# Each tool installs standalone into ~/.local/bin, or runs once from here.

set -eu

VERSION="1.0.0"
RAW_BASE="${DEVTOOLS_RAW_BASE:-https://raw.githubusercontent.com/limack0/limack-devtools/main}"
BIN_DIR="${HOME}/.local/bin"
# When run from a clone (tools/ sits next to this file) we use local copies;
# when piped through curl we fetch tool scripts on demand from RAW_BASE.
# shellcheck disable=SC1007  # 'CDPATH= cd' is an intentional env-prefix, not an assignment
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"

if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'err  %s\n' "$*" >&2; exit 1; }

# tool registry: id | command-name | one-line description | tools/<file>
TOOLS="
devbox|devbox|setup a dev machine (git/node/python/docker)|tools/devbox.sh
peek|peek|inspect remote install scripts before you run them|tools/peek.sh
sneakersync|sneakersync|move a git repo between machines over USB, no network|tools/sneakersync.sh
wat|wat|explain a command error in plain French (AI)|tools/wat.sh
resurrect|resurrect|snapshot and rebuild your dev environment anywhere|tools/resurrect.sh
litemirror|litemirror|turn one machine into a LAN package cache|tools/litemirror.sh
tunnelforge|tunnelforge|expose a local port to the internet in one command|tools/tunnelforge.sh
deadman|deadman|monitor services + heartbeats, alert on Telegram when they die|tools/deadmanswitch.sh
secrets-doctor|secrets-doctor|find leaked secrets locally before they ship|tools/secrets-doctor.sh
relay|relay|queue commands offline, send them when the network returns|tools/relay.sh
fr|fr|francophone dev assistant in your terminal (AI)|tools/fr.sh
oneshot|oneshot|turn a fresh VPS into an app host in one command|tools/oneshot.sh
landrop|landrop|share one machine's AI model across the LAN (offline AI)|tools/landrop.sh
"

tool_field() { # id field-index  -> prints the field
  printf '%s\n' "$TOOLS" | while IFS='|' read -r id cmd desc path; do
    [ "$id" = "$1" ] || continue
    case "$2" in 1) echo "$cmd";; 2) echo "$desc";; 3) echo "$path";; esac
  done
}

fetch_tool() { # id -> path to a runnable script (local clone or downloaded temp)
  rel="$(tool_field "$1" 3)"
  if [ -n "$SELF_DIR" ] && [ -f "${SELF_DIR}/${rel}" ]; then
    printf '%s\n' "${SELF_DIR}/${rel}"; return 0
  fi
  tmp="$(mktemp)"
  curl -fsSL "${RAW_BASE}/${rel}" -o "$tmp" || die "could not fetch ${rel}"
  printf '%s\n' "$tmp"
}

install_tool() { # id -> copy into ~/.local/bin as <command>
  cmd="$(tool_field "$1" 1)"
  src="$(fetch_tool "$1")"
  mkdir -p "$BIN_DIR"
  cp "$src" "${BIN_DIR}/${cmd}"
  chmod +x "${BIN_DIR}/${cmd}"
  ok "installed '${cmd}' -> ${BIN_DIR}/${cmd}"
  case ":${PATH}:" in
    *":${BIN_DIR}:"*) : ;;
    *) warn "add ${BIN_DIR} to your PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
}

run_tool() { # id [args...] -> run once without installing
  id="$1"; shift
  src="$(fetch_tool "$id")"
  sh "$src" "$@"
}

banner() {
  say ""
  say "  ${B}Lim@ck DevTools${R} ${D}v${VERSION}${R}"
  say "  ${D}offline-first dev tools · one command each · audit before you run${R}"
  say ""
}

menu() {
  banner
  i=1
  printf '%s\n' "$TOOLS" | while IFS='|' read -r id cmd desc path; do
    [ -n "$id" ] || continue
    printf '  [%s] %-10s %s\n' "$i" "$cmd" "$desc"
    i=$((i+1))
  done
  say "  ${D}(prefix 'r' to run once instead of install, e.g. r1)${R}"
  say "  [0] quit"
  say ""
  printf "  select> "
  read -r choice

  mode="install"
  case "$choice" in
    r*) mode="run"; choice="${choice#r}" ;;
  esac
  [ "$choice" = "0" ] && { say "bye"; exit 0; }

  # map numeric choice -> tool id
  id="$(printf '%s\n' "$TOOLS" | awk -F'|' -v n="$choice" 'NF{c++; if(c==n){print $1}}')"
  [ -n "$id" ] || { warn "invalid choice"; return; }

  if [ "$mode" = "run" ]; then run_tool "$id"; else install_tool "$id"; fi
}

# ----- non-interactive: install.sh install|run <tool> [args] -----------------
if [ "${1:-}" = "install" ] || [ "${1:-}" = "run" ]; then
  action="$1"; shift
  [ "${1:-}" ] || die "usage: install.sh ${action} <tool> [args...]"
  toolname="$1"; shift
  # accept either id or command name
  id="$(printf '%s\n' "$TOOLS" | awk -F'|' -v t="$toolname" 'NF && ($1==t || $2==t){print $1; exit}')"
  [ -n "$id" ] || die "unknown tool: $toolname"
  if [ "$action" = "install" ]; then install_tool "$id"; else run_tool "$id" "$@"; fi
  exit 0
fi
[ "${1:-}" = "--version" ] && { say "Lim@ck DevTools v${VERSION}"; exit 0; }

while true; do menu; done
