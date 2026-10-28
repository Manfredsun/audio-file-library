#!/usr/bin/env python3
"""Privacy and release-gate regressions; all mutations stay in temporary folders."""
import importlib.util
import json
import tempfile
import sqlite3
import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("public_audit", ROOT / "scripts/check-public.py")
exporter = load("public_export", ROOT / "scripts/export-public.py")


class PublicExportTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.root = Path(self.work.name)

    def tearDown(self):
        self.work.cleanup()

    def fixture(self):
        for name in ("LICENSE", "THIRD-PARTY-NOTICES.txt", "README.md", "dependencies/Package.resolved"):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("public")

    def test_private_control_file_is_rejected(self):
        self.fixture()
        (self.root / ".commit-message").write_text("private")
        self.assertTrue(any("control" in x for x in audit.audit(self.root)))

    def test_personal_path_is_rejected_without_exposing_value(self):
        self.fixture()
        (self.root / "README.md").write_text("/Users/" + "muffin/private")
        issues = audit.audit(self.root)
        self.assertTrue(any("personal" in x for x in issues))
        self.assertFalse(any("private" in x for x in issues))

    def test_audio_and_database_are_rejected(self):
        self.fixture()
        for name in ("sound.wav", "library.sqlite"):
            (self.root / name).write_text("private")
        self.assertEqual(sum("data/control" in x for x in audit.audit(self.root)), 2)

    def test_diagnostic_reports_are_rejected(self):
        self.fixture()
        (self.root / "docs").mkdir()
        (self.root / "docs/report.txt").write_text("private")
        self.assertTrue(any("diagnostic" in x for x in audit.audit(self.root)))

    def test_export_is_allowlisted_and_does_not_copy_history(self):
        target = self.root / "snapshot"
        exporter.export(target)
        self.assertEqual(audit.audit(target), [])
        self.assertFalse((target / ".git").exists())
        self.assertFalse((target / "docs/library-inspect.txt").exists())
        self.assertFalse((target / "harness/tasks/H-001.yaml").exists())
        self.assertIn("base: HEAD", (target / "harness/task.yaml").read_text())
        self.assertFalse(json.loads((target / "PUBLIC-SOURCE-MANIFEST.json").read_text())["release_ready"])

    def test_export_includes_website_but_not_private_diagnostics(self):
        target = self.root / "website-snapshot"
        exporter.export(target)
        for name in ("website/index.html", "website/zh-hant.html", "website/css/style.css",
                     "website/js/site.js", "website/assets/app-icon.png"):
            self.assertTrue((target / name).is_file(), name)
        self.assertFalse((target / "docs/audio-truth.txt").exists())
        self.assertFalse((target / "docs/library-inspect.txt").exists())
        self.assertEqual(audit.audit(target), [])
        (target / "website/index.html").write_text("tampered")
        self.assertIn("snapshot changed: website/index.html", audit.audit(target))

    def test_pages_deploy_is_manual_only(self):
        workflow = (ROOT / ".github/workflows/pages.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("\n  push:", workflow)
        self.assertNotIn("\n  pull_request:", workflow)

    def test_ci_audits_public_export_instead_of_private_checkout(self):
        workflow = (ROOT / ".github/workflows/verify.yml").read_text()
        self.assertIn('python3 scripts/export-public.py "$RUNNER_TEMP/audio-file-library-public-source"', workflow)
        self.assertIn('python3 scripts/check-public.py "$RUNNER_TEMP/audio-file-library-public-source"', workflow)
        self.assertNotIn("run: python3 scripts/check-public.py .", workflow)
        self.assertIn("bash scripts/verify.sh", workflow)

    def test_export_includes_both_localization_catalogs(self):
        target = self.root / "localized-snapshot"
        exporter.export(target)
        for name in ["Localizable.xcstrings", "InfoPlist.xcstrings"]:
            catalog = json.loads((target / "app/Resources" / name).read_text())
            self.assertEqual(catalog["sourceLanguage"], "en")
            self.assertTrue(all({"en", "zh-Hant"}.issubset(value["localizations"])
                                for value in catalog["strings"].values()))
        self.assertEqual(json.loads((target / "PUBLIC-SOURCE-MANIFEST.json").read_text())["version"], "1.0.2-beta.2")

    def test_export_never_overwrites_an_existing_destination(self):
        with self.assertRaises(ValueError):
            exporter.export(self.root)

    def test_changed_snapshot_is_reported(self):
        target = self.root / "snapshot"
        exporter.export(target)
        (target / "README.md").write_text("tampered")
        self.assertIn("snapshot changed: README.md", audit.audit(target))

    def test_duplicate_preview_is_read_only_and_matches_only_generated_paths(self):
        tool = load("preview_duplicates", ROOT / "scripts/preview-organized-duplicates.py")
        database = self.root / "fixture.sqlite"
        connection = sqlite3.connect(database)
        connection.execute("CREATE TABLE sounds(id INTEGER,library_id INTEGER,relative_path TEXT,display_name TEXT,category_source TEXT,file_identifier TEXT)")
        connection.executemany("INSERT INTO sounds VALUES(?,1,?,NULL,NULL,?)", [
            (1, "kick.wav", "1:2"), (2, "_Organized/Kick.wav", "1:2"),
            (3, "XOrganized/Kick.wav", "1:2")])
        connection.commit()
        connection.close()
        before = hashlib.sha256(database.read_bytes()).hexdigest()
        rows = tool.preview(database)
        self.assertEqual([(r["generated_id"], r["original_id"]) for r in rows], [(2, 1)])
        self.assertEqual(hashlib.sha256(database.read_bytes()).hexdigest(), before)


if __name__ == "__main__":
    unittest.main()
