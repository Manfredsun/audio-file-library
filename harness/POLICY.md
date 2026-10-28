# POLICY.md — Agent 可以做什麼

> 架構文件 §17、§23 的落地版本。機器能檢查的部分在 `policy.yaml`（由 `harness.py check-diff` 執行），
> 機器檢查不到的部分寫在這裡，由 agent 自律、由使用者在交付時確認。

---

## 1. 檔案（機器檢查：V3）

| 層級 | 路徑 | 說明 |
|---|---|---|
| deny | `*.sqlite*`、音檔（`*.wav` 等）、`.env*`、`secrets/`、`FoleyLibrary.xcodeproj/`、`app/Info.plist` | 資料與產生物，不該出現在 agent 的 diff |
| approval | `Database/Migrations.swift`、`AppDatabase.swift`、`DatabaseBackup.swift`、`OrganizeJournal.swift` | 資料庫結構與備份 |
| approval | `Organizer/OrganizeExecutor.swift`、`PathRereadService.swift`、`OrganizerResultMapper.swift`、`FileSystem/FileActions.swift` | 會寫檔案系統、或會批次改建議狀態的地方（D-015、D-040） |
| approval | `project.yml`、`scripts/release.sh`、`watch.sh`、`commit.sh`、`verify.sh` | 建置、打包、harness 自身 |
| approval | `harness/harness.py`、`policy.yaml`、`limits.yaml`、`AGENTS.md`、`CLAUDE.md` | 規則本身。Agent 不能自己放寬自己的規則 |
| scope | `task.yaml` 列出的路徑 | 其他一律視為範圍外 |
| always | `docs/*.md`、`MEMORY.md`、`ROADMAP.md`、`README.md`、任務卡、reviews、`KNOWN-FAILURES.md` | 交接與紀錄 |

程式碼內容的檢查（新增行）：

| pattern | 為什麼需要核准 |
|---|---|
| `file-remove` `file-move` `file-trash` `file-replace` `file-attributes` | 原檔不改名、不搬移、不刪除（AGENTS.md §9、CLAUDE.md §57 第 1 條） |
| `network` | app 完全不連網（AGENTS.md §13） |
| `finder-tags` | Finder Tags 不在範圍內（AGENTS.md §12） |
| `raw-sql-write` | 批次寫入走 repository 與交易，D-040 事故就是批次寫入 |
| 腳本 `db-write` | 探測腳本一律 `sqlite3 "file:$DB?mode=ro"` |
| 腳本 `external-volume` `recursive-delete` `audio-batch` | 使用者邊編曲邊用這台電腦，碰外接碟或讀音訊的批次不能隨便跑 |
| 腳本 `network` | 同上，且建置已經因為連 GitHub 卡過十分鐘 |

## 2. 指令

Claude 能執行的只有兩處：

| 環境 | 能做 | 不能做 |
|---|---|---|
| Linux VM（`device_bash`） | 讀寫專案檔、grep、`python3`、`git --no-optional-locks` 的唯讀指令、`harness.py check-diff` 與自測 | 刪檔（系統禁止）；會寫 index 的 git 指令（會留下刪不掉的 `index.lock`）；swift／xcodebuild（沒有） |
| Mac（`watch.sh`） | 只能跑 `scripts/*.sh`（watch.sh 只接受 basename，擋掉 `../`） | 任意指令。要新的能力就寫一支新腳本，而新腳本會經過 V3 的腳本 pattern 檢查 |

## 3. 外部資源（機器檢查不到，agent 自律）

| 資源 | 層級 | 規則 |
|---|---|---|
| 真實資料庫（`~/Library/Application Support/com.manfredsun.foleylibrary/library.sqlite`） | 唯讀 auto；寫入 manual | 探測腳本只能 `mode=ro`。任何會寫的操作都要使用者在 app 裡自己按，或明確同意後先做 VACUUM 備份（AGENTS.md §61） |
| 音色庫外接碟（`/Volumes/Example SSD`） | manual | 不讀、不寫。整理（硬連結）由使用者在 app 裡執行 |
| 讀音訊的批次（全庫分析、重讀） | manual | 會吃 CPU，使用者正在編曲。要跑之前先問 |
| 網路 | deny | 建置用 `-skipPackageUpdates`，不連 GitHub |
| `dist/`、DMG、`release.sh` | manual | 只在使用者要求打包時 |
| 啟動 app（`run.sh`） | auto | 可以，但先說一聲；會關掉正在跑的舊版本 |
| commit | auto（經閘門） | 走 `commit.sh`；不 push、不改寫歷史、不 `--amend` |

## 4. 核准層級（架構文件 §23）

| 動作 | 層級 |
|---|---|
| 讀檔、搜尋、`check-diff`、harness 自測 | auto |
| 在 scope 內改程式與測試 | auto |
| 送驗（build + test） | auto |
| 唯讀探測真實資料庫 | auto |
| commit（PASS 且指紋相符） | auto |
| approval 清單的檔案、`pattern:*` | approval（使用者在對話中同意 → 寫進 `approved`） |
| migration、批次寫入邏輯、檔案系統寫入邏輯 | approval + review（`risk: high`） |
| 寫真實資料庫、碰外接碟、讀音訊批次、打包、改 harness 規則 | manual（使用者自己執行或逐次明確同意） |
| deny 清單 | 不可以 |

## 5. 核准怎麼記

```yaml
approved:
  # 2026-09-25 使用者：「可以，v13 migration 加索引」
  - app/Sources/Database/Migrations.swift
```

核准只對這一張任務卡有效。開新任務時 `approved` 清空。
