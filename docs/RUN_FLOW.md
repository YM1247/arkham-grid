# Run 流程與程序路線

## 狀態機

`RunStateMachine` 定義 `START → MAP → NODE` 的主流程。節點可進入戰鬥或直接返回地圖；一般戰鬥勝利進入獎勵，失敗進入結算；Boss 勝利直接通關。非法跳轉會被拒絕。

正式狀態為：`START`、`MAP`、`NODE`、`BATTLE`、`REWARD`、`VICTORY`、`DEFEAT`。

## 節點結果

`RunNodeResult` 是節點修改 Run 的唯一預定出口，包含：

- `node_id`、`node_type` 與 completed／failed／skipped outcome。
- 要套用到 RunState 的 `state_changes`。
- 完成後可選擇的 `next_node_ids`。

所有節點結果由此介面套用到 RunState；戰鬥結果先進入獎勵，再以節點結果返回地圖。事件會停留在 `NODE` 狀態顯示選項，選定且支付成功後才產生節點結果。

## 版本化程序路線

`data/map.json` 使用 `schema_version: 1`。固定 10 層路線保留作 fallback；正式 runtime 使用 `generation` 參數與 Run seed 建立 10 層分層 DAG。

演算法參考使用者提供的 Godot 4.5 地圖生成專案：分層節點、距離優先連邊、交叉抑制及雙向可達性驗證。整合版本改用注入式 `RandomNumberGenerator`，並輸出 Arkham Grid 的字串 ID、`next_ids`、節點類型與內容引用格式。

- 同一 seed 生成完全相同的節點、類型、連線與 encounter。
- 一般 runtime 每次新 Run 產生不同的正整數 seed，並在地圖與結算畫面顯示；固定 seed 模式只供除錯與自動測試使用。
- 每個節點至少有前進連線，下一層每個節點至少有來源。
- 多個起點都能抵達唯一 Boss。
- 結構化節點保證事件、商店、菁英、Boss 前免費休息及 Boss。
- 每條完整路徑通過 10 個節點，包含 7 場戰鬥。

第一版節點類型為：`normal_battle`、`elite`、`boss`、`event`、`shop`、`rest`。戰鬥類型的 `content_id` 必須引用存在的 encounter，事件必須引用存在的 event；所有 `next_ids`、起點與 Boss 引用都會在啟動前驗證。

## 多選項事件

`data/events.json` 保存場景描述與多個選項。`EventChoiceResolver` 以純資料預覽、檢查資源並計算絕對結果；`EventChoiceView` 顯示目前資源、選項代價／收益，並禁用無法支付的選項。第一版事件支援 HP、Sanity 與金錢，HP／Sanity 不可支付至 0，回復會受上限限制；Sanity 變化保留 `event:<event_id>:<option_id>` 來源記錄。

## 盤面保存與完整流程

依 `BOARD-003`，棋盤在戰鬥、獎勵、事件、商店及休息之間完整保存。休息只回復玩家 HP／Sanity；開始全新 Run 時才重建程序友善盤面。

地圖 UI 只允許點擊目前可達節點。流程已包含新 Run、地圖選擇、節點、戰鬥、獎勵、Boss 通關、失敗結算及重新開始；舊的 encounter modulo 無限循環已移除。

## 磁碟存檔基礎

`SaveGameService` 已提供單一 Run 自動槽、版本 envelope、同目錄暫存檔、last-known-good 備份、損壞主檔回退與逐版遷移。存檔會先做嚴格結構驗證；既有主檔若無法解析或遷移，服務會拒絕覆寫，以保留人工復原機會。

RunState v5 保存 RunManager 獎勵 RNG 與 Tablet 抽牌 RNG 的當前狀態。RunManager 在新 Run、節點入口、節點完成與結算時自動保存。正式匯出版本啟動時會續接有效存檔；Godot 編輯器執行則依 `run_config.editor_start_fresh` 預設建立新 Run，避免每次測試都停留在上一局。`node_entered` checkpoint 已保存玩家選定的 `current_node_id`，恢復時會重啟同一節點，不能回到地圖改選路線；戰鬥中不另存半套敵人狀態，而是回到該安全入口重啟戰鬥。

進行中 Run 與歷史紀錄分開保存。`run_autosave.json` 維持單一續玩槽及備份；`meta_progress.json` 的 MetaState v2 另保存最近 20 局的勝敗、結束原因、seed、節點／戰鬥進度、剩餘資源與時間戳。舊 MetaState v1 會自動補入空歷史後升級，不需刪除既有 profile。

若主檔的 JSON、結構或內容引用失效，系統會依序嘗試 last-known-good 備份。成功回退後，損壞主檔會隔離成 `.rejected-*`，再由備份修復主槽，使後續自動保存可以繼續且原始壞檔仍可人工檢查。存檔 envelope 也記錄每份內容文件的 schema version，預留未來 content-ID migration 的判斷依據。
