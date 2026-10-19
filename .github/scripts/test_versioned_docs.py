import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

import generate_versioned_docs as docs


VERSIONS = ["v0.0.15", "v0.0.14"]


class VersionedDocsTests(unittest.TestCase):
    def test_versions_preserve_the_default_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "versions.json"
            config.write_text(json.dumps({"versions": VERSIONS}))
            self.assertEqual(docs.load_versions(config), VERSIONS)

    def test_invalid_versions_are_rejected(self):
        invalid = [
            {}, [], {"versions": "v0.0.15"},
            *({"versions": versions} for versions in [
                [], ["v0.0.15", "v0.0.15"], ["main"], ["../../main"],
                ["--help"], ["v0.0.15\n"], [15], [None],
            ]),
        ]
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "versions.json"
            for value in invalid:
                with self.subTest(value=value):
                    config.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        docs.load_versions(config)

    @patch.object(docs.subprocess, "run")
    def test_only_published_matching_releases_are_accepted(self, run):
        run.return_value = Mock(stdout=json.dumps({"tag_name": VERSIONS[0], "draft": False}))
        docs.verify_release(VERSIONS[0])
        run.assert_called_once_with(
            ["gh", "api", f"repos/contentauth/c2pa-swift/releases/tags/{VERSIONS[0]}"],
            check=True, stdout=subprocess.PIPE, text=True,
        )
        for release in [
            [], {"tag_name": VERSIONS[0]}, {"tag_name": VERSIONS[0], "draft": True},
            {"tag_name": VERSIONS[1], "draft": False},
        ]:
            with self.subTest(release=release):
                run.return_value = Mock(stdout=json.dumps(release))
                with self.assertRaises(ValueError):
                    docs.verify_release(VERSIONS[0])
        run.side_effect = subprocess.CalledProcessError(1, ["gh", "api"])
        with self.assertRaises(subprocess.CalledProcessError):
            docs.verify_release(VERSIONS[0])

    def make_archive(self, filename=".github/scripts/build.sh", mode=stat.S_IFREG | 0o755):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("C2PA.xcworkspace/contents.xcworkspacedata", "<Workspace/>")
            archive.writestr("Library/Library.xcodeproj/project.pbxproj", "// project")
            archive.writestr("Library/Sources/Reader.swift", "public struct Reader {}")
            entry = zipfile.ZipInfo(filename)
            entry.external_attr = mode << 16
            archive.writestr(entry, "#!/bin/sh\nexit 0\n")
        return buffer.getvalue()

    @patch.object(docs.subprocess, "run")
    def test_exact_tag_is_exported_and_script_permissions_are_preserved(self, run):
        run.side_effect = [Mock(stdout="a" * 40 + "\n"), Mock(stdout=self.make_archive())]
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            docs.export_release(docs.ROOT, VERSIONS[0], stage)
            script = stage / ".github/scripts/build.sh"
            self.assertTrue(script.stat().st_mode & stat.S_IXUSR)
            self.assertTrue((stage / "Library/Sources/Reader.swift").is_file())
        self.assertEqual(
            run.call_args_list[0].args[0],
            ["git", "rev-parse", "--verify", f"refs/tags/{VERSIONS[0]}^{{commit}}"],
        )
        self.assertEqual(
            run.call_args_list[1].args[0],
            ["git", "archive", "--format=zip", "a" * 40],
        )

    @patch.object(docs.subprocess, "run")
    def test_unsafe_or_incomplete_archives_fail(self, run):
        for filename, mode in [
            ("../escape", stat.S_IFREG), ("/escape", stat.S_IFREG),
            ("Library/..\\escape", stat.S_IFREG), ("C:/escape", stat.S_IFREG),
            (".git/config", stat.S_IFREG), ("link", stat.S_IFLNK),
        ]:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as directory:
                run.side_effect = [
                    Mock(stdout="a" * 40),
                    Mock(stdout=self.make_archive(filename, mode)),
                ]
                with self.assertRaises(ValueError):
                    docs.export_release(docs.ROOT, VERSIONS[0], Path(directory))
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("README.md", "# No workspace")
        run.side_effect = [Mock(stdout="a" * 40), Mock(stdout=buffer.getvalue())]
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "missing its workspace"):
                docs.export_release(docs.ROOT, VERSIONS[0], Path(directory))

    @patch.dict(os.environ, {"GH_TOKEN": "fixture-token", "GITHUB_TOKEN": "fixture-token"})
    @patch.object(docs.subprocess, "run")
    def test_archive_build_uses_an_isolated_generic_destination_without_github_tokens(self, run):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            archive = stage / ".build/DerivedData/Build/Products/Debug-iphonesimulator/C2PA.doccarchive"
            archive.mkdir(parents=True)
            self.assertEqual(docs.build_archive(stage), archive)
            command = run.call_args.args[0]
            self.assertIn("generic/platform=iOS Simulator", command)
            self.assertIn("CODE_SIGNING_ALLOWED=NO", command)
            self.assertEqual(run.call_args.kwargs["cwd"], stage)
            self.assertNotIn("GH_TOKEN", run.call_args.kwargs["env"])
            self.assertNotIn("GITHUB_TOKEN", run.call_args.kwargs["env"])

    @patch.object(docs.subprocess, "run")
    def test_missing_or_ambiguous_archives_fail(self, run):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "found 0"):
                docs.build_archive(stage)
            for configuration in ["Debug", "Release"]:
                (stage / f".build/DerivedData/Build/Products/{configuration}/C2PA.doccarchive").mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, "found 2"):
                docs.build_archive(stage)

    @patch.object(docs.subprocess, "run")
    def test_rendering_injects_assets_and_preserves_hosting_paths(self, run):
        def transform(command, **kwargs):
            output = Path(command[command.index("--output-path") + 1])
            for relative in ["index.html", "documentation/c2pa/index.html", "documentation/c2pa/reader/index.html"]:
                page = output / relative
                page.parent.mkdir(parents=True, exist_ok=True)
                page.write_text("<html><head></head><body><div id=\"app\"></div></body></html>")

        run.side_effect = transform
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for prefix in ["", f"versions/{VERSIONS[0]}"]:
                with self.subTest(prefix=prefix):
                    output = root / (prefix or "default")
                    docs.render_archive(root / "archive", output, VERSIONS[0], VERSIONS, prefix)
                    hosting = f"{docs.BASE_PATH}/{prefix}" if prefix else docs.BASE_PATH
                    self.assertIn(hosting, run.call_args.args[0])
                    for relative in ["documentation/c2pa/index.html", "documentation/c2pa/reader/index.html"]:
                        page = (output / relative).read_text()
                        self.assertIn(f'src="{hosting}/doc-version-selector.js"', page)
                        self.assertIn(f'data-prefix="{prefix}"', page)
                    self.assertIn(
                        f'content="0; url={hosting}/documentation/c2pa/"',
                        (output / "index.html").read_text(),
                    )
                    self.assertTrue((output / "doc-version-selector.js").is_file())
                    self.assertTrue((output / "doc-version-selector.css").is_file())

    @patch.object(docs.subprocess, "run")
    def test_rendering_without_a_landing_page_fails(self, run):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "landing page"):
                docs.render_archive(Path(directory), Path(directory) / "output", VERSIONS[0], VERSIONS, "")

    @patch.object(docs.subprocess, "run")
    def test_malformed_docc_templates_fail_explicitly(self, run):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output"
            landing = output / "documentation/c2pa/index.html"
            landing.parent.mkdir(parents=True)
            landing.write_text("<html><body>No head element</body></html>")
            with self.assertRaisesRegex(ValueError, "closing head element"):
                docs.render_archive(root / "archive", output, VERSIONS[0], VERSIONS, "")

    @patch.object(docs, "verify_release")
    @patch.object(docs, "export_release")
    @patch.object(docs, "build_archive")
    @patch.object(docs, "render_archive")
    def test_site_defaults_failure_preservation_and_cleanup(self, render, build, export, verify):
        build.side_effect = lambda stage: stage / "C2PA.doccarchive"

        def generate(archive, output, tag, versions, prefix):
            output.mkdir(parents=True)
            (output / "index.html").write_text(f"{tag}:{prefix}")

        render.side_effect = generate
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "docs/versions.json").write_text(json.dumps({"versions": VERSIONS}))
            with patch.object(docs, "ROOT", root):
                site = docs.build_site()
                self.assertEqual((site / "index.html").read_text(), f"{VERSIONS[0]}:")
                for tag in VERSIONS:
                    self.assertEqual(
                        (site / "versions" / tag / "index.html").read_text(),
                        f"{tag}:versions/{tag}",
                    )
                self.assertTrue((site / ".nojekyll").is_file())
                self.assertEqual(list((root / ".build").iterdir()), [])
                self.assertEqual(verify.call_count, 2)
                self.assertEqual(export.call_count, 2)
                self.assertEqual(build.call_count, 2)
                self.assertEqual(render.call_count, 3)
                render.side_effect = RuntimeError("DocC rendering failed")
                with self.assertRaisesRegex(RuntimeError, "DocC rendering failed"):
                    docs.build_site()
                self.assertEqual((site / "index.html").read_text(), f"{VERSIONS[0]}:")
                self.assertEqual(list((root / ".build").iterdir()), [])

    @unittest.skipUnless(os.environ.get("RUN_DOCC_INTEGRATION") == "1", "Set RUN_DOCC_INTEGRATION=1 with Xcode selected.")
    def test_real_docc_archive_rendering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Reader.swift"
            source.write_text("/// Reads C2PA data.\npublic struct Reader {\n/// Creates a reader.\npublic init() {}\n}\n")
            symbols = root / "symbols"
            symbols.mkdir()
            subprocess.run(
                ["xcrun", "swiftc", "-emit-module", "-module-name", "C2PA",
                 "-emit-module-path", str(root / "C2PA.swiftmodule"),
                 "-emit-symbol-graph", "-emit-symbol-graph-dir", str(symbols), str(source)],
                check=True,
            )
            catalog = root / "C2PA.docc"
            catalog.mkdir()
            (catalog / "C2PA.md").write_text("# ``C2PA``\n\nA documentation fixture.\n\n## Topics\n\n- ``Reader``\n")
            archive = root / "C2PA.doccarchive"
            subprocess.run(
                ["xcrun", "docc", "convert", str(catalog),
                 "--additional-symbol-graph-dir", str(symbols),
                 "--fallback-display-name", "C2PA",
                 "--fallback-bundle-identifier", "org.contentauth.c2pa",
                 "--fallback-bundle-version", "0.0.15",
                 "--output-path", str(archive)],
                check=True,
            )
            for prefix in ["", f"versions/{VERSIONS[0]}"]:
                output = root / (prefix or "default")
                docs.render_archive(archive, output, VERSIONS[0], VERSIONS, prefix)
                page = output / "documentation/c2pa/reader/index.html"
                self.assertTrue(page.is_file())
                self.assertIn("doc-version-selector.js", page.read_text())
                self.assertTrue((output / "data/documentation/c2pa/reader.json").is_file())


if __name__ == "__main__":
    unittest.main()
