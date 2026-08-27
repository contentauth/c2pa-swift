#!/usr/bin/env bash
# Resolve the c2pa-rs release version a tracking branch should pin to.
#
# Reads a GitHub releases JSON array on stdin.
#
# Usage:
#   resolve-c2pa-version.sh --mode stable
#   resolve-c2pa-version.sh --mode rc --stable vX.Y.Z
#
# Exit codes:
#   0  resolved; a v-prefixed version (e.g. v0.91.0-rc.2) on stdout -- built
#      from the matching c2pa-v* tag, not printed verbatim as its suffix
#   3  nothing to track -- the idle-train no-op; stdout empty
#   1  usage or input error

set -euo pipefail

usage() {
  echo "usage: $0 --mode stable|rc [--stable vX.Y.Z]" >&2
  exit 1
}

mode=""
stable=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      case "${2:-}" in
        ''|--*) echo "--mode requires a value" >&2; usage ;;
      esac
      mode="$2"; shift 2 ;;
    --stable)
      case "${2:-}" in
        ''|--*) echo "--stable requires a value" >&2; usage ;;
      esac
      stable="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

case "$mode" in
  stable) ;;
  rc)
    [ -n "$stable" ] || { echo "--mode rc requires --stable" >&2; exit 1; }
    if ! printf '%s\n' "$stable" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "--stable value '$stable' is not shaped like vX.Y.Z" >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac

# Read stdin exactly once so it can be validated before anything downstream
# (jq, awk) sees it. A CI-scheduled fetch that failed outright must not be
# silently indistinguishable from "checked and there is nothing to track".
raw_input="$(cat)"

if [ -z "$(printf '%s' "$raw_input" | tr -d '[:space:]')" ]; then
  echo "no input: stdin was empty (did the release fetch fail?)" >&2
  exit 1
fi

# `if !` keeps a jq failure (bad JSON, or valid JSON that isn't an array) from
# tripping set -e with jq's own exit status -- it is checked as a condition,
# not run as a bare statement, so the failure is ours to handle below.
if ! printf '%s' "$raw_input" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "invalid input: stdin is not a JSON array (likely a GitHub API error response, e.g. a rate-limit body, rather than a releases list)" >&2
  exit 1
fi

# Consider only the c2pa-v* tag family. Per c2pa-rs docs/release-process.md it
# is library-release.yml, triggered on c2pa-v* tags, that builds the Apple
# binaries our Xcode build phase downloads -- so this tag family, and not
# c2pa-c-ffi-v*, is the authoritative "do binaries exist" signal.
#
# Selection is by tag SHAPE rather than the .prerelease flag, so a mis-flagged
# upstream release cannot put a release candidate on the stable branch.
# Drafts are excluded: they carry no downloadable assets.
tags="$(printf '%s' "$raw_input" | jq -r '.[] | select(.draft != true) | .tag_name' | sed -n 's/^c2pa-v//p')"

case "$mode" in
  stable) pattern='^[0-9]+\.[0-9]+\.[0-9]+$' ;;
  rc)     pattern='^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$' ;;
esac

# grep exits 1 for "no match" (normal -- falls through to the "nothing to
# track" exit 3 below) and >1 for a real tooling/regex error, which must not
# be swallowed into the same "nothing to track" outcome.
candidates="$(printf '%s\n' "$tags" | grep -E "$pattern")" || {
  grep_status=$?
  if [ "$grep_status" -gt 1 ]; then
    echo "grep failed while selecting candidate tags (exit $grep_status)" >&2
    exit 1
  fi
  candidates=""
}

[ -n "$candidates" ] || exit 3

# Order by a zero-padded numeric key rather than `sort -V`, whose prerelease
# handling is not semver-correct (it sorts 0.91.0 BEFORE 0.91.0-rc.1) and
# differs between GNU and BSD userlands. Stable and RC candidates are never
# mixed in one sort, so the two key spaces stay independent.
#
# In rc mode, --stable acts as a floor: only candidates whose BASE version
# exceeds the current stable release are eligible.
best="$(printf '%s\n' "$candidates" | awk -F'[.-]' -v stable="${stable#v}" '
  BEGIN {
    if (stable != "") {
      split(stable, s, ".")
      floor_key = sprintf("%05d%05d%05d", s[1], s[2], s[3])
    }
  }
  {
    base = sprintf("%05d%05d%05d", $1, $2, $3)
    if (floor_key != "" && base <= floor_key) next
    rc = ($4 == "rc") ? $5 : 0
    printf "%s%05d\t%s\n", base, rc, $0
  }
' | sort | tail -1 | cut -f2)"

[ -n "$best" ] || exit 3

echo "v$best"
