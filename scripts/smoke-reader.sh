#!/usr/bin/env bash
# Runs a scripted reader session on an EPUB with a built Aomidori.app and collects its output.
#
#   APP=build/Aomidori.app scripts/smoke-reader.sh output-folder book.epub
#
# The app measures the first spine item (the cover) at three window sizes and three modes,
# checks the per-chapter position memory and the chapter-edge toast, and writes snapshots plus
# report.json (see ReaderSmokeTest). Reading positions are kept in the output folder; settings
# and the window frame are not changed. No Screen Recording permission is needed. The app is started as a
# separate instance in the background (`open -g -n`): another running Aomidori is left alone
# and nothing is brought to the front.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"
EPUB="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

BIN="$APP/Contents/MacOS/Aomidori"
pkill -f "^$BIN" 2>/dev/null && sleep 1 || true
rm -f "$OUT"/*.png "$OUT/report.json"
open -g -n -a "$APP" "$EPUB" --args -AomidoriReaderSmoke "$OUT"
for _ in {1..120}; do
  [[ -s "$OUT/report.json" ]] && break
  sleep 0.5
done
pkill -f "^$BIN" 2>/dev/null || true
if [[ ! -s "$OUT/report.json" ]]; then
  echo "No report written; is Aomidori running?" >&2
  exit 1
fi
cat "$OUT/report.json"
