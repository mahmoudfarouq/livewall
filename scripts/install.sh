#!/bin/sh
# Installs livewall for the current user (no sudo):
#   the binary to $PREFIX/bin, presets to $PREFIX/share/livewall/presets.
# Usage: scripts/install.sh [path/to/livewall]   (PREFIX defaults to ~/.local)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
prefix=${PREFIX:-"$HOME/.local"}
bin=${1:-}

# Find the binary: an argument, a release archive layout, or a local build.
for candidate in "$bin" "$root/livewall" "$root/.build/release/livewall"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -x "$candidate" ]; then bin=$candidate; break; fi
done
if [ -z "$bin" ] || [ ! -x "$bin" ]; then
  echo "livewall binary not found; run 'swift build -c release' first" >&2
  exit 1
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
