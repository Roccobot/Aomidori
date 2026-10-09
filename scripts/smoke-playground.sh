#!/usr/bin/env bash
# Runs a scripted CSS Playground session with a built Aomidori.app and collects its output.
#
#   APP=build/Aomidori.app scripts/smoke-playground.sh output-folder [book.epub]
#
# The app types into the editor, toggles Night, saves `PlaygroundSmoke.css` to the styles folder
# (and removes it again), optionally previews an EPUB, and writes snapshots plus report.json
# (see PlaygroundSmokeTest). No Screen Recording permission is needed. The app is started as a
# separate instance in the background (`open -g -n`): another running Aomidori is left alone
# and nothing is brought to the front.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"
ARGS=(-AomidoriPlaygroundSmoke "$OUT")
if [[ $# -ge 2 ]]; then
  ARGS+=(-AomidoriPlaygroundEPUB "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")")
fi

BIN="$APP/Contents/MacOS/Aomidori"
pkill -f "^$BIN" 2>/dev/null && sleep 1 || true
rm -f "$OUT"/*.png "$OUT/report.json"
open -g -n -a "$APP" --args "${ARGS[@]}"
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
