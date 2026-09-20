#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
POOLSIDE_SDK="${POOLSIDE_SDK:-$(xcrun --show-sdk-path)}"
swiftc -sdk "$POOLSIDE_SDK" -parse-as-library -swift-version 6 Sources/Poolside/Models.swift Validation/Check.swift -o .build/check
.build/check Sources/Poolside/Resources/sample.json
