#!/usr/bin/env bash
set -euo pipefail

TEST_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-versioned-docs.sh"
source "$(dirname "$TEST_SCRIPT")/generate-versioned-docs.sh"
SOURCE_ROOT="$ROOT"

gh() {
  [[ "$1" == api ]] || return 1
  printf '{"tag_name":"%s","draft":false}\n' "${2##*/}"
}

make_docc() {
  local output="$1" relative
  for relative in index.html documentation/c2pa/index.html documentation/c2pa/reader/index.html; do
    mkdir -p "$(dirname "$output/$relative")"
    printf '%s\n' '<html><head></head><body><div id="app"></div></body></html>' > "$output/$relative"
  done
  mkdir -p "$output/data/documentation/c2pa"
  printf '{}\n' > "$output/data/documentation/c2pa/reader.json"
}

case "${1:-}" in
  --build)
    ROOT="$2"
    build_site
    exit
    ;;
  --xcodebuild)
    shift
    [[ -z "${GH_TOKEN+x}" && -z "${GITHUB_TOKEN+x}" ]] || exit 70
    [[ "$#" == 10 && "$1" == docbuild && "$2" == -workspace && "$3" == C2PA.xcworkspace && "$4" == -scheme && "$5" == Library ]] || exit 71
    [[ "$6" == -destination && "$7" == 'generic/platform=iOS Simulator' && "$8" == -derivedDataPath && "${10}" == CODE_SIGNING_ALLOWED=NO ]] || exit 72
    [[ ! -f Library/FAIL_BUILD ]] || exit 73
    products="$9/Build/Products"
    mkdir -p "$products"
    [[ ! -f Library/NO_ARCHIVE ]] || exit 0
    archive="$products/Debug-iphonesimulator/C2PA.doccarchive"
    mkdir -p "$archive"
    if [[ -f Library/MULTIPLE_ARCHIVES ]]; then mkdir -p "$products/Release/C2PA.doccarchive"; fi
    if [[ -f Library/FAIL_RENDER ]]; then touch "$archive/FAIL_RENDER"; fi
    exit
    ;;
  --xcrun)
    shift
    [[ "$#" == 8 && "$1" == docc && "$2" == process-archive && "$3" == transform-for-static-hosting ]] || exit 74
    [[ "$5" == --hosting-base-path && "$7" == --output-path ]] || exit 75
    [[ ! -f "$4/FAIL_RENDER" ]] || exit 76
    mkdir -p "$8"
    [[ ! -f "$4/NO_LANDING" ]] || exit 0
    make_docc "$8"
    printf '%s\n' "$6" > "$8/hosting.txt"
    if [[ -f "$4/BAD_TEMPLATE" ]]; then
      printf '<html><body>No head</body></html>\n' > "$8/documentation/c2pa/index.html"
    fi
    exit
    ;;
esac

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/versioned-docs-tests-XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

expect_failure() {
  if "$@" > "$ROOT/failure.log" 2>&1; then
    cat "$ROOT/failure.log"
    fail "Expected command to fail: $*"
    return 1
  fi
}

configure_root() {
  mkdir -p "$ROOT/docs" "$ROOT/.github/scripts" "$ROOT/docs-output"
  printf '%s\n' '{"versions":["v0.0.15","v0.0.14"]}' > "$ROOT/docs/versions.json"
  cp "$SOURCE_ROOT/.github/scripts/doc-version-selector.js" "$SOURCE_ROOT/.github/scripts/doc-version-selector.css" "$ROOT/.github/scripts/"
  printf 'Existing site\n' > "$ROOT/docs-output/previous.html"
}

mock_tools() {
  mkdir -p "$ROOT/bin"
  printf '#!/usr/bin/env bash\nexec bash %q --xcodebuild "$@"\n' "$TEST_SCRIPT" > "$ROOT/bin/xcodebuild"
  printf '#!/usr/bin/env bash\nexec bash %q --xcrun "$@"\n' "$TEST_SCRIPT" > "$ROOT/bin/xcrun"
  chmod +x "$ROOT/bin/xcodebuild" "$ROOT/bin/xcrun"
  export PATH="$ROOT/bin:$PATH"
}

commit_sources() {
  git -C "$ROOT" add -- .github/scripts/build.sh C2PA.xcworkspace Library
  git -C "$ROOT" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
}

prepare_releases() {
  configure_root
  git -C "$ROOT" init -q
  mkdir -p "$ROOT/C2PA.xcworkspace" "$ROOT/Library/Library.xcodeproj" "$ROOT/Library/Sources"
  printf '<Workspace/>\n' > "$ROOT/C2PA.xcworkspace/contents.xcworkspacedata"
  printf '// project\n' > "$ROOT/Library/Library.xcodeproj/project.pbxproj"
  printf 'public struct Reader {}\n' > "$ROOT/Library/Sources/Reader.swift"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$ROOT/.github/scripts/build.sh"
  chmod +x "$ROOT/.github/scripts/build.sh"
  commit_sources
  git -C "$ROOT" tag v0.0.15
  git -C "$ROOT" tag v0.0.14
  mock_tools
}

