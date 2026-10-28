# LOOP.md — 工作循環

> 架構文件 §1、§12、§15、§16 在這個專案的落地版本。
> 適用於所有在這個 repo 寫 code 的 agent。純文件改動（只動 `*.md`）可以跳過 §3–§4，但仍要做 §7。

```text
0 任務卡 ─→ 1 情境 ─→ 2 計畫 ─→ 3 小步實作 ─→ 4 自查（VM）─→ 5 送驗（Mac）
                                        ▲                           │
                                        │                    PASS / PENDING / FAIL / BLOCKED
                                        │                           │
                                        └──── 6 重試階梯 ←── FAIL ──┤
                                                                     ├── PENDING → review／人工驗收 → 再送驗
                                                                     ├── BLOCKED → 7 升級，停下來
                                                                     └── PASS → 8 交付
```

---

## 1. 任務卡

動手前先寫 `harness/task.yaml`（範本：`task.template.yaml`）。沒有任務卡不寫 code。

### 1.1 必填

| 欄位 | 寫什麼 |
|---|---|
| `id` | 里程碑 `M42`、修正 `FIX-xxx`、harness 本身 `H-xxx` |
| `base` | 任務開始時的 commit。之後 diff 都以它為準 |
| `scope` | 允許改的路徑。寫窄一點；發現要改範圍外的檔案時，**先在對話說明原因再擴大**，不要默默加 |
| `required_tests` | 這個任務的驗收測試。新功能一定要有新的或擴充的測試類別列在這裡 |
| `risk` | 見 1.2 |

`approved` 只能寫使用者在對話中明確同意的項目，並在上一行用註解記下日期與原話摘要。

### 1.2 risk: high 的判斷

以下任何一項成立就是 high，需要 review（VERIFY.md V5）：

- 新增或修改 migration、資料庫結構
- 會批次寫入 `organizer_suggestions`、`organizer_analysis` 或人工欄位的程式（D-040 事故的類型）
- 會在使用者的外接碟上建立、搬移、刪除任何東西（整理、硬連結、撤銷）
- 觸及 CLAUDE.md §57 的三條線任何一條
- 改 `policy.yaml`、`limits.yaml`、`harness.py`

---

## 2. 情境（Context）

依序讀，讀到夠用就停。**不要整份讀 AGENTS.md / CLAUDE.md / ROADMAP.md**（各 30–40KB），用 grep 找章節。

```text
1. MEMORY.md                         現況索引（短）
2. docs/HANDOFF.md 最上面一段          上次停在哪、已知問題
3. harness/task.yaml                 這次要做什麼、能改什麼
4. 要改的檔案 + 對應的測試檔            先讀再改（AGENTS.md §44）
5. docs/DECISIONS.md 裡相關的 D-xxx    grep 檔名或功能名
6. harness/KNOWN-FAILURES.md          碰到相關子系統時
```

不確定需求時先問，不要猜（→ §7 升級條件「需求不清」）。

---

## 3. 計畫與小步實作

- 在對話裡用三到五行寫計畫：改哪些檔、為什麼、怎麼驗。
- **每一步 ≤ 8 個程式碼檔、≤ 400 行新增**（`limits.yaml`）。超過會在驗證報告裡出現警告。
  理由：每一輪建置都要佔用使用者正在編曲的那台 Mac（CLAUDE.md §52）。
- 先寫或先改測試，再寫實作。
- 不做範圍外的重構。看到值得改的東西，記進 HANDOFF 的「下一步」。

---

## 4. 自查（Claude 的 VM，秒級）

```bash
python3 harness/harness.py check-diff
```

只檢查 diff 與 policy，不建置。FAIL 就先修，不要把明知會失敗的東西送去 Mac 建置。

---

## 5. 送驗（Mac）

```bash
echo verify.sh > .run-request          # watch.sh 會接手
# 等 runs/LATEST 更新，然後讀：
cat runs/$(cat runs/LATEST)/final.md
```

- watch.sh 沒開（兩分鐘內 `runs/LATEST` 沒變）→ 請使用者開啟，不要改用其他方式繞過。
- 回報時只貼 `final.md` 的判定與失敗項，不整段貼 build log。
- **沒有 run 紀錄就不能說「建置通過」或「測試通過」。**

---

## 6. 重試階梯

