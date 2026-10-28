#!/bin/bash
# 打包成可以給別人的 DMG。
#
#   bash scripts/release.sh
#
# 產出：dist/Audio File Library <MARKETING_VERSION>.dmg
# 輸出同時寫到 docs/release-output.txt，不在 Terminal 前面的人（包括 Claude）也看得到。
#
# **沒有 Apple 開發者憑證**，所以只能做 ad-hoc 簽署。
# 別人第一次打開時 macOS 會擋，DMG 裡附了說明怎麼開。

set -e
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/build/tools/bin:$PATH"
# A package must correspond to a verified source fingerprint and the full test baseline.
PYTHONDONTWRITEBYTECODE=1 python3 - <<'GATE'
import importlib.util
spec = importlib.util.spec_from_file_location("release_harness", "harness/harness.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
ok, reason = h.gate(["app/Sources", "project.yml"])
if not ok or not h.ledger() or h.ledger()[-1].get("tests", 0) < 486:
    raise SystemExit("Release blocked: " + (reason if not ok else "test baseline is missing"))
GATE
exec > >(tee "$ROOT/docs/release-output.txt") 2>&1

VERSION="$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')"
APP_NAME="Audio File Library"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "=== 1. 產生專案 ==="
python3 scripts/generate-schemas.py
xcodegen generate

echo
echo "=== 2. Release 建置 ==="
# 全新的 derivedDataPath 裡沒有套件快取，會去 GitHub 重抓 GRDB——2026-09-23 曾經卡住十分鐘以上。
# 改用 Debug 建置已經抓好的那份，並跳過套件更新（版本已釘在 Package.resolved）。
SPM="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/FoleyLibrary-*/SourcePackages 2>/dev/null | head -1)"
SPM_ARGS=()
if [ -n "$SPM" ]; then
  echo "套件快取：$SPM"
  SPM_ARGS=(-clonedSourcePackagesDirPath "$SPM" -skipPackageUpdates)
fi
xcodebuild -project FoleyLibrary.xcodeproj \
           -scheme FoleyLibrary \
           -configuration Release \
           -derivedDataPath "$STAGE/dd" \
           -destination 'platform=macOS' \
           ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' \
           -onlyUsePackageVersionsFromResolvedFile \
           "${SPM_ARGS[@]}" \
           build | tail -5

BUILT="$STAGE/dd/Build/Products/Release/FoleyLibrary.app"
[ -d "$BUILT" ] || { echo "找不到建置產物：$BUILT"; exit 1; }

echo
echo "=== 3. 改成給人看的名字 ==="
mkdir -p "$STAGE/vol"
cp -R "$BUILT" "$STAGE/vol/$APP_NAME.app"

echo
python3 scripts/export-public.py "$STAGE/public-source" --release
cp "$STAGE/public-source/PUBLIC-SOURCE-MANIFEST.json" "$STAGE/vol/$APP_NAME.app/Contents/Resources/"

echo "=== 4. Ad-hoc 簽署 ==="
# 沒有憑證時 ad-hoc 簽署仍然有用：至少 app 內部是完整的，
# 使用者右鍵打開之後就不會每次都再問一次。
codesign --force --deep --sign - "$STAGE/vol/$APP_NAME.app"
codesign --verify --deep --strict "$STAGE/vol/$APP_NAME.app" && echo "簽署驗證通過（ad-hoc）"

echo
echo "=== 5. 放說明與 Applications 捷徑 ==="
ln -s /Applications "$STAGE/vol/Applications"
cp "$ROOT/docs/FIRST-RUN.txt" "$STAGE/vol/第一次打開請先看我.txt"

echo
echo "=== 6. 做 DMG ==="
mkdir -p "$DIST"
DMG="$DIST/$APP_NAME $VERSION-beta.2.dmg"
[ ! -e "$DMG" ] || { echo "Existing release preserved: $DMG"; exit 1; }
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGE/vol" \
               -ov -format UDZO \
               "$DMG" | tail -2

echo
echo "完成 → $DMG"
ls -lh "$DMG"
python3 scripts/check-release.py "$DMG" --version "$VERSION" --build "4"
python3 - "$DMG" <<'CHECKSUM'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
p.with_suffix(p.suffix + ".sha256").write_text(hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n")
CHECKSUM
