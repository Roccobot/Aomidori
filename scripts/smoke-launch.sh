#!/usr/bin/env bash
# Launches a built Aomidori.app with no book and checks the empty window (see LaunchSmokeTest).
#
#   APP=build/Aomidori.app scripts/smoke-launch.sh output-folder book.epub
#
# The book is only handed to the session, not opened at launch. Reading state is kept in the
# output folder and window frames are not remembered; settings are not changed. The app is
# started as a separate instance in the background (`open -g -n`); another running Aomidori is
# left alone.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"
EPUB="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

BIN="$APP/Contents/MacOS/Aomidori"
pkill -f "^$BIN" 2>/dev/null && sleep 1 || true
rm -f "$OUT"/*.png "$OUT/report.json" "$OUT/progress.log"
open -g -n -a "$APP" --args -AomidoriLaunchSmoke "$OUT" -AomidoriLaunchSmokeBook "$EPUB"
for _ in {1..60}; do
  [[ -s "$OUT/report.json" ]] && break
  sleep 0.5
done
pkill -f "^$BIN" 2>/dev/null || true
if [[ ! -s "$OUT/report.json" ]]; then
  echo "No report written; is Aomidori running?" >&2
  exit 1
fi
cat "$OUT/report.json"
