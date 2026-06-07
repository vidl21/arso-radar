#!/usr/bin/env bash
# Build (and optionally run) the Weather Radar app for the Edge 530.
#
#   ./build.sh         # compile WeatherRadar.prg
#   ./build.sh run     # compile, launch the simulator, and load the app
#
set -euo pipefail
cd "$(dirname "$0")"

CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="$(cat "$CIQ/current-sdk.cfg")"
DEVICE="edge530"
OUT="WeatherRadar.prg"

echo "Building $OUT for $DEVICE ..."
"$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -o "$OUT" -y developer_key
echo "OK -> $OUT"

if [[ "${1:-}" == "run" ]]; then
    echo "Starting simulator ..."
    "$SDK/bin/connectiq" >/dev/null 2>&1 &
    sleep 4
    echo "Loading app into simulator ..."
    "$SDK/bin/monkeydo" "$OUT" "$DEVICE"
fi
