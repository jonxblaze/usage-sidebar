#!/usr/bin/env bash
# Wire this repo's commit hooks without replacing the Hermes post-commit hook.
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

# Wiki entity sync. Prepends its block and leaves any other post-commit body.
if [[ -f "$HOME/wiki/scripts/repo-commit-wiki-sync.py" ]]; then
  python3 "$HOME/wiki/scripts/repo-commit-wiki-sync.py" install --repo "$root"
else
  echo "wiki sync script not found; version bump is installed, wiki update is not" >&2
fi

echo "Installed $dest"
echo "On commit: patch version + CHANGELOG, then wiki entity sync."
echo "Skip the bump with [skip version] or USAGE_SIDEBAR_SKIP_VERSION=1."
