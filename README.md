# Audio File Library

原生 macOS 音效與音樂素材庫管理工具。將散落在資料夾與外接硬碟的素材，整合成可以搜尋、預覽、編輯及拖入 Logic Pro 的本機音色庫。

A native macOS sound library manager for searching, previewing and organizing audio, with human-controlled metadata and local analysis. English and Traditional Chinese interfaces are included.

**Search → Preview → Drag**

## Free and open source / 免費開源

Source code is published under the [MIT License](LICENSE). This repository starts with a clean public history; private development diagnostics and previous internal Git history are not included. See the [Changelog](CHANGELOG.md), [Third-party notices](THIRD-PARTY-NOTICES.txt), and [website](website/).

目前版本以**公開預覽版（pre-release）**提供；音訊分類建議未經 30–50 筆真實素材人工抽樣驗收，完整 Logic Pro 拖放／整理撤銷實機驗收亦未完成。自動測試通過唔等於所有真實音效庫環境都已驗證。

## Landing Page 本機預覽同部署

網站係 `website/` 入面嘅靜態 HTML、CSS 同 JavaScript，唔需要 Node.js、npm 或後端。英文入口係 `index.html`，繁中入口係 `zh-hant.html`。

```bash
python3 -m http.server 8000 --directory website
```

開啟 <http://localhost:8000/> 或 <http://localhost:8000/zh-hant.html>。網站部署透過 `.github/workflows/pages.yml` 手動觸發；如 Pages 未啟用，請喺 Repository Settings → Pages 選擇 GitHub Actions。

