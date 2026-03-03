#!/bin/sh
# Usage: sh scripts/bump_version.sh <new-version>
# Updates version in all source files, commits, and tags.
set -euo pipefail

if [ "${1-}" = "" ]; then
  echo "Usage: $0 <version>  (e.g. 0.2.0)" >&2
  exit 1
fi

NEW="$1"

# Validate semver-ish: digits and dots only
case "$NEW" in
  *[!0-9.]* | '') echo "Usage: $0 <version>  (e.g. 0.2.0)" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Detect current version from release.sh
OLD=$(grep '^VERSION=' "$ROOT/scripts/release.sh" | head -1 | sed 's/VERSION="\(.*\)"/\1/')

if [ "$OLD" = "$NEW" ]; then
  echo "Already at $NEW — nothing to do." >&2
  exit 0
fi

echo "Bumping $OLD → $NEW"

sed -i '' "s/^VERSION=\"$OLD\"/VERSION=\"$NEW\"/" "$ROOT/scripts/release.sh"

sed -i '' "s/private let appVersion = \"$OLD\"/private let appVersion = \"$NEW\"/" "$ROOT/Sources/mdv/App.swift"

PLIST="$ROOT/mdv.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" "$PLIST"

sed -i '' "s/^- Version: \`$OLD\`/- Version: \`$NEW\`/" "$ROOT/RELEASE.md"

echo "Updated. Verify with: git diff"
echo ""
echo "To commit and tag:"
echo "  git add -A && git commit -m \"Bump version to $NEW\" && git tag v$NEW"
