#!/bin/bash
# 由 Claude 透過 watch.sh 觸發的 commit。
#
# Claude 在 Linux VM 裡不能刪檔，所以 git 在 VM 裡留下的 .git/index.lock 刪不掉，
# commit 也就只能在 Mac 這一側做。協定：
#   .commit-message   commit 訊息（整份檔案）
#   .commit-paths     要 stage 的路徑，一行一個（相對 repo 根目錄）
# 結果寫到 docs/commit-output.txt。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
OUT="docs/commit-output.txt"
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  # 只有在沒有任何 git 行程時才清掉遺留的鎖。
  if [ -f .git/index.lock ] && ! pgrep -x git >/dev/null; then
    echo "清除遺留的 .git/index.lock"
    rm -f .git/index.lock
  fi
  if [ ! -f .commit-message ] || [ ! -f .commit-paths ]; then
    echo "缺少 .commit-message 或 .commit-paths，什麼都沒做"
    exit 0
  fi
  # Harness 閘門（harness/VERIFY.md §5）：有程式碼改動時，必須有同一份指紋的 PASS 驗證。
  # 只改文件不受影響。要略過閘門就在 Terminal 自己 commit——那是人的決定，不是 agent 的。
  if ! PYTHONDONTWRITEBYTECODE=1 python3 harness/harness.py gate .commit-paths; then
    echo "沒有 commit。先跑 scripts/verify.sh 並取得 PASS"
    exit 0
  fi
  while IFS= read -r p; do
    [ -n "$p" ] && git add -- "$p"
  done < .commit-paths
  echo "--- staged"
  git diff --cached --stat
  git commit -F .commit-message && rm -f .commit-message .commit-paths
  echo "--- HEAD"
  git log -1 --stat --format='%h %s'
  echo "--- 未追蹤／未 stage（僅供參考）"
  git status --short | head -30
} > "$OUT" 2>&1
cat "$OUT"
