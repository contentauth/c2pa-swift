#!/usr/bin/env bash
# Sourced, never executed. The seven Apple targets whose c2pa-c-ffi archives
# the C2PAC framework build phase consumes, one per line.
#
# Used by check-c2pa-assets.sh (release preflight) and
# build-c2pa-archives.sh (self-built archives for the main tracker). The
# list must match the *_SUFFIX assignments in the C2PAC build phase in
# Library/Library.xcodeproj/project.pbxproj; the two must always change
# together.
# shellcheck disable=SC2034
C2PA_APPLE_TARGETS="
aarch64-apple-ios
x86_64-apple-ios
aarch64-apple-ios-sim
x86_64-apple-ios-macabi
aarch64-apple-ios-macabi
x86_64-apple-darwin
aarch64-apple-darwin
"
