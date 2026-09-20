# Shared by build.sh and validate.sh. Prints the newest installed macOS SDK this swiftc accepts.
# Command Line Tools can ship an SDK newer than the compiler supports; probing avoids a manual
# POOLSIDE_SDK override. Set POOLSIDE_SDK to skip probing entirely.
poolside_sdk() {
  if [ -n "${POOLSIDE_SDK:-}" ]; then echo "$POOLSIDE_SDK"; return 0; fi
  local probe candidates sdk cache
  cache="$(dirname "${BASH_SOURCE[0]}")/.build/sdk-path"
  probe="$(mktemp -d)"
  echo 'import SwiftUI' > "$probe/probe.swift"
  poolside_sdk_ok() { swiftc -sdk "$1" -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 -emit-object "$probe/probe.swift" -o "$probe/probe.o" >/dev/null 2>&1; }
  if [ -f "$cache" ] && sdk="$(cat "$cache")" && [ -d "$sdk" ] && poolside_sdk_ok "$sdk"; then
    rm -rf "$probe"; echo "$sdk"; return 0
  fi
  candidates="$(xcrun --show-sdk-path 2>/dev/null || true)"$'\n'"$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -rV)"
  while IFS= read -r sdk; do
    [ -n "$sdk" ] && [ -d "$sdk" ] || continue
    if poolside_sdk_ok "$sdk"; then
      mkdir -p "$(dirname "$cache")"; echo "$sdk" > "$cache"
      rm -rf "$probe"; echo "$sdk"; return 0
    fi
  done <<< "$(printf '%s\n' "$candidates" | awk '!seen[$0]++')"
  rm -rf "$probe"
  echo "No installed macOS SDK is compatible with this swiftc. Set POOLSIDE_SDK to an SDK path." >&2
  return 1
}
