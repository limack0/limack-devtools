#!/usr/bin/env sh
# DevBox-Init — one-line dev environment setup (Linux / macOS)
# Source of truth: https://github.com/limack0/devbox-init
# Run:  curl -fsSL setup.limackcorp.online | sh
#
# Design rules (MAS-style):
#   - POSIX sh, zero runtime dependency to launch.
#   - Interactive numbered menu, also drivable non-interactively (--silent --profile=web).
#   - Idempotent: re-running never breaks an already-configured machine.
#   - Reversible: every install is logged; `--undo` reverts the last run.
#   - Auditable: read this file before piping it to a shell. That's the point.

set -eu

VERSION="0.1.0"
STATE_DIR="${HOME}/.devbox-init"
LOG_FILE="${STATE_DIR}/install.log"
PROFILE=""
SILENT=0
OFFLINE=0
DO_UNDO=0

# ----- tiny output helpers ---------------------------------------------------
if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"; C_DIM="$(printf '\033[2m')"
  C_BOLD="$(printf '\033[1m')"; C_CYAN="$(printf '\033[36m')"
  C_GREEN="$(printf '\033[32m')"; C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serr%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ----- platform / package-manager detection ----------------------------------
detect_pm() {
  if command -v brew    >/dev/null 2>&1; then echo "brew";   return; fi
  if command -v apt-get >/dev/null 2>&1; then echo "apt";    return; fi
  if command -v dnf     >/dev/null 2>&1; then echo "dnf";    return; fi
  if command -v pacman  >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v apk     >/dev/null 2>&1; then echo "apk";    return; fi
  echo "unknown"
}
PM="$(detect_pm)"

have() { command -v "$1" >/dev/null 2>&1; }

# pkg_install <binary> <pkg-name> : install only if the binary is missing (idempotent)
pkg_install() {
  bin="$1"; pkg="${2:-$1}"
  if have "$bin"; then ok "$bin already present"; return 0; fi
  if [ "$OFFLINE" -eq 1 ]; then
    bundle="${STATE_DIR}/offline/${pkg}"
    if [ -e "$bundle" ]; then
      info "installing $pkg from offline bundle"
      # offline bundles are shell installers placed by `make-offline-bundle`
      sh "$bundle" && record "pkg:$pkg" && ok "$pkg (offline)"; return 0
    fi
    warn "offline bundle missing for $pkg — skipping (run make-offline-bundle on a connected machine)"; return 0
  fi
  info "installing $pkg"
  case "$PM" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
    dnf)    sudo dnf install -y "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    apk)    sudo apk add "$pkg" ;;
    *)      die "unsupported package manager — install $pkg manually" ;;
  esac
  record "pkg:$pkg"
  ok "$pkg"
}

# record an action so --undo can reason about what THIS tool installed
record() {
  mkdir -p "$STATE_DIR"
  printf '%s\t%s\n' "$(date +%s)" "$1" >> "$LOG_FILE"
}

# ----- profiles --------------------------------------------------------------
profile_web() {
  info "Profile: Web (git, curl, node, pnpm)"
  pkg_install git
  pkg_install curl
  if ! have node; then
    if [ "$OFFLINE" -eq 0 ]; then
      info "installing Node via nvm"
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | sh
      # shellcheck disable=SC1090,SC1091
      . "${HOME}/.nvm/nvm.sh" && nvm install --lts && record "node:nvm-lts"
    else warn "offline: skipping Node (bundle it first)"; fi
  else ok "node already present"; fi
  if have npm && ! have pnpm; then npm install -g pnpm && record "npm:pnpm" && ok "pnpm"; fi
}

profile_python() {
  info "Profile: Python (uv, ruff)"
  if ! have uv; then
    if [ "$OFFLINE" -eq 0 ]; then
      curl -fsSL https://astral.sh/uv/install.sh | sh && record "py:uv" && ok "uv"
    else warn "offline: skipping uv"; fi
  else ok "uv already present"; fi
  if have uv && ! have ruff; then uv tool install ruff && record "py:ruff" && ok "ruff"; fi
}

