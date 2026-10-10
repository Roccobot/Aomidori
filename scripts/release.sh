#!/usr/bin/env bash
# Makes the release ZIP of a built Aomidori.app, signs it for Sparkle (EdDSA) and adds it to
# the appcast. Run on the Mac after scripts/bundle.sh and the smoke tests; the remaining steps
# (GitHub release, then pushing publish/appcast.xml) are printed at the end. See Rules.md,
# "Releases and updates".
#
#   scripts/release.sh [app]                 default: build/Aomidori.app
#
# The private key is read from the login Keychain (account "aomidori", made by
# `generate_keys --account aomidori`); macOS may ask once to let sign_update use it. With
# ED_KEY_FILE=<file> the key is read from that file instead (the `generate_keys -x` backup).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-build/Aomidori.app}"
ACCOUNT="${SPARKLE_ACCOUNT:-aomidori}"
PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_SYSTEM="$(plist LSMinimumSystemVersion)"
PUBLIC_ED_KEY="$(plist SUPublicEDKey)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]{2}$ ]]; then
  echo "CFBundleShortVersionString $VERSION is not SlimVer x.xx." >&2
  exit 1
fi
if [[ "$PUBLIC_ED_KEY" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" ]]; then
  echo "The app was built with another SUPublicEDKey than Resources/Info.plist; rebuild it." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

TOOLS="$(dirname "$(find .build/artifacts -type f -path '*/Sparkle/bin/sign_update' | head -n 1)")"
if [[ ! -x "$TOOLS/sign_update" ]]; then
  echo "Sparkle's sign_update not found in .build/artifacts; run scripts/bundle.sh first." >&2
  exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
  echo "The tag v$VERSION already exists on GitHub: raise the version first." >&2
  exit 1
fi
if [[ -n "${ED_KEY_FILE:-}" ]]; then
  # A key file inside the clone could be committed with the next `git add`: only an ignored one is accepted.
  KEY_PATH="$(cd "$(dirname "$ED_KEY_FILE")" && pwd)/$(basename "$ED_KEY_FILE")"
  if [[ "$KEY_PATH" == "$(pwd)"/* ]] && ! git check-ignore -q "$KEY_PATH"; then
    echo "ED_KEY_FILE is inside the repository and not ignored: move it out." >&2
    exit 1
  fi
  KEY_ARGS=(--ed-key-file "$ED_KEY_FILE")
else
  KEY_ARGS=(--account "$ACCOUNT")
  # The Keychain's key must be the one the app trusts, or no installed copy would accept the update.
  if [[ "$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)" != "$PUBLIC_ED_KEY" ]]; then
    echo "The Keychain key (account $ACCOUNT) does not match SUPublicEDKey." >&2
    exit 1
  fi
fi

ZIP="$(dirname "$APP")/Aomidori-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNED="$("$TOOLS/sign_update" "${KEY_ARGS[@]}" "$ZIP")"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNED")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGNED")"
if [[ -z "$SIGNATURE" || "$LENGTH" != "$(stat -f %z "$ZIP")" ]]; then
  echo "Unexpected sign_update output: $SIGNED" >&2
  exit 1
fi
"$TOOLS/sign_update" "${KEY_ARGS[@]}" --verify "$ZIP" "$SIGNATURE" >/dev/null
# The check that matters: the signature verifies with the key installed copies trust, whichever
# key (Keychain or ED_KEY_FILE) made it.
if ! swift scripts/verify-signature.swift "$PUBLIC_ED_KEY" "$SIGNATURE" "$ZIP"; then
  echo "The signature does not verify with SUPublicEDKey: wrong key, nothing added to the appcast." >&2
  exit 1
fi

python3 scripts/appcast.py add --appcast publish/appcast.xml --build "$BUILD" --version "$VERSION" \
  --length "$LENGTH" --signature "$SIGNATURE" --min-system "$MIN_SYSTEM"
shasum -a 256 "$ZIP"
cat <<NEXT
Signed $ZIP ($LENGTH bytes). Next, in this order (from the clone with the git history):
  1. gh release create v$VERSION "$ZIP" --title "Aomidori $VERSION" --notes-file <notes>
  2. commit publish/appcast.xml and push it to main: GitHub Pages publishes it, and installed
     copies see the update only then, when the ZIP already exists.
NEXT