test_versions_preserve_order() {
  printf '%s\n' '{"versions":["v0.0.16-beta.1","v0.0.15"]}' > "$ROOT/config.json"
  [[ "$(load_versions "$ROOT/config.json")" == $'v0.0.16-beta.1\nv0.0.15' ]]
}

test_invalid_versions() {
  local config
  for config in '{}' '[]' '{"versions":"v0.0.15"}' '{"versions":[]}' \
    '{"versions":["v0.0.15","v0.0.15"]}' '{"versions":["main"]}' \
    '{"versions":["../../main"]}' '{"versions":["--help"]}' \
    '{"versions":["0.0.15"]}' '{"versions":["v0.0.15\n"]}' \
    '{"versions":[15]}' '{"versions":[null]}' 'not JSON'; do
    printf '%s\n' "$config" > "$ROOT/config.json"
    expect_failure load_versions "$ROOT/config.json"
  done
}

test_published_releases() {
  verify_release v0.0.15
  local response
  for response in '[]' '{"tag_name":"v0.0.15"}' '{"tag_name":"v0.0.15","draft":true}' '{"tag_name":"v0.0.14","draft":false}'; do
    gh() { printf '%s\n' "$response"; }
    expect_failure verify_release v0.0.15
  done
  gh() { return 1; }
  expect_failure verify_release v0.0.15
}

test_export_and_permissions() {
  prepare_releases
  mkdir "$ROOT/stage"
  export_release "$ROOT" v0.0.15 "$ROOT/stage"
  [[ -x "$ROOT/stage/.github/scripts/build.sh" && -f "$ROOT/stage/Library/Sources/Reader.swift" ]]
  expect_failure export_release "$ROOT" v0.0.1 "$ROOT/stage"
}

test_unsafe_sources() {
  prepare_releases
  local name tag=1
  for name in link 'unsafe\name' 'C:escape'; do
    if [[ "$name" == link ]]; then ln -s ../outside "$ROOT/Library/$name"; else touch "$ROOT/Library/$name"; fi
    commit_sources
    git -C "$ROOT" tag "v1.0.$tag"
    mkdir "$ROOT/stage-$tag"
    expect_failure export_release "$ROOT" "v1.0.$tag" "$ROOT/stage-$tag"
    [[ ! -e "$ROOT/stage-$tag/C2PA.xcworkspace" ]]
    rm "$ROOT/Library/$name"
    tag=$((tag + 1))
  done
}

test_missing_sources() {
  prepare_releases
  rm "$ROOT/C2PA.xcworkspace/contents.xcworkspacedata"
  commit_sources
  git -C "$ROOT" tag v1.0.0
  mkdir "$ROOT/stage"
  expect_failure export_release "$ROOT" v1.0.0 "$ROOT/stage"
}

test_build_removes_tokens() {
  prepare_releases
  export GH_TOKEN=fixture-token GITHUB_TOKEN=fixture-token
  build_archive "$ROOT"
  [[ "$BUILT_ARCHIVE" == "$ROOT/.build/DerivedData/Build/Products/Debug-iphonesimulator/C2PA.doccarchive" ]]
  [[ "$GH_TOKEN" == fixture-token && "$GITHUB_TOKEN" == fixture-token ]]
}

test_missing_or_ambiguous_archives() {
  prepare_releases
  touch "$ROOT/Library/NO_ARCHIVE"
  expect_failure build_archive "$ROOT"
  grep -Fq 'found 0' "$ROOT/failure.log"
  rm "$ROOT/Library/NO_ARCHIVE"
  touch "$ROOT/Library/MULTIPLE_ARCHIVES"
  expect_failure build_archive "$ROOT"
  grep -Fq 'found 2' "$ROOT/failure.log"
}

test_render_hosting_paths() {
  configure_root
  mock_tools
  mkdir "$ROOT/archive"
  local prefix output hosting
  for prefix in '' versions/v0.0.15 versions/v0.0.14; do
    output="$ROOT/output/${prefix:-default}"
    hosting="$BASE_PATH${prefix:+/$prefix}"
    render_archive "$ROOT/archive" "$output" v0.0.15 '["v0.0.15","v0.0.14"]' "$prefix"
    [[ "$(cat "$output/hosting.txt")" == "$hosting" ]]
    grep -Fq "src=\"$hosting/doc-version-selector.js\"" "$output/documentation/c2pa/reader/index.html"
    grep -Fq "data-prefix=\"$prefix\"" "$output/documentation/c2pa/index.html"
    grep -Fq 'data-versions="[&quot;v0.0.15&quot;,&quot;v0.0.14&quot;]"' "$output/documentation/c2pa/index.html"
    grep -Fq "content=\"0; url=$hosting/documentation/c2pa/\"" "$output/index.html"
    [[ -f "$output/doc-version-selector.css" && -f "$output/doc-version-selector.js" ]]
    [[ "$(cat "$output/data/documentation/c2pa/reader.json")" == '{}' ]]
  done
}

