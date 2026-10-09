#!/usr/bin/env bash
# Opens an EPUB with a built Aomidori.app and saves snapshots of the rendered chapter.
#
#   APP=build/Aomidori.app scripts/smoke.sh book.epub [snapshot.png]
#
# The app writes the snapshots itself (`-AomidoriSnapshotPath`), so no Screen Recording
# permission is needed. The app is started as a separate instance in the background
# (`open -g -n`); another running Aomidori is left alone.
set -euo pipefail

cd "$(dirname "$0")/.."
EPUB="$1"
OUT="$(cd "$(dirname "${2:-build/smoke.png}")" && pwd)/$(basename "${2:-build/smoke.png}")"
APP="$(cd "$(dirname "${APP:-build/Aomidori.app}")" && pwd)/$(basename "${APP:-build/Aomidori.app}")"

pkill -f "^$APP/Contents/MacOS/Aomidori" 2>/dev/null && sleep 1 || true
rm -f "$OUT" "${OUT%.png}.window.png" "${OUT%.png}"-*.png
open -g -n -a "$APP" "$EPUB" --args -AomidoriSnapshotPath "$OUT"
for _ in {1..30}; do
  [[ -s "$OUT" ]] && break
  sleep 0.5
done
if [[ ! -s "$OUT" ]]; then
  echo "No snapshot written; is Aomidori running?" >&2
  exit 1
fi
sleep 0.5
echo "Saved $OUT"
