#!/usr/bin/env python3
"""Prepare an allowlisted source snapshot; never copy private Git history or DMGs."""
import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = ["app/Sources/**/*.swift", "app/Resources/*.xcstrings", "app/Tests/**/*.swift", "app/Resources/AppIcon.icns",
            "organizer/references/*.md", "organizer/schemas/*.json", "harness/*.md",
            "harness/*.py", "harness/*.yaml", "harness/tests/*.py", "harness/reviews/README.md",
            ".github/workflows/*.yml", "dependencies/Package.resolved", "scripts/tests/*.py",
            "website/*.html", "website/css/*.css", "website/js/*.js", "website/assets/*.png"]
FILES = ["README.md", "CHANGELOG.md", "LICENSE", "THIRD-PARTY-NOTICES.txt", "project.yml", ".gitignore",
         "scripts/verify.sh", "scripts/commit.sh", "scripts/generate-schemas.py",
         "scripts/install-xcodegen.py", "scripts/bootstrap-dependencies.sh", "scripts/release.sh", "scripts/check-release.py",
         "scripts/check-public.py", "scripts/export-public.py", "scripts/preview-organized-duplicates.py", "docs/FIRST-RUN.txt",
         "docs/RELEASE-NOTES.md"]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def export(destination, release=False):
    destination = Path(destination).absolute()
    if destination.exists():
        raise ValueError("Destination already exists; choose a new directory.")
    if release:
        harness = load_module("release_harness", ROOT / "harness/harness.py")
        ok, reason = harness.gate(["app/Sources"])
        if not ok:
            raise ValueError("Release gate refused: " + reason)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix="public-source-", dir=destination.parent))
    try:
        paths = {ROOT / name for name in FILES}
        for pattern in PATTERNS:
            paths.update(ROOT.glob(pattern))
        for source in sorted(paths):
            if not source.is_file() or source.is_symlink():
                raise ValueError("Missing or unsafe source: " + str(source.relative_to(ROOT)))
            target = temporary / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        # Public operating documents are maintained separately from private session history.
        for source in (ROOT / "docs/public").glob("*.md"):
            target = temporary / source.name if source.name in {"AGENTS.md", "MEMORY.md", "ROADMAP.md"} else temporary / "docs" / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        shutil.copytree(ROOT / "docs/public", temporary / "docs/public")
        (temporary / "harness/task.yaml").write_text("""id: PUBLIC-VERIFY
title: Verify the published source snapshot
risk: normal
base: HEAD
scope:
  - app/Sources/*
  - app/Tests/*
required_tests:
  - AppEnvironmentTests
  - OrganizeExecutorTests
  - OrganizeJournalTests
  - OrganizerMapperTests
  - LibraryManagerTests
  - LibraryScannerTests
  - PathRereadTests
  - TextureBackfillTests
  - MigrationTests
  - DatabaseBackupTests
approved: []
manual_checks: []
allow_test_removal: false
""")
        hashes = {str(p.relative_to(temporary)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(temporary.rglob("*")) if p.is_file()}
        manifest = {"version": "1.0.2-beta.2", "release_ready": release, "files": hashes}
        (temporary / "PUBLIC-SOURCE-MANIFEST.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        audit = load_module("public_audit", ROOT / "scripts/check-public.py")
        errors = audit.audit(temporary)
        if errors:
            raise ValueError("Public audit refused: " + "; ".join(errors))
        os.rename(temporary, destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--release", action="store_true", help="require the existing harness PASS gate")
    args = parser.parse_args()
    print(export(args.destination, args.release))
