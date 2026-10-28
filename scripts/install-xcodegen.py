#!/usr/bin/env python3
"""Install the pinned build tool locally, with archive and binary hash verification."""
import hashlib
import io
import urllib.request
import zipfile
from pathlib import Path

VERSION = "2.46.0"
ARCHIVE_SHA256 = "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
BINARY_SHA256 = "8774da746668bc18fe74e54cbaf10f2631a1fb05947cd374179aa912f14f99db"


def install():
    target = Path(__file__).resolve().parents[1] / "build/tools/bin/xcodegen"
    settings = target.parent.parent / "share/xcodegen/SettingPresets"
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == BINARY_SHA256 and any(settings.glob("*.yml")):
        return target
    url = "https://github.com/yonaskolb/XcodeGen/releases/download/" + VERSION + "/xcodegen.zip"
    cache = target.parent.parent / ("xcodegen-" + VERSION + ".zip")
    if cache.is_file():
        archive = cache.read_bytes()
    else:
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = response.read(32 * 1024 * 1024)
    if hashlib.sha256(archive).hexdigest() != ARCHIVE_SHA256:
        raise ValueError("XcodeGen archive checksum mismatch; installation stopped.")
    with zipfile.ZipFile(io.BytesIO(archive)) as package:
        names = [name for name in package.namelist() if name.endswith("/bin/xcodegen")]
        if len(names) != 1:
            raise ValueError("Unexpected XcodeGen archive layout.")
        binary = package.read(names[0])
        assets = []
        prefix = "xcodegen/share/xcodegen/"
        for name in package.namelist():
            if name.startswith(prefix) and not name.endswith("/"):
                relative = Path(name[len(prefix):])
                if relative.is_absolute() or ".." in relative.parts:
                    raise ValueError("Unsafe XcodeGen resource path.")
                assets.append((relative, package.read(name)))
    if hashlib.sha256(binary).hexdigest() != BINARY_SHA256:
        raise ValueError("XcodeGen executable checksum mismatch; installation stopped.")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(binary)
    target.chmod(0o755)
    for relative, data in assets:
        resource = target.parent.parent / "share/xcodegen" / relative
        resource.parent.mkdir(parents=True, exist_ok=True)
        resource.write_bytes(data)
    return target


if __name__ == "__main__":
    print(install())