FAIL 之後依次數升級做法。次數由 ledger 計算（`final.md` 會寫「第 N 次送驗」），不是 agent 自己數。

| 次數 | 做法 |
|---|---|
| 第 1 次失敗 | 同樣的做法，只讀 `final.md` 的錯誤行修正 |
| 第 2 次失敗 | 擴大情境：讀失敗測試的完整內容、相關 DECISIONS、`KNOWN-FAILURES.md`。**不能用同一招**——同一失敗特徵連續 2 次會直接 BLOCKED |
| 第 3 次失敗 | 寫診斷再動手：在對話列出三個可能原因與各自的驗證方法，先驗證再改。可請 reviewer 協助診斷 |
| 第 4 次失敗 | 縮小範圍：退回上一個 PASS 的狀態（VM 裡用 `git --no-optional-locks show <commit>:<path> > <path>` 逐檔還原；VM 不能跑會寫 index 的 git 指令），把任務拆小 |
| 第 5 次 | 自動 BLOCKED（`max_attempts_per_task`），走 §7 |

禁止的「修法」：刪測試、放寬斷言讓它過、`XCTSkip`、把失敗的程式路徑註解掉、改 `policy.yaml` / `limits.yaml`。
這些要嘛被 V2/V3 擋下，要嘛就是欺騙——兩者都不可以。

---

## 7. 升級（Escalation）

以下情況停止自動循環，向使用者回報：

```text
verify.sh 判定 BLOCKED（同一失敗 2 次、送驗 5 次、碰到 deny）
需求不清，或兩種解讀會做出不同的東西
需要 policy 核准（approval 清單、pattern:*）
需要動到真實資料庫、外接碟、或跑讀音訊的批次（POLICY.md §3）
發現既有規則彼此衝突
```

回報格式（一字不改地使用這四個標題）：

```text
BLOCKED
Reason:                  為什麼停
Required human decision: 需要你決定的具體問題（最好是選擇題）
Current state:           run id、判定、改了哪些檔、目前是否能建置
Suggested next action:   我建議怎麼做、為什麼
```

---

## 8. 交付（Delivery）

只有 **PASS** 可以交付。順序：

1. 更新 `docs/HANDOFF.md`（格式 AGENTS.md §58），寫入 run id 與測試數
2. 有架構或產品取捨 → `docs/DECISIONS.md`
3. 更新 `ROADMAP.md` §0、`MEMORY.md` 的測試基準
4. commit：寫 `.commit-message`、`.commit-paths`，`echo commit.sh > .run-request`。
   commit.sh 會核對指紋；驗證之後又改了程式碼就會被拒，要重新送驗
5. 讀 `docs/commit-output.txt` 確認 HEAD
6. 在對話中回報：做了什麼、run id、測試數、動用了哪些核准、有什麼需要使用者手動確認

打包 DMG（`release.sh`）不在一般交付內，需要使用者明確要求。

---

## 9. 上限一覽（`limits.yaml`）

| 項目 | 值 | 超過時 |
|---|---|---|
| 同一任務送驗次數 | 5 | BLOCKED |
| 同一失敗特徵連續 | 2 | BLOCKED |
| 每步程式碼檔案數 | 8 | 警告 |
| 每步新增行數 | 400 | 警告 |
| build / test 逾時 | 各 900 秒 | 該步驟記為失敗（exit 124） |
| xcodegen 逾時 | 120 秒 | 同上 |

---

## 10. 協作模式

預設 **Single Agent**：Claude 寫、verify.sh 判定。

**Worker → Reviewer**（`risk: high` 必須；其他選用）：

1. Worker 取得 PENDING（V1–V4 都過，只差 review）
2. `python3 harness/harness.py fingerprint` 取得指紋
3. Reviewer（Codex，或另開的 Claude 子代理，不能是寫這份 code 的同一段對話）讀 `runs/<id>/diff.patch`，
   依 `VERIFY.md` §4 的清單審查，寫 `harness/reviews/<任務 id>.md`：

   ```text
   fingerprint: <指紋>
   verdict: approve | changes
   reviewer: codex | claude-subagent
   ---
   發現的問題與結論
   ```

4. `changes` → 回到 §3；`approve` → 再送驗一次，得到 PASS
5. Review 之後又改了程式碼，指紋會不同，review 自動失效

Handoff（換人接手）照 AGENTS.md §46、§58；任務卡與 `runs/` 就是交接的一部分。
