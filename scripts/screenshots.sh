#!/usr/bin/env bash
# Takes the download page's four screenshots with a built Aomidori.app (see ScreenshotSession).
#
#   APP=build/Aomidori.app scripts/screenshots.sh work-folder italian.epub english.epub [spine]
#
# For each language and theme the app opens the book of that language at the spine item
# `spine` (default 3), with factory settings and its own support folder, in the asked theme
# (macOS's own is not touched), and comes to the front for a moment: the window is captured with
# `screencapture -l` into publish/assets/screenshot-<it|en>-<light|dark>.png. The books must be
# in the public domain: the page is public. Needs Screen Recording for the calling app, and the
# Mac awake and unlocked (caffeinate). The installed copy in ~/Applications is left alone.
# Author: Rocco Casadei, a.k.a. Roccobot
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "$1"
WORK="$(cd "$1" && pwd)"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"
BIN="$APP/Contents/MacOS/Aomidori"
SPINE="${4:-3}"
# Whatever happens, the test copy does not stay in front of the user's windows.
trap 'pkill -f "^$BIN" 2>/dev/null || true' EXIT

for lang in it en; do
  for theme in light dark; do
    out="$WORK/$lang-$theme"
    rm -rf "$out"; mkdir -p "$out"
    pkill -f "^$BIN" 2>/dev/null && sleep 1 || true
    if [[ "$lang" == it ]]; then given="$2"; else given="$3"; fi
    book="$(cd "$(dirname "$given")" && pwd)/$(basename "$given")"
    open -n -a "$APP" "$book" --args -AomidoriScreenshot "$out" -AomidoriScreenshotTheme "$theme" \
      -AomidoriScreenshotSpine "$SPINE" -AppleLanguages "($lang)"
    for _ in {1..60}; do [[ -s "$out/window.txt" ]] && break; sleep 0.5; done
    if [[ ! -s "$out/window.txt" ]]; then
      pkill -f "^$BIN" 2>/dev/null || true
      echo "No window for $lang $theme" >&2
      exit 1
    fi
    # macOS lets an app take the front only cooperatively; `open` on the running copy does it,
    # so the window is captured active, with coloured buttons and full-strength text.
    open -a "$APP"
    sleep 1.5
    shot="publish/assets/screenshot-$lang-$theme.png"
    screencapture -l "$(cat "$out/window.txt")" -o -x "$shot"
    pkill -f "^$BIN" 2>/dev/null || true
    size="$(sips -g pixelWidth -g pixelHeight "$shot" | awk '/pixel/ {print $2}' | paste -sd x -)"
    if [[ "$size" != "1600x1600" ]]; then
      echo "$shot is $size, not 1600x1600" >&2
      exit 1
    fi
    echo "$shot"
  done
done
