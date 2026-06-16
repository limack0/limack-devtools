#!/usr/bin/env sh
# secrets-doctor — find leaked secrets before they leave your machine.
# 100% local: nothing is ever uploaded. Scans files for API keys, tokens and
# private keys, redacts what it finds, and can gate your commits.
#
#   secrets-doctor scan [path]      # scan a dir/file (default: .)
#   secrets-doctor staged           # scan only git-staged files (pre-commit)
#   secrets-doctor install-hook     # install a pre-commit hook that runs 'staged'
#
# Exit code is non-zero when secrets are found, so it works in CI and hooks.
#
# Part of Lim@ck DevTools — https://github.com/limack0/limack-devtools

set -eu

VERSION="0.1.0"
if [ -t 1 ]; then
  R="$(printf '\033[0m')"; D="$(printf '\033[2m')"; B="$(printf '\033[1m')"
  CY="$(printf '\033[36m')"; GR="$(printf '\033[32m')"; YE="$(printf '\033[33m')"; RED="$(printf '\033[31m')"
else R=""; D=""; B=""; CY=""; GR=""; YE=""; RED=""; fi
info() { printf '%s==>%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%swarn%s %s\n' "$YE" "$R" "$*" >&2; }
die()  { printf 'secrets-doctor: %s\n' "$*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

EXCLUDES=".git node_modules vendor .venv venv env dist build target __pycache__ .next .cache"

# rule list: NAME|EXTENDED-REGEX  (one per line). Tuned to be high-signal.
rules() {
cat <<'EOF'
AWS Access Key|AKIA[0-9A-Z]{16}
GitHub Token|gh[posru]_[0-9A-Za-z]{36,}
GitHub PAT|github_pat_[0-9A-Za-z_]{60,}
Slack Token|xox[baprs]-[0-9A-Za-z-]{10,}
Google API Key|AIza[0-9A-Za-z_-]{35}
OpenAI/OpenRouter Key|sk-(or-)?[A-Za-z0-9_-]{20,}
Stripe Live Key|[rsp]k_live_[0-9A-Za-z]{16,}
Telegram Bot Token|[0-9]{8,10}:[A-Za-z0-9_-]{35}
Private Key Block|-----BEGIN [A-Z ]*PRIVATE KEY-----
JWT|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
Generic Secret Assignment|(api[_-]?key|secret|token|passwd|password|access[_-]?key)["' ]*[:=]["' ]*[A-Za-z0-9_+/-]{16,}
EOF
}

# obvious placeholders / examples we should not flag
is_placeholder() {
  printf '%s' "$1" | grep -qiE 'example|placeholder|changeme|your[_-]|_here|xxxx+|<[a-z_]+>|0000000|redacted|dummy|sample|fake[_-]?(key|token|secret)'
}

mask() { # show first 4 chars, hide the rest
  t="$1"
  printf '%s***' "$(printf '%s' "$t" | cut -c1-4)"
}

build_grep_excludes() {
  ge=""
  for d in $EXCLUDES; do ge="$ge --exclude-dir=$d"; done
  printf '%s' "$ge"
}

FOUND=0

# scan a single path (dir or file) against all rules
scan_path() {
  target="$1"
  ge="$(build_grep_excludes)"
  rules | while IFS='|' read -r name pat; do
    [ -n "$name" ] || continue
    # -r recurse, -n line numbers, -I skip binaries, -H always show filename
    # (-H matters when scanning a single file), -E extended regex
    # shellcheck disable=SC2086
    grep -rnIHE $ge -e "$pat" "$target" 2>/dev/null | while IFS= read -r hit; do
      file="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; content="${rest#*:}"
      token="$(printf '%s' "$content" | grep -oE -e "$pat" | head -1)"
      [ -n "$token" ] || continue
      is_placeholder "$content" && continue
      printf '%s●%s %s%s%s:%s%s%s  %s[%s]%s  %s\n' \
        "$RED" "$R" "$B" "$file" "$R" "$YE" "$lineno" "$R" \
        "$D" "$name" "$R" "$(mask "$token")"
      # signal a find via a marker file (subshell can't set parent vars)
      echo x >> "$MARK"
    done
  done
}

run_scan() {
  target="${1:-.}"
  [ -e "$target" ] || die "path not found: $target"
  MARK="$(mktemp)"; export MARK
  info "scanning ${B}${target}${R} ${D}(local only — nothing leaves this machine)${R}"
  echo
  scan_path "$target"
  count=$(wc -l < "$MARK" | tr -d ' '); rm -f "$MARK"
  echo
  if [ "$count" -gt 0 ]; then
    printf '%s  %s potential secret(s) found.%s redact/rotate them before committing.\n' "$RED$B" "$count" "$R"
    return 1
  fi
  ok "no secrets detected"
  return 0
}

run_staged() {
  have git || die "not a git repo / git missing"
  files="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)"
  [ -n "$files" ] || { ok "no staged files"; return 0; }
  MARK="$(mktemp)"; export MARK
  info "scanning staged files ${D}(pre-commit)${R}"; echo
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] && scan_path "$f"
  done
  count=$(wc -l < "$MARK" | tr -d ' '); rm -f "$MARK"
  echo
  if [ "$count" -gt 0 ]; then
    printf '%s  %s potential secret(s) in staged changes — commit blocked.%s\n' "$RED$B" "$count" "$R"
    return 1
  fi
  ok "staged changes are clean"
  return 0
}

install_hook() {
  have git || die "not a git repo"
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repo"
  hook="$root/.git/hooks/pre-commit"
  [ -f "$hook" ] && cp "$hook" "$hook.bak.$(date +%s)" && warn "backed up existing pre-commit hook"
  cat > "$hook" <<'HOOK'
#!/usr/bin/env sh
# installed by secrets-doctor
if command -v secrets-doctor >/dev/null 2>&1; then
  secrets-doctor staged || { echo "secrets-doctor blocked this commit. Use 'git commit --no-verify' to override (not recommended)."; exit 1; }
fi
HOOK
  chmod +x "$hook"
  ok "installed pre-commit hook -> $hook"
}

case "${1:-}" in
  scan)         shift; run_scan "${1:-.}" ;;
  staged)       shift; run_staged ;;
  install-hook) shift; install_hook ;;
  --version)    printf 'secrets-doctor v%s\n' "$VERSION" ;;
  -h|--help|"")
    printf 'secrets-doctor — find leaked secrets locally before they ship.\n\n'
    printf '  scan [path]       scan a dir/file (default .)\n'
    printf '  staged            scan git-staged files (pre-commit)\n'
    printf '  install-hook      add a pre-commit hook that runs '\''staged'\''\n\n'
    printf '  Exit code is non-zero when secrets are found.\n'
    ;;
  *) die "unknown command: $1 (try --help)" ;;
esac
