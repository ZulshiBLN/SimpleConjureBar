#!/usr/bin/env bash
# Checks a packaged release before anything is published: the zip holds the
# addon folder alone and complete, and release.json makes WowUp offer it to a
# WoW Forever client. With a tag, the TOC version must be the tag's.
#
# Usage: check-package.sh <zip> <release.json> [<tag>]
set -euo pipefail

zip="$1"
meta="$2"
tag="${3:-}"
addon="SimpleConjureBar"

fail() { echo "PACKAGE CHECK FAILED: $*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$zip" -d "$work"

top=$(ls -A "$work")
[ "$top" = "$addon" ] || fail "the zip's top level holds '$(echo $top)', expected $addon/ alone"
dir="$work/$addon"
toc="$dir/$addon.toc"
[ -f "$toc" ] || fail "no $addon.toc in $addon/"

for file in README.md LICENSE CHANGELOG.md; do
    [ -f "$dir/$file" ] || fail "$file is missing"
done

# Every file the TOC loads
while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    [ -f "$dir/$line" ] || fail "the TOC lists $line, which is not in the zip"
done < "$toc"

# Nothing of the repository's tooling ships
for path in tests .github .luacheckrc .busted .pkgmeta .gitignore .gitattributes .previews .media; do
    [ ! -e "$dir/$path" ] || fail "$path must not ship"
done

field() { grep -m1 -E "^## $1:" "$toc" | sed -E "s/^## $1:[[:space:]]*//" | tr -d '\r[:space:]'; }
interface=$(field Interface)
version=$(field Version)

jq -e --arg file "$(basename "$zip")" --argjson interface "$interface" '
    (.releases | length) == 1
    and .releases[0].filename == $file
    and .releases[0].nolib == false
    and (.releases[0].metadata | length) == 1
    and .releases[0].metadata[0].flavor == "forever"
    and .releases[0].metadata[0].interface == $interface' "$meta" > /dev/null \
    || fail "release.json does not name $(basename "$zip") under flavor forever, interface $interface"

if [ -n "$tag" ]; then
    [ "v$version" = "$tag" ] || fail "the TOC says $version, the tag is $tag"
fi

echo "package check passed: $(basename "$zip"), TOC version $version, interface $interface"
