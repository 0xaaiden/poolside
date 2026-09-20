#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
swiftc -sdk "$POOLSIDE_SDK" -parse-as-library -swift-version 6 Sources/Poolside/Models.swift Sources/Poolside/License.swift Validation/Check.swift -o .build/check
.build/check Sources/Poolside/Resources/sample.json Sources/Poolside/Resources/sample-closed.json
