#!/bin/bash
# Issue and verify Poolside Pro keys. See Tools/LicenseTool.swift for commands.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
if [ ! -x .build/license-tool ] || [ Sources/Poolside/License.swift -nt .build/license-tool ] || [ Tools/LicenseTool.swift -nt .build/license-tool ]; then
  swiftc -sdk "$POOLSIDE_SDK" -parse-as-library -swift-version 6 Sources/Poolside/License.swift Tools/LicenseTool.swift -o .build/license-tool
fi
exec .build/license-tool "$@"
