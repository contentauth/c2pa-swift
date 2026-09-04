#!/usr/bin/env bash
# Assert that a c2pa-rs release carries every per-target archive the C2PAC
# framework build phase downloads. Reads one GitHub release JSON object
# on stdin.
#
# Usage: check-c2pa-assets.sh vX.Y.Z[-rc.N]
#
# Exit codes:
#   0  all present
#   4  release is well-formed but missing one or more required archives;
#      the missing names are listed on stderr
#   1  usage or input error

set -euo pipefail

version="${1:-}"
[ -n "$version" ] || { echo "usage: $0 vX.Y.Z[-rc.N]" >&2; exit 1; }

# The seven required Apple targets live in c2pa-apple-targets.sh, shared with
# build-c2pa-archives.sh so the preflight and the self-built path cannot
# drift from each other or from the pbxproj build phase.
# shellcheck source=c2pa-apple-targets.sh
. "$(dirname "$0")/c2pa-apple-targets.sh"

# Read stdin exactly once so it can be validated before jq sees it. A
# CI-scheduled fetch that failed outright (rate-limited, or a proxy's HTML
# error page) must not be silently indistinguishable from a well-formed
# release that just happens to be missing archives (exit 4).
raw_input="$(cat)"

if [ -z "$(printf '%s' "$raw_input" | tr -d '[:space:]')" ]; then
  echo "no input: stdin was empty (did the release fetch fail?)" >&2
  exit 1
fi

# `if !` keeps a jq failure (invalid JSON, or valid JSON that isn't a release
# object with an assets array) from tripping set -e with jq's own exit
# status -- it is checked as a condition, not run as a bare statement, so the
# failure is ours to handle below. A release with no `assets` key at all, or
# a non-array `assets`, is rejected here too rather than left to crash the
# `jq -r '.assets[].name'` extraction below.
if ! printf '%s' "$raw_input" | jq -e 'type == "object" and (.assets | type) == "array"' >/dev/null 2>&1; then
  echo "invalid input: stdin is not a release object with an assets array (likely a GitHub API error response, e.g. a rate-limit body or an HTML error page, rather than a release)" >&2
  exit 1
fi

assets="$(printf '%s' "$raw_input" | jq -r '.assets[].name')"

missing=""
for target in $C2PA_APPLE_TARGETS; do
  expected="c2pa-${version}-${target}.zip"
  if ! printf '%s\n' "$assets" | grep -Fxq "$expected"; then
    missing="${missing}  ${expected}
"
  fi
done

if [ -n "$missing" ]; then
  echo "Missing required release assets for ${version}:" >&2
  printf '%s' "$missing" >&2
  exit 4
fi

count="$(printf '%s\n' "$C2PA_APPLE_TARGETS" | grep -c .)"
echo "All ${count} required target archives present for ${version}."