`.github/workflows/pages.yml` 只支援手動觸發 `workflow_dispatch`；部署 artifact 只包括 `website/`，唔包括其他檔案。GitHub Pages 網站公開可見，版本與下載狀態以 [GitHub Releases](https://github.com/Manfredsun/audio-file-library/releases) 為準。

## 版本與系統需求

目前提供 **1.0.2 上架候選版（rc.1，build 4）**。App 名稱為 **Audio File Library**，需要 **macOS 14 或更新版本**，同一個安裝包支援 **Apple Silicon 與 Intel**。

這是公開預覽版，而非完整驗收的穩定版。發佈前既有候選來源曾通過 541 項自動測試及獨立程式審查，但實際 Logic 拖放、整理／撤銷及 30–50 筆真實素材分類抽樣尚未全部驗收。App 採 ad-hoc 簽章，**未經 Apple 公證**；請先備份 App 資料，首次使用整理功能請以複製素材測試。

## 主要功能

- **搜尋與篩選**：搜尋檔名、顯示名稱、路徑、分類、標籤及備註；搭配收藏、評分、長度、BPM 等篩選條件。
- **音效預覽**：選取或雙擊播放，查看波形、調整音量，使用空白鍵播放／暫停。
- **拖入 Logic Pro**：直接提供原始音檔位置，不產生額外音檔副本。
- **多庫瀏覽**：管理多個資料夾與外接硬碟，依資料夾、分類、風格或材質尋找素材。
- **人工 metadata**：編輯顯示名稱、分類、標籤、風格、材質、評分、收藏與備註。
- **虛擬分頁**：建立、命名與排序素材集合，不搬移原始音檔。
- **本機分析**：利用聲學量測及檔名／路徑證據提出建議，供使用者接受、修改或拒絕；不確定的結果保留待複查。
- **整理與撤銷**：先預覽命名與目的路徑、匯出 CSV，再經確認建立 `_Organized` 硬連結；由整理紀錄撤銷。
- **備份**：支援手動資料庫備份，並在特定批次修改前自動備份；備份失敗時停止該批次動作。
- **外觀與語言**：跟隨系統／淺色／深色；繁體中文／English／跟隨系統，支援中英文內建名稱搜尋。

可索引 WAV、AIFF（AIF／AIFF）、CAF、MP3、M4A 與 FLAC；個別編碼能否預覽仍取決於 macOS 解碼支援及檔案是否完整。

## 安裝

1. 從 [GitHub Releases](https://github.com/Manfredsun/audio-file-library/releases) 下載公開預覽版 `Audio File Library 1.0.2-rc.1.dmg`，核對 SHA-256 校驗碼。
2. 退出正在執行的舊版本，開啟 DMG。
3. 將 **Audio File Library.app** 拖入 **Applications**，再從 Applications 開啟。
4. 若 macOS 阻擋首次開啟，依系統提示前往「系統設定 → 隱私權與安全性」，檢視此 App 的開啟選項。

可在 Terminal 核對下載內容：

```bash
shasum -a 256 "Audio File Library 1.0.2-rc.1.dmg"
```

輸出應與附帶的 `.dmg.sha256` 相同。這個候選包不需要登入帳號，也不需要設定 API Key。

## 第一次使用

1. 按工具列 **＋**，選擇含有音效的資料夾，等待索引完成。
2. 輸入關鍵字，或從側欄選擇資料夾與分類。
3. 選取音效查看波形與資訊，預覽後拖入 Logic Pro。
4. 視需要修改顯示名稱、分類、標籤與備註。
5. 從「分析」選單開啟本機分析與備份功能，逐項檢查建議。

首次測試整理功能時，先使用少量複製素材。分類是輔助建議；「未知」或「待複查」是正常結果。

## 外觀與語言

點擊工具列齒輪或按 **⌘,** 開啟設定。

| 設定 | 選項 | 套用時間 |
|---|---|---|
| 外觀 | 跟隨系統、淺色、深色 | 立即 |
| 介面語言 | 跟隨系統、繁體中文、English | 下次開啟 App |

預設跟隨系統；不支援的介面語言退回英文。切換語言不會強制退出 App，也不會改寫人工名稱、標籤、備註、分頁名稱、既有分析內容或實體檔案路徑。

## 資料與原始音檔

App 完全在本機運作，不上傳音檔、不呼叫生成式模型，也不依賴外部分析服務。資料庫儲存在：

```text
~/Library/Application Support/com.manfredsun.foleylibrary/
```

此 **Audio File Library** 包使用正式版的資料位置；曾使用正式版者會沿用該資料。先前 **Audio File Library Beta** 的獨立資料庫不會自動合併，Beta 的編輯也不會自動轉入本包。更新或移除音色庫前，請先備份重要的 App metadata。

- 修改「顯示名稱」不會重新命名原始音檔。
- 人工 metadata 優先於自動分析，人工清空也是有效決定。
- 分頁只保存素材關聯，不搬移音檔；音色庫離線時保留 metadata。
- 整理須經使用者確認，只建立硬連結；**硬連結不是備份**。其他軟體若原地修改其中一個連結，其餘連結也會讀到變更。
- 撤銷會核對檔案身分；被替換、無法辨識或無法安全處理的檔案會保留並回報。
- 移除音色庫紀錄會移除該庫的 App metadata，原始音檔仍保留。

## 已知限制

- 此候選版尚未完成人工實機流程與代表性分類抽樣；自動測試不能代表分類一定正確。
- 未經 Apple 公證，macOS 首次開啟可能需要額外確認。
- 瀏覽採分頁，尚未提供虛擬捲動及完整的增量資料夾監看。
- 舊版誤匯入的整理連結不會自動刪除；舊 journal 無法證明身分時也會保留檔案。
- 不提供雲端同步、Finder Tags 同步或自動匯入 Beta metadata。

## 從原始碼建置

需要完整 **Xcode**（含 macOS SDK）、**Python 3**、**Git** 與 **XcodeGen 2.46.0**。目前已驗證 Xcode 27.1；僅安裝 Command Line Tools 不足以執行完整驗證。GRDB.swift 固定為 **7.11.1**，鎖定資訊位於 `dependencies/Package.resolved`。

```bash
python3 scripts/install-xcodegen.py
bash scripts/bootstrap-dependencies.sh
bash scripts/verify.sh
```

第一次取得建置工具與相依套件需要網路；App 的日常使用不需要。Xcode 專案由 `project.yml` 產生。正式驗證結果記錄於 `runs/`，測試宿主與正式資料庫隔離。

公開原始碼應使用乾淨快照，保留私人儲存庫與歷史：

```bash
python3 scripts/export-public.py build/public-source-preview
```

目標資料夾必須不存在。公開預覽來源的 manifest 會標示 `release_ready=false`：代表仍未完成完整的穩定版發佈驗收，並不影響依 MIT 授權提供原始碼。

## 回報問題

請描述 App 版本、macOS 版本、重現步驟、預期及實際結果。截圖請遮蔽私人路徑與素材名稱，無須提供完整音色庫或商用音檔。

## 授權

本專案採 [MIT License](LICENSE)。GRDB.swift 等第三方授權資訊見 [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)。公開 Repository 使用經篩選的乾淨來源歷史，不包含原本私人開發歷史或音訊素材。App／網站圖示已由專案內程式產生並核對，第三方依賴與素材聲明見上方文件。
