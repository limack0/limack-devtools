#!/usr/bin/env sh
# test.sh — smoke test for the whole pack. Runs only safe paths (no installs,
# no network, no system mutation) so it's green locally and in CI.
# Exits non-zero if any check fails.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$HERE/tools"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \033[32mok\033[0m  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mXX\033[0m  %s\n' "$1"; }

# helpers use _-prefixed vars so they never clobber the test body's variables.
# pass if the command exits 0 (stdin from /dev/null so nothing blocks)
t()    { _d="$1"; shift; if "$@" </dev/null >/dev/null 2>&1; then ok "$_d"; else bad "$_d"; fi; }
# pass if the command exits NON-zero
tfail(){ _d="$1"; shift; if "$@" </dev/null >/dev/null 2>&1; then bad "$_d"; else ok "$_d"; fi; }
# pass if output contains a substring
tout() { _d="$1"; _w="$2"; shift 2; _o="$("$@" 2>&1 </dev/null || true)"; case "$_o" in *"$_w"*) ok "$_d";; *) bad "$_d";; esac; }

echo "== --version / --help on every tool + hub =="
for x in devbox peek sneakersync wat resurrect litemirror tunnelforge \
         deadmanswitch secrets-doctor relay fr oneshot landrop; do
  t "$x --version" sh "$T/$x.sh" --version
  t "$x --help"    sh "$T/$x.sh" --help
done
t "hub --version" sh "$HERE/install.sh" --version

echo "== functional smoke =="

# peek scores a dangerous script
tmp="$(mktemp)"; printf '#!/bin/sh\nsudo rm -rf /\n' > "$tmp"
tout "peek scores risk" "risk score" sh "$T/peek.sh" --print "$tmp"; rm -f "$tmp"

# secrets-doctor: finds a planted key (exit!=0), clean dir is exit 0
d="$(mktemp -d)"; echo 'k=AKIAZ1234567890ABCDE' > "$d/x.env"
tfail "secrets-doctor flags a secret" sh "$T/secrets-doctor.sh" scan "$d"
rm "$d/x.env"; echo 'clean=1' > "$d/ok.env"
t "secrets-doctor passes a clean dir" sh "$T/secrets-doctor.sh" scan "$d"; rm -rf "$d"

# relay: offline queues, online flush runs it
rd="$(mktemp -d)"; mark="$rd/done"
RELAY_DIR="$rd" RELAY_CHECK_URL="http://127.0.0.1:1" sh "$T/relay.sh" -- touch "$mark" >/dev/null 2>&1
if [ -f "$mark" ]; then bad "relay queues while offline"; else ok "relay queues while offline"; fi
RELAY_DIR="$rd" RELAY_CHECK_URL="file:///etc/hostname" sh "$T/relay.sh" flush >/dev/null 2>&1
if [ -f "$mark" ]; then ok "relay flush runs the job"; else bad "relay flush runs the job"; fi
rm -rf "$rd"

# relay: dedup identical jobs
rd="$(mktemp -d)"
for _ in 1 2; do RELAY_DIR="$rd" RELAY_CHECK_URL="http://127.0.0.1:1" sh "$T/relay.sh" -- git push >/dev/null 2>&1; done
n="$(find "$rd/queue" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n" = 1 ]; then ok "relay dedups identical jobs"; else bad "relay dedups identical jobs (got $n)"; fi
rm -rf "$rd"

# resurrect: snapshot writes a manifest with the expected sections
m="$(mktemp)"; sh "$T/resurrect.sh" save "$m" >/dev/null 2>&1
if grep -q '^\[tools\]' "$m" 2>/dev/null; then ok "resurrect save writes a manifest"; else bad "resurrect save writes a manifest"; fi
if sh "$T/resurrect.sh" show "$m" >/dev/null 2>&1; then ok "resurrect show reads it"; else bad "resurrect show reads it"; fi
rm -f "$m"

# wat / fr: build a valid request payload (dry, via a pipe)
o="$(printf 'err\n' | sh "$T/wat.sh" --dry 2>&1)"; case "$o" in *messages*) ok "wat --dry builds payload";; *) bad "wat --dry builds payload";; esac
o="$(printf 'q\n'   | sh "$T/fr.sh"  --dry 2>&1)"; case "$o" in *messages*) ok "fr --dry builds payload";;  *) bad "fr --dry builds payload";;  esac

# landrop / litemirror: client config + dry request
tout "landrop client config"   "LANDROP_HOST" sh "$T/landrop.sh" client
tout "landrop ask --dry"        "api/chat"     sh "$T/landrop.sh" ask --dry "hi"
tout "litemirror client config" "find-links"   sh "$T/litemirror.sh" client

# deadman: a down->up transition raises a RECOVERED alert (dry)
dd="$(mktemp -d)"
DEADMAN_DIR="$dd" DEADMAN_DRY=1 sh "$T/deadmanswitch.sh" add x --cmd 'false' >/dev/null 2>&1
DEADMAN_DIR="$dd" DEADMAN_DRY=1 sh "$T/deadmanswitch.sh" check >/dev/null 2>&1
DEADMAN_DIR="$dd" DEADMAN_DRY=1 sh "$T/deadmanswitch.sh" add x --cmd 'true' >/dev/null 2>&1
tout "deadman alerts on recovery" "RECOVERED" env DEADMAN_DIR="$dd" DEADMAN_DRY=1 sh "$T/deadmanswitch.sh" check
rm -rf "$dd"

# oneshot: host --dry writes a valid proxy compose
od="$(mktemp -d)"
ONESHOT_DIR="$od" sh "$T/oneshot.sh" host --dry >/dev/null 2>&1
if grep -q caddy-docker-proxy "$od/docker-compose.yml" 2>/dev/null; then ok "oneshot host writes proxy compose"; else bad "oneshot host writes proxy compose"; fi
rm -rf "$od"

echo
printf 'PASS=%s  FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
