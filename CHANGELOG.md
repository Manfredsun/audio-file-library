# Changelog

## 1.0.2-rc.1 — Public preview (2026-10-29)

- First public, MIT-licensed source snapshot with a clean Git history.
- English and Traditional Chinese landing pages; GitHub Pages deployment is manual-only.
- Public source export audit and CI checks separate from private development diagnostics.
- Preview distribution uses an ad-hoc signature and is not Apple-notarized.
- Real-library classification sampling and complete Logic Pro/organize-undo manual acceptance have **not** been completed; do not treat this preview as a validated stable release.

## Unreleased

- Additional real-device QA, Apple Developer ID signing/notarization and real app screenshots remain future improvements.

## 1.0.2-rc.1 — 2026-10-27（本機候選包）

### 新增

- 跟隨系統／淺色／深色外觀，立即生效。
- 跟隨系統／繁體中文／English 介面，下次開啟套用。
- 內建分類、風格同材質嘅顯示翻譯，以及中英文名稱搜尋。
- 一般設定視窗，可由齒輪或者⌘,開啟。

### 修正

- 整理撤銷核對檔案身分，保留被替換嘅物件，並記錄逐項結果。
- 自動重讀及回填保護人工修改，人工清空亦保留 provenance。
- 音色庫重新連結保留既有紀錄、metadata 同分頁，遇到衝突停止。
- 掃描排除根目錄 `_Organized`，避免重複匯入整理連結。
- 以資料庫 scan ownership 阻止過期掃描覆寫新結果。
- 設定頁 Appearance 標籤保留完整字寬，修正英文折行。
- 修正窄欄、長分頁名稱同空白狀態嘅視窗佈局。

### 驗證及分發

- App 1.0.2，build 4；macOS 14+，Intel／Apple Silicon。
- App 測試由原有 524 項增加至 541 項；完整驗收狀態以對應 run 為準。
- ad-hoc 簽章，未經 Apple 公證；候選包並未放行公開下載。

## 1.0.1 — 2026-09-23（本機歷史版本）

- 人工決定分類之後清除待複查標記。
- 加入側欄分類瀏覽同較大點擊範圍。
- 更新中文介面與開發交接紀錄。

## 1.0 — 2026-09-19（本機歷史版本）

- App 圖示、Release 建置、ad-hoc 簽章同 DMG 打包。
- 資料庫備份、本機分析及路徑重讀等功能；後續安全修正見候選版本。
