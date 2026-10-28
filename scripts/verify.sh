#!/bin/bash
# Harness 驗證器（harness/VERIFY.md）。Agent 不能自己宣告完成，由這支腳本判定。
#
# Claude 觸發：echo verify.sh > .run-request   （watch.sh 要開著）
# 手動：       bash ~/Desktop/Antigravity/"Local Library Manager"/scripts/verify.sh
#
# 流程：
#   0. harness 自己的測試（policy 引擎壞了，後面的判定都不可信）
#   1. V3 Diff / Policy —— 失敗就不建置，省下編曲中這台機器的 CPU
#   2. 產生白名單 → xcodegen → build → test（每步有逾時，見 harness/limits.yaml）
#   3. 判定：PASS / PENDING / FAIL / BLOCKED
#
# 結果：runs/<id>/final.md（給人讀）、validation.json、events.jsonl、diff.patch、build.log
#       runs/LATEST 是最近一次的 id；runs/ledger.jsonl 是所有 run 的帳本。都不入版控。

set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
export PATH="$ROOT/build/tools/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1
H="python3 harness/harness.py"

RUN="$($H new-run)" || { echo "無法建立 run（harness/task.yaml 有問題？）"; exit 1; }
echo "Run：$RUN"

echo "=== 0. harness 自測 ==="
if ! python3 harness/tests/test_harness.py > "$RUN/harness-selftest.log" 2>&1; then
  echo "harness 自己的測試沒過，停止。見 $RUN/harness-selftest.log"
  $H event "$RUN" run_failed '{"reason":"harness selftest failed"}'
  exit 1
fi
if ! python3 scripts/tests/test_public_export.py > "$RUN/public-selftest.log" 2>&1; then
  echo "公開來源檢查自測未通過，停止。見 $RUN/public-selftest.log"
  $H event "$RUN" run_failed '{"reason":"public source selftest failed"}'
  exit 1
fi
echo "通過"

echo "=== 1. Diff / Policy ==="
if ! $H check-diff --run "$RUN"; then
  $H evaluate "$RUN" --skip-build
  echo "詳細：$RUN/final.md"
  exit 1
fi

echo "=== 2. 建置與測試 ==="

XB=(xcodebuild -project FoleyLibrary.xcodeproj -scheme FoleyLibrary -configuration Debug
    -destination 'platform=macOS' -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile)
$H event "$RUN" validation_started '{"layer":"build+test"}'
$H step "$RUN" toolchain -- bash scripts/bootstrap-dependencies.sh --check-tools &&
$H step "$RUN" generate -- python3 scripts/generate-schemas.py &&
$H step "$RUN" xcodegen -- xcodegen generate &&
$H step "$RUN" build -- "${XB[@]}" build &&
$H step "$RUN" test -- "${XB[@]}" test
echo "（步驟耗時見 $RUN/steps.json）"

echo "=== 3. 判定 ==="
$H evaluate "$RUN"
RC=$?
echo "詳細：$RUN/final.md"
exit $RC
