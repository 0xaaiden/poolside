#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
LUMA_SDK="${LUMA_SDK:-$(xcrun --show-sdk-path)}"
swiftc -sdk "$LUMA_SDK" -parse-as-library -swift-version 6 Sources/LumaLP/Models.swift Validation/Check.swift -o .build/check
.build/check Sources/LumaLP/Resources/sample.json
