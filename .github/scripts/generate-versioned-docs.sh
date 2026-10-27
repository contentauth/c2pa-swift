#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE_PATH=/c2pa-swift

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

load_versions() {
  local filename="$1"
  jq -e --arg pattern '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?\z' '
    if type != "object" then false
    elif (.versions | type) != "array" then false
    else .versions | length > 0 and
      all(.[]; if type == "string" then test($pattern) else false end) and
      (length == (unique | length))
    end
  ' "$filename" >/dev/null || { fail "Documentation versions must be unique release tags in a non-empty list."; return 1; }
  jq -r '.versions[]' "$filename"
}

verify_release() {
  local tag="$1" release
  release="$(gh api "repos/contentauth/c2pa-swift/releases/tags/$tag")" || return 1
  printf '%s' "$release" | jq -e --arg tag "$tag" '
    type == "object" and .tag_name == $tag and .draft == false
  ' >/dev/null || { fail "$tag is not a published GitHub release."; return 1; }
}

export_release() {
  local root="$1" tag="$2" destination="$3" commit entry mode path
  commit="$(git -C "$root" rev-parse --verify "refs/tags/$tag^{commit}")" || return 1
  git -C "$root" ls-tree -rz --full-tree "$commit" > "$destination.tree" || return 1
  while IFS= read -r -d '' entry; do
    mode="${entry%% *}"
    path="${entry#*$'\t'}"
    case "$mode" in
      100644|100755) ;;
      *) fail "Unsafe source entry in release $tag: $path"; return 1 ;;
    esac
    case "/$path/" in
      //*|*/../*|*/./*|*/.git/*|*\\*|*:*) fail "Unsafe source path in release $tag: $path"; return 1 ;;
    esac
  done < "$destination.tree"
  git -C "$root" archive --format=tar "$commit" > "$destination.tar" || return 1
  tar -xf "$destination.tar" -C "$destination" || return 1
  local required
  for required in C2PA.xcworkspace/contents.xcworkspacedata Library/Library.xcodeproj/project.pbxproj; do
    [[ -f "$destination/$required" ]] || { fail "Release $tag is missing its workspace or Swift API sources."; return 1; }
  done
  [[ -n "$(find "$destination/Library/Sources" -type f -name '*.swift' -print -quit)" ]] || {
    fail "Release $tag is missing Swift API sources."; return 1;
  }
}

build_archive() {
  local stage="$1" derived archive count=0
  derived="$stage/.build/DerivedData"
  (
    cd "$stage" || exit 1
    unset GH_TOKEN GITHUB_TOKEN
    xcodebuild docbuild -workspace C2PA.xcworkspace -scheme Library \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
      CODE_SIGNING_ALLOWED=NO
  ) || return 1
  [[ -d "$derived/Build/Products" ]] || { fail "Expected one C2PA.doccarchive, found 0."; return 1; }
  find "$derived/Build/Products" -type d -name C2PA.doccarchive -print0 > "$stage/.build/archives"
  while IFS= read -r -d '' archive; do
    BUILT_ARCHIVE="$archive"
    count=$((count + 1))
  done < "$stage/.build/archives"
  [[ "$count" == 1 ]] || { fail "Expected one C2PA.doccarchive, found $count."; return 1; }
}

render_archive() {
  local archive="$1" output="$2" tag="$3" versions="$4" prefix="$5"
  local hosting="$BASE_PATH" page additions escaped_tag escaped_versions escaped_prefix destination
  [[ -z "$prefix" ]] || hosting="$hosting/$prefix"
  mkdir -p "$output"
  xcrun docc process-archive transform-for-static-hosting "$archive" \
    --hosting-base-path "$hosting" --output-path "$output" || return 1
  [[ -f "$output/documentation/c2pa/index.html" ]] || {
    fail "DocC did not generate a C2PA landing page for $tag."; return 1;
  }
  escaped_tag="$(printf '%s' "$tag" | jq -Rr '@html')"
  escaped_versions="$(printf '%s' "$versions" | jq -Rr '@html')"
  escaped_prefix="$(printf '%s' "$prefix" | jq -Rr '@html')"
  additions="<link rel=\"stylesheet\" href=\"$hosting/doc-version-selector.css\">
<script defer src=\"$hosting/doc-version-selector.js\" data-version=\"$escaped_tag\" data-versions=\"$escaped_versions\" data-prefix=\"$escaped_prefix\"></script>"
  find "$output" -type f -name '*.html' -print0 > "$output.pages"
  while IFS= read -r -d '' page; do
    DOC_VERSION_ADDITIONS="$additions" awk '
      BEGIN { additions = ENVIRON["DOC_VERSION_ADDITIONS"] }
      {
        position = index($0, "</head>")
        if (position) {
          head = 1
          printf "%s%s\n%s\n", substr($0, 1, position - 1), additions, substr($0, position)
        } else print
      }
      END { if (!head) exit 1 }
    ' "$page" > "$page.tmp" || { fail "DocC page has no closing head element: $page"; return 1; }
    mv "$page.tmp" "$page"
  done < "$output.pages"
  rm "$output.pages"
  cp "$ROOT/.github/scripts/doc-version-selector.js" "$ROOT/.github/scripts/doc-version-selector.css" "$output/"
  destination="$hosting/documentation/c2pa/"
  printf '%s\n' '<!DOCTYPE html>' '<html lang="en"><head><meta charset="utf-8">' \
    "<meta http-equiv=\"refresh\" content=\"0; url=$destination\">" \
    "<link rel=\"canonical\" href=\"$destination\">" \
    '<title>C2PA API documentation</title></head><body>' \
    "<p>Continue to the <a href=\"$destination\">C2PA documentation</a>.</p>" \
    '</body></html>' > "$output/index.html"
}

build_site() (
  set -euo pipefail
  local versions=() tag versions_json workspace output stage default_archive=""
  mkdir -p "$ROOT/.build"
  output="$ROOT/docs-output"
  workspace="$(mktemp -d "$ROOT/.build/versioned-docs-XXXXXX")"
  trap 'status=$?; if [[ -d "$workspace/previous" && ! -e "$output" ]]; then mv "$workspace/previous" "$output" || status=1; fi; rm -rf -- "$workspace"; exit "$status"' EXIT
  load_versions "$ROOT/docs/versions.json" > "$workspace/versions"
  while IFS= read -r tag; do versions+=("$tag"); done < "$workspace/versions"
  versions_json="$(jq -c '.versions' "$ROOT/docs/versions.json")"
  for tag in "${versions[@]}"; do verify_release "$tag"; done
  for tag in "${versions[@]}"; do
    stage="$workspace/$tag"
    mkdir "$stage"
    export_release "$ROOT" "$tag" "$stage"
    build_archive "$stage"
    [[ "$tag" != "${versions[0]}" ]] || default_archive="$BUILT_ARCHIVE"
    render_archive "$BUILT_ARCHIVE" "$workspace/site/versions/$tag" "$tag" "$versions_json" "versions/$tag"
  done
  render_archive "$default_archive" "$workspace/default" "${versions[0]}" "$versions_json" ""
  cp -R "$workspace/default/." "$workspace/site/"
  touch "$workspace/site/.nojekyll"
  if [[ -e "$output" ]]; then mv "$output" "$workspace/previous"; fi
  mv "$workspace/site" "$output"
  printf 'Versioned DocC documentation generated at: %s\n' "$output"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  build_site
fi