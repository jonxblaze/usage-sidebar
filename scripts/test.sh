#!/usr/bin/env bash
# Compile the non-UI sources with Tests/main.swift and run it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc \
  "$root/Sources/Models/Models.swift" \
  "$root/Sources/Support/JSONMap.swift" \
  "$root/Sources/Support/Secrets.swift" \
  "$root/Sources/Providers/AntigravityProvider.swift" \
  "$root/Sources/Providers/ClaudeProvider.swift" \
  "$root/Sources/Providers/CopilotProvider.swift" \
  "$root/Tests/main.swift" \
  -o "$out/tests"
"$out/tests"
