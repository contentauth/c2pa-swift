#!/usr/bin/env python3
"""Build and publish a static DocC site from selected published release tags."""

import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = "/c2pa-swift"
TAG_PATTERN = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?")


def load_versions(filename: Path) -> list[str]:
    config = json.loads(filename.read_text(encoding="utf-8"))
    versions = config.get("versions") if isinstance(config, dict) else None
    if not isinstance(versions, list) or not versions:
        raise ValueError("Documentation versions must be a non-empty list.")
    for tag in versions:
        if not isinstance(tag, str) or not TAG_PATTERN.fullmatch(tag):
            raise ValueError("Documentation versions must be release tags such as v0.0.15.")
    if len(set(versions)) != len(versions):
        raise ValueError("Documentation versions must not contain duplicate tags.")
    return versions


def verify_release(tag: str) -> None:
    result = subprocess.run(
        ["gh", "api", f"repos/contentauth/c2pa-swift/releases/tags/{tag}"],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    release = json.loads(result.stdout)
    if (
        not isinstance(release, dict)
        or release.get("tag_name") != tag
        or release.get("draft") is not False
    ):
        raise ValueError(f"{tag} is not a published GitHub release.")


def export_release(root: Path, tag: str, destination: Path) -> None:
    commit = subprocess.run(
        ["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()
    archive = subprocess.run(
        ["git", "archive", "--format=zip", commit],
        cwd=root, check=True, capture_output=True,
    ).stdout
    with zipfile.ZipFile(io.BytesIO(archive)) as sources:
        for entry in sources.infolist():
            path = PurePosixPath(entry.filename)
            if (
                not path.parts
                or path.is_absolute()
                or ".." in path.parts
                or path.parts[0] == ".git"
                or any("\\" in part or ":" in part for part in path.parts)
                or stat.S_ISLNK(entry.external_attr >> 16)
            ):
                raise ValueError(f"Unsafe source archive in release {tag}.")
            if entry.is_dir():
                continue
            target = destination.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(sources.read(entry))
            if (entry.external_attr >> 16) & 0o111:
                target.chmod(0o755)
    required = [
        destination / "C2PA.xcworkspace/contents.xcworkspacedata",
        destination / "Library/Library.xcodeproj/project.pbxproj",
    ]
    if not all(path.is_file() for path in required) or not list(
        (destination / "Library/Sources").rglob("*.swift")
    ):
        raise ValueError(f"Release {tag} is missing its workspace or Swift API sources.")


def build_archive(stage: Path) -> Path:
    derived = stage / ".build/DerivedData"
    environment = os.environ.copy()
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        environment.pop(name, None)
    subprocess.run(
        [
            "xcodebuild", "docbuild",
            "-workspace", "C2PA.xcworkspace",
            "-scheme", "Library",
            "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(derived),
            "CODE_SIGNING_ALLOWED=NO",
        ],
        cwd=stage, env=environment, check=True,
    )
    archives = [
        path for path in (derived / "Build/Products").rglob("C2PA.doccarchive")
        if path.is_dir()
    ]
    if len(archives) != 1:
        raise RuntimeError(f"Expected one C2PA.doccarchive, found {len(archives)}.")
    return archives[0]


def render_archive(
    archive: Path, output: Path, tag: str, versions: list[str], prefix: str
) -> None:
    hosting = f"{BASE_PATH}/{prefix}" if prefix else BASE_PATH
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "xcrun", "docc", "process-archive", "transform-for-static-hosting",
            str(archive),
            "--hosting-base-path", hosting,
            "--output-path", str(output),
        ],
        check=True,
    )
    if not (output / "documentation/c2pa/index.html").is_file():
        raise RuntimeError(f"DocC did not generate a C2PA landing page for {tag}.")
    additions = (
        f'<link rel="stylesheet" href="{hosting}/doc-version-selector.css">\n'
        f'<script defer src="{hosting}/doc-version-selector.js"'
        f' data-version="{html.escape(tag, quote=True)}"'
        f' data-versions="{html.escape(json.dumps(versions), quote=True)}"'
        f' data-prefix="{html.escape(prefix, quote=True)}"></script>\n'
    )
    for page in output.rglob("*.html"):
        content = page.read_text(encoding="utf-8")
        if "</head>" not in content:
            raise ValueError(f"DocC page has no closing head element: {page}")
        page.write_text(content.replace("</head>", additions + "</head>"), encoding="utf-8")
    for asset in ("doc-version-selector.js", "doc-version-selector.css"):
        shutil.copy2(ROOT / ".github/scripts" / asset, output)
    destination = f"{hosting}/documentation/c2pa/"
    (output / "index.html").write_text(
        '<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">\n'
        f'<meta http-equiv="refresh" content="0; url={destination}">\n'
        f'<link rel="canonical" href="{destination}">\n'
        '<title>C2PA API documentation</title></head><body>\n'
        f'<p>Continue to the <a href="{destination}">C2PA documentation</a>.</p>\n'
        '</body></html>\n',
        encoding="utf-8",
    )


def build_site() -> Path:
    versions = load_versions(ROOT / "docs/versions.json")
    for tag in versions:
        verify_release(tag)
    build = ROOT / ".build"
    build.mkdir(exist_ok=True)
    output = ROOT / "docs-output"
    with tempfile.TemporaryDirectory(prefix="versioned-docs-", dir=build) as temporary:
        workspace = Path(temporary)
        site = workspace / "site"
        default_archive = None
        for tag in versions:
            stage = workspace / tag
            stage.mkdir()
            export_release(ROOT, tag, stage)
            archive = build_archive(stage)
            if tag == versions[0]:
                default_archive = archive
            render_archive(archive, site / "versions" / tag, tag, versions, f"versions/{tag}")
        if default_archive is None:
            raise RuntimeError("No default documentation archive was built.")
        default = workspace / "default"
        render_archive(default_archive, default, versions[0], versions, "")
        shutil.copytree(default, site, dirs_exist_ok=True)
        (site / ".nojekyll").touch()
        if output.exists():
            shutil.rmtree(output)
        shutil.move(str(site), str(output))
    return output


if __name__ == "__main__":
    print(f"Versioned DocC documentation generated at: {build_site()}")
