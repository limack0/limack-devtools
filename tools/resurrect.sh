#!/usr/bin/env sh
# resurrect — a Time Machine for your dev environment.
# Snapshot THIS machine's tools/packages/config into a portable manifest,
# then inspect, diff, or rebuild it elsewhere. "My laptop died, give me the same."
#
#   resurrect save [file]        # capture current state -> manifest
#   resurrect show <file>        # print a saved manifest
#   resurrect diff <file>        # what's missing on this machine vs the manifest
#   resurrect restore <file>     # plan the rebuild (dry by default)
#   resurrect restore <file> --apply   # actually reinstall
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'resurrect: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

detect_pm() {
  if have brew;    then echo brew;   return; fi
  if have apt-get; then echo apt;    return; fi
  if have dnf;     then echo dnf;     return; fi
  if have pacman;  then echo pacman;  return; fi
  echo unknown
}

TRACKED_TOOLS="git curl node npm pnpm yarn python3 uv ruff pipx docker go rustc cargo make gcc"

# ----- SAVE ------------------------------------------------------------------
cmd_save() {
  out="${1:-resurrect-$(hostname 2>/dev/null || echo host)-$(date +%Y%m%d).manifest}"
  pm="$(detect_pm)"
  info "snapshotting this machine -> ${B}${out}${R}"

  {
    echo "# resurrect manifest v1"
    echo "[meta]"
    echo "host=$(hostname 2>/dev/null || echo unknown)"
    echo "date=$(date -u +%FT%TZ)"
    echo "os=$(uname -s)"
    echo "kernel=$(uname -r)"
    # shellcheck disable=SC1091
    [ -f /etc/os-release ] && . /etc/os-release 2>/dev/null && echo "distro=${PRETTY_NAME:-unknown}"
    echo "shell=${SHELL:-unknown}"
    echo "pm=$pm"

    echo "[tools]"
    for t in $TRACKED_TOOLS; do
      if have "$t"; then
        v="$("$t" --version 2>/dev/null | head -1 | tr -d '\r')"
        echo "${t}=${v:-present}"
      fi
    done

    echo "[pm-packages]"
    case "$pm" in
      apt)  apt-mark showmanual 2>/dev/null ;;
      brew) brew leaves 2>/dev/null ;;
      dnf)  dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null ;;
      pacman) pacman -Qqe 2>/dev/null ;;
    esac

    echo "[uv-tools]"
    have uv && uv tool list 2>/dev/null | awk 'NF && $1!="-"{print $1}' || true

    echo "[pipx]"
    have pipx && pipx list --short 2>/dev/null | awk '{print $1}' || true

    echo "[npm-global]"
    have npm && npm ls -g --depth=0 2>/dev/null | sed -n 's/^[^ ]* //p' | grep -E '@?[a-zA-Z]' | sed 's/@[0-9].*$//' || true

    echo "[gitconfig]"
    have git && git config --global --list 2>/dev/null || true
  } > "$out"

  ok "wrote $out ($(wc -l < "$out" | tr -d ' ') lines)"
  info "carry it to a new machine, then:  resurrect restore '$out'"
}

# read one section's body lines from a manifest
section() { awk -v s="[$2]" '$0==s{f=1;next} /^\[/{f=0} f' "$1"; }

cmd_show() {
  f="${1:-}"; [ -f "$f" ] || die "manifest not found: ${f:-<none>}"
  info "meta";        section "$f" meta | sed 's/^/  /'
  info "tools";       section "$f" tools | sed 's/^/  /'
  info "pm-packages"; n=$(section "$f" pm-packages | grep -c . || true); echo "  ${n} package(s)"
  info "npm-global";  section "$f" npm-global | sed 's/^/  /'
  info "uv-tools";    section "$f" uv-tools | sed 's/^/  /'
}

cmd_diff() {
  f="${1:-}"; [ -f "$f" ] || die "manifest not found: ${f:-<none>}"
  pm="$(detect_pm)"; missing=0
  info "tools missing here"
  section "$f" tools | while IFS='=' read -r t _; do
    [ -n "$t" ] || continue
    have "$t" || printf '   %s-%s %s\n' "$YE" "$R" "$t"
  done
  info "pm-packages missing here ${D}(pm=$pm)${R}"
  section "$f" pm-packages | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$pm" in
      apt)  dpkg -s "$p" >/dev/null 2>&1 || printf '   %s-%s %s\n' "$YE" "$R" "$p" ;;
      brew) brew list "$p" >/dev/null 2>&1 || printf '   %s-%s %s\n' "$YE" "$R" "$p" ;;
      *)    printf '   %s?%s %s\n' "$D" "$R" "$p" ;;
    esac
  done
  [ "$missing" -eq 0 ] || true
}

cmd_restore() {
  f="${1:-}"; apply=0
  [ -f "$f" ] || die "manifest not found: ${f:-<none>}"
  [ "${2:-}" = "--apply" ] && apply=1
  pm="$(detect_pm)"

  run() { # echo, then run only if --apply
    printf '   %s$ %s%s\n' "$D" "$*" "$R"
    [ "$apply" -eq 1 ] && eval "$*" || true
  }

  [ "$apply" -eq 1 ] || warn "DRY RUN — showing the plan. Add --apply to execute."

  pkgs="$(section "$f" pm-packages | grep . | tr '\n' ' ')"
  if [ -n "$pkgs" ]; then
    info "package manager ($pm)"
    case "$pm" in
      apt)  run "sudo apt-get update -qq && sudo apt-get install -y $pkgs" ;;
      brew) run "brew install $pkgs" ;;
      dnf)  run "sudo dnf install -y $pkgs" ;;
      pacman) run "sudo pacman -S --noconfirm $pkgs" ;;
      *) warn "unknown pm — install manually: $pkgs" ;;
    esac
  fi

  uvt="$(section "$f" uv-tools | grep . | tr '\n' ' ')"
  [ -n "$uvt" ] && { info "uv tools"; for t in $uvt; do run "uv tool install $t"; done; }

  npmg="$(section "$f" npm-global | grep . | tr '\n' ' ')"
  [ -n "$npmg" ] && { info "npm globals"; run "npm install -g $npmg"; }

  info "git config"
  section "$f" gitconfig | while IFS='=' read -r k v; do
    [ -n "$k" ] || continue
    run "git config --global '$k' '$v'"
  done

  if [ "$apply" -eq 1 ]; then ok "restore complete"; else info "re-run with --apply to execute"; fi
}

case "${1:-}" in
  save)      shift; cmd_save    "$@" ;;
  show)      shift; cmd_show    "$@" ;;
  diff)      shift; cmd_diff    "$@" ;;
  restore)   shift; cmd_restore "$@" ;;
  --version) printf 'resurrect v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'resurrect — snapshot/restore your dev environment.\n\n'
    printf '  save [file]            capture this machine -> manifest\n'
    printf '  show <file>            print a manifest\n'
    printf '  diff <file>            what is missing here vs the manifest\n'
    printf '  restore <file>         plan the rebuild (dry)\n'
    printf '  restore <file> --apply actually reinstall\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
