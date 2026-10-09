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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Aomidori" "$APP/Contents/MacOS/Aomidori"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ReadingRoccobot.css "$APP/Contents/Resources/ReadingRoccobot.css"
cp THIRD_PARTY.md "$APP/Contents/Resources/THIRD_PARTY.md"
# CSS Playground sample text and its picture.
cp -R Resources/Playground "$APP/Contents/Resources/Playground"
# App icon by Graphe. The flat AppIcon.icns (CFBundleIconFile) is always shipped as the fallback;
# the layered Liquid Glass AppIcon.icon is compiled into Assets.car (CFBundleIconName) by Xcode's
# actool, which the Command Line Tools lack. actool also emits an .icns of its own: it is
# discarded, because Graphe's has hand-tuned 16 and 32 px sizes.
cp Resources/Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if xcrun --find actool >/dev/null 2>&1; then
  ICON_WORK="$(mktemp -d)"
  trap 'rm -rf "$ICON_WORK"' EXIT
  xcrun actool "$PWD/Resources/Icon/AppIcon.icon" \
    --compile "$ICON_WORK" \
    --platform macosx --target-device mac --minimum-deployment-target 27.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_WORK/partial.plist" \
    --errors --warnings --output-format human-readable-text >/dev/null
  if [[ ! -f "$ICON_WORK/Assets.car" ]]; then
    echo "actool did not produce Assets.car." >&2
    exit 1
  fi
  cp "$ICON_WORK/Assets.car" "$APP/Contents/Resources/Assets.car"
else
  echo "warning: actool not found (Command Line Tools only); shipping the flat icon only." >&2
fi
# Exactly two localizations: English (development language) and Italian, with the same keys.
for LANG_DIR in en.lproj it.lproj; do
  plutil -lint "Resources/$LANG_DIR/Localizable.strings" "Resources/$LANG_DIR/InfoPlist.strings" >/dev/null
  cp -R "Resources/$LANG_DIR" "$APP/Contents/Resources/$LANG_DIR"
done
if ! diff <(grep -o '^"[^"]*"' Resources/en.lproj/Localizable.strings | sort) \
          <(grep -o '^"[^"]*"' Resources/it.lproj/Localizable.strings | sort) >/dev/null; then
  echo "en.lproj and it.lproj Localizable.strings have different keys." >&2
  exit 1
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Aomidori")"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "Unexpected architectures: $ARCHS" >&2
  exit 1
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
# Finder and the Dock cache icons by bundle modification date.
touch "$APP"
echo "Built $APP"
