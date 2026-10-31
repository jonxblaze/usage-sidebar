#!/usr/bin/env bash
# Wire this repo's pre-commit hook. Other hooks are left alone.
#   bash scripts/install-hooks.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hooks="$(git -C "$root" rev-parse --git-path hooks)"
mkdir -p "$hooks"

src="$root/scripts/hooks/pre-commit"
dest="$hooks/pre-commit"
cp "$src" "$dest"
chmod +x "$dest" "$root/scripts/bump-release.py"
# commit-msg cannot change this commit's tree. Drop a previous install.
rm -f "$hooks/commit-msg"

echo "Installed $dest"
echo "On commit: patch version + CHANGELOG."
echo "Skip the bump with [skip version] or USAGE_SIDEBAR_SKIP_VERSION=1."
