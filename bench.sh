#!/bin/bash
# Offscreen layout benchmark. Usage: bash bench.sh <positions-envelope.json>
# Save a large wallet's response first, e.g.
#   curl -s 'https://api.revert.finance/v1/positions/account/<0x…>?limit=100&active=true&with-v4=true&with-ekubo=true' > .build/wallet.json
# The app's entry point is stripped so the benchmark can supply its own.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/bench
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
sed 's/^@main struct PoolsideApp/struct PoolsideApp/' Sources/Poolside/App.swift > .build/bench/App.swift
swiftc -O -sdk "$POOLSIDE_SDK" -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 \
  Sources/Poolside/Models.swift Sources/Poolside/License.swift Sources/Poolside/Icons.swift .build/bench/App.swift Sources/Poolside/Views.swift Validation/Bench.swift \
  -o .build/bench/bench
.build/bench/bench "${1:?positions JSON file required}"
