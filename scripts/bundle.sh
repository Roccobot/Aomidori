#!/usr/bin/env bash
# Builds Aomidori in release mode and assembles a signed (ad-hoc) Aomidori.app, with
# Sparkle.framework embedded for automatic updates.
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
# The empty window's drop zone art by Graphe (SVG, PNG fallbacks).
cp -R Resources/EmptyState "$APP/Contents/Resources/EmptyState"
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
PUBLIC_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
if [[ "$(printf '%s' "$PUBLIC_ED_KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" != "32" ]]; then
  echo "warning: SUPublicEDKey is not a Sparkle public key; this build will not check for updates." >&2
fi

# Sparkle (automatic updates), from the official binary package SwiftPM fetched. It goes where
# the executable's rpath looks (@executable_path/../Frameworks, see Package.swift), thinned to
# arm64 like the app (ditto --arch leaves signed binaries universal, so lipo thins every Mach-O
# file; the signatures are redone below). ditto keeps the framework's symlinks.
SPARKLE_SRC="$BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_SRC" ]]; then
  SPARKLE_SRC="$(find .build/artifacts -type d -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' -prune | head -n 1)"
fi
if [[ ! -d "$SPARKLE_SRC" ]]; then
  echo "Sparkle.framework not found in $BIN_DIR or .build/artifacts." >&2
  exit 1
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SRC" "$FRAMEWORK"
while IFS= read -r -d '' FILE; do
  if FILE_ARCHS="$(lipo -archs "$FILE" 2>/dev/null)" && [[ "$FILE_ARCHS" == *" "* ]]; then
    # cat, not mv: the file keeps its mode.
    lipo -thin arm64 "$FILE" -output "$FILE.thin" && cat "$FILE.thin" > "$FILE" && rm "$FILE.thin"
  fi
done < <(find "$FRAMEWORK/Versions/B" -type f -perm -u+x -print0)
if ! otool -l "$APP/Contents/MacOS/Aomidori" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
  echo "The executable has no @executable_path/../Frameworks rpath." >&2
  exit 1
fi
if ! otool -L "$APP/Contents/MacOS/Aomidori" | grep -q '@rpath/Sparkle.framework/'; then
  echo "The executable does not link Sparkle through @rpath." >&2
  exit 1
fi
if [[ "$(lipo -archs "$FRAMEWORK/Versions/B/Sparkle")" != "arm64" || "$(lipo -archs "$FRAMEWORK/Versions/B/Autoupdate")" != "arm64" ]]; then
  echo "Sparkle.framework was not thinned to arm64." >&2
  exit 1
fi

# Ad-hoc signature, inside out, as Sparkle's documentation orders it: nested code first, each
# with its own signature, the framework, then the app. No --deep: it would sign the XPC services
# without the Downloader's entitlements. No hardened runtime (-o runtime), as before.
sign() { codesign --force --sign - --timestamp=none "$@"; }
sign --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP"
codesign --verify --strict "$APP"
# --deep only to verify every nested signature, which Sparkle needs valid to accept an update.
codesign --verify --deep --strict "$APP"
# Finder and the Dock cache icons by bundle modification date.
touch "$APP"
echo "Built $APP"
