#!/usr/bin/env sh
# sneakersync — move a git repo between machines with no shared network.
# Uses `git bundle` to pack a repo (or a delta) onto a USB key, then unpack it
# on the other side. Built for places where the network is the unreliable part.
#
#   sneakersync push  /media/usb            # bundle THIS repo onto the key
#   sneakersync list  /media/usb            # what's on the key
#   sneakersync pull  /media/usb            # fetch into THIS repo (safe, namespaced)
#   sneakersync clone /media/usb myrepo dir # fresh clone from a bundled repo
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
die()  { printf 'sneakersync: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"

repo_name() { basename "$(git rev-parse --show-toplevel)"; }
in_repo()   { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repo"; }

cmd_push() {
  dest="${1:-}"; [ -n "$dest" ] || die "usage: sneakersync push <usb-path>"
  in_repo
  [ -d "$dest" ] || die "destination not found: $dest"
  name="$(repo_name)"
  bundle="${dest}/${name}.bundle"
  state="$(git rev-parse --git-dir)/sneakersync.last"

  if [ -f "$bundle" ] && [ -f "$state" ]; then
    base="$(cat "$state")"
    if git cat-file -e "${base}^{commit}" 2>/dev/null; then
      info "incremental bundle since ${D}${base}${R} (delta only)"
      if git bundle create "$bundle" "${base}..HEAD" --branches --tags 2>/dev/null; then
        :
      else
        warn "no new commits since last sync — re-bundling full repo"
        git bundle create "$bundle" --branches --tags
      fi
    else
      info "previous base unknown here — full bundle"
      git bundle create "$bundle" --branches --tags
    fi
  else
    info "full bundle of ${B}${name}${R}"
    git bundle create "$bundle" --branches --tags
  fi

  git rev-parse HEAD > "$state"
  printf '%s\t%s\t%s\n' "$name" "$(git rev-parse HEAD)" "$(date -u +%FT%TZ)" \
    >> "${dest}/.sneakersync-manifest"
  ok "wrote ${bundle}  ($(du -h "$bundle" | cut -f1))"
  ok "carry the key to the other machine, then: sneakersync pull '${dest}'"
}

cmd_list() {
  src="${1:-}"; [ -n "$src" ] || die "usage: sneakersync list <usb-path>"
  [ -d "$src" ] || die "not found: $src"
  found=0
  for b in "$src"/*.bundle; do
    [ -e "$b" ] || continue
    found=1
    name="$(basename "$b" .bundle)"
    head="$(git bundle list-heads "$b" 2>/dev/null | head -1 || true)"
    printf '  %s%-20s%s %s%s%s  %s\n' "$B" "$name" "$R" "$D" "$(du -h "$b" | cut -f1)" "$R" "$head"
  done
  [ "$found" -eq 1 ] || warn "no .bundle files in $src"
}

cmd_pull() {
  src="${1:-}"; [ -n "$src" ] || die "usage: sneakersync pull <usb-path> [name]"
  in_repo
  name="${2:-$(repo_name)}"
  bundle="${src}/${name}.bundle"
  [ -f "$bundle" ] || die "no bundle for '${name}' at ${src} (try: sneakersync list '${src}')"

  if ! git bundle verify "$bundle" >/dev/null 2>&1; then
    die "bundle needs commits this repo doesn't have — clone fresh instead, or get a full bundle"
  fi
  # Non-destructive: land incoming branches under refs/sneaker/* so nothing is clobbered.
  git fetch "$bundle" '+refs/heads/*:refs/sneaker/*'
  ok "fetched into refs/sneaker/*"
  info "review:   git branch -r --list 'sneaker/*'  (or: git log sneaker/main)"
  info "adopt:    git merge sneaker/main   # or: git checkout -b local sneaker/main"
  git rev-parse "refs/sneaker/$(git rev-parse --abbrev-ref HEAD)" > "$(git rev-parse --git-dir)/sneakersync.last" 2>/dev/null || true
}

cmd_clone() {
  src="${1:-}"; name="${2:-}"; dir="${3:-}"
  [ -n "$src" ] && [ -n "$name" ] || die "usage: sneakersync clone <usb-path> <name> [dir]"
  bundle="${src}/${name}.bundle"
  [ -f "$bundle" ] || die "no bundle for '${name}' at ${src}"
  dir="${dir:-$name}"
  git clone "$bundle" "$dir"
  ok "cloned '${name}' -> ${dir}"
  warn "origin points at the bundle file; set a real remote with: git -C '${dir}' remote set-url origin <url>"
}

case "${1:-}" in
  push)      shift; cmd_push  "$@" ;;
  list)      shift; cmd_list  "$@" ;;
  pull)      shift; cmd_pull  "$@" ;;
  clone)     shift; cmd_clone "$@" ;;
  --version) printf 'sneakersync v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'sneakersync — git over USB, no network.\n\n'
    printf '  push  <usb>            bundle this repo onto the key (delta after first time)\n'
    printf '  list  <usb>            list bundles on the key\n'
    printf '  pull  <usb> [name]     fetch into this repo (safe, under refs/sneaker/*)\n'
    printf '  clone <usb> <name>[dir] fresh clone from a bundle\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
