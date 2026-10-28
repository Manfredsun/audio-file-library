# Coding Harness

> 版本 H-001（2026-09-24）。依使用者提供的《Agent Harness Architecture v1.0》，
> 針對這個專案的實際限制落地。

這個資料夾規定 **agent 在這個 repo 寫 code 的工作方式**，並用腳本檢查它有沒有照做。
它不是另一個 AI app，也不跑模型；迴圈的「大腦」仍是對話中的 agent（目前是 Claude），
harness 負責的是：**看什麼、能改什麼、試幾次、怎樣算完成、失敗怎麼辦、留下什麼紀錄**。

三條核心原則（架構文件 §2）在這裡的具體意思：

| 原則 | 在這個專案 |
|---|---|
| Harness owns the loop | 迴圈步驟與上限寫在 `LOOP.md`、`limits.yaml`；送驗次數、同一失敗重複次數由 `harness.py` 從帳本算，不由 agent 自己數 |
| Completion must be verified | 只有 `scripts/verify.sh` 的判定算數。Agent 說「好了」不算；沒跑過建置就不能說跑過 |
| Instructions are not enforcement | `policy.yaml` 的規則由 `harness.py check-diff` 對 git diff 實際檢查；`scripts/commit.sh` 在 commit 前核對驗證指紋 |

---

## 檔案

```text
harness/
├── README.md            本文件：總覽、對照表、階段
├── LOOP.md              工作循環：任務卡 → 情境 → 計畫 → 小步實作 → 送驗 → 重試／升級 → 交付
├── VERIFY.md            成功標準：V1–V6 與四種判定
├── POLICY.md            可以做什麼：檔案、指令、外部資源、核准層級
├── KNOWN-FAILURES.md    長期記憶：踩過的坑與對策（重試第 2 級必讀）
├── policy.yaml          機器可讀的 policy（改它需要使用者核准）
├── limits.yaml          機器可讀的上限（改它需要使用者核准）
├── task.yaml            目前的任務卡
├── task.template.yaml   任務卡範本
├── reviews/             risk: high 任務的 review 紀錄（<任務 id>.md）
├── harness.py           驗證器本體（只用 python 標準函式庫）
└── tests/               harness 自己的測試（evals）

scripts/verify.sh        送驗入口（Mac 上跑）
scripts/commit.sh        commit，前面加了驗證閘門
runs/<id>/               每次送驗的紀錄（不入版控）
runs/ledger.jsonl        所有 run 的帳本（不入版控）
```

---

## 架構文件 → 這個專案的對照

| 架構層 | 這裡的實作 | 備註 |
|---|---|---|
| Runner / Loop Engine | 對話中的 agent 依 `LOOP.md` 執行；`verify.sh` 是每一輪的「Observe + Validate」 | Claude 在 Linux VM，**不能跑 xcodebuild**，建置一律透過 `watch.sh` 在 Mac 上跑 |
| Context | `LOOP.md` §2 的讀取順序與預算 | 不把 30KB 的 AGENTS.md 整份塞進來，用 grep 找章節 |
| Planner | 任務卡 `task.yaml` + 對話中的計畫 | 不另設 planner agent |
| Worker | Claude（lead，2026-09-23 起） | |
| Reviewer | 選用。`risk: high` 時必須（V5） | Codex、或另開的 Claude 子代理 |
| Judge / Race | 不做 | 見下方「階段」 |
| Tool / Environment | `device_bash`（VM，讀寫檔）、`watch.sh`（Mac，建置與腳本） | 單一工作樹；需要平行時才用 git worktree（AGENTS.md §45） |
| Policy | `policy.yaml` + `harness.py check-diff` + commit 閘門 | 外部資源（真實資料庫、音色庫外接碟）見 `POLICY.md` §3 |
| Validation | `VERIFY.md` V1–V6 | |
| State / Events / Ledger | `runs/<id>/state.json`、`events.jsonl`、`runs/ledger.jsonl` | |
| Memory | 工作記憶＝對話；Run 記憶＝`runs/`；長期記憶＝`MEMORY.md`、`docs/HANDOFF.md`、`docs/DECISIONS.md`、`KNOWN-FAILURES.md` | 不做 vector DB |
| Delivery | commit（經閘門）＋ HANDOFF；`release.sh` 需核准 | `auto_apply` 等同 false：交付永遠要 PASS |
| Human-in-the-loop | `POLICY.md` §4 的三級：auto / approval / manual | |
| Evaluation | `harness/tests/test_harness.py`（30 項，驗 harness 本身擋得住該擋的） | |
| Metrics | `python3 harness/harness.py metrics` | |

### 刻意不照抄的部分

- **不寫 Python runner 去呼叫模型**。這個專案只有一個主要 agent，且它沒辦法在自己的環境建置；
  自建 runner 會多一層要維護的東西，卻換不到更多保證。真正需要強制的只有「驗證」與「交付」兩個關口，
  這兩處都已經由腳本把關。
- **不做 `models.yaml` / adapter**。等真的需要 Codex 自動審查或 race 時再加（Phase 3–4）。
- **沒有 `config/` 資料夾**。設定只有兩個檔，放在 `harness/` 旁邊比較好找。

### 誠實的限制

Agent 與 harness 共用同一個檔案系統：agent 技術上可以改 `task.yaml` 的 `approved` 或 `policy.yaml`。
這套機制擋的是**失誤與偷懶**（改到範圍外、刪測試、手改產生物、沒驗證就 commit），
不是擋一個蓄意繞過的 agent。對後者的防線是：
`policy.yaml`、`limits.yaml`、`harness.py`、`verify.sh`、`commit.sh` 本身都列在 approval，
每次動用核准都會出現在 `final.md` 的「動用的核准」與 commit 的 diff 裡，使用者看得到。

---

## 快速使用

```bash
# Claude（Linux VM）：送驗前先自查，秒級、不耗 Mac CPU
python3 harness/harness.py check-diff

# 送驗（Mac 上執行；Claude 用 watch.sh 觸發）
echo verify.sh > .run-request
cat runs/$(cat runs/LATEST)/final.md

# 指標
python3 harness/harness.py metrics
```

---

## 階段（對應架構文件 §27–§31）

| 階段 | 內容 | 狀態 |
|---|---|---|
| MVH | LOOP / VERIFY / 驗證器 / state / 紀錄 | ✅ H-001 |
| Phase 2 | Policy engine、structured events | ✅ H-001（policy 只管 diff 與腳本內容；指令層見 POLICY.md §2） |
| Phase 2 | Git worktree | ⏸ 需要平行開發時再做 |
| Phase 3 | Reviewer、重試階梯、人工升級 | ✅ 規範；reviewer 為選用，`risk: high` 必須 |
| Phase 4 | Race / Best-of-N / Arbitration | ✗ 目前不需要 |
| Phase 5 | Evals、Metrics | ✅ 基本版（harness 自測、ledger 指標） |
| Phase 5 | Dashboard、Plugin、MCP | ✗ |
