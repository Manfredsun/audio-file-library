# KNOWN-FAILURES.md — 踩過的坑

> 長期記憶（架構文件 §21）。重試第 2 級必讀（LOOP.md §6）。
> 每一條：症狀 → 原因 → 對策 → 出處。新的坑解決後補在最下面。

## 環境與工具

**VM 裡的 git 留下刪不掉的 `.git/index.lock`**
→ Linux VM 不能刪檔，會寫 index 的 git 指令（一般的 `git status`、`add`、`stash`）會留鎖。
→ VM 只用 `git --no-optional-locks` 的唯讀指令；commit 走 `scripts/commit.sh`。（HANDOFF Session 05）

**建置卡在「Fetching from https://github.com/groue/GRDB.swift」十分鐘以上**
→ 每次建置都去檢查套件更新。
→ 所有 xcodebuild 都加 `-skipPackageUpdates`；verify.sh 另有逾時。（HANDOFF Session 05）

**打開的 app 是舊版**
→ DerivedData 路徑每次不同，Finder／Dock 開到舊的。
→ 用 `scripts/run.sh`，它會複製到固定的 `build/FoleyLibrary.app`；看執行檔時間戳，不看 .app 資料夾的。

**打包出來版本號不對**
→ XcodeGen 產生的 Info.plist 寫死 1.0。
→ `project.yml` 的 info 用 `$(MARKETING_VERSION)`。（打包 1.0.1）

**build.sh 最後的資料庫報表很慢**
→ 原本 find 整個 `~/Library`，卡在 Containers／Caches。
→ 只掃 Application Support 兩層。verify.sh 不做資料庫報表。（HANDOFF Session 04）

## SwiftUI / AppKit

**選單的點擊範圍只有 30×15，padding／frame 無效**
→ macOS 把 SwiftUI `Menu` 的標籤轉成 NSPopUpButton。
→ 一律用 `MenuButton`／`PopUpMenu`（NSMenu）。右鍵 `.contextMenu` 不受影響。（D-041）

**分頁收不到拖放**
→ SwiftUI 的 `dropDestination` 在這個情境收不到。三輪誤判。
→ 放置點改用 AppKit。（D-032）

## 資料與分類

**同一件事被數了兩次，分類被搶走**（犯過三次）
→ 計分單位是資料夾層級，不是命中詞數。具體規則宣告在前。（CLAUDE.md §55、D-022）

**中文詞界比對永遠對不上**
→ CJK 用子字串，其他用詞界；避開單字短詞。（D-023）

**包裝用語被寫進規則表，幾千個檔案一起歸錯**
→ 只收描述聲音本身的詞；`ChineseRuleTests` 會掃。（CLAUDE.md §56）

**路徑重讀把 24,290 筆聲學分類蓋掉**
→ 便宜的 path-only 結果被送進一般 mapper。
→ PathRereadService 只准寫可由字面查核的欄位；批次寫入前 VACUUM 備份並用測試證明 manual／accepted 不變。（D-040、AGENTS.md §61）

**接受建議之後黃點還在**
→ needs_review 沒有在人工決定分類時清掉。（D-043）

**覆蓋率數字變高不代表變好**
→ 47.7% 裡混著廠商名與整句檔名，修正後 42.2%。覆蓋率一定要連樣本一起看。（CLAUDE.md §58）

## AI 能力

**Antigravity 回報「公雞啼叫」**
→ headless 讀不到音訊，而且會流暢地編造。任何答案藏在聲音裡的工作都不交給它。（D-013、D-036）


## 2026-10-27 原生驗證補充

**harness step 在執行任何命令前 TypeError: unhashable type: list**
→ 子指令與 remainder 同用 cmd 欄位。
→ remainder 改為 command；新增真實 subprocess 成功與失敗自測，不改驗收規則。（D-048）

**搬移音色庫後被誤判為路徑不一致**
→ scanner 的 /var 路徑與 manager 書籤的 /private/var 路徑不一致；已搬走的尾段也無法直接 resolve。
→ 共同解析最近仍存在祖先，重建尾段；不可拿掉碰撞或檔案身分檢查。（D-046）

**只安裝 XcodeGen binary 時缺少 base/macOS 等預設設定**
→ 發行 ZIP 的 share/xcodegen/SettingPresets 沒有一起安裝。
→ 固定版安裝器校驗 archive/binary，並保留相對 share 資源結構。

## SwiftUI 空狀態使整個主視窗被裁切（2026-10-27）

EmptyStateView的多行說明若使用 `.fixedSize(horizontal: false, vertical: true)`，原生NavigationSplitView會在窄寬量測時算出1444pt fitting height。即使標頭／篩選列固定高度，空分頁仍會推掉頂部與底部。離屏實際元件probe證明移除該modifier後fitting height為600pt。UIEmptyStateLayoutTests以英文與繁中驗證真實EmptyStateView／原生split view，避免只測替身。GUI另驗1000×650、390pt內容欄的長／短空分頁、零結果與正常列表。證據：run018/019，541/0，指紋038a398109f697f8。
