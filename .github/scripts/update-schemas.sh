#!/usr/bin/env bash
#
# Regenerates the c2pa-rs JSON schemas the schema conformance tests check the
# Swift models against (Library/Tests/Resources/*.schema.json).
#
# The schemas come from the c2pa-rs release named by C2PA_VERSION in
# Configurations/Base.xcconfig. Run this after changing that version, then fix
# what SettingsSchemaConformanceTests and ManifestSchemaConformanceTests report.
#
# Environment:
#   C2PA_RS_DIR  An existing c2pa-rs checkout to use instead of cloning. It must
#                already be at the tag for C2PA_VERSION.
#
# Requires: git, cargo (the Rust toolchain c2pa-rs asks for), python3.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCCONFIG="${REPO_ROOT}/Configurations/Base.xcconfig"
OUTPUT_DIR="${REPO_ROOT}/Library/Tests/Resources"
SCHEMAS=(Builder ManifestDefinition Reader Settings)

VERSION="$(sed -n 's/^C2PA_VERSION[[:space:]]*=[[:space:]]*//p' "${XCCONFIG}" | tr -d '[:space:]')"
if [ -z "${VERSION}" ]; then
    echo "ERROR: C2PA_VERSION not found in ${XCCONFIG}" >&2
    exit 1
fi
TAG="c2pa-${VERSION}"

if [ -n "${C2PA_RS_DIR:-}" ]; then
    CHECKOUT="${C2PA_RS_DIR}"
    # The schemas are stamped with C2PA_VERSION, so they must come from it.
    if ! git -C "${CHECKOUT}" tag --points-at HEAD | grep -qxF "${TAG}"; then
        echo "ERROR: ${CHECKOUT} is not at ${TAG}" >&2
        exit 1
    fi
    echo "Using the c2pa-rs checkout at ${CHECKOUT}"
else
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "${WORK_DIR}"' EXIT
    CHECKOUT="${WORK_DIR}/c2pa-rs"
    echo "Cloning c2pa-rs at ${TAG}..."
    git clone --quiet --depth 1 --branch "${TAG}" https://github.com/contentauth/c2pa-rs.git "${CHECKOUT}"
fi

echo "Exporting schemas from c2pa-rs ${VERSION}..."
(cd "${CHECKOUT}" && cargo run --quiet -p export_schema --no-default-features --features rust_native_crypto)

for name in "${SCHEMAS[@]}"; do
    source_file="${CHECKOUT}/target/schema/${name}.schema.json"
    if [ ! -f "${source_file}" ]; then
        echo "ERROR: c2pa-rs did not export ${name}.schema.json" >&2
        exit 1
    fi
    # c2pa-rs gives instance_id a freshly generated default each time, so an
    # unchanged schema would otherwise differ on every run.
    python3 - "${source_file}" "${OUTPUT_DIR}/${name}.schema.json" "${VERSION}" <<'PYTHON'
import json
import sys

source, destination, version = sys.argv[1:4]
FIXED_INSTANCE_ID = "xmp.iid:00000000-0000-0000-0000-000000000000"


def fix_instance_id(node):
    if isinstance(node, dict):
        instance_id = node.get("properties", {}).get("instance_id")
        if isinstance(instance_id, dict) and "default" in instance_id:
            instance_id["default"] = FIXED_INSTANCE_ID
        for value in node.values():
            fix_instance_id(value)
    elif isinstance(node, list):
        for value in node:
            fix_instance_id(value)


with open(source, encoding="utf-8") as handle:
    schema = json.load(handle)
fix_instance_id(schema)

comment = f"Generated from c2pa-rs {version} by make update-schemas."
ordered = {}
for key, value in schema.items():
    if key == "$comment":
        continue
    ordered[key] = value
    if key == "$schema":
        ordered["$comment"] = comment
ordered.setdefault("$comment", comment)

with open(destination, "w", encoding="utf-8") as handle:
    json.dump(ordered, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PYTHON
    echo "  Wrote Library/Tests/Resources/${name}.schema.json"
done

echo "Schemas updated to c2pa-rs ${VERSION}."