test_invalid_docc_output() {
  configure_root
  mock_tools
  mkdir "$ROOT/archive"
  touch "$ROOT/archive/NO_LANDING"
  expect_failure render_archive "$ROOT/archive" "$ROOT/missing" v0.0.15 '["v0.0.15"]' ''
  grep -Fq 'landing page' "$ROOT/failure.log"
  rm "$ROOT/archive/NO_LANDING"
  touch "$ROOT/archive/BAD_TEMPLATE"
  expect_failure render_archive "$ROOT/archive" "$ROOT/malformed" v0.0.15 '["v0.0.15"]' ''
  grep -Fq 'closing head element' "$ROOT/failure.log"
}

test_complete_site() {
  prepare_releases
  GH_TOKEN=fixture-token GITHUB_TOKEN=fixture-token bash "$TEST_SCRIPT" --build "$ROOT"
  [[ -f "$ROOT/docs-output/.nojekyll" && ! -e "$ROOT/docs-output/previous.html" ]]
  local prefix
  for prefix in '' versions/v0.0.15 versions/v0.0.14; do
    grep -Fq "data-prefix=\"$prefix\"" "$ROOT/docs-output/$prefix/documentation/c2pa/index.html"
  done
  grep -Fq 'data-version="v0.0.15"' "$ROOT/docs-output/documentation/c2pa/index.html"
  grep -Fq 'data-version="v0.0.14"' "$ROOT/docs-output/versions/v0.0.14/documentation/c2pa/index.html"
  [[ -z "$(find "$ROOT/.build" -name 'versioned-docs-*' -print)" ]]
}

test_failed_build_preserves_site() {
  prepare_releases
  touch "$ROOT/Library/FAIL_BUILD"
  commit_sources
  git -C "$ROOT" tag -f v0.0.14 >/dev/null
  expect_failure bash "$TEST_SCRIPT" --build "$ROOT"
  [[ "$(cat "$ROOT/docs-output/previous.html")" == 'Existing site' ]]
  [[ -z "$(find "$ROOT/.build" -name 'versioned-docs-*' -print)" ]]
}

test_failed_render_preserves_site() {
  prepare_releases
  touch "$ROOT/Library/FAIL_RENDER"
  commit_sources
  git -C "$ROOT" tag -f v0.0.14 >/dev/null
  expect_failure bash "$TEST_SCRIPT" --build "$ROOT"
  [[ "$(cat "$ROOT/docs-output/previous.html")" == 'Existing site' ]]
  [[ -z "$(find "$ROOT/.build" -name 'versioned-docs-*' -print)" ]]
}

test_real_docc_rendering() {
  configure_root
  printf '%s\n' '/// Reads C2PA data.' 'public struct Reader {' '/// Creates a reader.' 'public init() {}' '}' > "$ROOT/Reader.swift"
  mkdir "$ROOT/symbols" "$ROOT/C2PA.docc"
  xcrun swiftc -emit-module -module-name C2PA -emit-module-path "$ROOT/C2PA.swiftmodule" \
    -emit-symbol-graph -emit-symbol-graph-dir "$ROOT/symbols" "$ROOT/Reader.swift"
  printf '# ``C2PA``\n\nA documentation fixture.\n\n## Topics\n\n- ``Reader``\n' > "$ROOT/C2PA.docc/C2PA.md"
  xcrun docc convert "$ROOT/C2PA.docc" --additional-symbol-graph-dir "$ROOT/symbols" \
    --fallback-display-name C2PA --fallback-bundle-identifier org.contentauth.c2pa \
    --fallback-bundle-version 0.0.15 --output-path "$ROOT/C2PA.doccarchive"
  local prefix output
  for prefix in '' versions/v0.0.15; do
    output="$ROOT/${prefix:-default}"
    render_archive "$ROOT/C2PA.doccarchive" "$output" v0.0.15 '["v0.0.15","v0.0.14"]' "$prefix"
    grep -Fq doc-version-selector.js "$output/documentation/c2pa/reader/index.html"
    [[ -f "$output/data/documentation/c2pa/reader.json" ]]
  done
}

tests=(test_versions_preserve_order test_invalid_versions test_published_releases
  test_export_and_permissions test_unsafe_sources test_missing_sources
  test_build_removes_tokens test_missing_or_ambiguous_archives test_render_hosting_paths
  test_invalid_docc_output test_complete_site test_failed_build_preserves_site
  test_failed_render_preserves_site)
if [[ "${RUN_DOCC_INTEGRATION:-0}" == 1 ]]; then tests+=(test_real_docc_rendering); fi
for test in "${tests[@]}"; do
  ROOT="$TEST_ROOT/$test"
  mkdir "$ROOT"
  set +e
  ( set -e; "$test" ) > "$ROOT/test.log" 2>&1
  status=$?
  set -e
  if [[ "$status" != 0 ]]; then
    cat "$ROOT/test.log"
    fail "FAIL: $test"
    exit 1
  fi
  printf 'PASS: %s\n' "$test"
done
printf '%s Bash tests passed.\n' "${#tests[@]}"