#!/usr/bin/env python3
"""Inspect a DMG read-only. Never launch its application."""
import argparse
import hashlib
import plistlib
import subprocess
import tempfile
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def inspect(image, version="1.0.2", build="4"):
    image = Path(image).resolve()
    run("hdiutil", "verify", str(image))
    with tempfile.TemporaryDirectory(prefix="foley-release-check-") as mount:
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, str(image))
        try:
            app = Path(mount) / "Audio File Library.app"
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != build:
                raise ValueError("The packaged version/build does not match the release.")
            if info.get("LSMinimumSystemVersion") != "14.0":
                raise ValueError("Unexpected minimum macOS version.")
            executable = info["CFBundleExecutable"]
            if Path(executable).name != executable:
                raise ValueError("Invalid executable name.")
            binary = app / "Contents/MacOS" / executable
            architectures = set(run("lipo", "-archs", str(binary)).split())
            if not {"arm64", "x86_64"}.issubset(architectures):
                raise ValueError("Both Apple Silicon and Intel binaries are required.")
            run("codesign", "--verify", "--deep", "--strict", str(app))
            resources = app / "Contents/Resources"
            for name in ("taxonomy.json", "tag-vocabulary.json", "style-vocabulary.json",
                         "texture-vocabulary.json", "organization-result.json", "LICENSE", "THIRD-PARTY-NOTICES.txt"):
                if not (resources / name).is_file():
                    raise ValueError("Missing bundled resource: " + name)
            if not (Path(mount) / "Applications").is_symlink():
                raise ValueError("Missing Applications shortcut.")
            if not (Path(mount) / "第一次打開請先看我.txt").is_file():
                raise ValueError("Missing first-run instructions.")
        finally:
            run("hdiutil", "detach", mount)
    checksum = hashlib.sha256(image.read_bytes()).hexdigest()
    print("Verified DMG: " + image.name)
    print("SHA-256: " + checksum)
    return checksum


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--version", default="1.0.2")
    parser.add_argument("--build", default="4")
    args = parser.parse_args()
    inspect(args.image, args.version, args.build)
