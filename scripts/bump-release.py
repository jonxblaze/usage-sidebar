#!/usr/bin/env python3
"""Bump Usage Sidebar's version and changelog as part of the commit being made.

Installed as .git/hooks/pre-commit by scripts/install-hooks.sh. The hook edits
Sources/Info.plist and CHANGELOG.md, then stages them so they land in the same
commit. commit-msg is too late: Git has already snapshotted the tree.

The commit subject is read from the parent `git commit -m` command. An editor
commit has no message yet; hand-written Unreleased notes are still promoted,
and an empty Unreleased section becomes "Version bump".

Skip:
  USAGE_SIDEBAR_SKIP_VERSION=1
  a commit message containing [skip version]
  merge commits
  git commit --amend
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

SKIP_RE = re.compile(r"\[skip[- ]version\]", re.I)
PLIST_KEYS = ("CFBundleShortVersionString", "CFBundleVersion")


def repo_root() -> Path:
    out = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()
    return Path(out)


def git_dir() -> Path:
    out = subprocess.check_output(
        ["git", "rev-parse", "--git-path", "."], text=True
    ).strip()
    return Path(out)


def parent_commit_command() -> str:
    try:
        return subprocess.check_output(
            ["ps", "-o", "command=", "-p", str(os.getppid())], text=True
        ).strip()
    except (subprocess.CalledProcessError, OSError):
        return ""


def parse_commit_command(cmd: str) -> tuple[bool, str]:
    """Return (is_amend, subject) from a `ps` rendering of `git commit`.

    `ps` drops shell quotes, so everything after `-m` up to the next flag is
    the message.
    """
    import shlex

    try:
        argv = shlex.split(cmd)
    except ValueError:
        argv = cmd.split()
    amend = "--amend" in argv
    messages: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-m", "--message"):
            i += 1
            parts: list[str] = []
            while i < len(argv) and not argv[i].startswith("-"):
                parts.append(argv[i])
                i += 1
            if parts:
                messages.append(" ".join(parts))
            continue
        if arg in ("-F", "--file") and i + 1 < len(argv):
            path = Path(argv[i + 1])
            if path.is_file():
                for line in path.read_text(errors="replace").splitlines():
                    if line.strip() and not line.startswith("#"):
                        messages.append(line.strip())
                        break
            i += 2
            continue
        i += 1
    subject = messages[0].splitlines()[0].strip()[:200] if messages else ""
    return amend, subject


def bump_semver(version: str) -> str:
    parts = version.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError(f"not a MAJOR.MINOR.PATCH version: {version!r}")
    parts[2] = str(int(parts[2]) + 1)
    return ".".join(parts)


def bump_build(build: str) -> str:
    if not build.isdigit():
        raise ValueError(f"CFBundleVersion is not an integer: {build!r}")
    return str(int(build) + 1)


def replace_plist_string(text: str, key: str, value: str) -> str:
    pattern = rf"(<key>{re.escape(key)}</key>\s*<string>)[^<]*(</string>)"
    new, n = re.subn(pattern, rf"\g<1>{value}\2", text, count=1)
    if n != 1:
        raise ValueError(f"{key} not found in Info.plist")
    return new


def read_plist_string(text: str, key: str) -> str:
    m = re.search(
        rf"<key>{re.escape(key)}</key>\s*<string>([^<]*)</string>", text
    )
    if not m:
        raise ValueError(f"{key} not found in Info.plist")
    return m.group(1)


def promote_changelog(text: str, version: str, day: str, subject: str) -> str:
    """Move ## [Unreleased] notes under the new version.

    An empty Unreleased section becomes one Changed bullet from the commit
    subject. Hand-written Unreleased notes are kept and not duplicated.
    """
    marker = "## [Unreleased]"
    if marker not in text:
        block = (
            f"{marker}\n\n"
            f"---\n\n"
            f"## [{version}] - {day}\n\n"
            f"### Changed\n"
            f"- {subject}\n\n"
        )
        return text.rstrip() + "\n\n" + block

    match = re.search(
        rf"{re.escape(marker)}\n(.*?)(?=\n---\n\n## \[|\n## \[)",
        text,
        re.S,
    )
    if not match:
        raise ValueError("CHANGELOG.md has Unreleased but no following version")
    body = match.group(1)
    has_notes = bool(re.search(r"^\s*[-*]", body, re.M))
    if has_notes:
        released_body = body if body.endswith("\n") else body + "\n"
    else:
        released_body = f"\n### Changed\n- {subject}\n\n"
    replacement = (
        f"{marker}\n\n"
        f"---\n\n"
        f"## [{version}] - {day}\n"
        f"{released_body}"
    )
    return text[: match.start()] + replacement + text[match.end() :]


def stage(root: Path, paths: list[Path]) -> None:
    rels = [str(p.relative_to(root)) for p in paths]
    subprocess.check_call(["git", "add", "--", *rels], cwd=root)


def already_ran(git_path: Path, key: str) -> bool:
    stamp = git_path / "usage-sidebar-bump-stamp"
    now = time.time()
    if stamp.exists():
        try:
            prev, ts = stamp.read_text().split("\n", 1)
            if prev == key and now - float(ts) < 30:
                return True
        except ValueError:
            pass
    stamp.write_text(f"{key}\n{now}\n")
    return False


def run_pre_commit() -> int:
    if os.environ.get("USAGE_SIDEBAR_SKIP_VERSION"):
        return 0
    amend, subject = parse_commit_command(parent_commit_command())
    if amend:
        print("bump-release: amend, leaving the version alone", file=sys.stderr)
        return 0
    git_path = git_dir()
    if (git_path / "MERGE_HEAD").exists():
        print("bump-release: merge, leaving the version alone", file=sys.stderr)
        return 0

    if SKIP_RE.search(subject):
        print("bump-release: [skip version], leaving the version alone", file=sys.stderr)
        return 0
    if not subject:
        subject = "Version bump"
    if already_ran(git_path, subject):
        print("bump-release: already bumped for this message", file=sys.stderr)
        return 0

    root = repo_root()
    plist_path = root / "Sources" / "Info.plist"
    changelog_path = root / "CHANGELOG.md"
    try:
        plist = plist_path.read_text()
        short = bump_semver(read_plist_string(plist, "CFBundleShortVersionString"))
        build = bump_build(read_plist_string(plist, "CFBundleVersion"))
        plist = replace_plist_string(plist, "CFBundleShortVersionString", short)
        plist = replace_plist_string(plist, "CFBundleVersion", build)
        day = time.strftime("%Y-%m-%d")
        changelog = promote_changelog(changelog_path.read_text(), short, day, subject)
        plist_path.write_text(plist)
        changelog_path.write_text(changelog)
        stage(root, [plist_path, changelog_path])
    except Exception:
        stamp = git_path / "usage-sidebar-bump-stamp"
        stamp.unlink(missing_ok=True)
        raise
    print(f"bump-release: {short} ({build})", file=sys.stderr)
    return 0


def self_test() -> int:
    plist = """<key>CFBundleShortVersionString</key>
	<string>1.2.0</string>
	<key>CFBundleVersion</key>
	<string>3</string>
