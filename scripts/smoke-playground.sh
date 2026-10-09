#!/usr/bin/env bash
# Runs a scripted CSS Playground session with a built Aomidori.app and collects its output.
#
#   APP=build/Aomidori.app scripts/smoke-playground.sh output-folder [book.epub]
#
# The app types into the editor, toggles Night, saves `PlaygroundSmoke.css` to the styles folder
# (and removes it again), optionally previews an EPUB, and writes snapshots plus report.json
# (see PlaygroundSmokeTest). No Screen Recording permission is needed. Any running Aomidori is
# quit first.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"
ARGS=(-AomidoriPlaygroundSmoke "$OUT")
if [[ $# -ge 2 ]]; then
  ARGS+=(-AomidoriPlaygroundEPUB "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")")
fi

pkill -x Aomidori 2>/dev/null && sleep 1 || true
rm -f "$OUT"/*.png "$OUT/report.json"
open -a "$APP" --args "${ARGS[@]}"
for _ in {1..60}; do
  [[ -s "$OUT/report.json" ]] && break
  sleep 0.5
done
pkill -x Aomidori 2>/dev/null || true
if [[ ! -s "$OUT/report.json" ]]; then
  echo "No report written; is Aomidori running?" >&2
  exit 1
fi
cat "$OUT/report.json"
