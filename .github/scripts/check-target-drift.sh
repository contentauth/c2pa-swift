#!/usr/bin/env bash
# Assert that the target list in c2pa-apple-targets.sh still matches the
# *_SUFFIX assignments in the C2PAC framework build phase in
# Library/Library.xcodeproj/project.pbxproj. The two are separate on purpose --
# the build phase picks a suffix per Xcode platform at build time, and the
# shell list is needed by CI without opening the project -- but they name the
# same Rust target triples and must never disagree.
#
# The build phase is a shell script embedded in the pbxproj as one escaped
# string, so the suffixes are read straight out of that string: every
# ARCH_SUFFIX / LIPO_ARCH1_SUFFIX / LIPO_ARCH2_SUFFIX assignment.
#
# Drift is otherwise silent until a release preflight fails or a download 404s
# partway through an Xcode build.
#
# Exit codes:
#   0  the two agree
#   1  they disagree (both lists are printed), or the pbxproj could not be parsed
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
pbxproj="$root/Library/Library.xcodeproj/project.pbxproj"

# shellcheck source=c2pa-apple-targets.sh
. "$(dirname "$0")/c2pa-apple-targets.sh"

[ -f "$pbxproj" ] || { echo "not found: $pbxproj" >&2; exit 1; }

# Inside the pbxproj string each quote is escaped, so an assignment reads
# ARCH_SUFFIX=\"aarch64-apple-ios\". Match those and keep the triple.
from_pbxproj="$(
  grep -oE '(ARCH|LIPO_ARCH[12])_SUFFIX=\\"[^\\]*\\"' "$pbxproj" \
    | sed -E 's/.*=\\"([^\\]*)\\"/\1/' \
    | sort -u
)"

from_script="$(printf '%s\n' "$C2PA_APPLE_TARGETS" | grep . | sort -u)"

if [ -z "$from_pbxproj" ]; then
  echo "could not parse any *_SUFFIX assignments out of the C2PAC build phase in ${pbxproj}" >&2
  echo "(the build phase's shape changed -- this checker needs updating)" >&2
  exit 1
fi

if [ "$from_pbxproj" != "$from_script" ]; then
  echo "Target lists have drifted apart." >&2
  echo >&2
  echo "Library/Library.xcodeproj/project.pbxproj:" >&2
  printf '%s\n' "$from_pbxproj" | sed 's/^/  /' >&2
  echo ".github/scripts/c2pa-apple-targets.sh:" >&2
  printf '%s\n' "$from_script" | sed 's/^/  /' >&2
  echo >&2
  echo "Bring them back in lockstep; both must list the same Rust target triples." >&2
  exit 1
fi

echo "Target lists agree ($(printf '%s\n' "$from_script" | wc -l | tr -d ' ') triples)."