"""
    assert bump_semver("1.2.0") == "1.2.1"
    assert bump_semver("1.9.9") == "1.9.10"
    assert bump_build("3") == "4"
    bumped = replace_plist_string(plist, "CFBundleShortVersionString", "1.2.1")
    bumped = replace_plist_string(bumped, "CFBundleVersion", "4")
    assert read_plist_string(bumped, "CFBundleShortVersionString") == "1.2.1"
    assert read_plist_string(bumped, "CFBundleVersion") == "4"

    notes = """# Changelog

---

## [Unreleased]

### Fixed
- Keep this note.

---

## [1.2.0] - 2026-09-01

### Added
- Old.
"""
    promoted = promote_changelog(notes, "1.2.1", "2026-10-23", "ignored when notes exist")
    assert "## [Unreleased]\n" in promoted
    assert "## [1.2.1] - 2026-10-23\n" in promoted
    assert "- Keep this note." in promoted
    assert "ignored when notes exist" not in promoted
    assert promoted.index("[Unreleased]") < promoted.index("[1.2.1]")
    assert promoted.index("[1.2.1]") < promoted.index("[1.2.0]")

    amend, subj = parse_commit_command(
        "/usr/bin/git commit -q -m feat: keychain prompt"
    )
    assert not amend and subj == "feat: keychain prompt"
    amend, subj = parse_commit_command(
        "/usr/bin/git commit --amend -m chore: redo --no-edit"
    )
    assert amend and subj == "chore: redo"

    empty = """# Changelog

---

## [Unreleased]

---

## [1.2.0] - 2026-09-01
"""
    filled = promote_changelog(empty, "1.2.1", "2026-10-23", "fix: keychain prompt")
    assert "### Changed\n- fix: keychain prompt" in filled
    print("bump-release self-test: ok")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) == 2 and sys.argv[1] == "pre-commit":
        try:
            return run_pre_commit()
        except Exception as exc:
            print(f"bump-release: {exc}", file=sys.stderr)
            return 1
    print("usage: bump-release.py pre-commit | --self-test", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
