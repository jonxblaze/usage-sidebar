#!/usr/bin/env bash
# Assemble UsageSidebar.app on macOS with swiftc (no Xcode project required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/dist"
APP="${DIST}/UsageSidebar.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
SOURCES=()

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS (found $(uname -s))." >&2
  echo "Copy this folder to the Mac and run: bash scripts/build-app.sh" >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode or Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode Command Line Tools." >&2
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
case "${ARCH}" in
  arm64) TARGET="arm64-apple-macosx14.0" ;;
  x86_64) TARGET="x86_64-apple-macosx14.0" ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

while IFS= read -r file; do
  SOURCES+=("${file}")
done < <(find "${ROOT}/Sources" -name '*.swift' | sort)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
  echo "No Swift sources under ${ROOT}/Sources" >&2
  exit 1
fi

rm -rf "${APP}"
mkdir -p "${MACOS}" "${CONTENTS}/Resources"
cp "${ROOT}/Sources/Info.plist" "${CONTENTS}/Info.plist"
printf 'APPL????' > "${CONTENTS}/PkgInfo"
/usr/bin/plutil -lint "${CONTENTS}/Info.plist" >/dev/null

echo "Compiling ${#SOURCES[@]} Swift files for ${TARGET}"
if ! swiftc \
  -O \
  -parse-as-library \
  -module-name UsageSidebar \
  -target "${TARGET}" \
  -sdk "${SDK}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  -framework ServiceManagement \
  -o "${MACOS}/UsageSidebar" \
  "${SOURCES[@]}"; then
  echo "swiftc failed. Removing incomplete ${APP}" >&2
  rm -rf "${APP}"
  exit 1
fi

chmod +x "${MACOS}/UsageSidebar"
if ! file "${MACOS}/UsageSidebar" | grep -q "Mach-O"; then
  echo "Compiled file is not a Mach-O binary:" >&2
  file "${MACOS}/UsageSidebar" >&2
  rm -rf "${APP}"
  exit 1
fi

# Unsigned + quarantine is what macOS reports as "damaged or incomplete".
xattr -cr "${APP}" 2>/dev/null || true
codesign --force --deep --sign - "${APP}"
xattr -cr "${APP}" 2>/dev/null || true

echo "Built ${APP}"
echo "Run with:  open \"${APP}\""
echo "Login items work more reliably if you copy the app to /Applications first."
