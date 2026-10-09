#!/usr/bin/env bash
# Builds Aomidori in release mode and assembles a signed (ad-hoc) Aomidori.app.
#
#   scripts/bundle.sh [output-directory]     default: ./build
set -euo pipefail

cd "$(dirname "$0")/.."
OUTPUT_DIR="${1:-build}"
APP="$OUTPUT_DIR/Aomidori.app"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Aomidori supports Apple Silicon only." >&2
  exit 1
fi

swift build -c release --product Aomidori
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/it.lproj"
cp "$BIN_DIR/Aomidori" "$APP/Contents/MacOS/Aomidori"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ReadingRoccobot.css "$APP/Contents/Resources/ReadingRoccobot.css"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
# An Italian localization folder makes AppKit's own menu items and panels Italian.
printf '"CFBundleDisplayName" = "Aomidori";\n' > "$APP/Contents/Resources/it.lproj/InfoPlist.strings"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Aomidori")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Unexpected architectures: $ARCHS" >&2
  exit 1
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
