#!/bin/sh
# Installs livewall for the current user (no sudo):
#   the binary to $PREFIX/bin, presets to $PREFIX/share/livewall/presets.
# Usage: scripts/install.sh [path/to/livewall]   (PREFIX defaults to ~/.local)
# Piped from curl, with no release or build next to it, it downloads the latest release first.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
prefix=${PREFIX:-"$HOME/.local"}
bin=${1:-}

# Find the binary: an argument, a release archive layout, or a local build.
for candidate in "$bin" "$root/livewall" "$root/.build/release/livewall"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -x "$candidate" ]; then bin=$candidate; break; fi
done
if [ -z "$bin" ] || [ ! -x "$bin" ] || [ ! -d "$root/presets" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading the latest livewall release"
  curl -fsSL https://github.com/mahmoudfarouq/livewall/releases/latest/download/livewall-macos-universal.tar.gz | tar -xz -C "$tmp"
  root="$tmp/livewall"
  bin="$root/livewall"
fi

presets="$prefix/share/livewall/presets"
mkdir -p "$prefix/bin" "$presets"
cp "$bin" "$prefix/bin/livewall"
# Downloaded archives get quarantined by Gatekeeper; the binary isn't notarized.
xattr -d com.apple.quarantine "$prefix/bin/livewall" 2>/dev/null || true
cp "$root"/presets/*.html "$presets/"

set -- "$root"/presets/*.html
echo "installed $prefix/bin/livewall and $# presets"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "note: add $prefix/bin to your PATH" ;; esac
