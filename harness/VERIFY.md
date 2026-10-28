# VERIFY.md — 成功標準

> 架構文件 §2.2、§14、§22 的落地版本。完成與否由 `scripts/verify.sh` 判定，不由 agent 宣告。

---

## 1. 檢查項目

| 代號 | 名稱 | 通過條件 | 誰檢查 |
|---|---|---|---|
| V0 | Harness 自測 | `harness/tests/test_harness.py` 全過。沒過就不往下跑——policy 引擎壞了，後面的判定都不可信 | verify.sh |
| V1 | 建置 | 白名單產生、xcodegen、`xcodebuild build` 都成功，出現 `** BUILD SUCCEEDED **`，沒有逾時 | harness.py evaluate |
| V2 | 測試 | `** TEST SUCCEEDED **`、0 failures；**測試數不得少於上一次 PASS**（2026-09-23 基準 486） | 同上 |
| V2w | 編譯警告 | 警告數多於上一次 PASS → 警告（不擋） | 同上 |
| V3 | Diff / Policy | 見 §2。失敗就不建置 | harness.py check-diff |
| V4 | 任務驗收測試 | `task.yaml` 的 `required_tests` 每一項都出現在 log 裡並且 passed（沒跑到也算失敗） | evaluate |
| V5 | Review | 只在 `risk: high`：`harness/reviews/<id>.md` 存在、`verdict: approve`、fingerprint 等於目前改動 | evaluate |
| V6 | 人工驗收 | `manual_checks` 每一項都改成 `[x] …`（由使用者確認後才能改） | evaluate |

## 2. V3 的規則（`policy.yaml`）

以 `task.yaml` 的 `base` 為基準，檢查所有改動（含未追蹤的新檔）：

| 規則 | 失敗條件 |
|---|---|
| deny | 改動命中 deny 清單（資料庫檔、音檔、`.env`、產生出來的 xcodeproj／Info.plist）。**沒有核准管道**，而且直接 BLOCKED |
| approval | 改動命中 approval 清單，但 `task.yaml` 的 `approved` 沒列 |
| scope | 改動不在 `scope`，也不在 `always_allowed`（文件、交接） |
| tests | 刪了 `app/Tests/` 的檔案，或 `func test…` 總數變少（`allow_test_removal: true` 除外） |
| generated | `organizer/schemas/*.json` 被改，但 `organizer/references/*.md` 與產生器都沒改——不准手改產生物（ROADMAP §36） |
| swift patterns | Swift 新增行出現刪檔／搬檔／改屬性／網路／Finder Tags／原生 SQL 寫入 → 需核准 `pattern:<名稱>` |
| script patterns | `scripts/` 新增行出現 `sudo`、`rm -rf /` → 直接失敗；出現非唯讀 sqlite3 寫入、`/Volumes/`、`rm -r`、`curl`、讀音訊的工具 → 需核准 |

## 3. 判定

| 判定 | 條件 | 可以做什麼 |
|---|---|---|
| **PASS** | 沒有 FAIL，也沒有 PENDING | 交付（LOOP.md §8） |
| **PENDING** | V1–V4 通過，但 V5 或 V6 未完成 | 找 reviewer／請使用者確認，然後再送驗 |
| **FAIL** | 任何一項 FAIL | 依 LOOP.md §6 重試 |
| **BLOCKED** | FAIL 且觸發升級：同一失敗特徵連續 `max_same_failure` 次、送驗達 `max_attempts_per_task` 次、或命中 deny | 停止，依 LOOP.md §7 回報使用者 |

「失敗特徵」＝ V3 錯誤種類 + 失敗的測試名稱 + 前三行編譯錯誤 + 逾時步驟，取雜湊。
換了寫法但錯在同一個地方，特徵就一樣。

## 4. Reviewer 清單（V5）

Reviewer 讀 `runs/<id>/diff.patch` 與任務卡，逐項回答：

```text
[ ] 需求：做的是任務卡寫的事，沒有多做
[ ] 三條線（CLAUDE.md §57）：原檔不動、AI 不寫人工欄位、手動放的東西不被重排
[ ] Provenance：manual > accepted > suggested 的優先序沒被繞過（AGENTS.md §7–§8）
[ ] 批次寫入：有 VACUUM 備份、有證明 manual／accepted 不變的測試（AGENTS.md §61）
[ ] Migration：只增不毀、有 migration 測試、舊資料能升級
[ ] 主執行緒：沒有在 SwiftUI view 裡做 DB、檔案系統、音訊解碼
[ ] 失敗處理：一個壞檔不會讓整批停下（AGENTS.md §43）
[ ] 測試：斷言有意義，不是為了讓它過而寫
```

## 5. 交付閘門

`scripts/commit.sh` 在 `git add` 之前執行 `harness.py gate`：

- `.commit-paths` 只有文件（`*.md`、`docs/`、任務卡、review）→ 放行
- 有程式碼 → ledger 最後一筆必須是 **PASS**，而且它的指紋等於目前工作樹（相對 HEAD）的程式碼指紋
- 驗證後又改了任何程式碼 → 拒絕，重新送驗

指紋只算程式碼，不算文件，所以 PASS 之後更新 HANDOFF、DECISIONS 不需要重跑。

## 6. 驗證紀錄

```text
runs/
├── LATEST                   最近一次的 run id
├── ledger.jsonl             每次 run 一行：任務、判定、第幾次、指紋、測試數、警告數、失敗項
└── 2026-09-24-001/
    ├── state.json           status / attempt / current_agent / last_validation
    ├── task.yaml            送驗當下的任務卡副本
    ├── events.jsonl         run_started / tool_call / tool_result / validation_* / run_completed|run_failed
    ├── steps.json           每個步驟的 exit code、秒數、是否逾時
    ├── diff-check.json      V3 的完整結果
    ├── diff.patch           相對 base 的 diff
    ├── build.log            完整建置與測試輸出
    ├── harness-selftest.log
    ├── validation.json      全部檢查結果（機器讀）
    └── final.md             給人讀的摘要與下一步
```

`runs/` 不入版控。要保存的結論寫進 HANDOFF（run id + 判定 + 測試數）。

## 7. 不算驗證的東西

- Agent 說「應該可以了」「我檢查過了」
- 只跑了 `check-diff`（它只看 diff，不建置）
- 跑了 `scripts/build.sh`（會建置測試，但不做 V3–V6、不寫 ledger，commit 閘門不認）
- 使用者手動在 Xcode 按了 Run