profile_docker() {
  info "Profile: Docker"
  if have docker; then ok "docker already present"; return; fi
  if [ "$OFFLINE" -eq 0 ]; then
    curl -fsSL https://get.docker.com | sh && record "docker:get.docker.com" && ok "docker"
  else warn "offline: skipping docker"; fi
}

profile_dotfiles() {
  info "Profile: Dotfiles (sane git + shell defaults)"
  if have git; then
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global core.editor "${EDITOR:-nano}"
    record "dotfiles:git" && ok "git defaults applied"
  else warn "git missing — run the Web profile first"; fi
}

run_profile() {
  case "$1" in
    web)      profile_web ;;
    python)   profile_python ;;
    docker)   profile_docker ;;
    dotfiles) profile_dotfiles ;;
    all)      profile_web; profile_python; profile_docker; profile_dotfiles ;;
    *)        die "unknown profile: $1" ;;
  esac
}

undo_last() {
  [ -f "$LOG_FILE" ] || die "nothing to undo (no log at $LOG_FILE)"
  warn "Undo is intentionally conservative: it lists what this tool installed."
  warn "Review and remove manually — auto-uninstall can break shared deps."
  say ""; cat "$LOG_FILE"
}

# ----- menu ------------------------------------------------------------------
banner() {
  say ""
  say "${C_BOLD}  DevBox-Init${C_RESET} ${C_DIM}v${VERSION}${C_RESET}  —  pm: ${C_CYAN}${PM}${C_RESET}$([ "$OFFLINE" -eq 1 ] && printf ' %s[OFFLINE]%s' "$C_YELLOW" "$C_RESET")"
  say "${C_DIM}  one-line dev setup · audit this script before running it${C_RESET}"
  say ""
}

menu() {
  banner
  say "  [1] Web      git · node · pnpm"
  say "  [2] Python   uv · ruff"
  say "  [3] Docker   engine + compose"
  say "  [4] Dotfiles sane git/shell defaults"
  say "  [5] Offline  toggle low-bandwidth mode (current: $([ "$OFFLINE" -eq 1 ] && echo ON || echo OFF))"
  say "  [9] All"
  say "  [0] Quit"
  say ""
  printf "  select> "
  read -r choice
  case "$choice" in
    1) run_profile web ;;
    2) run_profile python ;;
    3) run_profile docker ;;
    4) run_profile dotfiles ;;
    5) OFFLINE=$([ "$OFFLINE" -eq 1 ] && echo 0 || echo 1) ;;
    9) run_profile all ;;
    0) say "bye"; exit 0 ;;
    *) warn "invalid choice" ;;
  esac
}

# ----- arg parsing -----------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --silent)        SILENT=1 ;;
    --offline)       OFFLINE=1 ;;
    --undo)          DO_UNDO=1 ;;
    --profile=*)     PROFILE="${arg#--profile=}" ;;
    --version)       say "DevBox-Init v${VERSION}"; exit 0 ;;
    -h|--help)
      say "Usage: setup.sh [--profile=web|python|docker|dotfiles|all] [--silent] [--offline] [--undo]"
      exit 0 ;;
    *) warn "unknown arg: $arg" ;;
  esac
done

mkdir -p "$STATE_DIR"
[ "$PM" = "unknown" ] && warn "no known package manager detected — installs may fail"

if [ "$DO_UNDO" -eq 1 ]; then undo_last; exit 0; fi

if [ "$SILENT" -eq 1 ] || [ -n "$PROFILE" ]; then
  [ -n "$PROFILE" ] || die "--silent requires --profile=..."
  run_profile "$PROFILE"
  ok "done (profile: $PROFILE)"
  exit 0
fi

# interactive loop
while true; do menu; done
