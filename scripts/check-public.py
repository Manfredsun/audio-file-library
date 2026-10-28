#!/usr/bin/env python3
"""Audit a prepared public source tree without printing potentially secret values."""
import argparse
import hashlib
import json
import re
from pathlib import Path

FORBIDDEN = {".env", ".commit-message", ".commit-paths", ".run-request", ".build-request"}
DATA_SUFFIXES = {".sqlite", ".sqlite-wal", ".sqlite-shm", ".wav", ".aif", ".aiff", ".mp3", ".flac", ".p12", ".pem", ".key"}
PATTERNS = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    re.compile(rb"sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}"),
    re.compile(rb"AKIA[0-9A-Z]{16}"),
    re.compile(rb"/Users/(?:muffin|manfred)(?:/|\b)|/Volumes/XD[ ]Drive[ ]2"),
    re.compile(rb"[A-Za-z0-9._%+-]+@(?:gmail|icloud|hotmail|outlook)\.com"),
]


def audit(root):
    root = Path(root).resolve()
    errors = []
    for name in ("LICENSE", "THIRD-PARTY-NOTICES.txt", "README.md", "dependencies/Package.resolved"):
        if not (root / name).is_file():
            errors.append("missing required file: " + name)
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(p in {".git", "build", "dist", "runs", "__pycache__"} for p in relative.parts):
            continue
        if path.is_symlink():
            errors.append("unexpected symbolic link: " + str(relative))
            continue
        if not path.is_file():
            continue
        if path.name in FORBIDDEN or path.name.startswith(".env.") or path.suffix.lower() in DATA_SUFFIXES:
            errors.append("private data/control file: " + str(relative))
        if relative.parts[0] == "docs" and path.suffix in {".txt", ".log", ".png"} and path.name != "FIRST-RUN.txt":
            errors.append("local diagnostic output: " + str(relative))
        if any(rx.search(path.read_bytes()) for rx in PATTERNS):
            errors.append("credential or personal data pattern: " + str(relative))
    manifest = root / "PUBLIC-SOURCE-MANIFEST.json"
    if manifest.is_file():
        try:
            for name, expected in json.loads(manifest.read_text())["files"].items():
                path = root / name
                if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                    errors.append("snapshot changed: " + name)
        except (ValueError, KeyError, TypeError):
            errors.append("invalid source manifest")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    issues = audit(args.root)
    print("Public source audit: " + ("FAIL" if issues else "PASS"))
    for issue in issues:
        print("- " + issue)
    raise SystemExit(bool(issues))
