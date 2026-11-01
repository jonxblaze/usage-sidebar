#!/usr/bin/env bash
# Draw the app icon and rebuild Sources/Resources/AppIcon.png and AppIcon.icns.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
set_dir="$out/AppIcon.iconset"
mkdir "$set_dir"

swift "$root/scripts/make-icon.swift" "$out/icon.png"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$out/icon.png" --out "$set_dir/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$out/icon.png" --out "$set_dir/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$set_dir" -o "$root/Sources/Resources/AppIcon.icns"
cp "$set_dir/icon_512x512.png" "$root/Sources/Resources/AppIcon.png"
