#!/bin/bash
# Records the scripted Poolside demo from the real app.
#
#   bash Tools/Recording/record-demo.sh [frames-dir]
#
# Builds the app and the recorder, quits any running Poolside, launches the fresh build with
# POOLSIDE_DEMO_FIXTURE pointing at the illustrative fixtures and a made-up wallet in the argument
# defaults domain (nothing is saved to your preferences), streams the panel at 60 fps and native
# Retina resolution while Demo.swift plays its timeline, then relaunches your normal app.
# Output: PNG frames, timings.txt (frame index and host time) and clock.txt (timeline start in host
# time). Tools/Recording/video composites them into docs/poolside-demo.mp4 and the README still.
# Needs Screen Recording permission for the terminal.
set -euo pipefail
cd "$(dirname "$0")/../.."
FRAMES="${1:-.build/recording/frames}"
BUILD=.build/recording
WALLET=0x7a3e5b0c2d914f86ae4d7b1c0f5e6a92d3b8c91f
mkdir -p "$BUILD" "$FRAMES"; rm -f "$FRAMES"/*
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
swiftc -O -sdk "$POOLSIDE_SDK" -target arm64-apple-macosx14.0 Tools/Recording/Recorder.swift -o "$BUILD/recorder"
bash build.sh
# The fixture carries a fresh source timestamp so the header shows no stale marker.
python3 - "$BUILD/fixture.json" <<'PY'
import json, sys, time
d = json.load(open("Tools/Recording/fixture.json"))
for p in d["data"]: p["now_ts"] = int(time.time())
json.dump(d, open(sys.argv[1], "w"))
PY
pkill -x Poolside || true; sleep 1
POOLSIDE_DEMO_FIXTURE="$PWD/$BUILD/fixture.json" POOLSIDE_DEMO_CLOSED="$PWD/Tools/Recording/fixture-closed.json" POOLSIDE_DEMO_CLOCK="$PWD/$FRAMES/clock.txt" \
  ../Poolside.app/Contents/MacOS/Poolside -wallets "(\"$WALLET\")" -wallet "$WALLET" -theme dark -walletLabels '{}' > "$BUILD/app.log" 2>&1 &
"$BUILD/recorder" "$FRAMES" 20 640 540
wait || true
open ../Poolside.app || true
echo "frames in $FRAMES"
