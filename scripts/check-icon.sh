#!/usr/bin/env bash
# Renders the Liquid Glass icon in its six appearances with Icon Composer's ictool and lists
# the icon renditions compiled into a built app's Assets.car.
#
#   scripts/check-icon.sh output-folder [build/Aomidori.app]
#
# Needs Xcode (ictool ships inside Icon Composer, assetutil with Xcode).
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="$1"
APP="${2:-build/Aomidori.app}"
mkdir -p "$OUT"

ICTOOL="$(xcrun --find ictool 2>/dev/null || true)"
if [[ -z "$ICTOOL" ]]; then
  for candidate in "/Applications/Icon Composer.app/Contents/Executables/ictool" \
                   "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"; do
    [[ -x "$candidate" ]] && ICTOOL="$candidate" && break
  done
fi
if [[ -z "$ICTOOL" ]]; then
  echo "ictool not found (Icon Composer)." >&2
  exit 1
fi

for RENDITION in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  "$ICTOOL" Resources/Icon/AppIcon.icon --export-image --output-file "$OUT/icon-$RENDITION.png" \
    --platform macOS --rendition "$RENDITION" --width 512 --height 512 --scale 1
done
xcrun assetutil --info "$APP/Contents/Resources/Assets.car" > "$OUT/assets.json"
echo "Rendered $(ls "$OUT"/icon-*.png | wc -l | tr -d ' ') appearances; Assets.car: $(grep -c '"RenditionName"' "$OUT/assets.json") renditions"
