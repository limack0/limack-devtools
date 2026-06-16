#!/usr/bin/env sh
# make-offline-bundle.sh — run this on a CONNECTED machine to prepare offline
# installers, then copy ~/.devbox-init/offline/ to the target machine (USB key, etc.).
#
# This is the differentiator: prepare once where bandwidth exists, install
# anywhere it doesn't. Tailored for low-connectivity environments.

set -eu

OUT="${HOME}/.devbox-init/offline"
mkdir -p "$OUT"

say() { printf '%s\n' "$*"; }

say "Preparing offline bundles into $OUT"

# Self-contained installer scripts are the simplest portable bundle: download
# the upstream installer once; on the target it runs from disk with no network.
fetch() {
  name="$1"; url="$2"
  say "  - $name"
  curl -fsSL "$url" -o "${OUT}/${name}"
  chmod +x "${OUT}/${name}"
}

fetch "uv"  "https://astral.sh/uv/install.sh"
fetch "nvm" "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
# Docker's convenience script also works offline-as-a-file (still needs pkg repos,
# so for fully air-gapped Docker, mirror your distro packages separately).
fetch "docker" "https://get.docker.com"

say ""
say "Done. Copy '$OUT' to the target machine's ~/.devbox-init/offline/ and run:"
say "  sh setup.sh --offline --profile=all"
