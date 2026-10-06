#!/bin/sh
# Copies ~/Documents/personal/<slug>/index.html to presets/<slug>.html for every slug
# below whose source exists. Re-run it as new pieces land.
SLUGS="
pocket-universe
night-city
ink-water
word-creatures
tide-pool
mycelium
murmuration
last-train
lighthouse-keeper
sand-garden
glassblower
orrery
weather-jar
dream-archive
"
SRC="${SRC:-$HOME/Documents/personal}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/presets"
mkdir -p "$DEST"
for slug in $SLUGS; do
    if [ -f "$SRC/$slug/index.html" ]; then
        cp "$SRC/$slug/index.html" "$DEST/$slug.html"
        echo "synced  $slug"
    else
        echo "skipped $slug (no $SRC/$slug/index.html yet)"
    fi
done
