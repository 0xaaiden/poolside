#!/bin/bash
# Records the scripted Poolside demo and writes a Twitter-ready MP4.
#
#   bash Tools/Recording/record-demo.sh [out.mp4] [fps]
#
# Builds the app and the two helper tools, quits any running Poolside, launches the fresh build with
# POOLSIDE_DEMO_FIXTURE pointing at the illustrative fixture and a made-up wallet in the argument
# defaults domain (nothing is saved to your preferences), captures window-only frames of the panel
# while Demo.swift plays its timeline, relaunches your normal app, then composites the frames over
# the Last Light artwork at 1920x1080. Needs Screen Recording permission for the terminal.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:-poolside-demo.mp4}"
FPS="${2:-30}"
WALLET=0x7a3e5b0c2d914f86ae4d7b1c0f5e6a92d3b8c91f
BUILD=.build/recording
mkdir -p "$BUILD/frames"; rm -f "$BUILD"/frames/*
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
swiftc -O -sdk "$POOLSIDE_SDK" -target arm64-apple-macosx14.0 Tools/Recording/Recorder.swift -o "$BUILD/recorder"
swiftc -O -sdk "$POOLSIDE_SDK" -target arm64-apple-macosx14.0 Tools/Recording/Compose.swift -o "$BUILD/compose"
bash build.sh
# The fixture carries a fresh source timestamp so the header shows no stale marker.
python3 - "$BUILD/fixture.json" <<'EOF'
import json, sys, time
d = json.load(open("Tools/Recording/fixture.json"))
for p in d["data"]: p["now_ts"] = int(time.time())
json.dump(d, open(sys.argv[1], "w"))
EOF
pkill -x Poolside || true; sleep 1
POOLSIDE_DEMO_FIXTURE="$PWD/$BUILD/fixture.json" ../Poolside.app/Contents/MacOS/Poolside -wallets "(\"$WALLET\")" -wallet "$WALLET" -theme dark > "$BUILD/app.log" 2>&1 &
"$BUILD/recorder" "$BUILD/frames" "$FPS" 15
wait || true
open ../Poolside.app || true
"$BUILD/compose" "$BUILD/frames" dist/assets/last-light-v2.webp "$OUT" 1920 1080 "$FPS"
